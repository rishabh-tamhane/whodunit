begin;

select plan(40);

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

select has_table(
  'app_private',
  'story_generation_jobs',
  'generation jobs exist'
);
select has_table(
  'app_private',
  'canonical_stories',
  'canonical stories exist'
);
select has_table(
  'app_private',
  'canonical_solutions',
  'canonical solutions exist'
);
select has_table('app_private', 'story_rounds', 'story rounds exist');
select has_table('app_private', 'dossiers', 'dossiers exist');
select has_table('app_private', 'relationships', 'relationships exist');
select has_table('app_private', 'timeline_events', 'timeline events exist');
select has_table('app_private', 'evidence', 'evidence exists');
select has_table(
  'app_private',
  'evidence_dependencies',
  'evidence dependencies exist'
);
select has_table(
  'app_private',
  'consequence_specs',
  'consequence specifications exist'
);
select has_table('app_private', 'mission_specs', 'mission specifications exist');
select has_table(
  'app_private',
  'intervention_specs',
  'intervention specifications exist'
);
select has_table(
  'app_private',
  'accomplice_revelations',
  'accomplice revelations exist'
);
select has_table(
  'app_private',
  'final_reveal_sections',
  'final reveal sections exist'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon',
    'app_private.story_generation_jobs',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.story_generation_jobs',
    'SELECT'
  ),
  'API roles cannot read generation artifacts'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon',
    'app_private.canonical_stories',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.canonical_stories',
    'SELECT'
  ),
  'API roles cannot directly read canonical stories'
);

select ok(
  pg_catalog.to_regclass(
    'app_private.story_generation_jobs_one_active_per_room_idx'
  ) is not null,
  'one non-terminal generation job is indexed per room'
);

insert into auth.users (id)
values
  ('80000000-0000-4000-8000-000000000001'),
  ('80000000-0000-4000-8000-000000000002'),
  ('80000000-0000-4000-8000-000000000011'),
  ('80000000-0000-4000-8000-000000000012'),
  ('80000000-0000-4000-8000-000000000013');

insert into app_private.rooms (id, room_code, host_auth_user_id)
values
  (
    '81000000-0000-4000-8000-000000000001',
    'STORYA',
    '80000000-0000-4000-8000-000000000001'
  ),
  (
    '81000000-0000-4000-8000-000000000002',
    'STORYB',
    '80000000-0000-4000-8000-000000000002'
  ),
  (
    '81000000-0000-4000-8000-000000000003',
    'STORYC',
    '80000000-0000-4000-8000-000000000002'
  );

insert into app_private.room_host_principals (
  id,
  room_id,
  auth_user_id,
  started_at
)
values
  (
    '82000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '80000000-0000-4000-8000-000000000001',
    '2026-10-30 00:00:00+00'
  ),
  (
    '82000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000002',
    '80000000-0000-4000-8000-000000000002',
    '2026-10-30 00:00:00+00'
  ),
  (
    '82000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000003',
    '80000000-0000-4000-8000-000000000002',
    '2026-10-30 00:00:00+00'
  );

set constraints all immediate;

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
    '83000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    'Asha',
    'asha',
    'Historian',
    1
  ),
  (
    '83000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    'Kabir',
    'kabir',
    'Magician',
    2
  ),
  (
    '83000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000002',
    'Leela',
    'leela',
    'Detective',
    1
  );

insert into app_private.story_generation_jobs (
  id,
  room_id,
  idempotency_key,
  input_snapshot_json,
  model_id,
  prompt_version,
  story_schema_version,
  validator_version
)
values (
  '84000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '84000000-0000-4000-8000-000000000101',
  '{}'::jsonb,
  'gpt-6.1-sol',
  'prompt-v1',
  'story-v1',
  'validator-v1'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.story_generation_jobs (
      id, room_id, idempotency_key, input_snapshot_json, model_id,
      prompt_version, story_schema_version, validator_version
    ) values (
      '84000000-0000-4000-8000-000000000006',
      '81000000-0000-4000-8000-000000000001',
      '84000000-0000-4000-8000-000000000106',
      '{}'::jsonb, 'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1'
    )
  $sql$),
  '23505',
  'a room cannot have two non-terminal generation jobs'
);

