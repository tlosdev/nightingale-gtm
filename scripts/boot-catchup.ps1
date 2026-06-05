<#
.SYNOPSIS
    Boot catch-up backstop for the Nightingale agent chain (Phase 3).
    On startup, dispatches any scheduled agent that is OVERDUE beyond its normal
    cadence via GitHub workflow_dispatch. Idempotent via a per-agent cursor.

.DESCRIPTION
    Two layers cover a powered-off machine:
      1. PRIMARY (free, not this script): GitHub keeps a fired scheduled run
         queued for an available runner. If the PC was off at the cron time and
         boots later the SAME day, the runner service starts on boot and picks up
         the queued job. Covers same-day misses.
      2. BACKSTOP (this script): for LONGER outages (>~24h), the primary window
         lapses. This script runs on boot (registered by install-runner.ps1 as
         the Nightingale-Boot-Catchup task) and dispatches any agent whose last
         dispatch is older than its cadence, then stamps the cursor so a second
         boot the same day will not re-fire it.

    HONEST SCOPE: this is a COARSE ">cadence" backstop, not a precise
    missed-occurrence scheduler. cadence = the longest normal gap between runs
    (e.g. daily-brief = 3 days to absorb a Fri->Mon weekend). A genuine multi-day
    outage exceeds cadence and triggers exactly one catch-up dispatch per agent.

    Auth: reads github_pat + github_repo from ~/.nightingale/secrets.json
    (schema v5). The PAT needs fine-grained "Actions: read and write" on the
    target repo. If either is missing, the script prints guidance and exits 0
    (non-fatal -- the primary GitHub-queue layer still works).

    Cursor: ~/.nightingale/boot-catchup-cursor.json maps agent -> last dispatch
    date (yyyy-MM-dd). On FIRST run (no cursor) the script seeds every agent to
    today and dispatches NOTHING, so a fresh install never causes a dispatch
    storm.

.PARAMETER DryRun
    Compute + print what WOULD be dispatched without calling GitHub or writing
    the cursor.

.NOTES
    Windows + PowerShell 5.1+. Apify/HubSpot/etc. tokens are never touched here.
    The GitHub PAT is read into memory only to set the Authorization header and
    is never written to disk or logged.
#>
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Agent -> { workflow file, cadence in days }. cadence = longest normal gap.
# Must match the agent set in .github/workflows/ and the UI AGENT_TRIGGERS map.
$agents = @(
    @{ name = 'daily-brief';                workflow = 'daily-brief.yml';                cadence = 3  }  # Mon-Fri (weekend gap)
    @{ name = 'signal-watcher-commercial';  workflow = 'signal-watcher-commercial.yml';  cadence = 7  }  # Mon weekly
    @{ name = 'signal-watcher-academic';    workflow = 'signal-watcher-academic.yml';    cadence = 7  }  # Mon weekly
    @{ name = 'intro-finder';               workflow = 'intro-finder.yml';               cadence = 2  }  # Sun-Fri (Sat gap)
    @{ name = 'gmail-resurfacer';           workflow = 'gmail-resurfacer.yml';           cadence = 3  }  # Mon-Fri (weekend gap)
    @{ name = 'hubspot-manager';            workflow = 'hubspot-manager.yml';            cadence = 2  }  # daily
    @{ name = 'investor-analyzer';          workflow = 'investor-analyzer.yml';          cadence = 7  }  # Mon weekly
    @{ name = 'investor-newsletter';        workflow = 'investor-newsletter.yml';        cadence = 14 }  # biweekly Fri
)

$secretsPath = Join-Path $env:USERPROFILE '.nightingale\secrets.json'
$cursorPath  = Join-Path $env:USERPROFILE '.nightingale\boot-catchup-cursor.json'

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        $raw = Get-Content -Path $path -Raw
        # Strip a leading UTF-8 BOM (PS 5.1 Set-Content -Encoding utf8 writes one).
        if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
        return $raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

