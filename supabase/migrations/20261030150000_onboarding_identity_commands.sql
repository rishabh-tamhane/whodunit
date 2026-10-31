-- IDN-06/08/10/12/13/15/16: claims, recovery, consent, readiness, and presence.

create unique index room_memberships_one_pending_request_per_user_idx
  on app_private.room_memberships (room_id, auth_user_id)
  where status = 'PENDING';

create unique index host_recovery_tokens_digest_unique_idx
  on app_private.host_recovery_tokens (token_digest);

alter table app_private.player_descriptions
  drop constraint player_descriptions_content_state,
  add column response_status text not null default 'SUBMITTED',
  add constraint player_descriptions_response_status check (
    response_status in ('SUBMITTED', 'DECLINED')
  ),
  add constraint player_descriptions_content_state check (
    (
      purged_at is null
      and response_status = 'SUBMITTED'
      and description_text is not null
      and pg_catalog.char_length(pg_catalog.btrim(description_text)) between 1 and 500
    )
    or (
      purged_at is null
      and response_status = 'DECLINED'
      and description_text is null
    )
    or (purged_at is not null and description_text is null)
  );

create or replace view app_private.room_readiness_inputs
with (security_invoker = true)
as
select
  r.id as room_id,
  (
    select pg_catalog.count(*)
    from app_private.players as p
    where p.room_id = r.id
  ) as player_count,
  (
    select pg_catalog.count(*)
    from app_private.room_memberships as m
    where m.room_id = r.id and m.status = 'ACTIVE'
  ) as active_membership_count,
  (
    select pg_catalog.count(*)
    from app_private.players as p
    where p.room_id = r.id
      and p.fictional_use_acknowledged_at is not null
  ) as acknowledged_player_count,
  (
    select pg_catalog.count(*)
    from app_private.player_descriptions as d
    where d.room_id = r.id and d.purged_at is null
  ) as submitted_description_count,
  r.host_guidance_acknowledged_at is not null as host_guidance_acknowledged,
  r.room_consent_confirmed_at is not null as room_consent_confirmed
from app_private.rooms as r;

