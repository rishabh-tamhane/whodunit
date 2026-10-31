-- DB-12: immutable pacing and balanced-faction recommendations.

create table app_private.duration_profiles (
  profile_version text not null,
  duration_minutes smallint not null,
  round_count smallint not null,
  profile_json jsonb not null,
  checksum bytea not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  primary key (profile_version, duration_minutes),
  constraint duration_profiles_duration_supported check (
    duration_minutes in (30, 45, 60, 90, 120)
  ),
  constraint duration_profiles_round_count_supported check (
    round_count between 2 and 5
  ),
  constraint duration_profiles_version_present check (
    pg_catalog.char_length(pg_catalog.btrim(profile_version)) between 1 and 50
  ),
  constraint duration_profiles_profile_object check (
    pg_catalog.jsonb_typeof(profile_json) = 'object'
  ),
  constraint duration_profiles_checksum_length check (
    pg_catalog.octet_length(checksum) = 32
  )
);

create table app_private.faction_recommendation_profiles (
  profile_version text not null,
  player_count smallint not null,
  murderer_count smallint not null,
  accomplice_count smallint not null,
  innocent_count smallint not null,
  recommendation_json jsonb not null,
  checksum bytea not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  primary key (profile_version, player_count),
  constraint faction_recommendations_player_count_supported check (
    player_count between 4 and 12
  ),
  constraint faction_recommendations_counts_valid check (
    murderer_count >= 1
    and accomplice_count >= 0
    and innocent_count >= 1
    and murderer_count + accomplice_count + innocent_count = player_count
  ),
  constraint faction_recommendations_version_present check (
    pg_catalog.char_length(pg_catalog.btrim(profile_version)) between 1 and 50
  ),
  constraint faction_recommendations_payload_object check (
    pg_catalog.jsonb_typeof(recommendation_json) = 'object'
  ),
  constraint faction_recommendations_checksum_length check (
    pg_catalog.octet_length(checksum) = 32
  )
);

alter table app_private.duration_profiles enable row level security;
alter table app_private.faction_recommendation_profiles enable row level security;

revoke all on table app_private.duration_profiles
  from public, anon, authenticated, service_role;
revoke all on table app_private.faction_recommendation_profiles
  from public, anon, authenticated, service_role;

create function app_private.prepare_duration_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  round_minutes_total integer;
  round_minutes_count integer;
begin
  if pg_catalog.jsonb_typeof(new.profile_json -> 'roundTargetMinutes') <> 'array' then
    raise exception using
      errcode = '23514',
      message = 'duration profile round targets must be an array';
  end if;

  select pg_catalog.count(*)::integer, pg_catalog.sum(value::integer)::integer
  into round_minutes_count, round_minutes_total
  from pg_catalog.jsonb_array_elements_text(
    new.profile_json -> 'roundTargetMinutes'
  ) as element(value);

  if (new.profile_json ->> 'durationMinutes')::integer <> new.duration_minutes
    or (new.profile_json ->> 'roundCount')::integer <> new.round_count
    or round_minutes_count <> new.round_count
    or round_minutes_total <= 0
    or (new.profile_json ->> 'introMinutes')::integer
      + round_minutes_total
      + (new.profile_json ->> 'finalAccusationMinutes')::integer
      + (new.profile_json ->> 'revealMinutes')::integer
      <> new.duration_minutes
    or (new.profile_json ->> 'missionsPerPlayerPerRound')::integer <> 1
    or (new.profile_json ->> 'evidenceEventMinimum')::integer < new.round_count
    or (new.profile_json ->> 'evidenceEventMaximum')::integer
      < (new.profile_json ->> 'evidenceEventMinimum')::integer
    or (new.profile_json ->> 'interventionCapPerRound')::integer not between 1 and 3
  then
    raise exception using
      errcode = '23514',
      message = 'invalid duration profile pacing configuration';
  end if;

  new.checksum := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'profileVersion', new.profile_version,
        'durationMinutes', new.duration_minutes,
        'roundCount', new.round_count,
        'profile', new.profile_json
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  return new;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '23514',
      message = 'invalid duration profile numeric configuration';
end;
$function$;

create function app_private.prepare_faction_recommendation_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (new.recommendation_json ->> 'playerCount')::integer <> new.player_count
    or (new.recommendation_json ->> 'murderers')::integer <> new.murderer_count
    or (new.recommendation_json ->> 'accomplices')::integer <> new.accomplice_count
    or (new.recommendation_json ->> 'innocents')::integer <> new.innocent_count
    or pg_catalog.char_length(
      pg_catalog.btrim(new.recommendation_json ->> 'rationale')
    ) = 0
  then
    raise exception using
      errcode = '23514',
      message = 'invalid faction recommendation configuration';
  end if;

  new.checksum := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'profileVersion', new.profile_version,
        'playerCount', new.player_count,
        'murderers', new.murderer_count,
        'accomplices', new.accomplice_count,
        'innocents', new.innocent_count,
        'recommendation', new.recommendation_json
      )::text,
      'UTF8'
    ),
    'sha256'
  );

  return new;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '23514',
      message = 'invalid faction recommendation numeric configuration';
end;
$function$;

create function app_private.enforce_versioned_profile_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception using
    errcode = '23514',
    message = 'versioned application profile is immutable',
    constraint = 'versioned_profile_immutable';
end;
$function$;

create trigger duration_profiles_prepare
before insert on app_private.duration_profiles
for each row execute function app_private.prepare_duration_profile();

create trigger duration_profiles_immutable
before update or delete on app_private.duration_profiles
for each row execute function app_private.enforce_versioned_profile_immutable();

create trigger faction_recommendations_prepare
before insert on app_private.faction_recommendation_profiles
for each row execute function app_private.prepare_faction_recommendation_profile();

