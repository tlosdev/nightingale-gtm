# nightingale-gtm

Seven agents for Nightingale's GTM motion — five signal-first prospect-discovery agents, one feedback-loop agent that closes the loop with persona-refinement proposals from calls + emails, and one nightly HubSpot writer that turns the day's transcripts + replies into CRM updates under a strict two-tier guardrail. They run on Windows + Claude Code, hit public clinical-trial / regulatory / funding / academic-research feeds plus your LinkedIn network, your Gmail history, your Google Calendar, your HubSpot account, and a team-shared Google Drive folder of call transcripts, and drop daily/weekly markdown files on your Desktop.

- **`signal-watcher-commercial`** — biotech / pharma / med-device sponsors, 10–200 employees, US. Sources: ClinicalTrials.gov, SEC EDGAR 8-Ks, openFDA, press wires, LinkedIn job postings, Apollo funding.
- **`signal-watcher-academic`** — US academic medical centers and research hospitals running human-subjects studies. Sources: ClinicalTrials.gov (academic Lead Sponsor or Facility), NIH RePORTER, SBIR/STTR, university press / news.
- **`buying-group-finder-{commercial,academic}`** — auto-chained after each sweep. Find Economic Buyer / Tech Gatekeeper / Champion (commercial) or PI / Buyer / Tech Gatekeeper (academic) at every surfaced company / institution via WebSearch.
- **`intro-finder`** — runs daily Sun–Fri 7am. Spreads the active buying-group file's targets across the week (1/5 per day), invokes Apify per target across a randomized 8am–8pm window, and delivers a per-target + per-mutual warm-intro file each morning.
- **`gmail-resurfacer`** — runs daily Mon–Fri 7am (parallel to intro-finder, NOT chained). Walks 12 months of Gmail history forward from a cursor, scores every thread against both personas, and surfaces the top 5 contacts to re-engage today with HubSpot state annotation. Fully read-only against Gmail / HubSpot / Apollo. Never quotes email body verbatim.
- **`daily-brief`** — runs daily Mon–Fri 6am (one hour before the 7am stack so it lands first). Pulls today + tomorrow's Google Calendar, filters to external meetings, and assembles per-meeting prep including persona match, recent thread context, cross-agent context, Layer-A cached intro suggestions (reverse-lookup against intro-finder's `found-mutuals.json`), Layer-B fresh persona-roster intros (Apify with WebSearch fallback), recommended talking points, and HubSpot state. Fully read-only across all sources.
- **`feedback-analyzer`** — runs on-demand (no Task Scheduler entry; trigger via `RUN feedback-analyzer` or wire up your own weekly cron). Reads call transcripts from the team-shared Google Drive folder `/curanostics/nightingale/call transcripts` AND your inbound Gmail replies (last 7 days), scores them with a weighted confidence model (calls 1.0 / generic email 0.3 / value-prop-quoting or explicit-disqualification email 0.5), and emits a propose-only refinement report with literal before/after diffs against the persona files. Output lands on your Desktop at `~/Desktop/nightingale-signals/feedback-insights/` — never in the repo tree (the report contains verbatim prospect quotes and would otherwise risk being committed to a shared remote).
- **`hubspot-manager`** — runs nightly Mon-Sun 11pm. The only agent that WRITES to HubSpot. Reads the last 24h of new Granola transcripts + inbound Gmail replies and turns them into HubSpot writes under a strict two-tier guardrail. Auto-applies up to 20 low-risk items per night (log call/email/note engagements; populate-empty contact metadata like title, LinkedIn URL, phone, last-contacted). Queues everything else (object creation, deal stage/amount/close-date/owner/lifecycle changes, demographics/firmographics, strategic notes, anything that would overwrite a recently-set value, anything touching an active deal with activity in the last 7 days). Queued items appear at the top of the next morning's daily-brief; you approve with `apply hubspot updates {N,N,N} from {date}` (or `reject ...`). Never deletes. Never merges. Idempotent re-runs via dedup keys + transaction log. Requires HubSpot MCP authorization (see prerequisites).

This repo is **Windows-only** as of 2026-05. macOS and Linux are not supported.

---

## First-run punch list (in order)

Do these in order. Each one takes 2–5 minutes; the whole sequence is ~30 minutes.