create function app_private.append_identity_event(
  target_room_id uuid,
  target_state_version bigint,
  event_name text,
  event_actor_type app_private.command_actor_type,
  event_actor_auth_user_id uuid,
  event_actor_player_id uuid,
  event_source_id uuid,
  signal_type text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  next_sequence bigint;
begin
  select coalesce(pg_catalog.max(event.room_sequence), 0) + 1
  into next_sequence
  from app_private.game_events as event
  where event.room_id = target_room_id;

  insert into app_private.game_events (
    room_id,
    room_sequence,
    state_version,
    event_type,
    actor_type,
    actor_auth_user_id,
    actor_player_id,
    source_object_id
  ) values (
    target_room_id,
    next_sequence,
    target_state_version,
    event_name,
    event_actor_type,
    event_actor_auth_user_id,
    event_actor_player_id,
    event_source_id
  );

  insert into public.room_signals (room_id, state_version, change_type)
  values (target_room_id, target_state_version, signal_type);
end;
$function$;

create function app_private.calculate_room_readiness(target_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with inputs as (
    select
      readiness.*,
      readiness.player_count * (readiness.player_count - 1) as required_descriptions,
      room.status,
      room.duration_profile_version,
      room.config_json,
      room.locked_at
    from app_private.room_readiness_inputs as readiness
    join app_private.rooms as room on room.id = readiness.room_id
    where readiness.room_id = target_room_id
  )
  select pg_catalog.jsonb_build_object(
    'ready',
      player_count between 4 and 12
      and active_membership_count = player_count
      and acknowledged_player_count = player_count
      and submitted_description_count = required_descriptions
      and host_guidance_acknowledged
      and room_consent_confirmed
      and status = 'LOBBY'
      and duration_profile_version is not null
      and config_json ->> 'setupLocked' = 'true'
      and locked_at is null,
    'playerCount', player_count,
    'activeMembershipCount', active_membership_count,
    'acknowledgedPlayerCount', acknowledged_player_count,
    'completedDescriptionCount', submitted_description_count,
    'requiredDescriptionCount', required_descriptions,
    'hostGuidanceAcknowledged', host_guidance_acknowledged,
    'roomConsentConfirmed', room_consent_confirmed,
    'configurationValid',
      player_count between 4 and 12
      and duration_profile_version is not null
      and config_json ->> 'setupLocked' = 'true',
    'missing', pg_catalog.jsonb_build_object(
      'claims', greatest(player_count - active_membership_count, 0::bigint),
      'playerAcknowledgements',
        greatest(player_count - acknowledged_player_count, 0::bigint),
      'descriptions',
        greatest(required_descriptions - submitted_description_count, 0::bigint),
      'hostGuidance', not host_guidance_acknowledged,
      'roomConsent', not room_consent_confirmed
    )
  )
  from inputs;
$function$;

create function public.request_player_claim(
  target_room_id uuid,
  target_player_id uuid,
  requested_kind text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  room_record app_private.rooms%rowtype;
  existing_request app_private.room_memberships%rowtype;
  active_membership app_private.room_memberships%rowtype;
  created_membership app_private.room_memberships%rowtype;
  next_version bigint;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'authenticated guest session required';
  end if;

  perform app_private.lock_room(target_room_id);
  select room.* into strict room_record
  from app_private.rooms as room where room.id = target_room_id;

  if not exists (
    select 1 from app_private.players as player
    where player.room_id = target_room_id and player.id = target_player_id
  ) then
    raise exception using errcode = '23503', message = 'player slot not found';
  end if;

  if exists (
    select 1 from app_private.room_host_principals as principal
    where principal.room_id = target_room_id
      and principal.auth_user_id = caller_id
  ) then
    raise exception using errcode = '42501', message = 'Game Master principals cannot claim player slots';
  end if;

  select membership.* into existing_request
  from app_private.room_memberships as membership
  where membership.room_id = target_room_id
    and membership.auth_user_id = caller_id
    and membership.status = 'PENDING';

  if found then
    if existing_request.player_id = target_player_id
      and existing_request.request_kind::text = requested_kind then
      return pg_catalog.jsonb_build_object(
        'claimId', existing_request.id,
        'roomId', existing_request.room_id,
        'playerId', existing_request.player_id,
        'status', existing_request.status::text,
        'requestKind', existing_request.request_kind::text,
        'stateVersion', room_record.state_version::text,
        'replayed', true
      );
    end if;
    raise exception using errcode = '23505', message = 'this device already has a pending request';
  end if;

  if requested_kind = 'INITIAL_CLAIM' then
    if room_record.status not in ('DRAFT', 'LOBBY') then
      raise exception using errcode = '55000', message = 'initial claims are closed';
    end if;
    if exists (
      select 1 from app_private.room_memberships as membership
      where membership.room_id = target_room_id
        and membership.player_id = target_player_id
        and membership.status = 'ACTIVE'
    ) then
      raise exception using errcode = '23505', message = 'player slot is already occupied';
    end if;
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, request_kind
    ) values (
      target_room_id, caller_id, target_player_id, 'INITIAL_CLAIM'
    ) returning * into created_membership;
  elsif requested_kind = 'RECONNECT' then
    select membership.* into active_membership
    from app_private.room_memberships as membership
    where membership.room_id = target_room_id
      and membership.player_id = target_player_id
      and membership.status = 'ACTIVE'
    for update;

    if not found then
      raise exception using errcode = '55000', message = 'there is no active device to replace';
    end if;
    if active_membership.auth_user_id = caller_id then
      raise exception using errcode = '23505', message = 'this device is already active';
    end if;

    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, request_kind, replaces_membership_id
    ) values (
      target_room_id, caller_id, target_player_id, 'RECONNECT', active_membership.id
    ) returning * into created_membership;
  else
    raise exception using errcode = '22023', message = 'invalid claim kind';
  end if;

  update app_private.rooms
  set state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id
  returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'PLAYER_CLAIM_REQUESTED', 'PLAYER',
    caller_id, target_player_id, created_membership.id, 'CLAIMS_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'claimId', created_membership.id,
    'roomId', created_membership.room_id,
    'playerId', created_membership.player_id,
    'status', created_membership.status::text,
    'requestKind', created_membership.request_kind::text,
    'stateVersion', next_version::text,
    'replayed', false
  );
