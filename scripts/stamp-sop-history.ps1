#requires -Version 5.1
<#
.SYNOPSIS
  Change History stamping engine for compliance SOPs (SOP-QA-001 step 8).

.DESCRIPTION
  Shared engine + CLI that appends a Change History row and bumps the header
  Version (date) on a compliance SOP whenever its content changes. Enforces
  SOP-QA-001 step 8 mechanically: incremented version, UTC date, named author,
  and a what/who/how description, with the header version kept equal to the
  newest (bottom) row.

  This file is BOTH a library and a command:
    - Dot-source it (`. scripts/stamp-sop-history.ps1`) to load the functions
      without running anything. watch-sop-history.ps1 does this.
    - Run it directly to stamp every SOP that differs from git HEAD (a manual
      fallback for when the watcher is not running):
        powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stamp-sop-history.ps1
      Add -Editorial to record the change as a dotted sub-revision (1.2 -> 1.2.1)
      instead of a minor bump (1.2 -> 1.3). Add -WhatIf to preview without writing.

  All 68 SOP files share one format: a header blockquote whose first '>' line
  ends with '... | Version X.Y (YYYY-MM-DD)', and a '## Change History' section
  (last in the file) with a 4-column table, newest row at the bottom.

  ASCII-only, no external modules. Windows-only per project rules.

.PARAMETER Path
  One or more SOP files to stamp directly. Default: every SOP changed vs HEAD.

.PARAMETER Editorial
  Bump as an editorial dotted sub-revision instead of a minor version.

.PARAMETER Author
  Override the resolved author string (default: git config nightingale.sopAuthor
  -> ~/.nightingale/sop-author.txt -> git config user.name).

.PARAMETER WhatIf
  Show what would be stamped without modifying any file.
#>
[CmdletBinding()]
param(
  [string[]]$Path,
  [switch]$Editorial,
  [string]$Author,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# --- author resolution ------------------------------------------------------
function Resolve-SopAuthor {
  param([string]$Override, [string]$RepoRoot)
  if ($Override) { return $Override.Trim() }
  # Resolve git config against the repo explicitly (git -C), not the current
  # working directory -- otherwise a watcher launched from another CWD cannot see
  # the repo-local nightingale.sopAuthor and silently writes rows as 'Unknown'.
  if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
  try { $a = (& git -C $RepoRoot config nightingale.sopAuthor 2>$null) } catch { $a = $null }
  if ($a) { return ([string]$a).Trim() }
  $f = Join-Path $HOME '.nightingale\sop-author.txt'
  if (Test-Path -LiteralPath $f) {
    $t = (Get-Content -LiteralPath $f -Raw).Trim()
    if ($t) { return $t }
  }
  try { $u = (& git -C $RepoRoot config user.name 2>$null) } catch { $u = $null }
  if ($u) { return ([string]$u).Trim() }
  return 'Unknown'
}

function Get-UtcDate { return ([datetime]::UtcNow).ToString('yyyy-MM-dd') }

# --- raw file IO preserving EOL + BOM-less UTF8 -----------------------------
function Read-SopRaw {
  param([string]$FilePath)
  $raw = Get-Content -LiteralPath $FilePath -Raw
  if ($null -eq $raw) { $raw = '' }
  $eol = "`n"
  if ($raw -match "`r`n") { $eol = "`r`n" }
  $trailing = $raw.EndsWith("`n")
  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($ln in ($raw -split "`r?`n")) { [void]$lines.Add($ln) }
  # a trailing newline yields a final empty element; drop it so line ops are clean
  if ($trailing -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
    $lines.RemoveAt($lines.Count - 1)
  }
  return [pscustomobject]@{ Lines = $lines; Eol = $eol; Trailing = $trailing }
}

function Write-SopRaw {
  param([string]$FilePath, $Doc)
  $text = ($Doc.Lines -join $Doc.Eol)
  if ($Doc.Trailing) { $text += $Doc.Eol }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($FilePath, $text, $enc)
}

# --- header version token ---------------------------------------------------
# Matches the '... | Version X.Y (YYYY-MM-DD)' field on the header blockquote line.
$script:VersionRe = [regex]'Version\s+(\d+(?:\.\d+)*)\s+\((\d{4}-\d{2}-\d{2})\)'

function Find-SopHeaderVersionIndex {
  param($Doc)
  for ($i = 0; $i -lt $Doc.Lines.Count; $i++) {
    if ($Doc.Lines[$i] -match '^>' -and $script:VersionRe.IsMatch($Doc.Lines[$i])) { return $i }
  }
  return -1
}

# --- Change History table location + rows -----------------------------------
function Get-SopHistory {
  param($Doc)
  $heading = -1
  for ($i = 0; $i -lt $Doc.Lines.Count; $i++) {
    if ($Doc.Lines[$i] -match '^##\s+Change History\s*$') { $heading = $i; break }
  }
  if ($heading -lt 0) { return $null }
  # separator row '|---|---|---|---|'
  $sep = -1
  for ($i = $heading + 1; $i -lt $Doc.Lines.Count; $i++) {
    if ($Doc.Lines[$i] -match '^\|[-\s|]+\|\s*$' -and $Doc.Lines[$i] -match '-') { $sep = $i; break }
    if ($Doc.Lines[$i] -match '^##\s') { break }
  }
  if ($sep -lt 0) { return $null }
  # data rows: consecutive '|' lines after the separator
  $rows = [System.Collections.Generic.List[object]]::new()
  $last = $sep
  for ($i = $sep + 1; $i -lt $Doc.Lines.Count; $i++) {
    $ln = $Doc.Lines[$i]
    if ($ln -match '^\|') {
      $cells = ($ln.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() }
      [void]$rows.Add([pscustomobject]@{
        Index = $i; Version = $cells[0]; Date = $cells[1]; Author = $cells[2]; Desc = ($cells[3..($cells.Count-1)] -join ' | ')
      })
      $last = $i
    } elseif ($ln.Trim() -eq '') {
      continue
    } else {
      break
    }
  }
  return [pscustomobject]@{ Heading = $heading; Separator = $sep; Rows = $rows; LastRowIndex = $last }
}

# --- substantive content (everything the watcher itself never writes) --------
# Excludes the header Version token and the whole '## Change History' block, so
# a stamp (which only touches those) does not count as a substantive change.
function Get-SopSubstantive {
  param([string]$FilePath, $Doc)
  if (-not $Doc) { $Doc = Read-SopRaw -FilePath $FilePath }
  $hv = Find-SopHeaderVersionIndex $Doc
  $hist = Get-SopHistory $Doc
  $cut = if ($hist) { $hist.Heading } else { $Doc.Lines.Count }
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $cut; $i++) {
    $ln = $Doc.Lines[$i]
    if ($i -eq $hv) { $ln = $script:VersionRe.Replace($ln, 'Version <v>') }
    [void]$sb.AppendLine($ln)
  }
  return $sb.ToString()
}

