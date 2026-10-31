# v0.1 Performance and Capacity Verification

This is the staging release record for QA-07. Local checks catch regressions;
they cannot approve provider latency, regional network behavior, or hosted
database capacity.

## Local automated baseline

Run `CI=true npm run test:performance`. The clean-worker suite performs three
warmed rounds of 120 concurrent health reads and ten concurrent room creates,
reports p50/p95/max, and enforces the local 500 ms read and 750 ms command p95
budgets. The same gate also exercises 4- and 12-player generation through the
deterministic provider mock, concurrent claim/command races, intervention
fallback behavior, and a 25-room cleanup bound.

| Field | Value |
|---|---|
| Commit | _pending_ |
| Machine / Docker resources | _pending_ |
| Read p50 / p95 / max | _pending_ |
| Command p50 / p95 / max | _pending_ |
| Result | _pending_ |

## Staging measurement method

Use one immutable staging deployment in the production regions with synthetic
data and staging-only secrets. Warm each route once, then record at least three
runs. Do not place room codes, names, story text, or provider payloads in the
report—only case dimensions, counts, timings, token use, cost, and normalized
errors.

| Scenario | Target | Run 1 | Run 2 | Run 3 | p50 / p95 / max | Result |
|---|---:|---:|---:|---:|---:|---|
| Ordinary projection read | p95 ≤ 500 ms | | | | | _pending_ |
| Ordinary state command | p95 ≤ 750 ms | | | | | _pending_ |
| 4-player story generation | p50 ≤ 45 s; p95 ≤ 90 s | | | | | _pending_ |
| 12-player story generation | p50 ≤ 45 s; p95 ≤ 90 s | | | | | _pending_ |
| Terminal generation recovery | visible by 120 s | | | | | _pending_ |
| Live intervention | p50 ≤ 2.5 s; p95 ≤ 5 s | | | | | _pending_ |
| Intervention fallback | starts by 6 s | | | | | _pending_ |
| Realtime fan-out to 12 players + GM | no private payload; refetch within target | | | | | _pending_ |
| Ten active rooms / 120 players | no capacity/error-budget breach | | | | | _pending_ |
| Competing database locks | no deadlock; bounded conflicts | | | | | _pending_ |
| Cleanup batch of 25 rooms | no lock starvation/backlog | | | | | _pending_ |

## Fault and budget evidence

- [ ] Provider timeout produces one deterministic intervention fallback.
- [ ] A stalled generation reaches reconciliation without locking a second
      story.
- [ ] Database conflicts return sanitized 409s and idempotent retries replay
      the original result.
- [ ] Token counts and estimated cost stay within the approved per-room caps.
- [ ] Alerts fire for generation stalls, fallback rate, command conflicts,
      spend, and cleanup backlog using content-free dimensions only.
- [ ] Results contain the staging deployment ID, region, database tier, Vercel
      plan, model/prompt/schema versions, tester, and UTC timestamp.

QA-07 closes only when every staging row passes or has an approved release
blocker/remediation with an owner and expiry.
