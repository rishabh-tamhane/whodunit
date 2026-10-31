begin;
select no_plan();

select has_table(
  'app_private','ai_call_reservations',
  'content-free model-call reservations are durable'
);
select has_function(
  'public','reserve_ai_call',array['uuid','uuid','text','text','bigint'],
  'atomic spend and concurrency reservation command exists'
);
select has_function(
  'public','settle_ai_call',
  array['uuid','text','integer','integer','bigint','text'],
  'model-call settlement command exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.reserve_ai_call(uuid,uuid,text,text,bigint)',
    'EXECUTE'
  ),
  'clients cannot reserve model spend directly'
);

insert into auth.users (id) values ('d1000000-0000-4000-8000-000000000001');
insert into app_private.rooms (
  id,room_code,host_auth_user_id,status,created_at,updated_at
)
select
  ('d2000000-0000-4000-8000-' || pg_catalog.lpad(sequence::text,12,'0'))::uuid,
  'BUDG' || pg_catalog.lpad(sequence::text,4,'0'),
  'd1000000-0000-4000-8000-000000000001'::uuid,
  'LOBBY',app_private.current_database_time(),app_private.current_database_time()
from pg_catalog.generate_series(1,12) as sequence;

select set_config('request.jwt.claims','{"role":"service_role"}',true);
create temporary table first_reservation as
select public.reserve_ai_call(
  'd2000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'STORY','gpt-6-astra',1700000
) as result;
select is(
  (select result->>'allowed' from first_reservation),'true',
  'the first call within all budgets is reserved'
);
select lives_ok(
  $$select public.settle_ai_call(
    (select (result->>'reservationId')::uuid from first_reservation),
    'response-budget-1',1000,2000,110000,'COMPLETED'
  )$$,
  'a reservation settles with content-free usage and cost'
);
select is(
  (select status from app_private.ai_call_reservations
    where provider_response_id='response-budget-1'),
  'COMPLETED',
  'the settled ledger entry is terminal'
);

-- Force the room total close to its hard cap without storing room content.
insert into app_private.ai_call_reservations (
  correlation_id,room_hash,call_kind,model_id,status,
  reserved_cost_microusd,actual_cost_microusd,input_tokens,output_tokens,
  settled_at
) values (
  'd3000000-0000-4000-8000-000000000002',
  pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
    'd2000000-0000-4000-8000-000000000001','UTF8'
  ),'sha256'),'hex'),
  'STORY','gpt-6.1-sol','COMPLETED',2800000,2800000,0,0,
  app_private.current_database_time()
);
select is(
  public.reserve_ai_call(
    'd2000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000003',
    'INTERVENTION','gpt-6.1-sol',100000
  )->>'reason',
  'ROOM_HARD_CAP',
  'a room cannot reserve above its three-dollar hard cap'
);

-- Ten different rooms can hold story calls; the eleventh is denied globally.
select public.reserve_ai_call(
  ('d2000000-0000-4000-8000-' || pg_catalog.lpad(sequence::text,12,'0'))::uuid,
  pg_catalog.gen_random_uuid(),'STORY','gpt-6.1-sol',1000
)
from pg_catalog.generate_series(2,11) as sequence;
select is(
  public.reserve_ai_call(
    'd2000000-0000-4000-8000-000000000012',
    'd3000000-0000-4000-8000-000000000012',
    'STORY','gpt-6.1-sol',1000
  )->>'reason',
  'STORY_CONCURRENCY_CAP',
  'the eleventh concurrent story model call is denied'
);

select throws_ok(
  $$insert into app_private.operational_events (
    correlation_id,event_type,severity,metadata_json
  ) values (
    pg_catalog.gen_random_uuid(),'UNSAFE_BUDGET_EVENT','INFO',
    '{"prompt":"private"}'::jsonb
  )$$,
  '23514',
  'new row for relation "operational_events" violates check constraint "operational_events_metadata_allowlist"',
  'the expanded telemetry allowlist still rejects private payload fields'
);

select * from finish();
rollback;
