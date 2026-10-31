begin;

select plan(21);

create or replace function pg_temp.capture_sqlstate(command text)
returns text
language plpgsql
as $function$
begin
  execute command;
  return null;
exception
  when others then return sqlstate;
end;
$function$;

create or replace function pg_temp.uuid_from_seed(seed text)
returns uuid
language plpgsql
immutable
as $function$
declare
  hash text := pg_catalog.md5(seed);
begin
  return (
    pg_catalog.substr(hash, 1, 8) || '-' ||
    pg_catalog.substr(hash, 9, 4) || '-4' ||
    pg_catalog.substr(hash, 14, 3) || '-8' ||
    pg_catalog.substr(hash, 18, 3) || '-' ||
    pg_catalog.substr(hash, 21, 12)
  )::uuid;
end;
$function$;

create or replace function pg_temp.build_room_fixture(
  fixture_name text,
  fixture_room_id uuid,
  fixture_host_id uuid,
  fixture_room_code text,
  fixture_player_count integer,
  fixture_duration integer
)
returns void
language plpgsql
as $function$
declare
  seat integer;
  fixture_player_id uuid;
  fixture_auth_id uuid;
  fixture_membership_id uuid;
  recommendation app_private.faction_recommendation_profiles%rowtype;
begin
  insert into auth.users (id) values (fixture_host_id);

  select profile.* into recommendation
  from app_private.faction_recommendation_profiles as profile
  where profile.profile_version = 'factions-v1'
    and profile.player_count = fixture_player_count;

  insert into app_private.rooms (
    id, room_code, host_auth_user_id, status, state_version,
    config_json, scoring_profile_version,
    duration_profile_version, duration_minutes,
    host_guidance_acknowledged_at, room_consent_confirmed_at
  )
  values (
    fixture_room_id, fixture_room_code, fixture_host_id, 'LOBBY', 1,
    pg_catalog.jsonb_build_object(
      'fixture', fixture_name,
      'playerCount', fixture_player_count,
      'murderers', recommendation.murderer_count,
      'accomplices', recommendation.accomplice_count,
      'innocents', recommendation.innocent_count
    ),
    'score-v1', 'duration-v1', fixture_duration,
    app_private.current_database_time(), app_private.current_database_time()
  );

  insert into app_private.room_host_principals (
    room_id, auth_user_id
  ) values (fixture_room_id, fixture_host_id);

  for seat in 1..fixture_player_count loop
    fixture_player_id := pg_temp.uuid_from_seed(
      fixture_name || ':player:' || seat::text
    );
    fixture_auth_id := pg_temp.uuid_from_seed(
      fixture_name || ':auth:' || seat::text
    );
    fixture_membership_id := pg_temp.uuid_from_seed(
      fixture_name || ':membership:' || seat::text
    );

    insert into auth.users (id) values (fixture_auth_id);

    insert into app_private.players (
      id, room_id, display_name, display_name_normalized, costume,
      seat_order, fictional_use_acknowledged_at
    ) values (
      fixture_player_id, fixture_room_id,
      fixture_name || ' Player ' || seat::text,
      pg_catalog.lower(fixture_name) || '-player-' || seat::text,
      'Costume ' || seat::text, seat,
      app_private.current_database_time()
    );

    insert into app_private.room_memberships (
      id, room_id, auth_user_id, player_id, status, request_kind,
      approved_by_auth_user_id, last_seen_at, joined_at
    ) values (
      fixture_membership_id, fixture_room_id, fixture_auth_id,
      fixture_player_id, 'ACTIVE', 'INITIAL_CLAIM', fixture_host_id,
      app_private.current_database_time(), app_private.current_database_time()
    );
  end loop;

  insert into app_private.player_descriptions (
    room_id, author_player_id, subject_player_id, description_text
  )
  select
    fixture_room_id,
    author.id,
    subject.id,
    'Fixture-safe fictional description from seat '
      || author.seat_order::text || ' for seat ' || subject.seat_order::text
  from app_private.players as author
  join app_private.players as subject
    on subject.room_id = author.room_id and subject.id <> author.id
  where author.room_id = fixture_room_id;
end;
$function$;

select is(
  (select pg_catalog.count(*)::integer
    from supabase_migrations.schema_migrations
    where version between '20261030000000' and '20261030210000'),
  22,
  'every foundation-through-gameplay-fix migration replayed from empty'
);

select is(
  (select pg_catalog.count(distinct version)::integer
    from supabase_migrations.schema_migrations
    where version between '20261030000000' and '20261030210000'),
  22,
  'forward migration versions are unique'
);

