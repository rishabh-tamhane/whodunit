begin;

select plan(29);

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

create function pg_temp.capture_deferred_sqlstate(commands text[])
returns text
language plpgsql
as $function$
declare
  command text;
  captured_sqlstate text;
begin
  set constraints all deferred;

  foreach command in array commands
  loop
    execute command;
  end loop;

  set constraints all immediate;
  set constraints all deferred;
  return null;
exception
  when others then
    get stacked diagnostics captured_sqlstate = returned_sqlstate;
    set constraints all deferred;
    return captured_sqlstate;
end;
$function$;

select has_function(
  'app_private',
  'lock_room',
  array['uuid'],
  'the shared room-first lock helper exists'
);

select ok(
  (
    select 'search_path=""' = any(coalesce(p.proconfig, array[]::text[]))
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'app_private' and p.proname = 'lock_room'
  ),
  'the room lock helper has an empty fixed search_path'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'app_private.lock_room(uuid)'::pg_catalog.regprocedure
      )
    ),
    'for update'
  ) > 0,
  'the room helper takes a row lock'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app_private.lock_room(uuid)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.lock_room(uuid)',
    'EXECUTE'
  ),
  'API roles cannot call the internal lock helper'
);

select has_trigger(
  'app_private',
  'room_memberships',
  'room_memberships_enforce_identity',
  'membership identity enforcement is installed'
);
select has_trigger(
  'app_private',
  'room_host_principals',
  'room_host_principals_enforce_identity',
  'Game Master history enforcement is installed'
);
select has_trigger(
  'app_private',
  'rooms',
  'rooms_enforce_host_identity',
  'current Game Master enforcement is installed'
);
select has_trigger(
  'app_private',
  'rooms',
  'rooms_check_host_tenure',
  'rooms receive commit-time tenure validation'
);
select has_trigger(
  'app_private',
  'room_host_principals',
  'room_host_principals_check_tenure',
  'tenure changes receive commit-time validation'
);

select ok(
  (
    select pg_catalog.bool_and(t.tgdeferrable and t.tginitdeferred)
    from pg_catalog.pg_trigger as t
    where t.tgname in (
      'rooms_check_host_tenure',
      'room_host_principals_check_tenure'
    )
  ),
  'tenure constraint triggers are initially deferred'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'app_private.enforce_membership_identity()'::pg_catalog.regprocedure
      )
    ),
    'app_private.lock_room'
  ) > 0
  and pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'app_private.enforce_host_principal_identity()'::pg_catalog.regprocedure
      )
    ),
    'app_private.lock_room'
  ) > 0,
  'claim and recovery identity paths take the same room-first lock'
);

insert into auth.users (id)
values
  ('70000000-0000-4000-8000-000000000001'),
  ('70000000-0000-4000-8000-000000000002'),
  ('70000000-0000-4000-8000-000000000003'),
  ('70000000-0000-4000-8000-000000000004'),
  ('70000000-0000-4000-8000-000000000011'),
  ('70000000-0000-4000-8000-000000000012');

insert into app_private.rooms (id, room_code, host_auth_user_id)
values (
  '71000000-0000-4000-8000-000000000001',
  'GMROOM',
  '70000000-0000-4000-8000-000000000001'
);

insert into app_private.room_host_principals (
  id,
  room_id,
  auth_user_id,
  started_at
)
values (
  '72000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000001',
  '2026-10-30 00:00:00+00'
);

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
    '73000000-0000-4000-8000-000000000001',
    '71000000-0000-4000-8000-000000000001',
    'Maya',
    'maya',
    'Witch',
    1
  ),
  (
    '73000000-0000-4000-8000-000000000002',
    '71000000-0000-4000-8000-000000000001',
    'Rahul',
    'rahul',
    'Detective',
    2
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
  '74000000-0000-4000-8000-000000000001',
  '71000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000011',
  '73000000-0000-4000-8000-000000000001',
  'ACTIVE',
  'INITIAL_CLAIM',
  '70000000-0000-4000-8000-000000000001',
  app_private.current_database_time()
);

set constraints all immediate;

select is(
  (
    select h.auth_user_id
    from app_private.room_host_principals as h
    where h.room_id = '71000000-0000-4000-8000-000000000001'
      and h.ended_at is null
  ),
  '70000000-0000-4000-8000-000000000001'::uuid,
  'a valid room has one open tenure matching its current Game Master'
);

set constraints all deferred;

select is(
  pg_temp.capture_deferred_sqlstate(
    array[
      $sql$
        insert into app_private.rooms (id, room_code, host_auth_user_id)
        values (
          '71000000-0000-4000-8000-000000000002',
          'NOHOST',
          '70000000-0000-4000-8000-000000000003'
        )
      $sql$
    ]
  ),
  '23514',
  'a room without an open Game Master tenure fails commit validation'
);

select is(
  pg_temp.capture_deferred_sqlstate(
    array[
      $sql$
        insert into app_private.rooms (id, room_code, host_auth_user_id)
        values (
          '71000000-0000-4000-8000-000000000003',
          'BADHOST',
          '70000000-0000-4000-8000-000000000003'
        )
      $sql$,
      $sql$
        insert into app_private.room_host_principals (
          room_id, auth_user_id, started_at
        ) values (
          '71000000-0000-4000-8000-000000000003',
          '70000000-0000-4000-8000-000000000004',
          '2026-10-30 00:00:00+00'
        )
      $sql$
    ]
  ),
  '23514',
  'a mismatched open tenure fails commit validation'
);

