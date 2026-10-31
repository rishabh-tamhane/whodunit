-- END: owner-private accusations, frozen deterministic scoring, reveal, and case file.

create function app_private.validate_final_case(
  target_room_id uuid,
  target_player_id uuid,
  structured_case jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  murderer_count integer;
  accomplice_count integer;
  evidence_count integer;
begin
  if pg_catalog.jsonb_typeof(structured_case) <> 'object'
    or pg_catalog.jsonb_typeof(structured_case -> 'murdererPlayerIds') <> 'array'
    or pg_catalog.jsonb_typeof(structured_case -> 'accomplicePlayerIds') <> 'array'
    or pg_catalog.jsonb_typeof(structured_case -> 'evidenceIds') <> 'array'
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(structured_case ->> 'motive', ''))) not between 1 and 1000
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(structured_case ->> 'method', ''))) not between 1 and 1000
  then
    raise exception using errcode = '22023', message = 'final case is incomplete';
  end if;

  select pg_catalog.count(*), pg_catalog.count(distinct item.value)
  into murderer_count, accomplice_count
  from pg_catalog.jsonb_array_elements_text(structured_case -> 'murdererPlayerIds') as item;
  if murderer_count < 1 or murderer_count > 12 or murderer_count <> accomplice_count then
    raise exception using errcode = '22023', message = 'murderer selections must be unique';
  end if;

  select pg_catalog.count(*), pg_catalog.count(distinct item.value)
  into accomplice_count, evidence_count
  from pg_catalog.jsonb_array_elements_text(structured_case -> 'accomplicePlayerIds') as item;
  if accomplice_count > 11 or accomplice_count <> evidence_count then
    raise exception using errcode = '22023', message = 'accomplice selections must be unique';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(structured_case -> 'murdererPlayerIds') as murderer
    join pg_catalog.jsonb_array_elements_text(structured_case -> 'accomplicePlayerIds') as accomplice
      on accomplice.value = murderer.value
  ) then
    raise exception using errcode = '22023', message = 'a player cannot be both murderer and accomplice in one case';
  end if;

  if exists (
    select 1
    from (
      select item.value::uuid as player_id
      from pg_catalog.jsonb_array_elements_text(structured_case -> 'murdererPlayerIds') as item
      union all
      select item.value::uuid
      from pg_catalog.jsonb_array_elements_text(structured_case -> 'accomplicePlayerIds') as item
    ) as selected
    where not exists (
      select 1 from app_private.players as player
      where player.room_id = target_room_id and player.id = selected.player_id
    )
  ) then
    raise exception using errcode = '22023', message = 'final case references a player outside the room';
  end if;

  select pg_catalog.count(*), pg_catalog.count(distinct item.value)
  into evidence_count, accomplice_count
  from pg_catalog.jsonb_array_elements_text(structured_case -> 'evidenceIds') as item;
  if evidence_count > 50 or evidence_count <> accomplice_count then
    raise exception using errcode = '22023', message = 'evidence selections must be unique';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(structured_case -> 'evidenceIds') as item
    left join app_private.evidence as evidence
      on evidence.room_id = target_room_id and evidence.id = item.value::uuid
    left join app_private.evidence_releases as release
      on release.room_id = target_room_id and release.evidence_id = evidence.id
    where evidence.id is null
      or release.id is null
      or not app_private.audience_allows_player(evidence.audience_json, target_player_id)
  ) then
    raise exception using errcode = '22023', message = 'only evidence released to this player may support a final case';
  end if;
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'final case contains an invalid identifier';
end;
$function$;

