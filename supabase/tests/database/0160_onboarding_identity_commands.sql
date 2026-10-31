begin;

select no_plan();

select has_function(
  'public', 'request_player_claim', array['uuid', 'uuid', 'text'],
  'player claim request command exists'
);
select has_function(
  'public', 'review_player_claim', array['uuid', 'uuid', 'bigint', 'text'],
  'Game Master claim review command exists'
);
select has_function(
  'public', 'record_player_heartbeat', array['uuid'],
  'rate-limited heartbeat command exists'
);
select has_function(
  'public', 'get_onboarding_view', array['uuid'],
  'actor-safe onboarding projection exists'
);
select has_function(
  'public', 'recover_game_master',
  array['bytea', 'bytea', 'timestamp with time zone'],
  'host recovery command exists'
);

insert into auth.users (id)
values
  ('a0100000-0000-4000-8000-000000000001'),
  ('a0100000-0000-4000-8000-000000000002'),
  ('a0100000-0000-4000-8000-000000000003'),
  ('a0100000-0000-4000-8000-000000000004'),
  ('a0100000-0000-4000-8000-000000000005'),
  ('a0100000-0000-4000-8000-000000000006');

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

create temporary table onboarding_room as
select public.create_game_room(
  pg_catalog.decode(pg_catalog.repeat('34', 32), 'hex'),
  app_private.current_database_time() + interval '90 days'
) as result;

select public.save_room_configuration(
  (select (result ->> 'roomId')::uuid from onboarding_room),
  0,
  '{"durationProfileVersion":"duration-v1","factionProfileVersion":"factions-v1","durationMinutes":30,"murdererCount":1,"accompliceCount":0,"innocentCount":3,"murdererAware":true}'::jsonb,
  '[{"displayName":"Aarav","costume":"Pirate"},{"displayName":"Aarav","costume":"Vampire"},{"displayName":"Isha","costume":"Ghost"},{"displayName":"Kabir","costume":"Detective"}]'::jsonb
);
select public.open_room_lobby(
  (select (result ->> 'roomId')::uuid from onboarding_room),
  1
);

create temporary table onboarding_players as
select player.id, player.seat_order
from app_private.players as player
where player.room_id = (select (result ->> 'roomId')::uuid from onboarding_room);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
create temporary table first_claim as
select public.request_player_claim(
  (select (result ->> 'roomId')::uuid from onboarding_room),
  (select id from onboarding_players where seat_order = 1),
  'INITIAL_CLAIM'
) as result;

select is(
  public.request_player_claim(
    (select (result ->> 'roomId')::uuid from onboarding_room),
    (select id from onboarding_players where seat_order = 1),
    'INITIAL_CLAIM'
  ) ->> 'replayed',
  'true',
  'repeating the same pending claim is idempotent'
);
select is(
  (
    select membership.status::text
    from app_private.room_memberships as membership
    where membership.id = (select (result ->> 'claimId')::uuid from first_claim)
  ),
  'PENDING',
  'room-code knowledge creates only a pending request'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  pg_catalog.format(
    'select public.review_player_claim(%L, %L, %s, %L)',
    (select result ->> 'roomId' from onboarding_room),
    (select result ->> 'claimId' from first_claim),
    (select room.state_version from app_private.rooms as room
      where room.id = (select (result ->> 'roomId')::uuid from onboarding_room)),
    'APPROVE'
  ),
  'the Game Master can approve a current claim'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_memberships as membership
    where membership.room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
      and membership.player_id = (select id from onboarding_players where seat_order = 1)
      and membership.status = 'ACTIVE'
  ),
  1,
  'approval binds exactly one active device to the stable player identity'
);

-- Complete the remaining claims, acknowledgements, and directed descriptions.
do $setup$
declare
  target_room_id uuid := (select (result ->> 'roomId')::uuid from onboarding_room);
  host_id uuid := 'a0100000-0000-4000-8000-000000000001';
  user_ids uuid[] := array[
    'a0100000-0000-4000-8000-000000000002'::uuid,
    'a0100000-0000-4000-8000-000000000003'::uuid,
    'a0100000-0000-4000-8000-000000000004'::uuid,
    'a0100000-0000-4000-8000-000000000005'::uuid
  ];
  seat integer;
  subject record;
  player_id uuid;
  claim_id uuid;
  response_text text;
begin
  for seat in 2..4 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', user_ids[seat]::text, 'role', 'authenticated')::text,
      true
    );
    perform public.request_player_claim(
      target_room_id,
      (select id from onboarding_players where seat_order = seat),
      'INITIAL_CLAIM'
    );
    select membership.id into claim_id
    from app_private.room_memberships as membership
    where membership.room_id = target_room_id
      and membership.auth_user_id = user_ids[seat]
      and membership.status = 'PENDING';
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', host_id::text, 'role', 'authenticated')::text,
      true
    );
    perform public.review_player_claim(
      target_room_id,
      claim_id,
      (select state_version from app_private.rooms where id = target_room_id),
      'APPROVE'
    );
  end loop;

  for seat in 1..4 loop
    player_id := (select id from onboarding_players where seat_order = seat);
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', user_ids[seat]::text, 'role', 'authenticated')::text,
      true
    );
    perform public.acknowledge_player_fictional_use(
      target_room_id,
      (select state_version from app_private.rooms where id = target_room_id)
    );
    for subject in
      select id, seat_order from onboarding_players
      where id <> player_id order by seat_order
    loop
      response_text := case
        when seat = 1 and subject.seat_order = 2 then 'RAW-ONE-TO-TWO'
        when seat = 2 and subject.seat_order = 1 then 'RAW-TWO-TO-ONE'
        else 'Party-safe detail ' || seat::text || '-' || subject.seat_order::text
      end;
      perform public.save_player_description(
        target_room_id,
        subject.id,
        case when seat = 1 and subject.seat_order = 4 then 'DECLINED' else 'SUBMITTED' end,
        response_text,
        (select state_version from app_private.rooms where id = target_room_id)
      );
    end loop;
  end loop;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', host_id::text, 'role', 'authenticated')::text,
    true
  );
  perform public.acknowledge_game_master_guidance(
    target_room_id,
    (select state_version from app_private.rooms where id = target_room_id)
  );
  perform public.confirm_room_consent(
    target_room_id,
    (select state_version from app_private.rooms where id = target_room_id)
  );
