<#
.SYNOPSIS
    Captures the user's Apify API token, Apify Actor ID, LinkedIn profile URL (for
    validation), and LinkedIn li_at cookie. Validates all of them against Apify in
    one round-trip, then writes ~/.nightingale/secrets.json with a restricted ACL.

.DESCRIPTION
    One-time per-user setup for the intro-finder agent. Re-run to rotate any
    individual secret; existing values are preserved unless you choose to overwrite.

    Validation flow:
      1. Apify API token  -> GET /v2/users/me (header auth).
      2. Apify Actor ID   -> exists and is callable by this account.
      3. LinkedIn li_at   -> one Actor run against YOUR own LinkedIn profile URL.
                             Costs ~$0.01-0.05 in Apify credit. Worth it: cookie
                             validation catches bad creds at setup, not Monday morning.

.NOTES
    Secrets file lives outside the repo: $env:USERPROFILE\.nightingale\secrets.json
    Cannot be accidentally git-add'd.

    Requires Windows + PowerShell 5.1+.
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

$secretsDir  = Join-Path $env:USERPROFILE '.nightingale'
$secretsPath = Join-Path $secretsDir 'secrets.json'

# --- Ensure ~/.nightingale exists with restrictive ACL -----------------------
if (-not (Test-Path $secretsDir)) {
    New-Item -ItemType Directory -Path $secretsDir | Out-Null
}
try {
    $acl = Get-Acl $secretsDir
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$env:USERDOMAIN\$env:USERNAME",
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $secretsDir -AclObject $acl
} catch {
    Write-Warning "Could not lock down ACL on ${secretsDir}: $($_.Exception.Message)"
    Write-Warning "Continuing; please verify file permissions manually."
}

# --- Load existing secrets ---------------------------------------------------
$existing = $null
if (Test-Path $secretsPath) {
    try {
        $existing = Get-Content $secretsPath -Raw | ConvertFrom-Json
        Write-Host "Existing secrets file found at $secretsPath."
        if ($existing.schema_version -lt 2) {
            Write-Host "Schema v1 -> v2 upgrade: prompting for missing fields (apify_actor_id, apify_validation_url)."
        }
    } catch {
        Write-Warning "Existing secrets file is unreadable ($($_.Exception.Message)); will overwrite."
        $existing = $null
    }
} else {
    Write-Host "Creating new secrets file at $secretsPath."
}

# --- Helper: masked input ----------------------------------------------------
function Read-MaskedString([string]$prompt) {
    $secure = Read-Host -AsSecureString $prompt
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
    }
}

# --- Decide which fields to (re)prompt --------------------------------------
$promptApify        = $true
$promptActor        = $true
$promptValidationUrl = $true
$promptLiAt         = $true

if ($existing) {
    if ($existing.apify_api_token) {
        $resp = Read-Host "Overwrite existing apify_api_token? [y/N]"
        $promptApify = ($resp -match '^[Yy]')
    }
    if ($existing.apify_actor_id) {
        $resp = Read-Host "Overwrite existing apify_actor_id? [y/N]"
        $promptActor = ($resp -match '^[Yy]')
    } else {
        Write-Host "No apify_actor_id on file (v1 secrets); will prompt."
    }
    if ($existing.apify_validation_url) {
        $resp = Read-Host "Overwrite existing apify_validation_url? [y/N]"
        $promptValidationUrl = ($resp -match '^[Yy]')
    } else {
        Write-Host "No apify_validation_url on file (v1 secrets); will prompt."
    }
    if ($existing.linkedin_li_at) {
        $resp = Read-Host "Overwrite existing linkedin_li_at? [y/N]"
        $promptLiAt = ($resp -match '^[Yy]')
    }
}

# --- Prompt: Apify API token ------------------------------------------------
$apifyToken = if ($existing) { $existing.apify_api_token } else { $null }
if ($promptApify) {
    Write-Host ''
    Write-Host 'Apify API token'
    Write-Host '---'
    Write-Host 'Get yours from: https://console.apify.com/account/integrations'
    Write-Host ''
    $apifyToken = (Read-MaskedString 'Paste Apify API token (input hidden)').Trim()
    if ([string]::IsNullOrWhiteSpace($apifyToken)) {
        Write-Error 'Empty Apify token. Aborting.'
        exit 1
    }
}

