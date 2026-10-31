-- DB-04: generation jobs, canonical story package, and materialized story rows.

create type app_private.generation_job_status as enum (
  'PENDING',
  'RUNNING',
  'SUCCEEDED',
  'FAILED',
  'CANCELLED'
);

create type app_private.generation_phase as enum (
  'SNAPSHOT',
  'BLUEPRINT',
  'PLAYABLE_CONTENT',
  'VALIDATION',
  'CRITIC',
  'REPAIR',
  'LOCKING',
  'COMPLETE'
);

create type app_private.faction as enum (
  'MURDERER',
  'ACCOMPLICE',
  'INNOCENT'
);

create type app_private.mission_action_kind as enum (
  'ASK_PLAYER',
  'SHARE_FACT',
  'MAKE_PUBLIC_CLAIM',
  'PRESENT_EVIDENCE',
  'SUBMIT_PRIVATE_THEORY',
  'COMPARE_ALIBIS',
  'REQUEST_INFORMATION'
);

create type app_private.evidence_dependency_kind as enum (
  'SUPPORTS',
  'CONTRADICTS',
  'REQUIRES',
  'RED_HERRING_EXPLAINED_BY'
);

create type app_private.intervention_candidate_kind as enum (
  'DIRECTED_QUESTION',
  'RELEASE_EVIDENCE',
  'RELEASE_CONSEQUENCE',
  'ACTIVATE_MISSION'
);

create table app_private.story_generation_jobs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  idempotency_key uuid not null,
  status app_private.generation_job_status not null default 'PENDING',
  phase app_private.generation_phase not null default 'SNAPSHOT',
  input_snapshot_json jsonb not null,
  blueprint_json jsonb,
  playable_content_json jsonb,
  validation_issues_json jsonb not null default '[]'::jsonb,
  provider_response_ids_json jsonb not null default '{}'::jsonb,
  attempt_count integer not null default 1,
  repair_count integer not null default 0,
  escalation_count integer not null default 0,
  model_id text not null,
  escalation_model_id text,
  prompt_version text not null,
  story_schema_version text not null,
  validator_version text not null,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  latency_ms bigint not null default 0,
  sanitized_error_code text,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint story_generation_jobs_room_id_id_unique unique (room_id, id),
  constraint story_generation_jobs_room_idempotency_unique unique (
    room_id,
    idempotency_key
  ),
  constraint story_generation_jobs_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint story_generation_jobs_input_object check (
    pg_catalog.jsonb_typeof(input_snapshot_json) = 'object'
  ),
  constraint story_generation_jobs_blueprint_object check (
    blueprint_json is null or pg_catalog.jsonb_typeof(blueprint_json) = 'object'
  ),
  constraint story_generation_jobs_content_object check (
    playable_content_json is null
    or pg_catalog.jsonb_typeof(playable_content_json) = 'object'
  ),
  constraint story_generation_jobs_validation_array check (
    pg_catalog.jsonb_typeof(validation_issues_json) = 'array'
  ),
  constraint story_generation_jobs_response_ids_object check (
    pg_catalog.jsonb_typeof(provider_response_ids_json) = 'object'
  ),
  constraint story_generation_jobs_counts_nonnegative check (
    attempt_count > 0
    and repair_count >= 0
    and escalation_count >= 0
    and input_tokens >= 0
    and output_tokens >= 0
    and latency_ms >= 0
  ),
  constraint story_generation_jobs_versions_present check (
    pg_catalog.char_length(pg_catalog.btrim(model_id)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(prompt_version)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(story_schema_version)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(validator_version)) > 0
  ),
  constraint story_generation_jobs_error_code_length check (
    sanitized_error_code is null
    or pg_catalog.char_length(sanitized_error_code) between 1 and 100
  ),
  constraint story_generation_jobs_status_times check (
    (
      status = 'PENDING'
      and started_at is null
      and finished_at is null
    )
    or (
      status = 'RUNNING'
      and started_at is not null
      and finished_at is null
    )
    or (
      status in ('SUCCEEDED', 'FAILED', 'CANCELLED')
      and started_at is not null
      and finished_at is not null
    )
  ),
  constraint story_generation_jobs_time_order check (
    (finished_at is null or finished_at >= started_at)
    and updated_at >= created_at
  )
);

