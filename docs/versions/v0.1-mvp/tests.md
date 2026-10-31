# Whodunit v0.1 MVP — Master Test Plan

**Version:** v0.1 MVP

**Status:** Active release-control plan

**Last updated:** 2026-10-30

This plan defines the evidence required to release the 4–12 player MVP. A task
or requirement is not complete merely because its happy path works. The mapped
automated checks and human review must pass in the named environment, and every
release exception must have an owner, expiry date, mitigation, and rollback
condition.

## 1. Quality ownership

| Area | Accountable owner | Required evidence |
|---|---|---|
| Product rules, pacing, and playability | Product / Game Design | Deterministic profile tests plus moderated playtests |
| Database integrity and authorization | Backend | Clean migration replay, pgTAP, concurrency probes |
| Actor privacy and browser security | Security / Backend | Projection snapshots, adversarial HTTP tests, privacy review |
| Story quality and model policy | AI / Product | Fixed-corpus deterministic validation and live-model evaluation |
| Mobile, desktop, and accessibility | Design / QA | Automated audit plus supported-device manual matrix |
| Reliability, latency, and capacity | Backend / Operations | Fault, recovery, load, and cleanup measurements |
| Deployment and incident readiness | Operations | Staging drills, smoke game, rollback evidence |

## 2. Test pyramid and commands

| Layer | Purpose | Command / evidence | Merge or release gate |
|---|---|---|---|
| Static | Formatting, lint, module boundaries, committed-secret scan, types | `npm run check` | Every merge |
| Unit | Contracts, validation, provider mapping, scoring/evaluation, UI states | `npm test` | Every merge |
| Database | Constraints, RLS/RPC authorization, projections, commands, retention | `npm run db:test` | Every merge |
| HTTP integration | Real Next.js, anonymous Auth, cookies, API/RPC boundaries | `npm run test:integration` | Every merge |
| Clean worker | Empty-database migration replay plus database and HTTP suites | `CI=true npm run db:verify` | Every merge |
| Browser E2E | Isolated Game Master/player contexts and responsive interaction | `npm run test:e2e` | Release candidate |
| Security/privacy | Abuse, cross-actor, webhook, cache/header, redaction, deletion | `npm run test:security` | Release candidate |
| Performance | Command/projection/load/cleanup budgets | `npm run test:performance` | Release candidate |
| Story evaluation | Fixed corpus and separately approved live-model candidates | `npm run test:story-evals` | Model/prompt change and release |
| Human | Accessibility/device review, playtests, staging drills, production smoke | Signed checklists | Release only |

The canonical local gates are `npm run check` and
`CI=true npm run db:verify`. CI runs the equivalent `Application checks` and
`Database smoke` jobs on a clean worker.

The HTTP integration suite sends sustained requests through the real Next.js
server for room discovery, player claims, host recovery, story generation, and
game commands. It verifies route-specific per-IP, principal, and room budgets;
the same public response for missing versus unavailable room codes and for used
versus unknown recovery credentials; a non-enumerating 429 envelope; and the
`X-Whodunit-Abuse-Action: turnstile-challenge` escalation signal on abusive
join, claim, and recovery traffic. Database and command suites separately prove
durable replay protection, while unit tests enforce the 64 KiB JSON boundary.

## 3. Environments and data policy

| Environment | Use | Credentials and data |
|---|---|---|
| Unit | Pure deterministic logic and rendered component states | No network and no real secrets |
| Local integration | Docker-backed local Supabase plus loopback Next.js | Generated local keys; synthetic fixtures only |
| CI | Disposable local Supabase and production Next build | No hosted credentials and no `.env.local` |
| Preview | Browser/accessibility review of a candidate | Preview-only Supabase/OpenAI projects and synthetic rooms |
| Staging | Load, provider, recovery, rotation, restore, and rollback drills | Staging-only secrets; no production data |
| Production | Final synthetic smoke and monitoring | Production-only secrets; least privilege |

