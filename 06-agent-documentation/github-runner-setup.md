# GitHub Actions self-hosted runner — agent scheduling (Phase 3)

This replaces Windows Task Scheduler as the way the Nightingale agent chain gets
scheduled. **Scheduling moves to GitHub; execution stays on your PC.**

## Why this design

The agents run as `claude -p "<phrase>"` against your **local** Claude Code
install. They need three things that cannot move to a GitHub-hosted cloud runner:

1. **claude.ai MCP connectors** (Gmail, Calendar, HubSpot, Drive, Apollo,
   ClinicalTrials.gov) — interactive OAuth through claude.ai, not exportable keys.
2. **The Desktop output tree** `~/Desktop/nightingale-signals/**`.
3. **Windows Task Scheduler** for the intro-finder per-target one-shots.

So we use a **self-hosted GitHub Actions runner**: the cron schedule lives in
GitHub (`.github/workflows/*.yml`), but the job runs on *your* machine via a
runner installed as a boot-start Windows service. This is the only way to get
"scheduling that survives a reboot" without losing local auth.

## What's in the repo

```
.github/workflows/
  daily-brief.yml                 # Mon-Fri 06:00 ET   (cron 0 11 * * 1-5 UTC)
  signal-watcher-commercial.yml   # Mon 07:00 ET       (cron 0 12 * * 1)
  signal-watcher-academic.yml     # Mon 07:00 ET       (cron 0 12 * * 1)
  intro-finder.yml                # Sun-Fri 07:00 ET   (cron 0 12 * * 0-5)
  gmail-resurfacer.yml            # Mon-Fri 07:00 ET   (cron 0 12 * * 1-5)
  hubspot-manager.yml             # daily 23:00 ET     (cron 0 4 * * *)
  investor-analyzer.yml           # Mon 08:00 ET       (cron 0 13 * * 1)
  investor-newsletter.yml         # biweekly Fri 09:00 ET (cron 0 14 * * 5 + guard)
  feedback-analyzer.yml           # workflow_dispatch only (on-demand)
  pitch-deck-updater.yml          # workflow_dispatch only (chained / on-demand)

scripts/
  install-runner.ps1      # download + register the runner as a service (+ boot-catchup task)
  boot-catchup.ps1        # on-boot backstop for >24h outages
  uninstall-schedule.ps1  # remove the 8 legacy Task Scheduler agents
  install-schedule.ps1    # DEPRECATED (use -Legacy only as a fallback)
```

Every scheduled workflow also has `workflow_dispatch`, so you can trigger any
agent manually from the GitHub Actions tab, `gh workflow run`, or the dashboard's
**Agents → Run now** (which in Docker mode dispatches the workflow).

## ⚠️ Time zone / DST caveat (read this)

GitHub cron is **UTC only** and does **not** follow local Daylight Saving Time.
The cron lines assume **US Eastern STANDARD time (EST, UTC-5)**. During Eastern
Daylight time (EDT, UTC-4, ~mid-March to early-November) every Nightingale
workflow fires **one hour later** in local terms. They all shift together, so the
*relative* order (daily-brief before the 7am stack) is always preserved — only the
absolute local clock time drifts ±1h twice a year.

If you are **not** in US Eastern, edit the `cron:` line in each workflow (or just
rely on `workflow_dispatch` + boot-catchup). There is no per-user timezone in
GitHub cron.

## ⚠️ Which repo does the runner attach to? (read before activating)

GitHub Actions **only runs workflows that exist in the repo on GitHub.** Attach
the runner to **the GitHub repo that hosts these `.github/workflows/*.yml`
files** — for this portable mirror that is **`tlosdev/nightingale-gtm`** (or your
own fork of it). The optional PAT (step 3 / boot-catchup) must point at the same
repo. The examples below use `tlosdev/nightingale-gtm`; substitute your fork if
you cloned one.

## Quick activation (recommended)

`scripts/activate-runner.ps1` does the whole migration in one command — it
self-elevates (UAC), fetches a runner registration token via the `gh` CLI,
installs the runner service, removes the legacy Task Scheduler agents, and prints
a verification summary. The registration token is handed to the installer through
the process **environment block**, never a command line.

```powershell
# Preview first (recommended) -- shows what would happen, changes nothing:
.\scripts\activate-runner.ps1 -WhatIf

# Then, from the repo root. No need to pre-elevate or mint a token yourself:
.\scripts\activate-runner.ps1
```

Defaults: `-RepoUrl https://github.com/tlosdev/nightingale-gtm`,
`-GhAccount tlosdev` (the gh account with admin on that repo, used to mint the
token). Pass `-RepoUrl`/`-GhAccount` if you cloned a fork. Useful switches:

```powershell
.\scripts\activate-runner.ps1 -WhatIf               # dry-run preview (read-only; no elevation, no token mint)
.\scripts\activate-runner.ps1 -ConfigureSecrets     # also run setup-secrets.ps1 (add the GitHub PAT)
.\scripts\activate-runner.ps1 -Token 'AXXXX...'     # use a token you minted yourself (run elevated)
.\scripts\activate-runner.ps1 -SkipLegacyUninstall  # keep the old tasks (almost never what you want)
```

Prerequisites for the auto-token path: the GitHub CLI (`gh`) installed and the
`-GhAccount` authenticated with **admin** on the repo (`gh auth login`). If `gh`
isn't available, mint a token yourself (below) and pass `-Token`.

