<#
.SYNOPSIS
    Installs a GitHub Actions self-hosted runner as a Windows SERVICE on this PC,
    so the Nightingale agent workflows in .github/workflows/ run on schedule and
    auto-start on boot. This replaces the scheduling half of install-schedule.ps1.

.DESCRIPTION
    Phase 3 of the UI/workflow overhaul moves agent scheduling off Windows Task
    Scheduler and onto GitHub Actions cron -- but execution STAYS on this host
    (self-hosted runner), because the agents depend on the local Claude Code
    install, claude.ai MCP connectors, and the Desktop output tree. None of those
    can move to a GitHub-hosted cloud runner.

    What this script does:
      1. Verifies `claude` is on PATH (the runner needs it to run agents).
      2. Downloads the GitHub Actions runner for Windows x64.
      3. Configures it against your repo with labels `self-hosted,windows`.
      4. Installs it as a Windows service with Automatic (boot) start.
      5. Writes a `.env` in the runner dir setting NIGHTINGALE_VAULT to this repo,
         so each workflow runs `claude -p` from the real vault directory.
      6. Registers ONE on-boot Task Scheduler entry (Nightingale-Boot-Catchup)
         that runs scripts/boot-catchup.ps1 -- the >24h missed-run backstop.

    Boot-catch-up (operator requirement: survive a powered-off machine):
      - Primary: GitHub keeps a fired scheduled run queued for an available
        runner. PC off at the cron time, booted later the same day -> the runner
        service starts on boot and picks up the queued job. Covers same-day
        misses for free.
      - Backstop (>24h outages): Nightingale-Boot-Catchup runs boot-catchup.ps1
        on boot, which dispatches any agent overdue beyond its cadence (idempotent
        via a per-agent cursor). See scripts/boot-catchup.ps1.

.PARAMETER RepoUrl
    The GitHub repository URL the runner attaches to, e.g.
    https://github.com/ben-nightingale/Nightingale
    (or the mirror https://github.com/tlosdev/nightingale-gtm).

.PARAMETER Token
    A runner REGISTRATION token (short-lived, ~1h). Get it from the repo on
    GitHub: Settings -> Actions -> Runners -> New self-hosted runner -> copy the
    token shown in the `./config.cmd ... --token XXXX` line. This is NOT your
    PAT and is single-use/short-lived.

.PARAMETER InstallDir
    Where to install the runner. Default: C:\actions-runner-nightingale

.PARAMETER RunnerVersion
    GitHub Actions runner version (without the leading 'v'). Default below; bump
    if GitHub deprecates it (the runner self-updates anyway once registered).

.PARAMETER Name
    Runner name as it appears in GitHub. Default: <hostname>-nightingale

.EXAMPLE
    .\scripts\install-runner.ps1 `
        -RepoUrl 'https://github.com/ben-nightingale/Nightingale' `
        -Token 'AXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

.NOTES
    Run from an ELEVATED PowerShell (installing a service requires admin).
    Windows-only. To remove the runner later:
      cd <InstallDir>; .\svc.cmd stop; .\svc.cmd uninstall; .\config.cmd remove --token <new-removal-token>
    Then: Unregister-ScheduledTask -TaskName 'Nightingale-Boot-Catchup' -Confirm:$false
#>
param(
    [Parameter(Mandatory = $true)] [string]$RepoUrl,
    [string]$Token,
    [string]$InstallDir = 'C:\actions-runner-nightingale',
    [string]$RunnerVersion = '2.323.0',
    [string]$Name = "$($env:COMPUTERNAME)-nightingale"
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "This script must run from an ELEVATED PowerShell (Run as administrator) -- installing a Windows service requires it."
    exit 1
}

# Token resolution: prefer the -Token parameter; otherwise fall back to the
# NIGHTINGALE_RUNNER_TOKEN environment variable. The activate-runner.ps1 wrapper
# uses the env-var path so the short-lived registration token never appears on a
# command line / process listing. The token is consumed here and never logged.
if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:NIGHTINGALE_RUNNER_TOKEN
}
if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "No runner registration token. Pass -Token <token>, or set NIGHTINGALE_RUNNER_TOKEN, or use scripts/activate-runner.ps1 which fetches one for you."
    exit 1
}

# Resolve the repo root (one directory above this script) -- becomes NIGHTINGALE_VAULT.
$repoRoot = Split-Path -Parent $PSScriptRoot
Write-Host "Repo root (vault): $repoRoot"

# Validate the repo URL shape.
if ($RepoUrl -notmatch '^https://github\.com/[^/]+/[^/]+/?$') {
    Write-Error "RepoUrl must look like https://github.com/<owner>/<repo>. Got: $RepoUrl"
    exit 1
}
$RepoUrl = $RepoUrl.TrimEnd('/')

