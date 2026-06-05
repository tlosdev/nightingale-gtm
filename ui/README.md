# Nightingale UI

Opt-in local control panel for the Nightingale GTM agent chain. Loopback-only Node.js + Express + React app that consumes the markdown/JSON files written by the agents to `~/Desktop/nightingale-signals/**` and provides a single-pane control surface across **four tabs** — Dashboard (unified, category-tagged approval queue + re-surfaced contacts + today's brief), Agents (run on demand + view latest output), Settings (edit credentials + connector status), and Logs (live run output + scheduled-task state).

The UI is **a renderer + thin action layer**. It does not write to HubSpot directly and does not run on a schedule. The one credential it can write is `~/.nightingale/secrets.json`, via the Settings tab, through a dedicated script (values passed on stdin, never argv; owner-only ACL) — it never returns those values back to the browser. Every agent/approval action it takes is the same trigger phrase you could type into a terminal yourself (`claude -p "..."`). The agents remain the source of truth for everything; this is just a nicer way to look at and approve their output.

## Prerequisites

- Everything the repo root README already requires (Windows 10/11, Claude Code on PATH, MCP connectors authorized, etc.).
- **Node.js 18 LTS or newer.** Verify: `node --version`. Install: `https://nodejs.org/`.

That's it. No Python, no Electron, no Docker.

## Launch

From the repo root:

```powershell
.\scripts\start-ui.ps1
```

That script will:
1. Verify your Node version (≥ 18).
2. Run `npm install` if `ui/node_modules/` is missing (one-time, ~30-60s).
3. Run `npm run build` if `ui/web/dist/` is missing or older than the source.
4. Start the Express server on `http://localhost:8765`.
5. Open the URL in your default browser.

To stop: `Ctrl+C` in the terminal that runs the script.

## Configuration

| Env var | Default | What it does |
|---|---|---|
| `NIGHTINGALE_UI_PORT` | `8765` | Port the Express server binds to. Loopback (`127.0.0.1`) only — never `0.0.0.0`. |

## What you see when you open it (four tabs)

| Route | What it shows |
|---|---|
| `/` (Dashboard) | **Unified, category-tagged approval queue** — HubSpot updates, Pitch Deck Edits, and the Investor Newsletter merged into one list, each row carrying a colored category chip, with a filter-by-category control. Per-row Apply/Reject routes to the right backend automatically (`claude -p "apply hubspot updates N from DATE"` / `apply pitch-deck updates N from DATE` / `approve newsletter draft from DATE`). Below the queue: today's **re-surfaced contacts** and the **daily brief**, rich-rendered. The sidebar badge is the aggregate count across all three queues. |
| `/agents` | One card per agent: scheduled-task status, last-run time, most recent output timestamp, **Run now**, and **View output** (renders that agent's latest Desktop markdown). Run-now is **asynchronous** — it returns a run id immediately and links you to the Logs tab to watch it stream. |
| `/settings` | Editable credentials form (Apify token, Actor IDs, LinkedIn validation URL + `li_at` cookie, optional company-roster Actor, optional pitch-deck Drive pointer). Each field shows Configured ✓ / Not set; Save writes the changed fields only. Below: claude.ai MCP connector status with re-auth instructions (the browser can't drive that OAuth). |
| `/logs` | Recent runs (Run-now + Apply/Reject) with live status (running / ok / error / timeout) and a streaming log tail per run, plus the `Nightingale-*` scheduled-task table (state / last run / next run / last result). |

## How it stays safe

- **Loopback-only.** The Express server binds to `127.0.0.1`. Nobody on your LAN can reach it.
- **Trigger-phrase allowlist.** Every action that spawns `claude -p "..."` must match a regex in `server/trigger-allowlist.ts`. Arbitrary trigger phrases are refused with HTTP 400 — you cannot use this UI to invoke an unintended command, even by directly posting to the API.
- **No `shell: true`.** All subprocess spawns use array-argument form with `shell: false`. No string concatenation into commands.
- **Read scope confined to `~/Desktop/nightingale-signals/**`.** The only thing the server *writes* under that tree is its own run registry at `_runs/` (run status + streamed logs for the Logs tab); it never writes an agent's output tree.
- **Secrets are presence-only over the wire.** `/api/settings/secrets` (and the legacy `/api/diagnostics/secrets`) return booleans like `has_apify_actor_id`, never the actual token or cookie values. Saving a credential POSTs to `/api/settings/secrets`, which hands the values to `scripts/write-secrets.ps1` on **stdin** (never argv) for an ACL-first, owner-only atomic write.
- **Run model can't hang.** Agent runs spawn with the full user environment (minus known third-party secrets), an absolute-resolved `claude.exe`, a Windows process-tree kill on timeout, and a guaranteed-settle backstop — so a wedged run surfaces as `timeout`/`error` in Logs, never an infinite spinner.
- **No CORS opening, no telemetry, no outbound HTTP from the running server.**

## Development

```powershell
# Hot-reload dev mode (server on :8765, vite on :5173 with /api proxy)
npm run dev

# Type-check both server + web
npm run typecheck

# Production build (run once before `npm start`)
npm run build

# Start production server (serves built web + API)
npm start
```

Architecture overview lives in the repo-root plan file. Endpoint list lives in `server/routes/`. UI routes live in `web/src/routes/`.

## When this UI is NOT the right tool

- You need a CRM dashboard with charts → use HubSpot's own UI; this isn't trying to replace it.
- You want to manage agent schedules graphically → not in v1; edit `scripts/install-schedule.ps1` directly.
- You're on a non-Windows machine → the repo is Windows-only.
- You're worried about security exposing your machine on a network → the UI binds to loopback only and refuses non-localhost requests; this concern is already addressed.

## Stopping the UI

Just close the PowerShell window or hit `Ctrl+C`. There's no daemon, no service, no background process. The agents keep running on their normal scheduled-task cadence regardless of whether the UI is up.