create function public.open_final_accusations(
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
  receipt_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash('OPEN_FINAL_ACCUSATIONS', '{}'::jsonb);
  replay := app_private.command_replay(target_room_id, idempotency_key, 'OPEN_FINAL_ACCUSATIONS', request_hash);
  if replay is not null then return replay; end if;

  select room.* into strict room_record
  from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'IN_PROGRESS' then
    raise exception using errcode = '55000', message = 'early verdict requires active play';
  end if;

  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object(
    'roomId', target_room_id, 'status', 'FINAL_ACCUSATIONS',
    'stateVersion', next_version::text, 'replayed', false
  );
  perform app_private.record_command(
    receipt_id, target_room_id, idempotency_key, 'OPEN_FINAL_ACCUSATIONS',
    'GAME_MASTER', auth.uid(), null, request_hash, expected_state_version,
    next_version, result, 'EARLY_VERDICT_CALLED', room_record.current_round_id,
    'ENDGAME_CHANGED'
  );

  update app_private.mission_states
  set status = 'WAIVED', revision = revision + 1,
    resolved_at = app_private.current_database_time(),
    updated_at = app_private.current_database_time()
  where room_id = target_room_id
    and status in ('ASSIGNED', 'ACCEPTED', 'COMPLETION_REQUESTED');
  perform app_private.release_guaranteed_evidence(
    target_room_id, room_record.story_id, room_record.current_round_id,
    receipt_id, true
  );
  update app_private.rooms
  set status = 'FINAL_ACCUSATIONS', state_version = next_version,
    updated_at = app_private.current_database_time()
  where id = target_room_id;
  return result;
end;
$function$;

create function public.save_final_accusation(
  target_room_id uuid,
  expected_revision bigint,
  structured_case jsonb,
  explanation_text text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  authorized_player_id uuid;
  accusation app_private.final_accusations%rowtype;
  item record;
begin
  perform app_private.lock_room(target_room_id);
  authorized_player_id := app_private.assert_active_player(target_room_id);
  select room.* into strict room_record
  from app_private.rooms as room where room.id = target_room_id;
  if room_record.status <> 'FINAL_ACCUSATIONS'
    or exists (select 1 from app_private.scoring_snapshots where room_id = target_room_id)
  then
    raise exception using errcode = '55000', message = 'final-case intake is closed';
  end if;
  if pg_catalog.char_length(coalesce(explanation_text, '')) > 4000 then
    raise exception using errcode = '22023', message = 'final-case explanation is too long';
  end if;
  perform app_private.validate_final_case(target_room_id, authorized_player_id, structured_case);
  set constraints all deferred;

  select candidate.* into accusation
  from app_private.final_accusations as candidate
  where candidate.room_id = target_room_id
    and candidate.player_id = authorized_player_id
  for update;

  if accusation.id is null then
    if expected_revision <> 0 then
      raise exception using errcode = '40001', message = 'stale final accusation revision';
    end if;
    insert into app_private.final_accusations (
      room_id, story_id, player_id, structured_case_json, explanation_text
    ) values (
      target_room_id, room_record.story_id, authorized_player_id,
      structured_case, nullif(explanation_text, '')
    ) returning * into accusation;
  else
    if accusation.status <> 'DRAFT' then
      raise exception using errcode = '55000', message = 'submitted final accusation is immutable';
    end if;
    if accusation.revision <> expected_revision then
      raise exception using errcode = '40001', message = 'stale final accusation revision';
    end if;
    update app_private.final_accusations
    set revision = revision + 1, structured_case_json = structured_case,
      explanation_text = nullif(explanation_text, ''),
      updated_at = app_private.current_database_time()
    where id = accusation.id returning * into accusation;
  end if;

  delete from app_private.final_accusation_suspects where accusation_id = accusation.id;
  delete from app_private.final_accusation_evidence where accusation_id = accusation.id;
  for item in select value from pg_catalog.jsonb_array_elements_text(structured_case -> 'murdererPlayerIds')
  loop
    insert into app_private.final_accusation_suspects (
      room_id, story_id, owner_player_id, accusation_id,
      accusation_revision, suspect_player_id, suspected_role
    ) values (
      target_room_id, room_record.story_id, authorized_player_id, accusation.id,
      accusation.revision, item.value::uuid, 'MURDERER'
    );
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements_text(structured_case -> 'accomplicePlayerIds')
  loop
    insert into app_private.final_accusation_suspects (
      room_id, story_id, owner_player_id, accusation_id,
      accusation_revision, suspect_player_id, suspected_role
    ) values (
      target_room_id, room_record.story_id, authorized_player_id, accusation.id,
      accusation.revision, item.value::uuid, 'ACCOMPLICE'
    );
  end loop;
  for item in select value from pg_catalog.jsonb_array_elements_text(structured_case -> 'evidenceIds')
  loop
    insert into app_private.final_accusation_evidence (
      room_id, story_id, owner_player_id, accusation_id,
      accusation_revision, evidence_id
    ) values (
      target_room_id, room_record.story_id, authorized_player_id, accusation.id,
      accusation.revision, item.value::uuid
    );
  end loop;

  return pg_catalog.jsonb_build_object(
    'accusationId', accusation.id, 'status', accusation.status::text,
    'revision', accusation.revision, 'updatedAt', accusation.updated_at
  );
end;
$function$;

create function public.submit_final_accusation(
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
  authorized_player_id uuid;
  accusation app_private.final_accusations%rowtype;
  receipt_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  authorized_player_id := app_private.assert_active_player(target_room_id);
  request_hash := app_private.command_request_hash('SUBMIT_FINAL_ACCUSATION', '{}'::jsonb);
  replay := app_private.command_replay(target_room_id, idempotency_key, 'SUBMIT_FINAL_ACCUSATION', request_hash);
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'FINAL_ACCUSATIONS'
    or exists (select 1 from app_private.scoring_snapshots where room_id = target_room_id)
  then
    raise exception using errcode = '55000', message = 'final-case intake is closed';
  end if;
  select candidate.* into strict accusation
  from app_private.final_accusations as candidate
  where candidate.room_id = target_room_id and candidate.player_id = authorized_player_id
  for update;
  if accusation.status <> 'DRAFT' then
    raise exception using errcode = '55000', message = 'final accusation is already submitted';
  end if;

  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object(
    'accusationId', accusation.id, 'status', 'SUBMITTED',
    'stateVersion', next_version::text, 'replayed', false
  );
  perform app_private.record_command(
    receipt_id, target_room_id, idempotency_key, 'SUBMIT_FINAL_ACCUSATION',
    'PLAYER', auth.uid(), authorized_player_id, request_hash,
    expected_state_version, next_version, result, 'FINAL_ACCUSATION_SUBMITTED',
    accusation.id, 'ENDGAME_CHANGED'
  );
  set constraints all deferred;
  update app_private.final_accusation_suspects
  set accusation_revision = accusation.revision + 1
  where accusation_id = accusation.id;
  update app_private.final_accusation_evidence
  set accusation_revision = accusation.revision + 1
  where accusation_id = accusation.id;
  update app_private.final_accusations
  set status = 'SUBMITTED', revision = revision + 1,
    submitted_state_version = next_version,
    submission_command_receipt_id = receipt_id,
    submitted_at = app_private.current_database_time(),
    updated_at = app_private.current_database_time()
  where id = accusation.id;
  update app_private.rooms
  set state_version = next_version, updated_at = app_private.current_database_time()
  where id = target_room_id;
  return result;
end;
$function$;

revoke all on function app_private.validate_final_case(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.open_final_accusations(uuid, bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.save_final_accusation(uuid, bigint, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.submit_final_accusation(uuid, bigint, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.open_final_accusations(uuid, bigint, uuid) to authenticated;
grant execute on function public.save_final_accusation(uuid, bigint, jsonb, text) to authenticated;
grant execute on function public.submit_final_accusation(uuid, bigint, uuid) to authenticated;

create function app_private.score_frozen_endgame(
  target_room_id uuid,
  target_story_id uuid,
  target_snapshot_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  solution jsonb;
  profile jsonb;
  profile_version text;
  accusation record;
  theory record;
  correct_murderers integer;
  incorrect_murderers integer;
  correct_accomplices integer;
  incorrect_accomplices integer;
  correct_evidence integer;
  exact_murderer_set boolean;
  motive_correct boolean;
  method_correct boolean;
  qualifying boolean;
  early_bonus integer;
  round_count integer;
  theory_round integer;
  score jsonb;
  innocent_count integer;
  innocents_win boolean;
  winner_id uuid;
begin
  select canonical.solution_json into strict solution
  from app_private.canonical_solutions as canonical
  where canonical.room_id = target_room_id and canonical.story_id = target_story_id;
  select scoring.profile_json, scoring.profile_version into strict profile, profile_version
  from app_private.scoring_profiles as scoring
  join app_private.rooms as room on room.scoring_profile_version = scoring.profile_version
  where room.id = target_room_id;
  select pg_catalog.count(*)::integer into round_count
  from app_private.story_rounds where room_id = target_room_id;

  for theory in
    select submitted.*
    from app_private.player_theories as submitted
    where submitted.room_id = target_room_id
    order by submitted.submitted_at, submitted.id
  loop
    select
      pg_catalog.count(*) filter (
        where solution -> 'murdererPlayerIds' @> pg_catalog.jsonb_build_array(suspect.suspect_player_id::text)
      )::integer,
      pg_catalog.count(*) filter (
        where not (solution -> 'murdererPlayerIds' @> pg_catalog.jsonb_build_array(suspect.suspect_player_id::text))
      )::integer
    into correct_murderers, incorrect_murderers
    from app_private.player_theory_suspects as suspect
    where suspect.theory_id = theory.id and suspect.suspected_role = 'MURDERER';
    select pg_catalog.count(*)::integer into correct_evidence
    from app_private.player_theory_evidence as selected
    join app_private.evidence as evidence
      on evidence.room_id = selected.room_id and evidence.id = selected.evidence_id
    where selected.theory_id = theory.id and evidence.is_required;
    select round.sequence into strict theory_round
    from app_private.story_rounds as round where round.id = theory.round_id;
    qualifying := correct_murderers = pg_catalog.jsonb_array_length(solution -> 'murdererPlayerIds')
      and incorrect_murderers = 0
      and correct_evidence >= (profile #>> '{earlyDeduction,qualifyingEvidenceMinimum}')::integer;
    early_bonus := case when qualifying then least(
      (profile #>> '{earlyDeduction,maximumBonus}')::integer,
      (profile #>> '{earlyDeduction,pointsPerRemainingRound}')::integer
        * (round_count - theory_round + 1)
    ) else 0 end;
    insert into app_private.theory_scores (
      room_id, story_id, scoring_snapshot_id, theory_id, player_id,
      points, breakdown_json, explanation
    ) values (
      target_room_id, target_story_id, target_snapshot_id, theory.id,
      theory.player_id, early_bonus,
      pg_catalog.jsonb_build_object(
        'qualifying', qualifying, 'completeMurdererSet',
        correct_murderers = pg_catalog.jsonb_array_length(solution -> 'murdererPlayerIds') and incorrect_murderers = 0,
        'correctEvidenceCount', correct_evidence, 'roundSequence', theory_round,
        'remainingRoundBonus', early_bonus
      ),
      case when qualifying
        then 'Qualified early deduction from a complete, evidence-backed theory.'
        else 'Theory did not satisfy every early-deduction requirement.' end
    );
  end loop;

  for accusation in
    select final_case.*
    from app_private.final_accusations as final_case
    where final_case.room_id = target_room_id and final_case.status = 'SUBMITTED'
    order by final_case.submitted_at, final_case.id
  loop
    select
      pg_catalog.count(*) filter (
        where solution -> 'murdererPlayerIds' @> pg_catalog.jsonb_build_array(item.value)
      )::integer,
      pg_catalog.count(*) filter (
        where not (solution -> 'murdererPlayerIds' @> pg_catalog.jsonb_build_array(item.value))
      )::integer
    into correct_murderers, incorrect_murderers
    from pg_catalog.jsonb_array_elements_text(accusation.structured_case_json -> 'murdererPlayerIds') as item;
    select
      pg_catalog.count(*) filter (
        where solution -> 'accomplicePlayerIds' @> pg_catalog.jsonb_build_array(item.value)
      )::integer,
      pg_catalog.count(*) filter (
        where not (solution -> 'accomplicePlayerIds' @> pg_catalog.jsonb_build_array(item.value))
      )::integer
    into correct_accomplices, incorrect_accomplices
    from pg_catalog.jsonb_array_elements_text(accusation.structured_case_json -> 'accomplicePlayerIds') as item;
    select pg_catalog.count(*)::integer into correct_evidence
    from pg_catalog.jsonb_array_elements_text(accusation.structured_case_json -> 'evidenceIds') as item
    join app_private.evidence as evidence
      on evidence.room_id = target_room_id and evidence.id = item.value::uuid
    where evidence.is_required;
    exact_murderer_set := correct_murderers = pg_catalog.jsonb_array_length(solution -> 'murdererPlayerIds')
      and incorrect_murderers = 0;
    motive_correct := pg_catalog.lower(pg_catalog.btrim(accusation.structured_case_json ->> 'motive'))
      = pg_catalog.lower(pg_catalog.btrim(solution ->> 'motive'));
    method_correct := pg_catalog.lower(pg_catalog.btrim(accusation.structured_case_json ->> 'method'))
      = pg_catalog.lower(pg_catalog.btrim(solution ->> 'method'));
    select coalesce(theory_score.points, 0) into early_bonus
    from app_private.theory_scores as theory_score
    join app_private.player_theories as submitted on submitted.id = theory_score.theory_id
    where theory_score.scoring_snapshot_id = target_snapshot_id
      and theory_score.player_id = accusation.player_id and theory_score.points > 0
    order by submitted.submitted_at, submitted.id limit 1;
    early_bonus := coalesce(early_bonus, 0);
    score := app_private.calculate_player_score(
      profile_version, correct_murderers, incorrect_murderers, exact_murderer_set,
      correct_accomplices, incorrect_accomplices, motive_correct,
      method_correct, correct_evidence, early_bonus
    );
    insert into app_private.player_scores (
      room_id, story_id, scoring_snapshot_id, player_id,
      final_accusation_id, total_points, breakdown_json, explanation
    ) values (
      target_room_id, target_story_id, target_snapshot_id, accusation.player_id,
      accusation.id, (score ->> 'totalPoints')::integer,
      score -> 'breakdown',
      pg_catalog.format(
        '%s correct murderer(s), %s incorrect; motive %s; method %s; %s correct evidence item(s); %s early points.',
        correct_murderers, incorrect_murderers,
        case when motive_correct then 'correct' else 'incorrect' end,
        case when method_correct then 'correct' else 'incorrect' end,
        correct_evidence, early_bonus
      )
    );
  end loop;

  select pg_catalog.count(*)::integer into innocent_count
  from app_private.dossiers where room_id = target_room_id and faction = 'INNOCENT';
  innocents_win := not exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(solution -> 'murdererPlayerIds') as murderer
    where (
      select pg_catalog.count(*)
      from app_private.final_accusations as final_case
      join app_private.dossiers as dossier
        on dossier.room_id = final_case.room_id and dossier.player_id = final_case.player_id
      where final_case.room_id = target_room_id
        and final_case.status = 'SUBMITTED' and dossier.faction = 'INNOCENT'
        and final_case.structured_case_json -> 'murdererPlayerIds'
          @> pg_catalog.jsonb_build_array(murderer.value)
    ) <= innocent_count / 2
  );
  insert into app_private.faction_results (
    room_id, story_id, scoring_snapshot_id, faction, won, result_json, explanation
  ) values
    (target_room_id, target_story_id, target_snapshot_id, 'INNOCENT', innocents_win,
      pg_catalog.jsonb_build_object('threshold','STRICT_MAJORITY_OF_ALL_INNOCENTS','innocentCount',innocent_count),
      case when innocents_win then 'Every murderer was identified by a strict majority of all innocents.' else 'At least one murderer escaped the required innocent majority.' end),
    (target_room_id, target_story_id, target_snapshot_id, 'MURDERER', not innocents_win,
      pg_catalog.jsonb_build_object('winsWhenAnyMurdererEscapes',true),
      case when innocents_win then 'Every murderer was identified.' else 'At least one murderer escaped identification.' end),
    (target_room_id, target_story_id, target_snapshot_id, 'ACCOMPLICE', not innocents_win,
      pg_catalog.jsonb_build_object('sharesMurdererOutcome',true),
      case when innocents_win then 'The accomplice faction shares the murderer defeat.' else 'The accomplice faction shares the murderer victory.' end);

  select score_row.player_id into winner_id
  from app_private.player_scores as score_row
  join app_private.final_accusations as final_case on final_case.id = score_row.final_accusation_id
  join app_private.players as player on player.id = score_row.player_id
  where score_row.scoring_snapshot_id = target_snapshot_id
  order by score_row.total_points desc, final_case.submitted_at, player.seat_order limit 1;
  if winner_id is not null then
    insert into app_private.player_awards (
      room_id, story_id, scoring_snapshot_id, player_id,
      award_code, title, description, award_json
    ) values (
      target_room_id, target_story_id, target_snapshot_id, winner_id,
      'MASTER_DETECTIVE', 'Master Detective',
      'Highest deterministic final-case score.', '{}'::jsonb
    );
  end if;

  winner_id := null;
  select theory_score.player_id into winner_id
  from app_private.theory_scores as theory_score
  join app_private.player_theories as submitted on submitted.id = theory_score.theory_id
  join app_private.story_rounds as round on round.id = submitted.round_id
  join app_private.players as player on player.id = theory_score.player_id
  where theory_score.scoring_snapshot_id = target_snapshot_id and theory_score.points > 0
  order by round.sequence, submitted.submitted_at, player.seat_order limit 1;
  if winner_id is not null then
    insert into app_private.player_awards (
      room_id, story_id, scoring_snapshot_id, player_id,
      award_code, title, description, award_json
    ) values (
      target_room_id, target_story_id, target_snapshot_id, winner_id,
      'EARLIEST_BREAKTHROUGH', 'Earliest Breakthrough',
      'Earliest complete evidence-backed submitted theory.', '{}'::jsonb
    );
  end if;

  winner_id := null;
  select score_row.player_id into winner_id
  from app_private.player_scores as score_row
  join app_private.players as player on player.id = score_row.player_id
  where score_row.scoring_snapshot_id = target_snapshot_id
  order by (score_row.breakdown_json ->> 'evidence')::integer desc,
    score_row.total_points desc, player.seat_order limit 1;
  if winner_id is not null then
    insert into app_private.player_awards (
      room_id, story_id, scoring_snapshot_id, player_id,
      award_code, title, description, award_json
    ) values (
      target_room_id, target_story_id, target_snapshot_id, winner_id,
      'EVIDENCE_HOUND', 'Evidence Hound',
      'Strongest correct supporting-evidence score.', '{}'::jsonb
    );
  end if;
end;
$function$;

create function public.close_final_accusations(
  target_room_id uuid,
  expected_state_version bigint,
  idempotency_key uuid,
  confirmed_missing_player_ids uuid[],
  confirm_zero_submissions boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  story_record app_private.canonical_stories%rowtype;
  profile_record app_private.scoring_profiles%rowtype;
  receipt_id uuid := pg_catalog.gen_random_uuid();
  snapshot_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  actual_missing uuid[];
  confirmed_missing uuid[];
  submission_count integer;
  frozen_input jsonb;
  frozen_checksum bytea;
  last_event bigint;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash(
    'CLOSE_FINAL_ACCUSATIONS',
    pg_catalog.jsonb_build_object(
      'confirmedMissingPlayerIds', coalesce(confirmed_missing_player_ids, '{}'::uuid[]),
      'confirmZeroSubmissions', confirm_zero_submissions
    )
  );
  replay := app_private.command_replay(target_room_id, idempotency_key, 'CLOSE_FINAL_ACCUSATIONS', request_hash);
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'FINAL_ACCUSATIONS' then
    raise exception using errcode = '55000', message = 'final-case intake is not open';
  end if;
  if exists (select 1 from app_private.scoring_snapshots where room_id = target_room_id) then
    raise exception using errcode = '55000', message = 'final-case scoring is already frozen';
  end if;

  select coalesce(pg_catalog.array_agg(player.id order by player.id), '{}'::uuid[])
  into actual_missing
  from app_private.players as player
  where player.room_id = target_room_id and not exists (
    select 1 from app_private.final_accusations as final_case
    where final_case.room_id = target_room_id and final_case.player_id = player.id
      and final_case.status = 'SUBMITTED'
  );
  select coalesce(pg_catalog.array_agg(item order by item), '{}'::uuid[])
  into confirmed_missing from pg_catalog.unnest(coalesce(confirmed_missing_player_ids, '{}'::uuid[])) as item;
  if actual_missing <> confirmed_missing then
    raise exception using errcode = '22023', message = 'missing-player confirmation does not match current submissions';
  end if;
  select pg_catalog.count(*)::integer into submission_count
  from app_private.final_accusations
  where room_id = target_room_id and status = 'SUBMITTED';
  if submission_count = 0 and not confirm_zero_submissions then
    raise exception using errcode = '22023', message = 'closing with zero submissions requires explicit second confirmation';
  end if;

  select story.* into strict story_record
  from app_private.canonical_stories as story where story.id = room_record.story_id;
  select scoring.* into strict profile_record
  from app_private.scoring_profiles as scoring
  where scoring.profile_version = room_record.scoring_profile_version;
  select coalesce(pg_catalog.max(event.room_sequence), 0) into last_event
  from app_private.game_events as event where event.room_id = target_room_id;
  frozen_input := pg_catalog.jsonb_build_object(
    'schemaVersion', 'endgame-input-v1',
    'roomId', target_room_id, 'storyId', room_record.story_id,
    'sourceStateVersion', room_record.state_version,
    'sourceLastEventSequence', last_event,
    'players', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'playerId', player.id, 'seatOrder', player.seat_order,
        'faction', dossier.faction::text, 'submitted', final_case.id is not null
      ) order by player.seat_order)
      from app_private.players as player
      join app_private.dossiers as dossier on dossier.room_id = player.room_id and dossier.player_id = player.id
      left join app_private.final_accusations as final_case
        on final_case.room_id = player.room_id and final_case.player_id = player.id and final_case.status = 'SUBMITTED'
      where player.room_id = target_room_id
    ), '[]'::jsonb),
    'submittedAccusations', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', final_case.id, 'playerId', final_case.player_id,
        'case', final_case.structured_case_json,
        'explanation', final_case.explanation_text,
        'submittedAt', final_case.submitted_at
      ) order by final_case.submitted_at, final_case.id)
      from app_private.final_accusations as final_case
      where final_case.room_id = target_room_id and final_case.status = 'SUBMITTED'
    ), '[]'::jsonb),
    'submittedTheories', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', theory.id, 'playerId', theory.player_id, 'roundId', theory.round_id,
        'claim', theory.structured_claim_json,
        'explanation', theory.submitted_explanation,
        'submittedAt', theory.submitted_at
      ) order by theory.submitted_at, theory.id)
      from app_private.player_theories as theory where theory.room_id = target_room_id
    ), '[]'::jsonb),
    'releasedEvidence', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'evidenceId', release.evidence_id, 'releasedAt', release.released_at,
        'reason', release.release_reason
      ) order by release.released_at, release.id)
      from app_private.evidence_releases as release where release.room_id = target_room_id
    ), '[]'::jsonb)
  );
  frozen_checksum := extensions.digest(pg_catalog.convert_to(frozen_input::text, 'UTF8'), 'sha256');
  insert into app_private.scoring_snapshots (
    id, room_id, story_id, scoring_profile_version,
    scoring_profile_checksum, story_package_checksum, solution_checksum,
    frozen_input_checksum, source_state_version, source_last_event_sequence,
    frozen_input_json
  ) values (
    snapshot_id, target_room_id, room_record.story_id,
    room_record.scoring_profile_version, profile_record.checksum,
    story_record.package_checksum, story_record.solution_checksum,
    frozen_checksum, room_record.state_version, last_event, frozen_input
  );
  perform app_private.score_frozen_endgame(target_room_id, room_record.story_id, snapshot_id);

  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object(
    'roomId', target_room_id, 'status', 'SCORED',
    'scoringSnapshotId', snapshot_id, 'submissionCount', submission_count,
    'missingPlayerIds', actual_missing,
    'stateVersion', next_version::text, 'replayed', false
  );
  perform app_private.record_command(
    receipt_id, target_room_id, idempotency_key, 'CLOSE_FINAL_ACCUSATIONS',
    'GAME_MASTER', auth.uid(), null, request_hash, expected_state_version,
    next_version, result, 'FINAL_ACCUSATIONS_CLOSED', snapshot_id,
    'ENDGAME_CHANGED'
  );
  update app_private.rooms set state_version = next_version,
    updated_at = app_private.current_database_time() where id = target_room_id;
  return result;
