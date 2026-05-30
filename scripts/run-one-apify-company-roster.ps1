<#
.SYNOPSIS
    Performs a single Apify-driven LinkedIn company-employees lookup for one
    company, filters the result client-side to persona-matching titles, and
    writes the result JSON to disk. Invoked synchronously by the daily-brief
    morning agent for Layer-B intro discovery.

.PARAMETER CompanyName
    The target company name (free text; matched against the chosen Actor's
    `companyName` or `companyUrl` input depending on its schema).

.PARAMETER PersonaTitleRegex
    Regex used client-side to keep only persona-matching titles. Example:
    '(?i)(CEO|CFO|COO|CMO|VP\s+Clinical|Director.*Clinical|Principal Investigator|PI|Department\s+Chair|CISO|HIPAA)'

.PARAMETER ResultPath
    Where to write the result JSON. Convention:
    ~/Desktop/nightingale-signals/daily-brief/state/roster-runs/{date}/{slug}.json

.PARAMETER ActorId
    Optional override. If omitted, reads `apify_company_roster_actor_id` from
    secrets.json. Env var NIGHTINGALE_APIFY_ROSTER_ACTOR also overrides
    (priority: param > env var > secrets).

.NOTES
    - Sibling of run-one-apify-call.ps1. Same conventions: header auth (token
      never in URL), atomic write via .tmp + Move-Item, same status taxonomy
      for 404 / 429 / cookie-expiry / generic failures.
    - The Layer-B Actor ID lives in secrets.json schema v3 as an OPTIONAL
      field. If absent, the daily-brief agent falls back to WebSearch and
      does not invoke this script.
    - Cookie discipline: reads linkedin_li_at from secrets.json but never
      logs / echoes the value. Worker-only access; the agent never reads it.

    Requires Windows + PowerShell 5.1+.
#>

param(
    [Parameter(Mandatory=$true)] [string]$CompanyName,
    [Parameter(Mandatory=$true)] [string]$PersonaTitleRegex,
    [Parameter(Mandatory=$true)] [string]$ResultPath,
    [string]$ActorId = $null
)

$ErrorActionPreference = 'Stop'

$secretsDir          = Join-Path $env:USERPROFILE '.nightingale'
$secretsPath         = Join-Path $secretsDir 'secrets.json'
$sentinelActive      = Join-Path $secretsDir '.cookie-expired-active'
$today               = (Get-Date -Format 'yyyy-MM-dd')
$sentinelToday       = Join-Path $env:USERPROFILE "Desktop\nightingale-signals\.cookie-expired-$today"

function Write-Result($payload) {
    $dir = Split-Path -Parent $ResultPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Atomic write: tmp file then Move-Item. Same convention as the sibling
    # mutual-connections worker.
    $tmpPath = "$ResultPath.tmp"
    $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $tmpPath -Encoding utf8
    Move-Item -Path $tmpPath -Destination $ResultPath -Force
}

$base = [ordered]@{
    company_name       = $CompanyName
    persona_regex      = $PersonaTitleRegex
    actor_id           = $null
    invoked_at         = (Get-Date -Format 'o')
    status             = $null
    apify_run_id       = $null
    employees_total    = 0
    employees          = @()
    error              = $null
}

# --- Secrets missing? --------------------------------------------------------
if (-not (Test-Path $secretsPath)) {
    $base.status = 'secrets_missing'
    $base.error  = "Secrets file not found at $secretsPath. Run scripts/setup-secrets.ps1 first."
    Write-Result $base
    exit 0
}

# --- Sentinel active? --------------------------------------------------------
if (Test-Path $sentinelActive) {
    $base.status = 'skipped_cookie_expired'
    $base.error  = 'Cookie-expired sentinel active. Re-run scripts/setup-secrets.ps1 to refresh.'
    Write-Result $base
    exit 0
}

