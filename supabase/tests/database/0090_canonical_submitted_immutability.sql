begin;

select plan(34);

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

select has_function(
  'app_private',
  'enforce_canonical_story_locked',
  array[]::text[],
  'canonical lock enforcement exists'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and trigger.tgname like '%_locked_immutable'
      and not trigger.tgisinternal
  ),
  13,
  'every materialized canonical-story table has a lock trigger'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_trigger as trigger
    join pg_catalog.pg_class as relation on relation.oid = trigger.tgrelid
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and trigger.tgname in (
        'scoring_snapshots_immutable', 'player_scores_immutable',
        'theory_scores_immutable', 'faction_results_immutable',
        'player_awards_immutable', 'reveal_publications_immutable',
        'case_files_immutable'
      )
      and not trigger.tgisinternal
  ),
  7,
  'every finalized result table is append-only'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from pg_catalog.pg_trigger as trigger
    where trigger.tgname in (
      'mission_states_no_delete', 'consequence_states_no_delete',
      'intervention_requests_no_delete',
      'accomplice_revelation_states_no_delete'
    )
      and not trigger.tgisinternal
  ),
  4,
  'mutable runtime histories cannot be erased'
);

select has_trigger(
  'app_private',
  'rooms',
  'rooms_enforce_story_lock_immutable',
  'the room cannot replace its locked story'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon', 'app_private.canonical_stories', 'UPDATE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'app_private.player_scores', 'DELETE'
  ),
  'API roles have no direct canonical or result mutation privilege'
);

insert into auth.users (id)
values ('a0000000-0000-4000-8000-000000000001');

insert into app_private.rooms (id, room_code, host_auth_user_id, state_version)
values (
  'a1000000-0000-4000-8000-000000000001',
  'LOCKED1',
  'a0000000-0000-4000-8000-000000000001',
  10
);

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values (
  'a2000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000001'
);

set constraints all immediate;

insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume, seat_order
)
values
  (
    'a3000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'Mira', 'mira', 'Witch', 1
  ),
  (
    'a3000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000001',
    'Rohan', 'rohan', 'Pirate', 2
  );

insert into app_private.story_generation_jobs (
  id, room_id, idempotency_key, status, phase, input_snapshot_json,
  model_id, prompt_version, story_schema_version, validator_version,
  started_at, finished_at
)
values (
  'a4000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a4100000-0000-4000-8000-000000000001',
  'SUCCEEDED', 'COMPLETE', '{}'::jsonb,
  'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
  app_private.current_database_time(), app_private.current_database_time()
);

insert into app_private.canonical_stories (
  id, room_id, source_generation_job_id, story_schema_version,
  scoring_profile_version, prompt_version, model_id, package_json,
  package_checksum, solution_checksum, locked_at
)
values (
  'a5000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000001',
  'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol',
  '{"title":"The Locked Clock"}'::jsonb,
  decode(repeat('31',32),'hex'), decode(repeat('32',32),'hex'),
  app_private.current_database_time()
);

insert into app_private.canonical_solutions (
  id, room_id, story_id, victim_json, solution_json
)
values (
  'a5100000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  '{"name":"The Curator"}'::jsonb, '{"murderer":"Rohan"}'::jsonb
);

insert into app_private.story_rounds (
  id, room_id, story_id, sequence, title, target_duration_seconds,
  public_event_json
)
values (
  'a6000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  1, 'The Search', 600, '{}'::jsonb
);

insert into app_private.evidence (
  id, room_id, story_id, round_id, evidence_kind, content_json,
  release_rule_json, audience_json
)
values (
  'a7000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'a6000000-0000-4000-8000-000000000001',
  'PHYSICAL', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
);

insert into app_private.mission_specs (
  id, room_id, story_id, round_id, assigned_player_id, action_kind,
  objective_text, completion_rule_json, stakes_text,
  host_confirmation_guidance
)
values (
  'a7100000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'a6000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001',
  'ASK_PLAYER', 'Ask about the clock.', '{}'::jsonb,
  'The answer changes the room.', 'Confirm the question was asked.'
);

