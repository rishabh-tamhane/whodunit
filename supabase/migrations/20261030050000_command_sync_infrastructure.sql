-- DB-05: command idempotency, ordered events, safe invalidation, and presence.

create type app_private.command_actor_type as enum (
  'GAME_MASTER',
  'PLAYER',
  'SYSTEM'
);

create table app_private.command_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  idempotency_key uuid not null,
  command_name text not null,
  actor_type app_private.command_actor_type not null,
  actor_auth_user_id uuid references auth.users (id) on delete restrict,
  actor_player_id uuid,
  request_hash bytea not null,
  expected_state_version bigint not null,
  result_state_version bigint not null,
  response_status smallint not null,
  result_json jsonb not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint command_receipts_room_id_id_unique unique (room_id, id),
  constraint command_receipts_room_idempotency_unique unique (
    room_id,
    idempotency_key
  ),
  constraint command_receipts_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint command_receipts_actor_player_room_fk foreign key (
    room_id,
    actor_player_id
  ) references app_private.players (room_id, id) on delete restrict,
  constraint command_receipts_command_name check (
    command_name ~ '^[A-Z][A-Z0-9_]{1,99}$'
  ),
  constraint command_receipts_actor_shape check (
    (
      actor_type = 'GAME_MASTER'
      and actor_auth_user_id is not null
      and actor_player_id is null
    )
    or (
      actor_type = 'PLAYER'
      and actor_auth_user_id is not null
      and actor_player_id is not null
    )
    or (
      actor_type = 'SYSTEM'
      and actor_auth_user_id is null
      and actor_player_id is null
    )
  ),
  constraint command_receipts_request_hash_length check (
    pg_catalog.octet_length(request_hash) = 32
  ),
  constraint command_receipts_versions_ordered check (
    expected_state_version >= 0
    and result_state_version >= expected_state_version
  ),
  constraint command_receipts_success_status check (
    response_status between 200 and 299
  ),
  constraint command_receipts_result_object check (
    pg_catalog.jsonb_typeof(result_json) = 'object'
  )
);

create table app_private.webhook_receipts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  generation_job_id uuid not null,
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  payload_hash bytea not null,
  outcome text not null,
  outcome_code text,
  received_at timestamp with time zone not null,
  processed_at timestamp with time zone not null default app_private.current_database_time(),
  constraint webhook_receipts_room_id_id_unique unique (room_id, id),
  constraint webhook_receipts_provider_event_unique unique (
    provider,
    provider_event_id
  ),
  constraint webhook_receipts_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint webhook_receipts_job_room_fk foreign key (
    room_id,
    generation_job_id
  ) references app_private.story_generation_jobs (room_id, id) on delete restrict,
  constraint webhook_receipts_provider_present check (
    pg_catalog.char_length(pg_catalog.btrim(provider)) between 1 and 50
  ),
  constraint webhook_receipts_event_id_present check (
    pg_catalog.char_length(pg_catalog.btrim(provider_event_id)) between 1 and 255
  ),
  constraint webhook_receipts_event_type_present check (
    pg_catalog.char_length(pg_catalog.btrim(event_type)) between 1 and 100
  ),
  constraint webhook_receipts_payload_hash_length check (
    pg_catalog.octet_length(payload_hash) = 32
  ),
  constraint webhook_receipts_outcome_supported check (
    outcome in ('PROCESSED', 'IGNORED')
  ),
  constraint webhook_receipts_outcome_code_length check (
    outcome_code is null
    or pg_catalog.char_length(pg_catalog.btrim(outcome_code)) between 1 and 100
  ),
  constraint webhook_receipts_times_ordered check (
    processed_at >= received_at
  )
);

