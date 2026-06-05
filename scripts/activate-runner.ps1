<#
.SYNOPSIS
    One-command activation of Phase 3 (the GitHub Actions self-hosted runner that
    replaces Windows Task Scheduler). Orchestrates the whole migration so you
    don't have to juggle elevation, the runner registration token, and the
    legacy-task uninstall by hand.

.DESCRIPTION
    What it does, in order:
      1. Elevates itself (UAC prompt) if not already running as admin -- but only
         when you did NOT pass -Token (so a token is never relayed across the
         elevation boundary). If you pass -Token, run it elevated yourself.
      2. Fetches a short-lived runner REGISTRATION token from GitHub via the `gh`
         CLI (switching to the -GhAccount that has admin on the repo, then
         restoring your previous active account). Skipped if you pass -Token.
      3. Runs scripts/install-runner.ps1 in a child process, handing it the token
         through the process ENVIRONMENT block (NIGHTINGALE_RUNNER_TOKEN), never
         on a command line / process listing. That installs the runner as a
         boot-start Windows service + registers the on-boot catch-up task.
      4. Runs scripts/uninstall-schedule.ps1 to remove the 8 legacy
         Nightingale-* Task Scheduler agents (so nothing double-fires). Skip with
         -SkipLegacyUninstall.
      5. (Optional, -ConfigureSecrets) runs scripts/setup-secrets.ps1 so you can
         add the GitHub PAT that powers container-mode "Run now" + boot-catchup.
      6. Prints a verification summary + a test-dispatch command.

    IMPORTANT -- which repo: GitHub only runs workflows that exist in the repo on
    GitHub. The .github/workflows/ files currently live in
    tlosdev/nightingale-gtm, so that is the default -RepoUrl and the runner must
    attach there. If you later push the workflows to a different repo, pass its
    URL via -RepoUrl and the owning account via -GhAccount.

.PARAMETER RepoUrl
    Repo the runner attaches to (must host the .github/workflows files on
    GitHub). Default: https://github.com/tlosdev/nightingale-gtm

.PARAMETER GhAccount
    The `gh` CLI account that has admin on -RepoUrl, used to mint the runner
    registration token. Default: tlosdev. Ignored if you pass -Token.

.PARAMETER Token
    A runner registration token you minted yourself (web UI:
    <repo> Settings -> Actions -> Runners -> New self-hosted runner). If you pass
    this, run the script from an ELEVATED PowerShell (it will not self-elevate,
    to avoid relaying the token across the UAC boundary).

.PARAMETER SkipLegacyUninstall
    Do NOT remove the legacy Task Scheduler agents. Only use this if you
    deliberately want both schedulers (you almost never do -- everything fires
    twice).

.PARAMETER ConfigureSecrets
    After install, also run setup-secrets.ps1 (interactive) to add the GitHub PAT
    + repo for container dispatch + the boot-catchup backstop.

.PARAMETER InstallDir
.PARAMETER RunnerVersion
.PARAMETER Name
    Passed through to install-runner.ps1 if set (otherwise its defaults apply).

.EXAMPLE
    # Simplest path: double-click-equivalent. Mints the token via gh (tlosdev),
    # self-elevates, installs, migrates, verifies.
    .\scripts\activate-runner.ps1

.EXAMPLE
    # You already have a registration token; run elevated yourself.
    .\scripts\activate-runner.ps1 -Token 'AXXXX...'

.NOTES
    Windows-only. PowerShell 5.1+. ASCII-only source. The registration token is
    short-lived (~1h), single-use, and is never written to disk or logged.
#>

param(
    [string]$RepoUrl = 'https://github.com/tlosdev/nightingale-gtm',
    [string]$GhAccount = 'tlosdev',
    [string]$Token,
    [switch]$SkipLegacyUninstall,
    [switch]$ConfigureSecrets,
    [string]$InstallDir,
    [string]$RunnerVersion,
    [string]$Name
)

$ErrorActionPreference = 'Stop'

# --- Windows-only guard ------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    Write-Error 'activate-runner.ps1 is Windows-only.'
    exit 1
}

