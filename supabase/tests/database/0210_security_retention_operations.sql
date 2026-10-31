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
  ('c1000000-0000-4000-8000-000000000003'),
  ('c1000000-0000-4000-8000-000000000004'),
  ('c1000000-0000-4000-8000-000000000005');
insert into app_private.rooms (
  id, room_code, host_auth_user_id, status, created_at, updated_at
) values (
  'c2000000-0000-4000-8000-000000000004','STALEGEN',
  'c1000000-0000-4000-8000-000000000004','GENERATING',
  app_private.current_database_time() - interval '3 hours',
  app_private.current_database_time() - interval '20 minutes'
), (
  'c2000000-0000-4000-8000-000000000005','RECOVGEN',
  'c1000000-0000-4000-8000-000000000005','GENERATING',
  app_private.current_database_time() - interval '1 hour',
  app_private.current_database_time() - interval '20 minutes'
);
insert into app_private.room_host_principals (room_id, auth_user_id) values
  ('c2000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000004'),
  ('c2000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000005');
insert into app_private.story_generation_jobs (
  id, room_id, idempotency_key, status, phase, input_snapshot_json,
  attempt_count, model_id, escalation_model_id, prompt_version,
  story_schema_version, validator_version, created_at, started_at, updated_at,
  lease_owner, lease_expires_at
) values (
  'c3000000-0000-4000-8000-000000000004',
  'c2000000-0000-4000-8000-000000000004',
  'c4000000-0000-4000-8000-000000000004','RUNNING','PLAYABLE_CONTENT','{}',
  3,'gpt-6.1-sol','gpt-6-astra','story-prompt-v1','0.1.0','story-validator-v1',
  app_private.current_database_time() - interval '3 hours',
  app_private.current_database_time() - interval '3 hours',
  app_private.current_database_time() - interval '20 minutes',
  'dead-worker', app_private.current_database_time() - interval '16 minutes'
), (
  'c3000000-0000-4000-8000-000000000005',
  'c2000000-0000-4000-8000-000000000005',
  'c4000000-0000-4000-8000-000000000005','RUNNING','PLAYABLE_CONTENT','{}',
  1,'gpt-6.1-sol','gpt-6-astra','story-prompt-v1','0.1.0','story-validator-v1',
  app_private.current_database_time() - interval '1 hour',
  app_private.current_database_time() - interval '1 hour',
  app_private.current_database_time() - interval '20 minutes',
  'stale-worker', app_private.current_database_time() - interval '16 minutes'
);
create temporary table reconciliation_result as
select public.reconcile_stale_generation_jobs() as result;
select is(
  (select (result ->> 'failedCount')::integer from reconciliation_result),
  1,
  'exhausted stale generation fails safely instead of creating a second story'
);
select ok(
  (select result -> 'recoverableJobIds' from reconciliation_result)
    @> '["c3000000-0000-4000-8000-000000000005"]'::jsonb,
  'a bounded stale generation checkpoint is returned for provider reconciliation'
);
select is(
  (select status::text from app_private.story_generation_jobs
    where id='c3000000-0000-4000-8000-000000000004'),
  'FAILED',
  'an exhausted stale job reaches one terminal state'
);
select is(
  (select status::text from app_private.rooms
    where id='c2000000-0000-4000-8000-000000000004'),
  'LOBBY',
  'a failed pre-lock room returns to the editable lobby'
);
select ok(
  (select source_purged_at is not null from app_private.story_generation_jobs
    where id='c3000000-0000-4000-8000-000000000004'),
  'terminal stale generation purges its private source snapshot'
);
select ok(
  (select status='RUNNING' and lease_owner is null and lease_expires_at is null
    from app_private.story_generation_jobs
    where id='c3000000-0000-4000-8000-000000000005'),
  'a recoverable checkpoint releases its abandoned lease for one new worker'
);
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
