# Desktop icon — one-click launch for the Nightingale UI (Phase 4)

A small convenience: put a **"Nightingale UI"** icon on your Windows Desktop so
you can open the control panel with a double-click instead of running a launcher
command in a terminal.

This is purely cosmetic plumbing. It does **not** change any agent behavior,
schedules, or secrets — it only writes a shortcut to your Desktop and an icon
file under `scripts/assets/`.

## Install

```powershell
# Native (default): shortcut starts the Node UI via start-ui.ps1
.\scripts\install-desktop-icon.ps1
```

You'll get a `Nightingale UI.lnk` on your Desktop. Double-clicking it runs
`scripts\start-ui.ps1` (which starts the loopback Express server, waits for
health, and opens `http://127.0.0.1:8765` in your browser). The console window
stays open so you can see the server log and press `Ctrl+C` to stop it.

### Variants

| Command | Shortcut | When to use |
|---|---|---|
| `install-desktop-icon.ps1` | `.lnk` running `start-ui.ps1` | Default. You run the UI with Node directly. |
| `install-desktop-icon.ps1 -Docker` | `.lnk` running `start-ui.ps1 -Docker` | You run the UI as a Docker container. `docker compose up -d` is a no-op if it's already up, then the browser opens. |
| `install-desktop-icon.ps1 -UrlOnly` | `.url` to `http://127.0.0.1:8765` | The UI is already running as an always-on service (e.g. the Docker container with `restart: unless-stopped`). Opens the address directly — does **not** start anything, so it just fails to connect if the server is down. |
| `install-desktop-icon.ps1 -Port 9000` | as above, port 9000 | Non-default port. Passed to `start-ui.ps1` and used for the `.url` target. |
| `install-desktop-icon.ps1 -Remove` | (deletes both `.lnk` and `.url`) | Remove the Desktop shortcut. |
| `install-desktop-icon.ps1 -Force` | regenerates the icon asset | Re-draw `scripts/assets/nightingale.ico`. |

Only one shortcut of the given name exists at a time — switching shapes
(`-Docker` <-> `-UrlOnly`) replaces the previous one.

## The icon asset

The icon (an indigo disc with a white "N", matching the web favicon) is
**generated on demand** into `scripts/assets/nightingale.ico` the first time you
run the script — a deterministic 256x256 PNG wrapped in a Vista-style `.ico`
container, drawn with `System.Drawing`. No binary asset is committed to the repo;
`scripts/assets/` is git-ignored. If generation ever fails (rare), the script
warns and the shortcut falls back to the default PowerShell icon.

## Notes / caveats

- **Windows-only.** The script guards and exits on non-Windows (it uses
  `WScript.Shell` + `System.Drawing`). ASCII-only source, like the other
  PowerShell scripts.
- **No elevation needed.** Unlike `install-runner.ps1`, this writes only to your
  own Desktop and the repo's `scripts/assets/` — no admin rights required.
- **Loopback only.** The shortcut opens `http://127.0.0.1:8765`; the server still
  binds to `127.0.0.1` only and is never exposed on your LAN.
- The shortcut is independent of agent scheduling. Whether the agents run via the
  GitHub Actions self-hosted runner (see `github-runner-setup.md`) or not, this
  icon just opens the dashboard that renders their output.