# --- Prompt: Apify Actor ID -------------------------------------------------
$actorId = if ($existing) { $existing.apify_actor_id } else { $null }
if ($promptActor) {
    Write-Host ''
    Write-Host 'Apify Actor ID for LinkedIn mutual-connections lookup'
    Write-Host '---'
    Write-Host 'Browse the Apify store: https://apify.com/store?search=linkedin+mutual+connections'
    Write-Host 'Pick a maintained LinkedIn-mutual-connections Actor and paste its identifier here.'
    Write-Host 'Format: "{username}~{actor-name}", e.g. apimaestro~linkedin-mutual-connections'
    Write-Host ''
    $actorId = (Read-Host 'Apify Actor ID').Trim()
    if ([string]::IsNullOrWhiteSpace($actorId)) {
        Write-Error 'Empty Actor ID. Aborting.'
        exit 1
    }
}

# --- Prompt: validation URL (your own LinkedIn profile) ---------------------
$validationUrl = if ($existing) { $existing.apify_validation_url } else { $null }
if ($promptValidationUrl) {
    Write-Host ''
    Write-Host 'Your own LinkedIn profile URL (for cookie+Actor validation)'
    Write-Host '---'
    Write-Host 'This is used ONLY at setup time and only to validate that the Actor can be'
    Write-Host 'called with your cookie. Example: https://linkedin.com/in/your-slug'
    Write-Host ''
    $validationUrl = (Read-Host 'Your LinkedIn profile URL').Trim()
    if ([string]::IsNullOrWhiteSpace($validationUrl)) {
        Write-Error 'Empty validation URL. Aborting.'
        exit 1
    }
}

# --- Prompt: LinkedIn li_at cookie ------------------------------------------
$liAt = if ($existing) { $existing.linkedin_li_at } else { $null }
if ($promptLiAt) {
    Write-Host ''
    Write-Host 'LinkedIn li_at cookie'
    Write-Host '---'
    Write-Host '1. Open Chrome -> linkedin.com (log in if needed)'
    Write-Host "2. Press F12 -> DevTools -> 'Application' tab"
    Write-Host '3. Left sidebar: Storage -> Cookies -> https://www.linkedin.com'
    Write-Host "4. Find the row named 'li_at' and copy the Value column"
    Write-Host ''
    $liAt = (Read-MaskedString 'Paste li_at value (input hidden)').Trim()
    if ([string]::IsNullOrWhiteSpace($liAt)) {
        Write-Error 'Empty li_at value. Aborting.'
        exit 1
    }
}

# --- Validate: Apify API token via /v2/users/me -----------------------------
Write-Host ''
Write-Host 'Validating Apify API token...'
try {
    $headers = @{ Authorization = "Bearer $apifyToken" }
    $userResp = Invoke-RestMethod -Uri 'https://api.apify.com/v2/users/me' -Headers $headers -Method Get -TimeoutSec 15
    if (-not $userResp.data -or -not $userResp.data.id) {
        throw 'Unexpected response shape from /v2/users/me'
    }
    $apifyUser = if ($userResp.data.username) { $userResp.data.username } else { '(no username)' }
    Write-Host "Apify token OK (user: $apifyUser)"
} catch {
    Write-Error "Apify token validation failed: $($_.Exception.Message)"
    Write-Error 'Secrets file NOT written. Re-run with a valid token.'
    exit 1
}

# --- Validate: Actor exists + cookie works (single combined run) ------------
Write-Host ''
Write-Host "Validating Actor '$actorId' + cookie by invoking against $validationUrl ..."
Write-Host '(Costs ~$0.01-0.05 in Apify credit. Confirms both pieces in one call.)'