After it finishes, jump to [Verify](#verify).

---

If you'd rather run each step by hand, follow the manual setup below instead.

## Manual setup

### 1. Install the runner (one time, elevated PowerShell)

Get a **runner registration token** from GitHub — either from the web UI:
**your repo → Settings → Actions → Runners → New self-hosted runner** → copy the
token in the `./config.cmd ... --token XXXX` line (short-lived, ~1h, single-use —
*not* a PAT). Or from the terminal:

```powershell
gh auth switch --user tlosdev
gh api -X POST repos/tlosdev/nightingale-gtm/actions/runners/registration-token --jq .token
gh auth switch --user <your-default-account>   # restore
```

```powershell
# Run from an ELEVATED PowerShell (installing a service needs admin)
.\scripts\install-runner.ps1 `
    -RepoUrl 'https://github.com/tlosdev/nightingale-gtm' `
    -Token   'AXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
```

This downloads the runner, registers it with labels `self-hosted,windows`,
installs it as a Windows service (Automatic start = starts on boot), writes
`NIGHTINGALE_VAULT=<repo>` into the runner's `.env` (so jobs `Set-Location` to your
real vault), and registers the `Nightingale-Boot-Catchup` on-boot task.

> `install-runner.ps1` also accepts the token via the `NIGHTINGALE_RUNNER_TOKEN`
> environment variable (this is how `activate-runner.ps1` keeps it off the command
> line). The `-Token` parameter takes precedence.

### 2. Migrate off the old Task Scheduler agents

```powershell
.\scripts\uninstall-schedule.ps1        # add -WhatIf first to preview
```

This removes exactly the eight legacy `Nightingale-*` agent tasks so the two
systems don't **double-fire**. It does **not** touch `Nightingale-Boot-Catchup`
or the dynamic intro-finder one-shots.

### 3. (Optional) enable dispatch from Docker + the boot-catchup backstop

```powershell
.\scripts\setup-secrets.ps1             # schema v5 — prompts for GitHub PAT + repo
```

Create a **fine-grained PAT** scoped to only your Nightingale repo with
Repository permission **"Actions: Read and write"**
(<https://github.com/settings/personal-access-tokens/new>), and give the repo as
`owner/repo`. You can also set these from the dashboard **Settings** tab (native
host mode only — secrets editing is disabled inside the container).

This unlocks two things:
- The dashboard's **Run now** button working in **Docker/container mode** (the
  container fires a `workflow_dispatch` instead of spawning the host CLI).
- The **boot-catchup backstop** (below).

## Boot catch-up — surviving a powered-off machine

Two layers:

1. **Primary (free):** when a scheduled workflow fires, GitHub queues the job for
   an available runner. If your PC was off at the cron time and boots later the
   **same day**, the runner service starts on boot and picks up the queued job.
   This covers same-day misses with no extra moving parts.
2. **Backstop (`boot-catchup.ps1`, >24h outages):** the `Nightingale-Boot-Catchup`
   task runs ~2 minutes after every boot. For each agent it compares a per-agent
   cursor (`~/.nightingale/boot-catchup-cursor.json`, last dispatch date) against a
   **cadence** (the longest normal gap, e.g. daily-brief = 3 days to absorb a
   weekend). Anything overdue beyond its cadence gets exactly one
   `workflow_dispatch`, then the cursor is stamped so a second boot the same day
   won't re-fire it. On first run it seeds the cursor to "today" and dispatches
   nothing (no thundering herd).

   This is a **coarse backstop**, not a precise missed-occurrence scheduler — by
   design. Requires the GitHub PAT + repo from step 3.

   Test it: `.\scripts\boot-catchup.ps1 -DryRun`

## Verify

```powershell
Get-Service 'actions.runner.*'                 # Running, StartType Automatic
Get-ScheduledTask -TaskName 'Nightingale-*'    # only Nightingale-Boot-Catchup (+ dynamic intro one-shots)
gh workflow run daily-brief.yml --repo tlosdev/nightingale-gtm --ref main   # then check the Actions tab + Desktop output
```

## Caveats

- **Scheduled workflows auto-disable after 60 days of repo inactivity.** The
  nightly hubspot-manager run keeps the repo active, so this shouldn't trigger in
  practice — but if all agents go quiet for 60 days, GitHub disables the crons and
  you re-enable them in the Actions tab.
- **Cron events can be delayed** under GitHub load (especially on the hour). The
  agents are not second-sensitive, so this is fine.
- **The intro-finder per-target Apify one-shots stay on Windows Task Scheduler** —
  the intro-finder agent creates them dynamically on the host; only the daily
  delivery+queue pass moved to GitHub.
- **Don't run both systems.** If you keep the legacy tasks (`-Legacy`) *and* the
  runner, every agent fires twice. Run `uninstall-schedule.ps1` after migrating.

## Rollback

```powershell
# Stop + remove the runner service
cd C:\actions-runner-nightingale
.\svc.cmd stop; .\svc.cmd uninstall
.\config.cmd remove --token <removal-token-from-github>
# Remove the boot task, restore legacy scheduling
Unregister-ScheduledTask -TaskName 'Nightingale-Boot-Catchup' -Confirm:$false
..\scripts\install-schedule.ps1 -Legacy
```