end;
$function$;

revoke all on function app_private.score_frozen_endgame(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.close_final_accusations(uuid, bigint, uuid, uuid[], boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.close_final_accusations(uuid, bigint, uuid, uuid[], boolean)
  to authenticated;

create or replace function app_private.build_shared_reveal(target_room_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'solution', (
      select pg_catalog.jsonb_build_object(
        'victim', solution.victim_json,
        'canonicalSolution', solution.solution_json
      )
      from app_private.canonical_solutions as solution
      where solution.room_id = target_room_id
    ),
    'sections', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', section.id, 'sequence', section.sequence,
        'kind', section.section_kind, 'content', section.section_json
      ) order by section.sequence)
      from app_private.final_reveal_sections as section
      where section.room_id = target_room_id
    ), '[]'::jsonb),
    'factionResults', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'faction', result.faction::text, 'won', result.won,
        'result', result.result_json, 'explanation', result.explanation
      ) order by result.faction::text)
      from app_private.faction_results as result where result.room_id = target_room_id
    ), '[]'::jsonb),
    'playerScores', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'playerId', ranked.player_id, 'displayName', ranked.display_name,
        'submitted', ranked.submitted, 'totalPoints', ranked.total_points,
        'rank', ranked.shared_rank, 'breakdown', ranked.breakdown,
        'explanation', ranked.explanation
      ) order by ranked.shared_rank, ranked.seat_order)
      from (
        select player.id as player_id, player.display_name, player.seat_order,
          score.id is not null as submitted, coalesce(score.total_points, 0) as total_points,
          pg_catalog.rank() over (order by coalesce(score.total_points, 0) desc) as shared_rank,
          coalesce(score.breakdown_json, '{}'::jsonb) as breakdown,
          coalesce(score.explanation, 'No final case was submitted; zero points and no faction vote.') as explanation
        from app_private.players as player
        left join app_private.player_scores as score
          on score.room_id = player.room_id and score.player_id = player.id
        where player.room_id = target_room_id
      ) as ranked
    ), '[]'::jsonb),
    'awards', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'playerId', award.player_id, 'displayName', player.display_name,
        'code', award.award_code, 'title', award.title,
        'description', award.description, 'details', award.award_json
      ) order by award.award_code)
      from app_private.player_awards as award
      join app_private.players as player on player.id = award.player_id
      where award.room_id = target_room_id
    ), '[]'::jsonb),
    'submittedAccusations', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'playerId', accusation.player_id, 'displayName', player.display_name,
        'case', accusation.structured_case_json,
        'explanation', accusation.explanation_text,
        'submittedAt', accusation.submitted_at
      ) order by player.seat_order)
      from app_private.final_accusations as accusation
      join app_private.players as player on player.id = accusation.player_id
      where accusation.room_id = target_room_id and accusation.status = 'SUBMITTED'
    ), '[]'::jsonb)
  );
