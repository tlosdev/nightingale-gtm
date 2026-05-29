# nightingale-gtm — Project Context

## What this repo is

Five signal-first prospect-discovery agents for Nightingale's GTM motion, plus three Windows PowerShell scripts that register them with Windows Task Scheduler and capture the credentials the intro-finder stage needs. The repo is **Windows-only** as of 2026-05 — `.sh` parity was dropped to reduce maintenance surface.

The chain has three stages:

1. **`signal-watcher-{commercial,academic}`** — Monday 7am sweeps. Six commercial / four academic public sources. Output: `~/Desktop/nightingale-signals/{side}/output/{side}-signals-{date}.md` (qualified-list markdown).
2. **`buying-group-finder-{commercial,academic}`** — auto-chained from each sweep. WebSearch-driven contact discovery per role bucket. Output: `~/Desktop/nightingale-signals/{side}/buying-groups/output/buying-group-{date}.md`. Academic side additionally scrapes publicly-published institutional + personal emails. **No Apollo. No pattern-guessed emails.**
3. **`intro-finder`** — runs daily Sun–Fri 7am. Pulls 1/5 of the active buying-group file per day; schedules per-target Windows Task Scheduler one-shots at randomized 8am–8pm times (min 30s gap); each one-shot invokes `scripts/run-one-apify-call.ps1` once. The next morning's delivery aggregates yesterday's results into `~/Desktop/nightingale-signals/{side}/intros/output/intros-{date}.md`. **No Apollo. No direct Apify calls from the agent — only the worker script touches Apify.**

## Personas

- **`01-personas/commercial-persona.md`** — full ICP (3 buyer roles, disqualifiers, messaging principles).
- **`01-personas/academic-persona.md`** — v0 stub. PI = champion, Department Chair / Research Director = buyer, IT / Security / Privacy = tech gatekeeper.

## Scripts

- **`scripts/install-schedule.ps1`** — registers three Windows Task Scheduler entries (Mon-only commercial sweep, Mon-only academic sweep, Sun–Fri intro-finder morning).
- **`scripts/setup-secrets.ps1`** — captures Apify API token + Actor ID + the user's LinkedIn profile URL + `li_at` cookie. Validates ALL four against Apify in one round-trip (header auth; `/v2/users/me` for token, single Actor run against the user's own profile for Actor + cookie). Writes `~/.nightingale/secrets.json` (schema v2) with restricted ACL.
- **`scripts/run-one-apify-call.ps1`** — per-target worker. Loads secrets, calls Apify Actor once via `Authorization: Bearer` header (token never in URL), polls, writes result JSON atomically via `.tmp` + `Move-Item`. Distinguishes `apify_actor_not_found` (404), `apify_rate_limited` (429), `cookie_expired` (auth-failure indicators in payload), and generic `apify_start_failed` / `apify_fetch_failed` statuses.

## Secrets file

Lives at `%USERPROFILE%\.nightingale\secrets.json`, schema v2:

```json
{
  "schema_version": 2,
  "created_at": "...",
  "updated_at": "...",
  "apify_api_token": "...",
  "apify_actor_id": "...",
  "apify_validation_url": "https://linkedin.com/in/your-slug",
  "linkedin_li_at": "..."
}
```

Restricted ACL set by setup-secrets.ps1 (only current user has access). The file lives outside the repo and cannot be git-add'd. The `.gitignore` excludes `.nightingale/` defense-in-depth.

## Working rules

- **Windows-only.** All paths use `$env:USERPROFILE` / `~` semantics that resolve to `C:\Users\{user}\...`. Do NOT write `.sh` scripts, do not add macOS/Linux dispatch branches, do not reference `bash`, `launchd`, or `cron`. Use PowerShell for every shell operation.
- **Never `schtasks /sd YYYY-MM-DD`.** That flag is locale-dependent and breaks for non-en-US users. Always use `Register-ScheduledTask` with a `[datetime]`-parsed `-At` argument.
- **Never put the Apify token in a URL query string.** Always use `-Headers @{Authorization = "Bearer $token"}` so the token does not leak into `Get-CimInstance Win32_Process` / process command-lines.
- **Never log the LinkedIn `li_at` cookie value.** Only the worker script reads it; agents only check file existence.
- **Never pattern-guess emails** (inherits from the 2026-05-06 5-bounce incident). Buying-group commercial emits no emails; academic emits only emails scraped verbatim from publicly-served pages.
- **Runtime artifacts live on the user's Desktop, never in the repo.** `~/Desktop/nightingale-signals/` is auto-created; `.gitignore` blocks it.
- **Stale artifact cleanup is mandatory.** Intro-finder Step 0 sweeps `.cookie-expired-*` older than 7 days and `daily-results/{date}/` older than 30 days.
- **Persona files are the ICP source of truth.** Agents re-read them every run — if qualification rules change, edit the persona, not the agent.
- **Per-user scheduling.** `install-schedule.ps1` is the canonical setup. Do not commit per-user `CronCreate` registrations or `.claude/settings.local.json`.

## When you're editing this repo

If a user clones this repo and opens Claude Code from it, both their personal `~/.claude/CLAUDE.md` and THIS file load as context simultaneously. Keep this file's content generic and project-scoped, never personal — no `C:\Users\ben\...` paths, no Ben-specific GitHub accounts, no "commit and push" preferences.
