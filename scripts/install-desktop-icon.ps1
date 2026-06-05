<#
.SYNOPSIS
    Creates (or removes) a Windows Desktop shortcut that opens the Nightingale
    UI control panel. Phase 4 of the UI / workflow overhaul.

.DESCRIPTION
    Adds a "Nightingale UI" icon to the operator's Desktop so the dashboard can
    be opened with a double-click, no terminal required.

    Two shortcut shapes are supported:

      Native (default)  -> a .lnk that runs scripts/start-ui.ps1. That launcher
                           starts the loopback Express server, waits for health,
                           and opens the browser. This is the right choice when
                           you run the UI with Node directly (the common case).

      -Docker           -> a .lnk that runs scripts/start-ui.ps1 -Docker, which
                           does `docker compose up -d` (a no-op if the container
                           is already running under its restart policy) and then
                           opens the browser.

      -UrlOnly          -> a plain .url Internet Shortcut pointing straight at
                           http://127.0.0.1:<Port>. Use this only when the UI is
                           already running as an always-on service (e.g. the
                           Docker container with restart: unless-stopped) so the
                           address is live without launching anything. If the
                           server is down, this shortcut just fails to connect.

    The icon itself (an indigo disc with a white "N", matching the web favicon)
    is generated on demand into scripts/assets/nightingale.ico the first time
    this script runs. No binary asset is committed; generation is deterministic
    and self-contained (System.Drawing -> a 256x256 PNG wrapped in a Vista-style
    .ico container). Pass -Force to regenerate it.

.PARAMETER Docker
    Make the shortcut launch the UI in Docker/container mode (start-ui.ps1
    -Docker) instead of the native Node launcher. Ignored with -UrlOnly.

.PARAMETER UrlOnly
    Create a plain .url Internet Shortcut to http://127.0.0.1:<Port> instead of
    a launcher .lnk. Assumes the server is already running.

.PARAMETER Port
    Port the UI listens on. Used for the -UrlOnly target and passed to
    start-ui.ps1. Default 8765.

.PARAMETER ShortcutName
    Base name of the Desktop shortcut (no extension). Default "Nightingale UI".

.PARAMETER Remove
    Delete the Desktop shortcut (.lnk and .url variants) and exit. Does not
    delete the generated icon asset.

.PARAMETER Force
    Regenerate the icon asset even if it already exists.

.NOTES
    Windows-only. PowerShell 5.1+ (System.Drawing + WScript.Shell COM are .NET
    Framework / Windows facilities). ASCII-only source on purpose (PS 5.1
    mis-parses non-ASCII in BOM-less files).

    This script does not modify scheduled tasks, secrets, or any agent behavior.
    It only writes a shortcut to your Desktop and an icon under scripts/assets/.
#>

param(
    [switch]$Docker,
    [switch]$UrlOnly,
    [int]$Port = 8765,
    [string]$ShortcutName = 'Nightingale UI',
    [switch]$Remove,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Windows-only guard ------------------------------------------------------
# PS 5.1 has no $IsWindows (always Windows); PS 6+/7 defines it. Short-circuit
# so the 5.1 path never evaluates the undefined variable.
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    Write-Error 'install-desktop-icon.ps1 is Windows-only (it uses WScript.Shell + System.Drawing).'
    exit 1
}

# --- Resolve paths -----------------------------------------------------------
$repoRoot   = Split-Path -Parent $PSScriptRoot
$startUi     = Join-Path $PSScriptRoot 'start-ui.ps1'
$assetsDir   = Join-Path $PSScriptRoot 'assets'
$icoPath     = Join-Path $assetsDir 'nightingale.ico'

try {
    $desktop = [Environment]::GetFolderPath('Desktop')
} catch {
    Write-Error "Could not resolve the Desktop folder: $($_.Exception.Message)"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path $desktop)) {
    Write-Error "Desktop folder not found (got: '$desktop')."
    exit 1
}

$lnkPath = Join-Path $desktop ($ShortcutName + '.lnk')
$urlPath = Join-Path $desktop ($ShortcutName + '.url')

# --- Remove mode -------------------------------------------------------------
if ($Remove) {
    $removed = $false
    foreach ($p in @($lnkPath, $urlPath)) {
        if (Test-Path $p) {
            Remove-Item -Path $p -Force
            Write-Host "Removed $p" -ForegroundColor Yellow
            $removed = $true
        }
    }
    if (-not $removed) {
        Write-Host "No '$ShortcutName' shortcut found on the Desktop." -ForegroundColor DarkGray
    }
    exit 0
}

