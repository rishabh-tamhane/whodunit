# Whodunit

Whodunit is a mobile-first Halloween murder-mystery game for 4–12 players,
run by a separate, non-playing Game Master. This repository currently contains
the v0.1 product specification, technical design, execution backlog, and a
working end-to-end implementation through mystery completion and retention.

The foundation preserves the product's core boundaries:

- The Game Master is never a player and receives full generated-game visibility
  after the story locks.
- A public room code supports room discovery only; it never grants private data
  access.
- Player identity, device membership, and generated story role remain separate.
- The canonical story can be repaired before its first successful atomic lock,
  but can never regenerate afterward.
- OpenAI, Supabase service-role, webhook, and recovery secrets are server-only.

## Local setup

Requirements: Node.js 24 and npm 11.

For the simplest local setup, start Docker Desktop, create an ignored
`.env.local` beside `package.json` containing only your OpenAI key, then run:

```sh
npm install
npm run dev:local
```

```dotenv
OPENAI_API_KEY=your_openai_api_key_here
```

`dev:local` starts the committed local Supabase stack, discovers its local URL
and keys without printing them, and starts Whodunit at
`http://127.0.0.1:3000`. Next.js loads the OpenAI key from `.env.local`; the
launcher never reads or prints it. Press Ctrl+C to stop Next.js and run
`npm run db:stop` when finished.

For a manually configured or hosted environment, copy `.env.example` and
replace every placeholder before starting `npm run dev`. Runtime configuration
is validated at server startup; missing or malformed values stop the process
with a non-secret error message.

`APP_ENV`, `NEXT_PUBLIC_APP_ENV`, and `SERVER_CREDENTIAL_SCOPE` must agree.
Local, preview, staging, and production use separate Supabase projects and
separately scoped server credentials. A non-production deployment fails closed
if it is configured with `PRODUCTION_SUPABASE_PROJECT_REF`. Vercel environment
variables must therefore be scoped per deployment environment; never copy a
production service-role, model, webhook, recovery, or HMAC secret into Preview.

The initial routes are:

| Route            | Purpose                               |
| ---------------- | ------------------------------------- |
| `/`              | Product and architecture landing page |
| `/host`          | Game Master application boundary      |
| `/join`          | Player room-discovery boundary        |
| `/api/v1/health` | Uncached health response              |

## Quality checks

```sh
npm run format:check
npm run lint
npm run check:boundaries
npm run scan:secrets
npm run typecheck
npm test
npm run build
```

Run the complete local verification pipeline with `npm run check`. The custom
boundary check prevents browser code from importing service-role, recovery,
or OpenAI modules and keeps infrastructure dependencies out of shared domain
contracts.

## Local database and integration tests

Docker Desktop or another Docker-compatible runtime must be running. The
project-local Supabase CLI is pinned in `package.json`; no global install,
hosted project link, or Supabase access token is required.

```sh
npm run db:start
npm run db:reset
npm run db:test
npm run test:integration
npx playwright install chromium
npm run test:e2e
```

`npm run db:verify` is the clean-worker gate. It starts the local stack,
replays migrations and the deterministic seed, runs pgTAP, starts the Next.js
server on available loopback ports, and runs real HTTP, local Auth, and isolated
4/12-player browser journeys. The browser journeys build and run the production
Next.js server against a deterministic loopback OpenAI substitute; they never
use a real API key or mutate test state behind the product APIs. In CI the gate
also removes the local stack and volumes on exit; locally, run
`npm run db:stop` when finished.

## Continuous integration

The `CI` workflow runs on pull requests, pushes to `main`, and merge-queue
checks. Its `Application checks` job gates formatting, lint, module boundaries,
types, unit tests, and the production build. Its isolated `Database smoke` job
recreates the local Supabase stack and runs the full database/integration gate.

Repository rules should require both job names before merging to `main`:

- `Application checks`
- `Database smoke`

## Documentation

- [MVP overview](docs/versions/v0.1-mvp/README.md)
- [Requirements](docs/versions/v0.1-mvp/requirements.md)
- [Technical design](docs/versions/v0.1-mvp/technical-design.md)
- [Two-actor UX flow](docs/versions/v0.1-mvp/ux-flow.md)
- [Implementation backlog](docs/versions/v0.1-mvp/tasks.md)
- [Test strategy](docs/versions/v0.1-mvp/tests.md)
- [Operations and recovery runbook](docs/versions/v0.1-mvp/operations.md)

The backlog is the execution record. A checkbox is marked complete only after
the task's stated acceptance criteria and focused checks pass.
