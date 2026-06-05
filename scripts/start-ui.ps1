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
      4. If web/dist is missing OR older than the newest source file (or
         -Clean is set): runs `npm run build`.
      5. Starts `npm start` as a tracked child process (PID captured).
      6. Waits up to 60s for the server to respond to GET /api/health,
         printing progress every 5s.
      7. Opens http://127.0.0.1:<port> in the default browser.
      8. On Ctrl+C OR terminal close OR script exit, kills the child PID.

.PARAMETER Port
    Override the default port (8765). Sets NIGHTINGALE_UI_PORT for the server.

.PARAMETER Clean
    Delete ui/web/dist/ before building. Useful after a git pull that may have
    introduced source changes that the mtime-comparison stale-check can miss.

.PARAMETER Docker
    Run the UI as a Docker container ("container mode") via docker compose
    instead of natively with Node. Container mode is dashboard-ONLY: it renders
    the mounted agent output tree but cannot run agents, approve queues, or edit
    secrets (no host Claude Code / claude.ai MCP / PowerShell inside the
    container). Use the native (no -Docker) path for those actions. Requires
    Docker Desktop. The published port is bound to the host's 127.0.0.1 only.

.NOTES
    Requires Windows + PowerShell 5.1+ AND Node.js 18 LTS or newer.
    Install Node from https://nodejs.org/ if needed.

    The Node server binds to 127.0.0.1 only — never accessible from the LAN.
    No firewall prompt.

    Caveat: PowerShell `finally` blocks run on normal exit + most exceptions,
    but NOT when the terminal window is closed via the X button or via
    `taskkill /f`. The Register-EngineEvent + CancelKeyPress handlers cover
    Ctrl+C and clean shell exit; the X-close case leaves a stranded node
    process. If that happens, kill it manually:
      Get-Process -Name node | Where-Object { $_.MainWindowTitle -eq '' } | Stop-Process
#>

param(
    [int]$Port = 8765,
    [switch]$Clean,
    [switch]$Docker
)

$ErrorActionPreference = 'Stop'

# --- PowerShell version check ------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell $($PSVersionTable.PSVersion) detected; this script requires 5.1 or newer."
    exit 1
}

# --- Docker (container) mode -------------------------------------------------
# Dashboard-only. Builds + starts the container detached via docker compose,
# waits for health, opens the browser, and returns (the container keeps running
# under Docker's restart policy; stop it with `docker compose down`).
if ($Docker) {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        Write-Error "Docker was not found on PATH. Install Docker Desktop, or run without -Docker for the native UI."
        exit 1
    }
    $repoRootD = Split-Path -Parent $PSScriptRoot
    $uiDirD = Join-Path $repoRootD 'ui'
    if (-not (Test-Path (Join-Path $uiDirD 'docker-compose.yml'))) {
        Write-Error "ui/docker-compose.yml not found. Are you in the nightingale repo?"
        exit 1
    }
    Write-Host ""
    Write-Host "Starting Nightingale UI in Docker (container mode — dashboard only)..." -ForegroundColor Cyan
    Write-Host "Agent runs / approvals / secrets edits are DISABLED in this mode (use the native UI for those)." -ForegroundColor DarkGray

    $env:NIGHTINGALE_UI_PORT = $Port.ToString()
    Push-Location $uiDirD
    try {
        & docker compose up -d --build
        if ($LASTEXITCODE -ne 0) {
            Write-Error "docker compose up failed (exit $LASTEXITCODE). See the output above."
            exit 1
        }
    } finally {
        Pop-Location
    }

    $url = "http://127.0.0.1:$Port"
    Write-Host ""
    Write-Host "Waiting for the container to become healthy at $url ..." -ForegroundColor Cyan
    $healthy = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        try {
            $resp = Invoke-WebRequest -Uri "$url/api/health" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -eq 200) { $healthy = $true; break }
        } catch { }
        if (($i + 1) % 5 -eq 0) { Write-Host "  still waiting... ($($i + 1)s)" -ForegroundColor DarkGray }
    }
    if ($healthy) {
        Write-Host "Container healthy." -ForegroundColor Green
        Start-Process $url
    } else {
        Write-Warning "Container did not become healthy within 60s. Check: docker compose logs -f"
    }
    Write-Host ""
    Write-Host "Container is running detached. Manage it from ui/:" -ForegroundColor Green
    Write-Host "  docker compose logs -f      # tail logs"
    Write-Host "  docker compose down         # stop + remove"
    exit 0
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
    Write-Error "Could not determine the Node.js version (got: '$nodeVersionRaw')."
    Write-Error "Ensure a standard Node.js 18 LTS or newer is on PATH (https://nodejs.org/) and re-run."
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

# Track the launched npm/node PID for cleanup. Set later when we spawn it.
$script:nodePid = $null

