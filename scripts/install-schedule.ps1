<#
.SYNOPSIS
    Registers Windows Task Scheduler entries that drive the Nightingale agent chain.

.DESCRIPTION
    One-time setup. Run this once after cloning the nightingale repo. Eight scheduled
    tasks are registered:
      - Nightingale-Daily-Brief-Morning         (Mon-Fri 6:00 local — calendar brief, runs before the 7am stack)
      - Nightingale-Commercial-Sweep            (Monday 7:00 local — sweep + buying-group-finder)
      - Nightingale-Academic-Sweep              (Monday 7:00 local — sweep + buying-group-finder)
      - Nightingale-Intro-Finder-Morning        (Sun-Fri 7:00 local — delivery + queue)
      - Nightingale-Gmail-Resurfacer-Morning    (Mon-Fri 7:00 local — Gmail re-surfacer)
      - Nightingale-HubSpot-Manager-Nightly     (Mon-Sun 11:00pm local — nightly HubSpot writer with two-tier guardrail)
      - Nightingale-Investor-Analyzer-Weekly    (Monday 8:00 local — investor persona refinement, chains pitch-deck-updater)
      - Nightingale-Investor-Newsletter-Biweekly (every other Friday 9:00 local — biweekly investor update draft)

    Each task invokes the `claude` CLI headlessly from the cloned repo directory
    with the appropriate trigger phrase.

.PREREQUISITES
    - Claude Code installed and on PATH (the `claude` command must be runnable from a fresh shell)
    - The ClinicalTrials.gov MCP connector authorized (both sweeps + resurfacer + daily-brief)
    - The Apollo.io MCP connector authorized (commercial sweep + resurfacer + daily-brief read-only)
    - The Gmail MCP connector authorized (resurfacer + daily-brief + hubspot-manager)
    - The Google Calendar MCP connector authorized (daily-brief only)
    - The Google Drive MCP connector authorized (feedback-analyzer + hubspot-manager — both read the team-shared call transcripts folder)
    - The HubSpot MCP connector authorized — REQUIRED for hubspot-manager nightly writes, read-only for resurfacer + daily-brief annotation. See 06-agent documentation/signal-watcher-setup.md "HubSpot Manager" section for the OAuth setup walkthrough.
    - For intro-finder: ~/.nightingale/secrets.json populated via scripts/setup-secrets.ps1
    - For daily-brief Layer-B (optional): the same secrets file with apify_company_roster_actor_id set
    - Internet access from this machine during scheduled times

.NOTES
    To uninstall:  Unregister-ScheduledTask -TaskName 'Nightingale-Daily-Brief-Morning','Nightingale-Commercial-Sweep','Nightingale-Academic-Sweep','Nightingale-Intro-Finder-Morning','Nightingale-Gmail-Resurfacer-Morning','Nightingale-HubSpot-Manager-Nightly','Nightingale-Investor-Analyzer-Weekly','Nightingale-Investor-Newsletter-Biweekly' -Confirm:$false
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

# --- HubSpot manager nightly (Mon-Sun 11pm — fires before midnight rollover so the run is dated correctly for the next morning's daily-brief pickup) ---
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
    -Description 'Nightingale HubSpot manager: nightly Mon-Sun 11pm local. Reads last 24h of Granola transcripts + Gmail replies and writes to HubSpot under a two-tier guardrail. Auto-applies up to 20 low-risk items per night (call/email logging, summary notes, populate-empty contact metadata); queues everything else for next-morning approval via the daily-brief pending section.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-HubSpot-Manager-Nightly"

# --- Investor analyzer weekly (Monday 8am — after the 7am sweeps; chains pitch-deck-updater) ---
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
    -Description 'Nightingale investor-analyzer: weekly Monday 8am local. Reads investor call transcripts + investor email replies, proposes diffs to investor-persona.md (Desktop, propose-only), then chains pitch-deck-updater to refresh the deck-edit approval queue.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Investor-Analyzer-Weekly"

# --- Investor newsletter biweekly (every other Friday 9am) ---
# WeeksInterval 2 anchors the every-other-week cadence to the first fire after registration.
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
    -Description 'Nightingale investor-newsletter: biweekly Friday 9am local. Summarizes HubSpot changes since the last newsletter + internal-team transcripts into an investor update, builds the recipient roster, and queues it for approval. On approval it creates one unsent BCC Gmail draft (never sends).' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Investor-Newsletter-Biweekly"

Write-Host ""
Write-Host "Done. Verify with:  Get-ScheduledTask -TaskName 'Nightingale-*'"
Write-Host "Next daily-brief run:      next upcoming Mon-Fri at 6:00 AM local time."
Write-Host "Next sweep run:            next upcoming Monday at 7:00 AM local time."
Write-Host "Next intro-finder run:     next upcoming Sun-Fri at 7:00 AM local time."
Write-Host "Next resurfacer run:       next upcoming Mon-Fri at 7:00 AM local time."
Write-Host "Next hubspot-manager run:  next upcoming day at 11:00 PM local time (Mon-Sun)."
Write-Host "Next investor-analyzer run: next upcoming Monday at 8:00 AM local time (chains pitch-deck-updater)."
Write-Host "Next investor-newsletter run: next upcoming Friday at 9:00 AM local time, then every 2 weeks."
Write-Host "Outputs land in: $HOME\Desktop\nightingale-signals\{commercial|academic|resurfacer|daily-brief|hubspot-manager|investor-insights|pitch-deck|investor-newsletter}\..."
Write-Host ""
Write-Host "If you have not yet run scripts/setup-secrets.ps1, intro-finder will skip the"
Write-Host "Apify lookup step and write a SECRETS_MISSING-<date>.md notice. Run it before"
Write-Host "the next Sunday-Thursday 7am if you want intros to fire."
Write-Host ""
Write-Host "If the Gmail MCP connector is not authorized in Claude Code, the resurfacer"
Write-Host "will skip cleanly and write a GMAIL_NOT_AUTHORIZED-<date>.md notice instead."
Write-Host ""
Write-Host "If the Google Calendar MCP connector is not authorized in Claude Code, the"
Write-Host "daily-brief will skip cleanly and write a CALENDAR_NOT_AUTHORIZED-<date>.md notice."
Write-Host "Daily-brief Layer-B persona-roster lookup uses the optional"
Write-Host "apify_company_roster_actor_id from secrets.json; without it, Layer-B falls back"
Write-Host "to WebSearch (free, lower coverage). Add the Actor via scripts/setup-secrets.ps1."
Write-Host ""
Write-Host "If the HubSpot MCP connector is not authorized in Claude Code, the hubspot-manager"
Write-Host "will skip cleanly each night and write a detailed HUBSPOT_NOT_AUTHORIZED-<date>.md"
Write-Host "notice on your Desktop containing step-by-step OAuth setup instructions. See also:"
Write-Host "06-agent documentation/signal-watcher-setup.md 'HubSpot Manager' section."
Write-Host ""
Write-Host "Investor loop: pitch-deck-updater needs a deck pointer (pitch_deck_drive_file_id)."
Write-Host "Run scripts/setup-secrets.ps1 and paste your pitch deck's Google Drive file ID/URL"
Write-Host "when prompted (schema v4). Without it, the weekly chain writes a DECK_POINTER_MISSING"
Write-Host "notice and skips cleanly. Review pitch-deck edits + the investor newsletter draft in"
Write-Host "the optional UI dashboard (ui/) under 'Pitch Deck Edits' and 'Investor Newsletter'."
