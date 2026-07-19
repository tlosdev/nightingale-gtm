#requires -Version 5.1
<#
.SYNOPSIS
  Watches the compliance SOPs and auto-stamps a Change History row whenever one
  is edited (SOP-QA-001 step 8).

.DESCRIPTION
  A persistent loop over the three SOP folders:
    07-compliance/GxP/sops, 07-compliance/SOC 2/sops, 07-compliance/HIPAA/sops
  When an SOP's *substantive* content changes (anything except the header Version
  token and the Change History rows -- the only two things this tool writes), it:
    - opens an editing SESSION and appends ONE new Change History row
      (minor bump 1.2 -> 1.3, or a dotted sub-revision if the SOP was marked
      editorial via scripts/mark-sop-editorial.ps1),
    - keeps updating THAT row's date + auto-description while the session
      continues (no extra version bumps -- one row per editing session),
    - seals the session after an idle gap (default 5 min) or when a new git
      commit is detected; the next edit opens a fresh session (new bump).

  Implementation is a poll loop (default every 3 s), gated by file LastWriteTime
  so it is nearly free, with a stability debounce: a change is only stamped once
  its content has been quiet for -DebounceSeconds. This is deliberately chosen
  over raw FileSystemWatcher events for robustness (no multi-runspace event
  marshalling, no self-write echo races, no editor temp-file noise).

  State lives OUTSIDE the repo at ~/.nightingale/sop-history-state.json so the
  watcher's own bookkeeping is never itself stamped or committed. Never logs file
  bodies. ASCII-only. Windows-only per project rules. Ctrl-C to stop cleanly.

.PARAMETER PollSeconds
  Seconds between scans (default 3).

.PARAMETER DebounceSeconds
  A change must stay stable this long before it is stamped (default 8).

.PARAMETER SealMinutes
  Idle minutes after which an editing session is sealed (default 5).

.PARAMETER Once
  Run a single scan pass and exit (for testing / cron-style use).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/watch-sop-history.ps1
