#!/usr/bin/env bash
#
# install-schedule.sh
#
# Registers a weekly Monday 7:00 AM (local time) schedule that runs the two
# signal-watcher agents headlessly. Detects the OS and uses the right scheduler:
#   - macOS:  launchd (writes plists to ~/Library/LaunchAgents)
#   - Linux:  cron   (appends entries to the user crontab)
#
# Run once after cloning the nightingale-gtm repo.
#
# Prerequisites:
#   - Claude Code installed; `claude` on PATH
#   - Apollo.io MCP connector authorized (commercial agent only)
#   - ClinicalTrials.gov MCP connector authorized (both agents)
#   - Internet access from this machine on Monday mornings
#
# To uninstall:
#   macOS:  launchctl unload ~/Library/LaunchAgents/com.nightingale.{commercial,academic}-sweep.plist
#           rm ~/Library/LaunchAgents/com.nightingale.{commercial,academic}-sweep.plist
#   Linux:  crontab -e   (and delete the two lines tagged "# nightingale-gtm")

set -euo pipefail

# Resolve repo root (one directory above this script). Works whether the script is
# invoked from anywhere; resolves symlinks for the script path.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
echo "Repo root: $repo_root"

# Verify `claude` is on PATH
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

    write_plist() {
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
        # Unload any previous version, then load the new one
        launchctl unload "$plist_path" 2>/dev/null || true
        launchctl load "$plist_path"
        echo "Registered: $label (next run: next Monday 7:00 AM local)"
    }

    # Ensure log dir exists (launchd writes logs to Desktop/nightingale-signals/)
    mkdir -p "$HOME/Desktop/nightingale-signals"

    write_plist "com.nightingale.commercial-sweep" "weekly commercial sweep"
    write_plist "com.nightingale.academic-sweep"   "weekly academic sweep"
}

install_linux() {
    local marker="# nightingale-gtm"
    # Pull the existing crontab (if any), strip prior nightingale-gtm entries, then append fresh ones.
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    local cleaned
    cleaned="$(printf '%s\n' "$existing" | grep -v "$marker" || true)"

    local new_entries
    new_entries="$(cat <<EOF
0 7 * * 1 cd "${repo_root}" && "${claude_path}" -p "weekly commercial sweep" >> "${HOME}/Desktop/nightingale-signals/.cron.log" 2>&1 ${marker}
0 7 * * 1 cd "${repo_root}" && "${claude_path}" -p "weekly academic sweep"   >> "${HOME}/Desktop/nightingale-signals/.cron.log" 2>&1 ${marker}
EOF
)"

    mkdir -p "$HOME/Desktop/nightingale-signals"
    printf '%s\n%s\n' "$cleaned" "$new_entries" | crontab -
    echo "Registered two crontab entries tagged '${marker}'. Verify with: crontab -l"
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
echo "Next run: next Monday at 7:00 AM local time."
echo "Outputs land in: \$HOME/Desktop/nightingale-signals/{commercial,academic}/output/"
