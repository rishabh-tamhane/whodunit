-- IDN-02/04: atomic room creation, private recovery credentials, and setup.

create function public.create_game_room(
  recovery_token_digest bytea,
  recovery_expires_at timestamp with time zone
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  caller_id uuid := auth.uid();
  created_room app_private.rooms%rowtype;
  candidate_code text;
  attempt integer;
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated guest session required';
  end if;

  if pg_catalog.octet_length(recovery_token_digest) <> 32
    or recovery_expires_at <= app_private.current_database_time()
    or recovery_expires_at > app_private.current_database_time() + interval '365 days'
  then
    raise exception using
      errcode = '22023',
      message = 'invalid recovery credential';
  end if;

  for attempt in 1..10 loop
    candidate_code := pg_catalog.upper(
      pg_catalog.substr(
        pg_catalog.encode(extensions.gen_random_bytes(6), 'hex'),
        1,
        8
      )
    );

    begin
      insert into app_private.rooms (room_code, host_auth_user_id)
      values (candidate_code, caller_id)
      returning * into created_room;
      exit;
    exception
      when unique_violation then
        if attempt = 10 then
          raise exception using
            errcode = '40001',
            message = 'could not allocate a room code';
        end if;
    end;
  end loop;

  insert into app_private.room_host_principals (room_id, auth_user_id)
  values (created_room.id, caller_id);

  insert into app_private.host_recovery_tokens (
    room_id,
    token_digest,
    expires_at
  ) values (
    created_room.id,
    recovery_token_digest,
    recovery_expires_at
  );

  return pg_catalog.jsonb_build_object(
    'roomId', created_room.id,
    'roomCode', created_room.room_code,
    'stateVersion', created_room.state_version::text,
    'status', created_room.status::text,
    'recoveryExpiresAt', recovery_expires_at
  );
end;
$function$;

create function public.get_room_setup_profiles()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated guest session required';
  end if;

  return pg_catalog.jsonb_build_object(
    'durationProfileVersion', 'duration-v1',
    'durations', (
      select pg_catalog.jsonb_agg(
        profile.profile_json order by profile.duration_minutes
      )
      from app_private.duration_profiles as profile
      where profile.profile_version = 'duration-v1'
    ),
    'factionProfileVersion', 'factions-v1',
    'factionRecommendations', (
      select pg_catalog.jsonb_agg(
        profile.recommendation_json order by profile.player_count
      )
      from app_private.faction_recommendation_profiles as profile
      where profile.profile_version = 'factions-v1'
    )
  );
end;
$function$;

create function public.save_room_configuration(
  target_room_id uuid,
  expected_state_version bigint,
  configuration jsonb,
  player_slots jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  slot_count integer;
  duration_value integer;
  murderer_count integer;
  accomplice_count integer;
  innocent_count integer;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);

  select room.* into strict room_record
  from app_private.rooms as room
  where room.id = target_room_id;

  if room_record.state_version <> expected_state_version then
    raise exception using
      errcode = '40001',
      message = 'stale room state version';
  end if;

  if room_record.status <> 'DRAFT'
    or room_record.locked_at is not null
    or exists (
      select 1
      from app_private.room_memberships as membership
      where membership.room_id = target_room_id
    )
  then
    raise exception using
      errcode = '55000',
      message = 'room setup is locked';
  end if;

  if pg_catalog.jsonb_typeof(configuration) <> 'object'
    or pg_catalog.jsonb_typeof(player_slots) <> 'array'
  then
    raise exception using
      errcode = '22023',
      message = 'invalid room configuration';
  end if;

  slot_count := pg_catalog.jsonb_array_length(player_slots);
  duration_value := (configuration ->> 'durationMinutes')::integer;
  murderer_count := (configuration ->> 'murdererCount')::integer;
  accomplice_count := (configuration ->> 'accompliceCount')::integer;
  innocent_count := (configuration ->> 'innocentCount')::integer;

  if slot_count not between 4 and 12
    or murderer_count < 1
    or accomplice_count < 0
    or innocent_count < 1
    or murderer_count + accomplice_count + innocent_count <> slot_count
    or configuration ->> 'durationProfileVersion' <> 'duration-v1'
    or configuration ->> 'factionProfileVersion' <> 'factions-v1'
    or configuration -> 'murdererAware' is null
    or pg_catalog.jsonb_typeof(configuration -> 'murdererAware') <> 'boolean'
    or not exists (
      select 1
      from app_private.duration_profiles as profile
      where profile.profile_version = configuration ->> 'durationProfileVersion'
        and profile.duration_minutes = duration_value
    )
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(player_slots) as slot(value)
      where pg_catalog.char_length(
          pg_catalog.btrim(coalesce(slot.value ->> 'displayName', ''))
        ) not between 1 and 100
        or pg_catalog.char_length(
          pg_catalog.btrim(coalesce(slot.value ->> 'costume', ''))
        ) not between 1 and 200
        or pg_catalog.char_length(
          coalesce(slot.value ->> 'hostBackground', '')
        ) > 1000
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid room configuration';
  end if;

  delete from app_private.players where room_id = target_room_id;

  insert into app_private.players (
    room_id,
    display_name,
    display_name_normalized,
    costume,
    host_background,
    seat_order
  )
  select
    target_room_id,
    pg_catalog.btrim(slot.value ->> 'displayName'),
    pg_catalog.lower(pg_catalog.btrim(slot.value ->> 'displayName')),
    pg_catalog.btrim(slot.value ->> 'costume'),
    nullif(pg_catalog.btrim(slot.value ->> 'hostBackground'), ''),
    slot.seat::smallint
  from pg_catalog.jsonb_array_elements(player_slots)
    with ordinality as slot(value, seat);

  update app_private.rooms
  set
    config_json = configuration || pg_catalog.jsonb_build_object(
      'playerCount', slot_count,
      'setupLocked', false,
      'npcVictim', true
    ),
    duration_profile_version = configuration ->> 'durationProfileVersion',
    duration_minutes = duration_value,
    scoring_profile_version = 'score-v1',
    state_version = state_version + 1,
    updated_at = app_private.current_database_time()
  where id = target_room_id
  returning * into room_record;

  return pg_catalog.jsonb_build_object(
    'roomId', room_record.id,
    'roomCode', room_record.room_code,
    'status', room_record.status::text,
    'stateVersion', room_record.state_version::text,
    'playerCount', slot_count
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '22023',
      message = 'invalid room configuration';
end;
$function$;

create function public.open_room_lobby(
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
  room_record app_private.rooms%rowtype;
  player_count integer;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);

  select room.* into strict room_record
  from app_private.rooms as room
  where room.id = target_room_id;

  if room_record.state_version <> expected_state_version then
    raise exception using
      errcode = '40001',
      message = 'stale room state version';
  end if;

  select pg_catalog.count(*)::integer into player_count
  from app_private.players as player
  where player.room_id = target_room_id;

  if room_record.status <> 'DRAFT'
    or room_record.duration_profile_version is null
    or player_count not between 4 and 12
    or (room_record.config_json ->> 'playerCount')::integer <> player_count
  then
    raise exception using
      errcode = '55000',
      message = 'room configuration is incomplete';
  end if;

  update app_private.rooms
  set
    status = 'LOBBY',
    config_json = pg_catalog.jsonb_set(config_json, '{setupLocked}', 'true'),
    state_version = state_version + 1,
    updated_at = app_private.current_database_time()
  where id = target_room_id
  returning * into room_record;

  return pg_catalog.jsonb_build_object(
    'roomId', room_record.id,
    'roomCode', room_record.room_code,
    'status', room_record.status::text,
    'stateVersion', room_record.state_version::text
  );
end;
$function$;

revoke all on function public.create_game_room(bytea, timestamp with time zone)
  from public, anon, authenticated, service_role;
revoke all on function public.get_room_setup_profiles()
  from public, anon, authenticated, service_role;
revoke all on function public.save_room_configuration(uuid, bigint, jsonb, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.open_room_lobby(uuid, bigint)
  from public, anon, authenticated, service_role;

grant execute on function public.create_game_room(bytea, timestamp with time zone)
  to authenticated;
grant execute on function public.get_room_setup_profiles()
  to authenticated;
grant execute on function public.save_room_configuration(uuid, bigint, jsonb, jsonb)
  to authenticated;
grant execute on function public.open_room_lobby(uuid, bigint)
  to authenticated;

comment on function public.create_game_room(bytea, timestamp with time zone) is
  'Creates the room, initial Game Master tenure, and hashed recovery credential atomically.';
comment on function public.save_room_configuration(uuid, bigint, jsonb, jsonb) is
  'Replaces an unlocked draft setup with a validated 4-12 player configuration.';
