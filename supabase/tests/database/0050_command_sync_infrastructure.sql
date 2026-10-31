begin;

select plan(55);

create or replace function pg_temp.capture_sqlstate(
  command text,
  force_deferred_constraints boolean default false
)
returns text
language plpgsql
as $function$
begin
  execute command;

  if force_deferred_constraints then
    set constraints all immediate;
    set constraints all deferred;
  end if;

  return null;
exception
  when others then
    if force_deferred_constraints then
      set constraints all deferred;
    end if;

    return sqlstate;
end;
$function$;

select has_table(
  'app_private',
  'command_receipts',
  'command receipts exist'
);
select has_table(
  'app_private',
  'webhook_receipts',
  'webhook receipts exist'
);
select has_table('app_private', 'game_events', 'ordered game events exist');
select has_table('public', 'room_signals', 'content-free room signals exist');

select has_index(
  'app_private',
  'command_receipts',
  'command_receipts_room_created_idx',
  'command receipt lookup is indexed'
);
select has_index(
  'app_private',
  'webhook_receipts',
  'webhook_receipts_room_job_idx',
  'webhook receipt lookup is indexed'
);
select has_index(
  'app_private',
  'game_events',
  'game_events_room_version_sequence_idx',
  'event replay lookup is indexed'
);
select has_index(
  'public',
  'room_signals',
  'room_signals_room_version_created_idx',
  'signal polling lookup is indexed'
);
select has_index(
  'app_private',
  'room_memberships',
  'room_memberships_active_presence_idx',
  'active membership presence is indexed'
);

insert into auth.users (id)
values
  ('a0000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000002'),
  ('a0000000-0000-4000-8000-000000000011'),
  ('a0000000-0000-4000-8000-000000000012');

insert into app_private.rooms (
  id,
  room_code,
  host_auth_user_id,
  state_version
)
values
  (
    'a1000000-0000-4000-8000-000000000001',
    'SYNCA',
    'a0000000-0000-4000-8000-000000000001',
    1
  ),
  (
    'a1000000-0000-4000-8000-000000000002',
    'SYNCB',
    'a0000000-0000-4000-8000-000000000002',
    1
  );

insert into app_private.room_host_principals (
  id,
  room_id,
  auth_user_id
)
values
  (
    'a2000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000001'
  ),
  (
    'a2000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000002'
  );

set constraints all immediate;

insert into app_private.players (
  id,
  room_id,
  display_name,
  display_name_normalized,
  costume,
  seat_order
)
values
  (
    'a3000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'Asha',
    'asha',
    'Detective',
    1
  ),
  (
    'a3000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000002',
    'Ravi',
    'ravi',
    'Magician',
    1
  );

insert into app_private.room_memberships (
  id,
  room_id,
  auth_user_id,
  player_id,
  status,
  request_kind,
  approved_by_auth_user_id,
  joined_at,
  created_at
)
values (
  'a4000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000011',
  'a3000000-0000-4000-8000-000000000001',
  'ACTIVE',
  'INITIAL_CLAIM',
  'a0000000-0000-4000-8000-000000000001',
  '2026-10-30 00:01:00+00',
  '2026-10-30 00:00:00+00'
);

insert into app_private.room_memberships (
  id,
  room_id,
  auth_user_id,
  player_id,
  status,
  request_kind
)
values (
  'a4000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000012',
  'a3000000-0000-4000-8000-000000000001',
  'PENDING',
  'INITIAL_CLAIM'
);

insert into app_private.story_generation_jobs (
  id,
  room_id,
  idempotency_key,
  status,
  phase,
  input_snapshot_json,
  model_id,
  prompt_version,
  story_schema_version,
  validator_version,
  started_at,
  finished_at
)
values
  (
    'a5000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'a5100000-0000-4000-8000-000000000001',
    'FAILED',
    'COMPLETE',
    '{}'::jsonb,
    'gpt-6.1-sol',
    'prompt-v1',
    'story-v1',
    'validator-v1',
    app_private.current_database_time(),
    app_private.current_database_time()
  ),
  (
    'a5000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000002',
    'a5100000-0000-4000-8000-000000000002',
    'FAILED',
    'COMPLETE',
    '{}'::jsonb,
    'gpt-6.1-sol',
    'prompt-v1',
    'story-v1',
    'validator-v1',
    app_private.current_database_time(),
    app_private.current_database_time()
  );

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set state_version = 0
    where id = 'a1000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a room state version cannot decrease'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set state_version = 2
    where id = 'a1000000-0000-4000-8000-000000000002'
  $sql$),
  null,
  'a room state version can increase'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.room_memberships
    set last_seen_at = '2026-10-30 00:02:00+00'
    where id = 'a4000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'an active membership can record a heartbeat'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.room_memberships
    set last_seen_at = '2026-10-30 00:01:30+00'
    where id = 'a4000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a membership heartbeat cannot move backwards'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.room_memberships
    set last_seen_at = app_private.current_database_time()
    where id = 'a4000000-0000-4000-8000-000000000002'
  $sql$),
  '23514',
  'a pending membership cannot record a heartbeat'
);