function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Validate repo URL + extract owner/repo ----------------------------------
if ($RepoUrl -notmatch '^https://github\.com/([^/]+)/([^/]+?)(\.git)?/?$') {
    Write-Error "RepoUrl must look like https://github.com/<owner>/<repo>. Got: $RepoUrl"
    exit 1
}
$owner = $Matches[1]
$repo  = $Matches[2]
$RepoUrl = "https://github.com/$owner/$repo"

$installRunner   = Join-Path $PSScriptRoot 'install-runner.ps1'
$uninstallLegacy = Join-Path $PSScriptRoot 'uninstall-schedule.ps1'
$setupSecrets    = Join-Path $PSScriptRoot 'setup-secrets.ps1'
if (-not (Test-Path $installRunner)) {
    Write-Error "install-runner.ps1 not found next to this script ($installRunner)."
    exit 1
}

# --- Elevation ---------------------------------------------------------------
if (-not (Test-Admin)) {
    if ($Token) {
        Write-Error "You passed -Token, but this shell is not elevated. Re-run from an ELEVATED PowerShell (Run as administrator). The token is not relayed across a UAC prompt by design."
        exit 1
    }
    Write-Host "Elevation required to install the runner service. Requesting it now (UAC prompt)..." -ForegroundColor Cyan
    $relaunch = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
                  '-RepoUrl', $RepoUrl, '-GhAccount', $GhAccount)
    if ($SkipLegacyUninstall) { $relaunch += '-SkipLegacyUninstall' }
    if ($ConfigureSecrets)    { $relaunch += '-ConfigureSecrets' }
    if ($InstallDir)          { $relaunch += @('-InstallDir', $InstallDir) }
    if ($RunnerVersion)       { $relaunch += @('-RunnerVersion', $RunnerVersion) }
    if ($Name)                { $relaunch += @('-Name', $Name) }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunch | Out-Null
    } catch {
        Write-Error "Elevation was declined or failed. Re-run from an elevated PowerShell. ($($_.Exception.Message))"
        exit 1
    }
    Write-Host "Continuing in the elevated window. You can close this one." -ForegroundColor DarkGray
    exit 0
}

Write-Host "Activating the Nightingale self-hosted runner for $owner/$repo" -ForegroundColor Cyan
Write-Host ""

# --- Acquire the runner registration token -----------------------------------
$ghSwitched = $false
$prevAccount = $null
if (-not $Token) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Error @"
The GitHub CLI ('gh') was not found, so a token cannot be fetched automatically.
Either install gh, OR mint a runner registration token yourself and re-run with -Token:
  Web:  https://github.com/$owner/$repo/settings/actions/runners/new  (copy the --token value)
  CLI:  gh api -X POST repos/$owner/$repo/actions/runners/registration-token --jq .token
"@
        exit 1
    }

    try {
        # Remember the current active account so we can restore it afterward.
        $prevAccount = (& gh api user --jq .login) 2>$null
        if ($LASTEXITCODE -ne 0) { $prevAccount = $null }

        if ($GhAccount -and $prevAccount -and ($GhAccount -ne $prevAccount)) {
            Write-Host "Switching gh account: $prevAccount -> $GhAccount (to mint the token)" -ForegroundColor DarkGray
            & gh auth switch --user $GhAccount | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Could not switch gh to account '$GhAccount'. Is it authenticated? (gh auth login)  Or pass -Token."
                exit 1
            }
            $ghSwitched = $true
        }

        Write-Host "Requesting a runner registration token for $owner/$repo ..." -ForegroundColor Cyan
        $Token = (& gh api -X POST "repos/$owner/$repo/actions/runners/registration-token" --jq .token) 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Token)) {
            Write-Error @"
Failed to fetch a registration token via gh. The active gh account may lack admin
on $owner/$repo. Mint one manually and re-run with -Token:
  https://github.com/$owner/$repo/settings/actions/runners/new
"@
            exit 1
        }
        Write-Host "Got a registration token (short-lived, single-use)." -ForegroundColor Green
    } finally {
        if ($ghSwitched -and $prevAccount) {
            & gh auth switch --user $prevAccount | Out-Null
            Write-Host "Restored gh active account: $prevAccount" -ForegroundColor DarkGray
        }
    }
}

