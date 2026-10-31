begin;

select plan(35);

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

select has_table('app_private', 'scoring_snapshots', 'frozen scoring inputs exist');
select has_table('app_private', 'player_scores', 'player scores exist');
select has_table('app_private', 'theory_scores', 'submitted theory scores exist');
select has_table('app_private', 'faction_results', 'faction results exist');
select has_table('app_private', 'player_awards', 'player awards exist');
select has_table('app_private', 'reveal_publications', 'reveal publications exist');
select has_table('app_private', 'case_files', 'finalized case files exist');

select ok(
  not pg_catalog.has_table_privilege(
    'anon', 'app_private.scoring_snapshots', 'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'app_private.case_files', 'SELECT'
  ),
  'API roles cannot read endgame storage directly'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from information_schema.columns
    where table_schema = 'app_private'
      and table_name in (
        'scoring_snapshots', 'player_scores', 'theory_scores',
        'faction_results', 'player_awards', 'reveal_publications', 'case_files'
      )
      and column_name = 'room_id'
      and is_nullable = 'NO'
  ),
  7,
  'every endgame artifact has required room scope'
);

insert into auth.users (id)
values ('f0000000-0000-4000-8000-000000000001');

insert into app_private.rooms (id, room_code, host_auth_user_id, state_version)
values (
  'f1000000-0000-4000-8000-000000000001',
  'ENDGAME1',
  'f0000000-0000-4000-8000-000000000001',
  10
);

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values (
  'f2000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f0000000-0000-4000-8000-000000000001'
);

set constraints all immediate;

insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume, seat_order
)
values
  (
    'f3000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000001',
    'Asha', 'asha', 'Detective', 1
  ),
  (
    'f3000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000001',
    'Kabir', 'kabir', 'Vampire', 2
  );

insert into app_private.story_generation_jobs (
  id, room_id, idempotency_key, status, phase, input_snapshot_json,
  model_id, prompt_version, story_schema_version, validator_version,
  started_at, finished_at
)
values (
  'f4000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f4100000-0000-4000-8000-000000000001',
  'SUCCEEDED', 'COMPLETE', '{}'::jsonb,
  'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'score-validator-v1',
  app_private.current_database_time(), app_private.current_database_time()
);

insert into app_private.canonical_stories (
  id, room_id, source_generation_job_id, story_schema_version,
  scoring_profile_version, prompt_version, model_id, package_json,
  package_checksum, solution_checksum, locked_at
)
values (
  'f5000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f4000000-0000-4000-8000-000000000001',
  'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
  decode(repeat('11', 32), 'hex'), decode(repeat('12', 32), 'hex'),
  app_private.current_database_time()
);

insert into app_private.story_rounds (
  id, room_id, story_id, sequence, title, target_duration_seconds,
  public_event_json
)
values (
  'f6000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  1, 'Investigation', 600, '{}'::jsonb
);

insert into app_private.command_receipts (
  id, room_id, idempotency_key, command_name, actor_type,
  request_hash, expected_state_version, result_state_version,
  response_status, result_json
)
values (
  'f7000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f7100000-0000-4000-8000-000000000001',
  'ENDGAME_FINALIZE', 'SYSTEM', decode(repeat('21', 32), 'hex'),
  9, 10, 200, '{}'::jsonb
);

insert into app_private.player_theories (
  id, room_id, story_id, player_id, round_id, submitted_state_version,
  structured_claim_json, command_receipt_id
)
values (
  'f8000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000001',
  'f6000000-0000-4000-8000-000000000001',
  9, '{"suspect":"Kabir"}'::jsonb,
  'f7000000-0000-4000-8000-000000000001'
);

insert into app_private.final_accusations (
  id, room_id, story_id, player_id, structured_case_json
)
values (
  'f9000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000001',
  '{"suspect":"Kabir"}'::jsonb
);

