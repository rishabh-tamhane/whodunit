-- INT: bounded context-aware suggestions over canonical, pre-generated content.

alter table app_private.intervention_requests
  add column provider_input_tokens integer not null default 0,
  add column provider_output_tokens integer not null default 0,
  add column provider_latency_ms integer not null default 0,
  add constraint intervention_requests_provider_metrics_nonnegative check (
    provider_input_tokens >= 0
    and provider_output_tokens >= 0
    and provider_latency_ms >= 0
  );

alter table app_private.intervention_previews
  drop constraint intervention_previews_candidate_shape,
  add constraint intervention_previews_candidate_shape check (
    (
      candidate_kind = 'DIRECTED_QUESTION'
      and intervention_spec_id is not null
      and evidence_id is null
      and consequence_spec_id is null
      and mission_spec_id is null
    )
    or (
      candidate_kind = 'RELEASE_EVIDENCE'
      and evidence_id is not null
      and consequence_spec_id is null
      and mission_spec_id is null
    )
    or (
      candidate_kind = 'RELEASE_CONSEQUENCE'
      and evidence_id is null
      and consequence_spec_id is not null
      and mission_spec_id is null
    )
    or (
      candidate_kind = 'ACTIVATE_MISSION'
      and evidence_id is null
      and consequence_spec_id is null
      and mission_spec_id is not null
    )
  );

