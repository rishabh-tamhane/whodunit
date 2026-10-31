-- DB-13: immutable deterministic scoring configuration.

create table app_private.scoring_profiles (
  profile_version text primary key,
  profile_json jsonb not null,
  checksum bytea not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint scoring_profiles_version_present check (
    pg_catalog.char_length(pg_catalog.btrim(profile_version)) between 1 and 50
  ),
  constraint scoring_profiles_payload_object check (
    pg_catalog.jsonb_typeof(profile_json) = 'object'
  ),
  constraint scoring_profiles_checksum_length check (
    pg_catalog.octet_length(checksum) = 32
  )
);

alter table app_private.scoring_profiles enable row level security;
revoke all on table app_private.scoring_profiles
  from public, anon, authenticated, service_role;

create function app_private.prepare_scoring_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  weights jsonb;
  early_rule jsonb;
begin
  weights := new.profile_json -> 'weights';
  early_rule := new.profile_json -> 'earlyDeduction';

  if pg_catalog.jsonb_typeof(weights) <> 'object'
    or pg_catalog.jsonb_typeof(early_rule) <> 'object'
    or (weights ->> 'correctMurderer')::integer < 0
    or (weights ->> 'incorrectMurdererPenalty')::integer < 0
    or (weights ->> 'fullMurdererSetBonus')::integer < 0
    or (weights ->> 'correctAccomplice')::integer < 0
    or (weights ->> 'incorrectAccomplicePenalty')::integer < 0
    or (weights ->> 'correctMotive')::integer < 0
    or (weights ->> 'correctMethod')::integer < 0
    or (weights ->> 'correctEvidenceEach')::integer < 0
    or (weights ->> 'correctEvidenceCap')::integer < 0
    or (early_rule ->> 'qualifyingEvidenceMinimum')::integer < 1
    or (early_rule ->> 'pointsPerRemainingRound')::integer < 0
    or (early_rule ->> 'maximumBonus')::integer < 0
    or new.profile_json #>> '{factionOutcome,threshold}'
      <> 'STRICT_MAJORITY_OF_ALL_INNOCENTS'
    or new.profile_json #>> '{factionOutcome,nonSubmitterVote}' <> 'NO_VOTE'
    or new.profile_json #>> '{nonSubmitter,score}' <> 'ZERO'
    or pg_catalog.jsonb_array_length(new.profile_json -> 'awards') < 1
  then
    raise exception using
      errcode = '23514',
      message = 'invalid deterministic scoring profile';
  end if;

  new.checksum := extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'profileVersion', new.profile_version,
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
      message = 'invalid scoring profile numeric configuration';
end;
$function$;

create trigger scoring_profiles_prepare
before insert on app_private.scoring_profiles
for each row execute function app_private.prepare_scoring_profile();

create trigger scoring_profiles_immutable
before update or delete on app_private.scoring_profiles
for each row execute function app_private.enforce_versioned_profile_immutable();

insert into app_private.scoring_profiles (
  profile_version,
  profile_json,
  checksum
)
values (
  'score-v1',
  '{
    "weights": {
      "correctMurderer": 20,
      "incorrectMurdererPenalty": 5,
      "fullMurdererSetBonus": 20,
      "correctAccomplice": 5,
      "incorrectAccomplicePenalty": 2,
      "correctMotive": 10,
      "correctMethod": 10,
      "correctEvidenceEach": 3,
      "correctEvidenceCap": 15
    },
    "earlyDeduction": {
      "qualifyingEvidenceMinimum": 2,
      "pointsPerRemainingRound": 2,
      "maximumBonus": 10,
      "usesEarliestQualifyingTheoryOnly": true
    },
    "factionOutcome": {
      "threshold": "STRICT_MAJORITY_OF_ALL_INNOCENTS",
      "requiresEveryMurderer": true,
      "nonSubmitterVote": "NO_VOTE",
      "murderersWinWhenAnyEscapes": true,
      "accomplicesShareMurdererOutcome": true
    },
    "nonSubmitter": {
      "score": "ZERO",
      "automaticCase": false
    },
    "scoreboardTieBehavior": "SHARED_RANK",
    "awards": [
      {
        "code": "MASTER_DETECTIVE",
        "metric": "TOTAL_SCORE",
        "tieBreakers": ["FINAL_SUBMITTED_AT_ASC", "SEAT_ORDER_ASC"]
      },
      {
        "code": "EARLIEST_BREAKTHROUGH",
        "metric": "QUALIFYING_THEORY_ROUND_ASC",
        "tieBreakers": ["THEORY_SUBMITTED_AT_ASC", "SEAT_ORDER_ASC"]
      },
      {
        "code": "EVIDENCE_HOUND",
        "metric": "CORRECT_EVIDENCE_COUNT",
        "tieBreakers": ["TOTAL_SCORE_DESC", "SEAT_ORDER_ASC"]
      }
    ]
  }'::jsonb,
  decode(repeat('00', 32), 'hex')
);

