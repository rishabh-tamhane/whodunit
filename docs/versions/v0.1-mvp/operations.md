# v0.1 Operations, Privacy, and Recovery

This runbook is the operator contract for the MVP. It intentionally contains no
room codes, player names, story text, credentials, provider payloads, or private
player-authored content.

## Deployment shape

- Next.js runs on Vercel in `bom1`.
- Supabase Postgres, Auth, and Realtime run in Mumbai (`ap-south-1`).
- Cloudflare manages DNS and TLS. Workers are not required for the MVP.
- Preview, local, and production use different Supabase projects and secrets.
  Environment validation refuses a production project from a non-production
  deployment.
- The server-only OpenAI key, webhook secret, Supabase service-role key,
  recovery pepper, safety-identifier HMAC secret, and Cron secret live only in
  encrypted Vercel environment variables. They never use a `NEXT_PUBLIC_`
  prefix.
- `/api/internal/cron/maintenance` runs every ten minutes with Vercel's
  `CRON_SECRET`. It reconciles at most ten stale generation jobs, purges due
  generation inputs, and deletes at most 25 expired rooms per execution.
- The application enforces durable one-minute IP, principal, and room budgets.
  Discovery, claim, and recovery denials include
  `X-Whodunit-Abuse-Action: turnstile-challenge`; the production Cloudflare
  rule uses that route class and denial threshold to escalate sustained abuse.
  Normal clients must not send or depend on this response header.

## Privacy-safe observability

`operational_events` accepts only these dimensions: correlation ID, event type,
severity, route code, hashed room ID, duration, status/error code, counts,
phase, source, fallback flag, token counts, and model-call latency. The database
rejects every metadata key outside that allowlist.

Never log or send to analytics:

- prompts, provider payloads, generated roles, secrets, solutions, or dossiers;
- names, costumes, raw descriptions/authorship, notebooks, theories, or
  accusations;
- room codes, guest tokens, recovery credentials/fragments, cookies, API keys,
  webhook signatures, or service-role credentials;
- request/response bodies from player, generation, intervention, or endgame
  endpoints.

The committed-source secret scan blocks common OpenAI/Supabase/private-key
formats. `.env.local` is deliberately ignored and is never scanned, printed, or
committed. Error responses expose a correlation ID and stable sanitized code,
not database/provider payloads.

## Alert catalog

| Alert | Threshold | Owner / severity | Diagnose | Safe remediation | Resolution test |
|---|---|---|---|---|---|
| Availability | Health success below 99% for 5 min | Backend / SEV-1 | Vercel and Supabase status, sanitized 5xx count | Roll back last deployment or fail over provider-independent gameplay | Health and projection smoke pass for 15 min |
| Generation stalled | Any job stale for 15 min, or 3 failures in 15 min | AI/Backend / SEV-2 | Job phase, attempt count, response ID presence; never prompt/content | Run maintenance once; disable new generation if provider-wide | Job locks once or safely returns to LOBBY |
| Intervention fallback | More than 20% over 15 min with at least 10 calls | AI/Backend / SEV-3 | Provider latency/error code and fallback count | Keep deterministic fallback; disable live selection if needed | Fallback rate below threshold for 30 min |
| Webhook verification | 5 invalid/error deliveries in 5 min | Backend / SEV-2 | Signature error count, endpoint secret version | Verify endpoint URL; rotate webhook secret if exposure suspected | Signed test accepted; invalid/replay test rejected |
| Command conflicts | At least 10 conflicts over 15 min | Backend / SEV-3 | Route code and conflict count | Inspect client refresh/retry behavior; do not bypass version checks | Representative journey has no unexpected conflict |
| Auth/rate denial | 50 denials from one hashed source in 5 min | Security / SEV-2 | Hashed source, route class, status only | Keep throttling; enable Cloudflare challenge rule for that route/source | Legitimate smoke passes; abusive replay remains denied |
| Deletion backlog | `remainingEligible > 0` for 3 Cron runs | Operations / SEV-2 | Batch count and database availability | Run bounded cleanup again; never issue an unbounded delete | Backlog reaches zero and audit count matches |
| AI spend | US$50 monthly or US$2 per room warning; US$75 monthly or US$3 per room hard stop | Product/Operations / SEV-2 | OpenAI project budget plus stored token counts | Stop new AI calls; deterministic gameplay remains enabled | Budget reset/exception recorded and generation smoke approved |

## Failure and recovery matrix

