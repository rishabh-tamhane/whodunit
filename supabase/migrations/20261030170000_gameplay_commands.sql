-- APP/PLY/GAM: actor projection, private notebooks/theories, and command kernel.

-- Realtime carries invalidation only. Actor content is always refetched through
-- an authorized projection after a signal arrives.
do $block$
begin
  if exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_signals'
  ) then
    alter publication supabase_realtime add table public.room_signals;
  end if;
end
$block$;

create or replace function app_private.audience_allows_player(
  audience jsonb,
  target_player_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    pg_catalog.lower(
      coalesce(audience ->> 'kind', audience ->> 'visibility', '')
    ) in ('public', 'all_players')
    or audience ->> 'public' = 'true'
    or audience ->> 'targetPlayerId' = target_player_id::text
    or (
      coalesce(
        audience -> 'playerIds'
          @> pg_catalog.jsonb_build_array(target_player_id::text),
        false
      )
    )
    or (
      pg_catalog.lower(coalesce(audience ->> 'kind', '')) = 'factions'
      and exists (
        select 1
        from app_private.dossiers as dossier
        where dossier.player_id = target_player_id
          and audience -> 'factions'
            @> pg_catalog.jsonb_build_array(dossier.faction::text)
      )
    );
$function$;

create function app_private.command_request_hash(
  command_name text,
  request_payload jsonb
)
returns bytea
language sql
immutable
security definer
set search_path = ''
as $function$
  select extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'command', command_name,
        'payload', request_payload
      )::text,
      'UTF8'
    ),
    'sha256'
  );
$function$;

