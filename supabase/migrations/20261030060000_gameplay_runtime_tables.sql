-- DB-06: mutable gameplay state derived from an immutable canonical story.

create type app_private.runtime_resolution_status as enum (
  'PENDING',
  'RELEASED',
  'WAIVED'
);

create type app_private.intervention_request_status as enum (
  'REQUESTED',
  'PREVIEW_READY',
  'REJECTED',
  'RELEASED',
  'FAILED'
);

create type app_private.intervention_selection_source as enum (
  'LIVE_AI',
  'PREPARED_FALLBACK'
);

create type app_private.revelation_status as enum (
  'PENDING',
  'RELEASED'
);

create type app_private.runtime_effect_kind as enum (
  'EVIDENCE_RELEASE',
  'CONSEQUENCE_RELEASE',
  'MISSION_ACTIVATION',
  'ACCOMPLICE_REVELATION',
  'DIRECTED_QUESTION'
);

create table app_private.mission_states (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  mission_spec_id uuid not null,
  status app_private.mission_status not null default 'ASSIGNED',
  revision bigint not null default 0,
  deadline_at timestamp with time zone,
  accepted_at timestamp with time zone,
  completion_requested_at timestamp with time zone,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint mission_states_room_story_id_unique unique (room_id, story_id, id),
  constraint mission_states_story_mission_unique unique (story_id, mission_spec_id),
  constraint mission_states_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint mission_states_spec_room_story_fk foreign key (
    room_id,
    story_id,
    mission_spec_id
  ) references app_private.mission_specs (room_id, story_id, id) on delete restrict,
  constraint mission_states_revision_nonnegative check (revision >= 0),
  constraint mission_states_times_ordered check (
    updated_at >= created_at
    and (accepted_at is null or accepted_at >= created_at)
    and (
      completion_requested_at is null
      or completion_requested_at >= coalesce(accepted_at, created_at)
    )
    and (
      resolved_at is null
      or resolved_at >= coalesce(
        completion_requested_at,
        accepted_at,
        created_at
      )
    )
  ),
  constraint mission_states_status_timestamps check (
    (
      status = 'ASSIGNED'
      and accepted_at is null
      and completion_requested_at is null
      and resolved_at is null
    )
    or (
      status = 'ACCEPTED'
      and accepted_at is not null
      and completion_requested_at is null
      and resolved_at is null
    )
    or (
      status = 'COMPLETION_REQUESTED'
      and accepted_at is not null
      and completion_requested_at is not null
      and resolved_at is null
    )
    or (
      status in (
        'COMPLETED',
        'FAILED',
        'CONSEQUENCE_PENDING',
        'CONSEQUENCE_RELEASED',
        'WAIVED'
      )
      and resolved_at is not null
    )
  )
);

