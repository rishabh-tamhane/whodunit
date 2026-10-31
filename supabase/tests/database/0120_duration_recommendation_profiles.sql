begin;

select plan(30);

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

select has_table(
  'app_private', 'duration_profiles',
  'versioned duration profiles exist'
);
select has_table(
  'app_private', 'faction_recommendation_profiles',
  'versioned faction recommendation profiles exist'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.duration_profiles
    where profile_version = 'duration-v1'),
  5,
  'duration-v1 covers every supported target duration'
);

select is(
  (select pg_catalog.count(*)::integer
    from app_private.faction_recommendation_profiles
    where profile_version = 'factions-v1'),
  9,
  'factions-v1 covers every supported player count'
);

select is(
  (
    select pg_catalog.array_agg(duration_minutes order by duration_minutes)
    from app_private.duration_profiles
    where profile_version = 'duration-v1'
  ),
  array[30,45,60,90,120]::smallint[],
  'the pacing profile supports exactly 30, 45, 60, 90, and 120 minutes'
);

select ok(
  not exists (
    select 1 from app_private.duration_profiles
    where pg_catalog.octet_length(checksum) <> 32
  ),
  'every duration profile has a SHA-256 checksum'
);

select ok(
  not exists (
    select 1 from app_private.faction_recommendation_profiles
    where pg_catalog.octet_length(checksum) <> 32
  ),
  'every faction recommendation has a SHA-256 checksum'
);

select is(
  (
    select pg_catalog.string_agg(
      duration_minutes::text || ':' || round_count::text,
      ',' order by duration_minutes
    )
    from app_private.duration_profiles
    where profile_version = 'duration-v1'
  ),
  '30:2,45:3,60:3,90:4,120:5',
  'round counts scale deterministically with selected duration'
);

select ok(
  not exists (
    select 1
    from app_private.duration_profiles as profile
    cross join lateral (
      select pg_catalog.sum(value::integer)::integer as round_total
      from pg_catalog.jsonb_array_elements_text(
        profile.profile_json -> 'roundTargetMinutes'
      ) as element(value)
    ) as rounds
    where (profile.profile_json ->> 'introMinutes')::integer
      + rounds.round_total
      + (profile.profile_json ->> 'finalAccusationMinutes')::integer
      + (profile.profile_json ->> 'revealMinutes')::integer
      <> profile.duration_minutes
  ),
  'opening, investigation, accusation, and reveal targets sum to duration'
);

select ok(
  not exists (
    select 1 from app_private.duration_profiles
    where (profile_json ->> 'evidenceEventMinimum')::integer < round_count
      or (profile_json ->> 'missionsPerPlayerPerRound')::integer <> 1
  ),
  'every round guarantees evidence cadence and one mission per player'
);

select is(
  (
    select pg_catalog.array_agg(player_count order by player_count)
    from app_private.faction_recommendation_profiles
    where profile_version = 'factions-v1'
  ),
  array[4,5,6,7,8,9,10,11,12]::smallint[],
  'recommendations cover every party size from 4 through 12'
);

select ok(
  not exists (
    select 1 from app_private.faction_recommendation_profiles
    where murderer_count + accomplice_count + innocent_count <> player_count
  ),
  'every recommended faction distribution sums to player count'
);

select ok(
  not exists (
    select 1 from app_private.faction_recommendation_profiles
    where murderer_count < 1 or innocent_count < 1
  ),
  'every recommendation contains a murderer and an innocent'
);