create function app_private.intervention_candidates(
  target_room_id uuid,
  target_round_id uuid,
  requested_strength integer
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with prepared as (
    select
      0 as priority,
      spec.id as candidate_id,
      spec.id as source_spec_id,
      spec.candidate_kind::text as candidate_kind,
      spec.strength,
      spec.canonical_effect_json as effect,
      spec.presentation_json ->> 'text' as presentation,
      case spec.candidate_kind
        when 'RELEASE_EVIDENCE' then evidence.audience_json
        when 'ACTIVATE_MISSION' then pg_catalog.jsonb_build_object(
          'kind', 'PLAYERS',
          'playerIds', pg_catalog.jsonb_build_array(mission.assigned_player_id::text)
        )
        else pg_catalog.jsonb_build_object('kind', 'PUBLIC')
      end as audience,
      case spec.candidate_kind
        when 'RELEASE_EVIDENCE' then evidence.id
        when 'RELEASE_CONSEQUENCE' then consequence.id
        when 'ACTIVATE_MISSION' then mission.id
        else spec.id
      end as target_id,
      mission.assigned_player_id as canonical_target_player_id
    from app_private.intervention_specs as spec
    join app_private.rooms as room on room.id = spec.room_id
    left join app_private.evidence as evidence
      on evidence.room_id = spec.room_id
      and evidence.id = nullif(spec.canonical_effect_json ->> 'evidenceId', '')::uuid
    left join app_private.consequence_specs as consequence
      on consequence.room_id = spec.room_id
      and consequence.id = nullif(spec.canonical_effect_json ->> 'consequenceId', '')::uuid
    left join app_private.mission_specs as mission
      on mission.room_id = spec.room_id
      and mission.id = nullif(spec.canonical_effect_json ->> 'missionId', '')::uuid
    left join app_private.consequence_states as consequence_state
      on consequence_state.room_id = spec.room_id
      and consequence_state.consequence_spec_id = consequence.id
    left join app_private.mission_states as mission_state
      on mission_state.room_id = spec.room_id
      and mission_state.mission_spec_id = mission.id
    where spec.room_id = target_room_id
      and spec.round_id = target_round_id
      and spec.strength <= requested_strength
      and app_private.current_database_time() >= coalesce((
        select pg_catalog.max(event.occurred_at)
        from app_private.game_events as event
        where event.room_id = target_room_id
          and event.source_object_id = target_round_id
          and event.event_type in ('GAME_STARTED', 'ROUND_ADVANCED')
      ), room.started_at, room.updated_at) + pg_catalog.make_interval(
        secs => coalesce((spec.eligibility_rule_json ->> 'eligibleAfterSeconds')::integer, 0)
      )
      and not exists (
        select 1
        from app_private.intervention_releases as release
        join app_private.intervention_previews as preview
          on preview.room_id = release.room_id and preview.id = release.preview_id
        where release.room_id = target_room_id
          and preview.intervention_spec_id = spec.id
      )
      and (
        spec.candidate_kind = 'DIRECTED_QUESTION'
        or (
          spec.candidate_kind = 'RELEASE_EVIDENCE'
          and evidence.id is not null
          and not exists (
            select 1 from app_private.evidence_releases as released
            where released.room_id = target_room_id
              and released.evidence_id = evidence.id
          )
          and not exists (
            select 1 from app_private.evidence_dependencies as dependency
            where dependency.room_id = target_room_id
              and dependency.target_evidence_id = evidence.id
              and dependency.dependency_kind = 'REQUIRES'
              and not exists (
                select 1 from app_private.evidence_releases as released
                where released.room_id = target_room_id
                  and released.evidence_id = dependency.source_evidence_id
              )
          )
        )
        or (
          spec.candidate_kind = 'RELEASE_CONSEQUENCE'
          and consequence_state.status = 'PENDING'
        )
        or (
          spec.candidate_kind = 'ACTIVATE_MISSION'
          and mission.round_id = target_round_id
          and mission_state.status = 'ASSIGNED'
          and not exists (
            select 1 from app_private.runtime_effects as effect
            where effect.room_id = target_room_id
              and effect.effect_kind = 'MISSION_ACTIVATION'
              and effect.target_mission_spec_id = mission.id
          )
        )
      )
  ), manual_evidence as (
    select
      1 as priority,
      evidence.id as candidate_id,
      null::uuid as source_spec_id,
      'RELEASE_EVIDENCE'::text as candidate_kind,
      1::smallint as strength,
      pg_catalog.jsonb_build_object(
        'kind', 'RELEASE_EVIDENCE', 'evidenceId', evidence.id
      ) as effect,
      pg_catalog.concat(
        'Reveal evidence: ', evidence.content_json ->> 'title', ' — ',
        evidence.content_json ->> 'description'
      ) as presentation,
      evidence.audience_json as audience,
      evidence.id as target_id,
      null::uuid as canonical_target_player_id
    from app_private.evidence as evidence
    join app_private.story_rounds as earliest
      on earliest.room_id = evidence.room_id
      and earliest.id = (evidence.release_rule_json ->> 'earliestRoundId')::uuid
    join app_private.story_rounds as current_round
      on current_round.room_id = evidence.room_id
      and current_round.id = target_round_id
    where evidence.room_id = target_room_id
      and evidence.release_rule_json ->> 'kind' = 'GAME_MASTER_MANUAL'
      and current_round.sequence >= earliest.sequence
      and not exists (
        select 1 from app_private.evidence_releases as released
        where released.room_id = target_room_id
          and released.evidence_id = evidence.id
      )
      and not exists (
        select 1 from app_private.evidence_dependencies as dependency
        where dependency.room_id = target_room_id
          and dependency.target_evidence_id = evidence.id
          and dependency.dependency_kind = 'REQUIRES'
          and not exists (
            select 1 from app_private.evidence_releases as released
            where released.room_id = target_room_id
              and released.evidence_id = dependency.source_evidence_id
          )
      )
  ), candidates as (
    select * from prepared
    union all
    select * from manual_evidence
  )
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'candidateId', candidate_id,
      'sourceSpecId', source_spec_id,
      'kind', candidate_kind,
      'strength', strength,
      'effect', effect,
      'canonicalPresentation', presentation,
      'audience', audience,
      'targetId', target_id,
      'canonicalTargetPlayerId', canonical_target_player_id
    )) order by priority, strength desc, candidate_id
  ), '[]'::jsonb)
  from candidates;
$function$;

