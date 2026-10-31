begin;

select plan(31);

select has_function(
  'app_private', 'current_auth_user_id', array[]::text[],
  'authenticated-principal identity helper exists'
);
select has_function(
  'app_private', 'is_current_game_master', array['uuid'],
  'current Game Master helper exists'
);
select has_function(
  'app_private', 'active_player_id', array['uuid'],
  'active player identity helper exists'
);
select has_function(
  'app_private', 'assert_current_game_master', array['uuid'],
  'Game Master command assertion exists'
);
select has_function(
  'app_private', 'assert_active_player', array['uuid', 'uuid'],
  'player command assertion exists'
);
select has_function(
  'public', 'lookup_room_lobby', array['text'],
  'safe room-code discovery RPC exists'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relkind in ('r', 'p')
      and relation.relrowsecurity
  ),
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relkind in ('r', 'p')
  ),
  'RLS is enabled on every private application table'
);

select ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.lookup_room_lobby(text)', 'EXECUTE'
  ),
  'authenticated guest sessions may perform safe discovery'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'public.lookup_room_lobby(text)', 'EXECUTE'
  ),
  'unauthenticated callers cannot perform room discovery'
);

select ok(
  not pg_catalog.has_schema_privilege('service_role', 'app_private', 'USAGE')
  and not pg_catalog.has_table_privilege(
    'service_role', 'app_private.rooms', 'SELECT'
  ),
  'the generic service role has no private-schema shortcut'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app_private.is_current_game_master(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'app_private.assert_active_player(uuid,uuid)', 'EXECUTE'
  ),
  'private identity helpers are not API-callable RPCs'
);

insert into auth.users (id)
values
  ('c0000000-0000-4000-8000-000000000001'),
  ('c0000000-0000-4000-8000-000000000002'),
  ('c0000000-0000-4000-8000-000000000003'),
  ('c0000000-0000-4000-8000-000000000004'),
  ('c0000000-0000-4000-8000-000000000005');

insert into app_private.rooms (
  id, room_code, host_auth_user_id, status, state_version
)
values
  (
    'c1000000-0000-4000-8000-000000000001',
    'LOBBY1', 'c0000000-0000-4000-8000-000000000001', 'LOBBY', 1
  ),
  (
    'c1000000-0000-4000-8000-000000000002',
    'CLOSED1', 'c0000000-0000-4000-8000-000000000005', 'IN_PROGRESS', 1
  );

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values
  (
    'c2000000-0000-4000-8000-000000000001',
    'c1000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-000000000001'
  ),
  (
    'c2000000-0000-4000-8000-000000000002',
    'c1000000-0000-4000-8000-000000000002',
    'c0000000-0000-4000-8000-000000000005'
  );

set constraints all immediate;

insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume, seat_order
)
values
  (
    'c3000000-0000-4000-8000-000000000001',
    'c1000000-0000-4000-8000-000000000001',
    'Aarav', 'aarav', 'Pirate', 1
  ),
  (
    'c3000000-0000-4000-8000-000000000002',
    'c1000000-0000-4000-8000-000000000001',
    'Aarav', 'aarav', 'Vampire', 2
  ),
  (
    'c3000000-0000-4000-8000-000000000003',
    'c1000000-0000-4000-8000-000000000001',
    'Isha', 'isha', 'Ghost', 3
  ),
  (
    'c3000000-0000-4000-8000-000000000004',
    'c1000000-0000-4000-8000-000000000002',
    'Neel', 'neel', 'Detective', 1
  );

insert into app_private.room_memberships (
  id, room_id, auth_user_id, player_id, status, request_kind,
  approved_by_auth_user_id, last_seen_at, joined_at
)
values (
  'c4000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000002',
  'c3000000-0000-4000-8000-000000000001',
  'ACTIVE', 'INITIAL_CLAIM',
  'c0000000-0000-4000-8000-000000000001',
  app_private.current_database_time(), app_private.current_database_time()
);

insert into app_private.room_memberships (
  id, room_id, auth_user_id, player_id, status, request_kind
)
values (
  'c4000000-0000-4000-8000-000000000002',
  'c1000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000003',
  'c3000000-0000-4000-8000-000000000002',
  'PENDING', 'INITIAL_CLAIM'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  app_private.current_auth_user_id(),
  'c0000000-0000-4000-8000-000000000001'::uuid,
  'the JWT subject is the authenticated principal'
);