update app_private.final_accusations
set status = 'SUBMITTED', revision = 1, submitted_state_version = 9,
  submission_command_receipt_id = 'f7000000-0000-4000-8000-000000000001',
  submitted_at = app_private.current_database_time(),
  updated_at = app_private.current_database_time()
where id = 'f9000000-0000-4000-8000-000000000001';

insert into app_private.scoring_snapshots (
  id, room_id, story_id, scoring_profile_version,
  scoring_profile_checksum, story_package_checksum, solution_checksum,
  frozen_input_checksum, source_state_version, source_last_event_sequence,
  frozen_input_json
)
values (
  'fa000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'score-v1', (select checksum from app_private.scoring_profiles
    where profile_version = 'score-v1'),
  decode(repeat('11', 32), 'hex'), decode(repeat('12', 32), 'hex'),
  decode(repeat('14', 32), 'hex'), 10, 4,
  '{"submittedAccusations":1,"submittedTheories":1}'::jsonb
);

select is(
  (select pg_catalog.count(*)::integer from app_private.scoring_snapshots),
  1,
  'one frozen scoring snapshot is recorded'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.scoring_snapshots (
      room_id, story_id, scoring_profile_version, scoring_profile_checksum,
      story_package_checksum, solution_checksum, frozen_input_checksum,
      source_state_version, source_last_event_sequence, frozen_input_json
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001', 'wrong-profile',
      (select checksum from app_private.scoring_profiles
        where profile_version = 'score-v1'),
      decode(repeat('11',32),'hex'),
      decode(repeat('12',32),'hex'), decode(repeat('15',32),'hex'),
      10, 4, '{}'::jsonb
    )
  $sql$),
  '23514',
  'a scoring snapshot must use the story scoring-profile version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.scoring_snapshots
    set story_package_checksum = decode(repeat('99',32),'hex')
    where id = 'fa000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a scoring snapshot must use the canonical package checksum'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.scoring_snapshots
    set frozen_input_checksum = decode('01','hex')
    where id = 'fa000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'scoring source checksums are exactly 32 bytes'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.scoring_snapshots
    set frozen_input_json = '[]'::jsonb
    where id = 'fa000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'frozen scoring input is a structured object'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.scoring_snapshots (
      room_id, story_id, scoring_profile_version, scoring_profile_checksum,
      story_package_checksum, solution_checksum, frozen_input_checksum,
      source_state_version, source_last_event_sequence, frozen_input_json
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001', 'score-v1',
      (select checksum from app_private.scoring_profiles
        where profile_version = 'score-v1'),
      decode(repeat('11',32),'hex'),
      decode(repeat('12',32),'hex'), decode(repeat('15',32),'hex'),
      10, 4, '{}'::jsonb
    )
  $sql$),
  '23505',
  'a room has only one finalized scoring snapshot'
);

insert into app_private.player_scores (
  id, room_id, story_id, scoring_snapshot_id, player_id,
  final_accusation_id, total_points, breakdown_json, explanation
)
values (
  'fb000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000001',
  'f9000000-0000-4000-8000-000000000001',
  80, '{"suspect":50,"evidence":30}'::jsonb, 'Strong case.'
);

select is(
  (select total_points from app_private.player_scores
    where id = 'fb000000-0000-4000-8000-000000000001'),
  80,
  'a player score links to the submitted final accusation'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_scores
    set player_id = 'f3000000-0000-4000-8000-000000000002'
    where id = 'fb000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a score cannot be assigned to a player who does not own the accusation'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_scores (
      room_id, story_id, scoring_snapshot_id, player_id,
      final_accusation_id, total_points, breakdown_json, explanation
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001',
      'fa000000-0000-4000-8000-000000000001',
      'f3000000-0000-4000-8000-000000000001',
      'f9000000-0000-4000-8000-000000000001', 90, '{}', 'Duplicate.'
    )
  $sql$),
  '23505',
  'a player has only one score per frozen snapshot'
);

