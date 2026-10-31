begin;

select plan(27);

create function pg_temp.capture_sqlstate(command text)
returns text
language plpgsql
as $function$
begin
  execute command;
  return null;
exception
  when others then
    return sqlstate;
end;
$function$;

select has_table('app_private', 'rooms', 'rooms table exists');
select has_table('app_private', 'players', 'players table exists');
select has_table(
  'app_private',
  'room_memberships',
  'room membership history exists'
);
select has_table(
  'app_private',
  'room_host_principals',
  'Game Master tenure history exists'
);
select has_table(
  'app_private',
  'player_descriptions',
  'private player descriptions exist'
);
select has_table(
  'app_private',
  'host_recovery_tokens',
  'hashed host recovery records exist'
);
select has_view(
  'app_private',
  'room_readiness_inputs',
  'readiness inputs are derived in one view'
);

select ok(
  not pg_catalog.has_table_privilege('anon', 'app_private.rooms', 'SELECT')
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.rooms',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'anon',
    'app_private.room_memberships',
    'INSERT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.room_memberships',
    'INSERT'
  ),
  'API roles have no direct room or membership table access'
);

select ok(
  pg_catalog.to_regclass(
    'app_private.room_host_principals_one_open_per_room_idx'
  ) is not null,
  'only one open Game Master tenure is indexed per room'
);
select ok(
  pg_catalog.to_regclass(
    'app_private.room_memberships_one_active_device_per_player_idx'
  ) is not null,
  'only one active device is indexed per player slot'
);
select ok(
  pg_catalog.to_regclass(
    'app_private.room_memberships_one_active_player_per_user_idx'
  ) is not null,
  'only one active player is indexed per auth principal and room'
);
select ok(
  pg_catalog.to_regclass(
    'app_private.host_recovery_tokens_one_active_per_room_idx'
  ) is not null,
  'only one live recovery credential is indexed per room'
);

insert into auth.users (id)
values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000011'),
  ('00000000-0000-4000-8000-000000000012'),
  ('00000000-0000-4000-8000-000000000013');

insert into app_private.rooms (
  id,
  room_code,
  host_auth_user_id,
  host_guidance_acknowledged_at,
  room_consent_confirmed_at
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    'ROOMA1',
    '00000000-0000-4000-8000-000000000001',
    '2026-10-30 00:00:00+00',
    '2026-10-30 00:00:00+00'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'ROOMB1',
    '00000000-0000-4000-8000-000000000002',
    null,
    null
  );

insert into app_private.room_host_principals (
  id,
  room_id,
  auth_user_id,
  started_at
)
values
  (
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000001',
    '2026-10-30 00:00:00+00'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000000002',
    '2026-10-30 00:00:00+00'
  );

insert into app_private.players (
  id,
  room_id,
  display_name,
  display_name_normalized,
  costume,
  seat_order,
  fictional_use_acknowledged_at
)
values
  (
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'Alex',
    'alex',
    'Pirate',
    1,
    '2026-10-30 00:00:00+00'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'Alex',
    'alex',
    'Witch',
    2,
    null
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000002',
    'Priya',
    'priya',
    'Detective',
    1,
    '2026-10-30 00:00:00+00'
  );

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.players
    where room_id = '10000000-0000-4000-8000-000000000001'
      and display_name = 'Alex'
  ),
  2,
  'duplicate display names are allowed within one room'
);

insert into app_private.room_memberships (
  id,
  room_id,
  auth_user_id,
  player_id,
  status,
  request_kind,
  approved_by_auth_user_id,
  joined_at
)
values (
  '40000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000011',
  '30000000-0000-4000-8000-000000000001',
  'ACTIVE',
  'INITIAL_CLAIM',
  '00000000-0000-4000-8000-000000000001',
  app_private.current_database_time()
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
  '40000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000013',
  '30000000-0000-4000-8000-000000000003',
  'PENDING',
  'INITIAL_CLAIM'
);

insert into app_private.player_descriptions (
  id,
  room_id,
  author_player_id,
  subject_player_id,
  description_text
)
values
  (
    '50000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    'Always arrives with a dramatic story.'
  ),
  (
    '50000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001',
    'Notices every small detail.'
  );