#>
[CmdletBinding()]
param(
  [int]$PollSeconds = 3,
  [int]$DebounceSeconds = 8,
  [int]$SealMinutes = 5,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Load the stamping engine (functions only; dot-source skips its CLI).
. (Join-Path $PSScriptRoot 'stamp-sop-history.ps1')

# In -Once mode the transient debounce map does not survive between runs, so a
# single pass would always defer. Disable the debounce wait for one-shot runs.
if ($Once) { $DebounceSeconds = 0 }

$sopDirs = @(
  (Join-Path (Join-Path $repoRoot '07-compliance') 'GxP\sops'),
  (Join-Path (Join-Path $repoRoot '07-compliance') 'SOC 2\sops'),
  (Join-Path (Join-Path $repoRoot '07-compliance') 'HIPAA\sops')
)

$stateDir  = Join-Path $HOME '.nightingale'
$statePath = Join-Path $stateDir 'sop-history-state.json'
# One-shot "next stamp is editorial" flags dropped by scripts/mark-sop-editorial.ps1,
# as sentinel files so marking never races the running watcher's state writes.
$editorialDir = Join-Path $stateDir 'sop-editorial'
# Durable record of SOP files deleted off disk. A deleted SOP's own Change
# History table is destroyed with the file, so a hard delete of a controlled SOP
# is recorded here instead (SOP-QA-001: controlled SOPs are RETIRED in place, not
# deleted; a raw delete is a document-control deviation to investigate).
$retireLog = Join-Path $stateDir 'sop-retirement-log.md'
if (-not (Test-Path -LiteralPath $stateDir))    { New-Item -ItemType Directory -Path $stateDir | Out-Null }
if (-not (Test-Path -LiteralPath $editorialDir)) { New-Item -ItemType Directory -Path $editorialDir | Out-Null }

# --- state helpers (JSON <-> nested hashtables) -----------------------------
function ConvertTo-HashtableDeep {
  param($Obj)
  if ($null -eq $Obj) { return $null }
  if ($Obj -is [System.Management.Automation.PSCustomObject]) {
    $h = @{}
    foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
    return $h
  }
  return $Obj
}

function Load-State {
  if (-not (Test-Path -LiteralPath $statePath)) { return @{ files = @{} } }
  try {
    $obj = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $h = ConvertTo-HashtableDeep $obj
    if (-not $h.ContainsKey('files')) { $h['files'] = @{} }
    return $h
  } catch {
    Write-Host "  (state file unreadable; starting fresh)" -ForegroundColor Yellow
    return @{ files = @{} }
  }
}

function Save-State {
  param($State)
  $tmp = "$statePath.tmp"
  ($State | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $statePath -Force
}

function Get-SopIdFromPath {
  param([string]$FilePath)
  $m = [regex]::Match((Split-Path -Leaf $FilePath), '^(SOP-[A-Z]+-\d+)-')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Get-BottomRowVersion {
  param([string]$FilePath)
  $doc = Read-SopRaw -FilePath $FilePath
  $hist = Get-SopHistory $doc
  if ($hist -and $hist.Rows.Count -gt 0) { return $hist.Rows[$hist.Rows.Count - 1].Version }
  return '1.0'
}

function Get-BottomRowDesc {
  param([string]$FilePath)
  $doc = Read-SopRaw -FilePath $FilePath
  $hist = Get-SopHistory $doc
  if ($hist -and $hist.Rows.Count -gt 0) { return $hist.Rows[$hist.Rows.Count - 1].Desc }
  return ''
}

function Get-HeadSha {
  Push-Location $repoRoot
  try { return (& git rev-parse HEAD 2>$null | Out-String).Trim() } catch { return '' } finally { Pop-Location }
}

# --- the per-file scan ------------------------------------------------------
$mtimeCache = @{}   # transient: path -> last-seen write ticks
$pending    = @{}   # transient: path -> @{ Hash; Since }
$missing    = @{}   # transient: path -> first-missing NowUtc (deletion debounce)

function Process-File {
  param([string]$FilePath, $State, [datetime]$NowUtc)

  $files = $State['files']
  $key = $FilePath

  $curSub  = Get-SopSubstantive -FilePath $FilePath
  $curHash = Get-SopSubstantiveHash $curSub

  # First time we ever see this file: seed its sealed baseline; never retro-stamp.
  if (-not $files.ContainsKey($key)) {
    $files[$key] = @{
      sealedHash = $curHash; sealedSub = $curSub; sessionActive = $false
      sessionVersion = $null; lastStampedHash = $curHash; lastActivityUtc = $NowUtc.ToString('o')
      lastKnownVersion = (Get-BottomRowVersion $FilePath)
    }
    return $false
  }
  $st = $files[$key]
  # Backfill lastKnownVersion for entries seeded before deletion-tracking existed.
  if (-not $st.ContainsKey('lastKnownVersion') -or -not $st['lastKnownVersion']) {
    $st['lastKnownVersion'] = Get-BottomRowVersion $FilePath
  }

  # No substantive change vs sealed baseline (clean, or reverted): clear pending.
  if ($curHash -eq $st['sealedHash']) {
    if ($pending.ContainsKey($key)) { $pending.Remove($key) }
    # A session whose edits were fully reverted to the baseline. Append-only:
    # never remove the row we stamped -- append a NEW row recording the reversion,
    # so the change-history table is never edited destructively (ALCOA: entries
    # supersede but never erase). Then seal; a fresh edit opens a new session.
    if ($st['sessionActive']) {
      $revertedFrom = $st['sessionVersion']
      $utc  = Get-UtcDate
      $auth = Resolve-SopAuthor -RepoRoot $repoRoot
      $next = Get-NextVersion -Current (Get-BottomRowVersion $FilePath)
      $desc = "Reverted the change recorded in v$revertedFrom; content restored to the prior baseline."
      try {
        Set-SopHistory -FilePath $FilePath -Version $next -Date $utc -Author $auth -Description $desc | Out-Null
        Write-Host ("  {0}  {1} -> {2}  (reverted v{3} to baseline)" -f $utc, (Split-Path -Leaf $FilePath), $next, $revertedFrom) -ForegroundColor Cyan
      } catch {
        Write-Host ("  ! revert-row failed {0}: {1}" -f (Split-Path -Leaf $FilePath), $_.Exception.Message) -ForegroundColor Yellow
        $next = $revertedFrom
      }
      $st['sessionActive'] = $false
      $st['sessionVersion'] = $null
      $st['lastStampedHash'] = $st['sealedHash']   # substantive unchanged by the CH/version write
      $st['lastKnownVersion'] = $next
      $st['lastActivityUtc'] = $NowUtc.ToString('o')
      return $true
    }
    return $false
  }

  # Already stamped exactly this content (our own echo write, or no new edit).
  if ($curHash -eq $st['lastStampedHash']) {
    if ($pending.ContainsKey($key)) { $pending.Remove($key) }
    # idle-seal check happens in the caller
    return $false
  }

  # Debounce: only stamp once the content has been stable for DebounceSeconds.
  # DebounceSeconds <= 0 disables the wait (stamp on detection).
  if ($DebounceSeconds -gt 0) {
    if (-not $pending.ContainsKey($key) -or $pending[$key].Hash -ne $curHash) {
      $pending[$key] = @{ Hash = $curHash; Since = $NowUtc }
      return $false
    }
    if (($NowUtc - $pending[$key].Since).TotalSeconds -lt $DebounceSeconds) { return $false }
  }

  # --- stable substantive change: STAMP -----------------------------------
  $desc = Get-AutoDescription -BaselineText $st['sealedSub'] -CurrentText $curSub
  $utc  = Get-UtcDate
  $auth = Resolve-SopAuthor -RepoRoot $repoRoot

  if (-not $st['sessionActive']) {
    # Open a new session. Editorial if this SOP id was marked (sentinel file).
    $sopId = Get-SopIdFromPath $FilePath
    $isEditorial = $false
    if ($sopId) {
      $flag = Join-Path $editorialDir ("{0}.flag" -f $sopId)
      if (Test-Path -LiteralPath $flag) { $isEditorial = $true; Remove-Item -LiteralPath $flag -Force }
    }
    $next = Get-NextVersion -Current (Get-BottomRowVersion $FilePath) -Editorial:$isEditorial
    Set-SopHistory -FilePath $FilePath -Version $next -Date $utc -Author $auth -Description $desc | Out-Null
    $st['sessionActive'] = $true
    $st['sessionVersion'] = $next
    $st['lastKnownVersion'] = $next
    Write-Host ("  {0}  {1} -> {2}  ({3})" -f $utc, (Split-Path -Leaf $FilePath), $next, $desc) -ForegroundColor Cyan
  } else {
    # Continue the session: update the bottom row in place, same version.
    # Preserve an operator-customized description (one that is no longer auto-generated).
    $bottomDesc = Get-BottomRowDesc $FilePath
    $useDesc = if ($bottomDesc -match '^Edited ') { $desc } else { $bottomDesc }
    Set-SopHistory -FilePath $FilePath -Version $st['sessionVersion'] -Date $utc -Author $auth -Description $useDesc -UpdateLast | Out-Null
    Write-Host ("  {0}  {1} ~= {2}  ({3})" -f $utc, (Split-Path -Leaf $FilePath), $st['sessionVersion'], $useDesc) -ForegroundColor DarkCyan
  }

  # After the write, substantive content is unchanged -> record it as stamped.
  $st['lastStampedHash'] = $curHash
  $st['lastActivityUtc'] = $NowUtc.ToString('o')
  if ($pending.ContainsKey($key)) { $pending.Remove($key) }
  return $true
}

function Seal-IdleSessions {
  param($State, [datetime]$NowUtc)
  foreach ($key in @($State['files'].Keys)) {
    $st = $State['files'][$key]
    if ($st['sessionActive']) {
      $last = [datetime]::Parse($st['lastActivityUtc']).ToUniversalTime()
      if (($NowUtc - $last).TotalMinutes -ge $SealMinutes) {
        # re-read current substantive so the new baseline includes this session's edits
        if (Test-Path -LiteralPath $key) {
          $sub = Get-SopSubstantive -FilePath $key
          $st['sealedSub'] = $sub
          $st['sealedHash'] = Get-SopSubstantiveHash $sub
          $st['lastStampedHash'] = $st['sealedHash']
        }
        $st['sessionActive'] = $false
        $st['sessionVersion'] = $null
      }
    }
  }
}

function Reseal-OnCommit {
  param($State)
  foreach ($key in @($State['files'].Keys)) {
    if (-not (Test-Path -LiteralPath $key)) { continue }
    $sub = Get-SopSubstantive -FilePath $key
    $h = Get-SopSubstantiveHash $sub
    $st = $State['files'][$key]
    $st['sealedSub'] = $sub
    $st['sealedHash'] = $h
    $st['lastStampedHash'] = $h
    $st['sessionActive'] = $false
    $st['sessionVersion'] = $null
  }
}

# --- deletion handling ------------------------------------------------------
# A deleted SOP cannot get an in-file Change History row (the table dies with the
# file), so record it in the durable retirement log instead and warn loudly.
function Record-Deletion {
  param([string]$FilePath, [string]$SopId, [string]$Version, [datetime]$NowUtc)
  $auth  = Resolve-SopAuthor -RepoRoot $repoRoot
  $stamp = $NowUtc.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
  $id    = if ($SopId) { $SopId } else { Split-Path -Leaf $FilePath }
  $ver   = if ($Version) { $Version } else { 'unknown' }
  $enc   = New-Object System.Text.UTF8Encoding($false)
  if (-not (Test-Path -LiteralPath $retireLog)) {
    $header = @(
      '# SOP retirement / deletion log',
      '',
      "Durable record of controlled SOP files removed from disk while the watcher was running. A deleted SOP's own Change History table is destroyed with the file, so a hard delete is recorded here instead of in the file (SOP-QA-001). Controlled SOPs should be RETIRED in place (status + a Change History row), not deleted -- an entry here that was not a deliberate retirement is a document-control deviation to investigate.",
      '',
      '| Detected (UTC) | SOP | Last version | Author | Note |',
      '|---|---|---|---|---|',
      ''
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($retireLog, $header, $enc)
  }
  $row = "| $stamp | $id | $ver | $auth | File deleted from disk; in-file Change History destroyed with it. |`r`n"
  $existing = [System.IO.File]::ReadAllText($retireLog)
  [System.IO.File]::WriteAllText($retireLog, $existing + $row, $enc)
  Write-Host ("  ! DELETED {0} (was v{1}) -- recorded in {2}" -f $id, $ver, $retireLog) -ForegroundColor Red
}

# Detect state-tracked SOPs that have vanished from disk. Debounced (must stay
# missing for -DebounceSeconds) so an editor's atomic save (delete+rename) or a
# brief lock is not mistaken for a deletion.
function Detect-Deletions {
  param($State, [datetime]$NowUtc)
  $dirty = $false
  foreach ($key in @($State['files'].Keys)) {
    if (Test-Path -LiteralPath $key) {
      if ($missing.ContainsKey($key)) { $missing.Remove($key) }
      continue
    }
    if ($DebounceSeconds -gt 0) {
      if (-not $missing.ContainsKey($key)) { $missing[$key] = $NowUtc; continue }
      if (($NowUtc - $missing[$key]).TotalSeconds -lt $DebounceSeconds) { continue }
    }
    $st  = $State['files'][$key]
    $ver = if ($st.ContainsKey('lastKnownVersion') -and $st['lastKnownVersion']) { $st['lastKnownVersion'] } else { $null }
    Record-Deletion -FilePath $key -SopId (Get-SopIdFromPath $key) -Version $ver -NowUtc $NowUtc
    [void]$State['files'].Remove($key)
    if ($missing.ContainsKey($key))    { $missing.Remove($key) }
    if ($mtimeCache.ContainsKey($key)) { $mtimeCache.Remove($key) }
    if ($pending.ContainsKey($key))    { $pending.Remove($key) }
    $dirty = $true
  }
  return $dirty
}

# --- main loop --------------------------------------------------------------
Write-Host ''
Write-Host 'SOP Change History watcher (SOP-QA-001 step 8)' -ForegroundColor Cyan
Write-Host ("  watching  : {0}" -f ($sopDirs -join '; '))
Write-Host ("  author    : {0}" -f (Resolve-SopAuthor -RepoRoot $repoRoot))
Write-Host ("  state     : {0}" -f $statePath)
Write-Host ("  poll {0}s / debounce {1}s / seal {2}m" -f $PollSeconds, $DebounceSeconds, $SealMinutes)
Write-Host '  Ctrl-C to stop.'
Write-Host ''

$state = Load-State
$lastHead = Get-HeadSha
# Cheap gate for commit detection: .git/logs/HEAD is touched on every HEAD move
# (commit, checkout, reset), so we only shell out to git when it actually changes
# instead of once per poll.
$gitLogHead = Join-Path $repoRoot '.git\logs\HEAD'
$lastLogMtime = if (Test-Path -LiteralPath $gitLogHead) { (Get-Item -LiteralPath $gitLogHead).LastWriteTimeUtc.Ticks } else { 0 }

do {
  $nowUtc = ([datetime]::UtcNow)

  # commit boundary -> reseal every file to its committed baseline (only re-check
  # when the ref log actually moved)
  $curLogMtime = if (Test-Path -LiteralPath $gitLogHead) { (Get-Item -LiteralPath $gitLogHead).LastWriteTimeUtc.Ticks } else { 0 }
  if ($curLogMtime -ne $lastLogMtime) {
    $lastLogMtime = $curLogMtime
    $head = Get-HeadSha
    if ($head -and $head -ne $lastHead) {
      Reseal-OnCommit $state
      $lastHead = $head
      Write-Host ("  (commit detected {0}; sessions resealed)" -f $head.Substring(0, [Math]::Min(8, $head.Length))) -ForegroundColor DarkGray
    }
  }

  $dirty = $false
  foreach ($dir in $sopDirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter 'SOP-*.md' -File)) {
      $p = $f.FullName
      $ticks = $f.LastWriteTimeUtc.Ticks
      # mtime gate: skip untouched files unless a session is active (need idle-seal + settle)
      $sessionActive = $state['files'].ContainsKey($p) -and $state['files'][$p]['sessionActive']
      if ($mtimeCache.ContainsKey($p) -and $mtimeCache[$p] -eq $ticks -and -not $sessionActive -and -not $pending.ContainsKey($p)) {
        continue
      }
      $mtimeCache[$p] = $ticks
      # Per-file isolation: a single malformed SOP (e.g. a new draft with no
      # Change History table yet) must not take down the whole watcher.
      try {
        if (Process-File -FilePath $p -State $state -NowUtc $nowUtc) { $dirty = $true }
      } catch {
        Write-Host ("  ! skipped {0}: {1}" -f (Split-Path -Leaf $p), $_.Exception.Message) -ForegroundColor Yellow
      }
    }
  }

  if (Detect-Deletions $state $nowUtc) { $dirty = $true }
  Seal-IdleSessions $state $nowUtc
  Save-State $state

  if ($Once) { break }
  Start-Sleep -Seconds $PollSeconds
} while ($true)

Write-Host 'watcher stopped.' -ForegroundColor Green
