<#
.SYNOPSIS
    Registers Windows Task Scheduler entries that run the two signal-watcher agents every Monday at 7:00 AM (local time).

.DESCRIPTION
    One-time setup. Run this script once after cloning the nightingale-gtm repo. It registers two scheduled tasks:
      - Nightingale-Commercial-Sweep
      - Nightingale-Academic-Sweep
    Each task invokes the `claude` CLI headlessly from the cloned repo directory with the appropriate trigger phrase.

.PREREQUISITES
    - Claude Code installed and on PATH (the `claude` command must be runnable from a fresh shell)
    - The Apollo.io MCP connector authorized in your Claude Code instance (only needed for the commercial sweep)
    - The ClinicalTrials.gov MCP connector authorized (needed for both sweeps)
    - Internet access from this machine on Monday mornings

.NOTES
    To uninstall:  Unregister-ScheduledTask -TaskName 'Nightingale-Commercial-Sweep','Nightingale-Academic-Sweep' -Confirm:$false
    To list:       Get-ScheduledTask -TaskName 'Nightingale-*'
    Note: Windows Task Scheduler runs on LOCAL time, not Eastern. Adjust the -At argument below if you want a different local time.
#>

$ErrorActionPreference = 'Stop'

# Resolve the repo root (one directory above this script)
$repoRoot = Split-Path -Parent $PSScriptRoot
Write-Host "Repo root: $repoRoot"

# Verify `claude` is on PATH
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Error "The 'claude' CLI was not found on PATH. Install Claude Code and ensure 'claude' is runnable from a fresh shell, then re-run this script."
    exit 1
}
Write-Host "claude CLI: $($claudeCmd.Source)"

# Common trigger: weekly Monday 7:00 local time
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "7:00am"

# Run as the current user, only when logged on, network required
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -RunOnlyIfNetworkAvailable

# --- Commercial sweep ---
$commercialAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "weekly commercial sweep"' `
    -WorkingDirectory $repoRoot

Register-ScheduledTask `
    -TaskName 'Nightingale-Commercial-Sweep' `
    -Action $commercialAction `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale signal-watcher: weekly commercial sweep (Monday 7am local). Repo: nightingale-gtm.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Commercial-Sweep"

# --- Academic sweep ---
$academicAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "weekly academic sweep"' `
    -WorkingDirectory $repoRoot

Register-ScheduledTask `
    -TaskName 'Nightingale-Academic-Sweep' `
    -Action $academicAction `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale signal-watcher: weekly academic sweep (Monday 7am local). Repo: nightingale-gtm.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Academic-Sweep"

Write-Host ""
Write-Host "Done. Verify with:  Get-ScheduledTask -TaskName 'Nightingale-*'"
Write-Host "Next run is the next upcoming Monday at 7:00 AM local time."
Write-Host "Outputs land in: $HOME\Desktop\nightingale-signals\{commercial|academic}\output\"
