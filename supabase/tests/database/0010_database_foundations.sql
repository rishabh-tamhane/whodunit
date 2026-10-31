begin;

select plan(18);

select has_schema(
  'app_private',
  'the non-exposed application schema exists'
);

select is(
  (
    select n.nspname
    from pg_catalog.pg_extension as e
    join pg_catalog.pg_namespace as n on n.oid = e.extnamespace
    where e.extname = 'pgcrypto'
  ),
  'extensions',
  'pgcrypto is installed in the extensions schema'
);

select ok(
  not pg_catalog.has_schema_privilege('anon', 'app_private', 'USAGE'),
  'anon cannot use app_private'
);

select ok(
  not pg_catalog.has_schema_privilege('authenticated', 'app_private', 'USAGE'),
  'authenticated cannot use app_private'
);

select ok(
  not pg_catalog.has_schema_privilege('anon', 'app_private', 'CREATE'),
  'anon cannot create objects in app_private'
);

select ok(
  not pg_catalog.has_schema_privilege('authenticated', 'app_private', 'CREATE'),
  'authenticated cannot create objects in app_private'
);

select ok(
  not pg_catalog.has_schema_privilege('anon', 'public', 'CREATE'),
  'anon cannot create objects in public'
);

select ok(
  not pg_catalog.has_schema_privilege('authenticated', 'public', 'CREATE'),
  'authenticated cannot create objects in public'
);

select ok(
  pg_catalog.has_schema_privilege('anon', 'public', 'USAGE'),
  'anon can resolve explicitly granted public RPCs'
);

select ok(
  pg_catalog.has_schema_privilege('authenticated', 'public', 'USAGE'),
  'authenticated can resolve explicitly granted public RPCs'
);

select is(
  (
    select pg_catalog.array_agg(e.enumlabel::text order by e.enumsortorder)
    from pg_catalog.pg_enum as e
    join pg_catalog.pg_type as t on t.oid = e.enumtypid
    join pg_catalog.pg_namespace as n on n.oid = t.typnamespace
    where n.nspname = 'app_private' and t.typname = 'room_state'
  ),
  array[
    'DRAFT',
    'LOBBY',
    'GENERATING',
    'READY_TO_START',
    'IN_PROGRESS',
    'FINAL_ACCUSATIONS',
    'REVEAL',
    'COMPLETED'
  ]::text[],
  'room states match the shared contract'
);

select is(
  (
    select pg_catalog.array_agg(e.enumlabel::text order by e.enumsortorder)
    from pg_catalog.pg_enum as e
    join pg_catalog.pg_type as t on t.oid = e.enumtypid
    join pg_catalog.pg_namespace as n on n.oid = t.typnamespace
    where n.nspname = 'app_private' and t.typname = 'membership_status'
  ),
  array['PENDING', 'ACTIVE', 'REVOKED']::text[],
  'membership states match the shared contract'
);

select is(
  (
    select pg_catalog.array_agg(e.enumlabel::text order by e.enumsortorder)
    from pg_catalog.pg_enum as e
    join pg_catalog.pg_type as t on t.oid = e.enumtypid
    join pg_catalog.pg_namespace as n on n.oid = t.typnamespace
    where n.nspname = 'app_private' and t.typname = 'claim_kind'
  ),
  array['INITIAL_CLAIM', 'RECONNECT']::text[],
  'claim kinds match the shared contract'
);

select is(
  (
    select pg_catalog.array_agg(e.enumlabel::text order by e.enumsortorder)
    from pg_catalog.pg_enum as e
    join pg_catalog.pg_type as t on t.oid = e.enumtypid
    join pg_catalog.pg_namespace as n on n.oid = t.typnamespace
    where n.nspname = 'app_private' and t.typname = 'mission_status'
  ),
  array[
    'ASSIGNED',
    'ACCEPTED',
    'COMPLETION_REQUESTED',
    'COMPLETED',
    'FAILED',
    'CONSEQUENCE_PENDING',
    'CONSEQUENCE_RELEASED',
    'WAIVED'
  ]::text[],
  'mission states match the shared contract'
);

select is(
  (
    select pg_catalog.array_agg(e.enumlabel::text order by e.enumsortorder)
    from pg_catalog.pg_enum as e
    join pg_catalog.pg_type as t on t.oid = e.enumtypid
    join pg_catalog.pg_namespace as n on n.oid = t.typnamespace
    where n.nspname = 'app_private' and t.typname = 'accusation_status'
  ),
  array['DRAFT', 'SUBMITTED']::text[],
  'accusation states match the shared contract'
);

select has_function(
  'app_private',
  'current_database_time',
  array[]::text[],
  'the internal database clock exists'
);

select ok(
  (
    select 'search_path=""' = any(coalesce(p.proconfig, array[]::text[]))
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'app_private'
      and p.proname = 'current_database_time'
  ),
  'the internal database clock has an empty fixed search_path'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app_private.current_database_time()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.current_database_time()',
    'EXECUTE'
  ),
  'API roles cannot execute the internal database clock'
);

select * from finish();

rollback;
