# Ideal Client Persona — Nightingale (Academic / Research Institution)

> **Status: v0 stub.** Drafted alongside the academic signal-watcher agent. Title sets and messaging language will be refined as the first weekly sweeps surface real prospects and discovery calls produce direct quotes. Sections marked **TBD** are placeholders Ben will validate from real call data.

---

## Overview

**Persona Name:** The Academic Clinical Research Stakeholder
**Primary Goal:** Run human-subjects studies that produce publishable, regulator-defensible, IRB-compliant data — without the institution's IT/security review or data harmonization burden becoming a critical-path blocker.

This persona covers buyers at **research hospitals and academic medical centers** (Emory, Duke, UNC, Vanderbilt, Georgia Tech, Augusta U, etc.) running clinical studies. The studies can be **investigator-initiated (IIT)**, **industry-sponsored with the academic center as a site**, or **multi-site cooperative-group / academic consortium** trials. Nightingale is in active conversations to participate in all three types.

This is a **distinct ICP** from the commercial persona (`commercial-persona.md`). The buyer map, motivations, gatekeepers, and decision cycle differ enough that the two require separate outreach and qualification.

---

## Organization Profile

| Attribute | Detail |
|---|---|
| **Org Types** | Academic medical centers, research hospitals, university research arms, NCI cooperative groups, university spinouts (when the academic is the lead) |
| **Study Focus** | Human-subjects studies — IIT, industry-sponsored at site, or multi-site cooperative |
| **Org Size** | Not a 10–200 employee filter; institutional. Filter on study volume and presence of an active Office of Clinical Research / Clinical Research Unit |
| **Geography** | US only |

---

## Buyer Profile

Three distinct roles. Same multi-thread requirement as the commercial persona — engaging only the PI will stall the deal because PIs do not control institutional purchasing or IT/security sign-off.

---

### Role 1: Champion — Principal Investigator (PI)

| Title | What they care about |
|---|---|
| Principal Investigator (PI) | Their study runs on time, the data is publishable, and grant deliverables are met. The PI is the most pain-aware role — they personally feel the data reconciliation and harmonization burden across sites. |
| Co-PI / Co-Investigator | Same frame, secondary advocate. |
| Sub-Investigator (multi-PI trials) | Operational visibility into the trial; useful as an internal advocate. |

PIs are surfaced **directly from the signal sources** — ClinicalTrials.gov returns the PI name on each NCT record, and NIH RePORTER returns the PI on each grant award. No Apollo lookup is needed to identify the champion.

The PI's pain is concrete and frequent: **multi-site data harmonization for publication and grant close-out**. Quote what they say in their grant narratives — that is the language to mirror back.

---

### Role 2: Economic Buyer — Department / Research Leadership

The PI does not sign contracts. Institutional research leadership does. Titles to look for (Apollo + WebSearch against the institution name):

| Title | What they care about |
|---|---|
| Chair, Department of {X} / Department Chair | Departmental research output, faculty retention, grant overhead recovery. |
| Vice Chair for Research / Vice Chair, Research | Research portfolio across the department; resource allocation across active PIs. |
| Director, Clinical Research Unit (CRU) | Operational throughput of the institution's clinical research infrastructure. |
| Director, Office of Clinical Research / Office of Research Administration | Compliance posture across all institutional studies; institutional risk. |
| Director, Clinical Trials Office | Day-to-day operations of multi-trial portfolio. |
| Director, Translational Research | Cross-disciplinary research programs, bench-to-bedside data flow. |
| Associate Dean for Clinical Research / Senior Associate Dean, Research | Dean-level research strategy and budget. |
| Chief Research Officer (CRO at larger AMCs) | Enterprise research strategy. |
| Director, {Center Name} Cancer Center (and analogous disease-center directors) | Disease-specific institutional research; trial pipeline within the center. |

**TBD:** Which specific title(s) actually hold contract-signing authority at Emory and Duke — the academic signal-watcher surfaces every match against this set, and Ben filters by what closes first. Tighten the list once 2–3 deals reveal the real decision-maker title.

---