Production data must never be copied into local, CI, preview, or staging. Test
logs may contain stable fixture UUIDs and content-free correlation IDs, but
never names, descriptions, dossiers, notes, theories, accusations, room codes,
credentials, prompts, provider payloads, or story solutions.

## 4. Deterministic fixtures

| Fixture | Coverage |
|---|---|
| Minimal setup | Dedicated Game Master, editable DRAFT, no player slot |
| Four-player | Supported minimum, 30-minute profile, `1/0/3` factions |
| Twelve-player | Supported maximum, 120-minute profile, `3/2/7` factions |
| Duplicate display names | Two players with the same Unicode display name but distinct internal IDs |
| Aware / unaware | Both murderer-awareness modes and delayed accomplice knowledge |
| Multi-antagonist | Multiple murderers plus accomplices, with no player victim |
| Adversarial Unicode | Long Indian names, combining marks, emoji, and normalized-equivalent text |
| Source privacy | Unique raw phrases that must never be copied or projected |
| Recovery/race | Old/new host, old/new player device, competing claims, duplicate commands |
| Expired rooms | Completed, inactive incomplete, active, and GENERATING rooms at exact boundaries |
| Story corpus | Every party size 4–12, both awareness modes, safety and malformed-output cases |

Factories use explicit UUIDs and timestamps, validate their output through the
same Zod contracts as production, and register cleanup in reverse order. They
must not depend on `Math.random`, wall-clock time, Faker defaults, or shared
module counters.

## 5. Actor and privacy matrix

| Actor | May observe | Must never observe | Primary verification |
|---|---|---|---|
| Visitor with room code | Safe lobby identity/status list | Any private room, player, role, story, or submission state | `0100`, QA-03/09 HTTP tests |
| Pending claimant | Own request state and safe lobby | Any dossier, role, note, theory, evidence, solution, or other claim secret | `0100`, `0110`, QA-03 |
| Active player before reveal | Own dossier, missions, notebook, releases, own submissions | Other private dossiers/drafts, unreleased evidence, solution | `0110`, QA-03/06 |
| Current Game Master after lock | All generated truth, runtime state, and submitted snapshots | Raw descriptions/authorship, credentials, notebook drafts, unsubmitted/final-case drafts | `0110`, QA-03/09 |
| Former Game Master | No current room projection or command authority | Every current Game Master/player view and all recovery data | `0030`, `0100`, QA-02/03 |
| Revoked/replaced player | Safe rejoin/reconnect outcome only | Former player projection and all current private state | `0100`, QA-02/06 |
| Shared reveal player | Published reveal and own score/results | Game Master-only case file and another player's owner-only drafts | `0110`, QA-03/06 |
| Postgame Game Master | Full case file and submitted result history | Raw descriptions/authorship, credentials, owner-only drafts | `0080`, `0110`, QA-03 |
| Service role / Cron | Bounded maintenance commands | Direct browser exposure or unallowlisted operational payloads | `0210`, QA-09 |

## 6. Requirement verification matrix

`traceability.md` is the source mapping from requirement text to task IDs. This
table adds the concrete test owner and release method for every requirement
section.

