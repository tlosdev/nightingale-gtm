<#
.SYNOPSIS
    Captures the user's LinkedIn li_at cookie and Apify API token, validates the Apify
    token, and writes both to ~/.nightingale/secrets.json with restricted ACL.

.DESCRIPTION
    One-time per-user setup for the intro-finder agent. Run this once after cloning
    the nightingale repo. Re-run to rotate either secret; existing values are
    preserved unless you choose to overwrite.

    The Apify token is validated immediately against /v2/users/me. The LinkedIn
    cookie is held opaquely and validated on the first intro-finder Apify call
    (Sun-Thu mornings).

.NOTES
    Secrets file lives outside the repo: $env:USERPROFILE\.nightingale\secrets.json
    Cannot be accidentally git-add'd.
#>

$ErrorActionPreference = 'Stop'

$secretsDir  = Join-Path $env:USERPROFILE '.nightingale'
$secretsPath = Join-Path $secretsDir 'secrets.json'

# Ensure directory exists with restrictive ACL
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

# Load existing secrets, if any
$existing = $null
if (Test-Path $secretsPath) {
    try {
        $existing = Get-Content $secretsPath -Raw | ConvertFrom-Json
        Write-Host "Existing secrets file found at $secretsPath."
    } catch {
        Write-Warning "Existing secrets file is unreadable ($($_.Exception.Message)); will overwrite."
        $existing = $null
    }
} else {
    Write-Host "Creating new secrets file at $secretsPath."
}

# Helper: read masked input -> plaintext string
function Read-MaskedString([string]$prompt) {
    $secure = Read-Host -AsSecureString $prompt
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
    }
}

# Decide whether to (re)prompt for each secret
$promptLiAt  = $true
$promptApify = $true
if ($existing -and $existing.linkedin_li_at) {
    $resp = Read-Host "Overwrite existing linkedin_li_at? [y/N]"
    $promptLiAt = ($resp -match '^[Yy]')
}
if ($existing -and $existing.apify_api_token) {
    $resp = Read-Host "Overwrite existing apify_api_token? [y/N]"
    $promptApify = ($resp -match '^[Yy]')
}

# Prompt for LinkedIn li_at
$liAtValue = if ($existing) { $existing.linkedin_li_at } else { $null }
if ($promptLiAt) {
    Write-Host ""
    Write-Host "LinkedIn li_at cookie setup"
    Write-Host "---"
    Write-Host "1. Open Chrome -> linkedin.com (log in if needed)"
    Write-Host "2. Press F12 -> DevTools -> 'Application' tab"
    Write-Host "3. Left sidebar: Storage -> Cookies -> https://www.linkedin.com"
    Write-Host "4. Find the row named 'li_at' and copy the Value column"
    Write-Host ""
    $liAtValue = (Read-MaskedString "Paste li_at value (input hidden)").Trim()
    if ([string]::IsNullOrWhiteSpace($liAtValue)) {
        Write-Error "Empty li_at value. Aborting."
        exit 1
    }
}

# Prompt for Apify token
$apifyToken = if ($existing) { $existing.apify_api_token } else { $null }
if ($promptApify) {
    Write-Host ""
    Write-Host "Apify API token setup"
    Write-Host "---"
    Write-Host "Get your token from: https://console.apify.com/account/integrations"
    Write-Host ""
    $apifyToken = (Read-MaskedString "Paste Apify API token (input hidden)").Trim()
    if ([string]::IsNullOrWhiteSpace($apifyToken)) {
        Write-Error "Empty Apify token. Aborting."
        exit 1
    }
}

# Validate Apify token
Write-Host ""
Write-Host "Validating Apify token..."
try {
    $headers = @{ Authorization = "Bearer $apifyToken" }
    $resp = Invoke-RestMethod -Uri "https://api.apify.com/v2/users/me" -Headers $headers -Method Get -TimeoutSec 15
    if (-not $resp.data -or -not $resp.data.id) {
        throw "Unexpected response shape from /v2/users/me"
    }
    $apifyUser = if ($resp.data.username) { $resp.data.username } else { "(no username)" }
    Write-Host "Apify token OK (user: $apifyUser)"
} catch {
    Write-Error "Apify token validation failed: $($_.Exception.Message)"
    Write-Error "Secrets file NOT written. Re-run with a valid token."
    exit 1
}

Write-Host "LinkedIn li_at not validated here (validated on first intro-finder Apify call)."

# Preserve created_at; bump updated_at to today
$createdAt = if ($existing -and $existing.created_at) { $existing.created_at } else { (Get-Date -Format 'yyyy-MM-dd') }
$updatedAt = (Get-Date -Format 'yyyy-MM-dd')

$secrets = [ordered]@{
    schema_version  = 1
    created_at      = $createdAt
    updated_at      = $updatedAt
    linkedin_li_at  = $liAtValue
    apify_api_token = $apifyToken
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
    Write-Warning "Please verify file permissions manually."
}

# Clear sentinel if it was set previously (the user just refreshed credentials)
$sentinel = Join-Path $secretsDir '.cookie-expired-active'
if (Test-Path $sentinel) {
    Remove-Item $sentinel -Force
    Write-Host "Cleared cookie-expired sentinel."
}

Write-Host ""
Write-Host "Done. Secrets written to: $secretsPath"
Write-Host "Next intro-finder run (Sun-Thu 7am) will use these credentials."