update app_private.rooms
set story_id = 'a5000000-0000-4000-8000-000000000001',
  locked_at = app_private.current_database_time(),
  scoring_profile_version = 'score-v1',
  status = 'READY_TO_START',
  updated_at = app_private.current_database_time()
where id = 'a1000000-0000-4000-8000-000000000001';

set constraints all immediate;

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set story_id = null, locked_at = null
    where id = 'a1000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a room cannot be unlocked'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set story_id = '00000000-0000-4000-8000-000000000099'
    where id = 'a1000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a room cannot replace its canonical story'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.canonical_stories
    set package_json = '{"changed":true}'::jsonb
    where id = 'a5000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a locked canonical package cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.canonical_stories
    where id = 'a5000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a locked canonical package cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.canonical_solutions
    set solution_json = '{"changed":true}'::jsonb
    where id = 'a5100000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'the locked solution cannot be changed'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.story_rounds
    where id = 'a6000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'locked story material cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence (
      id, room_id, story_id, evidence_kind, content_json,
      release_rule_json, audience_json
    ) values (
      'a7000000-0000-4000-8000-000000000002',
      'a1000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000001',
      'LATE_ADDITION', '{}', '{}', '{}'
    )
  $sql$),
  '23514',
  'new canonical content cannot be inserted after lock'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_specs
    set objective_text = 'Changed mission.'
    where id = 'a7100000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a locked mission specification cannot be updated'
);

insert into app_private.command_receipts (
  id, room_id, idempotency_key, command_name, actor_type,
  request_hash, expected_state_version, result_state_version,
  response_status, result_json
)
values (
  'a8000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a8100000-0000-4000-8000-000000000001',
  'LOCK_TEST', 'SYSTEM', decode(repeat('33',32),'hex'),
  9, 10, 200, '{}'::jsonb
);

insert into app_private.evidence_releases (
  id, room_id, story_id, evidence_id, released_in_round_id,
  release_reason, command_receipt_id
)
values (
  'a9000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'a7000000-0000-4000-8000-000000000001',
  'a6000000-0000-4000-8000-000000000001',
  'GUARANTEED', 'a8000000-0000-4000-8000-000000000001'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.evidence_releases set release_reason = 'STANDALONE'
    where id = 'a9000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a release record cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.evidence_releases
    where id = 'a9000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a release record cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence_releases (
      room_id, story_id, evidence_id, released_in_round_id,
      release_reason, command_receipt_id
    ) values (
      'a1000000-0000-4000-8000-000000000001',
      'a5000000-0000-4000-8000-000000000001',
      'a7000000-0000-4000-8000-000000000001',
      'a6000000-0000-4000-8000-000000000001',
      'STANDALONE', 'a8000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'canonical evidence can be released only once'
);

insert into app_private.mission_states (
  id, room_id, story_id, mission_spec_id
)
values (
  'aa000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'a7100000-0000-4000-8000-000000000001'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.mission_states
    where id = 'aa000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'runtime progress cannot be erased'
);

insert into app_private.game_events (
  id, room_id, room_sequence, state_version, event_type, actor_type,
  command_receipt_id
)
values (
  'ab000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  1, 10, 'LOCK_TESTED', 'SYSTEM',
  'a8000000-0000-4000-8000-000000000001'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.game_events set event_type = 'CHANGED'
    where id = 'ab000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'game history cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.game_events
    where id = 'ab000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'game history cannot be deleted while its room exists'
);

insert into app_private.player_theories (
  id, room_id, story_id, player_id, round_id, submitted_state_version,
  structured_claim_json, command_receipt_id
)
values (
  'ac000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001',
  'a6000000-0000-4000-8000-000000000001', 10,
  '{}'::jsonb, 'a8000000-0000-4000-8000-000000000001'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_theories set structured_claim_json = '{"x":1}'
    where id = 'ac000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a submitted theory cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.player_theories
    where id = 'ac000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a submitted theory cannot be deleted while its room exists'
);

insert into app_private.final_accusations (
  id, room_id, story_id, player_id, structured_case_json
)
values (
  'ad000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001', '{}'::jsonb
);

update app_private.final_accusations
set status = 'SUBMITTED', revision = 1, submitted_state_version = 10,
  submission_command_receipt_id = 'a8000000-0000-4000-8000-000000000001',
  submitted_at = app_private.current_database_time(),
  updated_at = app_private.current_database_time()
