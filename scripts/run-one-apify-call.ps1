<#
.SYNOPSIS
    Performs a single Apify-driven LinkedIn mutual-connections lookup for one target,
    and writes the result JSON to disk. Invoked by an OS one-shot task scheduled by
    the intro-finder morning agent.

.PARAMETER Side
    'commercial' or 'academic'. Determines sentinel paths and is recorded in the
    result for downstream delivery aggregation.

.PARAMETER TargetUrl
    The LinkedIn profile URL of the target (the person we want mutual connections
    against).

.PARAMETER TargetMetaPath
    Path to a small JSON file written by the morning agent containing the target's
    metadata (name, title, company, role_bucket, signal_tier, buying_group_source).

.PARAMETER ResultPath
    Where to write the result JSON. Convention:
    ~/Desktop/nightingale-signals/{side}/intros/daily-results/{date}/{slug}.json

.PARAMETER ActorId
    The Apify Actor ID to invoke. Default: $env:NIGHTINGALE_APIFY_ACTOR or
    'apimaestro/linkedin-profile-batch-scraper' as placeholder (replace with the
    actual mutual-connections actor when pinned).

.NOTES
    Never logs the LinkedIn cookie value. Detects cookie-expired conditions and
    writes sentinel files so the morning agent can short-circuit subsequent calls.
#>

param(
    [Parameter(Mandatory=$true)] [string]$Side,
    [Parameter(Mandatory=$true)] [string]$TargetUrl,
    [Parameter(Mandatory=$true)] [string]$TargetMetaPath,
    [Parameter(Mandatory=$true)] [string]$ResultPath,
    [string]$ActorId = $(if ($env:NIGHTINGALE_APIFY_ACTOR) { $env:NIGHTINGALE_APIFY_ACTOR } else { 'apimaestro~linkedin-profile-batch-scraper' })
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
    $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultPath -Encoding utf8
}

function Load-Meta {
    try {
        return Get-Content $TargetMetaPath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

$meta = Load-Meta
$base = [ordered]@{
    side                 = $Side
    target_url           = $TargetUrl
    target_meta          = $meta
    actor_id             = $ActorId
    invoked_at           = (Get-Date -Format 'o')
    status               = $null
    apify_run_id         = $null
    mutuals              = @()
    error                = $null
}

# Secrets missing?
if (-not (Test-Path $secretsPath)) {
    $base.status = 'secrets_missing'
    $base.error  = "Secrets file not found at $secretsPath. Run scripts/setup-secrets first."
    Write-Result $base
    exit 0
}

# Sentinel active?
if (Test-Path $sentinelActive) {
    $base.status = 'skipped_cookie_expired'
    $base.error  = 'Cookie-expired sentinel active. Re-run scripts/setup-secrets.'
    Write-Result $base
    exit 0
}

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
    $base.error  = 'Missing apify_api_token or linkedin_li_at in secrets file.'
    Write-Result $base
    exit 0
}

# Kick off Apify run
$runStartUri = "https://api.apify.com/v2/acts/$ActorId/runs?token=$apifyToken"
$runInput = @{
    targetUrl          = $TargetUrl
    sessionCookie      = $liAt
    proxyConfiguration = @{
        useApifyProxy     = $true
        apifyProxyGroups  = @('RESIDENTIAL')
    }
}

$runId = $null
try {
    $startResp = Invoke-RestMethod -Uri $runStartUri -Method Post `
        -Body ($runInput | ConvertTo-Json -Depth 5) `
        -ContentType 'application/json' `
        -TimeoutSec 30
    $runId = $startResp.data.id
    if (-not $runId) { throw "Apify did not return a run id" }
} catch {
    $base.status = 'apify_start_failed'
    $base.error  = "Could not start Apify run: $($_.Exception.Message)"
    Write-Result $base
    exit 0
}

$base.apify_run_id = $runId

# Poll for completion (exponential backoff, 5s -> 30s cap, ~3min total)
$delay      = 5
$totalSlept = 0
$maxTotal   = 180
$status     = $null
while ($totalSlept -lt $maxTotal) {
    Start-Sleep -Seconds $delay
    $totalSlept += $delay
    try {
        $runStatus = Invoke-RestMethod -Uri "https://api.apify.com/v2/acts/$ActorId/runs/$runId`?token=$apifyToken" -Method Get -TimeoutSec 20
        $status = $runStatus.data.status
        if ($status -in @('SUCCEEDED', 'FAILED', 'ABORTED', 'TIMED-OUT', 'TIMEOUT')) { break }
    } catch {
        # transient; keep polling
    }
    if ($delay -lt 30) { $delay = [Math]::Min($delay * 2, 30) }
}

if ($status -ne 'SUCCEEDED') {
    $base.status = 'apify_run_not_succeeded'
    $base.error  = "Apify run finished with status: $status (after $totalSlept seconds)"
    Write-Result $base
    exit 0
}

# Fetch dataset items
try {
    $items = Invoke-RestMethod -Uri "https://api.apify.com/v2/acts/$ActorId/runs/$runId/dataset/items?token=$apifyToken" -Method Get -TimeoutSec 30
} catch {
    $base.status = 'apify_fetch_failed'
    $base.error  = "Could not fetch dataset items: $($_.Exception.Message)"
    Write-Result $base
    exit 0
}

# Detect cookie expiry signals (Actor-specific; common indicators)
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
if (-not $items -or ($items -is [array] -and $items.Count -eq 0)) {
    # Empty result alone is ambiguous; combined with the absence of a successful
    # auth, the Actor would typically return at least a structural row. We only
    # flag cookie-expired when explicit indicators appear in payload.
}

if ($flagged) {
    # Write sentinel files so subsequent calls/morning routines can short-circuit
    try {
        New-Item -ItemType File -Path $sentinelActive -Force | Out-Null
        $sentinelDir = Split-Path -Parent $sentinelToday
        if (-not (Test-Path $sentinelDir)) { New-Item -ItemType Directory -Path $sentinelDir -Force | Out-Null }
        New-Item -ItemType File -Path $sentinelToday -Force | Out-Null
    } catch {
        # best-effort; do not fail the result write
    }
    $base.status = 'cookie_expired'
    $base.error  = 'Apify Actor returned auth-failure indicators. Cookie sentinel set.'
    Write-Result $base
    exit 0
}

# Normalize + dedupe mutuals
$mutuals = @()
$seen = @{}
foreach ($i in @($items)) {
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
    $company = $i.company
    if (-not $company) { $company = $i.currentCompany }
    if (-not $company) { $company = $i.companyName }

    if (-not $url -and -not $name) { continue }
    $key = if ($url) { $url } else { $name }
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true

    $mutuals += [ordered]@{
        name            = $name
        url             = $url
        current_title   = $title
        current_company = $company
    }
}

$base.status  = 'succeeded'
$base.mutuals = $mutuals
Write-Result $base
exit 0