| Requirement area | Owner | Automated method | Human/release method |
|---|---|---|---|
| §1 coherent mystery and private play | AI / Product | Story validators, fixed corpus, actor projections | 4/12-player playtests |
| §2 player count and dedicated host | Backend | `0020`, `0030`, `0100`, `0140`, E2E contexts | Host usability review |
| §2 duration and faction configuration | Product / Backend | `0120`, setup integration, story corpus | Pacing playtests |
| §2 discovery, claim, reconnect, recovery | Backend / Security | `0100`, `0150`, `0160`, race suite, E2E | Recovery staging drill |
| §2 complete description matrix/privacy | Backend / Security | `0140`, snapshot denylist, source-copy validator | Privacy review |
| §3 factions, awareness, NPC victim | AI / Product | Story validator/corpus and projection snapshots | Playtest comprehension |
| §4 immutable coherent storyline | AI / Backend | `0040`, `0090`, `0170`, rollback/fault tests | Live-model approval |
| §4 cultural/sensitive-trait safety | AI / Product | Deterministic safety diagnostics and fixed corpus | Indian-context playtests |
| §5 host-controlled rounds | Backend / Product | `0180`, command integration, E2E | Host pacing review |
| §6 private dossiers and reveal timing | Security / Backend | `0110`, projection allowlists | Cross-device privacy check |
| §7 evidence graph and solvability | AI / Backend | Story graph validator, `0040`, `0180` | Playtest solvability |
| §8 missions and consequences | Product / Backend | Validator, all-success/all-failure command tests | Mission-achievability review |
| §9 Game Master controls | Backend / QA | Full GM snapshot and multi-actor E2E | Desktop GM review |
| §9 notebook/theory privacy | Security / Backend | `0070`, `0110`, actor snapshots | Player usability review |
| §9 interventions | AI / Backend | Provider, canonical-candidate, fallback/approval tests | Usefulness review |
| §10 Early Verdict/final accusations | Backend / Product | `0200`, E2E, scoring fixtures | Endgame comprehension |
| §10 outcomes, scores, awards | Product / Backend | `0130`, `0200`, golden scoring cases | Product sign-off |
| §11 reveal and case file | Backend / Design | `0080`, `0110`, E2E snapshots | Cinematic/usability review |
| §11 30-day expiration | Backend / Operations | `0210`, exact-boundary and residue tests | Staging cleanup drill |
| §12 mobile/desktop screens | Design / QA | Browser E2E, axe, responsive assertions | Supported-device matrix |
| §13 architecture and deployment | Platform / Operations | CI, env isolation, build, smoke tests | Staging and production drills |
| §13 provider/repair/escalation | AI / Backend | Provider fault suite, reconciliation, model eval | Separate model approval |
| §13 security/privacy/Realtime | Security / Backend | RLS, HTTP abuse, webhook, headers/cache, signal tests | Security review |
| §14 complete playable MVP | Product / QA | 4/12-player synthetic E2E | Moderated playtests and go/no-go |

## 7. High-risk invariant gates

| Invariant | Required proof | Owner |
|---|---|---|
| Game Master can never be a player | Cross-table constraint/RPC tests plus concurrent recovery/claim probes | Backend |
| Room code is discovery-only | Unauthenticated and wrong-actor projection/API denial | Security |
| Exactly one immutable story locks | Concurrent worker, repair, rollback, duplicate webhook, and mutation denial | AI / Backend |
| One player has one current device | Competing claim/reconnect/revoke races and old-session denial | Backend |
| Wrong actors see no private data | Allowlisted snapshots at every lifecycle state | Security |
| Game Master gets full truth but not source/drafts | GM golden snapshot and denylist scan | Security / Product |
| Submitted/finalized state is immutable | Database mutation denial and idempotent replay | Backend |
| Canonical effects happen once | Duplicate/concurrent command and intervention approval tests | Backend |
| LLM cannot authorize or score | Provider-output adversarial tests and deterministic database rules | Security / Backend |
| Expiry removes all room residue | Cascade inventory before/after cleanup plus active-room control | Operations |
| Logs contain no private content | Metadata allowlist, secret scan, error/log capture tests | Security |

## 8. Performance and capacity method

Measure at least three warmed runs and report p50/p95/max without private
payloads. Release targets are:

- story generation p50 ≤ 45 s, p95 ≤ 90 s, visible terminal recovery by 120 s;
- intervention p50 ≤ 2.5 s, p95 ≤ 5 s, fallback starts by 6 s;
- ordinary command p95 ≤ 750 ms;
- 12-player projection p95 ≤ 500 ms;
- 10 concurrent active rooms / 120 connected players;
- 25-room cleanup batches complete without lock starvation.

