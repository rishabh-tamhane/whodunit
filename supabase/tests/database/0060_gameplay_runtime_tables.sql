begin;

select plan(59);

create or replace function pg_temp.capture_sqlstate(command text)
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

select has_table('app_private', 'mission_states', 'mission states exist');
select has_table('app_private', 'evidence_releases', 'evidence releases exist');
select has_table('app_private', 'consequence_states', 'consequence states exist');
select has_table(
  'app_private',
  'intervention_requests',
  'intervention requests exist'
);
select has_table(
  'app_private',
  'intervention_previews',
  'intervention previews exist'
);
select has_table(
  'app_private',
  'intervention_releases',
  'intervention releases exist'
);
select has_table(
  'app_private',
  'accomplice_revelation_states',
  'accomplice revelation state exists'
);
select has_table('app_private', 'runtime_effects', 'once-only runtime effects exist');

select has_index(
  'app_private',
  'runtime_effects',
  'runtime_effects_once_evidence_idx',
  'evidence effects are once-only'
);
select has_index(
  'app_private',
  'runtime_effects',
  'runtime_effects_once_consequence_idx',
  'consequence effects are once-only'
);
select has_index(
  'app_private',
  'runtime_effects',
  'runtime_effects_once_mission_idx',
  'mission activation effects are once-only'
);
select has_index(
  'app_private',
  'runtime_effects',
  'runtime_effects_once_revelation_idx',
  'accomplice revelation effects are once-only'
);
select has_index(
  'app_private',
  'runtime_effects',
  'runtime_effects_once_question_idx',
  'directed question effects are once-only'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon',
    'app_private.mission_states',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.runtime_effects',
    'SELECT'
  ),
  'API roles cannot directly read gameplay runtime state'
);

insert into auth.users (id)
values
  ('b0000000-0000-4000-8000-000000000001'),
  ('b0000000-0000-4000-8000-000000000002'),
  ('b0000000-0000-4000-8000-000000000011'),
  ('b0000000-0000-4000-8000-000000000012');

insert into app_private.rooms (id, room_code, host_auth_user_id, state_version)
values
  (
    'b1000000-0000-4000-8000-000000000001',
    'RUNTIMEA',
    'b0000000-0000-4000-8000-000000000001',
    1
  ),
  (
    'b1000000-0000-4000-8000-000000000002',
    'RUNTIMEB',
    'b0000000-0000-4000-8000-000000000002',
    1
  );

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values
  (
    'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001'
  ),
  (
    'b2000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b0000000-0000-4000-8000-000000000002'
  );

set constraints all immediate;

insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume, seat_order
)
values
  (
    'b3000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'Meera', 'meera', 'Astronaut', 1
  ),
  (
    'b3000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'Kabir', 'kabir', 'Wizard', 1
  );

insert into app_private.story_generation_jobs (
  id, room_id, idempotency_key, status, phase, input_snapshot_json,
  model_id, prompt_version, story_schema_version, validator_version,
  started_at, finished_at
)
values
  (
    'b4000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b4100000-0000-4000-8000-000000000001',
    'SUCCEEDED', 'COMPLETE', '{}'::jsonb,
    'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
    app_private.current_database_time(), app_private.current_database_time()
  ),
  (
    'b4000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b4100000-0000-4000-8000-000000000002',
    'SUCCEEDED', 'COMPLETE', '{}'::jsonb,
    'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
    app_private.current_database_time(), app_private.current_database_time()
  );

insert into app_private.canonical_stories (
  id, room_id, source_generation_job_id, story_schema_version,
  scoring_profile_version, prompt_version, model_id, package_json,
  package_checksum, solution_checksum, locked_at
)
values
  (
    'b5000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b4000000-0000-4000-8000-000000000001',
    'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
    decode(repeat('11', 32), 'hex'), decode(repeat('12', 32), 'hex'),
    app_private.current_database_time()
  ),
  (
    'b5000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b4000000-0000-4000-8000-000000000002',
    'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
    decode(repeat('21', 32), 'hex'), decode(repeat('22', 32), 'hex'),
    app_private.current_database_time()
  );

insert into app_private.story_rounds (
  id, room_id, story_id, sequence, title, target_duration_seconds,
  public_event_json
)
values
  (
    'b6000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001',
    1, 'Investigation', 600, '{}'::jsonb
  ),
  (
    'b6000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002',
    1, 'Investigation', 600, '{}'::jsonb
  );

