begin;

select plan(25);

select has_function(
  'public', 'create_game_room', array['bytea', 'timestamp with time zone'],
  'atomic room-creation command exists'
);
select has_function(
  'public', 'get_room_setup_profiles', array[]::text[],
  'reviewed setup-profile projection exists'
);
select has_function(
  'public', 'save_room_configuration',
  array['uuid', 'bigint', 'jsonb', 'jsonb'],
  'validated room-configuration command exists'
);
select has_function(
  'public', 'open_room_lobby', array['uuid', 'bigint'],
  'setup-locking command exists'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.create_game_room(bytea,timestamp with time zone)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.create_game_room(bytea,timestamp with time zone)',
    'EXECUTE'
  ),
  'only authenticated sessions may create rooms'
);

insert into auth.users (id)
values
  ('f0000000-0000-4000-8000-000000000001'),
  ('f0000000-0000-4000-8000-000000000002');

select set_config(
  'request.jwt.claims',
  '{"sub":"f0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

create temporary table created_room as
select public.create_game_room(
  pg_catalog.decode(pg_catalog.repeat('12', 32), 'hex'),
  app_private.current_database_time() + interval '90 days'
) as result;

select is(
  (select result ->> 'status' from created_room),
  'DRAFT',
  'new rooms begin in DRAFT'
);
select matches(
  (select result ->> 'roomCode' from created_room),
  '^[A-F0-9]{8}$',
  'room creation allocates a canonical public code'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_host_principals as principal
    where principal.room_id = (select (result ->> 'roomId')::uuid from created_room)
      and principal.auth_user_id = 'f0000000-0000-4000-8000-000000000001'
      and principal.ended_at is null
  ),
  1,
  'room creation atomically opens one Game Master tenure'
);
select is(
  (
    select pg_catalog.encode(token.token_digest, 'hex')
    from app_private.host_recovery_tokens as token
    where token.room_id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  pg_catalog.repeat('12', 32),
  'only the recovery credential digest is persisted'
);

select is(
  pg_catalog.jsonb_array_length(
    public.get_room_setup_profiles() -> 'factionRecommendations'
  ),
  9,
  'setup profiles cover every supported party size'
);
select is(
  pg_catalog.jsonb_array_length(
    public.get_room_setup_profiles() -> 'durations'
  ),
  5,
  'setup profiles cover every supported duration'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f0000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  pg_catalog.format(
    'select public.save_room_configuration(%L, 0, %L::jsonb, %L::jsonb)',
    (select result ->> 'roomId' from created_room),
    '{"durationProfileVersion":"duration-v1","factionProfileVersion":"factions-v1","durationMinutes":30,"murdererCount":1,"accompliceCount":0,"innocentCount":3,"murdererAware":true}',
    '[{"displayName":"A","costume":"One"},{"displayName":"B","costume":"Two"},{"displayName":"C","costume":"Three"},{"displayName":"D","costume":"Four"}]'
  ),
  '42501',
  'current Game Master authorization required',
  'another authenticated guest cannot configure the room'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  pg_catalog.format(
    'select public.save_room_configuration(%L, 0, %L::jsonb, %L::jsonb)',
    (select result ->> 'roomId' from created_room),
    '{"durationProfileVersion":"duration-v1","factionProfileVersion":"factions-v1","durationMinutes":30,"murdererCount":1,"accompliceCount":0,"innocentCount":3,"murdererAware":false}',
    '[{"displayName":"Aarav","costume":"Pirate"},{"displayName":"Aarav","costume":"Vampire"},{"displayName":"Isha","costume":"Ghost"},{"displayName":"Kabir","costume":"Detective","hostBackground":"Arrived late"}]'
  ),
  'the Game Master can save a valid four-player configuration'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.players as player
    where player.room_id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  4,
  'configuration creates exactly four player slots and no NPC victim slot'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.players as player
    where player.room_id = (select (result ->> 'roomId')::uuid from created_room)
      and player.display_name = 'Aarav'
  ),
  2,
  'duplicate display names are supported'
);
select is(
  (
    select room.state_version::integer
    from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  1,
  'a successful setup save increments the room version once'
);
select is(
  (
    select room.duration_minutes::integer
    from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  30,
  'the room references the immutable duration profile'
);
select is(
  (
    select room.config_json ->> 'npcVictim'
    from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  'true',
  'configuration records the fictional NPC victim invariant'
);

select throws_ok(
  pg_catalog.format(
    'select public.save_room_configuration(%L, 1, %L::jsonb, %L::jsonb)',
    (select result ->> 'roomId' from created_room),
    '{"durationProfileVersion":"duration-v1","factionProfileVersion":"factions-v1","durationMinutes":30,"murdererCount":2,"accompliceCount":2,"innocentCount":2,"murdererAware":true}',
    '[{"displayName":"A","costume":"One"},{"displayName":"B","costume":"Two"},{"displayName":"C","costume":"Three"},{"displayName":"D","costume":"Four"}]'
  ),
  '22023',
  'invalid room configuration',
  'faction counts must equal the player count'
);

select lives_ok(
  pg_catalog.format(
    'select public.open_room_lobby(%L, 1)',
    (select result ->> 'roomId' from created_room)
  ),
  'a complete setup can be locked and opened'
);
select is(
  (
    select room.status::text
    from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  'LOBBY',
  'opening a room transitions it to LOBBY'
);
select is(
  (
    select room.config_json ->> 'setupLocked'
    from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from created_room)
  ),
  'true',
  'opening the lobby permanently locks setup editing'
);
select throws_ok(
  pg_catalog.format(
    'select public.save_room_configuration(%L, 2, %L::jsonb, %L::jsonb)',
    (select result ->> 'roomId' from created_room),
    '{"durationProfileVersion":"duration-v1","factionProfileVersion":"factions-v1","durationMinutes":30,"murdererCount":1,"accompliceCount":0,"innocentCount":3,"murdererAware":true}',
    '[{"displayName":"A","costume":"One"},{"displayName":"B","costume":"Two"},{"displayName":"C","costume":"Three"},{"displayName":"D","costume":"Four"}]'
  ),
  '55000',
  'room setup is locked',
  'lobby setup cannot be rewritten'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f0000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select pg_catalog.count(*)::integer
    from public.lookup_room_lobby(
      (select result ->> 'roomCode' from created_room)
    )
  ),
  4,
  'the public code reveals only the four safe lobby slots after opening'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from public.lookup_room_lobby(
      (select result ->> 'roomCode' from created_room)
    )
    where display_name = 'Aarav'
  ),
  2,
  'safe discovery keeps duplicate names distinguishable by costume and seat'
);

select * from finish();
rollback;
