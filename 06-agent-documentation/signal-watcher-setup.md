# signal-watcher — setup guide

This guide covers installing and running the two signal-watcher agents — `signal-watcher-commercial` and `signal-watcher-academic` — on a fresh machine after cloning the Nightingale repo. The agents are designed to be portable: anyone with access to the repo and the required MCP connectors can run them without editing the agent files.

---

## What these agents do

Both agents scan a curated set of public/free signal feeds, surface only events that have fired since the last run, qualify the firing entity against Nightingale's ICP, and emit a markdown qualified-list file to the user's Desktop. They stop at the qualified-list — no contact outreach, no HubSpot sync — in v1.

- `signal-watcher-commercial` — biotech / pharma / med-device sponsors, 10–200 employees, US. Sources: ClinicalTrials.gov, SEC EDGAR 8-Ks, openFDA, press wires, LinkedIn jobs, Apollo funding.
- `signal-watcher-academic` — US academic medical centers and research hospitals running human-subjects studies. Sources: ClinicalTrials.gov (academic Lead Sponsor or Facility), NIH RePORTER, SBIR/STTR, university press / news.

---

## Where outputs live

Both agents write to the **user's Desktop**, not into the cloned repo. This keeps the repo clean for other users and keeps your runtime artifacts user-local.

```
~/Desktop/nightingale-signals/
├── commercial/
│   ├── state/
│   │   └── seen-signals.json          # dedup + tier history
│   └── output/
│       └── commercial-signals-YYYY-MM-DD.md
└── academic/
    ├── state/
    │   └── seen-signals.json
    └── output/
        └── academic-signals-YYYY-MM-DD.md
```

The `~` resolves on Windows to `$env:USERPROFILE\Desktop\nightingale-signals\...`.

The folder tree is created automatically on first run — no manual `mkdir` needed.

---

## Prerequisites

