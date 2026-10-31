# Whodunit

Whodunit is a mobile-first Halloween murder-mystery game for 4–12 players,
run by a separate, non-playing Game Master. This repository currently contains
the v0.1 product specification, technical design, execution backlog, and the
first application-foundation increment.

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

```sh
cp .env.example .env.local
npm install
npm run dev
```

Replace every placeholder in `.env.local` before starting the server. Runtime
configuration is validated at server startup; missing or malformed values stop
the process with a non-secret error message.

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
```

`npm run db:verify` is the clean-worker gate. It starts the local stack,
replays migrations and the deterministic seed, runs pgTAP, starts the Next.js
development server on an available loopback port, and runs real HTTP and local
Auth smoke tests. In CI it also removes the local stack and volumes on exit;
locally, run `npm run db:stop` when finished.

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

The backlog is the execution record. A checkbox is marked complete only after
the task's stated acceptance criteria and focused checks pass.