insert into app_private.command_receipts (
  id,
  room_id,
  idempotency_key,
  command_name,
  actor_type,
  actor_auth_user_id,
  request_hash,
  expected_state_version,
  result_state_version,
  response_status,
  result_json
)
values (
  'a6000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a6100000-0000-4000-8000-000000000001',
  'ADVANCE_ROUND',
  'GAME_MASTER',
  'a0000000-0000-4000-8000-000000000001',
  decode(repeat('11', 32), 'hex'),
  0,
  1,
  200,
  '{"ok":true}'::jsonb
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      room_id, idempotency_key, command_name, actor_type,
      actor_auth_user_id, request_hash, expected_state_version,
      result_state_version, response_status, result_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a6100000-0000-4000-8000-000000000001',
      'ADVANCE_ROUND', 'GAME_MASTER',
      'a0000000-0000-4000-8000-000000000001',
      decode(repeat('11', 32), 'hex'), 0, 1, 200, '{}'::jsonb
    )
  $sql$),
  '23505',
  'duplicate room command idempotency keys fail'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      id, room_id, idempotency_key, command_name, actor_type,
      actor_auth_user_id, request_hash, expected_state_version,
      result_state_version, response_status, result_json
    ) values (
      'a6000000-0000-4000-8000-000000000002',
      'a1000000-0000-4000-8000-000000000002',
      'a6100000-0000-4000-8000-000000000001',
      'ADVANCE_ROUND', 'GAME_MASTER',
      'a0000000-0000-4000-8000-000000000002',
      decode(repeat('22', 32), 'hex'), 1, 2, 200, '{}'::jsonb
    )
  $sql$),
  null,
  'an idempotency key can be reused in a different room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      room_id, idempotency_key, command_name, actor_type,
      request_hash, expected_state_version, result_state_version,
      response_status, result_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a6100000-0000-4000-8000-000000000003',
      'SYSTEM_TASK', 'SYSTEM', decode('11', 'hex'),
      1, 1, 200, '{}'::jsonb
    )
  $sql$),
  '23514',
  'command request hashes must be SHA-256 length'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      room_id, idempotency_key, command_name, actor_type,
      actor_auth_user_id, actor_player_id, request_hash,
      expected_state_version, result_state_version, response_status, result_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a6100000-0000-4000-8000-000000000004',
      'PLAYER_ACTION', 'PLAYER',
      'a0000000-0000-4000-8000-000000000011',
      'a3000000-0000-4000-8000-000000000002',
      decode(repeat('11', 32), 'hex'), 1, 1, 200, '{}'::jsonb
    )
  $sql$),
  '23503',
  'a command actor player cannot come from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      room_id, idempotency_key, command_name, actor_type,
      actor_auth_user_id, request_hash, expected_state_version,
      result_state_version, response_status, result_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a6100000-0000-4000-8000-000000000005',
      'SYSTEM_TASK', 'SYSTEM',
      'a0000000-0000-4000-8000-000000000001',
      decode(repeat('11', 32), 'hex'), 1, 1, 200, '{}'::jsonb
    )
  $sql$),
  '23514',
  'system command receipts cannot contain actor identity'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      room_id, idempotency_key, command_name, actor_type,
      request_hash, expected_state_version, result_state_version,
      response_status, result_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a6100000-0000-4000-8000-000000000006',
      'SYSTEM_TASK', 'SYSTEM', decode(repeat('11', 32), 'hex'),
      1, 1, 200, '[]'::jsonb
    )
  $sql$),
  '23514',
  'command results must be JSON objects'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.command_receipts (
      room_id, idempotency_key, command_name, actor_type,
      request_hash, expected_state_version, result_state_version,
      response_status, result_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a6100000-0000-4000-8000-000000000007',
      'lowercase', 'SYSTEM', decode(repeat('11', 32), 'hex'),
      1, 1, 200, '{}'::jsonb
    )
  $sql$),
  '23514',
  'command names use stable uppercase machine labels'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.command_receipts
    set result_json = '{"changed":true}'::jsonb
    where id = 'a6000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'command receipts cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.command_receipts
    where id = 'a6000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'command receipts cannot be deleted while their room exists'
);

