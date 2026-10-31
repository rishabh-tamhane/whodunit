begin;
select plan(2);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('app_private', 'public')
      and procedure.prokind = 'f'
      and pg_catalog.pg_get_functiondef(procedure.oid)
        ~ 'errcode[[:space:]]*=[[:space:]]*''40001'''
  ),
  0::bigint,
  'application stale-state conflicts never use retryable SQLSTATE 40001'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('app_private', 'public')
      and procedure.prokind = 'f'
      and pg_catalog.pg_get_functiondef(procedure.oid)
        ~ 'errcode[[:space:]]*=[[:space:]]*''P4091'''
  ),
  27::bigint,
  'all stale-state functions use the non-retryable application SQLSTATE'
);

select * from finish();
rollback;