# --- Read secrets ------------------------------------------------------------
try {
    $secrets = Get-Content $secretsPath -Raw | ConvertFrom-Json
} catch {
    $base.status = 'secrets_unreadable'
    $base.error  = "Could not parse $secretsPath : $($_.Exception.Message)"
    Write-Result $base
    exit 0
}

$apifyToken = $secrets.apify_api_token
$liAt       = $secrets.linkedin_li_at
if ([string]::IsNullOrWhiteSpace($apifyToken) -or [string]::IsNullOrWhiteSpace($liAt)) {
    $base.status = 'secrets_incomplete'
    $base.error  = 'Missing apify_api_token or linkedin_li_at in secrets file. Re-run scripts/setup-secrets.ps1.'
    Write-Result $base
    exit 0
}

# Actor ID resolution: param > env > secrets.apify_company_roster_actor_id
if ([string]::IsNullOrWhiteSpace($ActorId)) {
    if ($env:NIGHTINGALE_APIFY_ROSTER_ACTOR) {
        $ActorId = $env:NIGHTINGALE_APIFY_ROSTER_ACTOR
    } elseif ($secrets.apify_company_roster_actor_id) {
        $ActorId = $secrets.apify_company_roster_actor_id
    }
}
if ([string]::IsNullOrWhiteSpace($ActorId)) {
    $base.status = 'actor_id_missing'
    $base.error  = 'No company-roster Apify Actor ID resolved. Run scripts/setup-secrets.ps1 to add apify_company_roster_actor_id, or set NIGHTINGALE_APIFY_ROSTER_ACTOR env var. The daily-brief agent will fall back to WebSearch when this status is seen.'
    Write-Result $base
    exit 0
}
$base.actor_id = $ActorId

# --- Start Apify run (header auth; no token in URL) -------------------------
# Different Actors expect different input keys. Pass commonly-accepted ones
# so most LinkedIn-company-employees Actors recognize at least one. The
# operator can swap the Actor freely without editing this script as long as
# it accepts companyName, companyUrl, or company.
$headers = @{ Authorization = "Bearer $apifyToken" }
$runInput = @{
    companyName        = $CompanyName
    companyUrl         = $CompanyName
    company            = $CompanyName
    sessionCookie      = $liAt
    proxyConfiguration = @{
        useApifyProxy    = $true
        apifyProxyGroups = @('RESIDENTIAL')
    }
}