select is(
  (select pg_catalog.max(version)
    from supabase_migrations.schema_migrations),
  '20261030210000',
  'the clean worker reached the expected schema head'
);

select pg_temp.build_room_fixture(
  'Minimal',
  'e0000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000001',
  'MINIMUM', 0, 30
);
select pg_temp.build_room_fixture(
  'Four',
  'e0000000-0000-4000-8000-000000000004',
  'e1000000-0000-4000-8000-000000000004',
  'FOURPLAY', 4, 30
);
select pg_temp.build_room_fixture(
  'Twelve',
  'e0000000-0000-4000-8000-000000000012',
  'e1000000-0000-4000-8000-000000000012',
  'TWELVE12', 12, 120
);

set constraints all immediate;

select is(
  (select player_count::integer from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000001'),
  0,
  'the minimal fixture builds a host-only setup room'
);

select is(
  (select player_count::integer from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000004'),
  4,
  'the minimum supported party fixture contains four players'
);

select is(
  (select player_count::integer from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000012'),
  12,
  'the maximum supported party fixture contains twelve players'
);

select is(
  (select active_membership_count::integer
    from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000004'),
  4,
  'the four-player fixture binds every player to one active device'
);

select is(
  (select active_membership_count::integer
    from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000012'),
  12,
  'the twelve-player fixture binds every player to one active device'
);

select is(
  (select submitted_description_count::integer
    from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000004'),
  12,
  'the four-player fixture builds the complete directed description matrix'
);

select is(
  (select submitted_description_count::integer
    from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000012'),
  132,
  'the twelve-player fixture builds all 132 other-player descriptions'
);

select ok(
  (
    select acknowledged_player_count = player_count
      and host_guidance_acknowledged
      and room_consent_confirmed
    from app_private.room_readiness_inputs
    where room_id = 'e0000000-0000-4000-8000-000000000012'
  ),
  'the maximum fixture satisfies all consent/readiness inputs'
);

select is(
  (select duration_minutes::integer from app_private.rooms
    where id = 'e0000000-0000-4000-8000-000000000004'),
  30,
  'the four-player fixture retains the shortest pacing profile'
);

select is(
  (select duration_minutes::integer from app_private.rooms
    where id = 'e0000000-0000-4000-8000-000000000012'),
  120,
  'the twelve-player fixture retains the longest pacing profile'
);

select is(
  (select (config_json ->> 'murderers') || '/'
    || (config_json ->> 'accomplices') || '/'
    || (config_json ->> 'innocents')
    from app_private.rooms
    where id = 'e0000000-0000-4000-8000-000000000004'),
  '1/0/3',
  'the four-player fixture uses its reviewed faction recommendation'
);

select is(
  (select (config_json ->> 'murderers') || '/'
    || (config_json ->> 'accomplices') || '/'
    || (config_json ->> 'innocents')
    from app_private.rooms
    where id = 'e0000000-0000-4000-8000-000000000012'),
  '3/2/7',
  'the twelve-player fixture uses its reviewed faction recommendation'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.room_memberships as membership
    join app_private.rooms as room on room.id = membership.room_id
    where membership.auth_user_id = room.host_auth_user_id
  ),
  0,
  'no representative fixture binds its dedicated Game Master as a player'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.players (
      room_id, display_name, display_name_normalized, costume, seat_order
    ) values (
      'e0000000-0000-4000-8000-000000000012',
      'Thirteenth', 'thirteenth', 'Extra', 13
    )
  $sql$),
  '23514',
  'the maximum fixture fails closed on a thirteenth seat'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.room_memberships (
      room_id, auth_user_id, player_id, status, request_kind,
      approved_by_auth_user_id, joined_at
    ) values (
      'e0000000-0000-4000-8000-000000000004',
      'e1000000-0000-4000-8000-000000000012',
      (select id from app_private.players
        where room_id = 'e0000000-0000-4000-8000-000000000012'
        order by seat_order limit 1),
      'ACTIVE', 'INITIAL_CLAIM',
      'e1000000-0000-4000-8000-000000000004',
      app_private.current_database_time()
    )
  $sql$),
  '23503',
  'representative fixtures fail closed on cross-room player references'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.duration_profiles
    set round_count = 5
    where profile_version = 'duration-v1' and duration_minutes = 30
  $sql$),
  '23514',
  'fixture-referenced profile versions remain immutable'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.rooms
    where config_json ? 'fixture'
  ),
  3,
  'failed constraint probes roll back without corrupting any fixture'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relkind in ('r', 'p')
      and not relation.relrowsecurity
  ),
  'every private table at schema head retains closed RLS'
);

select * from finish();

rollback;
