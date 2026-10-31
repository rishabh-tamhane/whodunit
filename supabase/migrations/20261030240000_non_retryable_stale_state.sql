-- REL-03: stale client versions are application conflicts, not database
-- serialization failures. PostgREST retries SQLSTATE 40001 automatically when
-- concurrent calls overlap, so using it for an expected stale version can spin
-- until the request timeout. P4091 is application-owned and non-retryable.

do $migration$
declare
  routine record;
  original_definition text;
  rewritten_definition text;
  rewritten_count integer := 0;
begin
  for routine in
    select procedure.oid
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('app_private', 'public')
      and procedure.prokind = 'f'
      and pg_catalog.pg_get_functiondef(procedure.oid)
        ~ 'errcode[[:space:]]*=[[:space:]]*''40001'''
  loop
    original_definition := pg_catalog.pg_get_functiondef(routine.oid);
    rewritten_definition := pg_catalog.regexp_replace(
      original_definition,
      'errcode[[:space:]]*=[[:space:]]*''40001''',
      'errcode = ''P4091''',
      'g'
    );

    if rewritten_definition = original_definition then
      raise exception 'failed to rewrite a stale-state SQLSTATE';
    end if;

    execute rewritten_definition;
    rewritten_count := rewritten_count + 1;
  end loop;

  if rewritten_count <> 27 then
    raise exception 'expected to rewrite 27 stale-state functions, rewrote %',
      rewritten_count;
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('app_private', 'public')
      and procedure.prokind = 'f'
      and pg_catalog.pg_get_functiondef(procedure.oid)
        ~ 'errcode[[:space:]]*=[[:space:]]*''40001'''
  ) then
    raise exception 'a retryable stale-state SQLSTATE remains';
  end if;
end;
$migration$;

comment on function public.review_player_claim(uuid, uuid, bigint, text) is
  'Reviews a player claim; stale versions raise non-retryable SQLSTATE P4091.';