function Get-SopSubstantiveHash {
  param([string]$Text)
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  return ([System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace '-', '')
}

# --- version bump -----------------------------------------------------------
function Get-NextVersion {
  param([string]$Current, [switch]$Editorial)
  $parts = @($Current -split '\.')
  if ($Editorial) {
    if ($parts.Count -ge 3) {
      $parts[-1] = [string]([int]$parts[-1] + 1)
      return ($parts -join '.')
    }
    return "$Current.1"
  }
  $major = $parts[0]
  $minor = 0
  if ($parts.Count -ge 2) { $minor = [int]$parts[1] }
  return ("{0}.{1}" -f $major, ($minor + 1))
}

# --- auto description from a section-level diff ------------------------------
function Get-SopSections {
  param([string]$Text)
  $sections = [ordered]@{}
  $cur = 'header metadata'
  $buf = New-Object System.Text.StringBuilder
  foreach ($ln in ($Text -split "`r?`n")) {
    $m = [regex]::Match($ln, '^#{2,3}\s+(.+?)\s*$')
    if ($m.Success) {
      $sections[$cur] = $buf.ToString()
      $buf = New-Object System.Text.StringBuilder
      # strip a trailing context tag like '[INTERNAL]' from the title
      $cur = ($m.Groups[1].Value -replace '\s*\[[A-Z]+\]\s*$', '').Trim()
    } else {
      [void]$buf.AppendLine($ln)
    }
  }
  $sections[$cur] = $buf.ToString()
  return $sections
}

# Net add vs remove for a section body, by normalized-length delta -- so a
# deletion reads as a deletion ('content removed') instead of a bland 'edited'.
function Get-SectionChangeKind {
  param([string]$Base, [string]$Cur)
  $b = ($Base -replace '\s+', ' ').Trim()
  $c = ($Cur  -replace '\s+', ' ').Trim()
  if ($b -eq $c) { return '' }
  $d = $c.Length - $b.Length
  if ($d -gt 0) { return 'content added' }
  if ($d -lt 0) { return 'content removed' }
  return 'content changed'
}

function Get-AutoDescription {
  param([string]$BaselineText, [string]$CurrentText)
  $b = Get-SopSections $BaselineText
  $c = Get-SopSections $CurrentText
  $changed = [System.Collections.Generic.List[string]]::new()
  $seen = @{}
  foreach ($k in $c.Keys) {
    $seen[$k] = $true
    if ($b.Contains($k)) {
      if ($b[$k] -ne $c[$k]) {
        $kind = Get-SectionChangeKind -Base $b[$k] -Cur $c[$k]
        if ($kind) { [void]$changed.Add("$k ($kind)") } else { [void]$changed.Add($k) }
      }
    } else {
      [void]$changed.Add("$k (new)")
    }
  }
  foreach ($k in $b.Keys) {
    if (-not $seen.ContainsKey($k)) { [void]$changed.Add("$k (removed)") }
  }
  if ($changed.Count -eq 0) { return 'Edited SOP content.' }
  if ($changed.Count -eq 1 -and $changed[0] -eq 'header metadata') { return 'Edited header metadata.' }
  return ('Edited sections: ' + ($changed -join ', ') + '.')
}

function Format-SopDesc {
  param([string]$Desc)
  $d = ($Desc -replace '[\r\n]+', ' ') -replace '\|', '/'
  return ($d -replace '\s+', ' ').Trim()
}

# --- the writer -------------------------------------------------------------
# Appends a new bottom row (append) or replaces the current bottom row (update),
# and rewrites the header Version (date) to match. Returns the chosen version.
function Set-SopHistory {
  param(
    [string]$FilePath,
    [string]$Version,
    [string]$Date,
    [string]$Author,
    [string]$Description,
    [switch]$UpdateLast,
    [switch]$WhatIf
  )
  $Doc = Read-SopRaw -FilePath $FilePath
  $hv = Find-SopHeaderVersionIndex $Doc
  if ($hv -lt 0) { throw "[$FilePath] no header 'Version X.Y (date)' token found" }
  $hist = Get-SopHistory $Doc
  if (-not $hist) { throw "[$FilePath] no '## Change History' table found" }

  $desc = Format-SopDesc $Description
  $row = "| $Version | $Date | $Author | $desc |"

  if ($UpdateLast -and $hist.Rows.Count -gt 0) {
    $Doc.Lines[$hist.LastRowIndex] = $row
  } else {
    $Doc.Lines.Insert($hist.LastRowIndex + 1, $row)
  }
  # bump the header version token
  $Doc.Lines[$hv] = $script:VersionRe.Replace($Doc.Lines[$hv], "Version $Version ($Date)")

  if ($WhatIf) {
    Write-Host ("  [WhatIf] {0} -> {1}  {2}" -f (Split-Path -Leaf $FilePath), $Version, $desc) -ForegroundColor DarkCyan
    return $Version
  }
  Write-SopRaw -FilePath $FilePath -Doc $Doc
  return $Version
}

# Roll back a stamp: remove the current bottom Change History row and restore the
# header Version (date) to the new bottom row. MANUAL utility only -- the watcher
# is append-only and never calls this (a same-session revert appends a reversion
# row instead of erasing one). Kept for deliberate operator corrections. Only
# removes the row when it matches the given version, and never removes the last
# remaining (initial-issue) row.
function Remove-LastSopHistoryRow {
  param([string]$FilePath, [string]$ExpectVersion, [switch]$WhatIf)
  $Doc = Read-SopRaw -FilePath $FilePath
  $hv = Find-SopHeaderVersionIndex $Doc
  if ($hv -lt 0) { throw "[$FilePath] no header 'Version X.Y (date)' token found" }
  $hist = Get-SopHistory $Doc
  if (-not $hist -or $hist.Rows.Count -lt 2) { return $false }
  $bottom = $hist.Rows[$hist.Rows.Count - 1]
  if ($ExpectVersion -and $bottom.Version -ne $ExpectVersion) { return $false }
  $prev = $hist.Rows[$hist.Rows.Count - 2]
  $Doc.Lines.RemoveAt($bottom.Index)
  $Doc.Lines[$hv] = $script:VersionRe.Replace($Doc.Lines[$hv], "Version $($prev.Version) ($($prev.Date))")
  if ($WhatIf) { return $true }
  Write-SopRaw -FilePath $FilePath -Doc $Doc
  return $true
}

# Convenience for the manual CLI / one-shot: stamp a file given a baseline text.
# Appends a NEW row (fresh session). Returns the new version, or $null if no
# substantive change vs the baseline.
function Invoke-SopStamp {
  param(
    [string]$FilePath,
    [string]$BaselineText,
    [switch]$Editorial,
    [string]$Author,
    [switch]$WhatIf
  )
  $curSub = Get-SopSubstantive -FilePath $FilePath
  if ($null -ne $BaselineText -and (Get-SopSubstantiveHash $curSub) -eq (Get-SopSubstantiveHash $BaselineText)) {
    return $null
  }
  $Doc = Read-SopRaw -FilePath $FilePath
  $hist = Get-SopHistory $Doc
  $curVer = if ($hist -and $hist.Rows.Count -gt 0) { $hist.Rows[$hist.Rows.Count - 1].Version } else { '1.0' }
  $next = Get-NextVersion -Current $curVer -Editorial:$Editorial
  $auth = Resolve-SopAuthor -Override $Author
  $desc = if ($null -ne $BaselineText) { Get-AutoDescription -BaselineText $BaselineText -CurrentText $curSub } else { 'Edited SOP content.' }
  Set-SopHistory -FilePath $FilePath -Version $next -Date (Get-UtcDate) -Author $auth -Description $desc -WhatIf:$WhatIf | Out-Null
  return $next
}

# --- CLI (skipped when the file is dot-sourced) -----------------------------
if ($MyInvocation.InvocationName -ne '.') {
  $repoRoot = Split-Path -Parent $PSScriptRoot

  # Baseline sources, in order: (1) the watcher's last-sealed substantive text
  # from ~/.nightingale/sop-history-state.json, (2) the file at git HEAD. The
  # state baseline is what makes this work even when the compliance tree is
  # untracked (git diff HEAD would list nothing) -- it matches exactly what the
  # watcher considers a change.
  $stateBaselines = @{}
  $statePath = Join-Path $HOME '.nightingale\sop-history-state.json'
  if (Test-Path -LiteralPath $statePath) {
    try {
      $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      foreach ($p in $st.files.PSObject.Properties) {
        if ($p.Value.sealedSub) { $stateBaselines[$p.Name] = [string]$p.Value.sealedSub }
      }
    } catch { }
  }

  function Get-HeadSubstantive([string]$FullPath) {
    $rel = ($FullPath.Substring($repoRoot.Length).TrimStart('\') -replace '\\', '/')
    $headRaw = (& git -C $repoRoot show ("HEAD:{0}" -f $rel) 2>$null | Out-String)
    if (-not $headRaw) { return $null }
    $tmpDoc = [pscustomobject]@{ Lines = [System.Collections.Generic.List[string]]::new(); Eol = "`n"; Trailing = $true }
    foreach ($ln in ($headRaw -split "`r?`n")) { [void]$tmpDoc.Lines.Add($ln) }
    return (Get-SopSubstantive -Doc $tmpDoc)
  }

  # Target list: explicit -Path, else every SOP on disk (tracked or not).
  $targets = @()
  if ($Path) {
    $targets = $Path | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }
  } else {
    foreach ($sub in @('GxP\sops', 'SOC 2\sops', 'HIPAA\sops')) {
      $d = Join-Path (Join-Path $repoRoot '07-compliance') $sub
      if (Test-Path -LiteralPath $d) {
        $targets += (Get-ChildItem -LiteralPath $d -Filter 'SOP-*.md' -File).FullName
      }
    }
  }

  $stamped = 0; $checked = 0
  foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t)) { Write-Host "  skip (missing): $t" -ForegroundColor Yellow; continue }
    $checked++
    # Per-file isolation: a malformed SOP (e.g. a draft with no Change History
    # table yet) must not abort the whole run.
    try {
      $baseSub = $null
      if ($stateBaselines.ContainsKey($t)) { $baseSub = $stateBaselines[$t] }
      if ($null -eq $baseSub) { $baseSub = Get-HeadSubstantive $t }
      # No baseline anywhere: only stamp when the file was explicitly targeted
      # (avoids spurious stamps on files we cannot diff).
      if ($null -eq $baseSub -and -not $Path) { continue }
      $ver = Invoke-SopStamp -FilePath $t -BaselineText $baseSub -Editorial:$Editorial -Author $Author -WhatIf:$WhatIf
      if ($ver) {
        $stamped++
        Write-Host ("  stamped {0} -> {1}" -f (Split-Path -Leaf $t), $ver) -ForegroundColor Cyan
      }
    } catch {
      Write-Host ("  ! skipped {0}: {1}" -f (Split-Path -Leaf $t), $_.Exception.Message) -ForegroundColor Yellow
    }
  }
  if ($stamped -eq 0) { Write-Host ("No substantive SOP changes to stamp ({0} checked)." -f $checked) -ForegroundColor Green }
  else { Write-Host ("Done. {0} file(s) stamped ({1} checked)." -f $stamped, $checked) -ForegroundColor Green }
  exit 0
}
