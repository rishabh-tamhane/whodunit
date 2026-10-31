-- GEN-03/05/07/09: immutable snapshots, durable jobs, atomic lock, and purge.

alter table app_private.story_generation_jobs
  add column lease_owner text,
  add column lease_expires_at timestamp with time zone,
  add column purge_due_at timestamp with time zone,
  add column source_purged_at timestamp with time zone,
  add constraint story_generation_jobs_lease_shape check (
    (lease_owner is null and lease_expires_at is null)
    or (
      lease_owner is not null
      and pg_catalog.char_length(pg_catalog.btrim(lease_owner)) between 1 and 100
      and lease_expires_at is not null
    )
  ),
  add constraint story_generation_jobs_purge_order check (
    source_purged_at is null
    or (purge_due_at is not null and source_purged_at <= purge_due_at)
  );

create function app_private.assert_service_role()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'service role required';
  end if;
end;
$function$;

create function public.start_story_generation(
  target_room_id uuid,
  expected_state_version bigint,
  idempotency_key uuid,
  requested_model_id text,
  requested_escalation_model_id text,
  requested_prompt_version text,
  requested_story_schema_version text,
  requested_validator_version text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  existing_job app_private.story_generation_jobs%rowtype;
  created_job app_private.story_generation_jobs%rowtype;
  readiness jsonb;
  generation_snapshot jsonb;
  next_version bigint;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);

  select job.* into existing_job
  from app_private.story_generation_jobs as job
  where job.room_id = target_room_id and job.idempotency_key = start_story_generation.idempotency_key;
  if found then
    return pg_catalog.jsonb_build_object(
      'jobId', existing_job.id,
      'roomId', existing_job.room_id,
      'status', existing_job.status::text,
      'phase', existing_job.phase::text,
      'replayed', true
    );
  end if;

  if requested_model_id <> 'gpt-6.1-sol'
    or requested_escalation_model_id <> 'gpt-6-astra' then
    raise exception using errcode = '22023', message = 'unapproved story model policy';
  end if;

  select room.* into strict room_record
  from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.story_id is not null or room_record.locked_at is not null then
    raise exception using errcode = '55000', message = 'a locked room can never regenerate';
  end if;

  readiness := app_private.calculate_room_readiness(target_room_id);
  if coalesce((readiness ->> 'ready')::boolean, false) is not true then
    raise exception using errcode = '55000', message = 'room is not ready for generation';
  end if;

  select pg_catalog.jsonb_build_object(
    'snapshotVersion', 'generation-snapshot-v1',
    'roomId', room_record.id,
    'stateVersion', room_record.state_version::text,
    'capturedAt', app_private.current_database_time(),
    'configuration', pg_catalog.jsonb_build_object(
      'durationProfileVersion', room_record.duration_profile_version,
      'durationMinutes', room_record.duration_minutes,
      'roundCount', profile.round_count,
      'scoringProfileVersion', room_record.scoring_profile_version,
      'murdererCount', (room_record.config_json ->> 'murdererCount')::integer,
      'accompliceCount', (room_record.config_json ->> 'accompliceCount')::integer,
      'innocentCount', (room_record.config_json ->> 'innocentCount')::integer,
      'murdererAware', (room_record.config_json ->> 'murdererAware')::boolean
    ),
    'players', (
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'playerId', player.id,
        'displayName', player.display_name,
        'costume', player.costume,
        'hostBackground', player.host_background
      ) order by player.seat_order)
      from app_private.players as player where player.room_id = target_room_id
    ),
    'descriptionResponses', (
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'subjectPlayerId', description.subject_player_id,
        'responseStatus', description.response_status,
        'descriptionText', description.description_text
      ) order by description.subject_player_id, description.id)
      from app_private.player_descriptions as description
      where description.room_id = target_room_id and description.purged_at is null
    )
  ) into generation_snapshot
  from app_private.duration_profiles as profile
  where profile.profile_version = room_record.duration_profile_version
    and profile.duration_minutes = room_record.duration_minutes;

  if generation_snapshot is null then
    raise exception using errcode = '55000', message = 'generation profile is unavailable';
  end if;

  insert into app_private.story_generation_jobs (
    room_id, idempotency_key, input_snapshot_json, model_id,
    escalation_model_id, prompt_version, story_schema_version, validator_version
  ) values (
    target_room_id, idempotency_key, generation_snapshot, requested_model_id,
    requested_escalation_model_id, requested_prompt_version,
    requested_story_schema_version, requested_validator_version
  ) returning * into created_job;

  update app_private.rooms
  set status = 'GENERATING', state_version = state_version + 1,
      updated_at = app_private.current_database_time()
  where id = target_room_id
  returning state_version into next_version;

  perform app_private.append_identity_event(
    target_room_id, next_version, 'GENERATION_REQUESTED', 'GAME_MASTER',
    auth.uid(), null, created_job.id, 'GENERATION_CHANGED'
  );

  return pg_catalog.jsonb_build_object(
    'jobId', created_job.id,
    'roomId', created_job.room_id,
    'status', created_job.status::text,
    'phase', created_job.phase::text,
    'stateVersion', next_version::text,
    'replayed', false
  );