where id = 'ad000000-0000-4000-8000-000000000001';

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.final_accusations set revision = 2
    where id = 'ad000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a submitted final accusation cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.final_accusations
    where id = 'ad000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a submitted final accusation cannot be deleted while its room exists'
);

insert into app_private.scoring_snapshots (
  id, room_id, story_id, scoring_profile_version,
  scoring_profile_checksum, story_package_checksum, solution_checksum,
  frozen_input_checksum, source_state_version, source_last_event_sequence,
  frozen_input_json
)
values (
  'ae000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001', 'score-v1',
  decode(repeat('34',32),'hex'), decode(repeat('31',32),'hex'),
  decode(repeat('32',32),'hex'), decode(repeat('35',32),'hex'),
  10, 1, '{}'::jsonb
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.scoring_snapshots set source_last_event_sequence = 2
    where id = 'ae000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a frozen scoring input cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.scoring_snapshots
    where id = 'ae000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a frozen scoring input cannot be deleted while its room exists'
);

insert into app_private.player_scores (
  id, room_id, story_id, scoring_snapshot_id, player_id,
  final_accusation_id, total_points, breakdown_json, explanation
)
values (
  'af000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001',
  'ad000000-0000-4000-8000-000000000001', 70, '{}', 'Good case.'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_scores set total_points = 100
    where id = 'af000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a finalized player score cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.player_scores
    where id = 'af000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a finalized player score cannot be deleted'
);

insert into app_private.faction_results (
  id, room_id, story_id, scoring_snapshot_id, faction, won,
  result_json, explanation
)
values (
  'b0000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000001',
  'INNOCENT', true, '{}', 'Investigators win.'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.faction_results set won = false
    where id = 'b0000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a finalized faction result cannot be updated'
);

insert into app_private.player_awards (
  id, room_id, story_id, scoring_snapshot_id, player_id,
  award_code, title, description
)
values (
  'b1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000001',
  'a3000000-0000-4000-8000-000000000001',
  'BEST_CASE', 'Best Case', 'Strongest final argument.'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.player_awards
    where id = 'b1000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a finalized award cannot be deleted'
);

insert into app_private.reveal_publications (
  id, room_id, story_id, scoring_snapshot_id, command_receipt_id,
  publication_state_version, scoring_profile_version,
  scoring_profile_checksum, story_package_checksum, solution_checksum,
  frozen_input_checksum, reveal_checksum, published_payload_json
)
values (
  'b2000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000001',
  'a8000000-0000-4000-8000-000000000001', 10, 'score-v1',
  decode(repeat('34',32),'hex'), decode(repeat('31',32),'hex'),
  decode(repeat('32',32),'hex'), decode(repeat('35',32),'hex'),
  decode(repeat('36',32),'hex'), '{}'::jsonb
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.reveal_publications set publication_state_version = 11
    where id = 'b2000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a published reveal cannot be updated'
);

insert into app_private.case_files (
  id, room_id, story_id, scoring_snapshot_id, reveal_publication_id,
  case_file_schema_version, scoring_profile_version,
  scoring_profile_checksum, story_package_checksum, solution_checksum,
  frozen_input_checksum, reveal_checksum, content_checksum, content_json
)
values (
  'b3000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a5000000-0000-4000-8000-000000000001',
  'ae000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000001',
  'case-v1', 'score-v1', decode(repeat('34',32),'hex'),
  decode(repeat('31',32),'hex'), decode(repeat('32',32),'hex'),
  decode(repeat('35',32),'hex'), decode(repeat('36',32),'hex'),
  decode(repeat('37',32),'hex'), '{}'::jsonb
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.case_files set content_json = '{"changed":true}'
    where id = 'b3000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a finalized case file cannot be updated'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.case_files
    where id = 'b3000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a finalized case file cannot be deleted'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon', 'app_private.enforce_canonical_story_locked()', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated', 'app_private.enforce_room_story_lock_immutable()', 'EXECUTE'
  ),
  'API roles cannot invoke immutability trigger functions directly'
);

select * from finish();

rollback;