alter table app_private.rooms
  add constraint rooms_scoring_profile_fk foreign key (scoring_profile_version)
  references app_private.scoring_profiles (profile_version)
  on update restrict on delete restrict;

alter table app_private.canonical_stories
  add constraint canonical_stories_scoring_profile_fk foreign key (
    scoring_profile_version
  ) references app_private.scoring_profiles (profile_version)
  on update restrict on delete restrict;

alter table app_private.scoring_snapshots
  add constraint scoring_snapshots_profile_fk foreign key (
    scoring_profile_version
  ) references app_private.scoring_profiles (profile_version)
  on update restrict on delete restrict;

create or replace function app_private.validate_scoring_snapshot_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_story app_private.canonical_stories%rowtype;
  source_profile_checksum bytea;
begin
  select story.*
  into source_story
  from app_private.canonical_stories as story
  where story.room_id = new.room_id
    and story.id = new.story_id;

  select profile.checksum
  into source_profile_checksum
  from app_private.scoring_profiles as profile
  where profile.profile_version = new.scoring_profile_version;

  if source_story.id is null
    or source_profile_checksum is null
    or new.scoring_profile_version <> source_story.scoring_profile_version
    or new.scoring_profile_checksum <> source_profile_checksum
    or new.story_package_checksum <> source_story.package_checksum
    or new.solution_checksum <> source_story.solution_checksum then
    raise exception using
      errcode = '23514',
      message = 'scoring snapshot does not match its canonical story and profile',
      constraint = 'scoring_snapshots_canonical_source_match';
  end if;

  return new;
end;
$function$;

create function app_private.calculate_player_score(
  target_profile_version text,
  correct_murderers integer,
  incorrect_murderers integer,
  exact_murderer_set boolean,
  correct_accomplices integer,
  incorrect_accomplices integer,
  motive_correct boolean,
  method_correct boolean,
  correct_evidence_count integer,
  early_bonus integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  profile jsonb;
  weights jsonb;
  murderer_points integer;
  accomplice_points integer;
  motive_points integer;
  method_points integer;
  evidence_points integer;
  full_set_points integer;
  uncapped_total integer;
  total_points integer;
begin
  select scoring.profile_json into profile
  from app_private.scoring_profiles as scoring
  where scoring.profile_version = target_profile_version;

  if profile is null then
    raise exception using errcode = '22023', message = 'unknown scoring profile';
  end if;

  if correct_murderers < 0
    or incorrect_murderers < 0
    or correct_accomplices < 0
    or incorrect_accomplices < 0
    or correct_evidence_count < 0
    or early_bonus < 0
    or early_bonus > (profile #>> '{earlyDeduction,maximumBonus}')::integer
  then
    raise exception using errcode = '22023', message = 'invalid scoring inputs';
  end if;

  weights := profile -> 'weights';
  murderer_points :=
    correct_murderers * (weights ->> 'correctMurderer')::integer
    - incorrect_murderers * (weights ->> 'incorrectMurdererPenalty')::integer;
  accomplice_points :=
    correct_accomplices * (weights ->> 'correctAccomplice')::integer
    - incorrect_accomplices * (weights ->> 'incorrectAccomplicePenalty')::integer;
  motive_points := case when motive_correct
    then (weights ->> 'correctMotive')::integer else 0 end;
  method_points := case when method_correct
    then (weights ->> 'correctMethod')::integer else 0 end;
  evidence_points := least(
    correct_evidence_count * (weights ->> 'correctEvidenceEach')::integer,
    (weights ->> 'correctEvidenceCap')::integer
  );
  full_set_points := case when exact_murderer_set
    then (weights ->> 'fullMurdererSetBonus')::integer else 0 end;

  uncapped_total := murderer_points + accomplice_points + motive_points
    + method_points + evidence_points + full_set_points + early_bonus;
  total_points := greatest(0, uncapped_total);

  return pg_catalog.jsonb_build_object(
    'profileVersion', target_profile_version,
    'totalPoints', total_points,
    'breakdown', pg_catalog.jsonb_build_object(
      'murderers', murderer_points,
      'fullSetBonus', full_set_points,
      'accomplices', accomplice_points,
      'motive', motive_points,
      'method', method_points,
      'evidence', evidence_points,
      'earlyDeduction', early_bonus,
      'preFloorTotal', uncapped_total
    )
  );
end;
$function$;

revoke execute on function app_private.prepare_scoring_profile()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.calculate_player_score(
  text, integer, integer, boolean, integer, integer, boolean, boolean,
  integer, integer
) from public, anon, authenticated, service_role;

comment on table app_private.scoring_profiles is
  'Immutable reviewed scoring, faction-outcome, tie, and award rules.';
comment on function app_private.calculate_player_score(
  text, integer, integer, boolean, integer, integer, boolean, boolean,
  integer, integer
) is 'Pure deterministic score breakdown; the LLM never participates.';
