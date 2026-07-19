# SOP Change History watcher — usage

Automates **SOP-QA-001 step 8**: whenever a compliance SOP is edited, a new
`Change History` row is appended and the header `Version (date)` is bumped — no
silent edits, no forgetting. This is the mechanical half of the ALCOA-attributable
document audit trail (git history is the other half).

## What it does

A background watcher over the three SOP folders —
`07-compliance/GxP/sops`, `07-compliance/SOC 2/sops`, `07-compliance/HIPAA/sops` —
that, on each edit to an `SOP-*.md`:

- **opens an editing session** and appends **one** new Change History row
  (minor bump, e.g. `1.2 -> 1.3`), with the UTC date, your author string, and an
  auto-description of which sections changed (`Edited sections: Procedure, Records.`);
- **keeps updating that same row** (date + description) while you continue editing —
  so a whole editing session is one version bump, not one per save;
- **seals the session** after 5 idle minutes *or* when a new git commit lands; the
  next edit opens a fresh session (a new bump).

It only ever writes the header `Version` token and the Change History rows, so it
never fights `scripts/check-sop-sync.ps1` (titles/context/framework flags are
untouched). A master SOP and its SOC 2 / HIPAA framework-native copy each get their
own independent row when both are edited (step 8 + rule 4).

## One-time setup

```powershell
# 1. Set the author string used in every row (git user.name alone is not enough).
git config nightingale.sopAuthor "Ben Heuertz, COO"

# 2. (Optional) auto-start the watcher at logon.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-sop-watcher.ps1
```

Author resolution order: `git config nightingale.sopAuthor` ->
`~/.nightingale/sop-author.txt` -> `git config user.name`.

## Running it

```powershell
# Run in the foreground (Ctrl-C to stop).
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/watch-sop-history.ps1

# If installed at logon, start it now without logging off:
Start-ScheduledTask -TaskName 'Nightingale-SOP-History-Watcher'

# Remove the logon task:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-sop-watcher.ps1 -Unregister
```

Tunables: `-PollSeconds` (default 3), `-DebounceSeconds` (default 8 — a change must
be quiet this long before it is stamped), `-SealMinutes` (default 5), `-Once` (one
pass and exit).

## Editorial (typo-only) changes

Editorial/typo-only corrections get a dotted sub-revision (`1.2 -> 1.2.1`) instead
of a minor bump. Since the watcher fires on edit (no commit message to tag), mark the
SOP **before** editing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/mark-sop-editorial.ps1 SOP-QA-001
# ...then edit the SOP. The next session for SOP-QA-001 is a sub-revision.
# Undo a pending mark:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/mark-sop-editorial.ps1 SOP-QA-001 -Clear
```

The mark is a one-shot sentinel file at `~/.nightingale/sop-editorial/<SOP-ID>.flag`,
consumed when that SOP's next session opens.

## Refining the "why"

The auto-description captures **what** sections changed and **who** — but not always
**why**. To add the rationale, edit the row's Description cell by hand *after* the
session seals (idle 5 min or after a commit). While a session is still active the
watcher keeps the auto-description fresh; once you customize a cell so it no longer
starts with `Edited `, the watcher stops overwriting it.

## Deletions and retirement

The watcher can append a Change History row on **edit**, but it cannot put one in a
file that is **deleted** — the Change History table lives inside the SOP, so it is
destroyed with the file. Under SOP-QA-001 a controlled SOP should be **retired in
place** (leave the file, set its status, add a Change History row), never hard-deleted.

So when a tracked SOP disappears off disk, the watcher instead:

- confirms the file has stayed gone for `-DebounceSeconds` (so an editor's atomic
  save — delete-then-rename — is not mistaken for a deletion);
- appends a row to the durable **retirement log** at
  `~/.nightingale/sop-retirement-log.md` (SOP id, last known version, author, UTC
  time) — outside the repo, so the record survives the file;
- prints a red `! DELETED …` warning and drops the file from its state.

Treat any entry there that was **not** a deliberate retirement as a document-control
deviation to investigate. If the delete was accidental, restore the file (git, or your
editor's undo) — the watcher re-seeds it on the next scan without retro-stamping.

## Manual fallback (watcher not running)

If the watcher was off when you edited, stamp changed SOPs in one shot before
committing. It diffs each SOP against the watcher's last-sealed baseline
(`~/.nightingale/sop-history-state.json`), falling back to the file at `HEAD` --
so it works whether or not the compliance tree is committed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stamp-sop-history.ps1
# -Editorial for a sub-revision, -WhatIf to preview, -Path <file> to target one file.
```

A malformed SOP (e.g. a new draft with no Change History table yet) is skipped with
a warning rather than aborting the run -- same isolation as the watcher.

## Files

| File | Role |
|---|---|
| `scripts/stamp-sop-history.ps1` | Parse/write engine + one-shot CLI (dot-sourced by the watcher). |
| `scripts/watch-sop-history.ps1` | The persistent watcher (poll loop + session state machine). |
| `scripts/mark-sop-editorial.ps1` | Mark an SOP's next stamp as an editorial sub-revision. |
| `scripts/install-sop-watcher.ps1` | Optional at-logon autostart (Task Scheduler). |
| `~/.nightingale/sop-history-state.json` | Watcher state (outside the repo; never committed). |
| `~/.nightingale/sop-retirement-log.md` | Durable log of deleted SOPs (outside the repo; the deleted file's own Change History cannot record its own deletion). |

## Notes & limits

- **Obsidian:** the watcher writes to a file you may have open. The debounce means it
  writes only after you pause; Obsidian then reloads the external change. Keep the
  debounce non-trivial (>= a few seconds) to avoid writing mid-keystroke.
- **One row per session, not per save** — a burst of saves collapses into one bump.
  A commit or 5 idle minutes seals the session; the next edit starts a new version.
- **Append-only — the table is never edited destructively.** The watcher only ever
  *adds* rows; it never removes or rewrites a past row (ALCOA: entries supersede but
  never erase). If you add something and then remove it *within the same session*
  (content returns to the sealed baseline), it does **not** silently undo the bump —
  it appends a new row `Reverted the change recorded in vX.Y; content restored to the
  prior baseline.` A genuine deletion of pre-existing content (or of content already
  sealed) likewise gets its own row reading `Edited sections: <name> (content removed).`
- **Descriptions distinguish add vs remove** — a section that grew reads `(content
  added)`, one that shrank `(content removed)`, so a deletion is visible at a glance.
- **Not a substitute for review.** It records the edit; approval and the "why" still
  come from the operator (per SOP-QA-001 change flow) — refine the row as above.
- **Mirroring:** these scripts + this doc are mirrored to `tlosdev/nightingale-gtm`
  like the rest of the GTM pipeline; keep the two in sync.
