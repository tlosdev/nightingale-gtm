<#
.SYNOPSIS
    Removes the legacy Windows Task Scheduler entries that drove the Nightingale
    agent chain BEFORE Phase 3 moved scheduling to GitHub Actions.

.DESCRIPTION
    Phase 3 migration step. After you install the self-hosted GitHub Actions
    runner (scripts/install-runner.ps1), the eight agent schedules live in
    .github/workflows/ and fire via GitHub cron. The old Task Scheduler entries
    must be removed or BOTH systems will fire each agent - double runs.

    This script unregisters exactly the eight legacy agent tasks. It deliberately
    does NOT touch:
      - Nightingale-Boot-Catchup        (Phase 3 on-boot backstop - keep it)
      - Nightingale-Intro-*-<target>    (per-target Apify one-shots the
                                         intro-finder agent creates dynamically -
                                         these stay on Task Scheduler by design)

    Safe to run before OR after install-runner.ps1, and safe to re-run (a missing
    task is reported, not an error).

.PARAMETER WhatIf
    Show which tasks WOULD be removed without removing them.

.NOTES
    Windows-only. No elevation required (these are per-user tasks).
#>
param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# The eight legacy agent tasks registered by the pre-Phase-3 install-schedule.ps1.
# Listed explicitly (NOT a wildcard) so we never remove the Phase-3 boot-catchup
# task or the dynamic intro-finder one-shots.
$legacyTasks = @(
    'Nightingale-Daily-Brief-Morning',
    'Nightingale-Commercial-Sweep',
    'Nightingale-Academic-Sweep',
    'Nightingale-Intro-Finder-Morning',
    'Nightingale-Gmail-Resurfacer-Morning',
    'Nightingale-HubSpot-Manager-Nightly',
    'Nightingale-Investor-Analyzer-Weekly',
    'Nightingale-Investor-Newsletter-Biweekly'
)

$removed = 0
$missing = 0
foreach ($name in $legacyTasks) {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "  (not present) $name"
        $missing++
        continue
    }
    if ($WhatIf) {
        Write-Host "  [whatif] would remove $name"
        continue
    }
    try {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Host "  removed   $name"
        $removed++
    } catch {
        Write-Warning "  failed to remove ${name}: $($_.Exception.Message)"
    }
}

Write-Host ''
if ($WhatIf) {
    Write-Host "Dry run complete. Re-run without -WhatIf to remove the legacy tasks."
} else {
    Write-Host "Done. Removed $removed legacy task(s); $missing already absent."
    Write-Host "Agent scheduling now runs via GitHub Actions (.github/workflows/) on the"
    Write-Host "self-hosted runner. Verify the runner: Get-Service 'actions.runner.*'"
    Write-Host "Verify no legacy agent tasks remain: Get-ScheduledTask -TaskName 'Nightingale-*'"
    Write-Host "(You should see only Nightingale-Boot-Catchup and any dynamic intro one-shots.)"
}