Local synthetic measurements establish regressions. Staging provider and
regional measurements are release evidence; local model placeholders cannot
approve production latency or cost.

The clean-worker integration suite includes a dependency-free local regression
smoke with 120 concurrent warmed HTTP reads and ten concurrently created rooms.
It enforces the ordinary local read/command budgets and catches gross
serialization, pool, or route regressions. This is intentionally not the
release sign-off: QA-07 still requires three warmed staging runs with real
12-player projections, Realtime fan-out, database lock contention, cleanup
batches, and configured model latency/cost.

## 9. Accessibility and device matrix

Automated checks cover axe violations, semantic labels, focusable controls,
touch-target CSS, reduced motion, and 360 px horizontal overflow. Manual
release coverage is:

| Surface | Required browsers/devices |
|---|---|
| Player | Latest two major iOS Safari and Android Chrome releases |
| Game Master | Latest two Chrome, Safari, and Edge releases on desktop |
| All | Keyboard-only, VoiceOver or TalkBack, 200% zoom, reduced motion, 360 × 640 viewport, long Unicode names |

No critical accessibility issue may ship. A serious issue may ship only with a
time-bounded approved exception that preserves the core game path.

## 10. Defect severity and release policy

| Severity | Examples | Policy |
|---|---|---|
| Critical | Cross-actor data exposure, story/credential leak, authorization bypass, data corruption, unusable core journey | Stop release; fix and rerun all affected gates |
| High | Wrong score/faction outcome, mutable canonical truth, unrecoverable room, webhook forgery, completed-data residue | Stop release unless executive risk acceptance names an immediate rollback |
| Medium | Recoverable feature failure, serious pacing/accessibility issue, degraded supported browser | Owner, mitigation, expiry, and focused regression required |
| Low | Cosmetic or copy issue with no task/privacy/accessibility impact | May defer with backlog reference |

Any flaky release-blocking check is a failure, not a pass. Quarantine requires
a named owner, root-cause task, expiry within seven days, and equivalent manual
evidence until repaired.

## 11. Release evidence checklist

- `npm run check` and `CI=true npm run db:verify` exit 0 at the release commit.
- QA-02 through QA-10 evidence is linked from the release checklist.
- Two moderated 4-player parties and one 12-player stress party complete.
- Supported-browser/accessibility matrix has no critical finding.
- Staging recovery, rotation, provider-outage, cleanup, restore, and rollback
  drills meet their targets.
- Production environment isolation, backups, alerts, budgets, webhook, Cron,
  DNS/TLS, and required GitHub checks are confirmed by a human operator.
- A synthetic production smoke reaches create → claim → generation → gameplay
  → fallback → reveal while rollback remains available.

## 12. Automated multi-actor journey evidence

`tests/e2e/multi-actor-journeys.spec.ts` runs two production-server journeys
through public HTTP and browser surfaces only:

- a 4-player, 30-minute, murderer-aware room with duplicate names, initial
  claims, player-device reconnect, host recovery, private-description matrix,
  generation/lock, early suspicion, Early Verdict, all final cases, scoring,
  reveal, completion, case file, and exact 30-day expiry;
- a 12-player, 120-minute, murderer-unaware room with duplicate and Unicode
  Indian names, three murderers, two accomplices, actor-separated dossiers,
  hidden murderer faction, the same endgame, and completed-room expiry.

Every Game Master and player uses a separate Playwright browser context and
anonymous session. The suite asserts that replaced principals lose access,
raw descriptions never enter projections, players receive no canonical
solution before reveal, the Game Master receives the full locked truth, and
the rendered Game Master/player surfaces hydrate without browser errors. Story
generation traverses the real worker and atomic database lock using a strict
loopback Responses API substitute; no direct database fixture mutation is used
by the journeys.
