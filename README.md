# nightingale-gtm

Five signal-first prospect-discovery agents for Nightingale's GTM motion. They run on Windows + Claude Code, hit public clinical-trial / regulatory / funding / academic-research feeds plus your LinkedIn network, your own Gmail history, and your Google Calendar, and drop daily/weekly markdown files on your Desktop.

- **`signal-watcher-commercial`** — biotech / pharma / med-device sponsors, 10–200 employees, US. Sources: ClinicalTrials.gov, SEC EDGAR 8-Ks, openFDA, press wires, LinkedIn job postings, Apollo funding.
- **`signal-watcher-academic`** — US academic medical centers and research hospitals running human-subjects studies. Sources: ClinicalTrials.gov (academic Lead Sponsor or Facility), NIH RePORTER, SBIR/STTR, university press / news.
- **`buying-group-finder-{commercial,academic}`** — auto-chained after each sweep. Find Economic Buyer / Tech Gatekeeper / Champion (commercial) or PI / Buyer / Tech Gatekeeper (academic) at every surfaced company / institution via WebSearch.
- **`intro-finder`** — runs daily Sun–Fri 7am. Spreads the active buying-group file's targets across the week (1/5 per day), invokes Apify per target across a randomized 8am–8pm window, and delivers a per-target + per-mutual warm-intro file each morning.
- **`gmail-resurfacer`** — runs daily Mon–Fri 7am (parallel to intro-finder, NOT chained). Walks 12 months of Gmail history forward from a cursor, scores every thread against both personas, and surfaces the top 5 contacts to re-engage today with HubSpot state annotation. Fully read-only against Gmail / HubSpot / Apollo. Never quotes email body verbatim.
- **`daily-brief`** — runs daily Mon–Fri 6am (one hour before the 7am stack so it lands first). Pulls today + tomorrow's Google Calendar, filters to external meetings, and assembles per-meeting prep including persona match, recent thread context, cross-agent context, Layer-A cached intro suggestions (reverse-lookup against intro-finder's `found-mutuals.json`), Layer-B fresh persona-roster intros (Apify with WebSearch fallback), recommended talking points, and HubSpot state. Fully read-only across all sources.

This repo is **Windows-only** as of 2026-05. macOS and Linux are not supported.

---

## Quick start (Windows + PowerShell)

You need:
- Windows 10/11 with PowerShell 5.1+
- Git
- Claude Code installed, `claude` on PATH

```powershell
# 1. Clone
git clone https://github.com/tlosdev/nightingale-gtm.git
cd nightingale-gtm

# 2. (One-time) Register the schedules
.\scripts\install-schedule.ps1

# 3. (Optional, one-time) Set up secrets for the intro-finder stage
.\scripts\setup-secrets.ps1

# 4. (Optional) Run a manual sweep right now to verify everything works
claude -p "scan commercial signals"
claude -p "scan academic signals"
```

That's it. Step 2 registers three Windows Task Scheduler entries. Step 3 is **opt-in** — if you only want the signal-watcher + buying-group-finder stages, skip it. Intro-finder will write a `SECRETS_MISSING-{date}.md` notice each morning until you run setup-secrets.

---

## What runs when

| Task | Cadence | What it does |
|---|---|---|
| `Nightingale-Daily-Brief-Morning`        | Mon–Fri 6am local        | Daily brief: today + tomorrow calendar prep with per-meeting persona match, cross-agent context, and intro suggestions |
| `Nightingale-Commercial-Sweep`           | Monday 7am local         | Commercial sweep + buying-group discovery |
| `Nightingale-Academic-Sweep`             | Monday 7am local         | Academic sweep + buying-group discovery |
| `Nightingale-Intro-Finder-Morning`       | Sun–Fri 7am local        | Intro-finder: delivery (Mon–Fri) + queue (Sun–Thu) |
| `Nightingale-Gmail-Resurfacer-Morning`   | Mon–Fri 7am local        | Gmail re-surfacer: walks 12-month inbox history, surfaces top 5 contacts to re-engage today |

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
└── daily-brief\
    ├── state\                                            # attendee-roster cache + brief history + LinkedIn-URL cache
    └── output\daily-brief-YYYY-MM-DD.md                  # daily brief (Mon–Fri, when Google Calendar MCP authorized)