insert into app_private.consequence_specs (
  id, room_id, story_id, severity, consequence_json, eligibility_rule_json
)
values
  (
    'b7000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001',
    1, '{}'::jsonb, '{}'::jsonb
  ),
  (
    'b7000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002',
    1, '{}'::jsonb, '{}'::jsonb
  );

insert into app_private.mission_specs (
  id, room_id, story_id, round_id, assigned_player_id, action_kind,
  objective_text, completion_rule_json, stakes_text,
  host_confirmation_guidance, failure_consequence_id
)
values
  (
    'b8000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001',
    'b6000000-0000-4000-8000-000000000001',
    'b3000000-0000-4000-8000-000000000001',
    'ASK_PLAYER', 'Ask about the lantern', '{}'::jsonb,
    'A secret may surface', 'Confirm the question was asked',
    'b7000000-0000-4000-8000-000000000001'
  ),
  (
    'b8000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002',
    'b6000000-0000-4000-8000-000000000002',
    'b3000000-0000-4000-8000-000000000002',
    'ASK_PLAYER', 'Ask about the clock', '{}'::jsonb,
    'A secret may surface', 'Confirm the question was asked',
    'b7000000-0000-4000-8000-000000000002'
  );

insert into app_private.evidence (
  id, room_id, story_id, round_id, evidence_kind, content_json,
  release_rule_json, audience_json
)
values
  (
    'b9000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001',
    'b6000000-0000-4000-8000-000000000001',
    'PHYSICAL', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  ),
  (
    'b9000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002',
    'b6000000-0000-4000-8000-000000000002',
    'PHYSICAL', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  );

insert into app_private.intervention_specs (
  id, room_id, story_id, round_id, strength, candidate_kind,
  canonical_effect_json, presentation_json, eligibility_rule_json
)
values
  (
    'ba000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001',
    'b6000000-0000-4000-8000-000000000001',
    1, 'DIRECTED_QUESTION', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  ),
  (
    'ba000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002',
    'b6000000-0000-4000-8000-000000000002',
    1, 'DIRECTED_QUESTION', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  );

insert into app_private.accomplice_revelations (
  id, room_id, story_id, accomplice_player_id, round_id, revelation_json
)
values
  (
    'bb000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'b5000000-0000-4000-8000-000000000001',
    'b3000000-0000-4000-8000-000000000001',
    'b6000000-0000-4000-8000-000000000001', '{}'::jsonb
  ),
  (
    'bb000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000002',
    'b3000000-0000-4000-8000-000000000002',
    'b6000000-0000-4000-8000-000000000002', '{}'::jsonb
  );

insert into app_private.command_receipts (
  id, room_id, idempotency_key, command_name, actor_type,
  actor_auth_user_id, request_hash, expected_state_version,
  result_state_version, response_status, result_json
)
values
  (
    'bc000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'bc100000-0000-4000-8000-000000000001',
    'GAMEPLAY_ACTION', 'GAME_MASTER',
    'b0000000-0000-4000-8000-000000000001',
    decode(repeat('31', 32), 'hex'), 0, 1, 200, '{}'::jsonb
  ),
  (
    'bc000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000001',
    'bc100000-0000-4000-8000-000000000002',
    'SECOND_ACTION', 'GAME_MASTER',
    'b0000000-0000-4000-8000-000000000001',
    decode(repeat('32', 32), 'hex'), 0, 1, 200, '{}'::jsonb
  ),
  (
    'bc000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000002',
    'bc100000-0000-4000-8000-000000000003',
    'OTHER_ROOM_ACTION', 'GAME_MASTER',
    'b0000000-0000-4000-8000-000000000002',
    decode(repeat('33', 32), 'hex'), 0, 1, 200, '{}'::jsonb
  );

insert into app_private.mission_states (
  id, room_id, story_id, mission_spec_id
)
values (
  'bd000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'b8000000-0000-4000-8000-000000000001'
);