select ok(
  app_private.is_current_game_master(
    'c1000000-0000-4000-8000-000000000001'
  ),
  'the authoritative open-tenure host is the current Game Master'
);

select is(
  app_private.active_player_id(
    'c1000000-0000-4000-8000-000000000001'
  ),
  null::uuid,
  'the dedicated Game Master never resolves to a player identity'
);

select lives_ok(
  $sql$
    select app_private.assert_current_game_master(
      'c1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  'the current Game Master passes the host command guard'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select is(
  app_private.active_player_id(
    'c1000000-0000-4000-8000-000000000001'
  ),
  'c3000000-0000-4000-8000-000000000001'::uuid,
  'an active membership resolves to its stable player identity'
);

select ok(
  not app_private.is_current_game_master(
    'c1000000-0000-4000-8000-000000000001'
  ),
  'an active player is not the Game Master'
);

select lives_ok(
  $sql$
    select app_private.assert_active_player(
      'c1000000-0000-4000-8000-000000000001',
      'c3000000-0000-4000-8000-000000000001'
    )
  $sql$,
  'an active player passes its matching command guard'
);

select throws_ok(
  $sql$
    select app_private.assert_active_player(
      'c1000000-0000-4000-8000-000000000001',
      'c3000000-0000-4000-8000-000000000002'
    )
  $sql$,
  '42501',
  'active player authorization required',
  'a player cannot act as another slot'
);

select is(
  app_private.active_player_id(
    'c1000000-0000-4000-8000-000000000002'
  ),
  null::uuid,
  'an active player identity does not cross room boundaries'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);

select is(
  app_private.active_player_id(
    'c1000000-0000-4000-8000-000000000001'
  ),
  null::uuid,
  'a pending claim grants no player authorization'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);

select throws_ok(
  $sql$
    select app_private.assert_current_game_master(
      'c1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '42501',
  'current Game Master authorization required',
  'an outsider fails the Game Master command guard'
);

-- Temporarily grant object privileges to prove RLS still denies generic table
-- access. These test-only grants roll back with this transaction.
grant usage on schema app_private to authenticated;
grant select, insert on table app_private.rooms to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);

select is(
  (select pg_catalog.count(*)::integer from app_private.rooms),
  0,
  'closed RLS returns no private rooms even after an accidental SELECT grant'
);

select throws_ok(
  $sql$
    insert into app_private.rooms (room_code, host_auth_user_id)
    values ('DENIED1', 'c0000000-0000-4000-8000-000000000004')
  $sql$,
  '42501',
  null,
  'closed RLS denies direct writes even after an accidental INSERT grant'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.lookup_room_lobby('lobby1')
  ),
  3,
  'case-normalized room-code discovery returns every safe lobby slot'
);

select is(
  (
    select pg_catalog.string_agg(slot_status, ',' order by seat_order)
    from public.lookup_room_lobby('LOBBY1')
  ),
  'OCCUPIED,PENDING,AVAILABLE',
  'discovery distinguishes occupied, pending, and available slots'
);

select ok(
  (
    select not (
      pg_catalog.to_jsonb(lobby) ?| array[
        'host_auth_user_id', 'auth_user_id', 'config_json', 'story_id',
        'recovery_token', 'description_text', 'dossier_json'
      ]
    )
    from public.lookup_room_lobby('LOBBY1') as lobby
    limit 1
  ),
  'discovery rows contain no host, auth, configuration, story, or secret data'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.lookup_room_lobby('bad code!')
  ),
  0,
  'an invalid room code returns the same empty discovery shape'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from public.lookup_room_lobby('CLOSED1')
  ),
  0,
  'a room outside the joinable lobby states is not discoverable'
);

select is(
  (
    select pg_catalog.count(distinct player_id)::integer
    from public.lookup_room_lobby('LOBBY1')
    where display_name = 'Aarav'
  ),
  2,
  'duplicate display names remain distinct by opaque player ID and costume'
);

reset role;

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app_private.current_auth_user_id()', 'EXECUTE'
  ),
  'the safe public RPC does not broaden private helper grants'
);

select * from finish();

rollback;
