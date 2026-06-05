<#
.SYNOPSIS
    Captures the user's Apify API token, Apify Actor ID (mutual-connections),
    LinkedIn profile URL (for validation), LinkedIn li_at cookie, and an
    OPTIONAL second Apify Actor ID for LinkedIn-company-employees scraping
    (powers the daily-brief Layer-B persona-roster lookup), and an OPTIONAL
    pitch-deck Google Drive pointer (powers the pitch-deck-updater agent).
    Validates all REQUIRED fields against Apify in one round-trip, then writes
    ~/.nightingale/secrets.json (schema v5) with a restricted ACL.

.DESCRIPTION
    One-time per-user setup for the intro-finder + daily-brief agents. Re-run
    to rotate any individual secret; existing values are preserved unless you
    choose to overwrite. The company-roster Actor ID is OPTIONAL — leave blank
    to use the daily-brief WebSearch fallback path.

    Validation flow:
      1. Apify API token  -> GET /v2/users/me (header auth).
      2. Apify Actor ID   -> exists and is callable by this account.
      3. LinkedIn li_at   -> one Actor run against YOUR own LinkedIn profile URL.
                             Costs ~$0.01-0.05 in Apify credit. Worth it: cookie
                             validation catches bad creds at setup, not Monday morning.
      4. Company-roster Actor (OPTIONAL) -> not validated at setup time to
                             avoid additional Apify spend; failures surface on
                             first daily-brief Layer-B call with actionable status.

.NOTES
    Secrets file lives outside the repo: $env:USERPROFILE\.nightingale\secrets.json
    Cannot be accidentally git-add'd.

    Requires Windows + PowerShell 5.1+.
#>

$ErrorActionPreference = 'Stop'

# --- PowerShell version check ------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell $($PSVersionTable.PSVersion) detected; this script requires 5.1 or newer."
    Write-Error "Upgrade Windows PowerShell (or install PowerShell 7+) and re-run."
    exit 1
}

# --- claude CLI on PATH check ------------------------------------------------
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Warning "The 'claude' CLI was not found on PATH."
    Write-Warning "setup-secrets.ps1 will continue (secrets are usable without the CLI)"
    Write-Warning "but install-schedule.ps1 will not work until claude is installed."
    Write-Host ''
}

# --- ExecutionPolicy preflight ----------------------------------------------
# Note: scheduled tasks invoke 'powershell.exe -ExecutionPolicy Bypass ...' so
# they will run regardless of CurrentUser policy. This warning is for the user
# who runs the install/setup scripts MANUALLY in a regular PowerShell session
# (where CurrentUser policy applies). If you got here via a Bypass-launched
# session, this script is already running fine and the warning is informational.
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'AllSigned')) {
    Write-Warning "PowerShell ExecutionPolicy for CurrentUser is '$policy'."
    Write-Warning "Scheduled tasks fire via -ExecutionPolicy Bypass and are unaffected,"
    Write-Warning "but if you ever want to manually re-run install-schedule.ps1 or this"
    Write-Warning "script from a plain PowerShell window, you need:"
    Write-Warning "    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    Write-Host ''
}

# --- Scheduled-task presence check (U1) --------------------------------------
# Detect whether install-schedule.ps1 has been run. If no Nightingale-* tasks
# exist, this script will still write secrets correctly, but those secrets sit
# idle until the install-schedule pass happens. Warn so the operator does the
# steps in the right order.
$nightingaleTasks = Get-ScheduledTask -TaskName 'Nightingale-*' -ErrorAction SilentlyContinue
if (-not $nightingaleTasks -or $nightingaleTasks.Count -eq 0) {
    Write-Warning "No 'Nightingale-*' scheduled tasks are registered yet."
    Write-Warning "Run scripts/install-schedule.ps1 BEFORE relying on intro-finder /"
    Write-Warning "daily-brief / hubspot-manager — otherwise the secrets this script"
    Write-Warning "captures will not be read by anything."
    Write-Host ''
}

$secretsDir  = Join-Path $env:USERPROFILE '.nightingale'
$secretsPath = Join-Path $secretsDir 'secrets.json'

