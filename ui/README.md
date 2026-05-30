# Nightingale UI

Opt-in local control panel for the Nightingale GTM agent chain. Loopback-only Node.js + Express + React app that consumes the markdown/JSON files written by the agents to `~/Desktop/nightingale-signals/**` and provides a single-pane control surface — view today's brief, work through the HubSpot pending-approval queue, trigger agent runs on demand, and check connector / scheduled-task / secrets health.

The UI is **purely a renderer + thin action layer**. It does not write to HubSpot directly, does not store credentials, does not run on a schedule. Every action it takes is the same trigger phrase you could type into a terminal yourself (`claude -p "..."`). The agents remain the source of truth for everything; this is just a nicer way to look at and approve their output.

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

## What you see when you open it

| Route | What it shows |
|---|---|
| `/` (Dashboard) | Today's brief at-a-glance, pending HubSpot counts, any unauthorized-MCP warnings, quick "Run now" buttons for each agent. |
| `/brief` | Today's daily-brief rich-rendered: meetings expand to attendees + persona match + recent thread context + intro suggestions + talking points + HubSpot state. |
| `/pending` | Full HubSpot pending queue, cross-day. Inline Apply / Reject per item; multi-select for bulk actions. Each action invokes `claude -p "apply hubspot updates N,N from DATE"` (or `reject ...`) via the local server. |
| `/agents` | Control panel: one card per agent with scheduled-task status, last-run time, most recent output file, **Run now** button. |
| `/signals/:side` | Latest commercial / academic signal-watcher sweep, buying groups, intros. |
| `/resurfacer` | Top 5 contacts the re-surfacer surfaced today. |
| `/feedback` | Feedback-analyzer refinement reports with side-by-side diff viewer per proposed change. |
| `/diagnostics` | MCP connector status, scheduled-task status, secrets-file health (existence + schema only, never values). |

## How it stays safe

- **Loopback-only.** The Express server binds to `127.0.0.1`. Nobody on your LAN can reach it.
- **Trigger-phrase allowlist.** Every action that spawns `claude -p "..."` must match a regex in `server/trigger-allowlist.ts`. Arbitrary trigger phrases are refused with HTTP 400 — you cannot use this UI to invoke an unintended command, even by directly posting to the API.
- **No `shell: true`.** All subprocess spawns use array-argument form with `shell: false`. No string concatenation into commands.
- **Read scope confined to `~/Desktop/nightingale-signals/**`.** The server never reads anything outside that subtree.
- **Secrets endpoint is presence-only.** `/api/diagnostics/secrets` returns booleans like `has_apify_actor`, never the actual token or cookie values.
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
