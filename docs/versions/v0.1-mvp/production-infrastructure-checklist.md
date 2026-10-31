# v0.1 Hobby Deployment Record

This is the non-secret provisioning record for the friends-only MVP. It records
what is actually deployed, not a future enterprise setup. Never add credential
values, room recovery links, player data, prompts, or generated stories here.

## Live environment

| Component | Current configuration | Status |
|---|---|---|
| Application | Vercel Hobby project `whodunit`, Node 24, region `bom1` | Ready |
| Healthy deployment | `DWUYY25p52EkzH6rXyC67S8BEmEE` | Ready |
| Public URL | `https://whodunit.rishabhtamhane.com` | Ready |
| DNS | Cloudflare DNS-only CNAME to Vercel | Ready |
| TLS | Managed by Vercel for the public hostname | Ready |
| Database/Auth | Supabase project `vicgjoyxlwubjuskwgce`, Seoul (`ap-northeast-2`) | Ready |
| Database schema | All 24 committed migrations applied | Ready |
| Guest access | Supabase anonymous sign-in enabled | Ready |
| Maintenance | Vercel Cron once daily at 05:00 UTC | Ready |
| OpenAI API key | Rotated by the owner; value is not stored in this record | Ready for a controlled smoke test |
| OpenAI webhook | Final HTTPS endpoint and signing secret not registered | Pending |

Cloudflare is intentionally not proxying the hostname. This keeps the hobby
deployment simple: Cloudflare supplies DNS and Vercel terminates HTTPS. A
separate staging Supabase project, preview isolation, managed PITR, and
Cloudflare challenge rules are future upgrades, not v0.1 hobby prerequisites.

## Verified on 2026-10-30

- [x] The production build starts without exposing environment values in logs.
- [x] `GET /api/v1/health` returns HTTP 200 from the public hostname.
- [x] Anonymous session creation returns HTTP 201.
- [x] Setup profiles return HTTP 200 for an authenticated guest session.
- [x] A disposable DRAFT room can be created through the public API.
- [x] The room code is discovery-only and the recovery credential is not logged.
- [x] All local and linked migration versions match.
- [x] The public hostname resolves through Cloudflare DNS and serves Vercel over HTTPS.

The disposable smoke room contains no real player data and may expire through
the normal inactive-room retention process.

## Still to verify

- [ ] Register and verify the OpenAI webhook, or explicitly approve polling-only
      generation for the hobby build.
- [ ] Rotate the app-owned webhook, recovery-pepper, safety-HMAC, and Cron
      secrets if their current versions were ever copied outside Vercel.
- [ ] Run one deliberately low-cost story generation after the OpenAI key and
      spend limit are confirmed.
- [ ] Complete one real end-to-end game: claims, GameMasterView, a gameplay
      command, intervention/fallback, final accusation, reveal, and case file.
- [ ] Check the player experience on the phones and browsers the group will
      actually use.
- [ ] Confirm the daily maintenance invocation succeeds after its first run.

## Deliberate hobby trade-offs

- Preview deployments may share configuration with the live project. Do not
  use previews for destructive tests or real games.
- There is no separate staging project or rehearsed database restore.
- Supabase free-plan backup/PITR guarantees have not been claimed or verified.
- No paid 18-case model evaluation is required. Model quality will be checked
  through one controlled smoke generation and real friend-group playtests.
- Branch protection, formal on-call alerts, and enterprise Cloudflare controls
  are deferred unless the game grows beyond a private friends-only MVP.

## Human sign-off

| Check | Owner | Date | Result |
|---|---|---|---|
| Infrastructure and non-AI smoke | Project owner + Codex | 2026-10-30 | Passed |
| AI generation smoke | Project owner | _pending_ | _pending_ |
| Real-device game smoke | Project owner and friends | _pending_ | _pending_ |