1. **Windows 10/11** with PowerShell 5.1+ (Claude Code's `claude` CLI on PATH). This repo is Windows-only as of the 2026-05 cleanup; macOS and Linux are not supported.
2. **The Nightingale repo cloned locally** — open Claude Code from the cloned directory so the agents under `.claude/agents/` are discovered.
3. **MCP connectors authorized** for your Claude Code instance:
   - **ClinicalTrials.gov** — required for both agents (Source A in commercial, Source A in academic). No API key needed; just the MCP connector.
   - **Apollo.io** — required only for the **commercial** agent (Source F + Step 6 enrichment). The free tier is sufficient because enrichment is gated to Strong-tier companies only.
   - **WebFetch + WebSearch** — built into Claude Code. Required for SEC EDGAR (commercial), openFDA (commercial), press wires (commercial), LinkedIn jobs (commercial), NIH RePORTER (academic), SBIR/STTR (academic), and university press/news (academic).
4. **Internet access** to the public APIs: `efts.sec.gov`, `api.fda.gov`, `api.reporter.nih.gov`, `api.www.sbir.gov`.

There is no `.env` file, no API key to set, and no setup script. The only secrets involved are MCP-connector auth tokens, which Claude Code manages separately.

---

## First run

From the cloned repo, with Claude Code open:

### Commercial

Type one of these into the Claude Code prompt:

```
scan commercial signals
```

What happens:
1. The agent creates `~/Desktop/nightingale-signals/commercial/{state,output}/` if missing and seeds an empty `state/seen-signals.json`.
2. It scans all six sources for the last 14 days (the first-run lookback window).
3. It clusters by company, tiers Strong / Weak, runs Apollo enrichment on Strong-tier only, applies ICP disqualifiers.
4. It writes `commercial-signals-{today}.md` to the Desktop output folder.
5. It prints a terminal summary with per-source signal counts and the file path.

### Academic

```
scan academic signals
```

What happens:
1. The agent creates `~/Desktop/nightingale-signals/academic/{state,output}/` if missing.
2. It scans all four sources for the last 14 days.
3. It clusters by institution, tiers Strong / Weak. For Strong-tier institutions, it runs broad-regex WebSearch for Director / Department-Chair / CISO titles.
4. It writes `academic-signals-{today}.md` to the Desktop output folder.
5. It prints a terminal summary.

The academic agent does NOT call Apollo and does NOT need an Apollo connector authorized.

---

## Verifying the first run worked

After a successful first run, you should see:

- The folder tree under `~/Desktop/nightingale-signals/`
- A populated `state/seen-signals.json` with `last_run_date` set and a non-empty `seen_ids` map
- A markdown output file with Strong / Weak / Re-Surfaced sections (any of which can be empty on the first run — the file is still written)
- A terminal summary showing per-source counts

If the bootstrap folder appears but `seen_ids` is empty, that means the sources legitimately returned zero events in the lookback window (rare in practice but possible). Re-run with a longer lookback by waiting until the next scheduled run, or temporarily widen the date floor in the agent file.

---

## Optional — register the weekly cron

> **Note:** This `CronCreate` path is an **alternative** to `scripts/install-schedule.ps1`, **not** an addition to it. `install-schedule.ps1` already registers the commercial + academic sweeps (Monday 7am) as Windows Task Scheduler entries with these exact trigger phrases. If you have run `install-schedule.ps1`, do **not** also register the sweeps via `CronCreate` — you would double-register them and the sweeps would fire twice (doubling API usage and notifications). Use one mechanism or the other for the sweeps.

Both agents are designed to run weekly on Monday at 7am US Eastern. Registration is per-user (your schedule lives on your machine; it is not committed to the repo).

Inside Claude Code, register the two schedules using `CronCreate` (skip this if you used `install-schedule.ps1`):

- Commercial: schedule `0 7 * * 1`, timezone `America/New_York`, trigger phrase `weekly commercial sweep`
- Academic: schedule `0 7 * * 1`, timezone `America/New_York`, trigger phrase `weekly academic sweep`

(The exact `CronCreate` invocation depends on your Claude Code version; ask Claude `register a weekly cron for signal-watcher-commercial on Monday 7am ET` and confirm before it fires the tool call.)

To verify registration:

```
CronList
```

Both schedules should appear with the correct cron expression and timezone.

When a scheduled run fires, the agent additionally sends a single `PushNotification` with the headline signal counts so you see the result without opening the terminal. Manual triggers (`scan commercial signals` etc.) do not send a push notification — the terminal summary is sufficient.

To remove a schedule later: `CronDelete {schedule_id}`.

---

## Common operations after first run

| What | How |
|---|---|
| Manual sweep (commercial) | `scan commercial signals` |
| Manual sweep (academic) | `scan academic signals` |
| Manual buying-group discovery on latest sweep | `find buying group from latest commercial sweep` / `find buying group from latest academic sweep` |
| Manual intro-finder run (delivery + queue) | `intro-finder daily morning` |
| Manual intro-finder against a specific BG file | `find intros from {absolute path to a buying-group-{date}.md}` |
| Inspect sweep dedup state | Open `~/Desktop/nightingale-signals/{commercial|academic}/state/seen-signals.json` |
| Inspect buying-group state | Open `~/Desktop/nightingale-signals/{commercial|academic}/buying-groups/state/found-companies.json` |
| Inspect intro-finder cursor | Open `~/Desktop/nightingale-signals/{commercial|academic}/intros/state/cursor.json` |
| Inspect intro-finder found-mutuals | Open `~/Desktop/nightingale-signals/{commercial|academic}/intros/state/found-mutuals.json` |
| Force a re-surface for a known company | Edit `company_tier_history.{key}.signal_types_seen` in the sweep state JSON to remove one type; next run will re-surface when that type fires |
| Force re-query of contacts for a known company | Delete the entry from `buying-groups/state/found-companies.json` (or set `last_found` to a date >30 days ago); next buying-group run will re-discover |
| Force re-query of mutuals for a known target | Delete the entry from `intros/state/found-mutuals.json` (or set `last_found` to a date >30 days ago); the next intro-finder queue will re-discover |
| Clear all state (start over) | Delete the `seen-signals.json`, `found-companies.json`, `cursor.json`, and `found-mutuals.json` files; next runs re-bootstrap |
| Tighten academic title regex | Edit the buyer/CISO title lists in `01-personas/academic-persona.md` (the agent reads it every run) |
| Disable a flaky source | Edit the agent file to comment out the source block; e.g. LinkedIn jobs WebSearch occasionally degrades |
| Disable the buying-group auto-chain | Delete `Step 11 — Hand off to buying-group-finder-*` from the signal-watcher agent file. The sweep will still run; contact discovery just won't fire after it. |
| Disable the intro-finder daily morning | `Unregister-ScheduledTask -TaskName 'Nightingale-Intro-Finder-Morning' -Confirm:$false`. Sweeps + buying-group-finder continue to run. |
| Refresh LinkedIn cookie / Apify token / Actor ID | Re-run `scripts/setup-secrets.ps1`. Prompts per-secret. Clears any active cookie-expired sentinel. |

---

## What this agent set does NOT do (v1)

- No outreach message generation — the qualified-list file is the deliverable.
- No HubSpot company / contact / association creation.
- No Apollo enrichment on Weak-tier commercial companies (free-tier credit gate).
- No Apollo at all for the academic agent.
- No conference-abstract scraping (ASCO / AHA / JPM) — quarterly cadence does not fit a weekly cron.
- No Crunchbase or other paid data sources — Apollo `last_raised_at` covers the high-value commercial funding cases.

These are explicitly deferred. Adding any of them is a follow-up project, not a v1 change.

---

## Troubleshooting

**The agent fails at Step 0 with a permission error on `~/Desktop/`.** Some corporate-managed Windows profiles restrict the Desktop folder. Manually create `~/Desktop/nightingale-signals/` once via File Explorer and rerun — Step 0 will accept an existing folder and proceed.

**Apollo returns `API_INACCESSIBLE` / rate limit.** The commercial agent's Step 2 Source F and Step 6 enrichment both depend on Apollo. If Apollo is gated, the commercial agent will log the failure and continue with the other five sources — you'll get a qualified-list missing the funding signal and missing Apollo enrichment fields. Restore your Apollo connector and re-run.

**WebSearch returns zero LinkedIn job results consistently.** LinkedIn periodically degrades its public job-posting search index. The agent will log `Source E returned 0 results — possible search-index degradation, continuing` and skip the source for that run. This is expected; do not chase it.

**The output file contains a clearly wrong company (e.g., an academic center surfaced in the commercial output).** Both agents have explicit cross-agent guard rails (commercial Hard Rule 8, academic Hard Rule 8). If a guard rail mis-fires, fix the regex in the responsible agent file and re-run.

---

## Auto-chain: buying-group discovery after each sweep

Every scheduled Monday sweep ends with a **Step 11 hand-off** that invokes the corresponding buying-group-finder agent on the just-written sweep file. The chain happens inside the same scheduled task — no second cron entry is needed.

**What the chain does:**

- `signal-watcher-commercial` writes its sweep file, prints the terminal summary, fires its push notification, then invokes `buying-group-finder-commercial` with the sweep file path. The contact discovery agent runs WebSearch-only (no Apollo) for Economic Buyer / Technical Gatekeeper / Champion candidates and writes a `buying-group-{date}.md` file to `~/Desktop/nightingale-signals/commercial/buying-groups/output/`. **No emails on the commercial side.**
- `signal-watcher-academic` does the same with `buying-group-finder-academic`. PIs already named in the sweep are copied through; WebSearch finds Buyer (Director CRU / Department Chair / etc.) and Tech Gatekeeper (CISO / IT Security / HIPAA Privacy) candidates; WebFetch scrapes publicly-published **institutional emails** (`clinical.research@emory.edu`) and **personal emails** (faculty bio pages, NIH RePORTER `contact_email`). Pattern-guessed emails are forbidden.

**State and the 30-day re-query gate:** the buying-group-finder maintains its own state at `~/Desktop/nightingale-signals/{commercial|academic}/buying-groups/state/found-companies.json`. If a company / institution already has contact records in that state file from <30 days ago, the next chain run skips it. Skipped companies appear in a "Skipped (recent contacts on file)" section in the new buying-group file.

**Disabling the chain:** if you want sweep-only behavior, delete the `Step 11 — Hand off to buying-group-finder-*` block from the signal-watcher agent file. The signal-watcher will continue to run normally; the contact discovery agent simply won't fire.

**Manual trigger:** you can run buying-group discovery on any sweep file by typing `find buying group from latest commercial sweep` (or `academic`), or `find buying group from {explicit path}`. The 30-day gate still applies.

---

## Related files

| File | Role |
|---|---|
| `.claude/agents/signal-watcher-commercial.md` | The commercial sweep agent |
| `.claude/agents/signal-watcher-academic.md` | The academic sweep agent |
| `.claude/agents/buying-group-finder-commercial.md` | Commercial contact discovery (auto-chained after the commercial sweep) |
| `.claude/agents/buying-group-finder-academic.md` | Academic contact discovery + email scraping (auto-chained after the academic sweep) |
| `.claude/agents/intro-finder.md` | Daily warm-intro discovery (Sun-Fri 7am). Consumes the active buying-group file, calls Apify per target via OS-scheduled one-shots, delivers each prior day's intros each morning. |
| `.claude/agents/gmail-resurfacer.md` | Daily Gmail re-surfacer (Mon-Fri 7am). Walks 12 months of Gmail history forward from a cursor, scores threads against both personas, surfaces top 5 contacts to re-engage today with HubSpot state annotation. Read-only against Gmail/HubSpot/Apollo. No verbatim email body in output. |
| `.claude/agents/daily-brief.md` | Daily morning calendar brief (Mon-Fri 6am, fires before the 7am stack). Pulls today + tomorrow's calendar, filters to external meetings, assembles per-meeting prep with persona match, recent thread context, cross-agent context, Layer-A cached intro suggestions (via intro-finder's found-mutuals.json) and Layer-B fresh persona-roster intros (Apify or WebSearch fallback). Read-only against all sources. Also surfaces the hubspot-manager pending-approval queue at the top of the brief. |
| `scripts/run-one-apify-company-roster.ps1` | Layer-B worker for daily-brief. Invoked synchronously per meeting attendee (cap 8/day). Reads optional `apify_company_roster_actor_id` from secrets v4; if absent, the agent falls back to WebSearch without invoking this script. Same conventions as `run-one-apify-call.ps1` (header auth, atomic write, distinct 404 / 429 / cookie-expired statuses). |
| `.claude/agents/hubspot-manager.md` | Nightly Mon-Sun 11pm HubSpot writer. Reads last 24h of Granola transcripts + Gmail replies, generates per-source candidates, auto-applies up to 20 low-risk items (call/email logging + summary notes + populate-empty contact metadata), queues everything else for next-morning daily-brief approval. Only agent that writes to HubSpot. Strict guardrails: no deletes, no merges, no overwriting recent values, no cross-operator assignment, active-deal protection. Idempotent via dedup keys + transaction log. Requires the HubSpot MCP connector authorized in Claude Code (OAuth walkthrough in this same doc under "HubSpot Manager"). |
| `ui/` + `scripts/start-ui.ps1` | Optional local Node.js + React control panel. Reads agent Desktop outputs, surfaces the approval queues with inline Apply/Reject — HubSpot updates, Pitch Deck Edits, and Investor Newsletter (Approve & create Gmail draft) — and lets you trigger any agent on demand. Loopback-only Express server on `http://localhost:8765`; no per-machine state, no scheduled task. Launch with `.\scripts\start-ui.ps1` (requires Node 18+); stop with Ctrl+C. See `ui/README.md`. |
| `.claude/agents/feedback-analyzer.md` | On-demand or weekly feedback-loop agent. Reads call transcripts from `/curanostics/nightingale/call transcripts` (team-shared Drive folder) and the operator's inbound Gmail replies, scores them with a weighted confidence model, and emits a propose-only refinement report with literal before/after diffs against the persona files (and any optional diff-target files present in the local checkout). Outputs land on the operator's Desktop at `~/Desktop/nightingale-signals/feedback-insights/`, never in the repo tree. |
| `scripts/setup-secrets.ps1` | One-time per-machine setup. Prompts for Apify API token + Actor ID + your LinkedIn profile URL + `li_at` cookie. Validates all four against Apify in one round-trip. Writes `~/.nightingale/secrets.json` with restricted ACL. |
| `scripts/run-one-apify-call.ps1` | Per-target worker invoked by a Windows Scheduled Task one-shot. Calls Apify Actor once via header auth, polls, writes result JSON atomically. Handles 404 / 429 / cookie-expiry as distinct statuses. |
| `scripts/install-schedule.ps1` | Registers the eight Windows Task Scheduler entries: daily-brief (Mon-Fri 6am), commercial sweep + academic sweep (Mon 7am), intro-finder (Sun-Fri 7am), gmail-resurfacer (Mon-Fri 7am), hubspot-manager (nightly 11pm), investor-analyzer (Mon 8am, chains pitch-deck-updater), investor-newsletter (biweekly Fri 9am). |
| `.claude/agents/investor-analyzer.md` | Weekly Mon 8am. Investor-persona refinement from investor call transcripts + investor email replies (propose-only diffs to `01-personas/investor-persona.md`, Desktop output). Auto-chains pitch-deck-updater. See `investor-analyzer-usage.md`. |
| `.claude/agents/pitch-deck-updater.md` | Chained off investor-analyzer (no own task). Reads the Google Slides deck read-only (pointer = `pitch_deck_drive_file_id` in secrets v4) and proposes slide edits to the dashboard's Pitch Deck Edits queue. Never edits the deck. See `pitch-deck-updater-usage.md`. |
| `.claude/agents/investor-newsletter.md` | Biweekly Fri 9am. HubSpot delta + internal transcripts → investor update; on approval creates one unsent BCC Gmail draft (only Gmail-writing agent, never sends). See `investor-newsletter-usage.md`. |
| `01-personas/commercial-persona.md` | ICP source of truth for the commercial side (drives signal qualification AND title-list for contact discovery) |
| `01-personas/investor-persona.md` | Investor ICP (v0 stub) — Partner = economic buyer, Principal = champion, Associate = diligence gatekeeper. Matured by investor-analyzer. |
| `01-personas/academic-persona.md` | ICP source of truth for the academic side (v0 stub, will firm up after a few sweeps) |
| `.claude/agents/prospecter.md` | Sibling agent — full company-first prospect discovery pipeline. The signal-watchers complement, not replace, prospecter. |