insert into app_private.theory_scores (
  id, room_id, story_id, scoring_snapshot_id, theory_id, player_id,
  points, breakdown_json, explanation
)
values (
  'fc000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'f8000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000001',
  25, '{"round":1}'::jsonb, 'Good early theory.'
);

select is(
  (select points from app_private.theory_scores
    where id = 'fc000000-0000-4000-8000-000000000001'),
  25,
  'a submitted theory receives a versioned score'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.theory_scores
    set player_id = 'f3000000-0000-4000-8000-000000000002'
    where id = 'fc000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a theory score must retain the submitting player'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.theory_scores (
      room_id, story_id, scoring_snapshot_id, theory_id, player_id,
      points, breakdown_json, explanation
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001',
      'fa000000-0000-4000-8000-000000000001',
      'f8000000-0000-4000-8000-000000000001',
      'f3000000-0000-4000-8000-000000000001', 1, '{}', 'Duplicate.'
    )
  $sql$),
  '23505',
  'each submitted theory is scored once per snapshot'
);

insert into app_private.faction_results (
  id, room_id, story_id, scoring_snapshot_id, faction, won,
  result_json, explanation
)
values (
  'fd000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'INNOCENT', true, '{"correctAccusations":1}', 'The investigators prevailed.'
);

select ok(
  (select won from app_private.faction_results
    where id = 'fd000000-0000-4000-8000-000000000001'),
  'a faction result records the deterministic outcome'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.faction_results (
      room_id, story_id, scoring_snapshot_id, faction, won,
      result_json, explanation
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001',
      'fa000000-0000-4000-8000-000000000001',
      'INNOCENT', false, '{}', 'Duplicate.'
    )
  $sql$),
  '23505',
  'each faction has one result per snapshot'
);

insert into app_private.player_awards (
  id, room_id, story_id, scoring_snapshot_id, player_id,
  award_code, title, description
)
values (
  'fe000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000001',
  'SHARP_EYE', 'Sharp Eye', 'Best use of physical evidence.'
);

select is(
  (select award_code from app_private.player_awards
    where id = 'fe000000-0000-4000-8000-000000000001'),
  'SHARP_EYE',
  'a deterministic award is linked to its player'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_awards (
      room_id, story_id, scoring_snapshot_id, player_id,
      award_code, title, description
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001',
      'fa000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000099',
      'INVALID_RECIPIENT', 'Invalid', 'Wrong room recipient.'
    )
  $sql$),
  '23503',
  'an award recipient must belong to the result room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_awards (
      room_id, story_id, scoring_snapshot_id, player_id,
      award_code, title, description
    ) values (
      'f1000000-0000-4000-8000-000000000001',
      'f5000000-0000-4000-8000-000000000001',
      'fa000000-0000-4000-8000-000000000001',
      'f3000000-0000-4000-8000-000000000002',
      'SHARP_EYE', 'Other', 'Duplicate code.'
    )
  $sql$),
  '23505',
  'an award code is assigned once per result snapshot'
);

insert into app_private.reveal_publications (
  id, room_id, story_id, scoring_snapshot_id, command_receipt_id,
  publication_state_version, scoring_profile_version,
  scoring_profile_checksum, story_package_checksum, solution_checksum,
  frozen_input_checksum, reveal_checksum, published_payload_json
)
values (
  'ff000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'f7000000-0000-4000-8000-000000000001', 10, 'score-v1',
  (select checksum from app_private.scoring_profiles
    where profile_version = 'score-v1'),
  decode(repeat('11',32),'hex'),
  decode(repeat('12',32),'hex'), decode(repeat('14',32),'hex'),
  decode(repeat('15',32),'hex'), '{"published":true}'::jsonb
);

