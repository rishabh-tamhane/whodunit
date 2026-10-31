# Whodunit v0.1 MVP — Requirement Traceability

**Status:** Living release-control matrix

**Last updated:** 2026-10-30

This matrix maps every committed requirement area and cross-cutting invariant to implementation and verification ownership. A requirement change must update this file, `tasks.md`, and the relevant test plan in the same change.

## Requirement Sections

| Requirement source | Implementation tasks | Verification ownership |
|---|---|---|
| §1 Product Overview: one coherent LLM-authored mystery, private dossiers, host control | GEN-01–GEN-09, GM-01, APP-03 | GEN-10, QA-04, QA-06, PLAY-01/02 |
| §2 Player count and dedicated non-playing Game Master | DB-02/03/10/11, IDN-02/04/06/08/10 | `0020`, `0030`, `0100`, `0110`, `0140`, QA-02/03 |
| §2 Duration and faction configuration | DB-12, IDN-04/05 | `0120`, `0140`, QA-06 |
| §2 Room-code discovery and player claiming | DB-10, IDN-01/06/07 | `0100`, QA-02, QA-06 |
| §2 Reconnect, stable player identity, and device replacement | DB-02/03, IDN-08/09, GAM-06 | `0020`, `0030`, QA-02, QA-06 |
| §2 Host recovery with permanent host/player separation | DB-03, IDN-02/10/11 | `0030`, QA-02, QA-06, LAUNCH-01 |
| §2 Raw description privacy and complete matrix | M0-02, IDN-12/13/14, GEN-03/09 | `0140`, QA-03/04/09 |
| §3 Factions and configurable murderer awareness | GEN-01/02/08, PLY-01 | QA-04, QA-06, QA-10 |
| §3 Fictional NPC victim and no player elimination | GEN-01/02, GAM-02 | QA-04, QA-05, PLAY-01/02 |
| §4 One canonical storyline and cross-player coherence | GEN-01–GEN-07 | `0040`, `0090`, GEN-10, QA-04/10 |
| §4 Cultural and sensitive-trait safety | GEN-02/06/10, UX-02 | QA-04/08/09/10, PLAY-01/02 |
| §5 Host-controlled rounds and pacing | DB-12, GAM-01/02, GM-02 | `0120`, QA-05/06 |
| §6 Private roles, secrets, alibis, and awareness timing | DB-04/11, GEN-01/02/08, PLY-01 | `0040`, `0110`, QA-03/04/06 |
| §7 Evidence graph, guaranteed solvability, and audience release | DB-04/06/11, GEN-01/02, GAM-04, PLY-02 | `0040`, `0060`, `0110`, QA-04/05/06 |
| §8 Achievable missions, confirmation, and consequences | DB-04/06, GEN-01/02, GAM-03/04, PLY-07 | `0040`, `0060`, QA-04/05/06 |
| §9 Full Game Master dashboard and sole game control | DB-11, GM-01/02/03/04/05 | `0110`, QA-03/05/06 |
| §9 Notebook and submitted-theory privacy boundary | DB-07/11, PLY-03/04/05/06 | `0070`, `0110`, QA-03/05/06 |
| §9 Context-aware interventions with approval and fallback | INT-01–INT-05, GM-03 | QA-05/06/10 |
| §10 Early Verdict and final-case transition | END-01/02/03, GM-04, PLY-08 | QA-05/06 |
| §10 Deterministic faction outcomes, scores, and awards | M0-04/05, DB-13, END-03/04 | `0130`, QA-05/06 |
| §11 Shared cinematic reveal | DB-11, END-05, PLY-09 | `0110`, QA-03/05/06 |
| §11 Game Master-only complete case file | DB-08/11, END-06, GM-05 | `0080`, `0110`, QA-03/05/06 |
| §11 30-day completed-room access and deletion | END-07, REL-05 | QA-06/09, LAUNCH-01 |
| §12 Required mobile and desktop screens | UX-01/02, UI-01, IDN/GM/PLY feature UI tasks, APP-01/03 | QA-06/08, PLAY-01/02 |
| §13 Next.js/Supabase/Vercel/Cloudflare architecture | FND-01–FND-08, DB-01–DB-14, OPS-04 | CI, QA-01/02/07/09, LAUNCH-01/02 |
| §13 OpenAI provider, repair, escalation, and immutable lock | GEN-04–GEN-07, SEC-04 | QA-04/10, LAUNCH-01 |
| §13 Security, privacy, and Realtime requirements | DB-09–DB-11, SEC-01–SEC-04, REL-02/03 | `0090`–`0110`, QA-02/03/09 |
| §14 Complete playable MVP principles | APP-03, all feature milestones | QA-06, PLAY-01/02, LAUNCH-02/03 |

## Cross-Cutting Decision Register

| Decision in `product-decisions.md` | Implementation tasks | Verification |
|---|---|---|
| Complete directed description matrix with explicit decline | IDN-12/13, GEN-03 | `0140`, QA-03/04 |
| Claim/reject/revoke/reconnect state table | IDN-06/08/09, GAM-06 | QA-02/06 |
| `score-v1`, faction threshold, awards, and missing-submitter behavior | DB-13, END-03/04 | `0130`, QA-05/06 |
| Per-state incomplete-room retention | REL-01/05/06, END-07 | QA-07/09, LAUNCH-01 |
| English-only UI with Unicode-safe culturally inclusive content | UX-02, GEN-02/10 | QA-08/10, PLAY-01/02 |
| Browser, region, latency, cost, and capacity targets | FND-08, INT-04, OPS-03/04 | QA-07/08, LAUNCH-01/02 |

## Non-Negotiable Invariants

| Invariant | Database evidence | Release evidence |
|---|---|---|
| Game Master is never a player | `0030`, `0100`, `0110`, `0140` | QA-02/03/06 |
| Room code never authorizes private data | `0100`, `0110` | QA-03/09 |
| One atomic immutable story per room | `0040`, `0090` | QA-04/09 |
| Players cannot read another pre-reveal private view | `0110` | QA-03/06/09 |
| Game Master receives full generated truth after lock but no owner-only drafts/raw descriptions | `0110` | QA-03/06/09 |
| Submitted theories/accusations and finalized results are immutable | `0070`, `0080`, `0090` | QA-02/05 |
| Released canonical effects happen at most once | `0060`, `0090` | QA-05 |
| LLM never determines authorization, lifecycle, scoring, or canonical mutation | `0090`, `0130` | QA-04/05/09/10 |
| Completed data is deleted after 30 days | REL-05 | QA-09, LAUNCH-01 |

## Maintenance Rule

The global definition of done requires every implementation change to name its task ID in the pull request, add or update the mapped automated verification, and update this matrix when it introduces, removes, or changes requirement coverage. A release cannot pass LAUNCH-02 with an uncovered requirement, an unowned verification row, or a checked task whose mapped gate is failing.