---

## Intro-finder — daily warm-intro discovery

The `intro-finder` agent is the third stage of the chain. It runs **every Sun–Fri morning at 7am local** and produces a daily intros file naming who in your LinkedIn network can introduce you to each target in the buying-group file.

### Why it exists

`signal-watcher` finds firing companies. `buying-group-finder` finds individuals at those companies. `intro-finder` answers the next question — "who do I already know who can introduce me to those individuals?" — by looking up mutual LinkedIn connections.

### Daily rhythm

```
Sun  7am: queue today's batch (1/5 of active BG file). No delivery.
Mon  7am: deliver Sun's output  + queue today's batch  (signal-watcher + BG-finder also fire Monday)
Tue  7am: deliver Mon's output  + queue today's batch
Wed  7am: deliver Tue's output  + queue today's batch
Thu  7am: deliver Wed's output  + queue today's batch (5th of 5)
Fri  7am: deliver Thu's output. No queueing.
Sat:     idle.
```

Each cycle consumes ONE buying-group file. The cycle that processes Monday's BG file starts the following Sunday — intro-finder intentionally lags BG-finder by one cadence.

### How a queued batch actually fires

The morning agent does not call Apify itself. Instead it:

1. Picks today's batch of ~`total_targets / 5` targets from the cursor.
2. Computes a random fire time per target in the 8:00–20:00 local window, enforcing min 30s between any two fire times.
3. Registers a Windows Task Scheduler one-shot per target using `Register-ScheduledTask -Once -At [datetime]`. Each task runs `scripts/run-one-apify-call.ps1` once at the chosen time. The task auto-deletes 2 hours after firing (`-DeleteExpiredTaskAfter`).
4. Each worker invocation calls Apify, polls for completion, and writes its result JSON to `~/Desktop/nightingale-signals/{side}/intros/daily-results/{today}/{slug}.json`.