select is(
  (
    select pg_catalog.concat_ws(
      '/', murderer_count, accomplice_count, innocent_count
    )
    from app_private.faction_recommendation_profiles
    where profile_version = 'factions-v1' and player_count = 12
  ),
  '3/2/7',
  'the largest supported party has a reviewed balanced default'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.duration_profiles
    set round_count = 5
    where profile_version = 'duration-v1' and duration_minutes = 30
  $sql$),
  '23514',
  'an installed duration profile cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.duration_profiles
    where profile_version = 'duration-v1' and duration_minutes = 30
  $sql$),
  '23514',
  'an installed duration profile cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.faction_recommendation_profiles
    set innocent_count = 2
    where profile_version = 'factions-v1' and player_count = 4
  $sql$),
  '23514',
  'an installed faction recommendation cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.faction_recommendation_profiles
    where profile_version = 'factions-v1' and player_count = 4
  $sql$),
  '23514',
  'an installed faction recommendation cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.duration_profiles (
      profile_version, duration_minutes, round_count, profile_json, checksum
    ) values (
      'invalid-duration', 30, 2,
      '{
        "durationMinutes":30,"roundCount":2,"introMinutes":3,
        "roundTargetMinutes":[5,5],"finalAccusationMinutes":4,
        "revealMinutes":5,"missionsPerPlayerPerRound":1,
        "evidenceEventMinimum":4,"evidenceEventMaximum":6,
        "interventionCapPerRound":1
      }'::jsonb,
      decode(repeat('00',32),'hex')
    )
  $sql$),
  '23514',
  'duration targets must add up to the selected duration'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.faction_recommendation_profiles (
      profile_version, player_count, murderer_count, accomplice_count,
      innocent_count, recommendation_json, checksum
    ) values (
      'invalid-factions', 4, 1, 1, 1,
      '{"playerCount":4,"murderers":1,"accomplices":1,"innocents":1,"rationale":"invalid"}',
      decode(repeat('00',32),'hex')
    )
  $sql$),
  '23514',
  'recommended faction counts must sum to player count'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.faction_recommendation_profiles (
      profile_version, player_count, murderer_count, accomplice_count,
      innocent_count, recommendation_json, checksum
    ) values (
      'mismatched-payload', 4, 1, 0, 3,
      '{"playerCount":4,"murderers":2,"accomplices":0,"innocents":2,"rationale":"mismatch"}',
      decode(repeat('00',32),'hex')
    )
  $sql$),
  '23514',
  'recommendation payload counts must match normalized lookup fields'
);

insert into app_private.duration_profiles (
  profile_version, duration_minutes, round_count, profile_json, checksum
)
values (
  'duration-test-v2', 30, 2,
  '{
    "durationMinutes":30,"roundCount":2,"introMinutes":3,
    "roundTargetMinutes":[9,9],"finalAccusationMinutes":4,
    "revealMinutes":5,"missionsPerPlayerPerRound":1,
    "evidenceEventMinimum":4,"evidenceEventMaximum":6,
    "interventionCapPerRound":1
  }'::jsonb,
  decode(repeat('ff',32),'hex')
);

select ok(
  (
    select checksum <> decode(repeat('ff',32),'hex')
      and pg_catalog.octet_length(checksum) = 32
    from app_private.duration_profiles
    where profile_version = 'duration-test-v2' and duration_minutes = 30
  ),
  'the database derives a canonical checksum instead of trusting callers'
);

select ok(
  (
    select checksum = extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.jsonb_build_object(
          'profileVersion', profile_version,
          'durationMinutes', duration_minutes,
          'roundCount', round_count,
          'profile', profile_json
        )::text,
        'UTF8'
      ),
      'sha256'
    )
    from app_private.duration_profiles
    where profile_version = 'duration-test-v2' and duration_minutes = 30
  ),
  'the stored duration checksum is reproducible from canonical fields'
);

insert into auth.users (id)
values ('e0000000-0000-4000-8000-000000000001');

insert into app_private.rooms (
  id, room_code, host_auth_user_id,
  duration_profile_version, duration_minutes
)
values (
  'e1000000-0000-4000-8000-000000000001',
  'PROFILE1', 'e0000000-0000-4000-8000-000000000001',
  'duration-v1', 60
);

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values (
  'e2000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000001',
  'e0000000-0000-4000-8000-000000000001'
);

set constraints all immediate;

select is(
  (select duration_minutes::integer from app_private.rooms
    where id = 'e1000000-0000-4000-8000-000000000001'),
  60,
  'a room retains its exact duration profile reference'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set duration_profile_version = 'missing-version'
    where id = 'e1000000-0000-4000-8000-000000000001'
  $sql$),
  '23503',
  'a room cannot reference an unknown duration profile'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set duration_profile_version = null
    where id = 'e1000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a room cannot store a partial duration profile reference'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from information_schema.columns
    where table_schema = 'app_private' and table_name = 'rooms'
      and column_name in ('duration_profile_version', 'duration_minutes')
      and is_nullable = 'YES'
  ),
  2,
  'migration compatibility permits pre-profile rooms until creation commands enforce selection'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon', 'app_private.duration_profiles', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'app_private.faction_recommendation_profiles', 'SELECT'
  ),
  'API roles cannot bypass application APIs to read or mutate profiles'
);

select ok(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relname = 'duration_profiles'
  )
  and (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relname = 'faction_recommendation_profiles'
  ),
  'new profile tables retain the closed private-schema RLS baseline'
);

select ok(
  not pg_catalog.has_function_privilege(
    'authenticated', 'app_private.prepare_duration_profile()', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role', 'app_private.enforce_versioned_profile_immutable()', 'EXECUTE'
  ),
  'profile trigger functions are not API-callable'
);

select * from finish();

rollback;