end;
$function$;

create function public.review_player_claim(
  target_room_id uuid,
  target_claim_id uuid,
  expected_state_version bigint,
  decision text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  room_record app_private.rooms%rowtype;
  claim_record app_private.room_memberships%rowtype;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);

  select room.* into strict room_record
  from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;

  select membership.* into strict claim_record
  from app_private.room_memberships as membership
  where membership.room_id = target_room_id
    and membership.id = target_claim_id
  for update;

  if claim_record.status <> 'PENDING' then
    raise exception using errcode = '55000', message = 'claim request is no longer pending';
  end if;

  if decision = 'REJECT' then
    update app_private.room_memberships
    set status = 'REVOKED',
        revoked_at = app_private.current_database_time(),
        updated_at = app_private.current_database_time()
    where id = claim_record.id;
  elsif decision = 'APPROVE' then
    if claim_record.request_kind = 'INITIAL_CLAIM'
      and room_record.status not in ('DRAFT', 'LOBBY') then
      raise exception using errcode = '55000', message = 'initial claims are closed';
    end if;

    if claim_record.request_kind = 'RECONNECT' then
      update app_private.room_memberships
      set status = 'REVOKED',
          revoked_at = app_private.current_database_time(),
          updated_at = app_private.current_database_time()
      where room_id = target_room_id
        and id = claim_record.replaces_membership_id
        and status = 'ACTIVE';
      if not found then
        raise exception using errcode = '55000', message = 'the device being replaced is no longer active';
      end if;
    elsif exists (
      select 1 from app_private.room_memberships as active
      where active.room_id = target_room_id
        and active.player_id = claim_record.player_id
        and active.status = 'ACTIVE'
    ) then
      raise exception using errcode = '23505', message = 'player slot is already occupied';
    end if;

    update app_private.room_memberships
    set status = 'REVOKED',
        revoked_at = app_private.current_database_time(),
        updated_at = app_private.current_database_time()
    where room_id = target_room_id
      and player_id = claim_record.player_id
      and status = 'PENDING'
      and id <> claim_record.id;

    update app_private.room_memberships
    set status = 'ACTIVE',
        approved_by_auth_user_id = caller_id,
        joined_at = app_private.current_database_time(),
        last_seen_at = app_private.current_database_time(),
        updated_at = app_private.current_database_time()
    where id = claim_record.id;
  else
    raise exception using errcode = '22023', message = 'invalid claim decision';
  end if;

  update app_private.rooms
  set state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id
  returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version,
    case when decision = 'APPROVE' then 'PLAYER_CLAIM_APPROVED' else 'PLAYER_CLAIM_REJECTED' end,
    'GAME_MASTER', caller_id, null, claim_record.id, 'CLAIMS_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'claimId', claim_record.id,
    'roomId', target_room_id,
    'playerId', claim_record.player_id,
    'status', case when decision = 'APPROVE' then 'ACTIVE' else 'REVOKED' end,
    'requestKind', claim_record.request_kind::text,
    'stateVersion', next_version::text
  );
end;
$function$;

create function public.revoke_player_membership(
  target_room_id uuid,
  target_membership_id uuid,
  expected_state_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  membership_record app_private.room_memberships%rowtype;
  current_version bigint;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  select state_version into strict current_version
  from app_private.rooms where id = target_room_id;
  if current_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;

  select membership.* into strict membership_record
  from app_private.room_memberships as membership
  where membership.room_id = target_room_id
    and membership.id = target_membership_id
  for update;
  if membership_record.status <> 'ACTIVE' then
    raise exception using errcode = '55000', message = 'membership is not active';
  end if;

  update app_private.room_memberships
  set status = 'REVOKED',
      revoked_at = app_private.current_database_time(),
      updated_at = app_private.current_database_time()
  where id = target_membership_id;

  update app_private.rooms
  set state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'PLAYER_MEMBERSHIP_REVOKED',
    'GAME_MASTER', caller_id, null, membership_record.id, 'CLAIMS_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'membershipId', membership_record.id,
    'playerId', membership_record.player_id,
    'status', 'REVOKED',
    'stateVersion', next_version::text
  );