create function app_private.command_replay(
  target_room_id uuid,
  target_idempotency_key uuid,
  expected_command_name text,
  expected_request_hash bytea
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare receipt app_private.command_receipts%rowtype;
begin
  select candidate.* into receipt
  from app_private.command_receipts as candidate
  where candidate.room_id = target_room_id
    and candidate.idempotency_key = target_idempotency_key;
  if receipt.id is null then return null; end if;
  if receipt.command_name <> expected_command_name
    or receipt.request_hash <> expected_request_hash then
    raise exception using errcode = '23505', message = 'idempotency key conflicts with a different command';
  end if;
  return receipt.result_json || pg_catalog.jsonb_build_object('replayed', true);
end;
$function$;

create function app_private.record_command(
  target_receipt_id uuid,
  target_room_id uuid,
  target_idempotency_key uuid,
  target_command_name text,
  target_actor_type app_private.command_actor_type,
  target_actor_auth_user_id uuid,
  target_actor_player_id uuid,
  target_request_hash bytea,
  target_expected_state_version bigint,
  target_result_state_version bigint,
  target_result jsonb,
  target_event_type text,
  target_source_object_id uuid,
  target_signal_type text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare next_sequence bigint;
begin
  insert into app_private.command_receipts (
    id, room_id, idempotency_key, command_name, actor_type,
    actor_auth_user_id, actor_player_id, request_hash,
    expected_state_version, result_state_version, response_status, result_json
  ) values (
    target_receipt_id, target_room_id, target_idempotency_key,
    target_command_name, target_actor_type, target_actor_auth_user_id,
    target_actor_player_id, target_request_hash,
    target_expected_state_version, target_result_state_version, 200, target_result
  );
  select coalesce(pg_catalog.max(event.room_sequence), 0) + 1
  into next_sequence from app_private.game_events as event
  where event.room_id = target_room_id;
  insert into app_private.game_events (
    room_id, room_sequence, state_version, event_type, actor_type,
    actor_auth_user_id, actor_player_id, source_object_id,
    command_receipt_id
  ) values (
    target_room_id, next_sequence, target_result_state_version,
    target_event_type, target_actor_type, target_actor_auth_user_id,
    target_actor_player_id, target_source_object_id, target_receipt_id
  );
  insert into public.room_signals (room_id, state_version, change_type)
  values (target_room_id, target_result_state_version, target_signal_type);
end;
$function$;

create function app_private.release_guaranteed_evidence(
  target_room_id uuid,
  target_story_id uuid,
  target_round_id uuid,
  target_receipt_id uuid,
  include_final_fallback boolean default false
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare released_count integer;
begin
  with eligible as (
    select evidence.id
    from app_private.evidence as evidence
    where evidence.room_id = target_room_id
      and evidence.story_id = target_story_id
      and (
        (
          evidence.release_rule_json ->> 'kind' = 'ROUND_START'
          and (evidence.release_rule_json ->> 'roundId')::uuid = target_round_id
        )
        or (
          include_final_fallback
          and evidence.release_rule_json ->> 'kind' = 'FINAL_ROUND_FALLBACK'
        )
      )
  ), inserted as (
    insert into app_private.evidence_releases (
      room_id, story_id, evidence_id, released_in_round_id,
      release_reason, command_receipt_id
    )
    select target_room_id, target_story_id, eligible.id, target_round_id,
      'GUARANTEED', target_receipt_id
    from eligible
    on conflict (story_id, evidence_id) do nothing
    returning id
  )
  select pg_catalog.count(*)::integer into released_count from inserted;
  return released_count;
end;
$function$;

create function public.get_actor_view(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  projection jsonb;
  authorized_player_id uuid;
  room_record app_private.rooms%rowtype;
  current_round_sequence integer;
begin
  if app_private.is_current_game_master(target_room_id) then
    return public.get_game_master_view(target_room_id);
  end if;
  if app_private.is_active_player(target_room_id) then
    authorized_player_id := app_private.assert_active_player(target_room_id);
    select room.* into strict room_record
    from app_private.rooms as room where room.id = target_room_id;
    projection := public.get_player_view(target_room_id);

    select round.sequence into current_round_sequence
    from app_private.story_rounds as round
    where round.room_id = target_room_id
      and round.id = room_record.current_round_id;

    projection := pg_catalog.jsonb_set(
      projection,
      '{missions}',
      coalesce((
        select pg_catalog.jsonb_agg(mission order by round.sequence)
        from pg_catalog.jsonb_array_elements(
          coalesce(projection -> 'missions', '[]'::jsonb)
        ) as mission
        join app_private.story_rounds as round
          on round.room_id = target_room_id
          and round.id = (mission ->> 'roundId')::uuid
        where room_record.status in ('FINAL_ACCUSATIONS', 'REVEAL', 'COMPLETED')
          or (
            room_record.status = 'IN_PROGRESS'
            and round.sequence <= current_round_sequence
          )
      ), '[]'::jsonb),
      true
    );

    projection := pg_catalog.jsonb_set(
      projection,
      '{evidence}',
      coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', evidence.id,
            'kind', evidence.evidence_kind,
            'content', evidence.content_json,
            'audience', evidence.audience_json,
            'releasedAt', release.released_at,
            'releasedInRoundId', release.released_in_round_id,
            'releaseReason', release.release_reason,
            'roundSequence', round.sequence
          ) order by release.released_at, evidence.id
        )
        from app_private.evidence_releases as release
        join app_private.evidence as evidence
          on evidence.room_id = release.room_id
          and evidence.story_id = release.story_id
          and evidence.id = release.evidence_id
        left join app_private.story_rounds as round
          on round.room_id = release.room_id
          and round.id = release.released_in_round_id
        where release.room_id = target_room_id
          and app_private.audience_allows_player(
            evidence.audience_json,
            authorized_player_id
          )
      ), '[]'::jsonb),
      true
    );

    projection := projection || pg_catalog.jsonb_build_object(
      'releasedConsequences', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', spec.id,
            'severity', spec.severity,
            'content', spec.consequence_json,
            'status', state.status::text,
            'resolvedAt', state.resolved_at
          ) order by state.resolved_at, spec.id
        )
        from app_private.consequence_states as state
        join app_private.consequence_specs as spec
          on spec.room_id = state.room_id
          and spec.story_id = state.story_id
          and spec.id = state.consequence_spec_id
        join app_private.mission_states as mission_state
          on mission_state.room_id = state.room_id
          and mission_state.id = state.source_mission_state_id
        join app_private.mission_specs as mission
          on mission.room_id = mission_state.room_id
          and mission.id = mission_state.mission_spec_id
        where state.room_id = target_room_id
          and state.status = 'RELEASED'
          and mission.assigned_player_id = authorized_player_id
      ), '[]'::jsonb)
    );
    return projection;
  end if;
  raise exception using errcode = '42501', message = 'authorized room actor required';