$function$;

create function public.publish_reveal(
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
  story_record app_private.canonical_stories%rowtype;
  snapshot app_private.scoring_snapshots%rowtype;
  receipt_id uuid := pg_catalog.gen_random_uuid();
  publication_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  payload jsonb;
  reveal_checksum bytea;
  next_version bigint;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash('PUBLISH_REVEAL', '{}'::jsonb);
  replay := app_private.command_replay(target_room_id, idempotency_key, 'PUBLISH_REVEAL', request_hash);
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'FINAL_ACCUSATIONS' then
    raise exception using errcode = '55000', message = 'room is not ready to reveal';
  end if;
  select frozen.* into strict snapshot
  from app_private.scoring_snapshots as frozen where frozen.room_id = target_room_id;
  select story.* into strict story_record
  from app_private.canonical_stories as story where story.id = room_record.story_id;
  payload := app_private.build_shared_reveal(target_room_id);
  reveal_checksum := extensions.digest(pg_catalog.convert_to(payload::text, 'UTF8'), 'sha256');
  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object(
    'roomId', target_room_id, 'status', 'REVEAL',
    'revealPublicationId', publication_id,
    'stateVersion', next_version::text, 'replayed', false
  );
  perform app_private.record_command(
    receipt_id, target_room_id, idempotency_key, 'PUBLISH_REVEAL',
    'GAME_MASTER', auth.uid(), null, request_hash, expected_state_version,
    next_version, result, 'REVEAL_PUBLISHED', publication_id, 'ENDGAME_CHANGED'
  );
  insert into app_private.reveal_publications (
    id, room_id, story_id, scoring_snapshot_id, command_receipt_id,
    publication_state_version, scoring_profile_version,
    scoring_profile_checksum, story_package_checksum, solution_checksum,
    frozen_input_checksum, reveal_checksum, published_payload_json
  ) values (
    publication_id, target_room_id, room_record.story_id, snapshot.id,
    receipt_id, next_version, snapshot.scoring_profile_version,
    snapshot.scoring_profile_checksum, story_record.package_checksum,
    story_record.solution_checksum, snapshot.frozen_input_checksum,
    reveal_checksum, payload
  );
  update app_private.rooms set status = 'REVEAL', state_version = next_version,
    updated_at = app_private.current_database_time() where id = target_room_id;
  return result;
end;
$function$;

create function public.complete_room(
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
  story_record app_private.canonical_stories%rowtype;
  snapshot app_private.scoring_snapshots%rowtype;
  publication app_private.reveal_publications%rowtype;
  case_file_id uuid := pg_catalog.gen_random_uuid();
  receipt_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  content jsonb;
  content_checksum bytea;
  completion_time timestamp with time zone := app_private.current_database_time();
  expiration_time timestamp with time zone;
  next_version bigint;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash('COMPLETE_ROOM', '{}'::jsonb);
  replay := app_private.command_replay(target_room_id, idempotency_key, 'COMPLETE_ROOM', request_hash);
  if replay is not null then return replay; end if;
  select room.* into strict room_record from app_private.rooms as room where room.id = target_room_id;
  if room_record.state_version <> expected_state_version then
    raise exception using errcode = '40001', message = 'stale room state version';
  end if;
  if room_record.status <> 'REVEAL' then
    raise exception using errcode = '55000', message = 'reveal must be published before completion';
  end if;
  select story.* into strict story_record
  from app_private.canonical_stories as story where story.id = room_record.story_id;
  select frozen.* into strict snapshot
  from app_private.scoring_snapshots as frozen where frozen.room_id = target_room_id;
  select reveal.* into strict publication
  from app_private.reveal_publications as reveal where reveal.room_id = target_room_id;
  expiration_time := completion_time + interval '30 days';

  content := pg_catalog.jsonb_build_object(
    'schemaVersion', 'case-file-v1',
    'roomId', target_room_id, 'storyId', room_record.story_id,
    'canonicalStory', story_record.package_json,
    'runtime', pg_catalog.jsonb_build_object(
      'missions', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'mission', pg_catalog.to_jsonb(spec) - 'room_id' - 'story_id',
          'state', pg_catalog.to_jsonb(state) - 'room_id' - 'story_id'
        ) order by round.sequence, player.seat_order)
        from app_private.mission_specs as spec
        join app_private.mission_states as state on state.mission_spec_id = spec.id
        join app_private.story_rounds as round on round.id = spec.round_id
        join app_private.players as player on player.id = spec.assigned_player_id
        where spec.room_id = target_room_id
      ), '[]'::jsonb),
      'evidenceReleases', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(release) - 'room_id' - 'story_id' order by release.released_at, release.id)
        from app_private.evidence_releases as release where release.room_id = target_room_id
      ), '[]'::jsonb),
      'consequences', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'spec', pg_catalog.to_jsonb(spec) - 'room_id' - 'story_id',
          'state', pg_catalog.to_jsonb(state) - 'room_id' - 'story_id'
        ) order by spec.severity, spec.id)
        from app_private.consequence_specs as spec
        left join app_private.consequence_states as state on state.consequence_spec_id = spec.id
        where spec.room_id = target_room_id
      ), '[]'::jsonb),
      'interventions', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'request', pg_catalog.to_jsonb(request) - 'room_id' - 'context',
          'preview', pg_catalog.to_jsonb(preview) - 'room_id',
          'release', pg_catalog.to_jsonb(release) - 'room_id'
        ) order by request.requested_at)
        from app_private.intervention_requests as request
        left join app_private.intervention_previews as preview on preview.request_id = request.id
        left join app_private.intervention_releases as release on release.request_id = request.id
        where request.room_id = target_room_id
      ), '[]'::jsonb),
      'events', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(event) - 'room_id' - 'private_payload_json'
          order by event.room_sequence
        ) from app_private.game_events as event where event.room_id = target_room_id
      ), '[]'::jsonb)
    ),
    'submittedTheories', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'theory', pg_catalog.to_jsonb(theory) - 'room_id' - 'story_id',
        'score', pg_catalog.to_jsonb(score) - 'room_id' - 'story_id'
      ) order by theory.submitted_at, theory.id)
      from app_private.player_theories as theory
      left join app_private.theory_scores as score on score.theory_id = theory.id
      where theory.room_id = target_room_id
    ), '[]'::jsonb),
    'submittedFinalAccusations', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(final_case) - 'room_id' - 'story_id' order by final_case.submitted_at, final_case.id)
      from app_private.final_accusations as final_case
      where final_case.room_id = target_room_id and final_case.status = 'SUBMITTED'
    ), '[]'::jsonb),
    'results', publication.published_payload_json,
    'scoringSnapshot', pg_catalog.jsonb_build_object(
      'id', snapshot.id, 'profileVersion', snapshot.scoring_profile_version,
      'frozenInputChecksum', pg_catalog.encode(snapshot.frozen_input_checksum, 'hex')
    ),
    'completedAt', completion_time, 'expiresAt', expiration_time
  );
  content_checksum := extensions.digest(pg_catalog.convert_to(content::text, 'UTF8'), 'sha256');
  insert into app_private.case_files (
    id, room_id, story_id, scoring_snapshot_id, reveal_publication_id,
    case_file_schema_version, scoring_profile_version,
    scoring_profile_checksum, story_package_checksum, solution_checksum,
    frozen_input_checksum, reveal_checksum, content_checksum, content_json,
    finalized_at
  ) values (
    case_file_id, target_room_id, room_record.story_id, snapshot.id,
    publication.id, 'case-file-v1', snapshot.scoring_profile_version,
    snapshot.scoring_profile_checksum, snapshot.story_package_checksum,
    snapshot.solution_checksum, snapshot.frozen_input_checksum,
    publication.reveal_checksum, content_checksum, content, completion_time
  );
  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object(
    'roomId', target_room_id, 'status', 'COMPLETED',
    'caseFileId', case_file_id, 'completedAt', completion_time,
    'expiresAt', expiration_time, 'stateVersion', next_version::text,
    'replayed', false
  );
  perform app_private.record_command(
    receipt_id, target_room_id, idempotency_key, 'COMPLETE_ROOM',
    'GAME_MASTER', auth.uid(), null, request_hash, expected_state_version,
    next_version, result, 'ROOM_COMPLETED', case_file_id, 'ENDGAME_CHANGED'
  );
  update app_private.rooms set status = 'COMPLETED', state_version = next_version,
    completed_at = completion_time, expires_at = expiration_time, updated_at = completion_time
  where id = target_room_id;
  return result;
end;
$function$;

revoke all on function public.publish_reveal(uuid, bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_room(uuid, bigint, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_reveal(uuid, bigint, uuid) to authenticated;
grant execute on function public.complete_room(uuid, bigint, uuid) to authenticated;