# --- Generate the icon asset (once, deterministic) ---------------------------
function New-NightingaleIcon {
    param([string]$Path)

    Add-Type -AssemblyName System.Drawing

    $size = 256
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear([System.Drawing.Color]::Transparent)

        # Indigo disc (#6366f1), matching ui/web/index.html favicon.
        $indigo = [System.Drawing.ColorTranslator]::FromHtml('#6366f1')
        $discBrush = New-Object System.Drawing.SolidBrush($indigo)
        $margin = [int]($size * 0.06)
        $g.FillEllipse($discBrush, $margin, $margin, ($size - 2 * $margin), ($size - 2 * $margin))
        $discBrush.Dispose()

        # White "N", centered.
        $font = New-Object System.Drawing.Font('Segoe UI', [single]($size * 0.5), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
        $g.DrawString('N', $font, $white, $rect, $fmt)
        $font.Dispose(); $white.Dispose(); $fmt.Dispose()
    } finally {
        $g.Dispose()
    }

    # PNG-compressed (Vista+) single-image .ico. width/height bytes = 0 => 256.
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $png = $ms.ToArray()
    $ms.Dispose(); $bmp.Dispose()

    $out = New-Object System.IO.MemoryStream
    $bw  = New-Object System.IO.BinaryWriter($out)
    try {
        # ICONDIR
        $bw.Write([uint16]0)              # reserved
        $bw.Write([uint16]1)              # type = icon
        $bw.Write([uint16]1)              # image count
        # ICONDIRENTRY
        $bw.Write([byte]0)               # width  (0 => 256)
        $bw.Write([byte]0)               # height (0 => 256)
        $bw.Write([byte]0)               # palette colors
        $bw.Write([byte]0)               # reserved
        $bw.Write([uint16]1)             # color planes
        $bw.Write([uint16]32)            # bits per pixel
        $bw.Write([uint32]$png.Length)   # size of image data
        $bw.Write([uint32]22)            # offset to image data (6 + 16)
        $bw.Write($png)
        $bw.Flush()
        [System.IO.File]::WriteAllBytes($Path, $out.ToArray())
    } finally {
        $bw.Dispose(); $out.Dispose()
    }
}

if (-not (Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Path $assetsDir | Out-Null
}

$iconOk = $true
if ($Force -or -not (Test-Path $icoPath)) {
    try {
        New-NightingaleIcon -Path $icoPath
        Write-Host "Generated icon: $icoPath" -ForegroundColor Green
    } catch {
        $iconOk = $false
        Write-Warning "Icon generation failed ($($_.Exception.Message)); the shortcut will use a default icon."
    }
} else {
    Write-Host "Using existing icon: $icoPath" -ForegroundColor DarkGray
}

# --- Create the shortcut -----------------------------------------------------
if ($UrlOnly) {
    # Plain Internet Shortcut. Assumes the server is already running.
    if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force }   # avoid two shortcuts of the same name
    $iconLines = ''
    if ($iconOk -and (Test-Path $icoPath)) {
        $iconLines = "IconFile=$icoPath`r`nIconIndex=0`r`n"
    }
    $content = "[InternetShortcut]`r`nURL=http://127.0.0.1:$Port`r`n$iconLines"
    [System.IO.File]::WriteAllText($urlPath, $content, (New-Object System.Text.ASCIIEncoding))
    Write-Host ""
    Write-Host "Created Desktop shortcut: $urlPath" -ForegroundColor Green
    Write-Host "  -> http://127.0.0.1:$Port (server must already be running)" -ForegroundColor DarkGray
    exit 0
}

# Launcher .lnk (native or Docker). Target = powershell.exe running start-ui.ps1.
if (-not (Test-Path $startUi)) {
    Write-Error "start-ui.ps1 not found at $startUi. Are you running this from the nightingale repo's scripts/ folder?"
    exit 1
}
if (Test-Path $urlPath) { Remove-Item $urlPath -Force }       # avoid two shortcuts of the same name

$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $psExe)) {
    $psCmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($psCmd) { $psExe = $psCmd.Source } else {
        Write-Error "Could not locate powershell.exe."
        exit 1
    }
}

$dockerArg = ''
if ($Docker) { $dockerArg = ' -Docker' }
# -NoExit keeps the console open so the operator sees the server log and can
# Ctrl+C to stop it (native mode). -ExecutionPolicy Bypass scopes only to this
# launched process; it does not change the machine policy.
$arguments = "-NoExit -ExecutionPolicy Bypass -File `"$startUi`" -Port $Port$dockerArg"

$WshShell = New-Object -ComObject WScript.Shell
try {
    $sc = $WshShell.CreateShortcut($lnkPath)
    $sc.TargetPath       = $psExe
    $sc.Arguments        = $arguments
    $sc.WorkingDirectory = $repoRoot
    $sc.WindowStyle      = 1
    $modeLabel = if ($Docker) { 'Docker' } else { 'native' }
    $sc.Description       = "Launch the Nightingale UI control panel ($modeLabel)"
    if ($iconOk -and (Test-Path $icoPath)) {
        $sc.IconLocation = "$icoPath,0"
    }
    $sc.Save()
} finally {
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell) | Out-Null
}

Write-Host ""
Write-Host "Created Desktop shortcut: $lnkPath" -ForegroundColor Green
if ($Docker) {
    Write-Host "  Double-click to start the UI in Docker and open the dashboard." -ForegroundColor DarkGray
} else {
    Write-Host "  Double-click to start the UI and open the dashboard." -ForegroundColor DarkGray
}
Write-Host "  Remove later with: scripts\install-desktop-icon.ps1 -Remove" -ForegroundColor DarkGray
exit 0