select is(
  pg_temp.capture_deferred_sqlstate(
    array[
      $sql$
        insert into app_private.rooms (id, room_code, host_auth_user_id)
        values (
          '71000000-0000-4000-8000-000000000004',
          'TWOHOST',
          '70000000-0000-4000-8000-000000000003'
        )
      $sql$,
      $sql$
        insert into app_private.room_host_principals (
          room_id, auth_user_id, started_at
        ) values (
          '71000000-0000-4000-8000-000000000004',
          '70000000-0000-4000-8000-000000000003',
          '2026-10-30 00:00:00+00'
        )
      $sql$,
      $sql$
        insert into app_private.room_host_principals (
          room_id, auth_user_id, started_at
        ) values (
          '71000000-0000-4000-8000-000000000004',
          '70000000-0000-4000-8000-000000000004',
          '2026-10-30 00:00:00+00'
        )
      $sql$
    ]
  ),
  '23505',
  'a room cannot have multiple open Game Master tenures'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind
    ) values (
      '71000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000001',
      '73000000-0000-4000-8000-000000000002',
      'PENDING',
      'INITIAL_CLAIM'
    )
  $sql$),
  '23514',
  'the current Game Master cannot create a player claim'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_memberships as m
    where m.room_id = '71000000-0000-4000-8000-000000000001'
      and m.auth_user_id = '70000000-0000-4000-8000-000000000011'
      and m.status = 'ACTIVE'
  ),
  1,
  'an ordinary player principal can hold a membership'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_host_principals (
      room_id, auth_user_id, started_at
    ) values (
      '71000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000011',
      '2026-10-30 00:01:00+00'
    )
  $sql$),
  '23514',
  'a player membership holder cannot receive a Game Master tenure'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set host_auth_user_id = '70000000-0000-4000-8000-000000000011'
    where id = '71000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a player membership holder cannot become the room current Game Master'
);

set constraints all deferred;

update app_private.room_host_principals
set ended_at = '2026-10-30 00:05:00+00'
where id = '72000000-0000-4000-8000-000000000001';

insert into app_private.room_host_principals (
  id,
  room_id,
  auth_user_id,
  started_at
)
values (
  '72000000-0000-4000-8000-000000000002',
  '71000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000002',
  '2026-10-30 00:05:00+00'
);

update app_private.rooms
set host_auth_user_id = '70000000-0000-4000-8000-000000000002'
where id = '71000000-0000-4000-8000-000000000001';

set constraints all immediate;

select is(
  (
    select pg_catalog.jsonb_build_object(
      'room_host', r.host_auth_user_id,
      'open_host', h.auth_user_id,
      'open_count', pg_catalog.count(*) over ()
    )
    from app_private.rooms as r
    join app_private.room_host_principals as h
      on h.room_id = r.id and h.ended_at is null
    where r.id = '71000000-0000-4000-8000-000000000001'
  ),
  pg_catalog.jsonb_build_object(
    'room_host', '70000000-0000-4000-8000-000000000002'::uuid,
    'open_host', '70000000-0000-4000-8000-000000000002'::uuid,
    'open_count', 1
  ),
  'host recovery atomically transfers authority and preserves equality'
);

set constraints all deferred;

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind
    ) values (
      '71000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000001',
      '73000000-0000-4000-8000-000000000002',
      'PENDING',
      'INITIAL_CLAIM'
    )
  $sql$),
  '23514',
  'a former Game Master remains permanently ineligible for player membership'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind
    ) values (
      '71000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
      '73000000-0000-4000-8000-000000000002',
      'PENDING',
      'INITIAL_CLAIM'
    )
  $sql$),
  '23514',
  'the replacement current Game Master cannot claim a player slot'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.room_host_principals
    set started_at = '2026-10-30 00:06:00+00'
    where id = '72000000-0000-4000-8000-000000000002'
  $sql$),
  '23514',
  'Game Master tenure identity fields cannot be rewritten'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.room_host_principals
    set ended_at = null
    where id = '72000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a closed Game Master tenure cannot reopen'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.room_host_principals
    where id = '72000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'Game Master tenure history cannot be deleted while the room exists'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.room_memberships
    set player_id = '73000000-0000-4000-8000-000000000002'
    where id = '74000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'membership identity cannot be rebound by rewriting its history row'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_memberships as m
    join app_private.room_host_principals as h
      on h.room_id = m.room_id and h.auth_user_id = m.auth_user_id
    where m.room_id = '71000000-0000-4000-8000-000000000001'
  ),
  0,
  'no current or former Game Master has any player membership row'
);

set constraints all deferred;

insert into app_private.rooms (id, room_code, host_auth_user_id)
values (
  '71000000-0000-4000-8000-000000000005',
  'DELROOM',
  '70000000-0000-4000-8000-000000000012'
);

insert into app_private.room_host_principals (
  id,
  room_id,
  auth_user_id,
  started_at
)
values (
  '72000000-0000-4000-8000-000000000005',
  '71000000-0000-4000-8000-000000000005',
  '70000000-0000-4000-8000-000000000012',
  '2026-10-30 00:00:00+00'
);

set constraints all immediate;
set constraints all deferred;

select is(
  pg_temp.capture_deferred_sqlstate(
    array[
      $sql$
        delete from app_private.rooms
        where id = '71000000-0000-4000-8000-000000000005'
      $sql$
    ]
  ),
  null,
  'room deletion may cascade through Game Master tenure history'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_host_principals
    where room_id = '71000000-0000-4000-8000-000000000005'
  ),
  0,
  'room deletion removes its Game Master history'
);

select * from finish();

rollback;