select is(
  (select status::text from app_private.mission_states
    where id = 'bd000000-0000-4000-8000-000000000001'),
  'ASSIGNED',
  'mission runtime state begins assigned'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.mission_states (
      room_id, story_id, mission_spec_id, status, revision, accepted_at
    ) values (
      'b1000000-0000-4000-8000-000000000002',
      'b5000000-0000-4000-8000-000000000002',
      'b8000000-0000-4000-8000-000000000002',
      'ACCEPTED', 0, app_private.current_database_time()
    )
  $sql$),
  '23514',
  'mission state cannot be inserted after the initial transition'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.mission_states (
      room_id, story_id, mission_spec_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b8000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'a canonical mission has only one runtime state'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.mission_states (
      room_id, story_id, mission_spec_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b8000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'mission runtime state cannot reference another story mission'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_states
    set status = 'COMPLETED', revision = 1,
      resolved_at = app_private.current_database_time(),
      updated_at = app_private.current_database_time()
    where id = 'bd000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'an assigned mission cannot jump directly to completed'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_states
    set status = 'ACCEPTED', revision = 2,
      accepted_at = app_private.current_database_time(),
      updated_at = app_private.current_database_time()
    where id = 'bd000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'mission revisions cannot skip a number'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_states
    set status = 'ACCEPTED', revision = 1,
      accepted_at = app_private.current_database_time(),
      updated_at = app_private.current_database_time()
    where id = 'bd000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'an assigned mission can be accepted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_states
    set status = 'COMPLETION_REQUESTED', revision = 2,
      completion_requested_at = app_private.current_database_time(),
      updated_at = app_private.current_database_time()
    where id = 'bd000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'an accepted mission can request completion'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_states
    set status = 'ACCEPTED', revision = 3,
      completion_requested_at = null,
      updated_at = app_private.current_database_time()
    where id = 'bd000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'the Game Master can reject a completion request back to accepted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.mission_states
    set revision = 4,
      deadline_at = app_private.current_database_time() + interval '10 minutes',
      updated_at = app_private.current_database_time()
    where id = 'bd000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'an active mission deadline can be extended in place'
);

insert into app_private.consequence_states (
  id, room_id, story_id, consequence_spec_id, source_mission_state_id,
  eligible_by_command_receipt_id
)
values (
  'be000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'b7000000-0000-4000-8000-000000000001',
  'bd000000-0000-4000-8000-000000000001',
  'bc000000-0000-4000-8000-000000000001'
);

select is(
  (select status::text from app_private.consequence_states
    where id = 'be000000-0000-4000-8000-000000000001'),
  'PENDING',
  'an eligible consequence begins pending'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.consequence_states (
      room_id, story_id, consequence_spec_id,
      eligible_by_command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b7000000-0000-4000-8000-000000000001',
      'bc000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'a consequence can become eligible only once'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.consequence_states (
      room_id, story_id, consequence_spec_id,
      eligible_by_command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b7000000-0000-4000-8000-000000000002',
      'bc000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23503',
  'consequence state cannot reference another story specification'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.consequence_states (
      room_id, story_id, consequence_spec_id, status,
      eligible_by_command_receipt_id, resolved_by_command_receipt_id,
      resolved_at
    ) values (
      'b1000000-0000-4000-8000-000000000002',
      'b5000000-0000-4000-8000-000000000002',
      'b7000000-0000-4000-8000-000000000002',
      'RELEASED', 'bc000000-0000-4000-8000-000000000003',
      'bc000000-0000-4000-8000-000000000003',
      app_private.current_database_time()
    )
  $sql$),
  '23514',
  'consequence state cannot be inserted already released'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.consequence_states
    set status = 'RELEASED',
      resolved_by_command_receipt_id = 'bc000000-0000-4000-8000-000000000002',
      resolved_at = app_private.current_database_time()
    where id = 'be000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'a pending consequence can be released'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.consequence_states
    set status = 'WAIVED'
    where id = 'be000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'a released consequence cannot transition again'
);

insert into app_private.evidence_releases (
  id, room_id, story_id, evidence_id, released_in_round_id,
  release_reason, command_receipt_id
)
values (
  'bf000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'b9000000-0000-4000-8000-000000000001',
  'b6000000-0000-4000-8000-000000000001',
  'STANDALONE', 'bc000000-0000-4000-8000-000000000001'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.evidence_releases
    where evidence_id = 'b9000000-0000-4000-8000-000000000001'),
  1,
  'canonical evidence can be released once'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence_releases (
      room_id, story_id, evidence_id, release_reason, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b9000000-0000-4000-8000-000000000001',
      'INTERVENTION', 'bc000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'duplicate evidence releases fail'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence_releases (
      room_id, story_id, evidence_id, release_reason, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b9000000-0000-4000-8000-000000000002',
      'INTERVENTION', 'bc000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23503',
  'evidence release cannot reference another story evidence item'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence_releases (
      room_id, story_id, evidence_id, release_reason, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b9000000-0000-4000-8000-000000000001',
      'INTERVENTION', 'bc000000-0000-4000-8000-000000000003'
    )
  $sql$),
  '23505',
  'duplicate evidence is rejected before an unrelated command can replace it'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.evidence_releases
    set release_reason = 'INTERVENTION'
    where id = 'bf000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'evidence release records are immutable'
);