end;
$setup$;

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select is(
  public.get_room_readiness(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  ) ->> 'ready',
  'true',
  'all four claims, acknowledgements, consent, and 12 responses make the room ready'
);
select is(
  public.get_room_readiness(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  ) ->> 'completedDescriptionCount',
  '12',
  'an explicit decline counts toward the complete directed matrix'
);
select ok(
  public.get_onboarding_view(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  )::text not like '%RAW-ONE-TO-TWO%',
  'the Game Master readiness projection never contains raw description text'
);
select ok(
  public.get_onboarding_view(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  )::text not like '%authorPlayerId%',
  'the Game Master readiness projection never exposes description authorship'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select ok(
  public.get_onboarding_view(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  )::text like '%RAW-ONE-TO-TWO%',
  'a player can restore their own raw description draft'
);
select ok(
  public.get_onboarding_view(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  )::text not like '%RAW-TWO-TO-ONE%',
  'a player cannot read another player raw description draft'
);

insert into app_private.player_notes (room_id, player_id, notes_text)
values (
  (select (result ->> 'roomId')::uuid from onboarding_room),
  (select id from onboarding_players where seat_order = 1),
  'Persistent private note'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);
create temporary table reconnect_claim as
select public.request_player_claim(
  (select (result ->> 'roomId')::uuid from onboarding_room),
  (select id from onboarding_players where seat_order = 1),
  'RECONNECT'
) as result;

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select public.review_player_claim(
  (select (result ->> 'roomId')::uuid from onboarding_room),
  (select (result ->> 'claimId')::uuid from reconnect_claim),
  (select room.state_version from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from onboarding_room)),
  'APPROVE'
);
select is(
  (
    select membership.auth_user_id
    from app_private.room_memberships as membership
    where membership.room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
      and membership.player_id = (select id from onboarding_players where seat_order = 1)
      and membership.status = 'ACTIVE'
  ),
  'a0100000-0000-4000-8000-000000000006'::uuid,
  'reconnect atomically moves the active binding to the replacement device'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.player_notes as note
    where note.room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
      and note.player_id = (select id from onboarding_players where seat_order = 1)
      and note.notes_text = 'Persistent private note'
  ),
  1,
  'player-keyed notebook state survives device replacement'
);

update app_private.room_memberships
set last_seen_at = null
where room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
  and auth_user_id = 'a0100000-0000-4000-8000-000000000006'
  and status = 'ACTIVE';
select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);
select is(
  public.record_player_heartbeat(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  ) ->> 'rateLimited',
  'false',
  'a stale active membership may refresh its heartbeat'
);
select is(
  public.record_player_heartbeat(
    (select (result ->> 'roomId')::uuid from onboarding_room)
  ) ->> 'rateLimited',
  'true',
  'heartbeats within 20 seconds are rate limited without revoking access'
);

-- A seventh, clean principal takes over as Game Master through the fragment token.
insert into auth.users (id) values ('a0100000-0000-4000-8000-000000000007');
select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000007","role":"authenticated"}',
  true
);
select lives_ok(
  $sql$
    select public.recover_game_master(
      pg_catalog.decode(pg_catalog.repeat('34', 32), 'hex'),
      pg_catalog.decode(pg_catalog.repeat('56', 32), 'hex'),
      app_private.current_database_time() + interval '90 days'
    )
  $sql$,
  'a clean replacement session can recover Game Master authority'
);
select is(
  (
    select room.host_auth_user_id
    from app_private.rooms as room
    where room.id = (select (result ->> 'roomId')::uuid from onboarding_room)
  ),
  'a0100000-0000-4000-8000-000000000007'::uuid,
  'recovery transfers the authoritative host principal'
);
select lives_ok(
  pg_catalog.format(
    'select public.get_onboarding_view(%L)',
    (select result ->> 'roomId' from onboarding_room)
  ),
  'the recovered session immediately receives the Game Master view'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a0100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  pg_catalog.format(
    'select public.get_onboarding_view(%L)',
    (select result ->> 'roomId' from onboarding_room)
  ),
  '42501',
  'room membership required',
  'the old Game Master immediately loses room projection authority'
);
select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_memberships as membership
    where membership.room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
      and membership.status = 'ACTIVE'
  ),
  4,
  'host recovery leaves all active player memberships unchanged'
);
select ok(
  exists (
    select 1 from app_private.host_recovery_tokens as token
    where token.room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
      and token.token_digest = pg_catalog.decode(pg_catalog.repeat('34', 32), 'hex')
      and token.consumed_at is not null
  ) and exists (
    select 1 from app_private.host_recovery_tokens as token
    where token.room_id = (select (result ->> 'roomId')::uuid from onboarding_room)
      and token.token_digest = pg_catalog.decode(pg_catalog.repeat('56', 32), 'hex')
      and token.consumed_at is null and token.revoked_at is null
  ),
  'recovery consumes the presented token and stores only the rotated digest'
);

select * from finish();
rollback;
