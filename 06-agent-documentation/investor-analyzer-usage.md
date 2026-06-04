# Investor-Analyzer Agent — Usage Guide

The `investor-analyzer` is the **fundraising-side feedback loop** of Nightingale — the investor counterpart to `feedback-analyzer`. It reads investor call transcripts + inbound investor email replies, extracts structured insights, and produces a refinement report with **proposed diffs** to `01-personas/investor-persona.md` (and any optional company-narrative / pitch-deck-outline files present). At the end of a full run it **auto-chains `pitch-deck-updater`**.

It is **propose-only**. It never edits source files. You decide which diffs to apply.

Agent file: `.claude/agents/investor-analyzer.md`

---

## What it does

End-to-end, in one run:

1. Reads `01-personas/investor-persona.md` + the `_processed.md` / `_patterns.md` history under `~/Desktop/nightingale-signals/investor-insights/state/`.
2. Searches the shared Drive folder `/curanostics/nightingale/call transcripts` and the operator's Gmail inbox (last 7 days) for new sources.
3. **Classifies each source** as investor / prospect / internal and processes **only investor** sources (prospect calls belong to feedback-analyzer; internal calls to investor-newsletter).
4. Extracts investor-specific dimensions: thesis fit & objections, what resonated, traction questions, valuation/terms language, role reality (Partner/Principal/Associate), asks for materials, pass reasons.
5. Aggregates with the weighted-confidence model (identical to feedback-analyzer):
   - Call **1.0**; investor email — pitch quote-back / explicit pass / role-conflict **0.5**; generic investor email **0.3** (non-stacking, max 0.5/email).
   - **High** ≥ 3.0 · **Medium** ≥ 2.0 · **Low** ≥ 1.0 (no diff) · **Sub-threshold** < 1.0 (patterns log only).
6. Generates literal before/after diffs against the investor persona (and optional targets), each citing verbatim investor quotes.
7. Writes `~/Desktop/nightingale-signals/investor-insights/output/refinement-{YYYY-MM-DD}.md`; appends to `_patterns.md` / `_processed.md`.
8. **Chains pitch-deck-updater** so the deck re-converges on the fresh signal.

---

## How to invoke

In a Claude Code session inside `C:\Users\ben\nightingale`:

- `RUN investor-analyzer` — full run (the weekly Monday-8am cron phrase; chains the deck updater).
- `ANALYZE investor feedback` — full run.
- `ANALYZE investor calls` — calls-only run.
- `REFINE investor-persona` / `WEEKLY investor insights` — full-run aliases.

## Applying diffs

The agent never auto-applies. Review the report and reply:

- `apply diffs {N, N, N} from refinement-{date}` — apply only the persona diffs you approve.

## Requirements

- Google Drive MCP authorized (investor transcripts) and/or Gmail MCP authorized (investor replies). Missing either → that source is skipped with a note; missing both → a single `MCPS_NOT_AUTHORIZED` notice.
- `01-personas/investor-persona.md` must exist (ships as a v0 stub) — this agent is the primary path that matures it.

## Outputs

```
~/Desktop/nightingale-signals/investor-insights/
├── output/refinement-{date}.md          # the report you review
└── state/{_processed.md,_patterns.md,operator-identity.json}
```

Outputs live on the Desktop, never in the repo — the report quotes investors verbatim.

See also: `pitch-deck-updater-usage.md` (the chained deck agent) and `investor-newsletter-usage.md`.
