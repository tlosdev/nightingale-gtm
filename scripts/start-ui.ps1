<#
.SYNOPSIS
    Launches the Nightingale UI local web server.

.DESCRIPTION
    Opt-in companion to the existing PowerShell + scheduled task flow. This
    script does NOT install or modify scheduled tasks, does NOT touch the
    secrets file, and does NOT change any agent behavior. It starts a local
    Node.js + Express server (loopback only) that serves a React control
    panel for viewing agent outputs and approving HubSpot pending items.

    Steps the script takes:
      1. Verifies Node.js 18+ is on PATH.
      2. cd into ui/.
      3. If node_modules is missing: runs `npm install` (one-time, ~1 min).
      4. If web/dist is missing OR older than the newest source file: runs `npm run build`.
      5. Starts `npm start` (Express on http://localhost:8765 by default).
      6. Waits for the server to respond to GET /api/health.
      7. Opens the URL in the default browser.

    Stop the server with Ctrl+C in this terminal. No background daemon, no
    auto-launch.

.PARAMETER Port
    Override the default port (8765). Sets NIGHTINGALE_UI_PORT for the server.

.NOTES
    Requires Windows + PowerShell 5.1+ AND Node.js 18 LTS or newer.
    Install Node from https://nodejs.org/ if needed.

    The Node server binds to 127.0.0.1 only — never accessible from the LAN.
    No firewall prompt.
#>

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'

# --- PowerShell version check ------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell $($PSVersionTable.PSVersion) detected; this script requires 5.1 or newer."
    exit 1
}

# --- Node.js version check ---------------------------------------------------
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Error "Node.js was not found on PATH."
    Write-Error "Install Node.js 18 LTS or newer from https://nodejs.org/ and re-run."
    exit 1
}

$nodeVersionRaw = (& node --version) 2>$null
if ($nodeVersionRaw -notmatch '^v(\d+)\.') {
    Write-Error "Could not parse Node.js version: $nodeVersionRaw"
    exit 1
}
$nodeMajor = [int]$Matches[1]
if ($nodeMajor -lt 18) {
    Write-Error "Node.js $nodeVersionRaw is too old; please install v18 LTS or newer from https://nodejs.org/"
    exit 1
}
Write-Host "Node.js: $nodeVersionRaw" -ForegroundColor Green

# --- claude CLI check (informational only) ----------------------------------
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Warning "The 'claude' CLI was not found on PATH."
    Write-Warning "The UI will still launch, but Run-Now and Apply/Reject buttons will fail."
    Write-Warning "Install Claude Code if you want those actions to work."
}

# --- Resolve repo + ui dir ---------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiDir = Join-Path $repoRoot 'ui'
if (-not (Test-Path $uiDir)) {
    Write-Error "ui/ directory not found at $uiDir. Are you in the nightingale repo root?"
    exit 1
}

# Switch into ui/ for npm operations.
Push-Location $uiDir
try {
    # --- npm install if needed ----------------------------------------------
    $nodeModules = Join-Path $uiDir 'node_modules'
    if (-not (Test-Path $nodeModules)) {
        Write-Host ""
        Write-Host "Installing dependencies (one-time, ~30-60s)..." -ForegroundColor Cyan
        & npm install
        if ($LASTEXITCODE -ne 0) {
            Write-Error "npm install failed (exit $LASTEXITCODE). Aborting."
            exit 1
        }
    }

    # --- npm build if dist missing or stale ---------------------------------
    $distDir = Join-Path $uiDir 'web\dist'
    $needsBuild = $true
    if (Test-Path $distDir) {
        # Find the newest source file vs newest dist file.
        $newestSrc = Get-ChildItem -Path (Join-Path $uiDir 'web\src') -Recurse -File |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First 1
        $newestDist = Get-ChildItem -Path $distDir -Recurse -File |
                      Sort-Object LastWriteTime -Descending |
                      Select-Object -First 1
        if ($newestSrc -and $newestDist -and $newestDist.LastWriteTime -gt $newestSrc.LastWriteTime) {
            $needsBuild = $false
        }
    }
    if ($needsBuild) {
        Write-Host ""
        Write-Host "Building frontend..." -ForegroundColor Cyan
        & npm run build
        if ($LASTEXITCODE -ne 0) {
            Write-Error "npm run build failed (exit $LASTEXITCODE). Aborting."
            exit 1
        }
    }

    # --- Start the server in this process -----------------------------------
    $env:NIGHTINGALE_UI_PORT = $Port.ToString()
    $url = "http://localhost:$Port"

    Write-Host ""
    Write-Host "Starting Nightingale UI on $url ..." -ForegroundColor Cyan
    Write-Host "(Ctrl+C to stop. The server binds to 127.0.0.1 only — not exposed on your LAN.)"
    Write-Host ""

    # Start npm start in the background so we can poll health, then open browser,
    # then re-attach to the npm process by waiting on it. Use Start-Job-equivalent.
    $serverJob = Start-Job -ScriptBlock {
        param($dir, $port)
        Set-Location $dir
        $env:NIGHTINGALE_UI_PORT = $port.ToString()
        & npm start
    } -ArgumentList $uiDir, $Port

    # Poll /api/health for up to 30s.
    $healthy = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try {
            $resp = Invoke-WebRequest -Uri "$url/api/health" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -eq 200) {
                $healthy = $true
                break
            }
        } catch {
            # not ready yet
        }
    }
    if (-not $healthy) {
        Write-Warning "Server did not become healthy within 30s. Check job output:"
        Receive-Job -Job $serverJob -Keep
        Write-Warning "Continuing anyway; browser will open but may show a connection error."
    } else {
        Write-Host "Server healthy." -ForegroundColor Green
        Start-Process $url
    }

    # Stream server output until Ctrl+C or job exit.
    try {
        while ($serverJob.State -eq 'Running') {
            Receive-Job -Job $serverJob
            Start-Sleep -Seconds 1
        }
        Receive-Job -Job $serverJob
    } finally {
        Write-Host ""
        Write-Host "Stopping server..." -ForegroundColor Yellow
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
    }
} finally {
    Pop-Location
}