create function public.request_intervention(
  target_room_id uuid,
  expected_state_version bigint,
  idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  request_id uuid := pg_catalog.gen_random_uuid();
  receipt_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  released_count integer;
  request_count integer;
  round_cap integer;
  strength integer;
  candidates jsonb;
  context jsonb;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash('REQUEST_INTERVENTION','{}'::jsonb);
  replay := app_private.command_replay(target_room_id,idempotency_key,'REQUEST_INTERVENTION',request_hash);
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room
  where room.id=target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode='40001',message='stale room state version';
  end if;
  if room_record.status <> 'IN_PROGRESS' or room_record.current_round_id is null then
    raise exception using errcode='55000',message='interventions require active play';
  end if;
  select (profile.profile_json ->> 'interventionCapPerRound')::integer
  into strict round_cap from app_private.duration_profiles as profile
  where profile.profile_version=room_record.duration_profile_version
    and profile.duration_minutes=room_record.duration_minutes;
  select pg_catalog.count(*)::integer into released_count
  from app_private.intervention_releases as release
  join app_private.intervention_requests as request
    on request.room_id=release.room_id and request.id=release.request_id
  where release.room_id=target_room_id
    and request.round_id=room_record.current_round_id;
  select pg_catalog.count(*)::integer into request_count
  from app_private.intervention_requests as request
  where request.room_id=target_room_id
    and request.round_id=room_record.current_round_id;
  if released_count >= round_cap then
    raise exception using errcode='54000',message='round intervention limit reached';
  end if;
  if request_count >= round_cap * 3 then
    raise exception using errcode='54000',message='round intervention retry budget reached';
  end if;
  strength := least(released_count + 1, 3);
  candidates := app_private.intervention_candidates(
    target_room_id,room_record.current_round_id,strength
  );
  if pg_catalog.jsonb_array_length(candidates)=0 then
    raise exception using errcode='55000',message='no eligible intervention available';
  end if;
  context := pg_catalog.jsonb_build_object(
    'storyId',room_record.story_id,
    'roomStateVersion',room_record.state_version,
    'roundId',room_record.current_round_id,
    'requestedStrength',strength,
    'candidates',candidates,
    'releasedEvidenceIds',coalesce((
      select pg_catalog.jsonb_agg(release.evidence_id order by release.released_at)
      from app_private.evidence_releases as release
      where release.room_id=target_room_id
    ),'[]'::jsonb),
    'missionOutcomes',coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'missionId',state.mission_spec_id,'status',state.status::text
      ) order by state.mission_spec_id)
      from app_private.mission_states as state
      where state.room_id=target_room_id
    ),'[]'::jsonb),
    'priorInterventions',coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'kind',preview.candidate_kind::text,
        'strength',request.requested_strength
      ) order by release.released_at)
      from app_private.intervention_releases as release
      join app_private.intervention_requests as request
        on request.room_id=release.room_id and request.id=release.request_id
      join app_private.intervention_previews as preview
        on preview.room_id=release.room_id and preview.id=release.preview_id
      where release.room_id=target_room_id
    ),'[]'::jsonb),
    'aggregateSuspicions',coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'suspectPlayerId',aggregate.suspect_player_id,
        'suspectedRole',aggregate.suspected_role::text,
        'submissionCount',aggregate.submission_count
      ) order by aggregate.submission_count desc,aggregate.suspect_player_id)
      from (
        select suspect.suspect_player_id,suspect.suspected_role,
          pg_catalog.count(*)::integer as submission_count
        from app_private.player_theory_suspects as suspect
        where suspect.room_id=target_room_id
        group by suspect.suspect_player_id,suspect.suspected_role
      ) as aggregate
    ),'[]'::jsonb),
    'permittedTargetPlayerIds',coalesce((
      select pg_catalog.jsonb_agg(player.id order by player.seat_order)
      from app_private.players as player where player.room_id=target_room_id
    ),'[]'::jsonb)
  );
  next_version:=room_record.state_version+1;
  result:=pg_catalog.jsonb_build_object(
    'requestId',request_id,'status','REQUESTED','strength',strength,
    'roundCap',round_cap,'stateVersion',next_version::text,
    'context',context,'replayed',false
  );
  perform app_private.record_command(
    receipt_id,target_room_id,idempotency_key,'REQUEST_INTERVENTION',
    'GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,
    next_version,result,'INTERVENTION_REQUESTED',request_id,'GAMEPLAY_CHANGED'
  );
  insert into app_private.intervention_requests (
    id,room_id,story_id,round_id,requested_state_version,
    requested_strength,request_command_receipt_id
  ) values (
    request_id,target_room_id,room_record.story_id,room_record.current_round_id,
    expected_state_version,strength,receipt_id
  );
  update app_private.rooms set state_version=next_version,
    updated_at=app_private.current_database_time() where id=target_room_id;
  return result;
end;
$function$;