Next morning's delivery phase aggregates yesterday's per-target JSONs into a single human-readable `intros-{yesterday}.md` and fires a push notification.

### Pacing protects your LinkedIn account

LinkedIn's official API does not expose mutual connections. The only programmatic path is a logged-in-session scraper, which violates LinkedIn ToS. The mitigation is **low daily volume + random intra-day pacing + minimum 30s gaps** to keep daily-per-cookie activity well under LinkedIn's behavioral-detection threshold. Do not raise the `daily_quota` or shorten the 30s minimum without thinking carefully about account-restriction risk.

### Secrets setup (one-time per machine)

Run `scripts/setup-secrets.ps1` once after cloning. It prompts for four things:

- **Apify API token** — from `https://console.apify.com/account/integrations`. Hidden / masked input.
- **Apify Actor ID** — the identifier of a LinkedIn-mutual-connections Actor from the Apify store (format `{username}~{actor-name}`). Browse `https://apify.com/store?search=linkedin+mutual+connections` to pick one.
- **Your own LinkedIn profile URL** — used only at setup time to validate that the chosen Actor can be invoked with your cookie. Costs ~$0.01–0.05 in Apify credit. Example: `https://linkedin.com/in/your-slug`.
- **LinkedIn `li_at` cookie** — the session cookie from your logged-in LinkedIn browser. Hidden / masked input. The script prints inline instructions (Chrome DevTools → Application → Cookies → `https://www.linkedin.com` → `li_at` → copy Value).

All four land in `~/.nightingale/secrets.json` with restricted ACL (only the current user has access). The file lives **outside the repo**, so it cannot be accidentally committed.

The setup script validates all credentials in one round-trip: Apify token → `/v2/users/me`, then a single Actor run against your own profile URL using the cookie. 404 → "Actor not found"; auth-failure indicators in the result → "Cookie rejected, refresh". Bad credentials fail fast at setup, not on Monday morning.

### Cookie expiry

LinkedIn rotates session cookies periodically (usually every few months, sooner if it suspects scraping). When the first per-target call of a day detects auth failure, the worker writes two sentinel files:

- `~/.nightingale/.cookie-expired-active` — blocks all subsequent per-target calls (defense-in-depth).
- `~/Desktop/nightingale-signals/.cookie-expired-{date}` — read by the next morning's delivery phase.

The next morning's run writes a `COOKIE_EXPIRED-{date}.md` notice to both sides' intros output folders, fires a push notification, and skips queueing until you re-run `scripts/setup-secrets` to refresh and clear the sentinel.

### Cron entry

After running `scripts/install-schedule.ps1`, you should see three Nightingale entries:

```
Nightingale-Commercial-Sweep       Monday 7am
Nightingale-Academic-Sweep         Monday 7am
Nightingale-Intro-Finder-Morning   Sun–Fri 7am
```

The intro-finder entry alone is independent of secrets — even without `setup-secrets`, it runs and writes a `SECRETS_MISSING-{date}.md` notice each morning so you know it's alive. Sweeps + buying-group-finder continue unaffected.

### Output paths

```
~/Desktop/nightingale-signals/
├── commercial/
│   └── intros/
│       ├── state/cursor.json                       # which BG file is active, daily quota, queue
│       ├── state/found-mutuals.json                # 30-day re-query gate
│       ├── daily-results/{date}/{slug}.json        # one file per Apify call
│       └── output/intros-{date}.md                 # delivered each morning
└── academic/
    └── intros/   (same shape)
```

### ToS / account-safety guidance

Read this before tuning anything:

- The Apify path drives a LinkedIn session via your `li_at` cookie. LinkedIn ToS forbids this. Restriction (temporary 24–72h block) is the realistic worst case at low volume; permanent ban requires repeated offenses.
- Keep `daily_quota` low. The default `ceil(total_targets / 5)` spread across 5 days targets a low-double-digit daily call count even for large sweeps.
- Keep the 30s minimum gap. The cascade is designed to space out cookie activity even if random sampling clusters times.
- Keep the 8–8 window. Calls outside business hours look more obviously automated.
- If you start seeing CAPTCHA challenges when browsing LinkedIn manually, pause intro-finder for a week: `Unregister-ScheduledTask -TaskName 'Nightingale-Intro-Finder-Morning' -Confirm:$false`. Restart it after the heat dies down by re-running `scripts/install-schedule.ps1`.
- Never log the cookie value. The agent reads only the file existence; the worker reads the cookie and never echoes it.

### What intro-finder does NOT do (v1)

- No Apollo calls. WebSearch + Apify only.
- No emails. Mutuals are surfaced with names + LinkedIn URLs + current title/company. Email discovery for mutuals is out of scope.
- No outreach generation. The intros file is the deliverable; the "Hey Bob, would you intro me to Jane?" message is manual.
- No HubSpot push. Manual follow-up.
- No backfill if the laptop is asleep during a queued fire time. The OS one-shot is skipped. Future runs may re-process via the 30-day gate window if needed.

---

## Gmail Re-Surfacer — daily Mon-Fri 7am

The `gmail-resurfacer` agent is the fourth stage of the chain, parallel to intro-finder (not chained from it). Its job is to mine the warmest signal available — **people you've already talked to** — and surface 5 reconnect-worthy contacts each weekday morning.

### Why it exists

The signal-watcher → buying-group-finder → intro-finder chain finds NEW prospects from public sources. None of those agents looks at your own inbox. A 12-month Gmail history contains hundreds of past conversations with people whose company has since hit a trial-design signal, whose title matches an ICP role, or who asked questions Nightingale can answer better today than 12 months ago. The resurfacer reads that history, scores it against the personas, and presents 5 highest-value re-engagement leads per morning with an explicit "why this person, why now" justification.

Per directive, every re-surfaced contact is labeled `re-surfaced` (= weak signal tier) because the existing-relationship premise itself is intrinsically weaker than a fresh signal-watcher trigger — but a re-surfaced contact whose company **also** fired a fresh trigger is exactly the highest-value lead in the funnel.

### Two-phase cursor model

Rather than starting at "now" and watching new mail, the cursor **starts 365 days ago and walks forward**. The earliest runs surface the most-forgotten contacts (highest latent value); by the time the cursor catches up to today, the agent switches to incremental "new mail" mode.

