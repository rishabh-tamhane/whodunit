# Whodunit v0.1 MVP — Product Decisions

**Status:** Approved implementation contract

**Last updated:** 2026-10-30

This document closes the product decisions that affect database constraints, state transitions, readiness, retention, copy, and release gates. Requirements remain the product source of truth; this file provides the exact operational rules referenced by implementation tasks.

## 1. Description Completeness

Every player receives one prompt for every other configured player. For `n` players, the room therefore has `n × (n - 1)` directed description responses.

Each response must reach exactly one terminal state:

- **SUBMITTED:** 1–500 characters of private description text.
- **DECLINED:** the author explicitly chooses “Prefer not to answer.” No reason is requested or stored.

Skipping does not remove or hide a prompt. An unanswered prompt remains **PENDING** and blocks generation. The Game Master sees only per-player and aggregate completion counts, never text, decline targets, or authorship.

A room is generation-ready only when all of these are true in one database snapshot:

1. The room is in `LOBBY` with 4–12 configured players.
2. Duration, faction counts, murderer-awareness mode, and immutable profile versions are valid.
3. Every player slot has one ACTIVE membership.
4. Every player has acknowledged fictional use and sensitive-input guidance.
5. The Game Master has acknowledged host guidance and confirmed room consent.
6. Every directed other-player prompt is `SUBMITTED` or `DECLINED`.
7. No story is locked and no generation job is active.

Examples:

- A 4-player room requires 12 terminal responses. Eleven submitted responses plus one explicit decline is complete; eleven submitted plus one unanswered prompt is not.
- A 12-player room requires 132 terminal responses. All 132 must be submitted or explicitly declined. The calculation is fixed and does not change because names are duplicated or a device reconnects.

## 2. Claim, Revocation, and Replacement States

| Room state | Initial claim request | Reject pending request | Revoke ACTIVE binding | Reconnect request/approval |
|---|---|---|---|---|
| DRAFT | Allowed | Allowed | Allowed | Allowed |
| LOBBY | Allowed | Allowed | Allowed | Allowed |
| GENERATING | Denied | Allowed | Allowed | Allowed |
| READY_TO_START | Denied | Allowed | Allowed | Allowed |
| IN_PROGRESS | Denied | Allowed | Allowed | Allowed |
| FINAL_ACCUSATIONS | Denied | Allowed | Allowed | Allowed |
| REVEAL | Denied | Allowed | Allowed | Allowed |
| COMPLETED | Denied | Allowed | Allowed | Allowed until room expiry |

Additional rules:

- An initial claim is valid only for an unoccupied player slot. An occupied slot uses `RECONNECT` and references its current ACTIVE membership.
- Revocation removes device authority, not the stable player identity or progress. The slot becomes reconnectable, not a new character.
- The dedicated current or former Game Master can never create any claim or membership in the same room.
- Multiple pending requests may race. Approval locks the room first and then the player slot/current membership. The first valid approval wins, revokes the replaced ACTIVE membership when applicable, and rejects all conflicting pending requests for that slot and requester.
- State and membership eligibility are rechecked after locks are acquired. A request that was valid when displayed but is stale at commit returns a conflict without partial changes.
- Rejection never revokes an unrelated ACTIVE binding. Direct revocation and replacement approval are separate commands with separate audit events.
- Completed-room reconnect exists only to restore authorized 30-day postgame access; no new player identity can join after `LOBBY`.

## 3. Incomplete-Room Retention

Only successful authenticated mutations update `last_activity_at`; page views, presence heartbeats, and failed requests do not keep a room indefinitely.

| State | Recovery behavior | Inactivity deletion | Warning |
|---|---|---:|---|
| DRAFT | Resume setup | 7 days | Game Master at 6 days |
| LOBBY | Resume claims/descriptions | 7 days | Game Master and active players at 6 days |
| GENERATING | A job with no heartbeat for 15 minutes is reconciled: resume a durable phase or fail safely back to LOBBY with no story | Never delete while actively generating; recovered LOBBY uses its 7-day clock | Generation status after 10 minutes |
| READY_TO_START | Resume from the locked story | 30 days | Game Master and active players at 27 and 29 days |
| IN_PROGRESS | Resume current round from materialized state/event history | 30 days | Game Master and active players at 27 and 29 days |
| FINAL_ACCUSATIONS | Resume draft/submission intake | 30 days | Game Master and active players at 27 and 29 days |
| REVEAL | Resume shared reveal/case-file finalization | 30 days | Game Master and active players at 27 and 29 days |
| COMPLETED | Read-only postgame access and reconnect | Exactly 30 days after `completed_at` | Game Master and active players at 27 and 29 days after completion |

Deletion is a room-first audited cascade in bounded batches. It removes all room-scoped data, auth-independent secrets, generated content, events, notes, submissions, results, and case files. Aggregate deletion metrics contain no story or player content.

## 4. Language Policy

The v0.1 interface, validation copy, transactional email-free recovery copy, generated mystery, and AI interventions are English-only. There is no Hindi copy layer in the MVP.

All identity and free-text paths remain Unicode-safe. Names are preserved exactly as entered and are never anglicized. Generated English fiction must support culturally inclusive Indian names and contexts without stereotypes or sensitive-trait crime motives. Unsupported browser-language preferences fall back to English without changing user-entered content.

Product owns interface and safety copy. Engineering owns Unicode correctness and the English fallback. Story evaluation owns cultural-quality gates.

## 5. Release and Operating Targets

| Target | MVP gate | Owner |
|---|---|---|
| Mobile browsers | Latest two major versions of iOS Safari and Android Chrome | QA |
| Desktop browsers | Latest two major versions of Chrome, Safari, and Edge | QA |
| Minimum viewport | 360 × 640 CSS pixels with no horizontal page scroll | Design/QA |
| Accessibility | WCAG 2.2 AA for contrast, focus, labels, keyboard flow, reduced motion, and 44 px touch targets | Design/QA |
| Supabase primary region | Mumbai `ap-south-1` | Infrastructure |
| Vercel Function region | Mumbai `bom1`, colocated with the database | Infrastructure |
| Story generation | p50 ≤ 45 s, p95 ≤ 90 s, hard visible failure/recovery by 120 s | AI/Backend |
| Live intervention | p50 ≤ 2.5 s, p95 ≤ 5 s, deterministic fallback begins at 6 s | AI/Backend |
| Ordinary command API | p95 ≤ 750 ms excluding model calls | Backend |
| Projection API | p95 ≤ 500 ms for 12-player active rooms | Backend |
| Initial capacity | 10 concurrent active rooms / 120 connected players | Infrastructure |
| AI monthly spend | Warning at US$50; stop new AI generation/interventions at US$75 while deterministic gameplay remains usable | Product/Operations |
| Per-room AI spend | Warning at US$2; hard cap at US$3 | Product/Operations |

[Supabase lists Mumbai as `ap-south-1`](https://supabase.com/docs/guides/platform/regions), and [Vercel lists Mumbai as `bom1`](https://vercel.com/docs/regions). Static assets remain CDN-distributed; stateful Functions run beside the primary database.

Release gates use representative 4-player and 12-player fixtures. A target miss blocks production unless the owner records a time-bounded exception and rollback condition in the release checklist.