insert into app_private.host_recovery_tokens (
  id,
  room_id,
  token_digest,
  expires_at
)
values (
  '60000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  pg_catalog.decode(
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'hex'
  ),
  '2030-01-01 00:00:00+00'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.rooms (room_code, host_auth_user_id)
    values ('lower1', '00000000-0000-4000-8000-000000000002')
  $sql$),
  '23514',
  'room codes must use the canonical uppercase format'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.players (
      room_id, display_name, display_name_normalized, costume, seat_order
    ) values (
      '10000000-0000-4000-8000-000000000001',
      'Maya', 'maya', 'Vampire', 1
    )
  $sql$),
  '23505',
  'seat order is unique within a room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000003',
      'PENDING', 'INITIAL_CLAIM'
    )
  $sql$),
  '23503',
  'a membership cannot reference a player from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind,
      approved_by_auth_user_id, joined_at
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000001',
      'ACTIVE', 'INITIAL_CLAIM',
      '00000000-0000-4000-8000-000000000001',
      app_private.current_database_time()
    )
  $sql$),
  '23505',
  'one player slot cannot have two active devices'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind,
      approved_by_auth_user_id, joined_at
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000011',
      '30000000-0000-4000-8000-000000000002',
      'ACTIVE', 'INITIAL_CLAIM',
      '00000000-0000-4000-8000-000000000001',
      app_private.current_database_time()
    )
  $sql$),
  '23505',
  'one auth principal cannot actively hold two player slots in a room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000002',
      'PENDING', 'RECONNECT'
    )
  $sql$),
  '23514',
  'a reconnect request must identify the membership it replaces'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind,
      replaces_membership_id
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000012',
      '30000000-0000-4000-8000-000000000002',
      'PENDING', 'RECONNECT',
      '40000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'a reconnect cannot replace a membership from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_descriptions (
      room_id, author_player_id, subject_player_id, description_text
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000003',
      'Cross-room input'
    )
  $sql$),
  '23503',
  'a description cannot reference a player from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_descriptions (
      room_id, author_player_id, subject_player_id, description_text
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      'Self description'
    )
  $sql$),
  '23514',
  'a player cannot describe themself'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_descriptions (
      room_id, author_player_id, subject_player_id, description_text
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      repeat('x', 501)
    )
  $sql$),
  '23514',
  'a friend description cannot exceed 500 characters'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_descriptions (
      room_id, author_player_id, subject_player_id, description_text
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      'Duplicate pair'
    )
  $sql$),
  '23505',
  'an author has one description per subject'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.host_recovery_tokens (
      room_id, token_digest, expires_at
    ) values (
      '10000000-0000-4000-8000-000000000002',
      decode('abcd', 'hex'),
      '2030-01-01 00:00:00+00'
    )
  $sql$),
  '23514',
  'recovery records require a 32-byte digest rather than plaintext'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.host_recovery_tokens (
      room_id, token_digest, expires_at
    ) values (
      '10000000-0000-4000-8000-000000000001',
      decode(
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        'hex'
      ),
      '2030-01-01 00:00:00+00'
    )
  $sql$),
  '23505',
  'a room cannot have two live recovery records'
);

select is(
  (
    select pg_catalog.jsonb_build_object(
      'player_count', player_count,
      'active_membership_count', active_membership_count,
      'acknowledged_player_count', acknowledged_player_count,
      'submitted_description_count', submitted_description_count,
      'host_guidance_acknowledged', host_guidance_acknowledged,
      'room_consent_confirmed', room_consent_confirmed
    )
    from app_private.room_readiness_inputs
    where room_id = '10000000-0000-4000-8000-000000000001'
  ),
  pg_catalog.jsonb_build_object(
    'player_count', 2,
    'active_membership_count', 1,
    'acknowledged_player_count', 1,
    'submitted_description_count', 2,
    'host_guidance_acknowledged', true,
    'room_consent_confirmed', true
  ),
  'readiness exposes deterministic inputs without deciding M0-02 policy'
);

select * from finish();

rollback;