# Register handlers so the node child process gets killed when this script
# exits — whether by Ctrl+C, normal completion, or any exception. PowerShell
# doesn't reliably trap window-close, so the script header above documents
# the manual recovery for that edge case.
$cleanup = {
    if ($script:nodePid) {
        try {
            $proc = Get-Process -Id $script:nodePid -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $script:nodePid -Force -ErrorAction SilentlyContinue
            }
        } catch { }
        $script:nodePid = $null
    }
}
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $cleanup
try {
    [Console]::TreatControlCAsInput = $false
    [Console]::CancelKeyPress += {
        param($s, $e)
        # Don't let CTRL+C kill the host before our cleanup; the script's
        # normal flow will see it and exit, then PowerShell.Exiting fires
        # our cleanup. e.Cancel = $false means "proceed with normal handling".
        if ($script:nodePid) {
            try {
                Stop-Process -Id $script:nodePid -Force -ErrorAction SilentlyContinue
            } catch { }
            $script:nodePid = $null
        }
    }
} catch {
    # [Console] might not be available in all hosts (e.g. ISE). Non-fatal.
}

Push-Location $uiDir
try {
    # --- npm install if needed ----------------------------------------------
    $nodeModules = Join-Path $uiDir 'node_modules'
    if (-not (Test-Path $nodeModules)) {
        Write-Host ""
        Write-Host "Installing dependencies (one-time, ~30-60s)..." -ForegroundColor Cyan
        & npm install
        if ($LASTEXITCODE -ne 0) {
            Write-Error "npm install failed (exit $LASTEXITCODE)."
            Write-Error "Common causes:"
            Write-Error "  - No internet connection or corporate proxy blocking npm registry"
            Write-Error "  - Corrupted npm cache (try: cd ui; npm cache clean --force; npm install)"
            Write-Error "  - Permission issues on node_modules (try: rm -r node_modules; npm install)"
            Write-Error "See ui/README.md troubleshooting section."
            exit 1
        }
    }

    # --- npm build if dist missing, stale, or -Clean specified --------------
    $distDir = Join-Path $uiDir 'web\dist'
    if ($Clean -and (Test-Path $distDir)) {
        Write-Host "Cleaning web/dist/ before build..." -ForegroundColor Cyan
        Remove-Item -Recurse -Force $distDir
    }
    $needsBuild = $true
    if (Test-Path $distDir) {
        # Find newest source mtime vs newest dist mtime.
        $newestSrc = Get-ChildItem -Path (Join-Path $uiDir 'web\src') -Recurse -File -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First 1
        $newestDist = Get-ChildItem -Path $distDir -Recurse -File -ErrorAction SilentlyContinue |
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

    # --- Start the server as a tracked child process ------------------------
    $env:NIGHTINGALE_UI_PORT = $Port.ToString()
    # FORCE_COLOR=0 prevents npm/Express from emitting ANSI codes that the
    # legacy PS host renders as garbage (modern Windows Terminal handles
    # them fine, but we can't assume that).
    $env:FORCE_COLOR = '0'

    # Use 127.0.0.1 literally rather than 'localhost' — on IPv6-only hosts
    # localhost may resolve to ::1 and miss the server's IPv4 bind.
    $url = "http://127.0.0.1:$Port"

    Write-Host ""
    Write-Host "Starting Nightingale UI on $url ..." -ForegroundColor Cyan
    Write-Host "(Ctrl+C to stop. The server binds to 127.0.0.1 only — not exposed on your LAN.)"
    Write-Host ""

    # Start `npm start` as a tracked child so we can kill its node descendant
    # cleanly on exit. Start-Process -PassThru returns a Process object whose
    # Id we capture. -NoNewWindow keeps stdout in this console so the operator
    # sees Express's startup log.
    $proc = Start-Process -FilePath 'npm.cmd' -ArgumentList 'start' `
                          -WorkingDirectory $uiDir `
                          -NoNewWindow -PassThru
    $script:nodePid = $proc.Id

    # --- Poll /api/health for up to 60s -------------------------------------
    $healthy = $false
    $elapsed = 0
    $maxWait = 60
    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds 1
        $elapsed++
        if (-not (Get-Process -Id $script:nodePid -ErrorAction SilentlyContinue)) {
            Write-Warning "Server process exited before becoming healthy. Check the output above."
            exit 1
        }
        try {
            $resp = Invoke-WebRequest -Uri "$url/api/health" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -eq 200) {
                $healthy = $true
                break
            }
        } catch {
            # not ready yet — keep polling
        }
        if ($elapsed % 5 -eq 0) {
            Write-Host "  still waiting... (${elapsed}s)" -ForegroundColor DarkGray
        }
    }

    if (-not $healthy) {
        Write-Warning "Server did not become healthy within ${maxWait}s."
        Write-Warning "The process is still running (PID $script:nodePid). Browser will open but may show a connection error."
    } else {
        Write-Host "Server healthy." -ForegroundColor Green
        Start-Process $url
    }

    # --- Wait for the child to exit (or Ctrl+C) -----------------------------
    Write-Host ""
    Write-Host "Server running. Ctrl+C in this terminal to stop." -ForegroundColor Green
    # Tight loop on process liveness. Cheaper than Wait-Process which blocks
    # signal handling on some PowerShell hosts.
    while (Get-Process -Id $script:nodePid -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 1
    }
    Write-Host ""
    Write-Host "Server exited." -ForegroundColor Yellow
} finally {
    Pop-Location
    & $cleanup
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
}
