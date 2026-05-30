<#
.SYNOPSIS
    Registers Windows Task Scheduler entries that drive the Nightingale agent chain.

.DESCRIPTION
    One-time setup. Run this once after cloning the nightingale repo. Four scheduled
    tasks are registered:
      - Nightingale-Commercial-Sweep         (Monday 7:00 local — sweep + buying-group-finder)
      - Nightingale-Academic-Sweep           (Monday 7:00 local — sweep + buying-group-finder)
      - Nightingale-Intro-Finder-Morning     (Sun-Fri 7:00 local — delivery + queue)
      - Nightingale-Gmail-Resurfacer-Morning (Mon-Fri 7:00 local — Gmail re-surfacer)

    Each task invokes the `claude` CLI headlessly from the cloned repo directory
    with the appropriate trigger phrase.

.PREREQUISITES
    - Claude Code installed and on PATH (the `claude` command must be runnable from a fresh shell)
    - The ClinicalTrials.gov MCP connector authorized (both sweeps + resurfacer)
    - The Apollo.io MCP connector authorized (commercial sweep + resurfacer read-only)
    - The Gmail MCP connector authorized (resurfacer only)
    - The HubSpot MCP connector authorized (resurfacer read-only annotation)
    - For intro-finder: ~/.nightingale/secrets.json populated via scripts/setup-secrets.ps1
    - Internet access from this machine during scheduled times

.NOTES
    To uninstall:  Unregister-ScheduledTask -TaskName 'Nightingale-Commercial-Sweep','Nightingale-Academic-Sweep','Nightingale-Intro-Finder-Morning','Nightingale-Gmail-Resurfacer-Morning' -Confirm:$false
    To list:       Get-ScheduledTask -TaskName 'Nightingale-*'
    Windows Task Scheduler runs on LOCAL time, not Eastern.
#>

$ErrorActionPreference = 'Stop'

# --- ExecutionPolicy preflight ----------------------------------------------
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Warning "PowerShell ExecutionPolicy for CurrentUser is '$policy'."
    Write-Warning "The scheduled tasks invoke 'powershell.exe -ExecutionPolicy Bypass ...' so they will run,"
    Write-Warning "but manual reruns of these scripts may fail. Recommended fix:"
    Write-Warning "    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    Write-Host ''
}

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

# Common principal + settings
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -RunOnlyIfNetworkAvailable

# --- Monday-only sweep triggers ---
$mondayTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "7:00am"

# Commercial sweep
$commercialAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "weekly commercial sweep"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Commercial-Sweep' `
    -Action $commercialAction `
    -Trigger $mondayTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale signal-watcher: weekly commercial sweep (Monday 7am local).' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Commercial-Sweep"

# Academic sweep
$academicAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "weekly academic sweep"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Academic-Sweep' `
    -Action $academicAction `
    -Trigger $mondayTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale signal-watcher: weekly academic sweep (Monday 7am local).' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Academic-Sweep"

# --- Intro-finder daily morning (Sun-Fri 7am) ---
$introTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday,Monday,Tuesday,Wednesday,Thursday,Friday -At "7:00am"
$introAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "intro-finder daily morning"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Intro-Finder-Morning' `
    -Action $introAction `
    -Trigger $introTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale intro-finder: daily morning delivery + queue (Sun-Fri 7am local). Saturdays idle.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Intro-Finder-Morning"

# --- Gmail re-surfacer morning (Mon-Fri 7am) ---
$resurfacerTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At "7:00am"
$resurfacerAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "gmail resurfacer daily morning"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Gmail-Resurfacer-Morning' `
    -Action $resurfacerAction `
    -Trigger $resurfacerTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale Gmail re-surfacer: daily Mon-Fri 7am local. Scans Gmail history, scores against personas, surfaces top 5 contacts to re-engage.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Gmail-Resurfacer-Morning"

Write-Host ""
Write-Host "Done. Verify with:  Get-ScheduledTask -TaskName 'Nightingale-*'"
Write-Host "Next sweep run:        next upcoming Monday at 7:00 AM local time."
Write-Host "Next intro-finder run: next upcoming Sun-Fri at 7:00 AM local time."
Write-Host "Next resurfacer run:   next upcoming Mon-Fri at 7:00 AM local time."
Write-Host "Outputs land in: $HOME\Desktop\nightingale-signals\{commercial|academic|resurfacer}\..."
Write-Host ""
Write-Host "If you have not yet run scripts/setup-secrets.ps1, intro-finder will skip the"
Write-Host "Apify lookup step and write a SECRETS_MISSING-<date>.md notice. Run it before"
Write-Host "the next Sunday-Thursday 7am if you want intros to fire."
Write-Host ""
Write-Host "If the Gmail MCP connector is not authorized in Claude Code, the resurfacer"
Write-Host "will skip cleanly and write a GMAIL_NOT_AUTHORIZED-<date>.md notice instead."
