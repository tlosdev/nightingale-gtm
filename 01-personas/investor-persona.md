# Investor Persona — Nightingale

> **Status: v0 stub.** This persona is the fundraising-side counterpart to the commercial + academic ICP personas. It seeds the investor-analyzer feedback loop: the agent reads real investor-call transcripts + investor email replies each week and proposes before/after diffs that mature the `**TBD:**` fields below. Treat every unvalidated claim here as a hypothesis until a real investor conversation confirms it. The pitch-deck-updater agent reads this file to keep the deck converging on what this persona actually responds to.

---

## Overview

**Persona Name:** The Early-Stage Health-Tech Investor
**Also Known As:** The Thesis-Fit Check-Writer
**Primary Goal:** Deploy capital into a small number of pre-seed/seed companies that can plausibly return the fund — companies with a credible wedge into a large market, a team that can execute, and early evidence the wedge is real.

Nightingale is a YC S26-applicant clinical-trial data-standardization startup raising at the pre-seed/seed stage. This persona describes the people who decide whether to write a check — and, just as importantly, the screeners who decide whether the partner ever sees the deck.

---

## Investor Profile

| Attribute | Detail |
|---|---|
| **Firm Types** | Pre-seed / seed venture funds; health-tech & life-sciences-focused funds; generalist seed funds with a health vertical; angel investors (often ex-operators or clinicians); accelerators / YC-adjacent scouts; strategic / corporate VC arms (pharma, CRO, health systems). **TBD:** which type actually converts for Nightingale — refine from call data. |
| **Check Size** | Angels $10k–$100k; pre-seed funds $100k–$750k; seed funds $500k–$3M lead. **TBD:** validate against the round Nightingale is actually raising. |
| **Stage Thesis** | Pre-seed / seed. Some are "first money in"; some only come after a lead is set. Knowing which is which changes the ask. **TBD.** |
| **Sector Thesis** | Clinical trials / clinical operations, life-sciences tooling, regulated-data infrastructure, vertical SaaS for healthcare, digital health. Mismatch here is the most common fast "no." |
| **Geography** | US-focused; many seed funds are geography-agnostic. Atlanta / Southeast angel networks and Emory-adjacent capital are a warm-intro surface. **TBD.** |

---

## Decision Roles

Mirroring the commercial persona's three-role structure: a fundraising "buying group" has distinct roles, and engaging only one stalls the raise. Identify each separately.

---

### Role 1: Economic Buyer — Partner / General Partner / Managing Director (writes/approves the check)

| Context | What They Care About |
|---|---|
| Fund lead / GP | Fund-level thesis fit, market size, "can this return the fund," founder conviction, and who else is in the round. They decide. They are also the hardest to reach cold — warm intros dominate. |
| Angel (self-directed) | Personal conviction + founder trust. Faster decision, smaller check, often a useful signal/reference for institutional money. |

**The ROI argument that lands here** is not the product — it is the *market and the wedge*: a credible path from "standardize Phase 2 medical-device trial data" to a large, defensible category. **TBD:** capture the exact framings that earned partner follow-ups.

---

### Role 2: Champion — Principal / Investor / Scout (advocates internally, doesn't sign alone)

| Title | What They Care About |
|---|---|
| Principal / Senior Associate | Finding a deal they can champion to the partnership. They feel the "is this interesting?" pull first and carry it into the Monday partner meeting. |
| Scout / angel-with-network | Early validation + the ability to bring it to a fund. A strong champion here is how a cold lead becomes a warm partner conversation. |

This is often the first real conversation. They can advance the deal but cannot close it without the Partner aligned. **TBD:** what makes this role lean in for Nightingale specifically.

---

### Role 3: Technical / Diligence Gatekeeper — Associate / Analyst / Diligence lead (can stall the deal)

| Title | What They Care About |
|---|---|
| Associate / Analyst | Screening inbound, sanity-checking the market, running first-pass diligence. They decide whether the deck reaches the partner at all. |
| Diligence lead / domain expert | Regulatory risk (FDA pathway), technical defensibility, competitive landscape, traction quality. The first to ask "why won't this break in a regulatory review?" — the same gate the commercial CMO raises. |