end;
$function$;

create function public.record_player_heartbeat(target_room_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  authorized_player_id uuid;
  membership_record app_private.room_memberships%rowtype;
  changed boolean := false;
  current_version bigint;
begin
  authorized_player_id := app_private.assert_active_player(target_room_id);
  select membership.* into strict membership_record
  from app_private.room_memberships as membership
  where membership.room_id = target_room_id
    and membership.auth_user_id = caller_id
    and membership.status = 'ACTIVE'
  for update;

  if membership_record.last_seen_at is null
    or membership_record.last_seen_at < app_private.current_database_time() - interval '20 seconds' then
    update app_private.room_memberships
    set last_seen_at = app_private.current_database_time(),
        updated_at = app_private.current_database_time()
    where id = membership_record.id
    returning * into membership_record;
    changed := true;
  end if;

  select state_version into current_version
  from app_private.rooms where id = target_room_id;
  if changed then
    insert into public.room_signals (room_id, state_version, change_type)
    values (target_room_id, current_version, 'PRESENCE_CHANGED');
  end if;

  return pg_catalog.jsonb_build_object(
    'playerId', authorized_player_id,
    'lastSeenAt', membership_record.last_seen_at,
    'rateLimited', not changed
  );
end;
$function$;

create function public.acknowledge_player_fictional_use(
  target_room_id uuid,
  expected_state_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  authorized_player_id uuid;
  room_record app_private.rooms%rowtype;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  authorized_player_id := app_private.assert_active_player(target_room_id);
  select room.* into strict room_record from app_private.rooms as room
  where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'LOBBY' or room_record.locked_at is not null then
    raise exception using errcode = '55000', message = 'acknowledgements are closed';
  end if;

  update app_private.players
  set fictional_use_acknowledged_at = coalesce(
        fictional_use_acknowledged_at,
        app_private.current_database_time()
      ),
      updated_at = app_private.current_database_time()
  where room_id = target_room_id and id = authorized_player_id;

  update app_private.rooms
  set state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'PLAYER_FICTIONAL_USE_ACKNOWLEDGED',
    'PLAYER', caller_id, authorized_player_id, authorized_player_id,
    'PLAYER_STATE_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'playerId', authorized_player_id,
    'acknowledged', true,
    'stateVersion', next_version::text
  );
end;
$function$;

create function public.acknowledge_game_master_guidance(
  target_room_id uuid,
  expected_state_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  room_record app_private.rooms%rowtype;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  select room.* into strict room_record from app_private.rooms as room
  where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'LOBBY' or room_record.locked_at is not null then
    raise exception using errcode = '55000', message = 'Game Master guidance acknowledgement is closed';
  end if;

  update app_private.rooms
  set host_guidance_acknowledged_at = coalesce(
        host_guidance_acknowledged_at,
        app_private.current_database_time()
      ),
      state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'GAME_MASTER_GUIDANCE_ACKNOWLEDGED',
    'GAME_MASTER', caller_id, null, target_room_id, 'PLAYER_STATE_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'hostGuidanceAcknowledged', true,
    'stateVersion', next_version::text
  );
end;
$function$;

create function public.confirm_room_consent(
  target_room_id uuid,
  expected_state_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  room_record app_private.rooms%rowtype;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  select room.* into strict room_record from app_private.rooms as room
  where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'LOBBY' or room_record.locked_at is not null then
    raise exception using errcode = '55000', message = 'room consent is closed';
  end if;

  update app_private.rooms
  set room_consent_confirmed_at = coalesce(
        room_consent_confirmed_at,
        app_private.current_database_time()
      ),
      state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'ROOM_CONSENT_CONFIRMED',
    'GAME_MASTER', caller_id, null, target_room_id, 'PLAYER_STATE_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'roomConsentConfirmed', true,
    'stateVersion', next_version::text
  );
end;
$function$;

create function public.save_player_description(
  target_room_id uuid,
  target_subject_player_id uuid,
  target_response_status text,
  target_description_text text,
  expected_state_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  author_id uuid;
  room_record app_private.rooms%rowtype;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  author_id := app_private.assert_active_player(target_room_id);
  select room.* into strict room_record from app_private.rooms as room
  where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'LOBBY' or room_record.locked_at is not null then
    raise exception using errcode = '55000', message = 'description editing is closed';
  end if;
  if author_id = target_subject_player_id
    or not exists (
      select 1 from app_private.players as subject
      where subject.room_id = target_room_id
        and subject.id = target_subject_player_id
    ) then
    raise exception using errcode = '22023', message = 'invalid description subject';
  end if;
  if target_response_status = 'SUBMITTED' then
    target_description_text := pg_catalog.btrim(target_description_text);
    if pg_catalog.char_length(target_description_text) not between 1 and 500 then
      raise exception using errcode = '22023', message = 'description must contain 1 to 500 characters';
    end if;
  elsif target_response_status = 'DECLINED' then
    target_description_text := null;
  else
    raise exception using errcode = '22023', message = 'invalid description response';
  end if;

  insert into app_private.player_descriptions (
    room_id, author_player_id, subject_player_id, description_text,
    response_status
  ) values (
    target_room_id, author_id, target_subject_player_id,
    target_description_text, target_response_status
  )
  on conflict (room_id, author_player_id, subject_player_id)
  do update set
    description_text = excluded.description_text,
    response_status = excluded.response_status,
    submitted_at = app_private.current_database_time(),
    updated_at = app_private.current_database_time(),
    purged_at = null;

  update app_private.rooms
  set state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'PLAYER_DESCRIPTION_COMPLETED',
    'PLAYER', caller_id, author_id, target_subject_player_id,
    'PLAYER_STATE_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'authorPlayerId', author_id,
    'subjectPlayerId', target_subject_player_id,
    'responseStatus', target_response_status,
    'stateVersion', next_version::text
  );
end;
$function$;

create function public.get_room_readiness(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  perform app_private.assert_current_game_master(target_room_id);
  return app_private.calculate_room_readiness(target_room_id);
end;
$function$;

create function public.get_onboarding_view(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  player_id uuid;
  pending_membership app_private.room_memberships%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'authenticated guest session required';
  end if;

  if app_private.is_current_game_master(target_room_id) then
    return pg_catalog.jsonb_build_object(
      'actor', 'GAME_MASTER',
      'room', (
        select pg_catalog.jsonb_build_object(
          'id', room.id,
          'roomCode', room.room_code,
          'status', room.status::text,
          'stateVersion', room.state_version::text,
          'config', room.config_json
        ) from app_private.rooms as room where room.id = target_room_id
      ),
      'players', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'playerId', player.id,
            'displayName', player.display_name,
            'costume', player.costume,
            'seatOrder', player.seat_order,
            'acknowledged', player.fictional_use_acknowledged_at is not null,
            'claimStatus', case
              when active.id is not null and active.last_seen_at >= app_private.current_database_time() - interval '90 seconds' then 'CONNECTED'
              when active.id is not null then 'DISCONNECTED'
              when pending.id is not null then 'PENDING'
              else 'UNCLAIMED'
            end,
            'activeMembershipId', active.id
          ) order by player.seat_order
        )
        from app_private.players as player
        left join lateral (
          select membership.id, membership.last_seen_at
          from app_private.room_memberships as membership
          where membership.room_id = player.room_id
            and membership.player_id = player.id
            and membership.status = 'ACTIVE'
          limit 1
        ) as active on true
        left join lateral (
          select membership.id
          from app_private.room_memberships as membership
          where membership.room_id = player.room_id
            and membership.player_id = player.id
            and membership.status = 'PENDING'
          order by membership.created_at limit 1
        ) as pending on true
        where player.room_id = target_room_id
      ), '[]'::jsonb),
      'claims', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'claimId', membership.id,
            'playerId', membership.player_id,
            'requestKind', membership.request_kind::text,
            'status', membership.status::text,
            'createdAt', membership.created_at
          ) order by membership.created_at
        )
        from app_private.room_memberships as membership
        where membership.room_id = target_room_id
          and membership.status = 'PENDING'
      ), '[]'::jsonb),
      'readiness', app_private.calculate_room_readiness(target_room_id)
    );
  end if;

  player_id := app_private.active_player_id(target_room_id);
  if player_id is not null then
    return pg_catalog.jsonb_build_object(
      'actor', 'PLAYER',
      'room', (
        select pg_catalog.jsonb_build_object(
          'id', room.id,
          'roomCode', room.room_code,
          'status', room.status::text,
          'stateVersion', room.state_version::text
        ) from app_private.rooms as room where room.id = target_room_id
      ),
      'self', (
        select pg_catalog.jsonb_build_object(
          'playerId', player.id,
          'displayName', player.display_name,
          'costume', player.costume,
          'acknowledged', player.fictional_use_acknowledged_at is not null
        ) from app_private.players as player
        where player.room_id = target_room_id and player.id = player_id
      ),
      'players', (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'playerId', player.id,
            'displayName', player.display_name,
            'costume', player.costume,
            'seatOrder', player.seat_order
          ) order by player.seat_order
        ) from app_private.players as player where player.room_id = target_room_id
      ),
      'descriptionResponses', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'subjectPlayerId', description.subject_player_id,
            'responseStatus', description.response_status,
            'descriptionText', description.description_text
          ) order by subject.seat_order
        )
        from app_private.player_descriptions as description
        join app_private.players as subject
          on subject.room_id = description.room_id
          and subject.id = description.subject_player_id
        where description.room_id = target_room_id
          and description.author_player_id = player_id
          and description.purged_at is null
      ), '[]'::jsonb)
    );
  end if;

  select membership.* into pending_membership
  from app_private.room_memberships as membership
  where membership.room_id = target_room_id
    and membership.auth_user_id = caller_id
    and membership.status = 'PENDING';
  if found then
    return pg_catalog.jsonb_build_object(
      'actor', 'PENDING_PLAYER',
      'roomId', target_room_id,
      'claim', pg_catalog.jsonb_build_object(
        'claimId', pending_membership.id,
        'playerId', pending_membership.player_id,
        'requestKind', pending_membership.request_kind::text,
        'status', pending_membership.status::text
      )
    );
  end if;

  raise exception using errcode = '42501', message = 'room membership required';