update app_private.story_generation_jobs
set
  status = 'FAILED',
  started_at = app_private.current_database_time(),
  finished_at = app_private.current_database_time(),
  sanitized_error_code = 'VALIDATION_FAILED'
where id = '84000000-0000-4000-8000-000000000001';

insert into app_private.story_generation_jobs (
  id,
  room_id,
  idempotency_key,
  status,
  phase,
  input_snapshot_json,
  blueprint_json,
  playable_content_json,
  model_id,
  prompt_version,
  story_schema_version,
  validator_version,
  started_at,
  finished_at
)
values
  (
    '84000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    '84000000-0000-4000-8000-000000000102',
    'SUCCEEDED',
    'COMPLETE',
    '{}'::jsonb,
    '{}'::jsonb,
    '{}'::jsonb,
    'gpt-6.1-sol',
    'prompt-v1',
    'story-v1',
    'validator-v1',
    app_private.current_database_time(),
    app_private.current_database_time()
  ),
  (
    '84000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000001',
    '84000000-0000-4000-8000-000000000103',
    'SUCCEEDED',
    'COMPLETE',
    '{}'::jsonb,
    '{}'::jsonb,
    '{}'::jsonb,
    'gpt-6.1-sol',
    'prompt-v1',
    'story-v1',
    'validator-v1',
    app_private.current_database_time(),
    app_private.current_database_time()
  ),
  (
    '84000000-0000-4000-8000-000000000004',
    '81000000-0000-4000-8000-000000000002',
    '84000000-0000-4000-8000-000000000104',
    'SUCCEEDED',
    'COMPLETE',
    '{}'::jsonb,
    '{}'::jsonb,
    '{}'::jsonb,
    'gpt-6.1-sol',
    'prompt-v1',
    'story-v1',
    'validator-v1',
    app_private.current_database_time(),
    app_private.current_database_time()
  ),
  (
    '84000000-0000-4000-8000-000000000005',
    '81000000-0000-4000-8000-000000000003',
    '84000000-0000-4000-8000-000000000105',
    'SUCCEEDED',
    'COMPLETE',
    '{}'::jsonb,
    '{}'::jsonb,
    '{}'::jsonb,
    'gpt-6.1-sol',
    'prompt-v1',
    'story-v1',
    'validator-v1',
    app_private.current_database_time(),
    app_private.current_database_time()
  );

