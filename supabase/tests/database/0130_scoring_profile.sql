begin;

select plan(25);

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
  'app_private', 'scoring_profiles',
  'versioned scoring profiles exist'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.scoring_profiles
    where profile_version = 'score-v1'),
  1,
  'score-v1 is installed exactly once'
);

select is(
  (select pg_catalog.octet_length(checksum)
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  32,
  'score-v1 has a SHA-256 checksum'
);

select is(
  (select profile_json #>> '{weights,correctMurderer}'
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  '20',
  'score-v1 awards twenty points per correct murderer'
);

select is(
  (select profile_json #>> '{weights,fullMurdererSetBonus}'
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  '20',
  'score-v1 preserves a meaningful exact-set bonus'
);

select is(
  (select profile_json #>> '{earlyDeduction,maximumBonus}'
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  '10',
  'the early-deduction bonus is bounded at ten points'
);

select is(
  (select profile_json #>> '{factionOutcome,threshold}'
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  'STRICT_MAJORITY_OF_ALL_INNOCENTS',
  'faction outcomes use the approved strict-majority rule'
);

select is(
  (select profile_json #>> '{nonSubmitter,score}'
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  'ZERO',
  'a missing final case deterministically scores zero'
);

select is(
  (select pg_catalog.jsonb_array_length(profile_json -> 'awards')
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  3,
  'score-v1 defines three deterministic fun awards'
);

select is(
  (select profile_json ->> 'scoreboardTieBehavior'
    from app_private.scoring_profiles where profile_version = 'score-v1'),
  'SHARED_RANK',
  'scoreboard ties retain a shared rank'
);

select is(
  app_private.calculate_player_score(
    'score-v1', 2, 0, true, 1, 0, true, true, 5, 10
  ) ->> 'totalPoints',
  '110',
  'a complete two-murderer case produces the reviewed full score'
);

select is(
  app_private.calculate_player_score(
    'score-v1', 1, 1, false, 0, 0, true, false, 2, 0
  ) ->> 'totalPoints',
  '31',
  'a partial multi-murderer deduction retains partial credit'
);

select is(
  app_private.calculate_player_score(
    'score-v1', 0, 3, false, 0, 2, false, false, 0, 0
  ) ->> 'totalPoints',
  '0',
  'incorrect guesses cannot drive a displayed score below zero'
);

select is(
  app_private.calculate_player_score(
    'score-v1', 0, 0, false, 0, 0, false, false, 99, 0
  ) #>> '{breakdown,evidence}',
  '15',
  'evidence points are capped at fifteen'
);

select is(
  pg_temp.capture_sqlstate($sql$
    select app_private.calculate_player_score(
      'score-v1', -1, 0, false, 0, 0, false, false, 0, 0
    )
  $sql$),
  '22023',
  'negative scoring inputs are rejected'
);

select is(
  pg_temp.capture_sqlstate($sql$
    select app_private.calculate_player_score(
      'score-v1', 1, 0, true, 0, 0, false, false, 2, 11
    )
  $sql$),
  '22023',
  'an early bonus cannot exceed the profile maximum'
);

select is(
  pg_temp.capture_sqlstate($sql$
    select app_private.calculate_player_score(
      'missing-profile', 1, 0, true, 0, 0, false, false, 0, 0
    )
  $sql$),
  '22023',
  'scoring cannot run against an unknown profile version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.scoring_profiles
    set profile_json = '{}'::jsonb
    where profile_version = 'score-v1'
  $sql$),
  '23514',
  'an installed scoring profile cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.scoring_profiles
    where profile_version = 'score-v1'
  $sql$),
  '23514',
  'an installed scoring profile cannot be deleted'
);

insert into app_private.scoring_profiles (
  profile_version, profile_json, checksum
)
select 'score-test-v2', profile_json, decode(repeat('ff',32),'hex')
from app_private.scoring_profiles
where profile_version = 'score-v1';

select ok(
  (
    select checksum <> decode(repeat('ff',32),'hex')
      and pg_catalog.octet_length(checksum) = 32
    from app_private.scoring_profiles
    where profile_version = 'score-test-v2'
  ),
  'the database derives rather than trusts a scoring checksum'
);

select ok(
  (
    select checksum = extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.jsonb_build_object(
          'profileVersion', profile_version,
          'profile', profile_json
        )::text,
        'UTF8'
      ),
      'sha256'
    )
    from app_private.scoring_profiles
    where profile_version = 'score-test-v2'
  ),
  'a scoring checksum is reproducible from canonical fields'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_constraint as constraint_record
    join pg_catalog.pg_class as relation
      on relation.oid = constraint_record.conrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relname in ('rooms', 'canonical_stories', 'scoring_snapshots')
      and constraint_record.contype = 'f'
      and constraint_record.confrelid = 'app_private.scoring_profiles'::regclass
  ),
  3,
  'room, canonical story, and frozen score all reference a profile version'
);

select ok(
  not pg_catalog.has_table_privilege(
    'authenticated', 'app_private.scoring_profiles', 'SELECT'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.calculate_player_score(text,integer,integer,boolean,integer,integer,boolean,boolean,integer,integer)',
    'EXECUTE'
  ),
  'API roles cannot bypass scoring commands or profile projections'
);

select ok(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relname = 'scoring_profiles'
  ),
  'scoring profiles retain the closed private-schema RLS baseline'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.scoring_profiles (
      profile_version, profile_json, checksum
    ) values (
      'invalid-score',
      '{"weights":{},"earlyDeduction":{},"factionOutcome":{},"nonSubmitter":{},"awards":[]}',
      decode(repeat('00',32),'hex')
    )
  $sql$),
  '23514',
  'incomplete scoring profiles are rejected'
);

select * from finish();

rollback;