- **Catch-up mode** — cursor is a date. Each daily run scans `[cursor, cursor + chunk_days]`, scores, picks top 5, advances cursor by `chunk_days`. Default `chunk_days = 12` clears the 365-day backlog in ~30 weekday runs (~6 calendar weeks).
- **Steady-state mode** — cursor becomes a Gmail historyId. Each run scans threads with new activity since the last run. If fewer than 5 pass the bar, the agent backfills from a long-tail cache of previously-scored-but-not-surfaced threads.

### Scoring rubric (0–100 composite)

| Component | Max | Source |
|---|---|---|
| **Persona role match** | 30 | LLM judges contact's title from signature / Gmail Contacts / WebSearch against persona buckets (commercial Economic Buyer / Tech Gatekeeper / Champion; academic PI / Buyer / Tech Gatekeeper) |
| **Company ICP match** | 20 | Sender domain → company → employee count 10-200 + bio/pharma/medical-device/CRO/academic-medical-center industry + US. Personal freemail → 0 + route to skip pile. |
| **Trial-stage signal** | 25 | Heuristic regex for trial-language tokens + ClinicalTrials.gov cross-ref. Phase 1 completed within last 90 days OR Phase 2 in design/recruiting within last 180 days → +25. Historical language only → +10. |
| **Conversation health** | 15 | LLM judges sentiment + recency. Healthy + cold > 90d → +15. Healthy + active < 30d → +0 (already in-flight). Terminal negative signal → entire thread scored to 0. |
| **Cross-agent boost** | 10 | +10 if company is in latest signal-watcher output. If contact also appears in any active buying-group file, recommended-action overrides to "awareness only, do NOT recommend new outreach." |

**Minimum surfacing threshold: 35.** Below 35, never surface — the bar stays high enough that 5 contacts/day stays signal-dense.

### Cooldown + snooze

- **60-day cooldown** — a contact surfaced today never re-appears for 60 days, regardless of score.
- **Manual snooze** — trigger phrase `snooze {email} for {N} days` adds the contact to `state/snoozed.json`. `unsnooze {email}` removes them.
- **Surface-count warning** — when `surface_count >= 3` for a contact, the terminal logs a soft warning suggesting snoozing or moving on. No automatic exclusion.

### HubSpot annotation (read-only)

For each surfaced contact, the agent queries HubSpot via `mcp__hubspot__hubspot-search-objects` and annotates:

- Not present → recommended action `cold re-engage`.
- Present, no deal → `warm re-engage; consider creating deal`.
- Present, deal stage = X, last activity < 30 days → `⚠ active deal — do not double-contact`.
- 30-89 days → `active but quiet — check with sales context`.
- ≥ 90 days → `stale deal — re-engage worthwhile`.

The agent never writes to HubSpot. Annotation is informational only.

### Privacy rule

**The output markdown NEVER quotes email body content verbatim.** The "Last contact" field is always a paraphrased ≤1-sentence summary. The Desktop markdown may be screenshotted or shared; protecting contacts' privacy and the operator's relationships is non-negotiable. Verbatim quoting indicates a prompt-failure and must be corrected.

### Output paths

```
~/Desktop/nightingale-signals/resurfacer/
├── state/
│   ├── cursor.json              # mode + date or historyId, chunk_days, last run
│   ├── surfaced-history.json    # 60-day cooldown + surface_count tracking
│   ├── snoozed.json             # user-snoozed contacts with expiry
│   └── scored-cache.json        # LRU-capped (5000 entries) for steady-state backfill
└── output/
    └── resurfacer-{date}.md     # delivered each weekday morning
```

### Cron entry

After running `scripts/install-schedule.ps1`, you should see four Nightingale entries:

```
Nightingale-Commercial-Sweep             Monday 7am
Nightingale-Academic-Sweep               Monday 7am
Nightingale-Intro-Finder-Morning         Sun–Fri 7am
Nightingale-Gmail-Resurfacer-Morning     Mon–Fri 7am
```

### Prerequisites

The resurfacer requires the **Gmail MCP connector** authorized in Claude Code (Settings → Connectors → Gmail). If unauthorized at run time, the agent writes a `GMAIL_NOT_AUTHORIZED-{date}.md` notice + push and exits cleanly. The other three stages of the chain are unaffected.

Optional but recommended connectors (graceful degradation if missing):
- **HubSpot MCP** — for state annotation. If missing, every surfaced contact shows `HubSpot: not present` and may surface duplicate-effort risk if you already have them in HubSpot.
- **Apollo MCP** — read-only enrichment for company ICP match when signature/Gmail-Contacts is insufficient.
- **ClinicalTrials.gov MCP** — for the trial-stage fresh-trigger cross-ref. If missing, that component falls back to historical-only (+10) for any thread with trial-language tokens.

### Trigger phrases

- `gmail resurfacer daily morning` — full daily run (what cron invokes; fires push).
- `RUN gmail resurfacer` / `re-surface my inbox` — manual run, no push.
- `snooze {email} for {N} days` — adds contact to snooze list.
- `unsnooze {email}` — removes contact from snooze list.
- `resurfacer dry run from {ISO date}` — test scoring without advancing the persistent cursor.
- `resurfacer reset cursor to {ISO date}` — explicit cursor rewind / fast-forward (confirms in terminal first).

### What gmail-resurfacer does NOT do (v1)

- No Gmail drafts created. No emails sent. The agent is fully read-only against Gmail.
- No HubSpot writes. Read-only annotation only.
- No Apollo writes. Read-only enrichment only when needed.
- No verbatim email body in the output md. Paraphrase only.
- No weekend runs. Mon-Fri only — matches a standard working week.
- No ML / embedding clustering. Heuristic + LLM-judgment scoring only.

---

## Daily Brief — daily Mon-Fri 6am

The `daily-brief` agent is the fifth stage of the chain. It runs Mon-Fri at **6am local — deliberately one hour before the 7am stack** (signal-watcher / intro-finder / gmail-resurfacer) so the brief lands first and is not buried under the 7am push notifications.

### Why it exists

The other four agents PRODUCE data — qualified companies, buying groups, intro paths, re-surfaced contacts. The daily-brief AGGREGATES that data into per-meeting action. For each external meeting on today + tomorrow's calendar, the brief assembles meeting essentials, attendee identity, persona match, recent thread context (paraphrased), cross-agent context (signal-watcher / buying-group / ClinicalTrials.gov / re-surfacer status for the attendee's company), Layer-A cached intro suggestions, Layer-B fresh persona-roster intros, recommended persona-aligned talking points, and HubSpot state annotation.

The agent does not produce new prospect data. It is read-and-synthesize.

### Operational rhythm

```
Mon-Fri 6am: enumerate today + tomorrow calendar → filter external → per-meeting prep → write md → push.
Sat/Sun:     no run.
```

### What counts as an "external meeting"

