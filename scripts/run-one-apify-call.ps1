<#
.SYNOPSIS
    Performs a single Apify-driven LinkedIn mutual-connections lookup for one target,
    and writes the result JSON to disk. Invoked by an OS one-shot task scheduled by
    the intro-finder morning agent.

.PARAMETER Side
    'commercial' or 'academic'. Determines sentinel paths and is recorded in the
    result for downstream delivery aggregation.

.PARAMETER TargetUrl
    The LinkedIn profile URL of the target.

.PARAMETER TargetMetaPath
    Path to a JSON file with target metadata (name, title, company, role_bucket,
    signal_tier, buying_group_source).

.PARAMETER ResultPath
    Where to write the result JSON. Convention:
    ~/Desktop/nightingale-signals/{side}/intros/daily-results/{date}/{slug}.json

.PARAMETER ActorId
    Optional override. If omitted, reads `apify_actor_id` from secrets.json. Env
    var NIGHTINGALE_APIFY_ACTOR also overrides (priority: param > env var > secrets).

.NOTES
    - Apify token is passed via Authorization header (never URL query) so it does
      not leak into the Windows process command-line.
    - Detects 404 / 429 / cookie-expiry separately and writes distinct result
      statuses so the morning agent can surface actionable errors.
    - Result JSON is written atomically (tmp file + Move-Item).

    Requires Windows + PowerShell 5.1+.
#>

param(
    [Parameter(Mandatory=$true)] [string]$Side,
    [Parameter(Mandatory=$true)] [string]$TargetUrl,
    [Parameter(Mandatory=$true)] [string]$TargetMetaPath,
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
    # Atomic write: tmp file then Move-Item. Prevents the delivery aggregator
    # from seeing a half-written JSON if this process is killed mid-flight.
    $tmpPath = "$ResultPath.tmp"
    $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $tmpPath -Encoding utf8
    Move-Item -Path $tmpPath -Destination $ResultPath -Force
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
    side          = $Side
    target_url    = $TargetUrl
    target_meta   = $meta
    actor_id      = $null
    invoked_at    = (Get-Date -Format 'o')
    status        = $null
    apify_run_id  = $null
    mutuals       = @()
    error         = $null
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

# Actor ID resolution: param > env > secrets
if ([string]::IsNullOrWhiteSpace($ActorId)) {
    if ($env:NIGHTINGALE_APIFY_ACTOR) {
        $ActorId = $env:NIGHTINGALE_APIFY_ACTOR
    } elseif ($secrets.apify_actor_id) {
        $ActorId = $secrets.apify_actor_id
    }
}
if ([string]::IsNullOrWhiteSpace($ActorId)) {
    $base.status = 'actor_id_missing'
    $base.error  = 'No Apify Actor ID resolved. Re-run scripts/setup-secrets.ps1 (or set NIGHTINGALE_APIFY_ACTOR).'
    Write-Result $base
    exit 0
}
$base.actor_id = $ActorId

# --- Start Apify run (header auth; no token in URL) -------------------------
$headers = @{ Authorization = "Bearer $apifyToken" }
$runInput = @{
    targetUrl          = $TargetUrl
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
    # L10 — prefer HTTP status code over message-string matching. Exception
    # message text varies with PowerShell version, proxy interposition, and
    # wrapping conventions; the .NET status code is reliable.
    $statusCode = $null
    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
    if ($statusCode -eq 404) {
        $base.status = 'apify_actor_not_found'
        $base.error  = "Actor '$ActorId' not found in your Apify account (HTTP 404). Verify in https://console.apify.com/actors and re-run scripts/setup-secrets.ps1 to update."
    } elseif ($statusCode -eq 429) {
        $retryAfter = $null
        try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch {}
        $base.status = 'apify_rate_limited'
        $base.error  = "Apify rate-limited (HTTP 429). Retry-After: $retryAfter. Likely hit free-tier monthly quota; intros resume next cycle."
    } else {
        $base.status = 'apify_start_failed'
        $base.error  = "Could not start Apify run (HTTP $statusCode): $($_.Exception.Message)"
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
        # L10 — status-code-based rate-limit detection.
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        if ($statusCode -eq 429) {
            $base.status = 'apify_rate_limited'
            $base.error  = "Apify rate-limited (HTTP 429) mid-poll. Run $runId orphaned."
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
    $statusCode = $null
    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
    if ($statusCode -eq 429) {
        $base.status = 'apify_rate_limited'
        $base.error  = "Apify rate-limited (HTTP 429) fetching dataset. Run $runId orphaned."
    } else {
        $base.status = 'apify_fetch_failed'
        $base.error  = "Could not fetch dataset items (HTTP $statusCode): $($_.Exception.Message)"
    }
    Write-Result $base
    exit 0
}

# --- Detect cookie-expiry indicators in payload -----------------------------
# M3 — top-level field check ONLY, not a full-JSON substring scan. The prior
# version stringified each result and regex-matched against the whole blob,
# which false-positives on legitimate prospect data containing words like
# "restricted" (e.g. "Restricted Stock Plans LLC" or a headline "I help teams
# who feel restricted by manual processes"). A single false-positive sets the
# sentinel and breaks ALL subsequent intro-finder calls until setup-secrets
# is re-run, so the cost of a false-positive is high.
$flagged = $false
if ($items -is [array] -and $items.Count -gt 0) {
    foreach ($i in $items) {
        # Check known auth-failure response shapes explicitly.
        if ($i.loginRequired -eq $true) { $flagged = $true; break }
        if ($i.captcha -eq $true)       { $flagged = $true; break }
        if ($i.authwall -eq $true)      { $flagged = $true; break }
        # Top-level error / message / status / reason fields only.
        foreach ($field in @('error','message','status','reason')) {
            $val = $i.$field
            if ($val -and $val -match '(?i)(authwall|please[ _-]?log[ _-]?in|login required|captcha|cookie expired|session expired|invalid cookie)') {
                $flagged = $true; break
            }
        }
        if ($flagged) { break }
    }
}

if ($flagged) {
    # M4 — Set-Content -Value '' instead of New-Item -Force. New-Item -Force
    # TRUNCATES any pre-existing file at the path. The sentinel path is
    # carefully chosen but defense-in-depth: Set-Content writes only what we
    # explicitly hand it (an empty string).
    try {
        Set-Content -Path $sentinelActive -Value '' -Encoding utf8 -NoNewline
        $sentinelDir = Split-Path -Parent $sentinelToday
        if (-not (Test-Path $sentinelDir)) {
            New-Item -ItemType Directory -Path $sentinelDir -Force | Out-Null
        }
        Set-Content -Path $sentinelToday -Value '' -Encoding utf8 -NoNewline
    } catch {
        # Best-effort; do not fail the result write.
    }
    $base.status = 'cookie_expired'
    $base.error  = 'Apify Actor returned auth-failure indicators. Cookie sentinel set.'
    Write-Result $base
    exit 0
}

# --- Normalize + dedupe mutuals ---------------------------------------------
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