insert into app_private.story_generation_jobs (
  id,
  room_id,
  idempotency_key,
  input_snapshot_json,
  model_id,
  prompt_version,
  story_schema_version,
  validator_version
)
values (
  '84000000-0000-4000-8000-000000000007',
  '81000000-0000-4000-8000-000000000001',
  '84000000-0000-4000-8000-000000000107',
  '{}'::jsonb,
  'gpt-6.1-sol',
  'prompt-v1',
  'story-v1',
  'validator-v1'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from app_private.story_generation_jobs
    where room_id = '81000000-0000-4000-8000-000000000001'
      and status in ('PENDING', 'RUNNING')
  ),
  1,
  'a new generation may start after earlier attempts become terminal'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.story_generation_jobs (
      room_id, idempotency_key, status, phase, input_snapshot_json,
      model_id, prompt_version, story_schema_version, validator_version,
      started_at, finished_at
    ) values (
      '81000000-0000-4000-8000-000000000001',
      '84000000-0000-4000-8000-000000000102',
      'FAILED', 'COMPLETE', '{}'::jsonb,
      'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
      app_private.current_database_time(), app_private.current_database_time()
    )
  $sql$),
  '23505',
  'generation idempotency keys are unique within a room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.story_generation_jobs (
      room_id, idempotency_key, status, phase, input_snapshot_json,
      model_id, prompt_version, story_schema_version, validator_version,
      started_at, finished_at
    ) values (
      '81000000-0000-4000-8000-000000000003',
      '84000000-0000-4000-8000-000000000108',
      'FAILED', 'COMPLETE', '[]'::jsonb,
      'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
      app_private.current_database_time(), app_private.current_database_time()
    )
  $sql$),
  '23514',
  'generation input snapshots must be JSON objects'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.canonical_stories (
      id, room_id, source_generation_job_id, story_schema_version,
      scoring_profile_version, prompt_version, model_id, package_json,
      package_checksum, solution_checksum, locked_at
    ) values (
      '85000000-0000-4000-8000-000000000003',
      '81000000-0000-4000-8000-000000000003',
      '84000000-0000-4000-8000-000000000002',
      'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
      decode(repeat('aa', 32), 'hex'),
      decode(repeat('bb', 32), 'hex'),
      app_private.current_database_time()
    )
  $sql$),
  '23503',
  'a canonical story cannot use a generation job from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.canonical_stories (
      id, room_id, source_generation_job_id, story_schema_version,
      scoring_profile_version, prompt_version, model_id, package_json,
      package_checksum, solution_checksum, locked_at
    ) values (
      '85000000-0000-4000-8000-000000000004',
      '81000000-0000-4000-8000-000000000003',
      '84000000-0000-4000-8000-000000000005',
      'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
      decode('aa', 'hex'),
      decode(repeat('bb', 32), 'hex'),
      app_private.current_database_time()
    )
  $sql$),
  '23514',
  'canonical story checksums must be 32 bytes'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.canonical_stories (
      id, room_id, source_generation_job_id, story_schema_version,
      scoring_profile_version, prompt_version, model_id, package_json,
      package_checksum, solution_checksum, locked_at
    ) values (
      '85000000-0000-4000-8000-000000000006',
      '81000000-0000-4000-8000-000000000003',
      '84000000-0000-4000-8000-000000000005',
      'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '[]'::jsonb,
      decode(repeat('aa', 32), 'hex'),
      decode(repeat('bb', 32), 'hex'),
      app_private.current_database_time()
    )
  $sql$),
  '23514',
  'canonical story packages must be JSON objects'
);

insert into app_private.canonical_stories (
  id,
  room_id,
  source_generation_job_id,
  story_schema_version,
  scoring_profile_version,
  prompt_version,
  model_id,
  package_json,
  package_checksum,
  solution_checksum,
  locked_at
)
values
  (
    '85000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '84000000-0000-4000-8000-000000000002',
    'story-v1',
    'score-v1',
    'prompt-v1',
    'gpt-6.1-sol',
    '{"title":"The Lantern Room"}'::jsonb,
    decode(repeat('aa', 32), 'hex'),
    decode(repeat('bb', 32), 'hex'),
    app_private.current_database_time()
  ),
  (
    '85000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000002',
    '84000000-0000-4000-8000-000000000004',
    'story-v1',
    'score-v1',
    'prompt-v1',
    'gpt-6.1-sol',
    '{"title":"The Clock Tower"}'::jsonb,
    decode(repeat('cc', 32), 'hex'),
    decode(repeat('dd', 32), 'hex'),
    app_private.current_database_time()
  );

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.canonical_stories (
      id, room_id, source_generation_job_id, story_schema_version,
      scoring_profile_version, prompt_version, model_id, package_json,
      package_checksum, solution_checksum, locked_at
    ) values (
      '85000000-0000-4000-8000-000000000005',
      '81000000-0000-4000-8000-000000000001',
      '84000000-0000-4000-8000-000000000003',
      'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
      decode(repeat('ee', 32), 'hex'),
      decode(repeat('ff', 32), 'hex'),
      app_private.current_database_time()
    )
  $sql$),
  '23505',
  'a room can have only one canonical story'
);

insert into app_private.canonical_solutions (
  id,
  room_id,
  story_id,
  victim_json,
  solution_json
)
values (
  '86000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  '{"kind":"NPC","name":"Dev Malhotra"}'::jsonb,
  '{"method":"fictional poison"}'::jsonb
);