create table app_private.game_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  room_sequence bigint not null,
  state_version bigint not null,
  event_type text not null,
  actor_type app_private.command_actor_type not null,
  actor_auth_user_id uuid references auth.users (id) on delete restrict,
  actor_player_id uuid,
  source_object_id uuid,
  command_receipt_id uuid,
  public_metadata_json jsonb not null default '{}'::jsonb,
  private_payload_json jsonb,
  occurred_at timestamp with time zone not null default app_private.current_database_time(),
  constraint game_events_room_id_id_unique unique (room_id, id),
  constraint game_events_room_sequence_unique unique (room_id, room_sequence),
  constraint game_events_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint game_events_actor_player_room_fk foreign key (
    room_id,
    actor_player_id
  ) references app_private.players (room_id, id) on delete restrict,
  constraint game_events_command_room_fk foreign key (
    room_id,
    command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint game_events_sequence_positive check (room_sequence > 0),
  constraint game_events_state_version_nonnegative check (state_version >= 0),
  constraint game_events_type_present check (
    event_type ~ '^[A-Z][A-Z0-9_]{1,99}$'
  ),
  constraint game_events_actor_shape check (
    (
      actor_type = 'GAME_MASTER'
      and actor_auth_user_id is not null
      and actor_player_id is null
    )
    or (
      actor_type = 'PLAYER'
      and actor_auth_user_id is not null
      and actor_player_id is not null
    )
    or (
      actor_type = 'SYSTEM'
      and actor_auth_user_id is null
      and actor_player_id is null
    )
  ),
  constraint game_events_public_metadata_object check (
    pg_catalog.jsonb_typeof(public_metadata_json) = 'object'
  ),
  constraint game_events_private_payload_object check (
    private_payload_json is null
    or pg_catalog.jsonb_typeof(private_payload_json) = 'object'
  )
);

-- This is the only table in the exposed schema. It deliberately contains no
-- actor identity, story content, arbitrary metadata, or private payload.
create table public.room_signals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  state_version bigint not null,
  change_type text not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint room_signals_room_id_id_unique unique (room_id, id),
  constraint room_signals_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint room_signals_state_version_nonnegative check (state_version >= 0),
  constraint room_signals_change_type_supported check (
    change_type in (
      'ROOM_STATE_CHANGED',
      'CLAIMS_CHANGED',
      'PLAYER_STATE_CHANGED',
      'PRESENCE_CHANGED',
      'GENERATION_CHANGED',
      'ROUND_CHANGED',
      'GAMEPLAY_CHANGED',
      'ENDGAME_CHANGED'
    )
  )
);

alter table public.room_signals enable row level security;

-- DB-11 adds the narrowly authorized Realtime read policy. Until then, the
-- table remains closed even though its row shape is content-free.
revoke all on table public.room_signals from public, anon, authenticated;

alter table app_private.room_memberships
  add constraint room_memberships_presence_ordered check (
    last_seen_at is null or last_seen_at >= created_at
  );

create index command_receipts_room_created_idx
  on app_private.command_receipts (room_id, created_at desc);
create index webhook_receipts_room_job_idx
  on app_private.webhook_receipts (room_id, generation_job_id, processed_at desc);
create index game_events_room_version_sequence_idx
  on app_private.game_events (room_id, state_version desc, room_sequence desc);
create index room_signals_room_version_created_idx
  on public.room_signals (room_id, state_version desc, created_at desc);
create index room_memberships_active_presence_idx
  on app_private.room_memberships (room_id, last_seen_at)
  where status = 'ACTIVE';

create function app_private.enforce_room_state_version_monotonic()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.state_version < old.state_version then
    raise exception using
      errcode = '23514',
      message = 'room state version cannot decrease',
      constraint = 'rooms_state_version_monotonic';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_membership_presence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.last_seen_at is distinct from old.last_seen_at then
    if new.status <> 'ACTIVE' then
      raise exception using
        errcode = '23514',
        message = 'only an active player membership may record a heartbeat',
        constraint = 'room_memberships_active_presence_only';
    end if;

    if old.last_seen_at is not null and new.last_seen_at < old.last_seen_at then
      raise exception using
        errcode = '23514',
        message = 'player presence timestamp cannot decrease',
        constraint = 'room_memberships_presence_monotonic';
    end if;
  end if;

  return new;
end;
$function$;

create function app_private.enforce_game_event_sequence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_room_version bigint;
  previous_sequence bigint;
  previous_state_version bigint;
