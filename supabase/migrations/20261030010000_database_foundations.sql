-- DB-01: application schema, privilege, extension, and enum foundations.
--
-- Keep application data outside the exposed public schema unless a later
-- migration explicitly defines a safe projection or signal table.

create schema app_private;

comment on schema app_private is
  'Non-exposed application data and internal command functions.';

-- Supabase exposes public through the Data API. Callers may resolve explicitly
-- granted RPCs there, but they may never create their own objects.
revoke create on schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated, service_role;

-- app_private is reachable only by object owners and deliberately granted
-- internal paths. Owning a valid JWT does not grant schema access.
revoke all on schema app_private from public, anon, authenticated;

-- Lock down objects that may already exist in public and ensure future objects
-- start closed. Later migrations must grant the minimum privilege explicitly.
revoke all on all tables in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke usage on types from public, anon, authenticated;

alter default privileges for role postgres in schema app_private
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema app_private
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema app_private
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema app_private
  revoke usage on types from public, anon, authenticated;

-- Required for checksums, recovery-secret digests, and secure random values in
-- later migrations. Supabase reserves the extensions schema for extensions.
create extension if not exists pgcrypto with schema extensions;

create type app_private.room_state as enum (
  'DRAFT',
  'LOBBY',
  'GENERATING',
  'READY_TO_START',
  'IN_PROGRESS',
  'FINAL_ACCUSATIONS',
  'REVEAL',
  'COMPLETED'
);

create type app_private.membership_status as enum (
  'PENDING',
  'ACTIVE',
  'REVOKED'
);

create type app_private.claim_kind as enum (
  'INITIAL_CLAIM',
  'RECONNECT'
);

create type app_private.mission_status as enum (
  'ASSIGNED',
  'ACCEPTED',
  'COMPLETION_REQUESTED',
  'COMPLETED',
  'FAILED',
  'CONSEQUENCE_PENDING',
  'CONSEQUENCE_RELEASED',
  'WAIVED'
);

create type app_private.accusation_status as enum (
  'DRAFT',
  'SUBMITTED'
);

comment on type app_private.room_state is
  'Immutable labels mirrored by src/contracts/domain/lifecycle.ts.';
comment on type app_private.membership_status is
  'Immutable labels mirrored by src/contracts/domain/membership.ts.';
comment on type app_private.claim_kind is
  'Immutable labels mirrored by src/contracts/domain/membership.ts.';
comment on type app_private.mission_status is
  'Immutable labels mirrored by src/contracts/domain/mission.ts.';
comment on type app_private.accusation_status is
  'Immutable labels mirrored by src/contracts/domain/accusation.ts.';

-- Internal time access is isolated behind a fixed-search-path function so
-- command functions can accept a Clock-equivalent dependency in tests later.
create function app_private.current_database_time()
returns timestamp with time zone
language sql
stable
security invoker
set search_path = ''
as $function$
  select pg_catalog.statement_timestamp();
$function$;

revoke all on function app_private.current_database_time()
  from public, anon, authenticated;

comment on function app_private.current_database_time() is
  'Internal database clock. Never grant directly to API roles.';