insert into app_private.story_rounds (
  id,
  room_id,
  story_id,
  sequence,
  title,
  target_duration_seconds,
  public_event_json
)
values
  (
    '87000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    1,
    'Arrival',
    600,
    '{"text":"The guests arrive."}'::jsonb
  ),
  (
    '87000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    2,
    'Investigation',
    900,
    '{"text":"The investigation begins."}'::jsonb
  ),
  (
    '87000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000002',
    '85000000-0000-4000-8000-000000000002',
    1,
    'Arrival',
    600,
    '{"text":"The clock stops."}'::jsonb
  );

insert into app_private.dossiers (
  id,
  room_id,
  story_id,
  player_id,
  faction,
  knowledge_policy_json,
  dossier_json
)
values
  (
    '88000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    '83000000-0000-4000-8000-000000000001',
    'MURDERER',
    '{"murdererAware":true}'::jsonb,
    '{"role":"Historian"}'::jsonb
  ),
  (
    '88000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    '83000000-0000-4000-8000-000000000002',
    'ACCOMPLICE',
    '{"murdererKnownAtStart":false}'::jsonb,
    '{"role":"Magician"}'::jsonb
  );

insert into app_private.relationships (
  id,
  room_id,
  story_id,
  source_player_id,
  target_player_id,
  relationship_json
)
values (
  '89000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000002',
  '{"kind":"rivals"}'::jsonb
);

insert into app_private.timeline_events (
  id,
  room_id,
  story_id,
  sequence,
  event_json
)
values (
  '90000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  1,
  '{"at":"21:00","event":"The lantern went dark."}'::jsonb
);

insert into app_private.evidence (
  id,
  room_id,
  story_id,
  round_id,
  evidence_kind,
  is_required,
  content_json,
  release_rule_json,
  audience_json
)
values
  (
    '91000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    '87000000-0000-4000-8000-000000000001',
    'PHYSICAL_CLUE',
    true,
    '{"text":"A cracked lantern lens."}'::jsonb,
    '{"round":1}'::jsonb,
    '{"kind":"PUBLIC"}'::jsonb
  ),
  (
    '91000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    '87000000-0000-4000-8000-000000000002',
    'TESTIMONY',
    true,
    '{"text":"A witness heard footsteps."}'::jsonb,
    '{"round":2}'::jsonb,
    '{"kind":"PUBLIC"}'::jsonb
  ),
  (
    '91000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000002',
    '85000000-0000-4000-8000-000000000002',
    '87000000-0000-4000-8000-000000000003',
    'PHYSICAL_CLUE',
    true,
    '{"text":"A stopped watch."}'::jsonb,
    '{"round":1}'::jsonb,
    '{"kind":"PUBLIC"}'::jsonb
  );

insert into app_private.evidence_dependencies (
  id,
  room_id,
  story_id,
  source_evidence_id,
  target_evidence_id,
  dependency_kind
)
values (
  '92000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002',
  'SUPPORTS'
);

insert into app_private.consequence_specs (
  id,
  room_id,
  story_id,
  severity,
  consequence_json,
  eligibility_rule_json
)
values
  (
    '93000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '85000000-0000-4000-8000-000000000001',
    1,
    '{"text":"Release a contradiction."}'::jsonb,
    '{"missionFailed":true}'::jsonb
  ),
  (
    '93000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000002',
    '85000000-0000-4000-8000-000000000002',
    1,
    '{"text":"Reveal the stopped watch."}'::jsonb,
    '{"missionFailed":true}'::jsonb
  );

insert into app_private.mission_specs (
  id,
  room_id,
  story_id,
  round_id,
  assigned_player_id,
  action_kind,
  objective_text,
  completion_rule_json,
  stakes_text,
  host_confirmation_guidance,
  failure_consequence_id
)
values (
  '94000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  '87000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000001',
  'ASK_PLAYER',
  'Ask Kabir about the lantern.',
  '{"targetPlayerId":"83000000-0000-4000-8000-000000000002"}'::jsonb,
  'A contradiction may be released.',
  'Confirm that the question was asked.',
  '93000000-0000-4000-8000-000000000001'
);