create unique index story_generation_jobs_one_active_per_room_idx
  on app_private.story_generation_jobs (room_id)
  where status in ('PENDING', 'RUNNING');

create index story_generation_jobs_room_created_idx
  on app_private.story_generation_jobs (room_id, created_at desc);

create table app_private.canonical_stories (
  id uuid primary key,
  room_id uuid not null,
  source_generation_job_id uuid not null,
  story_schema_version text not null,
  scoring_profile_version text not null,
  prompt_version text not null,
  model_id text not null,
  package_json jsonb not null,
  package_checksum bytea not null,
  solution_checksum bytea not null,
  locked_at timestamp with time zone not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint canonical_stories_room_unique unique (room_id),
  constraint canonical_stories_room_id_id_unique unique (room_id, id),
  constraint canonical_stories_source_job_unique unique (source_generation_job_id),
  constraint canonical_stories_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint canonical_stories_job_room_fk foreign key (
    room_id,
    source_generation_job_id
  ) references app_private.story_generation_jobs (room_id, id) on delete restrict,
  constraint canonical_stories_package_object check (
    pg_catalog.jsonb_typeof(package_json) = 'object'
  ),
  constraint canonical_stories_checksum_lengths check (
    pg_catalog.octet_length(package_checksum) = 32
    and pg_catalog.octet_length(solution_checksum) = 32
  ),
  constraint canonical_stories_versions_present check (
    pg_catalog.char_length(pg_catalog.btrim(story_schema_version)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(scoring_profile_version)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(prompt_version)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(model_id)) > 0
  )
);

create table app_private.canonical_solutions (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  victim_json jsonb not null,
  solution_json jsonb not null,
  constraint canonical_solutions_story_unique unique (story_id),
  constraint canonical_solutions_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint canonical_solutions_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint canonical_solutions_victim_object check (
    pg_catalog.jsonb_typeof(victim_json) = 'object'
  ),
  constraint canonical_solutions_solution_object check (
    pg_catalog.jsonb_typeof(solution_json) = 'object'
  )
);

create table app_private.story_rounds (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  sequence smallint not null,
  title text not null,
  target_duration_seconds integer not null,
  public_event_json jsonb not null,
  constraint story_rounds_room_story_id_unique unique (room_id, story_id, id),
  constraint story_rounds_story_sequence_unique unique (story_id, sequence),
  constraint story_rounds_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint story_rounds_sequence_positive check (sequence > 0),
  constraint story_rounds_duration_positive check (target_duration_seconds > 0),
  constraint story_rounds_title_present check (
    pg_catalog.char_length(pg_catalog.btrim(title)) > 0
  ),
  constraint story_rounds_event_object check (
    pg_catalog.jsonb_typeof(public_event_json) = 'object'
  )
);

create table app_private.dossiers (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  player_id uuid not null,
  faction app_private.faction not null,
  knowledge_policy_json jsonb not null,
  dossier_json jsonb not null,
  constraint dossiers_room_story_id_unique unique (room_id, story_id, id),
  constraint dossiers_story_player_unique unique (story_id, player_id),
  constraint dossiers_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint dossiers_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint dossiers_knowledge_policy_object check (
    pg_catalog.jsonb_typeof(knowledge_policy_json) = 'object'
  ),
  constraint dossiers_content_object check (
    pg_catalog.jsonb_typeof(dossier_json) = 'object'
  )
);