# --- Ensure ~/.nightingale exists with restrictive ACL -----------------------
# ACL recovery: if you ever need to restore default permissions on this
# directory or its files (e.g. after a profile / username change), run:
#     icacls "$env:USERPROFILE\.nightingale" /reset /T /C
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
    Write-Warning "Recovery: icacls `"$secretsDir`" /reset /T /C"
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
        if ($existing.schema_version -lt 3) {
            Write-Host "Schema v2 -> v3 upgrade: optional prompt for apify_company_roster_actor_id (powers daily-brief Layer-B)."
        }
        if ($existing.schema_version -lt 4) {
            Write-Host "Schema v3 -> v4 upgrade: optional prompt for pitch_deck_drive_file_id (powers pitch-deck-updater)."
        }
        if ($existing.schema_version -lt 5) {
            Write-Host "Schema v4 -> v5 upgrade: optional prompt for github_pat + github_repo (powers UI Run-now via GitHub workflow_dispatch from Docker/container mode + the boot-catchup backstop)."
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
$promptRosterActor  = $true
$promptDeckPointer  = $true
$promptGithub       = $true

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
    if ($existing.apify_company_roster_actor_id) {
        $resp = Read-Host "Overwrite existing apify_company_roster_actor_id (daily-brief Layer-B)? [y/N]"
        $promptRosterActor = ($resp -match '^[Yy]')
    } else {
        Write-Host "No apify_company_roster_actor_id on file (v2 secrets); will offer optional prompt."
    }
    if ($existing.pitch_deck_drive_file_id) {
        Write-Host "Current pitch_deck_drive_file_id: $($existing.pitch_deck_drive_file_id)"
        $resp = Read-Host "Overwrite existing pitch_deck_drive_file_id (pitch-deck-updater)? [y/N]"
        $promptDeckPointer = ($resp -match '^[Yy]')
    } else {
        Write-Host "No pitch_deck_drive_file_id on file (pre-v4 secrets); will offer optional prompt."
    }
    if ($existing.github_pat -or $existing.github_repo) {
        $resp = Read-Host "Overwrite existing github_pat / github_repo (UI workflow_dispatch + boot-catchup)? [y/N]"
        $promptGithub = ($resp -match '^[Yy]')
    } else {
        Write-Host "No github_pat / github_repo on file (pre-v5 secrets); will offer optional prompt."
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
# Note: this URL is intentionally retained in secrets.json. It is used at
# every re-run of setup-secrets.ps1 (and any future setup-secrets-style
# rotation workflow) to re-validate that the Apify Actor + cookie still work
# without re-prompting. The URL is your own public LinkedIn profile, which is
# already discoverable; no privacy uplift from discarding it.
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
    # U17 — validate the URL is a LinkedIn profile, not someone else's URL
    # or a malformed string. Catches typos before the Apify spend happens.
    if ($validationUrl -notmatch '^https?://([a-z0-9-]+\.)*linkedin\.[a-z.]{2,6}/in/[^/\s?#]+/?$') {
        Write-Error "validation URL does not look like a LinkedIn profile."
        Write-Error "Expected format: https://linkedin.com/in/{your-slug} (ccTLDs like linkedin.co.uk also accepted)"
        Write-Error "Got: $validationUrl"
        Write-Error "Aborting before we burn Apify credit on the wrong target."
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
    Write-Host 'Heads-up: at validation time below, this cookie value is sent to the'
    Write-Host 'Apify Actor you picked above (third-party scraping service). The Actor'
    Write-Host 'uses it to drive a logged-in LinkedIn browser session on your behalf.'
    Write-Host 'This is unavoidable for mutual-connections scraping and violates'
    Write-Host 'LinkedIn ToS. See 06-agent-documentation/signal-watcher-setup.md for'
    Write-Host 'the full ToS / account-safety discussion before continuing.'
    Write-Host ''
    $liAt = (Read-MaskedString 'Paste li_at value (input hidden)').Trim()
    if ([string]::IsNullOrWhiteSpace($liAt)) {
        Write-Error 'Empty li_at value. Aborting.'
        exit 1
    }
}

# --- Prompt: Company-roster Actor ID (OPTIONAL — daily-brief Layer-B) --------
$rosterActorId = if ($existing) { $existing.apify_company_roster_actor_id } else { $null }
if ($promptRosterActor) {
    Write-Host ''
    Write-Host 'OPTIONAL — Apify Actor ID for LinkedIn-company-employees scraping'
    Write-Host '---'
    Write-Host 'Powers the daily-brief agent Layer-B persona-roster lookup, which'
    Write-Host 'surfaces persona-matching colleagues at each meeting attendee''s'
    Write-Host 'company that the attendee could introduce you to.'
    Write-Host ''
    Write-Host 'Browse the Apify store: https://apify.com/store?search=linkedin+company+employees'
    Write-Host 'Pick a maintained LinkedIn-company-employees Actor and paste its identifier.'
    Write-Host 'Format: "{username}~{actor-name}".'
    Write-Host ''
    Write-Host 'Leave blank to use the WebSearch fallback path (cheaper, lower coverage).'
    Write-Host ''
    $rosterInput = (Read-Host 'Apify Company-Roster Actor ID (or press Enter to skip)').Trim()
    if ([string]::IsNullOrWhiteSpace($rosterInput)) {
        $rosterActorId = $null
        Write-Host 'Skipped. Daily-brief Layer-B will use WebSearch fallback.'
    } else {
        $rosterActorId = $rosterInput
        Write-Host 'Company-roster Actor ID recorded. Not validated at setup time to avoid'
        Write-Host 'extra Apify spend; first daily-brief Layer-B call will surface any issue.'
    }
}

# --- Prompt: Pitch-deck Google Drive pointer (OPTIONAL — pitch-deck-updater) --
# Accepts a raw Drive file ID or a full share URL; we extract the ID from a URL.
# Not validated at setup time (avoids requiring Drive MCP auth here); the
# pitch-deck-updater agent surfaces a DECK_POINTER_MISSING / DRIVE_NOT_AUTHORIZED
# notice on first run if anything is off.
$deckFileId  = if ($existing) { $existing.pitch_deck_drive_file_id } else { $null }
$deckUrl     = if ($existing) { $existing.pitch_deck_drive_url } else { $null }
if ($promptDeckPointer) {
    Write-Host ''
    Write-Host 'OPTIONAL — Pitch deck Google Drive pointer (Google Slides)'
    Write-Host '---'
    Write-Host 'Powers the pitch-deck-updater agent, which reads your deck READ-ONLY and'
    Write-Host 'proposes slide-by-slide edits to the dashboard for your approval. It NEVER'
    Write-Host 'edits the deck itself.'
    Write-Host ''
    Write-Host 'Paste either the Drive file ID or the full share URL, e.g.:'
    Write-Host '  https://docs.google.com/presentation/d/1AbCdEfGhIjK.../edit'
    Write-Host '  (or just the 1AbCdEfGhIjK... part)'
    Write-Host ''
    Write-Host 'Leave blank to skip — the weekly chain will write a DECK_POINTER_MISSING notice.'
    Write-Host ''
    $deckInput = (Read-Host 'Pitch deck Drive file ID or URL (or press Enter to skip)').Trim()
    if ([string]::IsNullOrWhiteSpace($deckInput)) {
        $deckFileId = $null
        $deckUrl    = $null
        Write-Host 'Skipped. pitch-deck-updater will write a DECK_POINTER_MISSING notice until set.'
    } else {
        # Extract the file ID from a presentation/document/file URL if a URL was pasted.
        # Anchor the capture so it stops at the next '/', '?', or '#' — otherwise a
        # trailing path segment or query string (e.g. /d/ID/edit?usp=sharing) would be
        # swallowed into the ID and silently rejected by the agent on first run.
        if ($deckInput -match '/d/([a-zA-Z0-9_-]+)(?=[/?#]|$)') {
            $deckFileId = $Matches[1]
            $deckUrl    = $deckInput
        } elseif ($deckInput -match '[?&]id=([a-zA-Z0-9_-]+)(?=[&#]|$)') {
            $deckFileId = $Matches[1]
            $deckUrl    = $deckInput
        } else {
            # Treat the whole input as a raw file ID.
            $deckFileId = $deckInput
            $deckUrl    = $null
        }
        Write-Host "Pitch deck pointer recorded (file ID: $deckFileId). Not validated at setup time."
    }
}

# --- Prompt: GitHub PAT + repo (OPTIONAL — UI workflow_dispatch + boot-catchup) --
# Powers two Phase-3 features:
#   1. The dashboard "Run now" button when the UI runs in Docker/container mode
#      (the container can't spawn the host claude CLI, so it dispatches a GitHub
#      workflow to the self-hosted runner instead).
#   2. scripts/boot-catchup.ps1, the >24h missed-run backstop, which dispatches
#      overdue agents on boot.
# Not needed at all if you only ever run the UI natively and rely on GitHub's own
# same-day queue catch-up. Stored as-is; the PAT VALUE is never echoed back by the
# UI (presence-only).
$githubPat  = if ($existing) { $existing.github_pat } else { $null }
$githubRepo = if ($existing) { $existing.github_repo } else { $null }
if ($promptGithub) {
    Write-Host ''
    Write-Host 'OPTIONAL — GitHub PAT + repo (for UI Run-now in Docker mode + boot-catchup)'
    Write-Host '---'
    Write-Host 'Create a FINE-GRAINED personal access token scoped to ONLY your Nightingale'
    Write-Host 'repo with Repository permission "Actions: Read and write":'
    Write-Host '  https://github.com/settings/personal-access-tokens/new'
    Write-Host ''
    Write-Host 'Then give the repo as owner/repo, e.g. ben-nightingale/Nightingale'
    Write-Host '(or the mirror tlosdev/nightingale-gtm).'
    Write-Host ''
    Write-Host 'Leave the token blank to skip — native Run-now + GitHub same-day queue catch-up'
    Write-Host 'still work without it.'
    Write-Host ''
    $patInput = (Read-MaskedString 'Paste GitHub fine-grained PAT (input hidden, or press Enter to skip)').Trim()
    if ([string]::IsNullOrWhiteSpace($patInput)) {
        $githubPat  = $null
        $githubRepo = $null
        Write-Host 'Skipped. UI Run-now will be host-only; boot-catchup backstop disabled.'
    } else {
        $githubPat = $patInput
        $repoInput = (Read-Host 'GitHub repo as owner/repo').Trim()
        if ($repoInput -notmatch '^[\w.-]+/[\w.-]+$') {
            Write-Error "GitHub repo must look like owner/repo. Got: '$repoInput'. Aborting (secrets NOT written)."
            exit 1
        }
        $githubRepo = $repoInput
        Write-Host 'GitHub PAT + repo recorded. Not validated at setup time (avoids a live API call);'
        Write-Host 'a failed dispatch will surface in the UI / boot-catchup output.'
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
    # L10 — prefer HTTP status code over message-string matching. The exception
    # message is brittle: a proxy or wrapped error might not contain '404' literally.
    $statusCode = $null
    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
    if ($statusCode -eq 404) {
        Write-Error "Actor '$actorId' not found in your Apify account (HTTP 404)."
        Write-Error 'Verify in https://console.apify.com/actors and re-run with the correct Actor ID.'
    } elseif ($statusCode -eq 429) {
        Write-Error "Apify rate-limited (HTTP 429). Wait until reset or upgrade your Apify plan."
    } else {
        Write-Error "Apify Actor run could not be started (HTTP $statusCode): $($_.Exception.Message)"
    }
    Write-Error 'Secrets file NOT written.'
    exit 1
}

# Poll the validation run (cap 2 minutes). U16 — print a dot every poll cycle
# so the operator sees progress instead of staring at a silent 2-minute wait.
Write-Host -NoNewline 'Polling Apify '
$delay      = 5
$totalSlept = 0
$maxTotal   = 120
$status     = $null
while ($totalSlept -lt $maxTotal) {
    Start-Sleep -Seconds $delay
    $totalSlept += $delay
    Write-Host -NoNewline '.'
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
Write-Host ''  # newline after dots

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
if ($items -is [array] -and $items.Count -gt 0) {
    # M3 — check top-level keys / explicit fields only, NOT a free-form
    # full-JSON substring match. The prior version matched against the entire
    # serialized JSON, so any prospect whose company name contained the word
    # "Restricted" (e.g. "Restricted Stock Plans LLC") or whose headline
    # mentioned feeling "restricted" would false-positive and write the
    # cookie-expired sentinel. Tighten to known auth-failure response shapes.
    foreach ($i in $items) {
        if ($i.loginRequired -eq $true) { $flagged = $true; break }
        if ($i.captcha -eq $true)       { $flagged = $true; break }
        if ($i.authwall -eq $true)      { $flagged = $true; break }
        # Some Actors return a top-level error string. Match common phrasings,
        # but only against $i.error / $i.message / $i.status — never the
        # body data.
        foreach ($field in @('error','message','status','reason')) {
            $val = $i.$field
            if ($val -and $val -match '(?i)(authwall|please[ _-]?log[ _-]?in|login required|captcha)') {
                $flagged = $true; break
            }
        }
        if ($flagged) { break }
    }
}
if ($flagged) {
    Write-Error 'Cookie was rejected by LinkedIn (Actor returned auth-failure indicators).'
    Write-Error "Refresh your li_at cookie from Chrome DevTools and re-run."
    Write-Error 'Secrets file NOT written.'
    exit 1
}
Write-Host 'Cookie + Actor validation OK.'

# --- Write secrets.json (schema v5) -----------------------------------------
$createdAt = if ($existing -and $existing.created_at) { $existing.created_at } else { (Get-Date -Format 'yyyy-MM-dd') }
$updatedAt = (Get-Date -Format 'yyyy-MM-dd')

$secrets = [ordered]@{
    schema_version       = 5
    created_at           = $createdAt
    updated_at           = $updatedAt
    apify_api_token      = $apifyToken
    apify_actor_id       = $actorId
    apify_validation_url = $validationUrl
    linkedin_li_at       = $liAt
}
# Only include the company-roster Actor ID when the operator provided one.
# Omitting (rather than writing an empty string) keeps the daily-brief agent's
# layer_b_actor_configured probe correct and avoids ambiguous empty-vs-missing.
if (-not [string]::IsNullOrWhiteSpace($rosterActorId)) {
    $secrets['apify_company_roster_actor_id'] = $rosterActorId
}
# Only include the pitch-deck pointer when the operator provided one. Same
# omit-when-empty discipline so pitch-deck-updater's "is a deck configured"
# probe stays unambiguous.
if (-not [string]::IsNullOrWhiteSpace($deckFileId)) {
    $secrets['pitch_deck_drive_file_id'] = $deckFileId
    if (-not [string]::IsNullOrWhiteSpace($deckUrl)) {
        $secrets['pitch_deck_drive_url'] = $deckUrl
    }
}
# Only include the GitHub PAT + repo when both were provided. Same omit-when-empty
# discipline so the UI's "is dispatch configured" probe (has_github_pat &&
# has_github_repo) stays unambiguous.
if (-not [string]::IsNullOrWhiteSpace($githubPat) -and -not [string]::IsNullOrWhiteSpace($githubRepo)) {
    $secrets['github_pat']  = $githubPat
    $secrets['github_repo'] = $githubRepo
}

$json = $secrets | ConvertTo-Json -Depth 5

# M6 — atomic ACL-first write. The prior version did:
#   Set-Content (writes plaintext with default ACL)
#   Set-Acl    (then locks down)
# That leaves a brief window where the plaintext file is readable by other
# local users. Defense-in-depth: create an empty file FIRST with the
# restricted ACL, then write the content. Combined with the parent directory
# ACL (already locked above), defense is sufficient even if Set-Acl on the
# file fails for some reason.

# Remove any pre-existing file so the new ACL applies cleanly.
if (Test-Path $secretsPath) {
    Remove-Item -Path $secretsPath -Force
}

try {
    # Create empty file via .NET API so we can hand-craft a SecurityDescriptor
    # before any content lands on disk.
    $fileSecurity = New-Object System.Security.AccessControl.FileSecurity
    $fileSecurity.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$env:USERDOMAIN\$env:USERNAME",
        'FullControl',
        'Allow')
    $fileSecurity.SetAccessRule($rule)

    # FileSecurity-aware constructor: empty file with restricted ACL atomically.
    [System.IO.File]::Create($secretsPath).Close()
    Set-Acl -Path $secretsPath -AclObject $fileSecurity

    # Now write the actual content — file is already locked to current user.
    Set-Content -Path $secretsPath -Value $json -Encoding utf8 -NoNewline
} catch {
    Write-Warning "Atomic ACL-first write failed: $($_.Exception.Message)"
    Write-Warning "Falling back to write-then-lock (brief readability window)."
    Set-Content -Path $secretsPath -Value $json -Encoding utf8 -NoNewline
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
        Write-Warning "Recovery: icacls `"$secretsPath`" /reset"
    }
}