insert into app_private.intervention_specs (
  id,
  room_id,
  story_id,
  round_id,
  strength,
  candidate_kind,
  canonical_effect_json,
  presentation_json,
  eligibility_rule_json
)
values (
  '95000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  '87000000-0000-4000-8000-000000000001',
  1,
  'DIRECTED_QUESTION',
  '{"question":"Who last saw the lantern intact?"}'::jsonb,
  '{"style":"gentle"}'::jsonb,
  '{"unused":true}'::jsonb
);

insert into app_private.accomplice_revelations (
  id,
  room_id,
  story_id,
  accomplice_player_id,
  round_id,
  revelation_json
)
values (
  '96000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000002',
  '87000000-0000-4000-8000-000000000002',
  '{"murdererPlayerIds":["83000000-0000-4000-8000-000000000001"]}'::jsonb
);

insert into app_private.final_reveal_sections (
  id,
  room_id,
  story_id,
  sequence,
  section_kind,
  section_json
)
values (
  '97000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000001',
  1,
  'SOLUTION',
  '{"text":"The lantern revealed the method."}'::jsonb
);

select is(
  (
    select pg_catalog.jsonb_build_object(
      'solutions', (select pg_catalog.count(*) from app_private.canonical_solutions where story_id = '85000000-0000-4000-8000-000000000001'),
      'rounds', (select pg_catalog.count(*) from app_private.story_rounds where story_id = '85000000-0000-4000-8000-000000000001'),
      'dossiers', (select pg_catalog.count(*) from app_private.dossiers where story_id = '85000000-0000-4000-8000-000000000001'),
      'relationships', (select pg_catalog.count(*) from app_private.relationships where story_id = '85000000-0000-4000-8000-000000000001'),
      'timeline', (select pg_catalog.count(*) from app_private.timeline_events where story_id = '85000000-0000-4000-8000-000000000001'),
      'evidence', (select pg_catalog.count(*) from app_private.evidence where story_id = '85000000-0000-4000-8000-000000000001'),
      'missions', (select pg_catalog.count(*) from app_private.mission_specs where story_id = '85000000-0000-4000-8000-000000000001'),
      'consequences', (select pg_catalog.count(*) from app_private.consequence_specs where story_id = '85000000-0000-4000-8000-000000000001'),
      'interventions', (select pg_catalog.count(*) from app_private.intervention_specs where story_id = '85000000-0000-4000-8000-000000000001'),
      'revelations', (select pg_catalog.count(*) from app_private.accomplice_revelations where story_id = '85000000-0000-4000-8000-000000000001'),
      'revealSections', (select pg_catalog.count(*) from app_private.final_reveal_sections where story_id = '85000000-0000-4000-8000-000000000001')
    )
  ),
  '{"solutions":1,"rounds":2,"dossiers":2,"relationships":1,"timeline":1,"evidence":2,"missions":1,"consequences":1,"interventions":1,"revelations":1,"revealSections":1}'::jsonb,
  'the canonical package has every materialized story category'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.dossiers (
      id, room_id, story_id, player_id, faction,
      knowledge_policy_json, dossier_json
    ) values (
      '88000000-0000-4000-8000-000000000003',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000003',
      'INNOCENT', '{}'::jsonb, '{}'::jsonb
    )
  $sql$),
  '23503',
  'a dossier cannot reference a player from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.dossiers (
      id, room_id, story_id, player_id, faction,
      knowledge_policy_json, dossier_json
    ) values (
      '88000000-0000-4000-8000-000000000004',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000001',
      'INNOCENT', '{}'::jsonb, '{}'::jsonb
    )
  $sql$),
  '23505',
  'a story has only one dossier per player'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.story_rounds (
      id, room_id, story_id, sequence, title,
      target_duration_seconds, public_event_json
    ) values (
      '87000000-0000-4000-8000-000000000004',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      1, 'Duplicate', 60, '{}'::jsonb
    )
  $sql$),
  '23505',
  'round sequence is unique within a story'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence (
      id, room_id, story_id, round_id, evidence_kind,
      content_json, release_rule_json, audience_json
    ) values (
      '91000000-0000-4000-8000-000000000004',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '87000000-0000-4000-8000-000000000003',
      'TESTIMONY', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
    )
  $sql$),
  '23503',
  'evidence cannot reference a round from another story'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence_dependencies (
      id, room_id, story_id, source_evidence_id,
      target_evidence_id, dependency_kind
    ) values (
      '92000000-0000-4000-8000-000000000002',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000003',
      'SUPPORTS'
    )
  $sql$),
  '23503',
  'evidence edges cannot cross story boundaries'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.mission_specs (
      id, room_id, story_id, round_id, assigned_player_id, action_kind,
      objective_text, completion_rule_json, stakes_text,
      host_confirmation_guidance, failure_consequence_id
    ) values (
      '94000000-0000-4000-8000-000000000002',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '87000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000001',
      'ASK_PLAYER', 'Ask a question.', '{}'::jsonb,
      'A clue may be released.', 'Confirm the question.',
      '93000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'a mission cannot reference a consequence from another story'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.intervention_specs (
      id, room_id, story_id, round_id, strength, candidate_kind,
      canonical_effect_json, presentation_json, eligibility_rule_json
    ) values (
      '95000000-0000-4000-8000-000000000002',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '87000000-0000-4000-8000-000000000001',
      4, 'DIRECTED_QUESTION', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
    )
  $sql$),
  '23514',
  'intervention strength is limited to the three escalation levels'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.accomplice_revelations (
      id, room_id, story_id, accomplice_player_id, round_id, revelation_json
    ) values (
      '96000000-0000-4000-8000-000000000002',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000003',
      '87000000-0000-4000-8000-000000000002',
      '{}'::jsonb
    )
  $sql$),
  '23503',
  'an accomplice revelation cannot target a player from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_reveal_sections (
      id, room_id, story_id, sequence, section_kind, section_json
    ) values (
      '97000000-0000-4000-8000-000000000002',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      1, 'MOTIVE', '{}'::jsonb
    )
  $sql$),
  '23505',
  'final reveal section sequence is unique within a story'
);

