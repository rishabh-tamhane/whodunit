# v0.1 Staging Operational Drills

This is the evidence record for OPS-05 and LAUNCH-01. Run against one immutable
staging deployment using synthetic data and staging-only credentials. A person
other than the procedure author must execute every drill.

## Run metadata

| Field | Value |
|---|---|
| Commit / deployment ID | _pending_ |
| Staging URL and regions | _pending_ |
| Supabase project ref (non-secret) | _pending_ |
| Operator / observer | _pending_ |
| UTC start/end | _pending_ |
| Approved recovery targets | _pending_ |

## Drill matrix

| Drill | Safe fault injection | Required proof | Duration / result | Evidence |
|---|---|---|---|---|
| Host recovery | Use current recovery link in a clean guest browser | New GM gets full view; old GM and old link are denied; replacement link rotates | _pending_ | |
| Secret rotation | Rotate one staging-only key using overlap where supported | New version works, old version revoked, logs contain neither value | _pending_ | |
| Generation reconciliation | Stop worker after durable provider receipt/checkpoint | Maintenance resumes once or fails safely to LOBBY; never a second story | _pending_ | |
| Provider outage | Disable staging provider access | Locked rooms remain playable; new generation fails safely and is bounded | _pending_ | |
| Intervention fallback | Force timeout/refusal | Prepared canonical fallback is staged by 6 s and still requires GM approval | _pending_ | |
| Retention deletion | Create due completed/inactive synthetic rooms | Batch deletes all room artifacts; active control survives; only hashed audit remains | _pending_ | |
| Database restore | Restore managed backup into a separate staging project | Migration head applies and content-free checks reconcile within target | _pending_ | |
| Failed migration | Apply a deliberately failing staging-only migration | Deployment stops; forward compensation restores compatibility; no destructive reset | _pending_ | |
| Webhook outage/replay | Pause endpoint, then resend signed and duplicate events | Reconciliation succeeds; replay receipt prevents duplicate side effects | _pending_ | |
| Deployment rollback | Promote previous healthy Vercel deployment | Health/auth/projection/command smokes pass against forward-compatible schema | _pending_ | |

## Evidence rules

- Capture provider/deployment IDs, UTC timestamps, normalized errors, counts,
  timings, and screenshots of public-safe status only.
- Never capture credentials, recovery fragments, cookies, room codes, names,
  prompts, descriptions, generated story text, notes, theories, or accusations.
- Link every failed target to a blocker with owner, mitigation, expiry, and
  rollback condition. Rerun the affected drill after remediation.

## Sign-off

| Role | Name | UTC date | Decision |
|---|---|---|---|
| Independent operator | _pending_ | _pending_ | _pending_ |
| Operations owner | _pending_ | _pending_ | _pending_ |
| Security owner | _pending_ | _pending_ | _pending_ |