end;
$function$;

create function public.save_player_notebook(
  target_room_id uuid,
  expected_revision bigint,
  notes_text text,
  suspects jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  owner_id uuid;
  note app_private.player_notes%rowtype;
  suspect jsonb;
begin
  owner_id := app_private.assert_active_player(target_room_id);
  if pg_catalog.char_length(notes_text) > 10000
    or pg_catalog.jsonb_typeof(suspects) <> 'array' then
    raise exception using errcode = '22023', message = 'invalid notebook content';
  end if;
  select existing.* into note from app_private.player_notes as existing
  where existing.room_id = target_room_id and existing.player_id = owner_id
  for update;
  if note.id is null then
    if expected_revision <> 0 then raise exception using errcode = '40001', message = 'stale notebook revision'; end if;
    insert into app_private.player_notes (room_id, player_id, notes_text)
    values (target_room_id, owner_id, notes_text) returning * into note;
  else
    if note.revision <> expected_revision then raise exception using errcode = '40001', message = 'stale notebook revision'; end if;
    set constraints all deferred;
    delete from app_private.player_note_suspects
    where room_id = target_room_id and owner_player_id = owner_id;
    update app_private.player_notes set revision = revision + 1,
      notes_text = save_player_notebook.notes_text,
      updated_at = app_private.current_database_time()
    where id = note.id returning * into note;
  end if;
  for suspect in select value from pg_catalog.jsonb_array_elements(suspects)
  loop
    if (suspect ->> 'playerId')::uuid = owner_id
      or suspect ->> 'suspectedRole' not in ('MURDERER','ACCOMPLICE')
      or not exists (
        select 1 from app_private.players as player
        where player.room_id = target_room_id and player.id = (suspect ->> 'playerId')::uuid
      ) then
      raise exception using errcode = '22023', message = 'invalid notebook suspect';
    end if;
    insert into app_private.player_note_suspects (
      room_id, owner_player_id, note_id, notebook_revision,
      suspect_player_id, suspected_role
    ) values (
      target_room_id, owner_id, note.id, note.revision,
      (suspect ->> 'playerId')::uuid,
      (suspect ->> 'suspectedRole')::app_private.suspected_role
    );
  end loop;
  return pg_catalog.jsonb_build_object(
    'noteId', note.id, 'revision', note.revision,
    'updatedAt', note.updated_at
  );
end;
$function$;

create function public.submit_player_theory(
  target_room_id uuid,
  expected_state_version bigint,
  idempotency_key uuid,
  structured_claim jsonb,
  submitted_explanation text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  player_id uuid;
  theory_id uuid := pg_catalog.gen_random_uuid();
  receipt_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  result jsonb;
  item jsonb;
begin
  perform app_private.lock_room(target_room_id);
  player_id := app_private.assert_active_player(target_room_id);
  request_hash := app_private.command_request_hash('SUBMIT_THEORY', pg_catalog.jsonb_build_object('claim', structured_claim, 'explanation', submitted_explanation));
  replay := app_private.command_replay(target_room_id, idempotency_key, 'SUBMIT_THEORY', request_hash);
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then raise exception using errcode = '40001', message = 'stale room state version'; end if;
  if room_record.status <> 'IN_PROGRESS' or room_record.current_round_id is null
    or pg_catalog.jsonb_typeof(structured_claim) <> 'object'
    or pg_catalog.jsonb_typeof(structured_claim -> 'suspects') <> 'array'
    or pg_catalog.jsonb_typeof(structured_claim -> 'evidenceIds') <> 'array'
    or pg_catalog.char_length(coalesce(submitted_explanation,'')) > 2000 then
    raise exception using errcode = '22023', message = 'invalid submitted theory';
  end if;
  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object('theoryId', theory_id, 'stateVersion', next_version::text, 'correctness', null, 'replayed', false);
  perform app_private.record_command(receipt_id, target_room_id, idempotency_key, 'SUBMIT_THEORY', 'PLAYER', auth.uid(), player_id, request_hash, expected_state_version, next_version, result, 'THEORY_SUBMITTED', theory_id, 'PLAYER_STATE_CHANGED');
  insert into app_private.player_theories (
    id, room_id, story_id, player_id, round_id, submitted_state_version,
    structured_claim_json, submitted_explanation, command_receipt_id
  ) values (
    theory_id, target_room_id, room_record.story_id, player_id,
    room_record.current_round_id, next_version, structured_claim,
    nullif(pg_catalog.btrim(submitted_explanation), ''), receipt_id
  );
  for item in select value from pg_catalog.jsonb_array_elements(structured_claim -> 'suspects')
  loop
    insert into app_private.player_theory_suspects (room_id, story_id, theory_id, suspect_player_id, suspected_role)
    values (target_room_id, room_record.story_id, theory_id, (item ->> 'playerId')::uuid, (item ->> 'suspectedRole')::app_private.suspected_role);
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements(structured_claim -> 'evidenceIds')
  loop
    insert into app_private.player_theory_evidence (room_id, story_id, theory_id, evidence_id)
    values (target_room_id, room_record.story_id, theory_id, (item #>> '{}')::uuid);
  end loop;
  update app_private.rooms set state_version = next_version,
    updated_at = app_private.current_database_time() where id = target_room_id;
  return result;
end;
$function$;

create function public.start_game(
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
declare room_record app_private.rooms%rowtype; first_round uuid; receipt_id uuid := pg_catalog.gen_random_uuid(); request_hash bytea; replay jsonb; next_version bigint; result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash('START_GAME', '{}'::jsonb);
  replay := app_private.command_replay(target_room_id,idempotency_key,'START_GAME',request_hash); if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id=target_room_id;
  if room_record.state_version<>expected_state_version then raise exception using errcode='40001',message='stale room state version'; end if;
  if room_record.status<>'READY_TO_START' or room_record.story_id is null then raise exception using errcode='55000',message='room is not ready to start'; end if;
  select round.id into strict first_round from app_private.story_rounds as round where round.room_id=target_room_id and round.story_id=room_record.story_id order by round.sequence limit 1;
  next_version:=room_record.state_version+1;
  result:=pg_catalog.jsonb_build_object('roomId',target_room_id,'status','IN_PROGRESS','currentRoundId',first_round,'stateVersion',next_version::text,'replayed',false);
  perform app_private.record_command(receipt_id,target_room_id,idempotency_key,'START_GAME','GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,next_version,result,'GAME_STARTED',first_round,'ROUND_CHANGED');
  update app_private.rooms set status='IN_PROGRESS',current_round_id=first_round,started_at=app_private.current_database_time(),state_version=next_version,updated_at=app_private.current_database_time() where id=target_room_id;
  perform app_private.release_guaranteed_evidence(target_room_id,room_record.story_id,first_round,receipt_id,false);
  return result;
end;
$function$;

create function public.advance_round(
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
declare room_record app_private.rooms%rowtype; next_round uuid; receipt_id uuid:=pg_catalog.gen_random_uuid(); request_hash bytea; replay jsonb; next_version bigint; result jsonb; next_status text;
begin
  perform app_private.lock_room(target_room_id); perform app_private.assert_current_game_master(target_room_id);
  request_hash:=app_private.command_request_hash('ADVANCE_ROUND','{}'::jsonb);
  replay:=app_private.command_replay(target_room_id,idempotency_key,'ADVANCE_ROUND',request_hash); if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id=target_room_id;
  if room_record.state_version<>expected_state_version then raise exception using errcode='40001',message='stale room state version'; end if;
  if room_record.status<>'IN_PROGRESS' or room_record.current_round_id is null then raise exception using errcode='55000',message='room is not in active play'; end if;
  select candidate.id into next_round from app_private.story_rounds as candidate
  join app_private.story_rounds as current on current.room_id=candidate.room_id and current.id=room_record.current_round_id
  where candidate.room_id=target_room_id and candidate.sequence=current.sequence+1;
  next_version:=room_record.state_version+1; next_status:=case when next_round is null then 'FINAL_ACCUSATIONS' else 'IN_PROGRESS' end;
  result:=pg_catalog.jsonb_build_object('roomId',target_room_id,'status',next_status,'currentRoundId',coalesce(next_round,room_record.current_round_id),'stateVersion',next_version::text,'replayed',false);
  perform app_private.record_command(receipt_id,target_room_id,idempotency_key,'ADVANCE_ROUND','GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,next_version,result,case when next_round is null then 'FINAL_ACCUSATIONS_OPENED' else 'ROUND_ADVANCED' end,coalesce(next_round,room_record.current_round_id),case when next_round is null then 'ENDGAME_CHANGED' else 'ROUND_CHANGED' end);
  update app_private.mission_states as state set status='WAIVED',revision=revision+1,resolved_at=app_private.current_database_time(),updated_at=app_private.current_database_time()
  from app_private.mission_specs as spec where state.room_id=target_room_id and state.mission_spec_id=spec.id and spec.round_id=room_record.current_round_id and state.status in ('ASSIGNED','ACCEPTED','COMPLETION_REQUESTED');
  if next_round is null then
    update app_private.rooms set status='FINAL_ACCUSATIONS',state_version=next_version,updated_at=app_private.current_database_time() where id=target_room_id;
    perform app_private.release_guaranteed_evidence(target_room_id,room_record.story_id,room_record.current_round_id,receipt_id,true);
  else
    update app_private.rooms set current_round_id=next_round,state_version=next_version,updated_at=app_private.current_database_time() where id=target_room_id;
    perform app_private.release_guaranteed_evidence(target_room_id,room_record.story_id,next_round,receipt_id,false);
    update app_private.accomplice_revelation_states as state set status='RELEASED',released_by_command_receipt_id=receipt_id,released_at=app_private.current_database_time()
    from app_private.accomplice_revelations as spec where state.room_id=target_room_id and state.revelation_spec_id=spec.id and spec.round_id=next_round and state.status='PENDING';
  end if;
  return result;
end;
$function$;

create function public.player_mission_command(
  target_room_id uuid, target_mission_id uuid, expected_state_version bigint,
  idempotency_key uuid, requested_action text
)
returns jsonb
language plpgsql volatile security definer set search_path=''
as $function$
declare room_record app_private.rooms%rowtype; state_record app_private.mission_states%rowtype; player_id uuid; receipt_id uuid:=pg_catalog.gen_random_uuid(); command_name text; request_hash bytea; replay jsonb; next_version bigint; next_status app_private.mission_status; result jsonb;
begin
  perform app_private.lock_room(target_room_id); player_id:=app_private.assert_active_player(target_room_id);
  command_name:=case requested_action when 'ACCEPT' then 'ACCEPT_MISSION' when 'REQUEST_COMPLETION' then 'REQUEST_MISSION_COMPLETION' else null end;
  if command_name is null then raise exception using errcode='22023',message='invalid mission action'; end if;
  request_hash:=app_private.command_request_hash(command_name,pg_catalog.jsonb_build_object('missionId',target_mission_id));
  replay:=app_private.command_replay(target_room_id,idempotency_key,command_name,request_hash); if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id=target_room_id;
  if room_record.state_version<>expected_state_version or room_record.status<>'IN_PROGRESS' then raise exception using errcode='40001',message='stale or inactive room state'; end if;
  select state.* into strict state_record from app_private.mission_states as state join app_private.mission_specs as spec on spec.room_id=state.room_id and spec.id=state.mission_spec_id where state.room_id=target_room_id and spec.id=target_mission_id and spec.assigned_player_id=player_id and spec.round_id=room_record.current_round_id for update of state;
  if requested_action='ACCEPT' and state_record.status='ASSIGNED' then next_status:='ACCEPTED';
  elsif requested_action='REQUEST_COMPLETION' and state_record.status='ACCEPTED' then next_status:='COMPLETION_REQUESTED';
  else raise exception using errcode='55000',message='invalid mission transition'; end if;
  next_version:=room_record.state_version+1; result:=pg_catalog.jsonb_build_object('missionId',target_mission_id,'status',next_status::text,'stateVersion',next_version::text,'replayed',false);
  perform app_private.record_command(receipt_id,target_room_id,idempotency_key,command_name,'PLAYER',auth.uid(),player_id,request_hash,expected_state_version,next_version,result,case when requested_action='ACCEPT' then 'MISSION_ACCEPTED' else 'MISSION_COMPLETION_REQUESTED' end,target_mission_id,'PLAYER_STATE_CHANGED');
  update app_private.mission_states set status=next_status,revision=revision+1,accepted_at=case when next_status='ACCEPTED' then app_private.current_database_time() else accepted_at end,completion_requested_at=case when next_status='COMPLETION_REQUESTED' then app_private.current_database_time() else completion_requested_at end,updated_at=app_private.current_database_time() where id=state_record.id;
  update app_private.rooms set state_version=next_version,updated_at=app_private.current_database_time() where id=target_room_id;
  return result;
end;
$function$;

create function public.adjudicate_mission(
  target_room_id uuid, target_mission_id uuid, expected_state_version bigint,
  idempotency_key uuid, decision text, extension_minutes integer default null
)
returns jsonb
language plpgsql volatile security definer set search_path=''
as $function$
declare room_record app_private.rooms%rowtype; state_record app_private.mission_states%rowtype; spec_record app_private.mission_specs%rowtype; receipt_id uuid:=pg_catalog.gen_random_uuid(); request_hash bytea; replay jsonb; next_version bigint; target_status app_private.mission_status; result jsonb;
begin
  perform app_private.lock_room(target_room_id); perform app_private.assert_current_game_master(target_room_id);
  request_hash:=app_private.command_request_hash('ADJUDICATE_MISSION',pg_catalog.jsonb_build_object('missionId',target_mission_id,'decision',decision,'extensionMinutes',extension_minutes));
  replay:=app_private.command_replay(target_room_id,idempotency_key,'ADJUDICATE_MISSION',request_hash); if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id=target_room_id;
  if room_record.state_version<>expected_state_version or room_record.status<>'IN_PROGRESS' then raise exception using errcode='40001',message='stale or inactive room state'; end if;
  select state.* into strict state_record
  from app_private.mission_states as state
  join app_private.mission_specs as spec
    on spec.room_id=state.room_id and spec.id=state.mission_spec_id
  where state.room_id=target_room_id and spec.id=target_mission_id
  for update of state;
  select spec.* into strict spec_record from app_private.mission_specs as spec
  where spec.room_id=target_room_id and spec.id=target_mission_id;
  if spec_record.round_id <> room_record.current_round_id then
    raise exception using errcode='55000',message='mission is not in the current round';
  end if;
  if decision='APPROVE' and state_record.status='COMPLETION_REQUESTED' then target_status:='COMPLETED';
  elsif decision='REJECT' and state_record.status='COMPLETION_REQUESTED' then target_status:='ACCEPTED';
  elsif decision='FAIL' and state_record.status in ('ASSIGNED','ACCEPTED','COMPLETION_REQUESTED') then target_status:='FAILED';
  elsif decision='WAIVE' and state_record.status in ('ASSIGNED','ACCEPTED','COMPLETION_REQUESTED','CONSEQUENCE_PENDING') then target_status:='WAIVED';
  elsif decision='EXTEND' and state_record.status in ('ACCEPTED','COMPLETION_REQUESTED') and extension_minutes between 1 and 60 then target_status:=state_record.status;
  else raise exception using errcode='55000',message='invalid mission adjudication'; end if;
  next_version:=room_record.state_version+1; result:=pg_catalog.jsonb_build_object('missionId',target_mission_id,'status',target_status::text,'stateVersion',next_version::text,'replayed',false);
  perform app_private.record_command(receipt_id,target_room_id,idempotency_key,'ADJUDICATE_MISSION','GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,next_version,result,'MISSION_ADJUDICATED',target_mission_id,'GAMEPLAY_CHANGED');
  update app_private.mission_states set status=target_status,revision=revision+1,
    deadline_at=case when decision='EXTEND' then app_private.current_database_time()+pg_catalog.make_interval(mins=>extension_minutes) else deadline_at end,
    completion_requested_at=case when decision='REJECT' then null else completion_requested_at end,
    resolved_at=case when decision in ('APPROVE','FAIL','WAIVE') then app_private.current_database_time() else resolved_at end,
    updated_at=app_private.current_database_time() where id=state_record.id;
  if decision='FAIL' and spec_record.failure_consequence_id is not null then
    if not exists (
      select 1 from app_private.consequence_specs as consequence
      where consequence.room_id=target_room_id
        and consequence.id=spec_record.failure_consequence_id
        and coalesce((consequence.eligibility_rule_json ->> 'afterFailedMission')::boolean,false)
        and consequence.eligibility_rule_json -> 'roundIds'
          @> pg_catalog.jsonb_build_array(room_record.current_round_id::text)
    ) then
      raise exception using errcode='55000',message='mission consequence is not eligible';
    end if;
    insert into app_private.consequence_states (room_id,story_id,consequence_spec_id,source_mission_state_id,eligible_by_command_receipt_id)
    values (target_room_id,room_record.story_id,spec_record.failure_consequence_id,state_record.id,receipt_id)
    on conflict (story_id,consequence_spec_id) do nothing;
    update app_private.mission_states set status='CONSEQUENCE_PENDING',revision=revision+1,updated_at=app_private.current_database_time() where id=state_record.id;
    result:=pg_catalog.jsonb_set(result,'{status}','"CONSEQUENCE_PENDING"'::jsonb);
    update app_private.command_receipts set result_json=result where id=receipt_id;
  end if;
  update app_private.rooms set state_version=next_version,updated_at=app_private.current_database_time() where id=target_room_id;
  return result;
end;
$function$;

create function public.resolve_canonical_release(
  target_room_id uuid, target_object_id uuid, expected_state_version bigint,
  idempotency_key uuid, object_kind text, decision text
)
returns jsonb
language plpgsql volatile security definer set search_path=''
as $function$
declare room_record app_private.rooms%rowtype; receipt_id uuid:=pg_catalog.gen_random_uuid(); request_hash bytea; replay jsonb; next_version bigint; result jsonb; state_id uuid;
begin
  perform app_private.lock_room(target_room_id); perform app_private.assert_current_game_master(target_room_id);
  request_hash:=app_private.command_request_hash('RESOLVE_CANONICAL_RELEASE',pg_catalog.jsonb_build_object('objectId',target_object_id,'kind',object_kind,'decision',decision));
  replay:=app_private.command_replay(target_room_id,idempotency_key,'RESOLVE_CANONICAL_RELEASE',request_hash); if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id=target_room_id;
  if room_record.state_version<>expected_state_version or room_record.status<>'IN_PROGRESS' then raise exception using errcode='40001',message='stale or inactive room state'; end if;
  next_version:=room_record.state_version+1; result:=pg_catalog.jsonb_build_object('objectId',target_object_id,'kind',object_kind,'decision',decision,'stateVersion',next_version::text,'replayed',false);
  perform app_private.record_command(receipt_id,target_room_id,idempotency_key,'RESOLVE_CANONICAL_RELEASE','GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,next_version,result,'CANONICAL_RELEASE_RESOLVED',target_object_id,'GAMEPLAY_CHANGED');
  if object_kind='EVIDENCE' and decision='RELEASE' then
    if not exists (
      select 1
      from app_private.evidence as evidence
      join app_private.story_rounds as earliest
        on earliest.room_id=evidence.room_id
        and earliest.id=(evidence.release_rule_json ->> 'earliestRoundId')::uuid
      join app_private.story_rounds as current_round
        on current_round.room_id=evidence.room_id
        and current_round.id=room_record.current_round_id
      where evidence.room_id=target_room_id
        and evidence.id=target_object_id
        and evidence.release_rule_json ->> 'kind'='GAME_MASTER_MANUAL'
        and current_round.sequence >= earliest.sequence
    )
      or exists (select 1 from app_private.evidence_dependencies as dependency where dependency.room_id=target_room_id and dependency.target_evidence_id=target_object_id and dependency.dependency_kind='REQUIRES' and not exists (select 1 from app_private.evidence_releases as released where released.room_id=target_room_id and released.evidence_id=dependency.source_evidence_id)) then
      raise exception using errcode='55000',message='evidence is not eligible for release';
    end if;
    insert into app_private.evidence_releases (room_id,story_id,evidence_id,released_in_round_id,release_reason,command_receipt_id)
    values (target_room_id,room_record.story_id,target_object_id,room_record.current_round_id,'STANDALONE',receipt_id);
    insert into app_private.runtime_effects (
      room_id,story_id,effect_kind,target_evidence_id,command_receipt_id
    ) values (
      target_room_id,room_record.story_id,'EVIDENCE_RELEASE',target_object_id,receipt_id
    );
  elsif object_kind='CONSEQUENCE' and decision in ('RELEASE','WAIVE') then
    select state.id into strict state_id from app_private.consequence_states as state where state.room_id=target_room_id and state.consequence_spec_id=target_object_id and state.status='PENDING' for update;
    update app_private.consequence_states set status=case when decision='RELEASE' then 'RELEASED'::app_private.runtime_resolution_status else 'WAIVED'::app_private.runtime_resolution_status end,resolved_by_command_receipt_id=receipt_id,resolved_at=app_private.current_database_time() where id=state_id;
    update app_private.mission_states set status=case when decision='RELEASE' then 'CONSEQUENCE_RELEASED'::app_private.mission_status else 'WAIVED'::app_private.mission_status end,revision=revision+1,updated_at=app_private.current_database_time() where room_id=target_room_id and id=(select source_mission_state_id from app_private.consequence_states where id=state_id);
    if decision='RELEASE' then
      insert into app_private.runtime_effects (
        room_id,story_id,effect_kind,target_consequence_spec_id,command_receipt_id
      ) values (
        target_room_id,room_record.story_id,'CONSEQUENCE_RELEASE',target_object_id,receipt_id
      );
    end if;
  else raise exception using errcode='22023',message='invalid canonical release action'; end if;
  update app_private.rooms set state_version=next_version,updated_at=app_private.current_database_time() where id=target_room_id;
  return result;
end;
$function$;

revoke execute on function app_private.command_request_hash(text,jsonb) from public,anon,authenticated,service_role;
revoke execute on function app_private.command_replay(uuid,uuid,text,bytea) from public,anon,authenticated,service_role;
revoke execute on function app_private.record_command(uuid,uuid,uuid,text,app_private.command_actor_type,uuid,uuid,bytea,bigint,bigint,jsonb,text,uuid,text) from public,anon,authenticated,service_role;
revoke execute on function app_private.release_guaranteed_evidence(uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.get_actor_view(uuid) from public,anon,authenticated,service_role;
revoke all on function public.save_player_notebook(uuid,bigint,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.submit_player_theory(uuid,bigint,uuid,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.start_game(uuid,bigint,uuid) from public,anon,authenticated,service_role;
revoke all on function public.advance_round(uuid,bigint,uuid) from public,anon,authenticated,service_role;
revoke all on function public.player_mission_command(uuid,uuid,bigint,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.adjudicate_mission(uuid,uuid,bigint,uuid,text,integer) from public,anon,authenticated,service_role;
revoke all on function public.resolve_canonical_release(uuid,uuid,bigint,uuid,text,text) from public,anon,authenticated,service_role;

grant execute on function public.get_actor_view(uuid) to authenticated;
grant execute on function public.save_player_notebook(uuid,bigint,text,jsonb) to authenticated;
grant execute on function public.submit_player_theory(uuid,bigint,uuid,jsonb,text) to authenticated;
grant execute on function public.start_game(uuid,bigint,uuid) to authenticated;
grant execute on function public.advance_round(uuid,bigint,uuid) to authenticated;
grant execute on function public.player_mission_command(uuid,uuid,bigint,uuid,text) to authenticated;
grant execute on function public.adjudicate_mission(uuid,uuid,bigint,uuid,text,integer) to authenticated;
grant execute on function public.resolve_canonical_release(uuid,uuid,bigint,uuid,text,text) to authenticated;