```

The `nightingale-signals\` folder is created automatically on the first run.

---

## Intro-finder + Gmail Re-Surfacer + Daily Brief are opt-in

Three of the five agents need external authorization:

- `intro-finder` needs Apify + a LinkedIn `li_at` cookie (set up via `scripts/setup-secrets.ps1`).
- `gmail-resurfacer` needs the Gmail MCP connector authorized in Claude Code (Settings → Connectors → Gmail). Optionally also authorize the HubSpot + Apollo + ClinicalTrials.gov MCP connectors for richer scoring and annotation.
- `daily-brief` needs the Google Calendar MCP connector authorized in Claude Code (Settings → Connectors → Google Calendar). Optionally: Gmail MCP for attendee identity resolution + recent thread context, HubSpot MCP for state annotation, Apollo MCP for company enrichment, ClinicalTrials.gov MCP for trial-design-window cross-ref, and a second optional Apify Actor (`apify_company_roster_actor_id`, set via `scripts/setup-secrets.ps1` schema v3) for richer Layer-B persona-roster intros. Without the Layer-B Actor, daily-brief falls back to WebSearch automatically.

Without those:

- `signal-watcher-{commercial,academic}` ✓ runs every Monday
- `buying-group-finder-{commercial,academic}` ✓ runs every Monday (auto-chained from sweep)
- `intro-finder` ⚠ runs but writes `SECRETS_MISSING-{date}.md` notices instead of intros
- `gmail-resurfacer` ⚠ runs but writes `GMAIL_NOT_AUTHORIZED-{date}.md` notices instead of contact lists
- `daily-brief` ⚠ runs but writes `CALENDAR_NOT_AUTHORIZED-{date}.md` notices instead of meeting prep

To enable intros, run `setup-secrets.ps1`. It prompts for four things in one flow:

1. **Apify API token** — from `https://console.apify.com/account/integrations`.
2. **Apify Actor ID** — pick a LinkedIn-mutual-connections Actor from `https://apify.com/store?search=linkedin+mutual+connections` and paste its identifier (format `{username}~{actor-name}`).
3. **Your own LinkedIn profile URL** — used once at setup to validate that the chosen Actor can be invoked with your cookie. Costs ~$0.01–0.05 in Apify credit. Example: `https://linkedin.com/in/your-slug`.
4. **LinkedIn `li_at` cookie** — the session cookie from your logged-in browser. Chrome DevTools → Application → Cookies → `https://www.linkedin.com` → `li_at` → copy Value.

All four are validated in one round-trip. Bad credentials fail fast at setup, not on Monday morning. Re-run anytime to rotate any secret.

**Why all four?** The official LinkedIn API doesn't expose mutual connections. The only programmatic path is an Apify Actor that drives a logged-in browser session via your cookie. This violates LinkedIn ToS — account-restriction risk is low at the pace this agent enforces (max ~10–20 calls/day with random spacing) but it is not zero. See `06-agent-documentation/signal-watcher-setup.md` for the full ToS / safety guidance.

Credentials live in `%USERPROFILE%\.nightingale\secrets.json` with restricted ACL. The file is outside the repo and cannot be accidentally git-add'd.

---

## What the install scripts actually do

`install-schedule.ps1` does NOT add any cron daemon or background service. It registers three entries with Windows Task Scheduler that invoke `claude -p "..."` with the appropriate trigger phrase. You can see them with:

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
Unregister-ScheduledTask -TaskName 'Nightingale-Daily-Brief-Morning','Nightingale-Commercial-Sweep','Nightingale-Academic-Sweep','Nightingale-Intro-Finder-Morning','Nightingale-Gmail-Resurfacer-Morning' -Confirm:$false
```

To delete credentials:

```powershell
Remove-Item "$env:USERPROFILE\.nightingale\secrets.json" -Force
```

---

## Prerequisites

1. **Windows 10/11** with PowerShell 5.1+.
2. **Claude Code** installed, with `claude` on PATH.
3. **MCP connectors authorized** in your Claude Code instance:
   - **ClinicalTrials.gov** — required for both sweeps.
   - **Apollo.io** — required for the commercial sweep (the free tier is enough — Apollo enrichment is gated to Strong-tier companies only).
   - **WebFetch + WebSearch** — built into Claude Code.
4. **For intro-finder ONLY**:
   - An **Apify account** with a paid or trial credit balance (LinkedIn-mutual-connections Actors typically run RESIDENTIAL proxy, ~$0.10–0.50 per call).
   - A **LinkedIn account** in good standing.
5. **Internet access** to: `efts.sec.gov`, `api.fda.gov`, `api.reporter.nih.gov`, `api.www.sbir.gov`, `api.apify.com`, plus the WebSearch index.

PowerShell ExecutionPolicy: the install + setup scripts check this on startup and warn if it's `Restricted` or `AllSigned`. Recommended: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`.

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
│       └── daily-brief.md
├── 01-personas/
│   ├── commercial-persona.md
│   └── academic-persona.md
├── 06-agent-documentation/
│   └── signal-watcher-setup.md                          # detailed setup + troubleshooting
└── scripts/
    ├── install-schedule.ps1                             # registers 5 Task Scheduler entries
    ├── setup-secrets.ps1                                # captures Apify + LinkedIn credentials (schema v3)
    ├── run-one-apify-call.ps1                           # per-target worker (called by intro-finder one-shots)
    └── run-one-apify-company-roster.ps1                 # per-attendee Layer-B worker (called by daily-brief, optional)
```

---

## What this does NOT do (v1)

- No outreach message generation — the qualified-list / buying-group / intros markdown files are the deliverables.
- No HubSpot company / contact / association creation.
- No Apollo enrichment on Weak-tier commercial companies (free-tier credit gate).
- No Apollo at all for the academic agent.
- No conference-abstract scraping (ASCO / AHA / JPM) — quarterly cadence does not fit a weekly cron.
- No emails for mutuals in intros (LinkedIn doesn't expose them; pattern-guessing is forbidden after a 2026-05-06 5-bounce incident).
- No macOS or Linux support — Windows only.

These are explicitly deferred / out of scope. Adding any of them is a follow-up project, not a v1 change.

---

## Troubleshooting

See `06-agent-documentation/signal-watcher-setup.md` for first-run verification steps, common operations, cookie-expiry recovery, and a troubleshooting checklist (Apollo gating, LinkedIn search index degradation, cross-agent boundary mis-fires, Apify 404 / 429 / cookie-rejection diagnostics).