begin
  perform app_private.lock_room(new.room_id);

  select r.state_version
  into current_room_version
  from app_private.rooms as r
  where r.id = new.room_id;

  if not found then
    raise exception using
      errcode = '23503',
      message = 'event room does not exist',
      constraint = 'game_events_room_fk';
  end if;

  select e.room_sequence, e.state_version
  into previous_sequence, previous_state_version
  from app_private.game_events as e
  where e.room_id = new.room_id
  order by e.room_sequence desc
  limit 1;

  if new.room_sequence <> coalesce(previous_sequence, 0) + 1 then
    raise exception using
      errcode = '23514',
      message = 'game event sequence must be the next room sequence',
      constraint = 'game_events_strict_room_sequence';
  end if;

  if previous_state_version is not null
    and new.state_version < previous_state_version then
    raise exception using
      errcode = '23514',
      message = 'game event state version cannot move backwards',
      constraint = 'game_events_state_version_monotonic';
  end if;

  if new.state_version > current_room_version + 1 then
    raise exception using
      errcode = '23514',
      message = 'game event state version cannot skip ahead of its room',
      constraint = 'game_events_state_version_bounded';
  end if;

  return new;
end;
$function$;

create function app_private.check_record_state_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_room_version bigint;
begin
  select r.state_version
  into current_room_version
  from app_private.rooms as r
  where r.id = new.room_id;

  -- Cascading room deletion may remove a just-created record in the same
  -- transaction. There is no surviving invariant to check in that case.
  if not found then
    return null;
  end if;

  if new.state_version > current_room_version then
    raise exception using
      errcode = '23514',
      message = 'record state version cannot exceed the committed room version',
      constraint = 'room_scoped_record_state_version_current';
  end if;

  return null;
end;
$function$;

create function app_private.enforce_room_record_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' then
    raise exception using
      errcode = '23514',
      message = 'append-only room record cannot be updated',
      constraint = 'room_record_append_only';
  end if;

  if exists (
    select 1 from app_private.rooms as r where r.id = old.room_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'append-only room record cannot be deleted while its room exists',
      constraint = 'room_record_append_only';
  end if;

  return old;
end;
$function$;

create trigger rooms_enforce_state_version_monotonic
before update of state_version on app_private.rooms
for each row execute function app_private.enforce_room_state_version_monotonic();

create trigger room_memberships_enforce_presence
before update of last_seen_at, status on app_private.room_memberships
for each row execute function app_private.enforce_membership_presence();

create trigger game_events_enforce_sequence
before insert on app_private.game_events
for each row execute function app_private.enforce_game_event_sequence();

create constraint trigger game_events_check_state_version
after insert on app_private.game_events
deferrable initially deferred
for each row execute function app_private.check_record_state_version();

create constraint trigger room_signals_check_state_version
after insert on public.room_signals
deferrable initially deferred
for each row execute function app_private.check_record_state_version();

create trigger command_receipts_immutable
before update or delete on app_private.command_receipts
for each row execute function app_private.enforce_room_record_immutable();

create trigger webhook_receipts_immutable
before update or delete on app_private.webhook_receipts
for each row execute function app_private.enforce_room_record_immutable();

create trigger game_events_immutable
before update or delete on app_private.game_events
for each row execute function app_private.enforce_room_record_immutable();

create trigger room_signals_immutable
before update or delete on public.room_signals
for each row execute function app_private.enforce_room_record_immutable();

revoke all on function app_private.enforce_room_state_version_monotonic()
  from public, anon, authenticated;
revoke all on function app_private.enforce_membership_presence()
  from public, anon, authenticated;
revoke all on function app_private.enforce_game_event_sequence()
  from public, anon, authenticated;
revoke all on function app_private.check_record_state_version()
  from public, anon, authenticated;
revoke all on function app_private.enforce_room_record_immutable()
  from public, anon, authenticated;

comment on table app_private.command_receipts is
  'Immutable successful command results keyed by a room-scoped idempotency key.';
comment on table app_private.webhook_receipts is
  'Immutable provider-event receipts used to reject webhook replays.';
comment on table app_private.game_events is
  'Append-only, strictly ordered room history; private payloads never enter Realtime.';
comment on table public.room_signals is
  'Content-free Realtime invalidation rows; DB-11 owns authorized read policy.';