select is(
  (select publication_state_version::integer from app_private.reveal_publications
    where id = 'ff000000-0000-4000-8000-000000000001'),
  10,
  'the reveal records its publication state version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.reveal_publications (
      room_id, story_id, scoring_snapshot_id, command_receipt_id,
      publication_state_version, scoring_profile_version,
      scoring_profile_checksum, story_package_checksum, solution_checksum,
      frozen_input_checksum, reveal_checksum, published_payload_json
    ) select room_id, story_id, scoring_snapshot_id, command_receipt_id,
      publication_state_version, scoring_profile_version,
      scoring_profile_checksum, story_package_checksum, solution_checksum,
      frozen_input_checksum, reveal_checksum, published_payload_json
    from app_private.reveal_publications
    where id = 'ff000000-0000-4000-8000-000000000001'
  $sql$),
  '23505',
  'a room publishes its reveal exactly once'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.reveal_publications
    set frozen_input_checksum = decode(repeat('99',32),'hex')
    where id = 'ff000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a reveal must match its frozen scoring source'
);

insert into app_private.case_files (
  id, room_id, story_id, scoring_snapshot_id, reveal_publication_id,
  case_file_schema_version, scoring_profile_version,
  scoring_profile_checksum, story_package_checksum, solution_checksum,
  frozen_input_checksum, reveal_checksum, content_checksum, content_json
)
values (
  'ee000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f5000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'ff000000-0000-4000-8000-000000000001',
  'case-file-v1', 'score-v1',
  (select checksum from app_private.scoring_profiles
    where profile_version = 'score-v1'),
  decode(repeat('11',32),'hex'), decode(repeat('12',32),'hex'),
  decode(repeat('14',32),'hex'), decode(repeat('15',32),'hex'),
  decode(repeat('16',32),'hex'), '{"complete":true}'::jsonb
);

select is(
  (select case_file_schema_version from app_private.case_files
    where id = 'ee000000-0000-4000-8000-000000000001'),
  'case-file-v1',
  'a finalized case file records its schema version'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.case_files (
      room_id, story_id, scoring_snapshot_id, reveal_publication_id,
      case_file_schema_version, scoring_profile_version,
      scoring_profile_checksum, story_package_checksum, solution_checksum,
      frozen_input_checksum, reveal_checksum, content_checksum, content_json
    ) select room_id, story_id, scoring_snapshot_id, reveal_publication_id,
      case_file_schema_version, scoring_profile_version,
      scoring_profile_checksum, story_package_checksum, solution_checksum,
      frozen_input_checksum, reveal_checksum, content_checksum, content_json
    from app_private.case_files
    where id = 'ee000000-0000-4000-8000-000000000001'
  $sql$),
  '23505',
  'a room has exactly one finalized case file'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.case_files
    set reveal_checksum = decode(repeat('99',32),'hex')
    where id = 'ee000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a case file must match its reveal publication'
);

select col_not_null(
  'app_private',
  'scoring_snapshots',
  'source_state_version',
  'a scoring snapshot must record its source state version'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'app_private.validate_scoring_snapshot_source()', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'app_private.validate_endgame_artifact_source()', 'EXECUTE'
  ),
  'API roles cannot invoke endgame validation triggers directly'
);

select ok(
  (
    select scoring.story_package_checksum = story.package_checksum
      and scoring.solution_checksum = story.solution_checksum
      and reveal.frozen_input_checksum = scoring.frozen_input_checksum
      and case_file.reveal_checksum = reveal.reveal_checksum
    from app_private.scoring_snapshots as scoring
    join app_private.canonical_stories as story
      on story.room_id = scoring.room_id and story.id = scoring.story_id
    join app_private.reveal_publications as reveal
      on reveal.scoring_snapshot_id = scoring.id
    join app_private.case_files as case_file
      on case_file.reveal_publication_id = reveal.id
    where scoring.id = 'fa000000-0000-4000-8000-000000000001'
  ),
  'the finalized endgame chain retains matching source checksums'
);

select * from finish();

rollback;
