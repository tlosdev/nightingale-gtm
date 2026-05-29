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

## Register the weekly schedule (one-time setup)

Both agents are designed to run weekly on Monday at 7:00 AM **local time**. Registration is per-machine — the repo carries the install scripts, not the schedule itself, because OS schedulers are per-user state.

Run the appropriate installer once after cloning:

```bash
# Windows (from PowerShell, in the repo root):
.\scripts\install-schedule.ps1

# macOS or Linux (from bash/zsh, in the repo root):
chmod +x scripts/install-schedule.sh
./scripts/install-schedule.sh
```

The installer detects your OS and registers two scheduled tasks (Windows Task Scheduler / macOS launchd / Linux cron) that wake up every Monday at 7:00 AM local time and invoke `claude` headlessly with the appropriate trigger phrase. Verify with:

```bash
# Windows:
Get-ScheduledTask -TaskName 'Nightingale-*'

# macOS:
launchctl list | grep nightingale

# Linux:
crontab -l | grep nightingale-gtm
```

When a scheduled run fires, the agent sends a single `PushNotification` with the headline signal counts so you see the result without opening the terminal. Manual triggers (`scan commercial signals` etc.) do not send a push notification — the terminal summary is sufficient.

To uninstall:

```bash
# Windows:
Unregister-ScheduledTask -TaskName 'Nightingale-Commercial-Sweep','Nightingale-Academic-Sweep' -Confirm:$false

# macOS:
launchctl unload ~/Library/LaunchAgents/com.nightingale.commercial-sweep.plist
launchctl unload ~/Library/LaunchAgents/com.nightingale.academic-sweep.plist
rm ~/Library/LaunchAgents/com.nightingale.{commercial,academic}-sweep.plist

# Linux:
crontab -e   # delete the two lines tagged "# nightingale-gtm"
```

---

## Common operations after first run

| What | How |
|---|---|
| Manual sweep (commercial) | `scan commercial signals` |
| Manual sweep (academic) | `scan academic signals` |
| Inspect dedup state | Open `~/Desktop/nightingale-signals/{commercial|academic}/state/seen-signals.json` |
| Force a re-surface for a known company | Edit `company_tier_history.{key}.signal_types_seen` in the state JSON to remove one type; next run will re-surface when that type fires |
| Clear all state (start over) | Delete the `seen-signals.json` file; next run re-bootstraps |
| Tighten academic title regex | Edit the buyer/CISO title lists in `01-personas/academic-persona.md` (the agent reads it every run) |
| Disable a flaky source | Edit the agent file to comment out the source block; e.g. LinkedIn jobs WebSearch occasionally degrades |

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

## Related files

| File | Role |
|---|---|
| `.claude/agents/signal-watcher-commercial.md` | The commercial agent prompt |
| `.claude/agents/signal-watcher-academic.md` | The academic agent prompt |
| `01-personas/commercial-persona.md` | ICP source of truth for the commercial agent |
| `01-personas/academic-persona.md` | ICP stub for the academic agent (v0, will firm up after a few sweeps) |
| `scripts/install-schedule.ps1` | Windows installer for the weekly Monday 7am scheduled task |
| `scripts/install-schedule.sh` | macOS / Linux installer for the weekly Monday 7am scheduled task |