1. **Install Windows prerequisites** — Windows 10/11 with PowerShell 5.1+, Git for Windows, Claude Code with `claude` on PATH.
2. **Set PowerShell ExecutionPolicy** (one-time):
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. **Clone the repo** (use a path with no spaces):
   ```powershell
   git clone https://github.com/tlosdev/nightingale-gtm.git
   cd nightingale-gtm
   ```
4. **Request Google Drive share access** to the team-shared call transcripts folder `/curanostics/nightingale/call transcripts` from whoever owns it on the Nightingale team. Without share access the `feedback-analyzer` and `hubspot-manager` Drive-sourced features are dead in the water — they'll still run but find zero transcripts.
5. **Authorize MCP connectors in Claude Code** — see [MCP connector authorization](#mcp-connector-authorization) below. Minimum recommended set: ClinicalTrials.gov, Apollo, Gmail, Google Calendar, Google Drive, HubSpot.
6. **Register the scheduled tasks** (one-time per machine):
   ```powershell
   .\scripts\install-schedule.ps1
   ```
   This registers six Windows Task Scheduler entries (see [What runs when](#what-runs-when) below). Verify with:
   ```powershell
   Get-ScheduledTask -TaskName 'Nightingale-*'
   ```
7. **(Optional) Run setup-secrets** for the intro-finder + daily-brief Layer-B features:
   ```powershell
   .\scripts\setup-secrets.ps1
   ```
   This captures Apify API token + Apify Actor IDs + a LinkedIn `li_at` cookie and writes them with a restricted ACL to `%USERPROFILE%\.nightingale\secrets.json`. Skip if you only want the signal-watcher + buying-group-finder + gmail-resurfacer + daily-brief (without Layer-B) + hubspot-manager + feedback-analyzer stages.
8. **Smoke test each agent** — see [Smoke tests](#smoke-tests) below.

If any step fails, the relevant agent will write a `*_NOT_AUTHORIZED-{date}.md` or `SECRETS_MISSING-{date}.md` or `MCPS_NOT_AUTHORIZED-{date}.md` notice on your Desktop the next time it runs. Each notice contains the exact recovery steps inline.

---

## Launch the UI (optional)

Don't want to open Desktop md files one at a time? There's an optional local web control panel — single-pane view of every agent output, inline Apply/Reject buttons for the HubSpot pending queue, on-demand "Run now" buttons for each agent.

```powershell
# One-time: install Node.js 18 LTS or newer from https://nodejs.org/
.\scripts\start-ui.ps1
```

That script handles the rest (first-time `npm install` ~30-60s, then build, then start). Opens `http://localhost:8765` in your default browser. Ctrl+C to stop.

The UI is **opt-in** — the chain works identically whether or not it's running. It binds to loopback only (no LAN exposure), has a strict allowlist of trigger phrases it can invoke, and never returns secret values from `secrets.json`. See `ui/README.md` for architecture + security details.

---

## Quick start (compressed — for users who've read the punch list)

```powershell
# 1. Clone
git clone https://github.com/tlosdev/nightingale-gtm.git
cd nightingale-gtm

# 2. Set execution policy + register schedules
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\scripts\install-schedule.ps1

# 3. (Optional) Configure Apify + LinkedIn for intro-finder + daily-brief Layer-B
.\scripts\setup-secrets.ps1

# 4. Smoke test the chain
claude -p "weekly commercial sweep"
claude -p "weekly academic sweep"
claude -p "daily brief dry run"
claude -p "list pending hubspot updates"
```

That's it. Step 2 registers **six** Windows Task Scheduler entries. Step 3 is opt-in. MCP connector authorization (HubSpot, Gmail, Calendar, Drive, Apollo, ClinicalTrials.gov) happens inside Claude Code's Settings → Connectors UI — see below.

---

## What runs when

| Task | Cadence | What it does |
|---|---|---|
| `Nightingale-Daily-Brief-Morning`        | Mon–Fri 6am local        | Daily brief: today + tomorrow calendar prep with per-meeting persona match, cross-agent context, intro suggestions, and the hubspot-manager pending-approval queue at the top |
| `Nightingale-Commercial-Sweep`           | Monday 7am local         | Commercial sweep + buying-group discovery |
| `Nightingale-Academic-Sweep`             | Monday 7am local         | Academic sweep + buying-group discovery |
| `Nightingale-Intro-Finder-Morning`       | Sun–Fri 7am local        | Intro-finder: delivery (Mon–Fri) + queue (Sun–Thu) |
| `Nightingale-Gmail-Resurfacer-Morning`   | Mon–Fri 7am local        | Gmail re-surfacer: walks 12-month inbox history, surfaces top 5 contacts to re-engage today |
| `Nightingale-HubSpot-Manager-Nightly`    | Mon–Sun 11pm local       | Reads last 24h of Granola transcripts + Gmail replies, auto-applies ≤20 low-risk HubSpot writes, queues everything else for next-morning approval |
| `Nightingale-Investor-Analyzer-Weekly`   | Monday 8am local         | Investor-persona refinement from investor call transcripts + investor email replies (propose-only diffs to `01-personas/investor-persona.md`). Auto-chains pitch-deck-updater. |
| `Nightingale-Investor-Newsletter-Biweekly` | Every other Fri 9am local | Summarizes HubSpot changes since the last newsletter + internal-team transcripts into an investor update; on approval creates one unsent BCC Gmail draft (never sends). |
| `feedback-analyzer` *(no scheduled task)* | Manual / on-demand       | Reads last 7 days of Granola transcripts + Gmail replies, emits propose-only persona refinement diffs. Trigger via `RUN feedback-analyzer` or wire up your own weekly cron entry. |
| `pitch-deck-updater` *(no scheduled task)* | Chained off investor-analyzer | Reads the Google Slides deck read-only (pointer = `pitch_deck_drive_file_id`), proposes slide edits to the dashboard's **Pitch Deck Edits** queue. Never edits the deck. |

The intro-finder's queue phase additionally registers per-target Windows Task Scheduler one-shots that fire at randomized times between 8am and 8pm on the same day, with a minimum 30-second gap between any two fires. These one-shots auto-delete 2 hours after they run.

Outputs land in:

```
C:\Users\{you}\Desktop\nightingale-signals\
├── commercial\
│   ├── output\commercial-signals-YYYY-MM-DD.md          # weekly sweep
│   ├── buying-groups\output\buying-group-YYYY-MM-DD.md  # weekly buying group
│   └── intros\output\intros-YYYY-MM-DD.md               # daily intros (when set up)
├── academic\   (same shape)
├── resurfacer\
│   ├── state\                                            # cursor + cooldown + snooze + score cache
│   └── output\resurfacer-YYYY-MM-DD.md                   # daily re-surfacer (Mon–Fri, when Gmail MCP authorized)
├── daily-brief\
│   ├── state\                                            # attendee-roster cache + brief history + LinkedIn-URL cache
│   └── output\daily-brief-YYYY-MM-DD.md                  # daily brief (Mon–Fri, when Google Calendar MCP authorized)
├── feedback-insights\
│   ├── state\                                            # _processed.md + _patterns.md (weighted-source schema)
│   └── output\refinement-YYYY-MM-DD.md                   # propose-only persona-refinement diffs (on-demand)
└── hubspot-manager\
    ├── state\                                            # processed-sources + transactions.jsonl + approval-history.jsonl
    ├── pending\YYYY-MM-DD.json                           # nightly queue file; consumed by daily-brief + apply/reject modes
    │   └── archive\YYYY-MM-DD.json                       # fully-decided pending files moved here
    └── output\run-YYYY-MM-DD.md                          # nightly run summary
```

The `nightingale-signals\` folder is created automatically on the first run.

---

## Four agents are opt-in (need external authorization)

- `intro-finder` needs Apify + a LinkedIn `li_at` cookie (set up via `scripts/setup-secrets.ps1`).
- `gmail-resurfacer` needs the Gmail MCP connector authorized in Claude Code (Settings → Connectors → Gmail). Optionally also authorize the HubSpot + Apollo + ClinicalTrials.gov MCP connectors for richer scoring and annotation.
- `daily-brief` needs the Google Calendar MCP connector authorized in Claude Code (Settings → Connectors → Google Calendar). Optionally: Gmail MCP for attendee identity resolution + recent thread context, HubSpot MCP for state annotation, Apollo MCP for company enrichment, ClinicalTrials.gov MCP for trial-design-window cross-ref, and a second optional Apify Actor (`apify_company_roster_actor_id`, set via `scripts/setup-secrets.ps1` schema v4) for richer Layer-B persona-roster intros. Without the Layer-B Actor, daily-brief falls back to WebSearch automatically.
- `hubspot-manager` REQUIRES the HubSpot MCP connector authorized in Claude Code (Settings → Connectors → HubSpot). See [HubSpot MCP authorization](#hubspot-mcp-authorization) below for the OAuth walkthrough. Without it, every nightly run writes a `HUBSPOT_NOT_AUTHORIZED-{date}.md` notice on your Desktop with step-by-step setup instructions and exits cleanly.
- **Investor loop** (`investor-analyzer` → `pitch-deck-updater` → `investor-newsletter`): reads the same Google Drive transcripts folder + Gmail (read-only) and, for the deck, the optional `pitch_deck_drive_file_id` Google Slides pointer (set via `scripts/setup-secrets.ps1` schema v4). `pitch-deck-updater` proposes slide edits and `investor-newsletter` drafts the biweekly update into the dashboard's **Pitch Deck Edits** and **Investor Newsletter** approval queues — both propose-only (the deck is never edited; the newsletter is only ever an unsent BCC Gmail draft). Without a deck pointer, pitch-deck-updater writes a `DECK_POINTER_MISSING-{date}.md` notice and skips. Per-agent setup: `06-agent-documentation/investor-analyzer-usage.md`, `pitch-deck-updater-usage.md`, `investor-newsletter-usage.md`.

Without those:

- `signal-watcher-{commercial,academic}` ✓ runs every Monday
- `buying-group-finder-{commercial,academic}` ✓ runs every Monday (auto-chained from sweep)
- `intro-finder` ⚠ runs but writes `SECRETS_MISSING-{date}.md` notices instead of intros
- `gmail-resurfacer` ⚠ runs but writes `GMAIL_NOT_AUTHORIZED-{date}.md` notices instead of contact lists
- `daily-brief` ⚠ runs but writes `CALENDAR_NOT_AUTHORIZED-{date}.md` notices instead of meeting prep
- `hubspot-manager` ⚠ runs but writes `HUBSPOT_NOT_AUTHORIZED-{date}.md` notices instead of HubSpot writes
- `feedback-analyzer` ⚠ writes a `MCPS_NOT_AUTHORIZED-{date}.md` notice if both Drive AND Gmail are unauthorized; otherwise gracefully degrades (skip the missing source)

---

## MCP connector authorization

Every agent that talks to a third-party service does so through a **Claude Code MCP connector** that you authorize once inside Claude Code (Settings → Connectors). The repo cannot do this for you — it's a per-operator, per-machine OAuth.

### Generic walkthrough (applies to all MCP connectors below)

1. Open Claude Code.
2. **Settings** → **Connectors** → search for the connector by name.
3. Click **Authorize** / **Connect**. A browser tab opens to the third party's OAuth consent screen.
4. Sign in to your account for that service. Approve the requested scopes.
5. Return to Claude Code. The connector should show "Connected." Verify with one of the smoke tests below.

If you authorize into the wrong account (e.g. personal vs work), disconnect from the same Settings screen and re-authorize.

### Connectors used by this repo

| Connector | Used by | Required? | Why |
|---|---|---|---|
| **ClinicalTrials.gov** | signal-watcher-{commercial,academic}, gmail-resurfacer, daily-brief, feedback-analyzer | required for sweeps | Trial discovery + cross-agent "trial-design window open" check |
| **Apollo.io** | signal-watcher-commercial, gmail-resurfacer, daily-brief, feedback-analyzer | required for commercial sweep | Funding signals + company enrichment (read-only for resurfacer/daily-brief/feedback) |
| **Gmail** | gmail-resurfacer, daily-brief, feedback-analyzer, hubspot-manager | required for those 4 agents | Inbound replies, signature scrape, identity resolution |
| **Google Calendar** | daily-brief | required for daily-brief | Today + tomorrow meeting enumeration |
| **Google Drive** | feedback-analyzer, hubspot-manager | required for Granola transcript ingestion | Reads `/curanostics/nightingale/call transcripts` (team-shared) |
| **HubSpot** | hubspot-manager (read+write), daily-brief, gmail-resurfacer (read-only annotation) | required for hubspot-manager nightly | CRM writes + state annotation |

**WebFetch + WebSearch** are built into Claude Code and need no separate authorization.

### Special case: Team Drive share access

The call transcripts source folder is **`/curanostics/nightingale/call transcripts`** in the Nightingale team's Google Workspace. Authorizing the Google Drive MCP connector is necessary but not sufficient — your Google account also needs **share access** to that specific folder.

If you're a new Nightingale team member, ping whoever owns the folder and ask to be added with at least Viewer permission. Without share access, `feedback-analyzer` and `hubspot-manager` will both still run but will find zero transcripts and operate against Gmail-only signals. Neither agent will surface this as an error (it looks like "quiet day, no new transcripts"), so the symptom is silent — verify share access explicitly before assuming the agents are working.

### Special case: HubSpot OAuth scopes

The HubSpot MCP needs specific scopes for hubspot-manager to function. See [HubSpot MCP authorization](#hubspot-mcp-authorization) below.

---

## HubSpot MCP authorization

The hubspot-manager agent will NOT write to HubSpot until the HubSpot MCP connector is authorized in Claude Code. Each Nightingale team member authorizes their own HubSpot account independently — the agent picks the authenticated operator as the engagement owner and never assigns work to another team member without explicit approval.

### One-time setup (Claude Code)

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

The agent is fully read-then-cautious-write — see `06-agent-documentation/signal-watcher-setup.md` "HubSpot Manager" section for the full auto-eligible / queue-only field tables, the two-tier guardrail rationale, and the approval workflow.

---

## Apify + LinkedIn setup (intro-finder + optional daily-brief Layer-B)

To enable warm-intro discovery via intro-finder, run `scripts/setup-secrets.ps1`. It prompts for four required values + one optional:

1. **Apify API token** — from `https://console.apify.com/account/integrations`.
2. **Apify Actor ID for mutual connections** — pick a LinkedIn-mutual-connections Actor from `https://apify.com/store?search=linkedin+mutual+connections` and paste its identifier (format `{username}~{actor-name}`). A tested-working default to copy: `apimaestro~linkedin-mutual-connections` — but verify it's still maintained and not banned by LinkedIn before relying on it.
3. **Your own LinkedIn profile URL** — used once at setup to validate that the chosen Actor can be invoked with your cookie. Costs ~$0.01–0.05 in Apify credit. Example: `https://linkedin.com/in/your-slug`. Must match `linkedin.com/in/{slug}` exactly.
4. **LinkedIn `li_at` cookie** — the session cookie from your logged-in browser. Chrome DevTools → Application → Cookies → `https://www.linkedin.com` → `li_at` → copy Value.
5. **(Optional) Apify Actor ID for company-employees scraping** — powers the daily-brief Layer-B persona-roster lookup. Browse `https://apify.com/store?search=linkedin+company+employees` and paste the identifier. Leave blank to fall back to WebSearch (cheaper, lower coverage).

All four required values are validated against Apify in one round-trip. Bad credentials fail fast at setup, not on Monday morning. Re-run `setup-secrets.ps1` anytime to rotate any single secret (existing values are preserved unless you say overwrite).

**Why all four?** The official LinkedIn API doesn't expose mutual connections. The only programmatic path is an Apify Actor that drives a logged-in browser session via your cookie. This violates LinkedIn ToS — account-restriction risk is low at the pace this agent enforces (max ~10–20 calls/day with random spacing) but it is not zero. See `06-agent-documentation/signal-watcher-setup.md` for the full ToS / safety guidance.

Credentials live in `%USERPROFILE%\.nightingale\secrets.json` with a restricted ACL (current user only). The file lives outside the repo tree and is also blocked by `.gitignore` defense-in-depth.

---

## Smoke tests

After completing the punch list above, run these one at a time to verify each agent is wired correctly. Each one is safe to run manually and idempotent.

```powershell
# Signal-watchers — write a qualified-list md to ~/Desktop/nightingale-signals/{side}/output/
claude -p "weekly commercial sweep"
claude -p "weekly academic sweep"

# Daily brief — dry-run mode does NOT advance state or fire push
claude -p "daily brief dry run"

# Gmail re-surfacer
claude -p "RUN gmail resurfacer"

# Feedback analyzer (on-demand; requires Drive + Gmail MCPs)
claude -p "ANALYZE feedback"

# HubSpot manager (the cross-day pending diagnostic — safe; no writes)
claude -p "list pending hubspot updates"

# Intro-finder (manual trigger using the most recent commercial BG file)
claude -p "find intros from latest commercial buying group"
```

Each command writes its output to `~/Desktop/nightingale-signals/{...}/output/{...}-{today}.md`. Open the file to confirm content. If you see a `*_NOT_AUTHORIZED-{date}.md` or `SECRETS_MISSING-{date}.md` notice instead, the notice file tells you what's missing.

---

## Expected first-week behavior

When you first complete the punch list and the scheduled tasks start firing automatically, expect:

- **First Monday 7am:** signal-watcher commercial + academic both fire. You'll see qualified-list md files appear, followed by chained buying-group-finder runs that produce their own files.
- **Next Sunday morning:** intro-finder picks up the Monday-written buying-group files (it intentionally lags by one cadence) and queues per-target Apify one-shots across that day. Tomorrow morning you'll see the first intros delivery md.
- **Every Mon–Fri morning:** daily-brief at 6am, then gmail-resurfacer at 7am.
- **Gmail re-surfacer catch-up mode:** the first ~30 weekday runs (~6 calendar weeks) walk forward through 12 months of inbox history at ~12 days per run. After the cursor reaches the present, it switches to steady-state mode (incremental new-mail diff). Daily output is the same shape across both modes.
- **Every night 11pm:** hubspot-manager processes the last 24h of new transcripts + replies, auto-applies ≤20 low-risk writes, queues everything else for next morning's daily-brief approval section.
- **Pending HubSpot approvals:** when hubspot-manager queues anything, the next morning's daily-brief will start with a "Pending HubSpot updates" table. Approve/reject by trigger phrase (see [HubSpot Manager](#hubspot-mcp-authorization)) — items stay in the queue until decided.

If a task didn't fire on the expected day (laptop was asleep / logged out), see [Missed-run recovery](#missed-run-recovery).

---

## Missed-run recovery

Windows Task Scheduler runs tasks with `-LogonType Interactive` — meaning they only fire **when you're logged in**. If your laptop was off, asleep, or you were logged out at the scheduled time, the run is skipped. No catch-up happens automatically when you log back in.

The agents are **idempotent** — safe to re-run manually. Each one dedups against state files so a manual re-run produces the same output as the cron would have:

| Missed task | Manual recovery |
|---|---|
| Daily brief 6am | `claude -p "daily brief morning"` |
| Commercial sweep Mon 7am | `claude -p "weekly commercial sweep"` |
| Academic sweep Mon 7am | `claude -p "weekly academic sweep"` |
| Intro-finder 7am | `claude -p "intro-finder daily morning"` |
| Gmail re-surfacer 7am | `claude -p "RUN gmail resurfacer"` |
| HubSpot manager 11pm | `claude -p "nightly hubspot manage"` |

If you miss several days in a row, the signal-watchers and gmail-resurfacer will pick up everything that's eligible (their seen-state files prevent duplicate writes). Intro-finder will resume on the active buying-group file's cursor where it left off. HubSpot manager will scan the last 24h of NEW activity only — if you want a longer window, edit the agent's Step 1 default temporarily (or re-run nightly for several days in a row to catch up incrementally).

---

## What the install scripts actually do

`install-schedule.ps1` does NOT add any cron daemon or background service. It registers six entries with Windows Task Scheduler that invoke `claude -p "..."` with the appropriate trigger phrase. You can see them with:

```powershell
Get-ScheduledTask -TaskName 'Nightingale-*'
```

Implications:

- **The schedule is per-machine.** If you clone the repo on a second machine and want it running there too, re-run `install-schedule.ps1` on that machine.
- **Schedules are not committed to the repo.** Cloning gives you the agent files, not the schedule itself. The install script is the bridge.
- **Tasks run with `-LogonType Interactive`.** They fire only when you're logged in. If your laptop is locked but logged-in and on AC, Windows will wake to fire the trigger. If you log out, tasks queue and fire next login.
- **Time is LOCAL.** Edit the `-At "7:00am"` argument in `install-schedule.ps1` before running if you want a different fire time.

To uninstall everything:

```powershell
Unregister-ScheduledTask -TaskName 'Nightingale-Daily-Brief-Morning','Nightingale-Commercial-Sweep','Nightingale-Academic-Sweep','Nightingale-Intro-Finder-Morning','Nightingale-Gmail-Resurfacer-Morning','Nightingale-HubSpot-Manager-Nightly','Nightingale-Investor-Analyzer-Weekly','Nightingale-Investor-Newsletter-Biweekly' -Confirm:$false
```

To delete credentials:

```powershell
Remove-Item "$env:USERPROFILE\.nightingale\secrets.json" -Force
```

To restore default permissions on the secrets file if the ACL ever blocks you out:

```powershell
icacls "$env:USERPROFILE\.nightingale\secrets.json" /reset
```

---

## Prerequisites (full)

1. **Windows 10/11** with PowerShell 5.1+ (`$PSVersionTable.PSVersion.Major` ≥ 5).
2. **Git for Windows** — for cloning + future pulls.
3. **Claude Code** installed, with `claude` on PATH. Verify: `Get-Command claude` returns a path.
4. **PowerShell ExecutionPolicy** at `RemoteSigned` (or looser) for the current user. The scripts work under `Bypass` but `Restricted` and `AllSigned` block manual runs.
5. **MCP connectors authorized in Claude Code** (see [MCP connector authorization](#mcp-connector-authorization)):
   - **ClinicalTrials.gov** (required for both sweeps + resurfacer + daily-brief + feedback-analyzer)
   - **Apollo.io** (required for commercial sweep; free tier is enough)
   - **Gmail** (required for resurfacer + daily-brief + feedback-analyzer + hubspot-manager)
   - **Google Calendar** (required for daily-brief)
   - **Google Drive** (required for feedback-analyzer + hubspot-manager transcript reads)
   - **HubSpot** (required for hubspot-manager nightly writes; read-only for resurfacer + daily-brief annotation)
6. **Google Drive share access** to `/curanostics/nightingale/call transcripts` — ask whoever owns it on the Nightingale team. Without it, transcript-driven agents (`feedback-analyzer`, `hubspot-manager`) operate against Gmail-only signals.
7. **For intro-finder + daily-brief Layer-B (optional)**:
   - An **Apify account** with a paid or trial credit balance (LinkedIn Actors typically use RESIDENTIAL proxy, ~$0.10–0.50 per call).
   - A **LinkedIn account** in good standing.
   - At least one LinkedIn-mutual-connections Apify Actor identified (see [Apify + LinkedIn setup](#apify--linkedin-setup-intro-finder--optional-daily-brief-layer-b)).
8. **For hubspot-manager (recommended)**:
   - A **HubSpot account** with permission to read + write contacts / companies / deals / notes / owners.
9. **Internet access** to: `efts.sec.gov`, `api.fda.gov`, `api.reporter.nih.gov`, `api.www.sbir.gov`, `api.apify.com`, `api.hubapi.com`, plus the WebSearch index.

The install + setup scripts check the ExecutionPolicy on startup and warn if it's `Restricted` or `AllSigned`. Recommended: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`.

---

## Repo layout

```
nightingale-gtm/
├── README.md                                            # this file
├── CLAUDE.md                                            # project context for Claude Code
├── .gitignore
├── .claude/
│   └── agents/
│       ├── signal-watcher-commercial.md
│       ├── signal-watcher-academic.md
│       ├── buying-group-finder-commercial.md
│       ├── buying-group-finder-academic.md
│       ├── intro-finder.md
│       ├── gmail-resurfacer.md
│       ├── daily-brief.md
│       ├── feedback-analyzer.md
│       └── hubspot-manager.md
├── 01-personas/
│   ├── commercial-persona.md
│   └── academic-persona.md
├── 06-agent-documentation/
│   └── signal-watcher-setup.md                          # detailed setup + troubleshooting per agent
├── scripts/
│   ├── install-schedule.ps1                             # registers 6 Task Scheduler entries
│   ├── setup-secrets.ps1                                # captures Apify + LinkedIn credentials + optional deck pointer (schema v4)
│   ├── run-one-apify-call.ps1                           # per-target worker (called by intro-finder one-shots)
│   ├── run-one-apify-company-roster.ps1                 # per-attendee Layer-B worker (called by daily-brief, optional)
│   └── start-ui.ps1                                     # launches the optional UI control panel
└── ui/                                                  # optional local Node.js + React control panel
    ├── README.md
    ├── package.json
    ├── server/                                          # Express server (loopback only)
    └── web/                                             # React + TypeScript + Vite frontend
```

---

## Common issues

- **"`claude` is not recognized"** — Claude Code isn't on PATH. Reinstall or add it manually.
- **"PowerShell ExecutionPolicy is Restricted"** — `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`.
- **Scheduled tasks never fire** — verify `Get-ScheduledTask -TaskName 'Nightingale-*'` shows them; verify you're actually logged in at the trigger time; verify Task Scheduler History is enabled and look for the entry. If task says "the operator or administrator has refused the request" you may need to re-register with elevated rights.
- **`HUBSPOT_NOT_AUTHORIZED-{date}.md` keeps appearing every night** — re-run the HubSpot OAuth from Claude Code Settings → Connectors. Verify with `claude -p "list pending hubspot updates"` — it should return without error.
- **`MCPS_NOT_AUTHORIZED-{date}.md` appears from feedback-analyzer** — neither Drive nor Gmail MCP is authorized. Authorize at least one.
- **Apify "404 Actor not found"** — your token is fine but the Actor ID is wrong. Re-run `setup-secrets.ps1` and paste the correct `{username}~{actor-name}` from the Apify store.
- **Apify "429 rate-limited"** — you've hit your monthly tier. Wait until reset or upgrade the Apify plan; intro-finder will resume automatically on the next cycle.
- **`.cookie-expired-active` sentinel persists** — re-run `setup-secrets.ps1` to capture a fresh `li_at` cookie. The sentinel is cleared by setup-secrets on a successful re-validation.
- **HubSpot writes show as the wrong owner** — you authorized into the wrong HubSpot account. Disconnect from Settings → Connectors and re-authorize with the correct sign-in.
- **Drive returns zero call transcripts** — you don't have share access to `/curanostics/nightingale/call transcripts`. Ask the folder owner on the Nightingale team to add you.

For deeper troubleshooting (cookie rotation, signal-watcher dedup edge cases, intro-finder cycle phase issues, hubspot-manager queue archival), see `06-agent-documentation/signal-watcher-setup.md`.

---

## What this does NOT do (v1)

- No outreach message generation — the qualified-list / buying-group / intros / brief / refinement markdown files are the deliverables.
- No HubSpot deletes (categorically forbidden by hubspot-manager — even with explicit approval).
- No HubSpot contact / company merges.
- No Apollo enrichment on Weak-tier commercial companies (free-tier credit gate).
- No Apollo at all for the academic agent.
- No conference-abstract scraping (ASCO / AHA / JPM) — quarterly cadence does not fit a weekly cron.
- No emails for mutuals in intros (LinkedIn doesn't expose them; pattern-guessing is forbidden after a 2026-05-06 5-bounce incident).
- No macOS or Linux support — Windows only.
- No automatic catch-up of missed Task Scheduler runs (see [Missed-run recovery](#missed-run-recovery)).
- No automatic state-file rotation — `transactions.jsonl` and other append-only files grow over time. For low-volume single-user operation they'll be fine for years; if you adopt across a large team, plan a periodic archival pass.

These are explicitly deferred / out of scope. Adding any of them is a follow-up project, not a v1 change.

---

## Troubleshooting

See `06-agent-documentation/signal-watcher-setup.md` for first-run verification steps, common operations, cookie-expiry recovery, and a per-agent troubleshooting checklist (Apollo gating, LinkedIn search index degradation, cross-agent boundary mis-fires, Apify 404 / 429 / cookie-rejection diagnostics, HubSpot manager pending-queue management).