create function public.stage_intervention_preview(
  target_room_id uuid,
  target_request_id uuid,
  selected_candidate_id uuid,
  selected_target_player_id uuid,
  presentation_style text,
  reason_code text,
  provider_model_id text,
  provider_response_id text,
  attempt_input_tokens integer,
  attempt_output_tokens integer,
  attempt_latency_ms integer,
  provider_failure_code text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  request_record app_private.intervention_requests%rowtype;
  candidates jsonb;
  candidate jsonb;
  source app_private.intervention_selection_source;
  preview_id uuid := pg_catalog.gen_random_uuid();
  next_version bigint;
  next_sequence bigint;
  target_player uuid;
  candidate_kind app_private.intervention_candidate_kind;
  source_spec_id uuid;
  target_id uuid;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  select room.* into strict room_record from app_private.rooms as room
  where room.id=target_room_id;
  select request.* into strict request_record
  from app_private.intervention_requests as request
  where request.room_id=target_room_id and request.id=target_request_id
  for update;
  if request_record.status='PREVIEW_READY' then
    select pg_catalog.jsonb_build_object(
      'requestId',request_record.id,'previewId',preview.id,
      'status','PREVIEW_READY','selectionSource',preview.selection_source::text,
      'candidateKind',preview.candidate_kind::text,
      'sourceSpecId',preview.intervention_spec_id,
      'effect',preview.preview_json -> 'effect',
      'audience',preview.audience_json,'preview',preview.preview_json,
      'stateVersion',room_record.state_version::text
    ) into result from app_private.intervention_previews as preview
    where preview.request_id=request_record.id;
    return result;
  end if;
  if room_record.status<>'IN_PROGRESS'
    or room_record.current_round_id<>request_record.round_id
    or request_record.status<>'REQUESTED' then
    raise exception using errcode='55000',message='intervention request is no longer active';
  end if;
  candidates:=app_private.intervention_candidates(
    target_room_id,request_record.round_id,request_record.requested_strength
  );
  if selected_candidate_id is not null then
    select value into candidate from pg_catalog.jsonb_array_elements(candidates)
    where (value ->> 'candidateId')::uuid=selected_candidate_id limit 1;
  end if;
  if candidate is not null
    and provider_model_id is not null and provider_response_id is not null
    and provider_failure_code is null then
    source:='LIVE_AI';
  else
    select item.value into candidate
    from pg_catalog.jsonb_array_elements(candidates) with ordinality
      as item(value,position)
    order by item.position limit 1;
    source:='PREPARED_FALLBACK';
  end if;
  if candidate is null then
    update app_private.intervention_requests set status='FAILED',revision=revision+1,
      failure_code='NO_ELIGIBLE_CANDIDATE',updated_at=app_private.current_database_time(),
      provider_input_tokens=greatest(coalesce(attempt_input_tokens,0),0),
      provider_output_tokens=greatest(coalesce(attempt_output_tokens,0),0),
      provider_latency_ms=greatest(coalesce(attempt_latency_ms,0),0)
    where id=request_record.id;
    next_version:=room_record.state_version+1;
    update app_private.rooms set state_version=next_version,
      updated_at=app_private.current_database_time() where id=target_room_id;
    insert into public.room_signals(room_id,state_version,change_type)
    values(target_room_id,next_version,'GAMEPLAY_CHANGED');
    return pg_catalog.jsonb_build_object(
      'requestId',request_record.id,'status','FAILED',
      'failureCode','NO_ELIGIBLE_CANDIDATE','stateVersion',next_version::text
    );
  end if;
  candidate_kind:=(candidate ->> 'kind')::app_private.intervention_candidate_kind;
  source_spec_id:=(candidate ->> 'sourceSpecId')::uuid;
  target_id:=(candidate ->> 'targetId')::uuid;
  if candidate_kind='DIRECTED_QUESTION'
    and selected_target_player_id is not null
    and exists(select 1 from app_private.players as player
      where player.room_id=target_room_id and player.id=selected_target_player_id) then
    target_player:=selected_target_player_id;
  elsif candidate ->> 'canonicalTargetPlayerId' is not null then
    target_player:=(candidate ->> 'canonicalTargetPlayerId')::uuid;
  end if;
  insert into app_private.intervention_previews (
    id,room_id,story_id,request_id,candidate_kind,intervention_spec_id,
    evidence_id,consequence_spec_id,mission_spec_id,target_player_id,
    selection_source,model_id,provider_response_id,presentation_style,
    reason_code,audience_json,preview_json
  ) values (
    preview_id,target_room_id,room_record.story_id,request_record.id,candidate_kind,
    source_spec_id,
    case when candidate_kind='RELEASE_EVIDENCE' then target_id end,
    case when candidate_kind='RELEASE_CONSEQUENCE' then target_id end,
    case when candidate_kind='ACTIVATE_MISSION' then target_id end,
    target_player,source,
    case when source='LIVE_AI' then provider_model_id end,
    case when source='LIVE_AI' then provider_response_id end,
    case when presentation_style in ('GENTLE','DIRECT','URGENT')
      then presentation_style else 'GENTLE' end,
    case when pg_catalog.char_length(coalesce(reason_code,'')) between 1 and 100
      then reason_code else coalesce(provider_failure_code,'PREPARED_FALLBACK') end,
    candidate -> 'audience',
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'text',candidate ->> 'canonicalPresentation',
      'style',case when presentation_style in ('GENTLE','DIRECT','URGENT')
        then presentation_style else 'GENTLE' end,
      'effect',candidate -> 'effect',
      'targetPlayerId',target_player
    ))
  );
  update app_private.intervention_requests set status='PREVIEW_READY',
    revision=revision+1,updated_at=app_private.current_database_time(),
    provider_input_tokens=greatest(coalesce(attempt_input_tokens,0),0),
    provider_output_tokens=greatest(coalesce(attempt_output_tokens,0),0),
    provider_latency_ms=greatest(coalesce(attempt_latency_ms,0),0)
  where id=request_record.id;
  next_version:=room_record.state_version+1;
  select coalesce(pg_catalog.max(event.room_sequence),0)+1 into next_sequence
  from app_private.game_events as event where event.room_id=target_room_id;
  insert into app_private.game_events(
    room_id,room_sequence,state_version,event_type,actor_type,source_object_id
  ) values (
    target_room_id,next_sequence,next_version,'INTERVENTION_PREVIEW_READY',
    'SYSTEM',request_record.id
  );
  update app_private.rooms set state_version=next_version,
    updated_at=app_private.current_database_time() where id=target_room_id;
  insert into public.room_signals(room_id,state_version,change_type)
  values(target_room_id,next_version,'GAMEPLAY_CHANGED');
  return pg_catalog.jsonb_build_object(
    'requestId',request_record.id,'previewId',preview_id,'status','PREVIEW_READY',
    'selectionSource',source::text,'candidateKind',candidate_kind::text,
    'sourceSpecId',source_spec_id,'effect',candidate -> 'effect',
    'audience',candidate -> 'audience',
    'preview',pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'text',candidate ->> 'canonicalPresentation',
      'style',case when presentation_style in ('GENTLE','DIRECT','URGENT')
        then presentation_style else 'GENTLE' end,
      'effect',candidate -> 'effect','targetPlayerId',target_player
    )),
    'stateVersion',next_version::text
  );
