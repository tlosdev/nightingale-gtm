# nightingale-gtm

Signal-first prospect-discovery agents for Nightingale's GTM motion. Two agents that scan public clinical-trial, regulatory, funding, and academic-research feeds every Monday morning and drop a qualified-companies markdown file on your Desktop.

- **`signal-watcher-commercial`** — biotech / pharma / medical-device sponsors, 10–200 employees, US. Sources: ClinicalTrials.gov, SEC EDGAR 8-Ks, openFDA, press wires, LinkedIn job postings, Apollo funding.
- **`signal-watcher-academic`** — US academic medical centers and research hospitals running human-subjects studies. Sources: ClinicalTrials.gov (academic Lead Sponsor or Facility), NIH RePORTER, SBIR/STTR awards, university press / news.

Both stop at the qualified-list. No outreach generation, no HubSpot sync — those are downstream / out of scope for v1.

---

## Quick start

You need Claude Code installed and the `claude` CLI on your PATH.

```bash
# 1. Clone
git clone https://github.com/tlosdev/nightingale-gtm.git
cd nightingale-gtm

# 2. Register the weekly schedule (ONE-TIME setup)
# Windows (from PowerShell):
.\scripts\install-schedule.ps1

# macOS / Linux (from bash/zsh):
chmod +x scripts/install-schedule.sh
./scripts/install-schedule.sh

# 3. (Optional) Run a manual sweep right now to verify everything works
claude -p "scan commercial signals"
claude -p "scan academic signals"
```

After step 2, the two agents will run **automatically every Monday at 7:00 AM local time** for as long as the scheduled task is registered on this machine.

Outputs land in:

```
~/Desktop/nightingale-signals/
├── commercial/output/commercial-signals-YYYY-MM-DD.md
└── academic/output/academic-signals-YYYY-MM-DD.md
```

The `~/Desktop/nightingale-signals/` folder is created automatically on the first run of each agent.

---

## What the install scripts actually do

The "automatic every Monday" behavior is not magic — it relies on the **host OS's scheduler** (Windows Task Scheduler, macOS launchd, Linux cron). The install script registers one entry per agent that runs `claude -p "weekly {commercial|academic} sweep"` from the cloned repo directory at 07:00 every Monday.

This means:
- **The schedule is per-machine.** If you clone the repo on a second machine and want it running there too, re-run the install script on that machine.
- **Schedules are not committed to the repo.** Cloning the repo gives you the agent files, not the schedule itself. The install script is the bridge.
- **Your machine has to be on (or wake) at 7:00 AM Monday** for the run to fire. Laptops asleep through the trigger time will run at the next available wake event (Windows + macOS) or skip the window entirely (Linux).
- **Time is LOCAL.** The scheduled task fires at 7:00 in your machine's local timezone. If you want a specific timezone (e.g., always 7:00 AM Eastern regardless of where you travel), edit the `-At` argument in `install-schedule.ps1` or the `StartCalendarInterval`/cron expression in `install-schedule.sh` before running.

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

## Prerequisites

1. **Claude Code** installed locally (Mac, Windows, or Linux), with `claude` on your PATH.
2. **MCP connectors authorized** in your Claude Code instance:
   - **ClinicalTrials.gov** — required for both agents.
   - **Apollo.io** — required for the commercial agent (the free tier is enough — Apollo enrichment is gated to Strong-tier companies only).
   - **WebFetch + WebSearch** — built into Claude Code; used by every other source.
3. **Internet access** to: `efts.sec.gov`, `api.fda.gov`, `api.reporter.nih.gov`, `api.www.sbir.gov`, plus the WebSearch index.

No API keys, no `.env`, no setup script beyond the schedule installer. MCP connector auth is managed inside Claude Code.

---

## Repo layout

```
nightingale-gtm/
├── README.md                                       # this file
├── CLAUDE.md                                       # project context for Claude Code
├── .claude/
│   └── agents/
│       ├── signal-watcher-commercial.md            # the commercial agent prompt
│       └── signal-watcher-academic.md              # the academic agent prompt
├── 01-personas/
│   ├── commercial-persona.md                       # ICP source of truth for commercial
│   └── academic-persona.md                         # ICP stub for academic (v0)
├── 06-agent-documentation/
│   └── signal-watcher-setup.md                     # detailed setup + troubleshooting
└── scripts/
    ├── install-schedule.ps1                        # Windows installer
    └── install-schedule.sh                         # macOS + Linux installer
```

---

## What this does NOT do (v1)

- No outreach message generation — the qualified-list markdown file is the deliverable.
- No HubSpot company / contact / association creation.
- No Apollo enrichment on Weak-tier commercial companies (free-tier credit gate).
- No Apollo at all for the academic agent.
- No conference-abstract scraping (ASCO / AHA / JPM) — quarterly cadence does not fit a weekly cron.
- No Crunchbase or other paid data sources — Apollo `last_raised_at` covers the high-value commercial funding cases.

These are explicitly deferred. Adding any of them is a follow-up project, not a v1 change.

---

## Troubleshooting

See `06-agent-documentation/signal-watcher-setup.md` for first-run verification steps, common operations, and a troubleshooting checklist (Apollo gating, LinkedIn search index degradation, cross-agent boundary mis-fires, etc.).