# --- Install the runner (token via env block, never argv) --------------------
Write-Host ""
Write-Host "Installing the runner service ..." -ForegroundColor Cyan
$installCode = 1
$env:NIGHTINGALE_RUNNER_TOKEN = $Token
try {
    $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installRunner, '-RepoUrl', $RepoUrl)
    if ($InstallDir)    { $argsList += @('-InstallDir', $InstallDir) }
    if ($RunnerVersion) { $argsList += @('-RunnerVersion', $RunnerVersion) }
    if ($Name)          { $argsList += @('-Name', $Name) }
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -NoNewWindow -Wait -PassThru
    $installCode = $proc.ExitCode
} finally {
    Remove-Item Env:NIGHTINGALE_RUNNER_TOKEN -ErrorAction SilentlyContinue
    $Token = $null
}
if ($installCode -ne 0) {
    Write-Error "install-runner.ps1 exited with code $installCode. Stopping before the legacy-task migration so nothing is half-applied."
    exit $installCode
}

# --- Retire the legacy Task Scheduler agents ---------------------------------
if (-not $SkipLegacyUninstall) {
    if (Test-Path $uninstallLegacy) {
        Write-Host ""
        Write-Host "Removing the legacy Task Scheduler agents (so they don't double-fire) ..." -ForegroundColor Cyan
        $u = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $uninstallLegacy) `
                -NoNewWindow -Wait -PassThru
        if ($u.ExitCode -ne 0) {
            Write-Warning "uninstall-schedule.ps1 exited with code $($u.ExitCode). Check Get-ScheduledTask 'Nightingale-*' manually to ensure the old agents are gone."
        }
    } else {
        Write-Warning "uninstall-schedule.ps1 not found; skipping legacy migration. Remove the old Nightingale-* tasks manually to avoid double-firing."
    }
} else {
    Write-Warning "-SkipLegacyUninstall set: the legacy Task Scheduler agents remain. If they are still registered, every agent will fire TWICE."
}

# --- Optional: configure GitHub PAT for dispatch + boot-catchup ---------------
if ($ConfigureSecrets) {
    if (Test-Path $setupSecrets) {
        Write-Host ""
        Write-Host "Launching setup-secrets.ps1 (add the GitHub PAT + repo when prompted; repo = $owner/$repo) ..." -ForegroundColor Cyan
        & $setupSecrets
    } else {
        Write-Warning "setup-secrets.ps1 not found; skipping. Run it later to add the GitHub PAT."
    }
}

# --- Verify ------------------------------------------------------------------
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "Activation complete. Verification:" -ForegroundColor Green
$svc = Get-Service -Name 'actions.runner.*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) {
    $st = Get-Service -Name $svc.Name
    Write-Host ("  Runner service : {0} -- {1}, StartType {2}" -f $svc.Name, $st.Status, $st.StartType)
} else {
    Write-Warning "  Runner service : NOT FOUND (check the install output above)."
}
$tasks = Get-ScheduledTask -TaskName 'Nightingale-*' -ErrorAction SilentlyContinue
if ($tasks) {
    Write-Host "  Nightingale-* tasks remaining:"
    foreach ($t in $tasks) { Write-Host ("    - {0}" -f $t.TaskName) }
    Write-Host "    (Expected: only Nightingale-Boot-Catchup, plus any dynamic intro-finder one-shots.)" -ForegroundColor DarkGray
} else {
    Write-Host "  No Nightingale-* scheduled tasks found." -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "Test a dispatch (writes real output to your Desktop):" -ForegroundColor Cyan
Write-Host "  gh workflow run daily-brief.yml --repo $owner/$repo --ref main"
Write-Host "Then check the repo's Actions tab + ~/Desktop/nightingale-signals/."
Write-Host "==============================================================" -ForegroundColor Green
exit 0