If the screen fails, the partner never sees the deck regardless of how warm the intro was. **TBD:** the diligence questions that recur — feed these straight into the deck and FAQ.

---

**Fundraising requirement:** For each target firm, identify all three — Partner (decides), Principal/Champion (advocates), Associate/Gatekeeper (screens). A deck that only satisfies the champion dies in diligence.

---

## Goals & KPIs They Probe

| Priority | What they dig into |
|---|---|
| **Primary** | Market size + wedge credibility — is "Phase 2 decentralized medical-device trials" a beachhead into something fund-returning? |
| **Primary** | Traction signal — design partners, pilots, LOIs, revenue, trial-design-phase engagements. Any proof the problem-unaware buyer will actually pay. |
| **Primary** | Team / founder-market fit — why these founders win this category. |
| **Secondary** | Moat — regulatory credibility (FDA submission standards, active audit), data network effects, switching costs. |
| **Hygiene** | Cap table cleanliness, burn / runway, round structure. Table stakes; rarely the reason for a "yes." |

---

## What Resonates in the Pitch

> The pitch-deck-updater agent maintains this section as the bridge between investor feedback and slide edits. Each line should eventually cite which slide / metric earned engagement.

- **TBD:** which slides earn follow-up questions vs. glazed eyes (timeline-compression / "4–6 weeks → days" framing? the regulatory-moat slide? the market-size build?).
- **TBD:** which traction metric moves the room.
- **TBD:** the one-liner that makes a champion repeat it back.

---

## Objections & Fears

**Voiced Objections (hypotheses — validate from calls):**
1. "This feels too early — come back with more traction."
2. "Clinical trials / regulated health is slow and hard to sell into — what's your wedge?"
3. "Is this a feature, a product, or a company? How big can it get?"
4. "Single market (Phase 2 medical-device) — show me the expansion path."
5. *(from diligence)* "What's the regulatory exposure, and does your output actually hold up in an FDA review?" — **Answer:** Nightingale meets FDA data-submission standards and is undergoing a formal audit. Lead with this in diligence, same as the commercial CMO gate.

**Hidden Fears (rarely said out loud):**
- Founders can build but can't sell into a conservative, problem-unaware buyer.
- The category never materializes — it stays a consulting/services business.
- Regulatory or sales cycles stretch past the next-round runway.

**TBD:** capture the real objections verbatim as they surface; do not over-fit to these guesses.

---

## Disqualifiers — NOT a Good-Fit Investor

- Wrong stage (growth/Series B+ only; or strictly pre-product angel-only when we need a lead).
- Wrong sector thesis (no healthcare/regulated-data/vertical-SaaS appetite).
- Geography or structure constraints that rule Nightingale out mechanically.
- Investors who require enterprise-validated, de-risked metrics Nightingale cannot show yet (same "unproven vendor" disqualifier as the commercial persona, applied to capital).

---

## Messaging Principles (v0 — to be validated)

1. **Lead with the wedge and the market, not the feature** — "we standardize fragmented Phase 2 trial data" is the wedge; the pitch is the category it opens.
2. **Make traction concrete** — name design partners, trial-design-phase engagements, and the regulatory-credibility proof points; vague "interest" reads as no traction.
3. **Pre-empt the regulatory gate** — state FDA-submission-standard compliance + active audit before diligence asks. An audit-in-progress is a credibility signal, not a weakness (mirrors the commercial CMO play).
4. **Warm intros over cold** — the same channel truth as the commercial buyer: peer credibility and trusted referrals break through; cold decks to partners rarely do. (The daily-brief + intro-finder agents are the warm-intro surface.)
5. **Match the ask to the role** — Partner gets market + conviction; Champion gets "a deal you can carry"; Associate gets a clean, diligence-ready story.

---

## Hard Rules — Read Before Using This Persona

1. **This is a v0 stub.** Most fields are hypotheses. The investor-analyzer agent matures them from real call + email evidence; do not treat `**TBD:**` content as established.
2. **Never fabricate traction.** Anything surfaced into the deck or newsletter must be true and operator-approved. The pitch-deck-updater and investor-newsletter agents are propose-only for exactly this reason.
3. **Role ID sources:** Partner / Principal / Associate are identified from call context + email signatures + firm websites — never pattern-guessed.