set constraints all immediate;

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set
      story_id = '85000000-0000-4000-8000-000000000002',
      locked_at = app_private.current_database_time()
    where id = '81000000-0000-4000-8000-000000000001'
  $sql$),
  '23503',
  'a room cannot reference another room canonical story'
);

update app_private.rooms
set
  story_id = '85000000-0000-4000-8000-000000000001',
  locked_at = app_private.current_database_time(),
  current_round_id = '87000000-0000-4000-8000-000000000001'
where id = '81000000-0000-4000-8000-000000000001';

select is(
  (
    select pg_catalog.jsonb_build_object(
      'storyId', story_id,
      'roundId', current_round_id,
      'locked', locked_at is not null
    )
    from app_private.rooms
    where id = '81000000-0000-4000-8000-000000000001'
  ),
  pg_catalog.jsonb_build_object(
    'storyId', '85000000-0000-4000-8000-000000000001'::uuid,
    'roundId', '87000000-0000-4000-8000-000000000001'::uuid,
    'locked', true
  ),
  'a room may reference its own locked story and current round'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.rooms
    set current_round_id = '87000000-0000-4000-8000-000000000003'
    where id = '81000000-0000-4000-8000-000000000001'
  $sql$),
  '23503',
  'a room current round cannot come from another story'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.evidence_dependencies (
      id, room_id, story_id, source_evidence_id,
      target_evidence_id, dependency_kind
    ) values (
      '92000000-0000-4000-8000-000000000003',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001',
      'REQUIRES'
    )
  $sql$),
  '23514',
  'an evidence dependency cannot point to itself'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.relationships (
      id, room_id, story_id, source_player_id,
      target_player_id, relationship_json
    ) values (
      '89000000-0000-4000-8000-000000000002',
      '81000000-0000-4000-8000-000000000001',
      '85000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000001',
      '83000000-0000-4000-8000-000000000001',
      '{}'::jsonb
    )
  $sql$),
  '23514',
  'a generated relationship must connect two different players'
);

select * from finish();

rollback;