create table app_private.relationships (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  source_player_id uuid not null,
  target_player_id uuid not null,
  relationship_json jsonb not null,
  constraint relationships_room_story_id_unique unique (room_id, story_id, id),
  constraint relationships_story_pair_unique unique (
    story_id,
    source_player_id,
    target_player_id
  ),
  constraint relationships_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint relationships_source_player_room_fk foreign key (
    room_id,
    source_player_id
  ) references app_private.players (room_id, id) on delete restrict,
  constraint relationships_target_player_room_fk foreign key (
    room_id,
    target_player_id
  ) references app_private.players (room_id, id) on delete restrict,
  constraint relationships_other_player check (
    source_player_id <> target_player_id
  ),
  constraint relationships_content_object check (
    pg_catalog.jsonb_typeof(relationship_json) = 'object'
  )
);

create table app_private.timeline_events (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  sequence integer not null,
  event_json jsonb not null,
  constraint timeline_events_room_story_id_unique unique (room_id, story_id, id),
  constraint timeline_events_story_sequence_unique unique (story_id, sequence),
  constraint timeline_events_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint timeline_events_sequence_positive check (sequence > 0),
  constraint timeline_events_content_object check (
    pg_catalog.jsonb_typeof(event_json) = 'object'
  )
);

create table app_private.evidence (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  round_id uuid,
  evidence_kind text not null,
  is_required boolean not null default false,
  content_json jsonb not null,
  release_rule_json jsonb not null,
  audience_json jsonb not null,
  constraint evidence_room_story_id_unique unique (room_id, story_id, id),
  constraint evidence_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint evidence_round_room_story_fk foreign key (
    room_id,
    story_id,
    round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint evidence_kind_present check (
    pg_catalog.char_length(pg_catalog.btrim(evidence_kind)) > 0
  ),
  constraint evidence_json_objects check (
    pg_catalog.jsonb_typeof(content_json) = 'object'
    and pg_catalog.jsonb_typeof(release_rule_json) = 'object'
    and pg_catalog.jsonb_typeof(audience_json) = 'object'
  )
);

create table app_private.evidence_dependencies (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  source_evidence_id uuid not null,
  target_evidence_id uuid not null,
  dependency_kind app_private.evidence_dependency_kind not null,
  constraint evidence_dependencies_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint evidence_dependencies_edge_unique unique (
    story_id,
    source_evidence_id,
    target_evidence_id,
    dependency_kind
  ),
  constraint evidence_dependencies_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint evidence_dependencies_source_room_story_fk foreign key (
    room_id,
    story_id,
    source_evidence_id
  ) references app_private.evidence (room_id, story_id, id) on delete restrict,
  constraint evidence_dependencies_target_room_story_fk foreign key (
    room_id,
    story_id,
    target_evidence_id
  ) references app_private.evidence (room_id, story_id, id) on delete restrict,
  constraint evidence_dependencies_distinct_nodes check (
    source_evidence_id <> target_evidence_id
  )
);

create table app_private.consequence_specs (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  severity smallint not null,
  consequence_json jsonb not null,
  eligibility_rule_json jsonb not null,
  constraint consequence_specs_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint consequence_specs_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint consequence_specs_severity_range check (severity between 1 and 3),
  constraint consequence_specs_json_objects check (
    pg_catalog.jsonb_typeof(consequence_json) = 'object'
    and pg_catalog.jsonb_typeof(eligibility_rule_json) = 'object'
  )
);

create table app_private.mission_specs (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  round_id uuid not null,
  assigned_player_id uuid not null,
  action_kind app_private.mission_action_kind not null,
  objective_text text not null,
  completion_rule_json jsonb not null,
  stakes_text text not null,
  host_confirmation_guidance text not null,
  success_effect_json jsonb,
  failure_consequence_id uuid,
  constraint mission_specs_room_story_id_unique unique (room_id, story_id, id),
  constraint mission_specs_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint mission_specs_round_room_story_fk foreign key (
    room_id,
    story_id,
    round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint mission_specs_player_room_fk foreign key (room_id, assigned_player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint mission_specs_consequence_room_story_fk foreign key (
    room_id,
    story_id,
    failure_consequence_id
  ) references app_private.consequence_specs (room_id, story_id, id) on delete restrict,
  constraint mission_specs_text_present check (
    pg_catalog.char_length(pg_catalog.btrim(objective_text)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(stakes_text)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(host_confirmation_guidance)) > 0
  ),
  constraint mission_specs_rule_object check (
    pg_catalog.jsonb_typeof(completion_rule_json) = 'object'
  ),
  constraint mission_specs_success_effect_object check (
    success_effect_json is null
    or pg_catalog.jsonb_typeof(success_effect_json) = 'object'
  )
);

create table app_private.intervention_specs (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  round_id uuid not null,
  strength smallint not null,
  candidate_kind app_private.intervention_candidate_kind not null,
  canonical_effect_json jsonb not null,
  presentation_json jsonb not null,
  eligibility_rule_json jsonb not null,
  constraint intervention_specs_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint intervention_specs_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint intervention_specs_round_room_story_fk foreign key (
    room_id,
    story_id,
    round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint intervention_specs_strength_range check (strength between 1 and 3),
  constraint intervention_specs_json_objects check (
    pg_catalog.jsonb_typeof(canonical_effect_json) = 'object'
    and pg_catalog.jsonb_typeof(presentation_json) = 'object'
    and pg_catalog.jsonb_typeof(eligibility_rule_json) = 'object'
  )
);

create table app_private.accomplice_revelations (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  accomplice_player_id uuid not null,
  round_id uuid not null,
  revelation_json jsonb not null,
  constraint accomplice_revelations_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint accomplice_revelations_story_player_unique unique (
    story_id,
    accomplice_player_id
  ),
  constraint accomplice_revelations_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint accomplice_revelations_player_room_fk foreign key (
    room_id,
    accomplice_player_id
  ) references app_private.players (room_id, id) on delete restrict,
  constraint accomplice_revelations_round_room_story_fk foreign key (
    room_id,
    story_id,
    round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint accomplice_revelations_content_object check (
    pg_catalog.jsonb_typeof(revelation_json) = 'object'
  )
);

create table app_private.final_reveal_sections (
  id uuid primary key,
  room_id uuid not null,
  story_id uuid not null,
  sequence smallint not null,
  section_kind text not null,
  section_json jsonb not null,
  constraint final_reveal_sections_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint final_reveal_sections_story_sequence_unique unique (
    story_id,
    sequence
  ),
  constraint final_reveal_sections_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint final_reveal_sections_sequence_positive check (sequence > 0),
  constraint final_reveal_sections_kind_present check (
    pg_catalog.char_length(pg_catalog.btrim(section_kind)) > 0
  ),
  constraint final_reveal_sections_content_object check (
    pg_catalog.jsonb_typeof(section_json) = 'object'
  )
);

alter table app_private.rooms
  add constraint rooms_story_room_fk foreign key (id, story_id)
  references app_private.canonical_stories (room_id, id)
  deferrable initially deferred;

alter table app_private.rooms
  add constraint rooms_current_round_story_fk foreign key (
    id,
    story_id,
    current_round_id
  ) references app_private.story_rounds (room_id, story_id, id)
  deferrable initially deferred;

create index story_rounds_story_sequence_idx
  on app_private.story_rounds (story_id, sequence);
create index dossiers_story_player_idx
  on app_private.dossiers (story_id, player_id);
create index evidence_story_round_idx
  on app_private.evidence (story_id, round_id);
create index mission_specs_story_round_player_idx
  on app_private.mission_specs (story_id, round_id, assigned_player_id);
create index intervention_specs_story_round_strength_idx
  on app_private.intervention_specs (story_id, round_id, strength);

comment on table app_private.story_generation_jobs is
  'Durable, resumable generation attempts and private intermediate artifacts.';
comment on table app_private.canonical_stories is
  'One validated canonical StoryPackage audit artifact per room.';
comment on table app_private.canonical_solutions is
  'NPC victim and canonical truth, visible only through authorized projections.';
