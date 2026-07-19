#requires -Version 5.1
<#
.SYNOPSIS
  Optional: auto-start the SOP Change History watcher at logon.

.DESCRIPTION
  Registers a Task Scheduler entry 'Nightingale-SOP-History-Watcher' that runs
  scripts/watch-sop-history.ps1 at user logon (hidden window) so SOP edits are
  auto-stamped without the operator remembering to start it. Opt-in, like the UI.

  Uses Register-ScheduledTask with a New-ScheduledTaskTrigger (never
  `schtasks /sd YYYY-MM-DD`, which is locale-dependent per project rules).
  ASCII-only. Windows-only.

.PARAMETER Unregister
  Remove the scheduled task instead of installing it.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-sop-watcher.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-sop-watcher.ps1 -Unregister
#>
[CmdletBinding()]
param([switch]$Unregister)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $PSScriptRoot
$watchScript = Join-Path $PSScriptRoot 'watch-sop-history.ps1'
$taskName    = 'Nightingale-SOP-History-Watcher'

function Test-Admin {
  $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Registering a Task Scheduler entry needs elevation on locked-down machines.
# Self-elevate via UAC and relaunch (mirrors scripts/install-runner.ps1).
if (-not (Test-Admin)) {
  Write-Host 'Elevation required to register the scheduled task. Requesting it now (UAC prompt)...' -ForegroundColor Cyan
  $relaunch = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  if ($Unregister) { $relaunch += '-Unregister' }
  try {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch | Out-Null
  } catch {
    Write-Error "Elevation was declined or failed. Re-run from an elevated PowerShell. ($($_.Exception.Message))"
    exit 1
  }
  exit 0
}

if ($Unregister) {
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed scheduled task: $taskName" -ForegroundColor Green
  } else {
    Write-Host "No scheduled task named $taskName." -ForegroundColor Yellow
  }
  exit 0
}

if (-not (Test-Path -LiteralPath $watchScript)) { throw "watcher script not found: $watchScript" }

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$action    = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchScript`"" `
    -WorkingDirectory $repoRoot

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale SOP Change History watcher: auto-stamps a Change History row + bumps the header version whenever a 07-compliance SOP is edited (SOP-QA-001 step 8). See scripts/watch-sop-history.ps1.' `
    -Force | Out-Null

Write-Host "Registered: $taskName (at logon, hidden)" -ForegroundColor Green
Write-Host "Set your author string once with:  git config nightingale.sopAuthor `"Ben Heuertz, COO`""
Write-Host "Start it now without logging off:   Start-ScheduledTask -TaskName '$taskName'"
Write-Host "Remove it with:                     scripts/install-sop-watcher.ps1 -Unregister"