insert into app_private.webhook_receipts (
  id,
  room_id,
  generation_job_id,
  provider,
  provider_event_id,
  event_type,
  payload_hash,
  outcome,
  received_at
)
values (
  'a7000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'openai',
  'evt_sync_1',
  'response.completed',
  decode(repeat('33', 32), 'hex'),
  'PROCESSED',
  '2026-10-30 00:00:00+00'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.webhook_receipts (
      room_id, generation_job_id, provider, provider_event_id,
      event_type, payload_hash, outcome, received_at
    ) values (
      'a1000000-0000-4000-8000-000000000002',
      'a5000000-0000-4000-8000-000000000002',
      'openai', 'evt_sync_1', 'response.completed',
      decode(repeat('33', 32), 'hex'), 'PROCESSED',
      '2026-10-30 00:00:00+00'
    )
  $sql$),
  '23505',
  'duplicate provider webhook event IDs fail globally'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.webhook_receipts (
      room_id, generation_job_id, provider, provider_event_id,
      event_type, payload_hash, outcome, received_at
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000002',
      'openai', 'evt_sync_2', 'response.completed',
      decode(repeat('33', 32), 'hex'), 'PROCESSED',
      '2026-10-30 00:00:00+00'
    )
  $sql$),
  '23503',
  'a webhook receipt cannot reference another room generation job'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.webhook_receipts (
      room_id, generation_job_id, provider, provider_event_id,
      event_type, payload_hash, outcome, received_at
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000001',
      'openai', 'evt_sync_3', 'response.completed',
      decode('33', 'hex'), 'PROCESSED',
      '2026-10-30 00:00:00+00'
    )
  $sql$),
  '23514',
  'webhook payload hashes must be SHA-256 length'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.webhook_receipts (
      room_id, generation_job_id, provider, provider_event_id,
      event_type, payload_hash, outcome, received_at
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000001',
      'openai', 'evt_sync_4', 'response.completed',
      decode(repeat('33', 32), 'hex'), 'RETRY',
      '2026-10-30 00:00:00+00'
    )
  $sql$),
  '23514',
  'webhook outcomes use the bounded receipt vocabulary'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.webhook_receipts
    set outcome = 'IGNORED'
    where id = 'a7000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'webhook receipts cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.webhook_receipts
    where id = 'a7000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'webhook receipts cannot be deleted while their room exists'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      id, room_id, room_sequence, state_version, event_type,
      actor_type, actor_auth_user_id, command_receipt_id
    ) values (
      'a8000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      1, 1, 'ROUND_ADVANCED', 'GAME_MASTER',
      'a0000000-0000-4000-8000-000000000001',
      'a6000000-0000-4000-8000-000000000001'
    )
  $sql$),
  null,
  'the first room event uses sequence one'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type, actor_type
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 1, 'SKIPPED_EVENT', 'SYSTEM'
    )
  $sql$),
  '23514',
  'a room event sequence cannot skip a number'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      id, room_id, room_sequence, state_version, event_type,
      actor_type, actor_auth_user_id, actor_player_id
    ) values (
      'a8000000-0000-4000-8000-000000000002',
      'a1000000-0000-4000-8000-000000000001',
      2, 1, 'PLAYER_UPDATED', 'PLAYER',
      'a0000000-0000-4000-8000-000000000011',
      'a3000000-0000-4000-8000-000000000001'
    )
  $sql$),
  null,
  'the next strict event sequence is accepted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type, actor_type
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 0, 'OLD_VERSION', 'SYSTEM'
    )
  $sql$),
  '23514',
  'event state versions cannot move backwards'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type,
      actor_type, actor_auth_user_id, actor_player_id
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 1, 'PLAYER_UPDATED', 'PLAYER',
      'a0000000-0000-4000-8000-000000000011',
      'a3000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'an event actor player cannot come from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type,
      actor_type, actor_auth_user_id
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 1, 'SYSTEM_EVENT', 'SYSTEM',
      'a0000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23514',
  'system events cannot contain actor identity'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type,
      actor_type, public_metadata_json
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 1, 'SYSTEM_EVENT', 'SYSTEM', '[]'::jsonb
    )
  $sql$),
  '23514',
  'event public metadata must be a JSON object'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type,
      actor_type, command_receipt_id
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 1, 'SYSTEM_EVENT', 'SYSTEM',
      'a6000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'an event cannot reference another room command receipt'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      room_id, room_sequence, state_version, event_type, actor_type
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      3, 2, 'FUTURE_EVENT', 'SYSTEM'
    )
  $sql$, true),
  '23514',
  'an event cannot commit ahead of its room state version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.game_events (
      id, room_id, room_sequence, state_version, event_type, actor_type
    ) values (
      'a8000000-0000-4000-8000-000000000003',
      'a1000000-0000-4000-8000-000000000001',
      3, 1, 'SYSTEM_EVENT', 'SYSTEM'
    )
  $sql$),
  null,
  'a valid third event preserves strict ordering'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.game_events
    set event_type = 'CHANGED'
    where id = 'a8000000-0000-4000-8000-000000000003'
  $sql$),
  '23514',
  'game events cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.game_events
    where id = 'a8000000-0000-4000-8000-000000000003'
  $sql$),
  '23514',
  'game events cannot be deleted while their room exists'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into public.room_signals (
      id, room_id, state_version, change_type
    ) values (
      'a9000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      1, 'ROUND_CHANGED'
    )
  $sql$),
  null,
  'a content-free room signal can record a committed version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into public.room_signals (
      id, room_id, state_version, change_type
    ) values (
      'a9000000-0000-4000-8000-000000000002',
      'a1000000-0000-4000-8000-000000000001',
      1, 'PRESENCE_CHANGED'
    )
  $sql$),
  null,
  'presence invalidation may reuse the gameplay state version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into public.room_signals (
      room_id, state_version, change_type
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      2, 'GAMEPLAY_CHANGED'
    )
  $sql$, true),
  '23514',
  'a signal cannot commit ahead of its room state version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into public.room_signals (
      room_id, state_version, change_type
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      1, 'SOLUTION_PAYLOAD'
    )
  $sql$),
  '23514',
  'room signals accept only broad content-free change labels'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update public.room_signals
    set change_type = 'GAMEPLAY_CHANGED'
    where id = 'a9000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'room signals cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from public.room_signals
    where id = 'a9000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'room signals cannot be deleted while their room exists'
);