# --- Clear stale cookie-expired sentinel if present -------------------------
$sentinel = Join-Path $secretsDir '.cookie-expired-active'
if (Test-Path $sentinel) {
    Remove-Item $sentinel -Force
    Write-Host 'Cleared cookie-expired sentinel.'
}

Write-Host ''
Write-Host "Done. Secrets written to: $secretsPath  (schema v5)"
Write-Host 'Next intro-finder run (Sun-Thu 7am) will use these credentials.'
if (-not [string]::IsNullOrWhiteSpace($rosterActorId)) {
    Write-Host 'Daily-brief Layer-B will use the configured company-roster Actor.'
} else {
    Write-Host 'Daily-brief Layer-B will use the WebSearch fallback path.'
}
if (-not [string]::IsNullOrWhiteSpace($deckFileId)) {
    Write-Host 'pitch-deck-updater will read the configured Google Drive deck (read-only).'
} else {
    Write-Host 'pitch-deck-updater has no deck pointer; it will write a DECK_POINTER_MISSING notice until set.'
}
if (-not [string]::IsNullOrWhiteSpace($githubPat) -and -not [string]::IsNullOrWhiteSpace($githubRepo)) {
    Write-Host "GitHub dispatch configured ($githubRepo): UI Run-now works in Docker mode + boot-catchup backstop is active."
} else {
    Write-Host 'No GitHub PAT/repo: UI Run-now is host-only and the boot-catchup backstop is disabled (GitHub same-day queue catch-up still works).'
}