# Verify `claude` is reachable -- the runner service inherits the machine PATH.
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Warning "The 'claude' CLI was not found on PATH for THIS shell."
    Write-Warning "The runner service runs as a service account and uses the MACHINE PATH."
    Write-Warning "Ensure Claude Code is installed for all users / on the machine PATH, or the"
    Write-Warning "scheduled agent runs will fail to find 'claude'. Continuing."
} else {
    Write-Host "claude CLI: $($claudeCmd.Source)"
}

# --- Download + extract the runner ------------------------------------------
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}
$zip = Join-Path $InstallDir "actions-runner-win-x64-$RunnerVersion.zip"
$url = "https://github.com/actions/runner/releases/download/v$RunnerVersion/actions-runner-win-x64-$RunnerVersion.zip"

if (-not (Test-Path (Join-Path $InstallDir 'config.cmd'))) {
    Write-Host "Downloading runner $RunnerVersion ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Write-Host "Extracting ..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $InstallDir)
    Remove-Item $zip -Force
} else {
    Write-Host "Runner already extracted in $InstallDir -- skipping download."
}

# --- Write the runner .env so every job knows the vault path -----------------
# The Actions runner reads a `.env` file in its root dir and applies it to all
# job environments. This is how workflows resolve $env:NIGHTINGALE_VAULT.
$envFile = Join-Path $InstallDir '.env'
"NIGHTINGALE_VAULT=$repoRoot" | Out-File -FilePath $envFile -Encoding ascii -Force
Write-Host "Wrote $envFile (NIGHTINGALE_VAULT=$repoRoot)"

# --- Configure + install as a service ---------------------------------------
Push-Location $InstallDir
try {
    Write-Host "Configuring runner against $RepoUrl ..."
    # --unattended : no prompts. --replace : re-register cleanly if re-run.
    # --runasservice : install + start as a Windows service (Automatic start =
    # auto-start on boot, which is the core of boot-catch-up).
    & "$InstallDir\config.cmd" --url $RepoUrl --token $Token `
        --name $Name --labels self-hosted,windows --work '_work' `
        --runasservice --unattended --replace
    if ($LASTEXITCODE -ne 0) {
        Write-Error "config.cmd failed with exit code $LASTEXITCODE."
        exit 1
    }
} finally {
    Pop-Location
}

# --- Confirm the service + force Automatic start ----------------------------
$svc = Get-Service -Name 'actions.runner.*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($svc) {
    Set-Service -Name $svc.Name -StartupType Automatic
    if ($svc.Status -ne 'Running') { Start-Service -Name $svc.Name }
    Write-Host "Runner service: $($svc.Name) -- Status $((Get-Service $svc.Name).Status), StartType Automatic."
} else {
    Write-Warning "Could not find an 'actions.runner.*' service. Check the config.cmd output above."
}

# --- Register the on-boot catch-up task -------------------------------------
# Single Task Scheduler entry (the ONLY Nightingale-* task that remains after
# migration; the intro-finder per-target one-shots are still created dynamically
# by the agent). Runs boot-catchup.ps1 ~2 min after boot so the runner service
# has come up first.
$bootScript = Join-Path $PSScriptRoot 'boot-catchup.ps1'
$principal  = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings   = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
$bootTrigger = New-ScheduledTaskTrigger -AtStartup
$bootTrigger.Delay = 'PT2M'
$bootAction = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$bootScript`"" `
    -WorkingDirectory $repoRoot
Register-ScheduledTask `
    -TaskName 'Nightingale-Boot-Catchup' `
    -Action $bootAction `
    -Trigger $bootTrigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Nightingale boot catch-up: on startup, dispatch any agent overdue beyond its cadence via GitHub workflow_dispatch (idempotent backstop for >24h outages). See scripts/boot-catchup.ps1.' `
    -Force | Out-Null
Write-Host "Registered: Nightingale-Boot-Catchup (on boot, +2m delay)"

Write-Host ''
Write-Host '=============================================================='
Write-Host 'Runner install complete.'
Write-Host "  Service:   $((Get-Service -Name 'actions.runner.*' -ErrorAction SilentlyContinue | Select-Object -First 1).Name)"
Write-Host "  Vault:     $repoRoot"
Write-Host "  Workflows: .github/workflows/*.yml (cron in UTC -- see file headers for DST note)"
Write-Host ''
Write-Host 'NEXT STEPS:'
Write-Host '  1. Migrate off the old Task Scheduler agents (avoid double-firing):'
Write-Host '       .\scripts\uninstall-schedule.ps1'
Write-Host '  2. (Optional) enable UI "Run now" from Docker/container mode by adding a'
Write-Host '     fine-grained GitHub PAT + repo to secrets.json:  .\scripts\setup-secrets.ps1'
Write-Host '  3. Verify a run:  gh workflow run daily-brief.yml --repo <owner/repo> --ref main'
Write-Host '     (or use the dashboard Agents tab -> Run now).'
Write-Host '=============================================================='
