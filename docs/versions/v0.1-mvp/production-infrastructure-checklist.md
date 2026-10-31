# v0.1 Production Infrastructure Checklist

This is the human provisioning record for OPS-04. Never paste credential values
into this document; record only provider resource IDs, secret versions, and
verification results.

## Environment isolation

| Control | Preview/staging | Production | Evidence |
|---|---|---|---|
| Vercel project/environment | Non-production only | Dedicated production | _pending_ |
| `APP_ENV` / `NEXT_PUBLIC_APP_ENV` | `preview` or `staging` | `production` | _pending_ |
| `SERVER_CREDENTIAL_SCOPE` | Matches non-production | `production` | _pending_ |
| Supabase project ref | Non-production project | Dedicated Mumbai project | _pending_ |
| `PRODUCTION_SUPABASE_PROJECT_REF` | Production ref only for fail-closed comparison | Same production ref | _pending_ |
| OpenAI project/key | Staging project and spend cap | Production project and spend cap | _pending_ |
| DNS/domain | Preview Vercel domain | Cloudflare-managed public domain | _pending_ |

The deployment must fail if a preview/staging environment can load the
production Supabase project or production-only server credentials.

## Vercel

- [ ] Import the GitHub repository without exposing secrets to forked preview
      builds.
- [ ] Use Node 24 from `.nvmrc`, region `bom1`, and the committed
      `vercel.json` ten-minute maintenance Cron.
- [ ] Configure all values from `.env.example`; only
      `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and
      `NEXT_PUBLIC_APP_ENV` may use `NEXT_PUBLIC_`.
- [ ] Scope production values to Production only and staging values to the
      intended non-production environment.
- [ ] Confirm deployment logs and build output contain no secret values,
      descriptions, prompts, generated stories, room codes, or player text.
- [ ] Record the healthy rollback deployment ID: _pending_.

## Supabase

- [ ] Create the production project in Mumbai (`ap-south-1`) and record its
      non-secret project ref: _pending_.
- [ ] Enable anonymous Auth, managed backups/PITR, Realtime, and the extensions
      required by committed migrations.
- [ ] Apply every migration in order to the intended project; never use local
      reset or `--linked` destructive commands as a release shortcut.
- [ ] Confirm RLS and grants from a production-like smoke principal before DNS
      cutover.
- [ ] Schedule/authorize only the Vercel maintenance endpoint; browser
      principals cannot execute cleanup/reconciliation functions.
- [ ] Record backup/PITR status and most recent successful backup: _pending_.

## OpenAI and webhooks

- [ ] Create production and staging API projects with separate API keys,
      budgets, and alert ownership.
- [ ] Register the final production HTTPS webhook endpoint and store its
      signing secret only in Vercel Production.
- [ ] Confirm configured story, escalation, and intervention model IDs have
      passed QA-10; do not enable an escalation model on assumption.
- [ ] Send one signed synthetic delivery and one invalid/replayed delivery;
      verify acceptance and safe rejection without payload logging.

## Cloudflare

- [ ] Proxy the public domain to Vercel with Full (strict) TLS and record the
      certificate/hostname result.
- [ ] Preserve Vercel's trusted client-IP headers; do not allow a client to
      bypass rate limits with an untrusted forwarding header.
- [ ] Configure challenge escalation for sustained join/claim/recovery abuse
      aligned with the application's 429 route signal.
- [ ] Verify DNS, HTTPS redirect, HSTS, CSP, frame denial, no-referrer policy,
      and private response caching from the public hostname.

## Production-like smoke

From a clean browser, create a synthetic room, open the lobby, claim and
approve one device, verify old/new host recovery authority, fetch actor views,
and invoke maintenance with the scheduler credential. Confirm preview/local
credentials cannot access any production resource.

| Role | Name | UTC date | Decision |
|---|---|---|---|
| Platform | _pending_ | _pending_ | _pending_ |
| Security | _pending_ | _pending_ | _pending_ |
