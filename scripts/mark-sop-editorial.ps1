#requires -Version 5.1
<#
.SYNOPSIS
  Marks the NEXT auto-stamp of an SOP as editorial (a dotted sub-revision).

.DESCRIPTION
  The watcher (scripts/watch-sop-history.ps1) bumps a minor version by default
  (1.2 -> 1.3). Editorial / typo-only corrections should instead be a dotted
  sub-revision (1.2 -> 1.2.1) per SOP-QA-001 step 8. Because the watcher fires on
  edit (there is no commit message to carry a flag), run this BEFORE editing to
  mark the next session for that SOP as editorial.

  It drops a one-shot sentinel file at ~/.nightingale/sop-editorial/<SOP-ID>.flag
  that the watcher consumes (and deletes) when it opens that SOP's next session.
  Sentinel files avoid racing the running watcher's state writes.

  ASCII-only. Windows-only per project rules.

.PARAMETER SopId
  The SOP identifier, e.g. SOP-QA-001 (matches the file's H1 / filename prefix).
  The '-Clear' switch removes the flag instead of setting it.

.PARAMETER Clear
  Remove the pending editorial flag for this SOP instead of setting it.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/mark-sop-editorial.ps1 SOP-QA-001
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$SopId,
  [switch]$Clear
)

$ErrorActionPreference = 'Stop'

if ($SopId -notmatch '^SOP-[A-Z]+-\d+$') {
  throw "SopId '$SopId' is not of the form SOP-XXX-NNN (e.g. SOP-QA-001)."
}

$editorialDir = Join-Path (Join-Path $HOME '.nightingale') 'sop-editorial'
if (-not (Test-Path -LiteralPath $editorialDir)) { New-Item -ItemType Directory -Path $editorialDir | Out-Null }

$flag = Join-Path $editorialDir ("{0}.flag" -f $SopId)

if ($Clear) {
  if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force }
  Write-Host "Cleared editorial flag for $SopId." -ForegroundColor Green
  exit 0
}

Set-Content -LiteralPath $flag -Value ([datetime]::UtcNow.ToString('o')) -Encoding ASCII
Write-Host "Next stamp of $SopId will be an editorial sub-revision (e.g. 1.2 -> 1.2.1)." -ForegroundColor Cyan
Write-Host "The watcher consumes this flag when it opens $SopId's next editing session."