$runId = $null
try {
    $startResp = Invoke-RestMethod `
        -Uri "https://api.apify.com/v2/acts/$ActorId/runs" `
        -Headers $headers -Method Post `
        -Body ($runInput | ConvertTo-Json -Depth 5) `
        -ContentType 'application/json' `
        -TimeoutSec 30
    $runId = $startResp.data.id
    if (-not $runId) { throw 'Apify did not return a run id' }
} catch {
    $msg = $_.Exception.Message
    if ($msg -match '404') {
        $base.status = 'apify_actor_not_found'
        $base.error  = "Actor '$ActorId' not found in your Apify account. Verify in https://console.apify.com/actors and re-run scripts/setup-secrets.ps1 to update apify_company_roster_actor_id."
    } elseif ($msg -match '429') {
        $retryAfter = $null
        try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch {}
        $base.status = 'apify_rate_limited'
        $base.error  = "Apify rate-limited (429). Retry-After: $retryAfter. Likely hit free-tier monthly quota."
    } else {
        $base.status = 'apify_start_failed'
        $base.error  = "Could not start Apify run: $msg"
    }
    Write-Result $base
    exit 0
}
$base.apify_run_id = $runId

# --- Poll for completion (5s -> 30s cap, ~3min total) -----------------------
$delay      = 5
$totalSlept = 0
$maxTotal   = 180
$status     = $null
while ($totalSlept -lt $maxTotal) {
    Start-Sleep -Seconds $delay
    $totalSlept += $delay
    try {
        $runStatus = Invoke-RestMethod `
            -Uri "https://api.apify.com/v2/acts/$ActorId/runs/$runId" `
            -Headers $headers -Method Get -TimeoutSec 20
        $status = $runStatus.data.status
        if ($status -in @('SUCCEEDED','FAILED','ABORTED','TIMED-OUT','TIMEOUT')) { break }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '429') {
            $base.status = 'apify_rate_limited'
            $base.error  = "Apify rate-limited (429) mid-poll. Run $runId orphaned."
            Write-Result $base
            exit 0
        }
        # other transients: keep polling
    }
    if ($delay -lt 30) { $delay = [Math]::Min($delay * 2, 30) }
}

if ($status -ne 'SUCCEEDED') {
    $base.status = 'apify_run_not_succeeded'
    $base.error  = "Apify run finished with status: $status (after $totalSlept seconds)"
    Write-Result $base
    exit 0
}

# --- Fetch dataset items -----------------------------------------------------
try {
    $items = Invoke-RestMethod `
        -Uri "https://api.apify.com/v2/acts/$ActorId/runs/$runId/dataset/items" `
        -Headers $headers -Method Get -TimeoutSec 30
} catch {
    $msg = $_.Exception.Message
    if ($msg -match '429') {
        $base.status = 'apify_rate_limited'
        $base.error  = "Apify rate-limited (429) fetching dataset. Run $runId orphaned."
    } else {
        $base.status = 'apify_fetch_failed'
        $base.error  = "Could not fetch dataset items: $msg"
    }
    Write-Result $base
    exit 0
}

# --- Detect cookie-expiry indicators in payload -----------------------------
$flagged = $false
if ($items -is [array] -and $items.Count -gt 0) {
    foreach ($i in $items) {
        $iJson = ($i | ConvertTo-Json -Depth 4 -Compress)
        if ($iJson -match '(?i)(loginRequired|captcha|restricted|authwall|please[ _-]?log[ _-]?in)') {
            $flagged = $true
            break
        }
    }
}

if ($flagged) {
    try {
        New-Item -ItemType File -Path $sentinelActive -Force | Out-Null
        $sentinelDir = Split-Path -Parent $sentinelToday
        if (-not (Test-Path $sentinelDir)) {
            New-Item -ItemType Directory -Path $sentinelDir -Force | Out-Null
        }
        New-Item -ItemType File -Path $sentinelToday -Force | Out-Null
    } catch {
        # Best-effort; do not fail the result write.
    }
    $base.status = 'cookie_expired'
    $base.error  = 'Apify Actor returned auth-failure indicators. Cookie sentinel set.'
    Write-Result $base
    exit 0
}

# --- Normalize + filter to persona-matching titles --------------------------
$employees = @()
$seen = @{}
$allCount = 0
foreach ($i in @($items)) {
    $allCount++
    # Best-effort field extraction; Actor schemas vary.
    $name = $i.name
    if (-not $name) { $name = $i.fullName }
    if (-not $name) { $name = $i.full_name }
    $url  = $i.url
    if (-not $url)  { $url  = $i.profileUrl }
    if (-not $url)  { $url  = $i.linkedinUrl }
    $title = $i.title
    if (-not $title) { $title = $i.headline }
    if (-not $title) { $title = $i.currentTitle }
    if (-not $title) { $title = $i.jobTitle }
    $company = $i.company
    if (-not $company) { $company = $i.currentCompany }
    if (-not $company) { $company = $i.companyName }
    if (-not $company) { $company = $CompanyName }

    if (-not $name -and -not $url) { continue }
    if (-not $title) { continue }

    # Apply persona regex filter — only retain titles that match.
    if ($title -notmatch $PersonaTitleRegex) { continue }

    $key = if ($url) { $url } else { "$name|$title" }
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true

    $employees += [ordered]@{
        name            = $name
        title           = $title
        company         = $company
        linkedin_url    = $url
        persona_bucket  = $null
    }
}

$base.status          = 'succeeded'
$base.employees_total = $employees.Count
$base.employees       = $employees
Write-Result $base
exit 0