insert into app_private.intervention_requests (
  id, room_id, story_id, round_id, requested_state_version,
  requested_strength, request_command_receipt_id
)
values (
  'c0000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'b6000000-0000-4000-8000-000000000001',
  1, 1, 'bc000000-0000-4000-8000-000000000001'
);

select is(
  (select status::text from app_private.intervention_requests
    where id = 'c0000000-0000-4000-8000-000000000001'),
  'REQUESTED',
  'an intervention begins requested'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.intervention_requests (
      room_id, story_id, round_id, requested_state_version,
      requested_strength, request_command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'b6000000-0000-4000-8000-000000000002',
      1, 1, 'bc000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23503',
  'an intervention request cannot use another story round'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.intervention_requests (
      room_id, story_id, round_id, requested_state_version,
      requested_strength, status, revision, request_command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000002',
      'b5000000-0000-4000-8000-000000000002',
      'b6000000-0000-4000-8000-000000000002',
      1, 1, 'PREVIEW_READY', 0,
      'bc000000-0000-4000-8000-000000000003'
    )
  $sql$),
  '23514',
  'an intervention cannot be inserted after the requested state'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.intervention_previews (
      room_id, story_id, request_id, candidate_kind,
      selection_source, presentation_style, reason_code,
      audience_json, preview_json
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'c0000000-0000-4000-8000-000000000001',
      'RELEASE_EVIDENCE', 'PREPARED_FALLBACK',
      'DIRECT', 'STALLED', '{}'::jsonb, '{}'::jsonb
    )
  $sql$),
  '23514',
  'an intervention preview must contain its typed canonical target'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.intervention_previews (
      room_id, story_id, request_id, candidate_kind, evidence_id,
      selection_source, presentation_style, reason_code,
      audience_json, preview_json
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'c0000000-0000-4000-8000-000000000001',
      'RELEASE_EVIDENCE', 'b9000000-0000-4000-8000-000000000002',
      'PREPARED_FALLBACK', 'DIRECT', 'STALLED',
      '{}'::jsonb, '{}'::jsonb
    )
  $sql$),
  '23503',
  'an intervention preview cannot reference another story candidate'
);

insert into app_private.intervention_previews (
  id, room_id, story_id, request_id, candidate_kind, intervention_spec_id,
  selection_source, presentation_style, reason_code, audience_json, preview_json
)
values (
  'c1000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000001',
  'DIRECTED_QUESTION', 'ba000000-0000-4000-8000-000000000001',
  'PREPARED_FALLBACK', 'DIRECT', 'STALLED', '{}'::jsonb, '{}'::jsonb
);

select is(
  (select pg_catalog.count(*)::integer from app_private.intervention_previews
    where request_id = 'c0000000-0000-4000-8000-000000000001'),
  1,
  'one immutable canonical preview is staged per request'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.intervention_requests
    set status = 'PREVIEW_READY', revision = 1,
      updated_at = app_private.current_database_time()
    where id = 'c0000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'a requested intervention can become preview ready'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.intervention_requests
    set status = 'REQUESTED', revision = 2,
      updated_at = app_private.current_database_time()
    where id = 'c0000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'an intervention cannot move backwards to requested'
);

update app_private.intervention_requests
set status = 'RELEASED', revision = 2,
  updated_at = app_private.current_database_time()
where id = 'c0000000-0000-4000-8000-000000000001';

insert into app_private.intervention_releases (
  id, room_id, story_id, request_id, preview_id, command_receipt_id
)
values (
  'c2000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000001',
  'bc000000-0000-4000-8000-000000000002'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.intervention_releases
    where request_id = 'c0000000-0000-4000-8000-000000000001'),
  1,
  'an approved preview is released once'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.intervention_releases (
      room_id, story_id, request_id, preview_id, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'c0000000-0000-4000-8000-000000000001',
      'c1000000-0000-4000-8000-000000000001',
      'bc000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23505',
  'duplicate intervention releases fail'
);