The brief filters out:
- Events with no attendees or only self (focus blocks, OOO markers).
- Events where every non-self attendee email ends in `@Nightingalesolution.com` (internal-only).
- Events whose title matches a recurring-internal pattern: `standup`, `sync`, `1:1`, `office hours`, `team meeting`, `all-hands`, `lunch`, `focus time`, `blocked`, `OOO`, `out of office`, `bday`, `birthday`.

Volume cap: **8 external meetings/day**. If the day has more, the first 8 by start time get full prep and the rest land in the "Skipped — volume cap" section so they're visible to the operator.

### Intro suggestions in two layers

**Layer A — cached (free, instant)**: reverse-scan intro-finder's `found-mutuals.json` per side. If the meeting attendee appears as a *mutual* against any prior target, emit "Ask {attendee} to intro you to **{target}** ({role} at {company}; strength: {strong/medium/weak})." Strict match preferred (`mutual.url == attendee.linkedin_url`); fuzzy fallback marked `⚠ fuzzy — verify before asking`.

**Layer B — fresh persona-roster (Apify or WebSearch, today's meetings only)**: for each external attendee with a resolved company, surface persona-matching colleagues at THAT company the attendee could introduce.

- **Preferred path** (when `apify_company_roster_actor_id` is set in secrets v4): invoke `scripts/run-one-apify-company-roster.ps1` synchronously (90s timeout) — Apify LinkedIn-company-employees Actor returns the roster, the worker filters client-side to persona-matching titles, agent surfaces top 5.
- **Fallback path** (when the Layer-B Actor is not configured OR Apify times out OR returns non-success): the agent issues WebSearch queries `site:linkedin.com/in "{title-role-token}" "{Company}"` per persona bucket and surfaces top 3 per bucket. Each row tagged `(source: WebSearch — Apify Layer-B not configured)`.

**Caps**: 8 Layer-B lookups/day across all meetings; 3 attendees per meeting maximum. Per-company results are cached for 30 days to avoid re-querying the same company across multiple meetings.

### Recommended talking points

For each meeting, the brief generates 3 bullets per matched persona bucket, sourced from the persona file's "Messaging Principles" and the matched role's "ROI & Justification Framework" sub-section. Each bullet references the source persona section by name so the operator can deep-read if needed. NOT a generated pitch — guidance only.

### Output paths

```
~/Desktop/nightingale-signals/daily-brief/
├── state/
│   ├── attendee-roster-cache.json    # per-company Layer-B results, 30-day TTL
│   ├── brief-history.json             # every brief delivered (date, meetings, attendees)
│   └── linkedin-url-cache.json        # email → LinkedIn URL resolution cache
└── output/
    └── daily-brief-{date}.md          # delivered each weekday 6am
```

### Cron entry

After running `scripts/install-schedule.ps1`, you should see five Nightingale entries:

```
Nightingale-Daily-Brief-Morning          Mon–Fri 6am
Nightingale-Commercial-Sweep             Monday 7am
Nightingale-Academic-Sweep               Monday 7am
Nightingale-Intro-Finder-Morning         Sun–Fri 7am
Nightingale-Gmail-Resurfacer-Morning     Mon–Fri 7am
```

### Prerequisites

The daily-brief requires the **Google Calendar MCP connector** authorized in Claude Code (Settings → Connectors → Google Calendar). If unauthorized at run time, the agent writes a `CALENDAR_NOT_AUTHORIZED-{date}.md` notice + push and exits cleanly. The other four agents are unaffected.

Optional but recommended connectors (graceful degradation):
- **Gmail MCP** — for attendee identity resolution (signature scrape) and recent thread context. Without it, the brief degrades to HubSpot + WebSearch identity resolution and shows "No prior email history" for every attendee.
- **HubSpot MCP** — for state annotation. Without it, every attendee shows `HubSpot: not present`.
- **Apollo MCP** — read-only enrichment when signature/HubSpot doesn't supply company industry / employee count.
- **ClinicalTrials.gov MCP** — for the cross-agent "trial-design window open" check on the attendee's company.
- **Apify Layer-B Actor** (optional secret in `~/.nightingale/secrets.json` schema v4 as `apify_company_roster_actor_id`): the daily-brief Layer-B persona-roster Apify path. Without it, Layer-B uses the WebSearch fallback.
- **Pitch-deck Drive pointer** (optional secret in `~/.nightingale/secrets.json` schema v4 as `pitch_deck_drive_file_id`, plus optional `pitch_deck_drive_url`): the Google Slides deck the `pitch-deck-updater` agent reads (read-only). Set it via `scripts/setup-secrets.ps1`. Without it, pitch-deck-updater writes a `DECK_POINTER_MISSING` notice and skips cleanly.

### Trigger phrases

- `daily brief morning` — full daily run (what cron invokes; fires push).
- `RUN daily brief` / `brief me on today` — manual run, no push.
- `brief me on {ISO date}` — force-run for a specific date.
- `daily brief dry run` — assemble brief but do NOT advance state or fire push.

### Privacy rule

Same paraphrase-only rule as the re-surfacer: **the brief markdown NEVER quotes email body content verbatim.** All thread-context summaries are paraphrased in ≤ 1 sentence per email. Verbatim quoting indicates a prompt-failure and must be corrected.

### What daily-brief does NOT do (v1)

- No calendar mutations. No event creation, no RSVP changes, no calendar writes.
- No Gmail mutations. No drafts, no replies.
- No HubSpot writes.
- No Apollo writes.
- No outreach generation. The brief informs the operator's manual outreach; it doesn't pre-write it.
- No weekend runs. Mon-Fri only.
- No support for non-Google calendars in v1 (Outlook / Apple / ICS feeds deferred).

---

## Feedback Analyzer — on-demand or weekly

The `feedback-analyzer` agent is the sixth stage of the chain. Unlike the other five it does NOT register a Task Scheduler entry — it runs on-demand via trigger phrase (operators can wire it to their own weekly cron if desired). Its job is to close the loop: take what's actually happening in calls and email replies and propose evidence-backed updates to the persona files (and any other diff-target files present in the checkout).

### Why it exists

The other five agents PRODUCE prospect activity (signal-watcher / buying-group-finder / intro-finder / gmail-resurfacer / daily-brief). None of them learns from the OUTCOME of that activity. A call where a prospect says "actually our reconciliation pain is 3 weeks, not 4-6" is high-value persona-correcting signal that no other agent captures. Same for an email reply that quotes back a value-prop and asks a sharper question, or one that says "wrong contact — talk to our CMO instead."

The feedback-analyzer reads two feedback sources:
1. **Granola call transcripts** from the team-shared Google Drive folder `/curanostics/nightingale/call transcripts`.
2. **Inbound Gmail replies** from the operator's own inbox (the last 7 days by default, in threads the operator participated in).

It extracts insights along the same dimensions for both, scores them with a weighted confidence model, and emits a propose-only refinement report.

### Weighted confidence model

Calls are deeper signal than emails. The thresholds use weighted occurrence sums, not raw counts:

| Source type | Weight per occurrence |
|---|---|
| Call | 1.0 |
| Email — value-prop quote-back (reply quotes a value-prop we sent) | 0.5 |
| Email — explicit disqualification ("not interested" / "wrong contact") | 0.5 |
| Email — role-reality conflict (reply signature contradicts the role we cold-emailed) | 0.5 |
| Email — generic | 0.3 |

Weights per email do NOT stack — apply the first matching category in priority order (VP quote-back > disqualification > role conflict > generic). Maximum email weight = 0.5.

Confidence tiers from weighted sum:
- **High** ≥ 3.0 (e.g. 3 calls; or 10 generic emails; or 1 call + 7 emails)
- **Medium** ≥ 2.0
- **Low** ≥ 1.0 — flagged in report, no before/after diff (single-source signal, judge manually)
- **Sub-threshold** < 1.0 — logged in `_patterns.md` only, not surfaced as a finding

A single email reply (0.3) is sub-threshold and never alone produces a persona-edit proposal. This is the intentional guard against email-driven persona churn.

### Diff targets (adaptive per checkout)

Always emitted (both repos have these files):
- `01-personas/commercial-persona.md`
- `01-personas/academic-persona.md`

Conditionally emitted (only if present in the local checkout — the GTM repo does not ship these, so they're typically absent here):
- `.claude/agents/prospecter.md`
- `02-sales/02b-campaigns/outreach-tier1-day1.md`
- `02-sales/02a-prospect lists/trial-qualification.md`

Findings that would target a missing file are surfaced under "Findings without an applicable diff target" so they're visible for manual review even if no automated diff is produced.

### Output paths

```
~/Desktop/nightingale-signals/feedback-insights/
├── state/
│   ├── _processed.md       # log of analyzed sources, with source column (call|email)
│   └── _patterns.md        # cumulative weighted pattern log
└── output/
    └── refinement-{date}.md  # propose-only report with literal before/after diffs
```

**Critically, outputs go to the operator's Desktop, NOT into the repo tree.** The refinement report quotes prospects verbatim — that's its core value — but keeping it outside the repo means it cannot be accidentally `git add`ed and pushed to a shared remote. Each operator's reports stay local to their Desktop.

### Prerequisites

At least ONE of these MCP connectors authorized in Claude Code (the agent gracefully degrades if one is missing; if BOTH are missing it writes a single `MCPS_NOT_AUTHORIZED-{date}.md` notice and exits):
- **Google Drive MCP** — for reading the team-shared call transcripts folder. Without it, Step 2a (call discovery) is skipped.
- **Gmail MCP** — for reading inbound replies. Without it, Step 2b (email discovery) is skipped.

To analyze the team-shared call transcripts, the operator's Google account also needs share access to `/curanostics/nightingale/call transcripts`.

### Trigger phrases

**Combined-feedback (primary):**
- `ANALYZE feedback` — full run against unprocessed transcripts + emails.
- `ANALYZE email replies` — emails-only run.
- `REFINE persona from feedback` — alias for full run.
- `RUN feedback-analyzer` — for any operator-scheduled weekly cron.
- `WEEKLY feedback insights` — alias for full run.

**Call-only aliases (preserved for compatibility with the older call-analyzer cron entries):**
- `ANALYZE calls`, `ANALYZE last week's calls`, `ANALYZE this week's calls`, `ANALYZE the {company} call`
- `REFINE persona from calls`, `RUN call-analyzer`, `WEEKLY call insights`

### Privacy rule (different from daily-brief / resurfacer)

Daily-brief and gmail-resurfacer paraphrase email body content because their outputs are operational briefs and could be screenshotted casually. The feedback-analyzer's report DOES contain verbatim prospect quotes — that's its evidentiary value (no quote, no diff). Treat the report on your Desktop as sensitive: do not share externally, do not commit, do not paste quotes into Slack/HubSpot/etc. without redaction.

### What feedback-analyzer does NOT do

- No source-file writes. Strictly propose-only — the operator manually reviews and applies approved diffs.
- No Gmail mutations (no drafts, no labels, no replies).
- No Google Drive mutations.
- No HubSpot / Apollo / Calendar / Instantly writes.
- No outreach generation.
- No auto-apply of diffs (operator must explicitly request `apply diffs N,N,N from refinement-{date}` and even then a separate apply pass is required).
- No Outlook / non-Google mail support in v1.

---

## HubSpot Manager — nightly Mon–Sun 11pm

The `hubspot-manager` agent is the seventh stage of the chain and the **only agent that writes to HubSpot**. Every night at 11pm local it reads the last 24 hours of new Granola transcripts + inbound Gmail replies and turns them into HubSpot writes under a strict two-tier guardrail. The next morning's daily-brief surfaces anything that required approval at the top of the brief.

### Why it exists

The other six agents PRODUCE briefs and reports. None of them updates the CRM. Calls happen, transcripts get written, emails land, and HubSpot drifts behind reality — by the time the operator sits down to update HubSpot manually, half the context is lost. The hubspot-manager closes that loop, but cautiously: it auto-applies activity logging + populate-empty metadata refreshes, and queues every pipeline-state change for explicit approval.

### Two-tier guardrail

**Auto-apply (capped at 20 writes per night).** These are either obviously true or trivially reversible:

1. `log_call` — log a Meeting or Call engagement when a fresh Granola transcript matches an existing HubSpot contact.
2. `log_email` — log an incoming Email engagement when a qualifying reply matches an existing HubSpot contact.
3. `add_summary_note` — for every `log_call` / `log_email` that auto-applied, also create a ≤3-sentence paraphrased summary Note engagement (paraphrased, never verbatim — Notes are visible across HubSpot UI/exports). Strategic notes never auto-apply.
4. `update_contact_title` — populate empty `jobtitle` OR refresh a stale value (>30 days old) from a fresh signature scrape.
5. `update_contact_linkedin` — populate empty `linkedin_url` from a fresh signature scrape. **Populate-empty only; never overwrite.**
6. `update_contact_phone` — populate empty `phone` from a fresh signature scrape. **Populate-empty only; never overwrite.**
7. `update_contact_lastcontacted` — bump the `notes_last_contacted` timestamp after a logged call/email.

**Populate-empty / refresh-stale guard:** any proposed write that would OVERWRITE a currently-non-empty property modified within the last 30 days is automatically downgraded to queue with `queue_reason: "would overwrite recent existing value"`.

**Queue for approval (no auto-apply ever, no cap):**

- **Object creation:** `create_contact`, `create_company`.
- **Deal state:** `move_deal_stage`, `update_deal_amount`, `update_deal_closedate`, `change_owner`, `change_lifecycle`, `disqualify`.
- **Contact demographics:** `update_contact_industry`, `update_contact_seniority`, `update_contact_persona_or_role`, `update_contact_location` (city/state/country) — affect segmentation and territory; queue even when current value is empty.
- **Company firmographics:** `update_company_industry`, `update_company_employeecount`, `update_company_annualrevenue`, `update_company_location`, `update_company_domain` — affect ICP fit and segmentation.
- **Non-summary notes:** `add_strategic_note` — risk assessments, expansion plays, account-status calls.
- **Active-deal protection:** ANY candidate (auto-eligible or otherwise) against a contact whose associated deal has activity in the last 7 days and is non-terminal — automatically downgrades to queue with rationale showing the active deal info.
- **Overflow:** any auto-eligible candidate generated AFTER the auto-cap of 20 is reached this run.

### Approval flow (next-morning)

1. Nightly 11pm: hubspot-manager writes `~/Desktop/nightingale-signals/hubspot-manager/pending/{run_date}.json` with every queued item (pending_id, action, target, payload, rationale, source quotes, queue_reason).
2. Next morning 6am: daily-brief reads the most-recent un-archived pending file(s) and surfaces every undecided item at the top of the brief as a "Pending HubSpot updates" section (capped at 15 items with an overflow footer).
3. Operator approves with `apply hubspot updates {N,N,N} from {date}` or rejects with `reject hubspot updates {N,N,N} from {date}`. Convenience: `apply hubspot updates all from {date}` and `reject hubspot updates all from {date}`.
4. Apply mode invokes the HubSpot MCP tool with the queued payload. Reject mode skips the call. Both write to `state/approval-history.jsonl` + `state/transactions.jsonl`. Once every item in a pending file is decided, the file moves to `pending/archive/{date}.json` and stops appearing in daily-brief.
5. Cross-day view: `list pending hubspot updates` returns every undecided item across every non-archived pending file. Useful when a few days went by without approval.

### Field coverage

| Object | Auto-eligible properties | Queue-only properties |
|---|---|---|
| **Contacts** | jobtitle (populate-empty / refresh-stale), linkedin_url (populate-empty), phone (populate-empty), notes_last_contacted | industry, seniority, persona/role, city, state, country, lifecycle stage, lead status (disqualify) |
| **Companies** | (none auto-eligible; firmographics affect segmentation) | industry, employee count, annual revenue, location, domain |
| **Deals** | (none auto-eligible; deal state always requires approval) | stage, amount, close date, owner |
| **Engagements** | calls, meetings, emails (incoming), summary notes (≤3 sentences, paraphrased) | strategic notes |

Anything outside this set falls through to queue with `queue_reason: "unrecognized field — review manually"`.

### Idempotency

Every candidate has a deterministic `dedup_key` (e.g., `log_call:{transcript_file_id}`). Every write attempt (auto_applied, approved, rejected, failed) appends one line to `state/transactions.jsonl`. Re-runs of the same agent or partial-failure retries never produce duplicate writes — the dedup filter at Step 3 short-circuits any candidate whose key is already recorded.

### State + output paths

```
~/Desktop/nightingale-signals/hubspot-manager/
├── state/
│   ├── processed-sources.json     # transcript file_ids + email content-hashes already scanned
│   ├── transactions.jsonl         # append-only — every HubSpot write attempt (audit + dedup)
│   └── approval-history.jsonl     # append-only — every operator decision via apply/reject
├── pending/
│   ├── {run_date}.json            # nightly queue file; consumed by daily-brief + apply/reject modes
│   └── archive/{run_date}.json    # fully-decided pending files moved here
└── output/
    └── run-{run_date}.md          # nightly run summary
```

All outputs live on the Desktop — never inside the repo tree. Each operator's transaction log and pending queue stay local to their machine.

### HubSpot MCP authorization required

The hubspot-manager agent will NOT write to HubSpot until the HubSpot MCP connector is authorized in Claude Code. Until then, every nightly run writes a `HUBSPOT_NOT_AUTHORIZED-{date}.md` notice on the operator's Desktop and exits cleanly. The other six agents are unaffected.

#### One-time setup (Claude Code)

1. Open Claude Code.
2. Settings → Connectors → search "HubSpot".
3. Click "Authorize" / "Connect". A browser tab opens to HubSpot's OAuth flow.
4. Sign in to your HubSpot account.
5. Approve the requested scopes:
   - `crm.objects.contacts` (read + write)
   - `crm.objects.companies` (read + write)
   - `crm.objects.deals` (read + write)
   - `crm.objects.notes` (read + write)
   - `crm.schemas.contacts` (read), `crm.schemas.companies` (read), `crm.schemas.deals` (read)
   - `crm.objects.owners` (read)
   - `sales-email-read` (for engagement context)
6. Return to Claude Code — the connector should show "Connected".

Verify: run `claude -p "list pending hubspot updates"` — should return without error (probably "no pending items" on a fresh install).

If you authorized into the WRONG HubSpot account (e.g. personal vs team), disconnect from the same Settings → Connectors screen and re-authorize.

The agent is fully read-then-cautious-write: it reads contacts/companies/deals/notes and only writes the categories listed in the "Auto-eligible properties" table above + the categories the operator explicitly approves via `apply hubspot updates {N,N,N} from {date}`.

#### Per-operator note

Each Nightingale team member authorizes their own HubSpot account independently. The agent picks the authenticated operator as the engagement owner — never assigns work to another team member without explicit approval.

### Trigger phrases

- `nightly hubspot manage` — what cron invokes (fires push).
- `RUN hubspot-manager` — manual nightly run (no push).
- `apply hubspot updates {N,N,N} from {date}` — apply specified pending IDs.
- `apply hubspot updates all from {date}` — apply every undecided item in `pending/{date}.json`.
- `reject hubspot updates {N,N,N} from {date}` — reject specified pending IDs.
- `reject hubspot updates all from {date}` — reject every undecided item in `pending/{date}.json`.
- `list pending hubspot updates` — cross-day view of all undecided items.

### What hubspot-manager does NOT do

- **Never deletes anything.** No path through this agent exposes deletion.
- **Never merges contacts or companies.**
- **Never assigns work to anyone other than the authenticated operator.**
- **Never overwrites a recently-set non-empty property** (last modified ≤ 30 days) without explicit approval.
- **Never writes verbatim email body content into a Note.** All notes are paraphrased (≤ 3 sentences).
- **Never reads / touches the LinkedIn `li_at` cookie.**
- **Never bypasses the 20-auto-applies-per-night cap.**
- **Never writes outside `~/Desktop/nightingale-signals/hubspot-manager/`.**