create trigger faction_recommendations_immutable
before update or delete on app_private.faction_recommendation_profiles
for each row execute function app_private.enforce_versioned_profile_immutable();

insert into app_private.duration_profiles (
  profile_version, duration_minutes, round_count, profile_json,
  checksum
)
values
  (
    'duration-v1', 30, 2,
    '{
      "durationMinutes":30,
      "roundCount":2,
      "introMinutes":3,
      "roundTargetMinutes":[9,9],
      "finalAccusationMinutes":4,
      "revealMinutes":5,
      "missionsPerPlayerPerRound":1,
      "evidenceEventMinimum":4,
      "evidenceEventMaximum":6,
      "interventionCapPerRound":1
    }'::jsonb,
    decode(repeat('00', 32), 'hex')
  ),
  (
    'duration-v1', 45, 3,
    '{
      "durationMinutes":45,
      "roundCount":3,
      "introMinutes":4,
      "roundTargetMinutes":[9,9,9],
      "finalAccusationMinutes":6,
      "revealMinutes":8,
      "missionsPerPlayerPerRound":1,
      "evidenceEventMinimum":6,
      "evidenceEventMaximum":8,
      "interventionCapPerRound":1
    }'::jsonb,
    decode(repeat('00', 32), 'hex')
  ),
  (
    'duration-v1', 60, 3,
    '{
      "durationMinutes":60,
      "roundCount":3,
      "introMinutes":5,
      "roundTargetMinutes":[12,12,12],
      "finalAccusationMinutes":8,
      "revealMinutes":11,
      "missionsPerPlayerPerRound":1,
      "evidenceEventMinimum":7,
      "evidenceEventMaximum":10,
      "interventionCapPerRound":2
    }'::jsonb,
    decode(repeat('00', 32), 'hex')
  ),
  (
    'duration-v1', 90, 4,
    '{
      "durationMinutes":90,
      "roundCount":4,
      "introMinutes":6,
      "roundTargetMinutes":[15,15,15,15],
      "finalAccusationMinutes":10,
      "revealMinutes":14,
      "missionsPerPlayerPerRound":1,
      "evidenceEventMinimum":10,
      "evidenceEventMaximum":14,
      "interventionCapPerRound":2
    }'::jsonb,
    decode(repeat('00', 32), 'hex')
  ),
  (
    'duration-v1', 120, 5,
    '{
      "durationMinutes":120,
      "roundCount":5,
      "introMinutes":8,
      "roundTargetMinutes":[17,17,17,17,17],
      "finalAccusationMinutes":12,
      "revealMinutes":15,
      "missionsPerPlayerPerRound":1,
      "evidenceEventMinimum":13,
      "evidenceEventMaximum":18,
      "interventionCapPerRound":2
    }'::jsonb,
    decode(repeat('00', 32), 'hex')
  );

insert into app_private.faction_recommendation_profiles (
  profile_version, player_count, murderer_count, accomplice_count,
  innocent_count, recommendation_json, checksum
)
values
  ('factions-v1', 4, 1, 0, 3,
    '{"playerCount":4,"murderers":1,"accomplices":0,"innocents":3,"rationale":"One hidden threat keeps a small group readable."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 5, 1, 1, 3,
    '{"playerCount":5,"murderers":1,"accomplices":1,"innocents":3,"rationale":"One accomplice adds conspiracy without overwhelming investigators."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 6, 1, 1, 4,
    '{"playerCount":6,"murderers":1,"accomplices":1,"innocents":4,"rationale":"A four-player investigating majority balances the hidden pair."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 7, 2, 0, 5,
    '{"playerCount":7,"murderers":2,"accomplices":0,"innocents":5,"rationale":"A second murderer raises uncertainty while preserving an investigating majority."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 8, 2, 1, 5,
    '{"playerCount":8,"murderers":2,"accomplices":1,"innocents":5,"rationale":"Three conspirators create cross-talk while five investigators retain agency."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 9, 2, 1, 6,
    '{"playerCount":9,"murderers":2,"accomplices":1,"innocents":6,"rationale":"A two-to-one investigating majority supports longer deduction."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 10, 2, 2, 6,
    '{"playerCount":10,"murderers":2,"accomplices":2,"innocents":6,"rationale":"Two accomplices support a larger conspiracy without adding a third murderer."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 11, 3, 1, 7,
    '{"playerCount":11,"murderers":3,"accomplices":1,"innocents":7,"rationale":"Three murderers create multiple valid leads for a large table."}', decode(repeat('00',32),'hex')),
  ('factions-v1', 12, 3, 2, 7,
    '{"playerCount":12,"murderers":3,"accomplices":2,"innocents":7,"rationale":"Five conspirators sustain complexity while investigators remain the majority."}', decode(repeat('00',32),'hex'));

alter table app_private.rooms
  add column duration_profile_version text,
  add column duration_minutes smallint,
  add constraint rooms_duration_profile_shape check (
    (duration_profile_version is null and duration_minutes is null)
    or (duration_profile_version is not null and duration_minutes is not null)
  ),
  add constraint rooms_duration_profile_fk foreign key (
    duration_profile_version,
    duration_minutes
  ) references app_private.duration_profiles (
    profile_version,
    duration_minutes
  ) on update restrict on delete restrict;

revoke execute on function app_private.prepare_duration_profile()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.prepare_faction_recommendation_profile()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.enforce_versioned_profile_immutable()
  from public, anon, authenticated, service_role;

comment on table app_private.duration_profiles is
  'Immutable reviewed pacing profiles; timers are targets, never automatic transitions.';
comment on table app_private.faction_recommendation_profiles is
  'Immutable balanced defaults; hosts may choose any separately valid distribution.';