insert into app_private.accomplice_revelation_states (
  id, room_id, story_id, revelation_spec_id
)
values (
  'c3000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'bb000000-0000-4000-8000-000000000001'
);

select is(
  (select status::text from app_private.accomplice_revelation_states
    where id = 'c3000000-0000-4000-8000-000000000001'),
  'PENDING',
  'accomplice knowledge begins unreleased'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.accomplice_revelation_states (
      room_id, story_id, revelation_spec_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'bb000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'accomplice revelation state cannot reference another story specification'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.accomplice_revelation_states (
      room_id, story_id, revelation_spec_id, status,
      released_by_command_receipt_id, released_at
    ) values (
      'b1000000-0000-4000-8000-000000000002',
      'b5000000-0000-4000-8000-000000000002',
      'bb000000-0000-4000-8000-000000000002',
      'RELEASED', 'bc000000-0000-4000-8000-000000000003',
      app_private.current_database_time()
    )
  $sql$),
  '23514',
  'accomplice revelation state cannot begin released'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.accomplice_revelation_states
    set status = 'RELEASED',
      released_by_command_receipt_id = 'bc000000-0000-4000-8000-000000000002',
      released_at = app_private.current_database_time()
    where id = 'c3000000-0000-4000-8000-000000000001'
  $sql$),
  null,
  'scheduled accomplice knowledge can be released once'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.accomplice_revelation_states (
      room_id, story_id, revelation_spec_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'bb000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'an accomplice revelation has only one runtime state'
);

insert into app_private.runtime_effects (
  id, room_id, story_id, effect_kind, source_intervention_request_id,
  target_evidence_id, command_receipt_id
)
values (
  'c4000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b5000000-0000-4000-8000-000000000001',
  'EVIDENCE_RELEASE', 'c0000000-0000-4000-8000-000000000001',
  'b9000000-0000-4000-8000-000000000001',
  'bc000000-0000-4000-8000-000000000002'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.runtime_effects
    where target_evidence_id = 'b9000000-0000-4000-8000-000000000001'),
  1,
  'a typed canonical effect is recorded once'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.runtime_effects (
      room_id, story_id, effect_kind, target_evidence_id, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'EVIDENCE_RELEASE', 'b9000000-0000-4000-8000-000000000001',
      'bc000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23505',
  'a canonical effect target cannot be applied twice'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.runtime_effects (
      room_id, story_id, effect_kind, target_mission_spec_id,
      command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'EVIDENCE_RELEASE', 'b8000000-0000-4000-8000-000000000001',
      'bc000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23514',
  'an effect kind must match its typed target'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.runtime_effects (
      room_id, story_id, effect_kind, target_evidence_id, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'EVIDENCE_RELEASE', 'b9000000-0000-4000-8000-000000000002',
      'bc000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'a runtime effect cannot reference another story canonical target'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.runtime_effects (
      room_id, story_id, effect_kind, target_evidence_id, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000001',
      'b5000000-0000-4000-8000-000000000001',
      'EVIDENCE_RELEASE', 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      'bc000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'a fabricated runtime effect target fails closed'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.runtime_effects (
      room_id, story_id, effect_kind, source_intervention_request_id,
      target_mission_spec_id, command_receipt_id
    ) values (
      'b1000000-0000-4000-8000-000000000002',
      'b5000000-0000-4000-8000-000000000002',
      'MISSION_ACTIVATION', 'c0000000-0000-4000-8000-000000000001',
      'b8000000-0000-4000-8000-000000000002',
      'bc000000-0000-4000-8000-000000000003'
    )
  $sql$),
  '23503',
  'an effect cannot use an intervention request from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.runtime_effects
    set target_evidence_id = null
    where id = 'c4000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'applied effects are immutable'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from information_schema.columns as c
    where c.table_schema = 'app_private'
      and c.table_name in (
        'mission_states',
        'evidence_releases',
        'consequence_states',
        'intervention_requests',
        'intervention_previews',
        'intervention_releases',
        'accomplice_revelation_states',
        'runtime_effects'
      )
      and c.column_name = 'room_id'
      and c.is_nullable = 'NO'
  ),
  8,
  'every gameplay runtime record has required room scope'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app_private.enforce_mission_state_transition()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.enforce_intervention_request_transition()',
    'EXECUTE'
  ),
  'API roles cannot invoke runtime transition triggers directly'
);

select * from finish();

rollback;