end;
$function$;

create function public.claim_generation_job(
  target_job_id uuid,
  requested_lease_owner text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job_record app_private.story_generation_jobs%rowtype;
begin
  perform app_private.assert_service_role();
  select job.* into strict job_record from app_private.story_generation_jobs as job
  where job.id = target_job_id for update;
  if job_record.status not in ('PENDING', 'RUNNING') then
    raise exception using errcode = '55000', message = 'generation job is terminal';
  end if;
  if job_record.lease_expires_at is not null
    and job_record.lease_expires_at > app_private.current_database_time()
    and job_record.lease_owner <> requested_lease_owner then
    raise exception using errcode = '55P03', message = 'generation job is leased';
  end if;
  update app_private.story_generation_jobs set
    status = 'RUNNING', phase = case when phase = 'SNAPSHOT' then 'BLUEPRINT' else phase end,
    lease_owner = requested_lease_owner,
    lease_expires_at = app_private.current_database_time() + interval '5 minutes',
    started_at = coalesce(started_at, app_private.current_database_time()),
    updated_at = app_private.current_database_time()
  where id = target_job_id returning * into job_record;
  return pg_catalog.jsonb_build_object(
    'jobId', job_record.id, 'roomId', job_record.room_id,
    'inputSnapshot', job_record.input_snapshot_json,
    'modelId', job_record.model_id, 'escalationModelId', job_record.escalation_model_id,
    'attemptCount', job_record.attempt_count, 'repairCount', job_record.repair_count,
    'escalationCount', job_record.escalation_count,
    'providerResponseIds', job_record.provider_response_ids_json
  );
end;
$function$;

create function public.checkpoint_generation_job(
  target_job_id uuid,
  expected_lease_owner text,
  next_phase text,
  provider_response_id text,
  generated_content jsonb,
  validation_issues jsonb,
  added_input_tokens bigint,
  added_output_tokens bigint,
  added_latency_ms bigint,
  repair_increment integer default 0,
  escalation_increment integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job_record app_private.story_generation_jobs%rowtype;
begin
  perform app_private.assert_service_role();
  if next_phase not in ('BLUEPRINT','PLAYABLE_CONTENT','VALIDATION','CRITIC','REPAIR','LOCKING') then
    raise exception using errcode = '22023', message = 'invalid generation phase';
  end if;
  select job.* into strict job_record from app_private.story_generation_jobs as job
  where job.id = target_job_id for update;
  if job_record.status <> 'RUNNING' or job_record.lease_owner <> expected_lease_owner then
    raise exception using errcode = '55000', message = 'generation lease is not owned';
  end if;
  update app_private.story_generation_jobs set
    phase = next_phase::app_private.generation_phase,
    playable_content_json = coalesce(generated_content, playable_content_json),
    validation_issues_json = coalesce(validation_issues, validation_issues_json),
    provider_response_ids_json = case when provider_response_id is null then provider_response_ids_json else provider_response_ids_json || pg_catalog.jsonb_build_object('story', provider_response_id) end,
    input_tokens = input_tokens + greatest(added_input_tokens, 0),
    output_tokens = output_tokens + greatest(added_output_tokens, 0),
    latency_ms = latency_ms + greatest(added_latency_ms, 0),
    repair_count = repair_count + repair_increment,
    escalation_count = escalation_count + escalation_increment,
    attempt_count = attempt_count + repair_increment + escalation_increment,
    lease_expires_at = app_private.current_database_time() + interval '5 minutes',
    updated_at = app_private.current_database_time()
  where id = target_job_id returning * into job_record;
  return pg_catalog.jsonb_build_object('jobId', job_record.id, 'status', job_record.status::text, 'phase', job_record.phase::text);
end;
$function$;

create function public.release_generation_lease(
  target_job_id uuid,
  expected_lease_owner text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform app_private.assert_service_role();
  update app_private.story_generation_jobs
  set lease_owner = null, lease_expires_at = null,
      updated_at = app_private.current_database_time()
  where id = target_job_id and status = 'RUNNING'
    and lease_owner = expected_lease_owner;
  if not found then
    raise exception using errcode = '55000', message = 'generation lease is not owned';
  end if;
end;
$function$;

create function app_private.purge_generation_source(target_job_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job_record app_private.story_generation_jobs%rowtype;
  purge_time timestamp with time zone := app_private.current_database_time();
begin
  select job.* into strict job_record from app_private.story_generation_jobs as job
  where job.id = target_job_id for update;
  update app_private.player_descriptions set description_text = null, purged_at = purge_time, updated_at = purge_time
  where room_id = job_record.room_id and purged_at is null;
  update app_private.players set host_background = null, updated_at = purge_time
  where room_id = job_record.room_id and host_background is not null;
  update app_private.story_generation_jobs set
    input_snapshot_json = pg_catalog.jsonb_build_object('purged', true, 'snapshotVersion', 'generation-snapshot-v1'),
    blueprint_json = null,
    playable_content_json = null,
    source_purged_at = purge_time,
    purge_due_at = coalesce(purge_due_at, purge_time + interval '24 hours'),
    updated_at = purge_time
  where id = target_job_id and source_purged_at is null;
end;
$function$;

create function public.fail_generation_job(
  target_job_id uuid,
  expected_lease_owner text,
  failure_code text,
  validation_issues jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job_record app_private.story_generation_jobs%rowtype;
  next_version bigint;
begin
  perform app_private.assert_service_role();
  select job.* into strict job_record from app_private.story_generation_jobs as job
  where job.id = target_job_id for update;
  perform app_private.lock_room(job_record.room_id);
  if job_record.status <> 'RUNNING' or job_record.lease_owner <> expected_lease_owner then
    raise exception using errcode = '55000', message = 'generation lease is not owned';
  end if;
  update app_private.story_generation_jobs set
    status = 'FAILED', sanitized_error_code = failure_code,
    validation_issues_json = validation_issues, finished_at = app_private.current_database_time(),
    purge_due_at = app_private.current_database_time() + interval '24 hours',
    lease_owner = null, lease_expires_at = null, updated_at = app_private.current_database_time()
  where id = target_job_id returning * into job_record;
  update app_private.rooms set status = 'LOBBY', state_version = state_version + 1,
    updated_at = app_private.current_database_time()
  where id = job_record.room_id and story_id is null returning state_version into next_version;
  perform app_private.purge_generation_source(target_job_id);
  perform app_private.append_identity_event(job_record.room_id, next_version, 'GENERATION_FAILED', 'SYSTEM', null, null, target_job_id, 'GENERATION_CHANGED');
  return pg_catalog.jsonb_build_object('jobId', target_job_id, 'status', 'FAILED', 'roomStatus', 'LOBBY', 'stateVersion', next_version::text);
end;
$function$;

create function public.lock_generated_story(
  target_job_id uuid,
  expected_lease_owner text,
  story_package jsonb,
  package_checksum_hex text,
  solution_checksum_hex text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job_record app_private.story_generation_jobs%rowtype;
  room_record app_private.rooms%rowtype;
  locked_story_id uuid := (story_package ->> 'storyId')::uuid;
  lock_time timestamp with time zone := app_private.current_database_time();
  next_version bigint;
  configured_count integer;
  package_character_count integer;
  package_dossier_count integer;
begin
  perform app_private.assert_service_role();
  select job.* into strict job_record from app_private.story_generation_jobs as job
  where job.id = target_job_id for update;
  perform app_private.lock_room(job_record.room_id);
  select room.* into strict room_record from app_private.rooms as room where room.id = job_record.room_id;
  if job_record.status <> 'RUNNING' or job_record.lease_owner <> expected_lease_owner then
    raise exception using errcode = '55000', message = 'generation lease is not owned';
  end if;
  if room_record.status <> 'GENERATING' or room_record.story_id is not null or room_record.locked_at is not null then
    raise exception using errcode = '55000', message = 'room cannot lock a story';
  end if;
  if story_package ->> 'schemaVersion' <> job_record.story_schema_version
    or story_package -> 'victim' ->> 'isNpc' <> 'true' then
    raise exception using errcode = '23514', message = 'story package failed lock checks';
  end if;
  select pg_catalog.count(*)::integer into configured_count from app_private.players where room_id = job_record.room_id;
  select pg_catalog.count(distinct (item ->> 'playerId')::uuid)::integer into package_character_count from pg_catalog.jsonb_array_elements(story_package -> 'characters') as item;
  select pg_catalog.count(distinct (item ->> 'playerId')::uuid)::integer into package_dossier_count from pg_catalog.jsonb_array_elements(story_package -> 'dossiers') as item;
  if configured_count <> package_character_count or configured_count <> package_dossier_count
    or exists (
      select 1 from app_private.players as player where player.room_id = job_record.room_id
      and not exists (select 1 from pg_catalog.jsonb_array_elements(story_package -> 'characters') as item where (item ->> 'playerId')::uuid = player.id)
    )
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(story_package -> 'characters') as item
      where not exists (select 1 from app_private.players as player where player.room_id = job_record.room_id and player.id = (item ->> 'playerId')::uuid)
    ) then
    raise exception using errcode = '23514', message = 'story player set changed before lock';
  end if;

  insert into app_private.canonical_stories (
    id, room_id, source_generation_job_id, story_schema_version, scoring_profile_version,
    prompt_version, model_id, package_json, package_checksum, solution_checksum, locked_at
  ) values (
    locked_story_id, job_record.room_id, job_record.id, job_record.story_schema_version,
    story_package ->> 'scoringProfileVersion', job_record.prompt_version, job_record.model_id,
    story_package, pg_catalog.decode(package_checksum_hex, 'hex'),
    pg_catalog.decode(solution_checksum_hex, 'hex'), lock_time
  );
  insert into app_private.canonical_solutions (id, room_id, story_id, victim_json, solution_json)
  values (pg_catalog.gen_random_uuid(), job_record.room_id, locked_story_id, story_package -> 'victim', story_package -> 'solution');
  insert into app_private.story_rounds (id, room_id, story_id, sequence, title, target_duration_seconds, public_event_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'sequence')::smallint,
    item ->> 'title', (item ->> 'targetDurationSeconds')::integer,
    pg_catalog.jsonb_build_object('text', item ->> 'publicEvent')
  from pg_catalog.jsonb_array_elements(story_package -> 'rounds') as item;
  insert into app_private.dossiers (id, room_id, story_id, player_id, faction, knowledge_policy_json, dossier_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'playerId')::uuid,
    (item ->> 'faction')::app_private.faction,
    pg_catalog.jsonb_build_object(
      'knownMurdererPlayerIds', item -> 'knownMurdererPlayerIds',
      'factionVisible', (item ->> 'faction') <> 'MURDERER'
        or coalesce((story_package ->> 'murdererAware')::boolean, false)
    ), item
  from pg_catalog.jsonb_array_elements(story_package -> 'dossiers') as item;
  insert into app_private.relationships (id, room_id, story_id, source_player_id, target_player_id, relationship_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'sourcePlayerId')::uuid,
    (item ->> 'targetPlayerId')::uuid, item
  from pg_catalog.jsonb_array_elements(story_package -> 'relationships') as item;
  insert into app_private.timeline_events (id, room_id, story_id, sequence, event_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'sequence')::integer, item
  from pg_catalog.jsonb_array_elements(story_package -> 'timeline') as item;
  insert into app_private.evidence (id, room_id, story_id, round_id, evidence_kind, is_required, content_json, release_rule_json, audience_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'roundId')::uuid,
    item ->> 'kind', (item ->> 'isRequired')::boolean, item, item -> 'releaseRule', item -> 'audience'
  from pg_catalog.jsonb_array_elements(story_package -> 'evidence') as item;
  insert into app_private.evidence_dependencies (id, room_id, story_id, source_evidence_id, target_evidence_id, dependency_kind)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'sourceEvidenceId')::uuid,
    (item ->> 'targetEvidenceId')::uuid, (item ->> 'kind')::app_private.evidence_dependency_kind
  from pg_catalog.jsonb_array_elements(story_package -> 'evidenceDependencies') as item;
  insert into app_private.consequence_specs (id, room_id, story_id, severity, consequence_json, eligibility_rule_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'severity')::smallint,
    item, item -> 'eligibility'
  from pg_catalog.jsonb_array_elements(story_package -> 'consequences') as item;
  insert into app_private.mission_specs (id, room_id, story_id, round_id, assigned_player_id, action_kind, objective_text, completion_rule_json, stakes_text, host_confirmation_guidance, success_effect_json, failure_consequence_id)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'roundId')::uuid,
    (item ->> 'assignedPlayerId')::uuid, (item ->> 'actionKind')::app_private.mission_action_kind,
    item ->> 'objective', pg_catalog.jsonb_build_object('description', item ->> 'completionRule'), item ->> 'stakes',
    item ->> 'hostConfirmationGuidance', nullif(item -> 'successEffect', 'null'::jsonb), (item ->> 'failureConsequenceId')::uuid
  from pg_catalog.jsonb_array_elements(story_package -> 'missions') as item;
  insert into app_private.intervention_specs (id, room_id, story_id, round_id, strength, candidate_kind, canonical_effect_json, presentation_json, eligibility_rule_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'roundId')::uuid,
    (item ->> 'strength')::smallint, (item ->> 'candidateKind')::app_private.intervention_candidate_kind,
    item -> 'canonicalEffect', pg_catalog.jsonb_build_object('text', item ->> 'presentation'),
    pg_catalog.jsonb_build_object('eligibleAfterSeconds', (item ->> 'eligibleAfterSeconds')::integer)
  from pg_catalog.jsonb_array_elements(story_package -> 'interventions') as item;
  insert into app_private.accomplice_revelations (id, room_id, story_id, accomplice_player_id, round_id, revelation_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'accomplicePlayerId')::uuid,
    (item ->> 'roundId')::uuid, item
  from pg_catalog.jsonb_array_elements(story_package -> 'accompliceRevelations') as item;
  insert into app_private.final_reveal_sections (id, room_id, story_id, sequence, section_kind, section_json)
  select (item ->> 'id')::uuid, job_record.room_id, locked_story_id, (item ->> 'sequence')::smallint,
    item ->> 'kind', item
  from pg_catalog.jsonb_array_elements(story_package -> 'finalReveal') as item;
  insert into app_private.mission_states (room_id, story_id, mission_spec_id)
  select job_record.room_id, locked_story_id, mission.id from app_private.mission_specs as mission
  where mission.room_id = job_record.room_id and mission.story_id = locked_story_id;
  insert into app_private.accomplice_revelation_states (
    room_id, story_id, revelation_spec_id
  )
  select job_record.room_id, locked_story_id, revelation.id
  from app_private.accomplice_revelations as revelation
  where revelation.room_id = job_record.room_id
    and revelation.story_id = locked_story_id;

  update app_private.story_generation_jobs set status = 'SUCCEEDED', phase = 'COMPLETE',
    finished_at = lock_time, purge_due_at = lock_time + interval '24 hours',
    lease_owner = null, lease_expires_at = null, updated_at = lock_time
  where id = target_job_id;
  update app_private.rooms set story_id = locked_story_id, locked_at = lock_time,
    status = 'READY_TO_START', sensitive_input_purge_pending = true,
    state_version = state_version + 1, updated_at = lock_time
  where id = job_record.room_id returning state_version into next_version;
  perform app_private.purge_generation_source(target_job_id);
  update app_private.rooms set sensitive_input_purge_pending = false where id = job_record.room_id;
  perform app_private.append_identity_event(job_record.room_id, next_version, 'STORY_LOCKED', 'SYSTEM', null, null, locked_story_id, 'GENERATION_CHANGED');
  return pg_catalog.jsonb_build_object('jobId', target_job_id, 'storyId', locked_story_id, 'status', 'SUCCEEDED', 'roomStatus', 'READY_TO_START', 'stateVersion', next_version::text);
end;
$function$;

create function public.get_generation_status(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare result jsonb;
begin
  perform app_private.assert_current_game_master(target_room_id);
  select pg_catalog.jsonb_build_object(
    'roomId', room.id, 'roomStatus', room.status::text, 'stateVersion', room.state_version::text,
    'locked', room.story_id is not null,
    'job', case when job.id is null then null else pg_catalog.jsonb_build_object(
      'jobId', job.id, 'status', job.status::text, 'phase', job.phase::text,
      'attemptCount', job.attempt_count, 'repairCount', job.repair_count,
      'escalationCount', job.escalation_count, 'sanitizedErrorCode', job.sanitized_error_code,
      'createdAt', job.created_at, 'startedAt', job.started_at, 'finishedAt', job.finished_at
    ) end
  ) into result
  from app_private.rooms as room
  left join lateral (
    select candidate.* from app_private.story_generation_jobs as candidate
    where candidate.room_id = room.id order by candidate.created_at desc limit 1
  ) as job on true
  where room.id = target_room_id;
  return result;
end;
$function$;

create function public.record_generation_webhook(
  provider_event_id text,
  provider_response_id text,
  provider_event_type text,
  payload_checksum_hex text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job_record app_private.story_generation_jobs%rowtype;
  existing_receipt app_private.webhook_receipts%rowtype;
begin
  perform app_private.assert_service_role();
  select job.* into job_record
  from app_private.story_generation_jobs as job
  where job.provider_response_ids_json @> pg_catalog.jsonb_build_object('story', provider_response_id)
  order by job.created_at desc limit 1;
  if job_record.id is null then
    return pg_catalog.jsonb_build_object('known', false, 'duplicate', false);
  end if;
  select receipt.* into existing_receipt from app_private.webhook_receipts as receipt
  where receipt.provider = 'openai' and receipt.provider_event_id = record_generation_webhook.provider_event_id;
  if found then
    return pg_catalog.jsonb_build_object('known', true, 'duplicate', true, 'jobId', existing_receipt.generation_job_id);
  end if;
  insert into app_private.webhook_receipts (
    room_id, generation_job_id, provider, provider_event_id, event_type,
    payload_hash, outcome, received_at
  ) values (
    job_record.room_id, job_record.id, 'openai', provider_event_id,
    provider_event_type, pg_catalog.decode(payload_checksum_hex, 'hex'),
    'PROCESSED', app_private.current_database_time()
  );
  return pg_catalog.jsonb_build_object('known', true, 'duplicate', false, 'jobId', job_record.id);
end;
$function$;

create function public.purge_terminal_generation_sources()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare target record; purged integer := 0;
begin
  perform app_private.assert_service_role();
  for target in
    select id from app_private.story_generation_jobs
    where status in ('SUCCEEDED','FAILED','CANCELLED') and source_purged_at is null
      and purge_due_at <= app_private.current_database_time()
    for update skip locked
  loop
    perform app_private.purge_generation_source(target.id);
    purged := purged + 1;
  end loop;
  return purged;
end;
$function$;

revoke execute on function app_private.assert_service_role() from public, anon, authenticated, service_role;
revoke execute on function app_private.purge_generation_source(uuid) from public, anon, authenticated, service_role;
revoke all on function public.start_story_generation(uuid,bigint,uuid,text,text,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.claim_generation_job(uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.checkpoint_generation_job(uuid,text,text,text,jsonb,jsonb,bigint,bigint,bigint,integer,integer) from public, anon, authenticated, service_role;
revoke all on function public.release_generation_lease(uuid,text) from public, anon, authenticated, service_role;
revoke all on function public.fail_generation_job(uuid,text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.lock_generated_story(uuid,text,jsonb,text,text) from public, anon, authenticated, service_role;
revoke all on function public.get_generation_status(uuid) from public, anon, authenticated, service_role;
revoke all on function public.record_generation_webhook(text,text,text,text) from public, anon, authenticated, service_role;
revoke all on function public.purge_terminal_generation_sources() from public, anon, authenticated, service_role;

grant execute on function public.start_story_generation(uuid,bigint,uuid,text,text,text,text,text) to authenticated;
grant execute on function public.get_generation_status(uuid) to authenticated;
grant execute on function public.record_generation_webhook(text,text,text,text) to service_role;
grant execute on function public.claim_generation_job(uuid,text) to service_role;
grant execute on function public.checkpoint_generation_job(uuid,text,text,text,jsonb,jsonb,bigint,bigint,bigint,integer,integer) to service_role;
grant execute on function public.release_generation_lease(uuid,text) to service_role;
grant execute on function public.fail_generation_job(uuid,text,text,jsonb) to service_role;
grant execute on function public.lock_generated_story(uuid,text,jsonb,text,text) to service_role;
grant execute on function public.purge_terminal_generation_sources() to service_role;