select is(
  (
    select pg_catalog.array_agg(c.column_name::text order by c.ordinal_position)
    from information_schema.columns as c
    where c.table_schema = 'public'
      and c.table_name = 'room_signals'
  ),
  array['id', 'room_id', 'state_version', 'change_type', 'created_at']::text[],
  'room signals have no actor, content, metadata, or payload columns'
);

select ok(
  (
    select c.relrowsecurity
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'room_signals'
  ),
  'row-level security is enabled for room signals'
);

select ok(
  not pg_catalog.has_table_privilege('anon', 'public.room_signals', 'SELECT')
  and pg_catalog.has_table_privilege(
    'authenticated',
    'public.room_signals',
    'SELECT'
  ),
  'room signals are selectable only through DB-11 actor-scoped RLS'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon',
    'app_private.command_receipts',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.command_receipts',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'anon',
    'app_private.webhook_receipts',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.game_events',
    'SELECT'
  ),
  'command, webhook, and event records are not directly readable by API roles'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from information_schema.columns as c
    where (
      (c.table_schema = 'app_private' and c.table_name in (
        'command_receipts',
        'webhook_receipts',
        'game_events'
      ))
      or (c.table_schema = 'public' and c.table_name = 'room_signals')
    )
      and c.column_name = 'room_id'
      and c.is_nullable = 'NO'
  ),
  4,
  'every command and synchronization record has a required room scope'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app_private.enforce_game_event_sequence()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.check_record_state_version()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.enforce_room_record_immutable()',
    'EXECUTE'
  ),
  'API roles cannot call internal synchronization trigger functions'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.rooms
    where id = 'a1000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'room retention deletion can cascade append-only infrastructure records'
);

select is(
  (
    select (
      (select pg_catalog.count(*) from app_private.command_receipts
        where room_id = 'a1000000-0000-4000-8000-000000000001')
      + (select pg_catalog.count(*) from app_private.webhook_receipts
        where room_id = 'a1000000-0000-4000-8000-000000000001')
      + (select pg_catalog.count(*) from app_private.game_events
        where room_id = 'a1000000-0000-4000-8000-000000000001')
      + (select pg_catalog.count(*) from public.room_signals
        where room_id = 'a1000000-0000-4000-8000-000000000001')
    )::integer
  ),
  0,
  'no command or synchronization record survives its room deletion'
);

select * from finish();

rollback;
