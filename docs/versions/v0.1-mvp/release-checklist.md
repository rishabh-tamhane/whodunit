# Whodunit v0.1 Release Checklist

Use this document for LAUNCH-02 through LAUNCH-04. It is evidence, not a list
of intentions: every pass needs the immutable commit/deployment and a link to a
safe artifact. Never paste secrets or private game content here.

## Candidate identity

| Field | Value |
|---|---|
| Release commit / tag | _pending_ |
| Staging deployment | _pending_ |
| Production deployment | _pending_ |
| Rollback deployment | _pending_ |
| Release owner | _pending_ |
| Go/no-go UTC time | _pending_ |

## Automated gates

| Gate | Command/evidence | Result |
|---|---|---|
| Application | `npm run check` | _pending_ |
| Clean database/API/browser | `CI=true npm run db:verify` | _pending_ |
| Security/privacy | `CI=true npm run test:security` | _pending_ |
| Local capacity regression | `CI=true npm run test:performance` | _pending_ |
| Deterministic story corpus | `npm run test:story-evals` | _pending_ |
| Paid production-model corpus | Safe report from `npm run eval:story:live` | _pending_ |
| GitHub merge controls | `Application checks` and `Database smoke` required | _pending_ |

## Human and hosted gates

- [ ] QA-07 staging performance rows pass in
      `performance-capacity-checklist.md`.
- [ ] QA-08 physical browser/device, keyboard, screen-reader, zoom, and motion
      rows pass in `accessibility-device-checklist.md`.
- [ ] QA-10 production model/prompt/schema safe report is approved; escalation
      remains disabled unless independently approved.
- [ ] Two moderated 4-player parties pass PLAY-01 with findings triaged.
- [ ] One moderated 12-player Indian-context stress party passes PLAY-02.
- [ ] OPS-04 production resources and isolation pass
      `production-infrastructure-checklist.md`.
- [ ] OPS-05/LAUNCH-01 independent staging drills pass
      `staging-drill-checklist.md`.
- [ ] Requirements/traceability, migrations, privacy copy, support ownership,
      dashboards, alerts, budgets, accepted risks, and rollback point are
      reviewed.

## Accepted risks

Every exception requires an owner, expiry date, mitigation, and rollback
trigger. An empty row is not approval.

| Risk | Severity | Owner | Expiry | Mitigation | Rollback trigger | Approval |
|---|---|---|---|---|---|---|
| _none recorded_ | | | | | | |

## Production smoke

Use synthetic content only. Record correlation/deployment IDs, not room codes
or story data.

- [ ] Create room and save/rotate host recovery.
- [ ] Configure 4 players, claim one device, and prove wrong/old actors cannot
      fetch private views.
- [ ] Generate and atomically lock exactly one story with approved model
      versions.
- [ ] Confirm full GameMasterView and spoiler-safe player view.
- [ ] Execute one idempotent gameplay command and one forced intervention
      fallback/approval.
- [ ] Reach reveal/completion, verify telemetry, and leave a rollback path
      available.
- [ ] Confirm maintenance reconciliation and bounded cleanup health.

## Initial observation window

Start: _pending_. End: _pending_. Owner: _pending_. Review availability,
auth/claim denials, generation latency/failure/quality, command latency,
intervention fallback, OpenAI spend, cleanup backlog, and user reports at the
agreed cadence. A release blocker keeps the window open and invokes the
recorded rollback condition.

| Checkpoint | Availability | Auth/claims | Generation | Latency | Fallback | Spend | Cleanup | Reports | Decision |
|---|---|---|---|---|---|---|---|---|---|
| +1 hour | | | | | | | | | _pending_ |
| +24 hours | | | | | | | | | _pending_ |
| Window close | | | | | | | | | _pending_ |

## Go/no-go approvals

| Role | Name | UTC date | Decision |
|---|---|---|---|
| Product | _pending_ | _pending_ | _pending_ |
| Engineering | _pending_ | _pending_ | _pending_ |
| Security/privacy | _pending_ | _pending_ | _pending_ |
| Operations | _pending_ | _pending_ | _pending_ |
