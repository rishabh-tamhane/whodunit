# Database Verification Matrix

This document records the database-milestone evidence for v0.1. The authoritative clean-worker command is:

```bash
CI=true npm run db:verify
```

It starts the disposable local Supabase Docker stack, replays every forward migration from an empty database, applies the deterministic seed, runs all pgTAP files in independent rollback transactions, starts the real Next.js application, runs HTTP and anonymous-Auth integration smoke tests, and removes the local stack in CI mode.

## Migration and Test Traceability

| Task | Migration | Primary pgTAP verification |
|---|---|---|
| DB-01 | `20261030010000_database_foundations.sql` | `0010_database_foundations.sql` |
| DB-02 | `20261030020000_room_identity_tables.sql` | `0020_room_identity_tables.sql` |
| DB-03 | `20261030030000_game_master_identity.sql` | `0030_game_master_identity.sql` |
| DB-04 | `20261030040000_canonical_story_tables.sql` | `0040_canonical_story_tables.sql` |
| DB-05 | `20261030050000_command_sync_infrastructure.sql` | `0050_command_sync_infrastructure.sql` |
| DB-06 | `20261030060000_gameplay_runtime_tables.sql` | `0060_gameplay_runtime_tables.sql` |
| DB-07 | `20261030070000_player_private_submitted_state.sql` | `0070_player_private_submitted_state.sql` |
| DB-08 | `20261030080000_endgame_result_case_file_tables.sql` | `0080_endgame_result_case_file_tables.sql` |
| DB-09 | `20261030090000_canonical_submitted_immutability.sql` | `0090_canonical_submitted_immutability.sql` |
| DB-10 | `20261030100000_identity_authorization_rls.sql` | `0100_identity_authorization_rls.sql` |
| DB-11 | `20261030110000_story_runtime_projections.sql` | `0110_story_runtime_projections.sql` |
| DB-12 | `20261030120000_duration_recommendation_profiles.sql` | `0120_duration_recommendation_profiles.sql` |
| DB-13 | `20261030130000_scoring_profile.sql` | `0130_scoring_profile.sql` |
| DB-14 | No production schema change | `0140_database_fixtures_migration_verification.sql` |
| IDN-02–04 | `20261030140000_room_setup_commands.sql` | `0150_room_setup_commands.sql` |
| IDN-06–10 | `20261030150000_onboarding_identity_commands.sql` | `0160_onboarding_identity_commands.sql` |
| GEN-01–10 | `20261030160000_generation_pipeline.sql` | `0170_generation_pipeline.sql` |
| GAM/GM/PLY runtime | `20261030170000_gameplay_commands.sql` | `0180_gameplay_commands.sql` |
| INT-01–05 | `20261030180000_live_interventions.sql` | `0190_live_interventions.sql` |
| END-01–07 | `20261030190000_endgame_commands.sql` | `0200_endgame_commands.sql` |
| SEC/REL retention | `20261030200000_security_retention_operations.sql` | `0210_security_retention_operations.sql` |
| GAM-03 failure receipt | `20261030210000_gameplay_failure_receipt.sql` | `0170_generation_pipeline.sql` full journey |

`0001_harness_smoke.sql` separately proves that local Auth, Postgres, and migration history exist before domain tests run.

## Representative Fixtures

The DB-14 test builds all fixtures only after a clean forward replay:

- **Minimal:** one dedicated Game Master, no player slots, default lifecycle state, and versioned duration/scoring references. This proves an editable setup room can exist before the host adds players.
- **Four-player:** the supported minimum with four unique player identities, four active device bindings, all acknowledgements, the complete 12-row directed description matrix, the 30-minute pacing profile, and the reviewed `1/0/3` faction recommendation.
- **Twelve-player:** the supported maximum with 12 unique player identities, 12 active device bindings, all acknowledgements, the complete 132-row directed description matrix, the 120-minute pacing profile, and the reviewed `3/2/7` recommendation.

The fixture test also proves that a thirteenth seat, cross-room membership, profile mutation, and Game Master/player identity overlap fail closed.

## Forward and Rollback Strategy

Production migrations are forward-only and ordered by unique timestamp. A clean reset is the supported local and CI rollback mechanism before release: discard the disposable database and replay the full history. Individual pgTAP files wrap fixtures and mutation probes in a transaction and end with `ROLLBACK`, proving that failed constraint probes and test data leave no state behind.

Deployed schema rollback is not performed by deleting migration-history rows or editing an applied migration. A production correction uses a new reviewed forward migration. Data-destructive recovery is handled only by an explicit, tested operational procedure with a backup and release approval.

## CI Gate

The database job is green only when all of these succeed in one clean worker:

1. Local Supabase starts without a hosted-project login or `.env.local`.
2. Every migration replays from empty in order.
3. The deterministic seed applies.
4. All pgTAP assertions pass.
5. The real `/api/v1/health` route responds through Next.js.
6. Anonymous Supabase Auth creates and cleans up a real local user.

Any migration, fixture, constraint, authorization, projection, or integration failure stops the job.