# --- Load auth from secrets.json --------------------------------------------
$secrets = Read-JsonFile $secretsPath
$pat  = if ($secrets) { $secrets.github_pat } else { $null }
$repo = if ($secrets) { $secrets.github_repo } else { $null }

if ([string]::IsNullOrWhiteSpace($pat) -or [string]::IsNullOrWhiteSpace($repo)) {
    Write-Host "boot-catchup: github_pat / github_repo not set in secrets.json -- skipping the >24h backstop."
    Write-Host "  (The primary GitHub-queue catch-up still works on boot. To enable this backstop,"
    Write-Host "   run scripts/setup-secrets.ps1 and add a fine-grained PAT + owner/repo.)"
    exit 0
}
if ($repo -notmatch '^[\w.-]+/[\w.-]+$') {
    Write-Host "boot-catchup: github_repo '$repo' is not in owner/repo form -- skipping."
    exit 0
}

$today = Get-Date
$todayStr = $today.ToString('yyyy-MM-dd')

# --- Seed cursor on first run (no dispatch storm) ---------------------------
$cursor = Read-JsonFile $cursorPath
if ($null -eq $cursor) {
    $seed = [ordered]@{}
    foreach ($a in $agents) { $seed[$a.name] = $todayStr }
    if (-not $DryRun) {
        ($seed | ConvertTo-Json) | Out-File -FilePath $cursorPath -Encoding ascii -Force
    }
    Write-Host "boot-catchup: first run -- seeded cursor to $todayStr for all agents, dispatched nothing."
    exit 0
}

# Normalize cursor into a hashtable we can update.
$cursorMap = @{}
foreach ($p in $cursor.PSObject.Properties) { $cursorMap[$p.Name] = $p.Value }

# --- Dispatch helper (REST; PAT in header only, never logged) ---------------
function Invoke-Dispatch([string]$repo, [string]$workflow, [string]$pat) {
    $uri = "https://api.github.com/repos/$repo/actions/workflows/$workflow/dispatches"
    $headers = @{
        Authorization          = "Bearer $pat"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'nightingale-boot-catchup'
    }
    $body = '{"ref":"main"}'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # 204 No Content on success. Invoke-RestMethod throws on non-2xx.
    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType 'application/json' | Out-Null
}

$dispatched = @()
foreach ($a in $agents) {
    $name = $a.name
    $last = $cursorMap[$name]
    $overdue = $true
    if ($last) {
        try {
            $lastDate = [datetime]::ParseExact($last, 'yyyy-MM-dd', $null)
            $gap = ($today.Date - $lastDate.Date).Days
            $overdue = ($gap -ge $a.cadence)
        } catch {
            $overdue = $true  # unparseable cursor -> treat as overdue
        }
    }
    if (-not $overdue) { continue }

    if ($DryRun) {
        Write-Host "[dry-run] would dispatch $name ($($a.workflow)) -- last=$last, cadence=$($a.cadence)d"
        $dispatched += $name
        continue
    }

    try {
        Invoke-Dispatch -repo $repo -workflow $a.workflow -pat $pat
        $cursorMap[$name] = $todayStr
        $dispatched += $name
        Write-Host "boot-catchup: dispatched $name ($($a.workflow)) -- was last $last."
    } catch {
        Write-Warning "boot-catchup: failed to dispatch $name ($($a.workflow)): $($_.Exception.Message)"
    }
}

# --- Persist the cursor ------------------------------------------------------
if (-not $DryRun) {
    $out = [ordered]@{}
    foreach ($a in $agents) { $out[$a.name] = if ($cursorMap.ContainsKey($a.name)) { $cursorMap[$a.name] } else { $todayStr } }
    ($out | ConvertTo-Json) | Out-File -FilePath $cursorPath -Encoding ascii -Force
}

if ($dispatched.Count -eq 0) {
    Write-Host "boot-catchup: nothing overdue. All agents within cadence."
} else {
    Write-Host "boot-catchup: dispatched $($dispatched.Count) overdue agent(s): $($dispatched -join ', ')."
}
exit 0