try {
    $headers = @{ Authorization = "Bearer $apifyToken" }
    $runInput = @{
        targetUrl          = $validationUrl
        sessionCookie      = $liAt
        proxyConfiguration = @{
            useApifyProxy    = $true
            apifyProxyGroups = @('RESIDENTIAL')
        }
    } | ConvertTo-Json -Depth 5
    $startResp = Invoke-RestMethod `
        -Uri "https://api.apify.com/v2/acts/$actorId/runs" `
        -Headers $headers -Method Post `
        -Body $runInput -ContentType 'application/json' -TimeoutSec 30
    $runId = $startResp.data.id
    if (-not $runId) { throw 'Apify did not return a run id' }
} catch {
    $msg = $_.Exception.Message
    if ($msg -match '404') {
        Write-Error "Actor '$actorId' not found in your Apify account."
        Write-Error 'Verify in https://console.apify.com/actors and re-run with the correct Actor ID.'
    } else {
        Write-Error "Apify Actor run could not be started: $msg"
    }
    Write-Error 'Secrets file NOT written.'
    exit 1
}

# Poll the validation run (cap 2 minutes)
$delay      = 5
$totalSlept = 0
$maxTotal   = 120
$status     = $null
while ($totalSlept -lt $maxTotal) {
    Start-Sleep -Seconds $delay
    $totalSlept += $delay
    try {
        $runStatus = Invoke-RestMethod `
            -Uri "https://api.apify.com/v2/acts/$actorId/runs/$runId" `
            -Headers $headers -Method Get -TimeoutSec 20
        $status = $runStatus.data.status
        if ($status -in @('SUCCEEDED','FAILED','ABORTED','TIMED-OUT','TIMEOUT')) { break }
    } catch {
        # transient; keep polling
    }
    if ($delay -lt 30) { $delay = [Math]::Min($delay * 2, 30) }
}

if ($status -ne 'SUCCEEDED') {
    Write-Error "Validation Actor run did not succeed (status: $status). Secrets file NOT written."
    Write-Error 'Common cause: bad Actor for this purpose. Try a different one from the Apify store.'
    exit 1
}

# Fetch items and look for auth-failure indicators
try {
    $items = Invoke-RestMethod `
        -Uri "https://api.apify.com/v2/acts/$actorId/runs/$runId/dataset/items" `
        -Headers $headers -Method Get -TimeoutSec 30
} catch {
    Write-Error "Could not fetch validation Actor dataset: $($_.Exception.Message)"
    Write-Error 'Secrets file NOT written.'
    exit 1
}

$flagged = $false
if ($items) {
    $itemsJson = ($items | ConvertTo-Json -Depth 5 -Compress)
    if ($itemsJson -match '(?i)(loginRequired|captcha|restricted|authwall|please[ _-]?log[ _-]?in)') {
        $flagged = $true
    }
}
if ($flagged) {
    Write-Error 'Cookie was rejected by LinkedIn (Actor returned auth-failure indicators).'
    Write-Error "Refresh your li_at cookie from Chrome DevTools and re-run."
    Write-Error 'Secrets file NOT written.'
    exit 1
}
Write-Host 'Cookie + Actor validation OK.'

# --- Write secrets.json (schema v2) -----------------------------------------
$createdAt = if ($existing -and $existing.created_at) { $existing.created_at } else { (Get-Date -Format 'yyyy-MM-dd') }
$updatedAt = (Get-Date -Format 'yyyy-MM-dd')

$secrets = [ordered]@{
    schema_version       = 2
    created_at           = $createdAt
    updated_at           = $updatedAt
    apify_api_token      = $apifyToken
    apify_actor_id       = $actorId
    apify_validation_url = $validationUrl
    linkedin_li_at       = $liAt
}

$json = $secrets | ConvertTo-Json -Depth 5
Set-Content -Path $secretsPath -Value $json -Encoding utf8 -NoNewline

# Lock down file ACL: only current user
try {
    $acl = Get-Acl $secretsPath
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.Access)) { $acl.RemoveAccessRule($r) | Out-Null }
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$env:USERDOMAIN\$env:USERNAME",
        'FullControl',
        'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $secretsPath -AclObject $acl
} catch {
    Write-Warning "Could not lock down ACL on ${secretsPath}: $($_.Exception.Message)"
    Write-Warning 'Please verify file permissions manually.'
}

# --- Clear stale cookie-expired sentinel if present -------------------------
$sentinel = Join-Path $secretsDir '.cookie-expired-active'
if (Test-Path $sentinel) {
    Remove-Item $sentinel -Force
    Write-Host 'Cleared cookie-expired sentinel.'
}

Write-Host ''
Write-Host "Done. Secrets written to: $secretsPath"
Write-Host 'Next intro-finder run (Sun-Thu 7am) will use these credentials.'