### Role 3: Technical Gatekeeper — IT, Security, Privacy

Distinct from the commercial CMO/Regulatory frame. At academic centers, the gatekeeper is the institutional **IT/Security/Privacy** function performing technical and security audits before any new data-handling tool can touch protected health information.

| Title | What they care about |
|---|---|
| Chief Information Security Officer (CISO) | Institutional security posture, vendor risk management framework. |
| Director, Information Security / Director, IT Security | Vendor security review and assessment. |
| Director, Health Information Security | Specifically HIPAA-protected data flows. |
| Director, Research Computing / Director, Research IT | Research-data infrastructure; integration with institutional systems. |
| HIPAA Security Officer / HIPAA Privacy Officer | HIPAA compliance and breach risk. |
| Chief Privacy Officer / Privacy Officer | Institutional privacy posture. |
| Information Security Officer | Vendor security review. |

**TBD:** Whether IT/Security at an academic center sits inside the IRB workflow or runs as a parallel approval gate. Discovery-call data will clarify; until then, treat as a parallel gate that must be cleared.

---

## Goals & KPIs

| Priority | Metric |
|---|---|
| **Primary (PI)** | Time to publishable data; grant deliverables on time |
| **Primary (Buyer)** | Trial throughput across the institution; cost-per-trial; compliance posture |
| **Primary (IT/Security)** | Zero data-handling incidents; vendor risk profile; HIPAA compliance |
| **Hygiene** | IRB approval timelines; institutional reputation in cooperative groups |

---

## Awareness & Trigger

Most PIs are **pain-aware** (unlike the commercial buyer who is problem-unaware): they know reconciling multi-site data is slow and expensive. They are not necessarily **solution-aware** — academic norms treat the reconciliation burden as "how it is."

**Entry signals (matched by the academic signal-watcher):**
- New NIH grant award (R01, U01, R21) — funded study about to begin.
- New SBIR/STTR award — academic spinout with commercialization timeline.
- New ClinicalTrials.gov registration with university as Lead Sponsor or Facility.
- University press / news mentioning Phase 2 launch or NIH grant.

**TBD:** Whether the "design phase" window framing from the commercial persona (must engage before protocol approval) applies as strictly here, or whether IIT studies have more flexible entry points mid-recruitment.

---

## Disqualifiers — NOT a Good Fit

- Non-US institution.
- Non-human-subjects research (animal-only, pre-clinical, bench science).
- Institutions without an active Office of Clinical Research / Clinical Research Unit (no buyer role to engage).
- Industry-sponsored trials where the academic is a site but the sponsor's central data pipeline is locked (no design-phase entry for Nightingale).

---

## Messaging Principles (v0 — to be validated)

These mirror the commercial persona's conservative register but reframe the value props:

1. **Lead with the PI's grant or publication outcome, not the product.** "Faster multi-site data harmonization → cleaner data for publication and grant close-out" beats any tool description.
2. **Acknowledge institutional review.** Mention IRB readiness, HIPAA compliance, and that the tool is built to clear institutional IT/security review.
3. **Conservative vocabulary.** Same register as commercial: "validated," "reliable," "audit-ready" — not "innovative," "AI-powered," or "cutting-edge."
4. **Cite peer institutions when available.** Academic credibility runs on peer-institution reference more than on industry case studies.
5. **TBD:** Whether the commercial persona's "FDA audit underway" credibility line lands the same way with an academic IT/security reviewer. Likely: replace with HIPAA / SOC 2 posture statement once those exist.

---

## Hard Rules — Read Before Outreach

1. This persona is **v0 / stub**. Do not generate cold outreach using this file until Ben validates the title set and messaging from at least 2 discovery calls.
2. The signal-watcher academic agent **does not generate outreach in v1** — it stops at the qualified-list. Outreach generation against this persona is explicitly out of scope until the persona is validated.
3. PI identity comes free from NIH RePORTER and ClinicalTrials.gov. Buyer + Tech Gatekeeper identity requires Apollo or WebSearch lookup against the institution and uses the title list above as a broad regex (every match surfaces; Ben filters).