end;
$function$;

create function public.resolve_intervention(
  target_room_id uuid,
  target_request_id uuid,
  expected_state_version bigint,
  idempotency_key uuid,
  decision text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  request_record app_private.intervention_requests%rowtype;
  preview_record app_private.intervention_previews%rowtype;
  receipt_id uuid:=pg_catalog.gen_random_uuid();
  release_id uuid:=pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash:=app_private.command_request_hash(
    'RESOLVE_INTERVENTION',pg_catalog.jsonb_build_object(
      'requestId',target_request_id,'decision',decision
    )
  );
  replay:=app_private.command_replay(
    target_room_id,idempotency_key,'RESOLVE_INTERVENTION',request_hash
  );
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room
  where room.id=target_room_id;
  if room_record.state_version<>expected_state_version then
    raise exception using errcode='40001',message='stale room state version';
  end if;
  select request.* into strict request_record
  from app_private.intervention_requests as request
  where request.room_id=target_room_id and request.id=target_request_id
  for update;
  select preview.* into strict preview_record
  from app_private.intervention_previews as preview
  where preview.room_id=target_room_id and preview.request_id=target_request_id;
  if room_record.status<>'IN_PROGRESS'
    or room_record.current_round_id<>request_record.round_id
    or request_record.status<>'PREVIEW_READY'
    or decision not in ('APPROVE','REJECT') then
    raise exception using errcode='55000',message='intervention cannot be resolved';
  end if;
  next_version:=room_record.state_version+1;
  result:=pg_catalog.jsonb_build_object(
    'requestId',target_request_id,
    'status',case when decision='APPROVE' then 'RELEASED' else 'REJECTED' end,
    'stateVersion',next_version::text,'replayed',false
  );
  perform app_private.record_command(
    receipt_id,target_room_id,idempotency_key,'RESOLVE_INTERVENTION',
    'GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,
    next_version,result,
    case when decision='APPROVE' then 'INTERVENTION_RELEASED'
      else 'INTERVENTION_REJECTED' end,
    target_request_id,'GAMEPLAY_CHANGED'
  );
  if decision='APPROVE' then
    if preview_record.candidate_kind='DIRECTED_QUESTION' then
      insert into app_private.runtime_effects(
        room_id,story_id,effect_kind,source_intervention_request_id,
        target_intervention_spec_id,command_receipt_id
      ) values (
        target_room_id,room_record.story_id,'DIRECTED_QUESTION',target_request_id,
        preview_record.intervention_spec_id,receipt_id
      );
    elsif preview_record.candidate_kind='RELEASE_EVIDENCE' then
      if exists(select 1 from app_private.evidence_releases as release
        where release.room_id=target_room_id
          and release.evidence_id=preview_record.evidence_id) then
        raise exception using errcode='55000',message='intervention evidence is no longer eligible';
      end if;
      insert into app_private.evidence_releases(
        room_id,story_id,evidence_id,released_in_round_id,release_reason,
        command_receipt_id
      ) values (
        target_room_id,room_record.story_id,preview_record.evidence_id,
        room_record.current_round_id,'INTERVENTION',receipt_id
      );
      insert into app_private.runtime_effects(
        room_id,story_id,effect_kind,source_intervention_request_id,
        target_evidence_id,command_receipt_id
      ) values (
        target_room_id,room_record.story_id,'EVIDENCE_RELEASE',target_request_id,
        preview_record.evidence_id,receipt_id
      );
    elsif preview_record.candidate_kind='RELEASE_CONSEQUENCE' then
      update app_private.consequence_states set status='RELEASED',
        resolved_by_command_receipt_id=receipt_id,
        resolved_at=app_private.current_database_time()
      where room_id=target_room_id
        and consequence_spec_id=preview_record.consequence_spec_id
        and status='PENDING';
      if not found then
        raise exception using errcode='55000',message='intervention consequence is no longer eligible';
      end if;
      update app_private.mission_states set status='CONSEQUENCE_RELEASED',
        revision=revision+1,updated_at=app_private.current_database_time()
      where room_id=target_room_id and id=(
        select state.source_mission_state_id
        from app_private.consequence_states as state
        where state.room_id=target_room_id
          and state.consequence_spec_id=preview_record.consequence_spec_id
      );
      insert into app_private.runtime_effects(
        room_id,story_id,effect_kind,source_intervention_request_id,
        target_consequence_spec_id,command_receipt_id
      ) values (
        target_room_id,room_record.story_id,'CONSEQUENCE_RELEASE',target_request_id,
        preview_record.consequence_spec_id,receipt_id
      );
    elsif preview_record.candidate_kind='ACTIVATE_MISSION' then
      if not exists(select 1 from app_private.mission_states as state
        join app_private.mission_specs as spec
          on spec.room_id=state.room_id and spec.id=state.mission_spec_id
        where state.room_id=target_room_id
          and state.mission_spec_id=preview_record.mission_spec_id
          and state.status='ASSIGNED'
          and spec.round_id=room_record.current_round_id) then
        raise exception using errcode='55000',message='urgent mission is no longer eligible';
      end if;
      insert into app_private.runtime_effects(
        room_id,story_id,effect_kind,source_intervention_request_id,
        target_mission_spec_id,command_receipt_id
      ) values (
        target_room_id,room_record.story_id,'MISSION_ACTIVATION',target_request_id,
        preview_record.mission_spec_id,receipt_id
      );
    end if;
    insert into app_private.intervention_releases(
      id,room_id,story_id,request_id,preview_id,command_receipt_id
    ) values (
      release_id,target_room_id,room_record.story_id,target_request_id,
      preview_record.id,receipt_id
    );
    update app_private.intervention_requests set status='RELEASED',
      revision=revision+1,updated_at=app_private.current_database_time()
    where id=target_request_id;
  else
    update app_private.intervention_requests set status='REJECTED',
      revision=revision+1,updated_at=app_private.current_database_time()
    where id=target_request_id;
  end if;
  update app_private.rooms set state_version=next_version,
    updated_at=app_private.current_database_time() where id=target_room_id;
  return result;
end;
$function$;

revoke execute on function app_private.intervention_candidates(uuid,uuid,integer)
  from public,anon,authenticated,service_role;
revoke all on function public.request_intervention(uuid,bigint,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.stage_intervention_preview(
  uuid,uuid,uuid,uuid,text,text,text,text,integer,integer,integer,text
) from public,anon,authenticated,service_role;
revoke all on function public.resolve_intervention(uuid,uuid,bigint,uuid,text)
  from public,anon,authenticated,service_role;

grant execute on function public.request_intervention(uuid,bigint,uuid)
  to authenticated;
grant execute on function public.stage_intervention_preview(
  uuid,uuid,uuid,uuid,text,text,text,text,integer,integer,integer,text
) to authenticated;
grant execute on function public.resolve_intervention(uuid,uuid,bigint,uuid,text)
  to authenticated;