| Failure | User-visible behavior | Owner action |
|---|---|---|
| Offline or missed Realtime signal | Last authorized view is marked stale; focus/online event and 5-second polling refetch | None unless availability alert fires |
| Stale command | HTTP 409, authoritative refetch, explicit retry; idempotency key prevents duplicates | Diagnose only if conflict alert fires |
| Revoked/replaced player | Projection returns forbidden and player is sent back to Join/Reconnect | Game Master approves one replacement binding |
| Old Game Master after recovery | Old principal cannot fetch or mutate; recovered session receives full GM view | Use current recovery credential only |
| Generation timeout/webhook loss | Durable phase is reconciled after 15 minutes; exhausted recovery returns safely to LOBBY | Run maintenance; inspect provider status |
| Live intervention timeout/refusal | Prepared canonical fallback is staged; GM still approves before release | No emergency action needed |
| Accusation intake closed during save | Failed draft/save is visible; refresh shows submitted/closed state; no mutation is implied | GM may wait before closing; never reopen frozen inputs |
| Database/provider outage after ambiguous command | Client refetches before offering retry; receipt replays the original result | Restore dependency, then run representative command smoke |

## Capacity and cost controls

- Release target: 10 concurrent rooms and 120 connected players.
- Projection polling is bounded to once per visible client per five seconds;
  Realtime carries only room ID, state version, change type, and timestamp.
- Story generation is limited to the initial attempt, two repairs, and one
  evaluation-approved escalation path. A response has a 24,000 output-token
  ceiling; token usage and provider response IDs are persisted.
- A live intervention has a 200 output-token ceiling, a 10-second request
  timeout, one model attempt, a per-round release cap, and deterministic
  canonical fallback. Input/output tokens and latency are persisted.
- When the monthly or per-room dollar hard cap is reached, operators disable
  new story generation and live intervention calls. Existing locked rooms keep
  all deterministic gameplay, prepared fallback, scoring, reveal, and case-file
  behavior.

## Retention and deletion

- DRAFT/LOBBY expire after seven inactive days.
- READY_TO_START, IN_PROGRESS, FINAL_ACCUSATIONS, and REVEAL expire after 30
  inactive days.
- GENERATING is never deleted; a stale job is resumed from its durable provider
  response/checkpoint or failed safely to LOBBY.
- COMPLETED expires exactly 30 days after `completed_at`.
- Successful room mutations and private draft saves extend incomplete-room
  activity. Page views and presence heartbeats do not.
- Cleanup locks room roots, deletes in bounded batches through foreign-key
  cascades, and retains only a hashed, content-free deletion audit. Old
  anonymous auth users are removed only when no membership or GM principal
  references them.

## Recovery and rollback procedures

### Rotate a secret

1. Create a replacement in the owning provider; do not paste it into tickets or
   chat.
2. Update the production-only Vercel secret and redeploy.
3. For webhook rotation, update the OpenAI endpoint and Vercel secret together,
   then send one signed test event. The official OpenAI webhook helper verifies
   the raw body, signature, and timestamp; the database deduplicates the durable
   `webhook-id` before side effects.
4. Revoke the old secret after health, generation, and webhook smokes pass.

### Database backup/restore

1. Confirm the Supabase managed backup/PITR is healthy before release.
2. Restore into a separate staging project, never over the live project.
3. Apply the repository migration head and run `CI=true npm run db:verify`.
4. Compare content-free row counts/checksums, then obtain incident-owner
   approval before any production cutover.

### Migration failure

Migrations are forward-only. Stop deployment, leave the last healthy Vercel
version serving, and ship a reviewed compensating migration. Never edit an
already-applied migration or use destructive reset commands against a linked
project. Validate the compensation from an empty database and a restored
staging backup.

### Provider or webhook outage

Keep locked rooms playable. Intervention requests use prepared fallback.
Generation remains durable and bounded; the maintenance job retrieves the
known provider response or safely fails back to LOBBY. Do not create a second
story for a locked room.

### Deployment rollback

Promote the previous healthy Vercel deployment, confirm it is compatible with
the forward database schema, run health/auth/projection/command smokes, and
record the rollback deployment ID and resolution evidence. Database rollback
is not coupled to application rollback.

## Production activation checklist (human-owned)

- Create production Supabase in Mumbai and confirm backups/PITR.
- Create Vercel production project in `bom1`; configure production-only secrets,
  Cron, spend alerts, and preview isolation.
- Configure Cloudflare DNS/TLS and the application domain.
- Register the final HTTPS OpenAI webhook URL and store its signing secret.
- Configure Cloudflare Turnstile/challenge escalation for sustained abusive
  join/claim/recovery traffic, matching the application's 429 escalation
  signal, and verify both an ordinary retry and a challenged abusive path.
- Require the GitHub checks `Application checks` and `Database smoke`.
- Run staging recovery, rotation, cleanup, webhook, provider-outage, and
  deployment-rollback drills; attach evidence to the release checklist.
