<#
.SYNOPSIS
    DEPRECATED (Phase 3). Agent scheduling has moved from Windows Task Scheduler
    to GitHub Actions cron on a self-hosted runner. Use scripts/install-runner.ps1.

.DESCRIPTION
    Before Phase 3 this script registered eight Windows Task Scheduler entries
    that each ran `claude -p "<phrase>"`. That approach could not survive a
    powered-off machine (a missed 6am task simply never ran). Phase 3 replaces it:

      - Schedules now live in .github/workflows/*.yml (GitHub cron, UTC).
      - Execution stays on THIS host via a self-hosted GitHub Actions runner
        installed as a boot-start Windows service (scripts/install-runner.ps1),
        so the local Claude Code install + claude.ai MCP connectors + Desktop
        output tree are all still available.
      - Boot catch-up (scripts/boot-catchup.ps1) handles >24h outages.

    MIGRATE:
      1. .\scripts\install-runner.ps1 -RepoUrl <url> -Token <runner-reg-token>
      2. .\scripts\uninstall-schedule.ps1        # remove the old tasks (this file's)
    See 06-agent documentation/github-runner-setup.md for the full walkthrough.

    FALLBACK: if you cannot run a self-hosted runner (e.g. a locked-down machine),
    you can still register the legacy Task Scheduler entries with -Legacy. This is
    unsupported going forward and does NOT survive a powered-off machine.

.PARAMETER Legacy
    Register the eight legacy Windows Task Scheduler entries anyway (pre-Phase-3
    behavior). Without this switch the script only prints migration guidance.

.NOTES
    Windows Task Scheduler runs on LOCAL time. The intro-finder per-target Apify
    one-shots are unaffected by this migration - the agent still creates those
    dynamically on Task Scheduler.
#>
param(
    [switch]$Legacy
)

$ErrorActionPreference = 'Stop'

if (-not $Legacy) {
    Write-Host ''
    Write-Host '=============================================================='
    Write-Host ' install-schedule.ps1 is DEPRECATED (Phase 3).'
    Write-Host ' Agent scheduling moved to GitHub Actions on a self-hosted runner.'
    Write-Host '=============================================================='
    Write-Host ''
    Write-Host ' Migrate:'
    Write-Host '   1. .\scripts\install-runner.ps1 -RepoUrl <repo-url> -Token <runner-reg-token>'
    Write-Host '   2. .\scripts\uninstall-schedule.ps1      # removes the old Task Scheduler agents'
    Write-Host ''
    Write-Host ' Docs: 06-agent documentation/github-runner-setup.md'
    Write-Host ''
    Write-Host ' To register the legacy Task Scheduler entries anyway (unsupported, does NOT'
    Write-Host ' survive a powered-off machine):'
    Write-Host '   .\scripts\install-schedule.ps1 -Legacy'
    Write-Host ''
    exit 0
}

Write-Warning 'Registering LEGACY Windows Task Scheduler entries (-Legacy).'
Write-Warning 'This is the pre-Phase-3 path and does NOT survive a powered-off machine.'
Write-Warning 'Prefer scripts/install-runner.ps1. Do NOT run both, or agents double-fire.'
Write-Host ''

# --- ExecutionPolicy preflight ----------------------------------------------
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Warning "PowerShell ExecutionPolicy for CurrentUser is '$policy'."
    Write-Warning "Recommended fix:  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
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

# --- Daily-brief morning (Mon-Fri 6am, fires before the 7am stack) ---
$dailyBriefTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At "6:00am"
$dailyBriefAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "daily brief morning"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Daily-Brief-Morning' `
    -Action $dailyBriefAction `
    -Trigger $dailyBriefTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale daily-brief: today + tomorrow calendar prep (Mon-Fri 6am local, runs one hour before the 7am agent stack so the brief lands first).' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Daily-Brief-Morning"

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

# --- HubSpot manager nightly (Mon-Sun 11pm) ---
$hubspotNightlyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday -At "11:00pm"
$hubspotNightlyAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "nightly hubspot manage"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-HubSpot-Manager-Nightly' `
    -Action $hubspotNightlyAction `
    -Trigger $hubspotNightlyTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale HubSpot manager: nightly Mon-Sun 11pm local. Two-tier guardrail; auto-applies <=20 low-risk items/night, queues the rest.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-HubSpot-Manager-Nightly"

# --- Investor analyzer weekly (Monday 8am) ---
$investorAnalyzerTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "8:00am"
$investorAnalyzerAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "RUN investor-analyzer"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Investor-Analyzer-Weekly' `
    -Action $investorAnalyzerAction `
    -Trigger $investorAnalyzerTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale investor-analyzer: weekly Monday 8am local. Proposes investor-persona diffs (propose-only), then chains pitch-deck-updater.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Investor-Analyzer-Weekly"

# --- Investor newsletter biweekly (every other Friday 9am) ---
$investorNewsletterTrigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 2 -DaysOfWeek Friday -At "9:00am"
$investorNewsletterAction = New-ScheduledTaskAction `
    -Execute $claudeCmd.Source `
    -Argument '-p "RUN investor-newsletter"' `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Investor-Newsletter-Biweekly' `
    -Action $investorNewsletterAction `
    -Trigger $investorNewsletterTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale investor-newsletter: biweekly Friday 9am local. Queues an investor update; on approval creates one unsent BCC Gmail draft (never sends).' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Investor-Newsletter-Biweekly"

Write-Host ""
Write-Host "Legacy tasks registered. Reminder: this path is deprecated and does NOT"
Write-Host "survive a powered-off machine. Prefer scripts/install-runner.ps1."
Write-Host "Verify with:  Get-ScheduledTask -TaskName 'Nightingale-*'"
