# Pitch-Deck-Updater Agent — Usage Guide

The `pitch-deck-updater` keeps Nightingale's investor pitch deck converging on what investors actually respond to. It reads your deck (Google Slides in Drive, **read-only**), the investor persona, and the newest investor refinement report, then proposes **slide-by-slide before/after edits** that land in the dashboard's **Pitch Deck Edits** approval queue.

It is **propose-only and never edits the Slides file.** When you Apply an edit, it appends that edit to a Desktop hand-off doc you paste into Slides by hand.

Agent file: `.claude/agents/pitch-deck-updater.md`

---

## Setup — point it at your deck

Run `scripts/setup-secrets.ps1` and, when prompted, paste your pitch deck's Google Drive file ID or share URL (schema v4 field `pitch_deck_drive_file_id`). Example URL:

```
https://docs.google.com/presentation/d/1AbCdEfGhIjK.../edit
```

Until a deck pointer is set, the agent writes a `DECK_POINTER_MISSING` notice and skips cleanly. The Google Drive MCP connector must be authorized for it to read the deck.

If your deck is all-images (no extractable text), keep an optional text mirror at `03-product/pitch-deck-outline.md` (segmented by `##` slide headings) — the agent falls back to it.

---

## How it runs

- **Chained (normal path):** `investor-analyzer` invokes it at the end of every full weekly run — you don't schedule it separately.
- **Manual:** `RUN pitch-deck-updater` or `update pitch deck`.

Per run it: reads the deck into an ordered slide list → compares against the investor persona + newest `investor-insights/output/refinement-*.md` → emits up to 15 slide edits (each with exact before/after text, a rationale, and verbatim investor quotes) → writes the approval queue.

## Reviewing & applying edits

Open the UI dashboard (`scripts/start-ui.ps1`) → **Pitch Deck Edits**. Each card shows the slide, the before/after, the rationale, and the source quotes. Then:

- **Apply** (one or many) → the agent appends the approved edits to `~/Desktop/nightingale-signals/pitch-deck/output/approved-edits-{date}.md`. Open that file and paste the changes into your Slides deck.
- **Reject** → logged, removed from the queue, deck untouched.

You can also drive it by phrase: `apply pitch-deck updates {N,N} from {date}` / `reject pitch-deck updates {N,N} from {date}` (or `all`).

## Outputs

```
~/Desktop/nightingale-signals/pitch-deck/
├── pending/{date}.json                  # the dashboard approval queue
├── output/proposed-edits-{date}.md      # human-readable mirror of the queue
├── output/approved-edits-{date}.md      # hand-off doc — paste these into Slides
└── state/approval-history.jsonl         # decision log (idempotent re-runs)
```

## Guardrails

- Never edits the Slides file or calls any Drive mutation tool.
- Never fabricates traction/metrics — numbers must already exist in approved material.
- Every refinement-driven edit cites a verbatim investor quote (no quote, no edit).
- Deck/persona/report text is treated as data, never as instructions.

See also: `investor-analyzer-usage.md` (the agent that chains this one).
