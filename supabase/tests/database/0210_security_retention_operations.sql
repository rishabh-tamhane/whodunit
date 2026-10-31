begin;
select no_plan();

select has_function(
  'public','consume_rate_limit',array['text','text','integer','integer'],
  'durable multi-instance rate-limit command exists'
);
select has_function(
  'public','reconcile_stale_generation_jobs',array[]::text[],
  'stale generation reconciliation command exists'
);
select has_function(
  'public','cleanup_expired_rooms',array['integer'],
  'batched retention cleanup command exists'
);
select has_column(
  'app_private','rooms','inactivity_expires_at',
  'rooms carry a state-specific inactivity deadline'
);
select ok(
  not has_function_privilege(
    'authenticated','public.cleanup_expired_rooms(integer)','EXECUTE'
  ),
  'clients cannot invoke destructive retention cleanup'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(
  public.consume_rate_limit(
    'IP_ROUTE', repeat('a',64), 1, 60
  ) ->> 'allowed',
  'true',
  'the first request in a durable rate window is allowed'
);
select is(
  public.consume_rate_limit(
    'IP_ROUTE', repeat('a',64), 1, 60
  ) ->> 'allowed',
  'false',
  'the request above the durable rate budget is denied'
);
select lives_ok(
  $$select public.record_operational_event(
    'c0000000-0000-4000-8000-000000000001','GENERATION_RECONCILED',
    'INFO','CRON_MAINTENANCE',null,12,200,null,
    '{"count":1,"latencyMs":12}'::jsonb
  )$$,
  'allowlisted operational telemetry is accepted'
);
select throws_ok(
  $$select public.record_operational_event(
    'c0000000-0000-4000-8000-000000000002','UNSAFE_EVENT',
    'INFO','TEST',null,null,200,null,
    '{"notesText":"private"}'::jsonb
  )$$,
  '23514',
  'new row for relation "operational_events" violates check constraint "operational_events_metadata_allowlist"',
  'private-content-shaped telemetry is rejected by the database'
);

insert into auth.users (id) values
  ('c1000000-0000-4000-8000-000000000001'),
  ('c1000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000003');
insert into app_private.rooms (
  id, room_code, host_auth_user_id, status, created_at, updated_at
) values (
  'c2000000-0000-4000-8000-000000000001','OLDLOBBY',
  'c1000000-0000-4000-8000-000000000001','LOBBY',
  app_private.current_database_time() - interval '9 days',
  app_private.current_database_time() - interval '8 days'
), (
  'c2000000-0000-4000-8000-000000000002','OLDDONE1',
  'c1000000-0000-4000-8000-000000000002','COMPLETED',
  app_private.current_database_time() - interval '32 days',
  app_private.current_database_time() - interval '31 days'
), (
  'c2000000-0000-4000-8000-000000000003','ACTIVE01',
  'c1000000-0000-4000-8000-000000000003','LOBBY',
  app_private.current_database_time(),
  app_private.current_database_time()
);
update app_private.rooms
set completed_at = app_private.current_database_time() - interval '31 days',
  expires_at = app_private.current_database_time() - interval '1 day'
where id = 'c2000000-0000-4000-8000-000000000002';
insert into app_private.room_host_principals (room_id, auth_user_id) values
  ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001'),
  ('c2000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002'),
  ('c2000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003');

select is(
  public.cleanup_expired_rooms(25) ->> 'deletedCount',
  '2',
  'cleanup deletes completed and incomplete rooms only after their policy deadline'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.rooms
    where id in (
      'c2000000-0000-4000-8000-000000000001',
      'c2000000-0000-4000-8000-000000000002'
    )),
  0,
  'expired room roots are removed with their cascaded artifacts'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.room_deletion_audit
    where room_hash in (
      pg_catalog.encode(extensions.digest(pg_catalog.convert_to('c2000000-0000-4000-8000-000000000001','UTF8'),'sha256'),'hex'),
      pg_catalog.encode(extensions.digest(pg_catalog.convert_to('c2000000-0000-4000-8000-000000000002','UTF8'),'sha256'),'hex')
    )),
  2,
  'deletion leaves only non-identifying audit evidence'
);
select ok(
  exists (select 1 from app_private.rooms where id='c2000000-0000-4000-8000-000000000003'),
  'active room principals are never deleted prematurely'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"c1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select ok(
  public.get_actor_view('c2000000-0000-4000-8000-000000000003')
    #>> '{room,retentionDeadline}' is not null,
  'authorized actors receive the current retention warning deadline'
);

select * from finish();
rollback;
