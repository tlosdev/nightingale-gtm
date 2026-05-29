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

The `~` resolves correctly per-OS:
- Windows PowerShell: `$env:USERPROFILE\Desktop\nightingale-signals\...`
- macOS / Linux: `$HOME/Desktop/nightingale-signals/...`

The folder tree is created automatically on first run — no manual `mkdir` needed.

---

## Prerequisites

1. **Claude Code** installed locally (Mac, Windows, or Linux).
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

Both agents are designed to run weekly on Monday at 7am US Eastern. Registration is per-user (your schedule lives on your machine; it is not committed to the repo).

Inside Claude Code, register the two schedules using `CronCreate`:

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
| Inspect sweep dedup state | Open `~/Desktop/nightingale-signals/{commercial|academic}/state/seen-signals.json` |
| Inspect buying-group state | Open `~/Desktop/nightingale-signals/{commercial|academic}/buying-groups/state/found-companies.json` |
| Force a re-surface for a known company | Edit `company_tier_history.{key}.signal_types_seen` in the sweep state JSON to remove one type; next run will re-surface when that type fires |
| Force re-query of contacts for a known company | Delete the entry from `buying-groups/state/found-companies.json` (or set `last_found` to a date >30 days ago); next buying-group run will re-discover |
| Clear all state (start over) | Delete the `seen-signals.json` and `found-companies.json` files; next run re-bootstraps |
| Tighten academic title regex | Edit the buyer/CISO title lists in `01-personas/academic-persona.md` (the agent reads it every run) |
| Disable a flaky source | Edit the agent file to comment out the source block; e.g. LinkedIn jobs WebSearch occasionally degrades |
| Disable the buying-group auto-chain | Delete `Step 11 — Hand off to buying-group-finder-*` from the signal-watcher agent file. The sweep will still run; contact discovery just won't fire after it. |

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

**The agent fails at Step 0 with a permission error on `~/Desktop/`.** Some corporate-managed Windows or macOS profiles restrict the Desktop folder. Manually create `~/Desktop/nightingale-signals/` once with the OS file manager and rerun — Step 0 will accept an existing folder and proceed.

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
| `01-personas/commercial-persona.md` | ICP source of truth for the commercial side (drives signal qualification AND title-list for contact discovery) |
| `01-personas/academic-persona.md` | ICP source of truth for the academic side (v0 stub, will firm up after a few sweeps) |
| `.claude/agents/prospecter.md` | Sibling agent — full company-first prospect discovery pipeline. The signal-watchers complement, not replace, prospecter. |
