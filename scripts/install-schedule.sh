#!/usr/bin/env bash
#
# install-schedule.sh
#
# Registers the Nightingale agent-chain schedules. Detects the OS and uses the
# right scheduler:
#   - macOS:  launchd (plists in ~/Library/LaunchAgents)
#   - Linux:  cron    (appends entries to the user crontab)
#
# Three scheduled jobs are registered:
#   - Monday 7am: weekly commercial sweep
#   - Monday 7am: weekly academic sweep
#   - Sun-Fri 7am: intro-finder daily morning (delivery + queue)
#
# Run once after cloning the nightingale repo.
#
# Prerequisites:
#   - Claude Code installed; `claude` on PATH
#   - ClinicalTrials.gov MCP connector authorized (both sweeps)
#   - Apollo.io MCP connector authorized (commercial sweep only)
#   - For intro-finder: ~/.nightingale/secrets.json populated via scripts/setup-secrets.sh
#   - Linux only: `at` and `atd` available (intro-finder schedules per-target one-shots via `at`)
#
# To uninstall:
#   macOS:  launchctl unload ~/Library/LaunchAgents/com.nightingale.{commercial-sweep,academic-sweep,intro-finder-morning}.plist
#           rm ~/Library/LaunchAgents/com.nightingale.{commercial-sweep,academic-sweep,intro-finder-morning}.plist
#   Linux:  crontab -e   (and delete the lines tagged "# nightingale")

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
echo "Repo root: $repo_root"

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: 'claude' CLI not found on PATH. Install Claude Code and ensure 'claude' is runnable from a fresh shell, then re-run." >&2
    exit 1
fi
claude_path="$(command -v claude)"
echo "claude CLI: $claude_path"

os="$(uname -s)"

install_macos() {
    local plist_dir="$HOME/Library/LaunchAgents"
    mkdir -p "$plist_dir"
    mkdir -p "$HOME/Desktop/nightingale-signals"

    # Monday-only sweep plist writer
    write_monday_plist() {
        local label="$1"
        local trigger_phrase="$2"
        local plist_path="$plist_dir/${label}.plist"
        cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>cd "${repo_root}" &amp;&amp; "${claude_path}" -p "${trigger_phrase}"</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>1</integer>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/Desktop/nightingale-signals/.${label}.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Desktop/nightingale-signals/.${label}.err.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF
        launchctl unload "$plist_path" 2>/dev/null || true
        launchctl load "$plist_path"
        echo "Registered: $label (Monday 7am local)"
    }

    # Sun-Fri intro-finder plist writer (6-day StartCalendarInterval array)
    write_intro_plist() {
        local label="$1"
        local trigger_phrase="$2"
        local plist_path="$plist_dir/${label}.plist"
        cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>cd "${repo_root}" &amp;&amp; "${claude_path}" -p "${trigger_phrase}"</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>${HOME}/Desktop/nightingale-signals/.${label}.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Desktop/nightingale-signals/.${label}.err.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF
        launchctl unload "$plist_path" 2>/dev/null || true
        launchctl load "$plist_path"
        echo "Registered: $label (Sun-Fri 7am local)"
    }

    write_monday_plist "com.nightingale.commercial-sweep"      "weekly commercial sweep"
    write_monday_plist "com.nightingale.academic-sweep"        "weekly academic sweep"
    write_intro_plist  "com.nightingale.intro-finder-morning"  "intro-finder daily morning"
}

install_linux() {
    # Preflight: warn (but don't block) if `at` is missing — intro-finder needs it
    if ! command -v at >/dev/null 2>&1; then
        echo "WARNING: 'at' is not installed. The intro-finder schedules per-target Apify calls via 'at'." >&2
        echo "Install it with:  sudo apt-get install at   (or yum/dnf install at) and 'sudo systemctl enable --now atd'." >&2
        echo "Continuing with cron registration; intro-finder will log per-target scheduling errors until 'at' is available." >&2
    fi

    local marker="# nightingale"
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    local cleaned
    cleaned="$(printf '%s\n' "$existing" | grep -v "$marker" || true)"

    mkdir -p "$HOME/Desktop/nightingale-signals"
    local log="${HOME}/Desktop/nightingale-signals/.cron.log"

    # Monday 7am sweeps + Sun-Fri 7am intro-finder
    local new_entries
    new_entries="$(cat <<EOF
0 7 * * 1       cd "${repo_root}" && "${claude_path}" -p "weekly commercial sweep" >> "${log}" 2>&1 ${marker}
0 7 * * 1       cd "${repo_root}" && "${claude_path}" -p "weekly academic sweep"   >> "${log}" 2>&1 ${marker}
0 7 * * 0,1,2,3,4,5 cd "${repo_root}" && "${claude_path}" -p "intro-finder daily morning" >> "${log}" 2>&1 ${marker}
EOF
)"

    printf '%s\n%s\n' "$cleaned" "$new_entries" | crontab -
    echo "Registered three crontab entries tagged '${marker}'. Verify with: crontab -l"
}

case "$os" in
    Darwin)
        install_macos
        ;;
    Linux)
        install_linux
        ;;
    *)
        echo "ERROR: Unsupported OS '$os'. This script supports macOS (launchd) and Linux (cron)." >&2
        echo "For Windows, run scripts/install-schedule.ps1 from an elevated PowerShell prompt." >&2
        exit 1
        ;;
esac

echo ""
echo "Done."
echo "Next sweep:        next Monday at 7:00 AM local time."
echo "Next intro-finder: next Sun-Fri at 7:00 AM local time. (Saturdays idle.)"
echo "Outputs land in: \$HOME/Desktop/nightingale-signals/{commercial,academic}/..."
echo ""
echo "If you have not yet run scripts/setup-secrets.sh, intro-finder will skip the"
echo "Apify lookup step and write a SECRETS_MISSING-<date>.md notice. Run it before"
echo "the next Sun-Thu 7am if you want intros to fire."
