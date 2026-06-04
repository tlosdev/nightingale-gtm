# Investor-Newsletter Agent — Usage Guide

The `investor-newsletter` produces Nightingale's biweekly investor update. It summarizes what changed since the last newsletter — HubSpot CRM deltas (traction) + internal-team call transcripts (product/team) — into an investor-persona-optimized update, builds the recipient roster, and queues it for your approval. On approval it creates **one unsent Gmail draft** with every recipient in **BCC**.

It **never sends.** It is the only Nightingale agent permitted to write to Gmail, and only `create_draft` (an unsent draft), and only after you approve.

Agent file: `.claude/agents/investor-newsletter.md`

---

## How it runs

- **Scheduled:** every other Friday at 9am (`Nightingale-Investor-Newsletter-Biweekly`).
- **Manual:** `RUN investor-newsletter` or `compose investor newsletter`.

Compose phase, in one run:

1. Reads `01-personas/investor-persona.md` + `state/cursor.json` (the delta window start = last newsletter).
2. **HubSpot delta (read-only):** deals advanced/closed-won, new logos, new contacts since the cursor → investor-friendly traction beats. Anything potentially sensitive (named prospect, specific $) is flagged `[REVIEW: sensitive]` for you to confirm.
3. **Internal-team transcripts (read-only):** shipped features, milestones, hiring, roadmap beats (paraphrased).
4. **Recipient roster:** built from investor call transcripts (signature emails — verbatim only) + Google Calendar external investor meetings (attendee emails — verbatim only). Deduped. **No pattern-guessed emails, ever.**
5. Writes the newsletter preview + the approval queue.

## Reviewing & approving

Open the UI dashboard (`scripts/start-ui.ps1`) → **Investor Newsletter**. You'll see the subject, the full body, any sensitivity flags, and the recipient table. Then:

- **Approve & create Gmail draft** → the agent creates ONE unsent draft: **To = you**, **BCC = every recipient** (so no investor sees another). Review it in Gmail Drafts and send manually. The newsletter cursor advances to "now" so the next run starts here.
- **Reject** → no draft created; the delta window is preserved so nothing is skipped next run.

Phrase equivalents: `approve newsletter draft from {date}` / `reject newsletter draft from {date}`.

## Outputs

```
~/Desktop/nightingale-signals/investor-newsletter/
├── pending/{date}.json          # the dashboard approval item (subject + body + roster)
├── output/newsletter-{date}.md  # full preview
└── state/{cursor.json,approval-history.jsonl}
```

## Guardrails

- **Draft-only, never sends.** BCC is mandatory; if BCC can't be guaranteed, no draft is created.
- Read-only against HubSpot, Drive, and Google Calendar.
- Sensitivity guard: confidential CRM detail is flagged for your review, never auto-included.
- Cursor advances only on approval (so a reject/abort never silently skips a window).
- Missing a connector degrades gracefully (omit that section + note); missing persona → notice + exit.

See also: `investor-analyzer-usage.md`, `pitch-deck-updater-usage.md`.