end;
$function$;

create function public.recover_game_master(
  recovery_token_digest bytea,
  replacement_token_digest bytea,
  replacement_expires_at timestamp with time zone
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  token_record app_private.host_recovery_tokens%rowtype;
  room_record app_private.rooms%rowtype;
  next_version bigint;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'authenticated guest session required';
  end if;
  if pg_catalog.octet_length(recovery_token_digest) <> 32
    or pg_catalog.octet_length(replacement_token_digest) <> 32
    or replacement_expires_at <= app_private.current_database_time()
  then
    raise exception using errcode = '22023', message = 'invalid recovery credential';
  end if;

  select token.* into token_record
  from app_private.host_recovery_tokens as token
  where token.token_digest = recovery_token_digest
    and token.consumed_at is null
    and token.revoked_at is null
    and token.expires_at > app_private.current_database_time();
  if not found then
    raise exception using errcode = '42501', message = 'recovery credential is invalid or expired';
  end if;

  perform app_private.lock_room(token_record.room_id);
  select token.* into strict token_record
  from app_private.host_recovery_tokens as token
  where token.id = token_record.id
    and token.consumed_at is null
    and token.revoked_at is null
    and token.expires_at > app_private.current_database_time()
  for update;

  if exists (
    select 1 from app_private.room_memberships as membership
    where membership.room_id = token_record.room_id
      and membership.auth_user_id = caller_id
  ) or exists (
    select 1 from app_private.room_host_principals as principal
    where principal.room_id = token_record.room_id
      and principal.auth_user_id = caller_id
  ) then
    raise exception using errcode = '42501', message = 'recovery requires a clean guest session';
  end if;

  select room.* into strict room_record from app_private.rooms as room
  where room.id = token_record.room_id;

  update app_private.room_host_principals
  set ended_at = app_private.current_database_time()
  where room_id = room_record.id and ended_at is null;
  update app_private.rooms
  set host_auth_user_id = caller_id,
      state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = room_record.id returning state_version into next_version;
  insert into app_private.room_host_principals (room_id, auth_user_id)
  values (room_record.id, caller_id);
  update app_private.host_recovery_tokens
  set consumed_at = app_private.current_database_time()
  where id = token_record.id;
  insert into app_private.host_recovery_tokens (
    room_id, token_digest, token_version, expires_at
  ) values (
    room_record.id, replacement_token_digest,
    token_record.token_version + 1, replacement_expires_at
  );

  perform app_private.append_identity_event(
    room_record.id, next_version, 'GAME_MASTER_RECOVERED',
    'GAME_MASTER', caller_id, null, room_record.id, 'ROOM_STATE_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'roomId', room_record.id,
    'roomCode', room_record.room_code,
    'status', room_record.status::text,
    'stateVersion', next_version::text,
    'recoveryExpiresAt', replacement_expires_at
  );
end;
$function$;

create function public.rotate_game_master_recovery(
  target_room_id uuid,
  replacement_token_digest bytea,
  replacement_expires_at timestamp with time zone
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  active_version integer;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  if pg_catalog.octet_length(replacement_token_digest) <> 32
    or replacement_expires_at <= app_private.current_database_time() then
    raise exception using errcode = '22023', message = 'invalid recovery credential';
  end if;

  select coalesce(pg_catalog.max(token.token_version), 0) into active_version
  from app_private.host_recovery_tokens as token
  where token.room_id = target_room_id;
  update app_private.host_recovery_tokens
  set revoked_at = app_private.current_database_time()
  where room_id = target_room_id
    and consumed_at is null and revoked_at is null;
  insert into app_private.host_recovery_tokens (
    room_id, token_digest, token_version, expires_at
  ) values (
    target_room_id, replacement_token_digest, active_version + 1,
    replacement_expires_at
  );

  return pg_catalog.jsonb_build_object(
    'roomId', target_room_id,
    'recoveryExpiresAt', replacement_expires_at
  );
end;
$function$;

revoke all on function app_private.append_identity_event(uuid,bigint,text,app_private.command_actor_type,uuid,uuid,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function app_private.calculate_room_readiness(uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.request_player_claim(uuid,uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.review_player_claim(uuid,uuid,bigint,text) from public, anon, authenticated, service_role;
revoke all on function public.revoke_player_membership(uuid,uuid,bigint) from public, anon, authenticated, service_role;
revoke all on function public.record_player_heartbeat(uuid) from public, anon, authenticated, service_role;
revoke all on function public.acknowledge_player_fictional_use(uuid,bigint) from public, anon, authenticated, service_role;
revoke all on function public.acknowledge_game_master_guidance(uuid,bigint) from public, anon, authenticated, service_role;
revoke all on function public.confirm_room_consent(uuid,bigint) from public, anon, authenticated, service_role;
revoke all on function public.save_player_description(uuid,uuid,text,text,bigint) from public, anon, authenticated, service_role;
revoke all on function public.get_room_readiness(uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_onboarding_view(uuid) from public, anon, authenticated, service_role;
revoke all on function public.recover_game_master(bytea,bytea,timestamp with time zone) from public, anon, authenticated, service_role;
revoke all on function public.rotate_game_master_recovery(uuid,bytea,timestamp with time zone) from public, anon, authenticated, service_role;

grant execute on function public.request_player_claim(uuid,uuid,text) to authenticated;
grant execute on function public.review_player_claim(uuid,uuid,bigint,text) to authenticated;
grant execute on function public.revoke_player_membership(uuid,uuid,bigint) to authenticated;
grant execute on function public.record_player_heartbeat(uuid) to authenticated;
grant execute on function public.acknowledge_player_fictional_use(uuid,bigint) to authenticated;
grant execute on function public.acknowledge_game_master_guidance(uuid,bigint) to authenticated;
grant execute on function public.confirm_room_consent(uuid,bigint) to authenticated;
grant execute on function public.save_player_description(uuid,uuid,text,text,bigint) to authenticated;
grant execute on function public.get_room_readiness(uuid) to authenticated;
grant execute on function public.get_onboarding_view(uuid) to authenticated;
grant execute on function public.recover_game_master(bytea,bytea,timestamp with time zone) to authenticated;
grant execute on function public.rotate_game_master_recovery(uuid,bytea,timestamp with time zone) to authenticated;