create table app_private.evidence_releases (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  evidence_id uuid not null,
  released_in_round_id uuid,
  release_reason text not null,
  command_receipt_id uuid not null,
  released_at timestamp with time zone not null default app_private.current_database_time(),
  constraint evidence_releases_room_story_id_unique unique (room_id, story_id, id),
  constraint evidence_releases_story_evidence_unique unique (story_id, evidence_id),
  constraint evidence_releases_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint evidence_releases_evidence_room_story_fk foreign key (
    room_id,
    story_id,
    evidence_id
  ) references app_private.evidence (room_id, story_id, id) on delete restrict,
  constraint evidence_releases_round_room_story_fk foreign key (
    room_id,
    story_id,
    released_in_round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint evidence_releases_command_room_fk foreign key (
    room_id,
    command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint evidence_releases_reason_supported check (
    release_reason in (
      'GUARANTEED',
      'MISSION_SUCCESS',
      'CONSEQUENCE',
      'INTERVENTION',
      'STANDALONE'
    )
  )
);

create table app_private.consequence_states (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  consequence_spec_id uuid not null,
  source_mission_state_id uuid,
  status app_private.runtime_resolution_status not null default 'PENDING',
  eligible_by_command_receipt_id uuid not null,
  resolved_by_command_receipt_id uuid,
  eligible_at timestamp with time zone not null default app_private.current_database_time(),
  resolved_at timestamp with time zone,
  constraint consequence_states_room_story_id_unique unique (room_id, story_id, id),
  constraint consequence_states_story_consequence_unique unique (
    story_id,
    consequence_spec_id
  ),
  constraint consequence_states_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint consequence_states_spec_room_story_fk foreign key (
    room_id,
    story_id,
    consequence_spec_id
  ) references app_private.consequence_specs (room_id, story_id, id) on delete restrict,
  constraint consequence_states_mission_room_story_fk foreign key (
    room_id,
    story_id,
    source_mission_state_id
  ) references app_private.mission_states (room_id, story_id, id) on delete restrict,
  constraint consequence_states_eligible_command_room_fk foreign key (
    room_id,
    eligible_by_command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint consequence_states_resolved_command_room_fk foreign key (
    room_id,
    resolved_by_command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint consequence_states_resolution_shape check (
    (
      status = 'PENDING'
      and resolved_by_command_receipt_id is null
      and resolved_at is null
    )
    or (
      status in ('RELEASED', 'WAIVED')
      and resolved_by_command_receipt_id is not null
      and resolved_at is not null
      and resolved_at >= eligible_at
    )
  )
);

create table app_private.intervention_requests (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  round_id uuid not null,
  requested_state_version bigint not null,
  requested_strength smallint not null,
  status app_private.intervention_request_status not null default 'REQUESTED',
  request_command_receipt_id uuid not null,
  revision bigint not null default 0,
  failure_code text,
  requested_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint intervention_requests_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint intervention_requests_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint intervention_requests_round_room_story_fk foreign key (
    room_id,
    story_id,
    round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint intervention_requests_command_room_fk foreign key (
    room_id,
    request_command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint intervention_requests_version_nonnegative check (
    requested_state_version >= 0 and revision >= 0
  ),
  constraint intervention_requests_strength_range check (
    requested_strength between 1 and 3
  ),
  constraint intervention_requests_failure_shape check (
    (
      status = 'FAILED'
      and failure_code is not null
      and pg_catalog.char_length(pg_catalog.btrim(failure_code)) between 1 and 100
    )
    or (status <> 'FAILED' and failure_code is null)
  ),
  constraint intervention_requests_times_ordered check (updated_at >= requested_at)
);

create table app_private.intervention_previews (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  request_id uuid not null,
  candidate_kind app_private.intervention_candidate_kind not null,
  intervention_spec_id uuid,
  evidence_id uuid,
  consequence_spec_id uuid,
  mission_spec_id uuid,
  target_player_id uuid,
  selection_source app_private.intervention_selection_source not null,
  model_id text,
  provider_response_id text,
  presentation_style text not null,
  reason_code text not null,
  audience_json jsonb not null,
  preview_json jsonb not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint intervention_previews_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint intervention_previews_room_story_request_id_unique unique (
    room_id,
    story_id,
    request_id,
    id
  ),
  constraint intervention_previews_request_unique unique (request_id),
  constraint intervention_previews_request_room_story_fk foreign key (
    room_id,
    story_id,
    request_id
  ) references app_private.intervention_requests (room_id, story_id, id)
    on delete cascade,
  constraint intervention_previews_spec_room_story_fk foreign key (
    room_id,
    story_id,
    intervention_spec_id
  ) references app_private.intervention_specs (room_id, story_id, id) on delete restrict,
  constraint intervention_previews_evidence_room_story_fk foreign key (
    room_id,
    story_id,
    evidence_id
  ) references app_private.evidence (room_id, story_id, id) on delete restrict,
  constraint intervention_previews_consequence_room_story_fk foreign key (
    room_id,
    story_id,
    consequence_spec_id
  ) references app_private.consequence_specs (room_id, story_id, id) on delete restrict,
  constraint intervention_previews_mission_room_story_fk foreign key (
    room_id,
    story_id,
    mission_spec_id
  ) references app_private.mission_specs (room_id, story_id, id) on delete restrict,
  constraint intervention_previews_player_room_fk foreign key (
    room_id,
    target_player_id
  ) references app_private.players (room_id, id) on delete restrict,
  constraint intervention_previews_candidate_shape check (
    (
      candidate_kind = 'DIRECTED_QUESTION'
      and intervention_spec_id is not null
      and evidence_id is null
      and consequence_spec_id is null
      and mission_spec_id is null
    )
    or (
      candidate_kind = 'RELEASE_EVIDENCE'
      and intervention_spec_id is null
      and evidence_id is not null
      and consequence_spec_id is null
      and mission_spec_id is null
    )
    or (
      candidate_kind = 'RELEASE_CONSEQUENCE'
      and intervention_spec_id is null
      and evidence_id is null
      and consequence_spec_id is not null
      and mission_spec_id is null
    )
    or (
      candidate_kind = 'ACTIVATE_MISSION'
      and intervention_spec_id is null
      and evidence_id is null
      and consequence_spec_id is null
      and mission_spec_id is not null
    )
  ),
  constraint intervention_previews_selection_shape check (
    (
      selection_source = 'LIVE_AI'
      and model_id is not null
      and provider_response_id is not null
    )
    or (
      selection_source = 'PREPARED_FALLBACK'
      and model_id is null
      and provider_response_id is null
    )
  ),
  constraint intervention_previews_text_present check (
    pg_catalog.char_length(pg_catalog.btrim(presentation_style)) between 1 and 50
    and pg_catalog.char_length(pg_catalog.btrim(reason_code)) between 1 and 100
  ),
  constraint intervention_previews_json_objects check (
    pg_catalog.jsonb_typeof(audience_json) = 'object'
    and pg_catalog.jsonb_typeof(preview_json) = 'object'
  )
);

create table app_private.intervention_releases (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  request_id uuid not null,
  preview_id uuid not null,
  command_receipt_id uuid not null,
  released_at timestamp with time zone not null default app_private.current_database_time(),
  constraint intervention_releases_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint intervention_releases_request_unique unique (request_id),
  constraint intervention_releases_preview_unique unique (preview_id),
  constraint intervention_releases_request_room_story_fk foreign key (
    room_id,
    story_id,
    request_id
  ) references app_private.intervention_requests (room_id, story_id, id)
    on delete restrict,
  constraint intervention_releases_preview_room_story_fk foreign key (
    room_id,
    story_id,
    request_id,
    preview_id
  ) references app_private.intervention_previews (
    room_id,
    story_id,
    request_id,
    id
  )
    on delete restrict,
  constraint intervention_releases_command_room_fk foreign key (
    room_id,
    command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict
);

create table app_private.accomplice_revelation_states (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  revelation_spec_id uuid not null,
  status app_private.revelation_status not null default 'PENDING',
  released_by_command_receipt_id uuid,
  released_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint accomplice_revelation_states_room_story_id_unique unique (
    room_id,
    story_id,
    id
  ),
  constraint accomplice_revelation_states_story_spec_unique unique (
    story_id,
    revelation_spec_id
  ),
  constraint accomplice_revelation_states_story_room_fk foreign key (
    room_id,
    story_id
  ) references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint accomplice_revelation_states_spec_room_story_fk foreign key (
    room_id,
    story_id,
    revelation_spec_id
  ) references app_private.accomplice_revelations (room_id, story_id, id)
    on delete restrict,
  constraint accomplice_revelation_states_command_room_fk foreign key (
    room_id,
    released_by_command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint accomplice_revelation_states_release_shape check (
    (
      status = 'PENDING'
      and released_by_command_receipt_id is null
      and released_at is null
    )
    or (
      status = 'RELEASED'
      and released_by_command_receipt_id is not null
      and released_at is not null
      and released_at >= created_at
    )
  )
);

create table app_private.runtime_effects (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  effect_kind app_private.runtime_effect_kind not null,
  source_intervention_request_id uuid,
  target_evidence_id uuid,
  target_consequence_spec_id uuid,
  target_mission_spec_id uuid,
  target_revelation_spec_id uuid,
  target_intervention_spec_id uuid,
  command_receipt_id uuid not null,
  applied_at timestamp with time zone not null default app_private.current_database_time(),
  constraint runtime_effects_room_story_id_unique unique (room_id, story_id, id),
  constraint runtime_effects_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint runtime_effects_request_room_story_fk foreign key (
    room_id,
    story_id,
    source_intervention_request_id
  ) references app_private.intervention_requests (room_id, story_id, id)
    on delete restrict,
  constraint runtime_effects_evidence_room_story_fk foreign key (
    room_id,
    story_id,
    target_evidence_id
  ) references app_private.evidence (room_id, story_id, id) on delete restrict,
  constraint runtime_effects_consequence_room_story_fk foreign key (
    room_id,
    story_id,
    target_consequence_spec_id
  ) references app_private.consequence_specs (room_id, story_id, id) on delete restrict,
  constraint runtime_effects_mission_room_story_fk foreign key (
    room_id,
    story_id,
    target_mission_spec_id
  ) references app_private.mission_specs (room_id, story_id, id) on delete restrict,
  constraint runtime_effects_revelation_room_story_fk foreign key (
    room_id,
    story_id,
    target_revelation_spec_id
  ) references app_private.accomplice_revelations (room_id, story_id, id)
    on delete restrict,
  constraint runtime_effects_intervention_room_story_fk foreign key (
    room_id,
    story_id,
    target_intervention_spec_id
  ) references app_private.intervention_specs (room_id, story_id, id)
    on delete restrict,
  constraint runtime_effects_command_room_fk foreign key (
    room_id,
    command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint runtime_effects_target_shape check (
    (
      effect_kind = 'EVIDENCE_RELEASE'
      and target_evidence_id is not null
      and target_consequence_spec_id is null
      and target_mission_spec_id is null
      and target_revelation_spec_id is null
      and target_intervention_spec_id is null
    )
    or (
      effect_kind = 'CONSEQUENCE_RELEASE'
      and target_evidence_id is null
      and target_consequence_spec_id is not null
      and target_mission_spec_id is null
      and target_revelation_spec_id is null
      and target_intervention_spec_id is null
    )
    or (
      effect_kind = 'MISSION_ACTIVATION'
      and target_evidence_id is null
      and target_consequence_spec_id is null
      and target_mission_spec_id is not null
      and target_revelation_spec_id is null
      and target_intervention_spec_id is null
    )
    or (
      effect_kind = 'ACCOMPLICE_REVELATION'
      and target_evidence_id is null
      and target_consequence_spec_id is null
      and target_mission_spec_id is null
      and target_revelation_spec_id is not null
      and target_intervention_spec_id is null
    )
    or (
      effect_kind = 'DIRECTED_QUESTION'
      and target_evidence_id is null
      and target_consequence_spec_id is null
      and target_mission_spec_id is null
      and target_revelation_spec_id is null
      and target_intervention_spec_id is not null
    )
  )
);

create unique index runtime_effects_once_evidence_idx
  on app_private.runtime_effects (story_id, target_evidence_id)
  where effect_kind = 'EVIDENCE_RELEASE';
create unique index runtime_effects_once_consequence_idx
  on app_private.runtime_effects (story_id, target_consequence_spec_id)
  where effect_kind = 'CONSEQUENCE_RELEASE';
create unique index runtime_effects_once_mission_idx
  on app_private.runtime_effects (story_id, target_mission_spec_id)
  where effect_kind = 'MISSION_ACTIVATION';
create unique index runtime_effects_once_revelation_idx
  on app_private.runtime_effects (story_id, target_revelation_spec_id)
  where effect_kind = 'ACCOMPLICE_REVELATION';
create unique index runtime_effects_once_question_idx
  on app_private.runtime_effects (story_id, target_intervention_spec_id)
  where effect_kind = 'DIRECTED_QUESTION';

create index mission_states_room_status_idx
  on app_private.mission_states (room_id, status, updated_at desc);
create index consequence_states_room_status_idx
  on app_private.consequence_states (room_id, status, eligible_at);
create index intervention_requests_room_round_status_idx
  on app_private.intervention_requests (room_id, round_id, status, requested_at);
create index accomplice_revelation_states_room_status_idx
  on app_private.accomplice_revelation_states (room_id, status);

create function app_private.enforce_mission_state_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'ASSIGNED' or new.revision <> 0 then
      raise exception using
        errcode = '23514',
        message = 'mission runtime state must begin assigned at revision zero',
        constraint = 'mission_states_initial_state';
    end if;

    return new;
  end if;

  if (new.room_id, new.story_id, new.mission_spec_id) is distinct from
    (old.room_id, old.story_id, old.mission_spec_id) then
    raise exception using
      errcode = '23514',
      message = 'mission runtime identity is immutable',
      constraint = 'mission_states_identity_immutable';
  end if;

  if new.revision <> old.revision + 1 then
    raise exception using
      errcode = '23514',
      message = 'mission runtime revision must increment by one',
      constraint = 'mission_states_revision_sequence';
  end if;

  if new.status = old.status then
    if old.status not in ('ASSIGNED', 'ACCEPTED', 'COMPLETION_REQUESTED')
      or new.deadline_at is not distinct from old.deadline_at then
      raise exception using
        errcode = '23514',
        message = 'only an active mission deadline may be extended in place',
        constraint = 'mission_states_valid_transition';
    end if;

    return new;
  end if;

  if not (
    (old.status = 'ASSIGNED' and new.status in ('ACCEPTED', 'FAILED', 'WAIVED'))
    or (
      old.status = 'ACCEPTED'
      and new.status in ('COMPLETION_REQUESTED', 'FAILED', 'WAIVED')
    )
    or (
      old.status = 'COMPLETION_REQUESTED'
      and new.status in ('ACCEPTED', 'COMPLETED', 'FAILED', 'WAIVED')
    )
    or (old.status = 'FAILED' and new.status = 'CONSEQUENCE_PENDING')
    or (
      old.status = 'CONSEQUENCE_PENDING'
      and new.status in ('CONSEQUENCE_RELEASED', 'WAIVED')
    )
  ) then
    raise exception using
      errcode = '23514',
      message = 'invalid mission runtime transition',
      constraint = 'mission_states_valid_transition';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_consequence_state_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'PENDING' then
      raise exception using
        errcode = '23514',
        message = 'consequence runtime state must begin pending',
        constraint = 'consequence_states_initial_state';
    end if;

    return new;
  end if;

  if (
    new.room_id,
    new.story_id,
    new.consequence_spec_id,
    new.source_mission_state_id,
    new.eligible_by_command_receipt_id,
    new.eligible_at
  ) is distinct from (
    old.room_id,
    old.story_id,
    old.consequence_spec_id,
    old.source_mission_state_id,
    old.eligible_by_command_receipt_id,
    old.eligible_at
  ) then
    raise exception using
      errcode = '23514',
      message = 'consequence eligibility identity is immutable',
      constraint = 'consequence_states_identity_immutable';
  end if;

  if old.status <> 'PENDING' or new.status not in ('RELEASED', 'WAIVED') then
    raise exception using
      errcode = '23514',
      message = 'invalid consequence runtime transition',
      constraint = 'consequence_states_valid_transition';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_intervention_request_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'REQUESTED' or new.revision <> 0 then
      raise exception using
        errcode = '23514',
        message = 'intervention request must begin requested at revision zero',
        constraint = 'intervention_requests_initial_state';
    end if;

    return new;
  end if;

  if (
    new.room_id,
    new.story_id,
    new.round_id,
    new.requested_state_version,
    new.requested_strength,
    new.request_command_receipt_id,
    new.requested_at
  ) is distinct from (
    old.room_id,
    old.story_id,
    old.round_id,
    old.requested_state_version,
    old.requested_strength,
    old.request_command_receipt_id,
    old.requested_at
  ) then
    raise exception using
      errcode = '23514',
      message = 'intervention request identity is immutable',
      constraint = 'intervention_requests_identity_immutable';
  end if;

  if new.revision <> old.revision + 1 then
    raise exception using
      errcode = '23514',
      message = 'intervention request revision must increment by one',
      constraint = 'intervention_requests_revision_sequence';
  end if;

  if not (
    (
      old.status = 'REQUESTED'
      and new.status in ('PREVIEW_READY', 'FAILED')
    )
    or (
      old.status = 'PREVIEW_READY'
      and new.status in ('REJECTED', 'RELEASED')
    )
  ) then
    raise exception using
      errcode = '23514',
      message = 'invalid intervention request transition',
      constraint = 'intervention_requests_valid_transition';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_revelation_state_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'PENDING' then
      raise exception using
        errcode = '23514',
        message = 'accomplice revelation must begin pending',
        constraint = 'accomplice_revelation_states_initial_state';
    end if;

    return new;
  end if;

  if (new.room_id, new.story_id, new.revelation_spec_id) is distinct from
    (old.room_id, old.story_id, old.revelation_spec_id)
    or old.status <> 'PENDING'
    or new.status <> 'RELEASED' then
    raise exception using
      errcode = '23514',
      message = 'invalid accomplice revelation transition',
      constraint = 'accomplice_revelation_states_valid_transition';
  end if;

  return new;
end;
$function$;

create trigger mission_states_enforce_transition
before insert or update on app_private.mission_states
for each row execute function app_private.enforce_mission_state_transition();

create trigger consequence_states_enforce_transition
before insert or update on app_private.consequence_states
for each row execute function app_private.enforce_consequence_state_transition();

create trigger intervention_requests_enforce_transition
before insert or update on app_private.intervention_requests
for each row execute function app_private.enforce_intervention_request_transition();

create trigger accomplice_revelation_states_enforce_transition
before insert or update on app_private.accomplice_revelation_states
for each row execute function app_private.enforce_revelation_state_transition();

create trigger evidence_releases_immutable
before update or delete on app_private.evidence_releases
for each row execute function app_private.enforce_room_record_immutable();

create trigger intervention_previews_immutable
before update or delete on app_private.intervention_previews
for each row execute function app_private.enforce_room_record_immutable();

create trigger intervention_releases_immutable
before update or delete on app_private.intervention_releases
for each row execute function app_private.enforce_room_record_immutable();

create trigger runtime_effects_immutable
before update or delete on app_private.runtime_effects
for each row execute function app_private.enforce_room_record_immutable();

revoke all on function app_private.enforce_mission_state_transition()
  from public, anon, authenticated;
revoke all on function app_private.enforce_consequence_state_transition()
  from public, anon, authenticated;
revoke all on function app_private.enforce_intervention_request_transition()
  from public, anon, authenticated;
revoke all on function app_private.enforce_revelation_state_transition()
  from public, anon, authenticated;

comment on table app_private.mission_states is
  'Validated mutable progress for immutable mission specifications.';
comment on table app_private.intervention_previews is
  'Immutable Game Master preview bound to exactly one canonical candidate.';
comment on table app_private.runtime_effects is
  'Typed, canonical, once-only effects applied during gameplay.';
