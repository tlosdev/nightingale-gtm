# nightingale-gtm — Project Context

## What this repo is

Two signal-first prospect-discovery agents for Nightingale's GTM motion. They scan public clinical-trial, regulatory, funding, and academic-research feeds on a weekly cadence and emit a qualified-companies markdown file to the user's Desktop. They are the **signal-first complement** to the company-first `prospecter` agent that lives in Nightingale's main internal repo (not here).

This repo is meant to be cloned and run by anyone on the Nightingale team with Claude Code installed. The `scripts/install-schedule.{ps1,sh}` installer registers an OS-level scheduled task that runs both agents every Monday at 7:00 AM local time.

## Agents

- **`.claude/agents/signal-watcher-commercial.md`** — biotech / pharma / med-device, 10–200 employees, US. Six sources. Apollo enrichment gated to Strong-tier only.
- **`.claude/agents/signal-watcher-academic.md`** — US academic medical centers and research hospitals running human-subjects studies. Four sources. No Apollo; broad WebSearch regex for PI / Director / CISO titles.

Both follow the same shape: bootstrap Desktop output folder → scan sources in parallel → dedup against state file → cluster by company → tier Strong/Weak → write qualified-list markdown. Outputs live in `~/Desktop/nightingale-signals/` (cross-platform; `~` resolves correctly on Windows PowerShell, macOS, and Linux).

## Personas

- **`01-personas/commercial-persona.md`** — full ICP definition (3 buyer roles, disqualifiers, messaging principles, FDA-audit credibility line).
- **`01-personas/academic-persona.md`** — v0 stub. PI is champion, Department Chair / Research Director is buyer, IT / Security / Privacy is tech gatekeeper. Title sets are best-guess and will firm up as discovery calls produce real data.

## Working rules

- All paths inside agent files must stay portable. Reads are repo-relative (e.g. `01-personas/commercial-persona.md`). Writes go under `~/Desktop/nightingale-signals/` only. Never hardcode `C:\Users\...`, `/Users/...`, or `/home/...` paths.
- Both agents stop at the qualified-list file in v1. No outreach, no HubSpot sync.
- Scheduling is per-user / per-machine. The `scripts/install-schedule.*` installer is the canonical setup path. Do not commit per-user Claude Code `CronCreate` registrations or `.claude/settings.local.json` files.
- Persona files are the ICP source of truth. If qualification rules change, edit the persona file — the agents re-read it every run.
