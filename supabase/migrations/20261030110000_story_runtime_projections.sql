-- DB-11: actor-scoped views and content-free signal authorization.

create function app_private.audience_allows_player(
  audience jsonb,
  target_player_id uuid
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $function$
  select
    pg_catalog.lower(
      coalesce(
        audience ->> 'visibility',
        audience ->> 'kind',
        ''
      )
    ) in ('public', 'all_players')
    or audience ->> 'public' = 'true'
    or audience ->> 'targetPlayerId' = target_player_id::text
    or coalesce(
      audience -> 'playerIds' @> pg_catalog.jsonb_build_array(target_player_id::text),
      false
    );
$function$;

create function app_private.build_shared_reveal(target_room_id uuid)
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
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', section.id,
          'sequence', section.sequence,
          'kind', section.section_kind,
          'content', section.section_json
        ) order by section.sequence
      )
      from app_private.final_reveal_sections as section
      where section.room_id = target_room_id
    ), '[]'::jsonb),
    'factionResults', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'faction', result.faction::text,
          'won', result.won,
          'result', result.result_json,
          'explanation', result.explanation
        ) order by result.faction::text
      )
      from app_private.faction_results as result
      where result.room_id = target_room_id
    ), '[]'::jsonb),
    'playerScores', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'playerId', score.player_id,
          'displayName', player.display_name,
          'totalPoints', score.total_points,
          'breakdown', score.breakdown_json,
          'explanation', score.explanation
        ) order by player.seat_order
      )
      from app_private.player_scores as score
      join app_private.players as player
        on player.room_id = score.room_id and player.id = score.player_id
      where score.room_id = target_room_id
    ), '[]'::jsonb),
    'awards', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'playerId', award.player_id,
          'displayName', player.display_name,
          'code', award.award_code,
          'title', award.title,
          'description', award.description,
          'details', award.award_json
        ) order by award.award_code
      )
      from app_private.player_awards as award
      join app_private.players as player
        on player.room_id = award.room_id and player.id = award.player_id
      where award.room_id = target_room_id
    ), '[]'::jsonb),
    'submittedAccusations', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'playerId', accusation.player_id,
          'displayName', player.display_name,
          'case', accusation.structured_case_json,
          'explanation', accusation.explanation_text,
          'submittedAt', accusation.submitted_at
        ) order by player.seat_order
      )
      from app_private.final_accusations as accusation
      join app_private.players as player
        on player.room_id = accusation.room_id
        and player.id = accusation.player_id
      where accusation.room_id = target_room_id
        and accusation.status = 'SUBMITTED'
    ), '[]'::jsonb)
  );
$function$;

create function public.get_game_master_view(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  story_record app_private.canonical_stories%rowtype;
  result jsonb;
begin
  perform app_private.assert_current_game_master(target_room_id);

  select room.* into strict room_record
  from app_private.rooms as room
  where room.id = target_room_id;

  result := pg_catalog.jsonb_build_object(
    'actor', 'GAME_MASTER',
    'room', pg_catalog.jsonb_build_object(
      'id', room_record.id,
      'roomCode', room_record.room_code,
      'status', room_record.status::text,
      'stateVersion', room_record.state_version,
      'config', room_record.config_json,
      'storyId', room_record.story_id,
      'currentRoundId', room_record.current_round_id,
      'lockedAt', room_record.locked_at,
      'completedAt', room_record.completed_at,
      'expiresAt', room_record.expires_at
    ),
    'players', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', player.id,
          'displayName', player.display_name,
          'costume', player.costume,
          'seatOrder', player.seat_order,
          'claimStatus', case
            when active_membership.id is not null then
              case
                when active_membership.last_seen_at is not null
                  and active_membership.last_seen_at
                    >= app_private.current_database_time()
                      - interval '90 seconds'
                  then 'CONNECTED'
                else 'DISCONNECTED'
              end
            when pending_membership.id is not null then 'PENDING'
            else 'UNCLAIMED'
          end
        ) order by player.seat_order
      )
      from app_private.players as player
      left join lateral (
        select membership.id, membership.last_seen_at
        from app_private.room_memberships as membership
        where membership.room_id = player.room_id
          and membership.player_id = player.id
          and membership.status = 'ACTIVE'
        limit 1
      ) as active_membership on true
      left join lateral (
        select membership.id
        from app_private.room_memberships as membership
        where membership.room_id = player.room_id
          and membership.player_id = player.id
          and membership.status = 'PENDING'
        order by membership.created_at
        limit 1
      ) as pending_membership on true
      where player.room_id = target_room_id
    ), '[]'::jsonb),
    'claims', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', membership.id,
          'playerId', membership.player_id,
          'status', membership.status::text,
          'requestKind', membership.request_kind::text,
          'replacesMembershipId', membership.replaces_membership_id,
          'createdAt', membership.created_at,
          'joinedAt', membership.joined_at,
          'revokedAt', membership.revoked_at,
          'lastSeenAt', membership.last_seen_at
        ) order by membership.created_at
      )
      from app_private.room_memberships as membership
      where membership.room_id = target_room_id
    ), '[]'::jsonb),
    'readiness', (
      select pg_catalog.to_jsonb(readiness)
      from app_private.room_readiness_inputs as readiness
      where readiness.room_id = target_room_id
    ),
    'generation', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', job.id,
          'status', job.status::text,
          'phase', job.phase::text,
          'attemptCount', job.attempt_count,
          'repairCount', job.repair_count,
          'escalationCount', job.escalation_count,
          'modelId', job.model_id,
          'sanitizedErrorCode', job.sanitized_error_code,
          'createdAt', job.created_at,
          'startedAt', job.started_at,
          'finishedAt', job.finished_at
        ) order by job.created_at desc
      )
      from app_private.story_generation_jobs as job
      where job.room_id = target_room_id
    ), '[]'::jsonb)
  );

  if room_record.locked_at is null or room_record.story_id is null then
    return result;
  end if;

  select story.* into strict story_record
  from app_private.canonical_stories as story
  where story.room_id = target_room_id
    and story.id = room_record.story_id;

  return result || pg_catalog.jsonb_build_object(
    'story', pg_catalog.jsonb_build_object(
      'id', story_record.id,
      'schemaVersion', story_record.story_schema_version,
      'scoringProfileVersion', story_record.scoring_profile_version,
      'promptVersion', story_record.prompt_version,
      'modelId', story_record.model_id,
      'package', story_record.package_json,
      'packageChecksum', pg_catalog.encode(story_record.package_checksum, 'hex'),
      'solutionChecksum', pg_catalog.encode(story_record.solution_checksum, 'hex'),
      'lockedAt', story_record.locked_at,
      'solution', (
        select pg_catalog.jsonb_build_object(
          'victim', solution.victim_json,
          'canonicalSolution', solution.solution_json
        )
        from app_private.canonical_solutions as solution
        where solution.room_id = target_room_id
          and solution.story_id = story_record.id
      )
    ),
    'runtime', pg_catalog.jsonb_build_object(
      'missions', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(state) - 'room_id' order by state.created_at
        )
        from app_private.mission_states as state
        where state.room_id = target_room_id
      ), '[]'::jsonb),
      'evidenceReleases', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(release) - 'room_id' order by release.released_at
        )
        from app_private.evidence_releases as release
        where release.room_id = target_room_id
      ), '[]'::jsonb),
      'consequences', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(state) - 'room_id' order by state.eligible_at
        )
        from app_private.consequence_states as state
        where state.room_id = target_room_id
      ), '[]'::jsonb),
      'interventionRequests', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(request) - 'room_id' order by request.requested_at
        )
        from app_private.intervention_requests as request
        where request.room_id = target_room_id
      ), '[]'::jsonb),
      'interventionPreviews', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(preview) - 'room_id' order by preview.created_at
        )
        from app_private.intervention_previews as preview
        where preview.room_id = target_room_id
      ), '[]'::jsonb),
      'interventionReleases', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(release) - 'room_id' order by release.released_at
        )
        from app_private.intervention_releases as release
        where release.room_id = target_room_id
      ), '[]'::jsonb),
      'effects', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(effect) - 'room_id' order by effect.applied_at
        )
        from app_private.runtime_effects as effect
        where effect.room_id = target_room_id
      ), '[]'::jsonb),
      'events', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(event) - 'room_id' order by event.room_sequence
        )
        from app_private.game_events as event
        where event.room_id = target_room_id
      ), '[]'::jsonb)
    ),
    'submittedState', pg_catalog.jsonb_build_object(
      'theories', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(theory) - 'room_id' order by theory.submitted_at
        )
        from app_private.player_theories as theory
        where theory.room_id = target_room_id
      ), '[]'::jsonb),
      'finalAccusations', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.to_jsonb(accusation) - 'room_id' order by accusation.submitted_at
        )
        from app_private.final_accusations as accusation
        where accusation.room_id = target_room_id
          and accusation.status = 'SUBMITTED'
      ), '[]'::jsonb)
    ),
    'results', pg_catalog.jsonb_build_object(
      'scoringSnapshot', (
        select pg_catalog.to_jsonb(snapshot) - 'room_id' - 'frozen_input_json'
        from app_private.scoring_snapshots as snapshot
        where snapshot.room_id = target_room_id
      ),
      'reveal', app_private.build_shared_reveal(target_room_id),
      'caseFile', (
        select pg_catalog.jsonb_build_object(
          'schemaVersion', case_file.case_file_schema_version,
          'content', case_file.content_json,
          'contentChecksum', pg_catalog.encode(case_file.content_checksum, 'hex'),
          'finalizedAt', case_file.finalized_at
        )
        from app_private.case_files as case_file
        where case_file.room_id = target_room_id
      )
    )
  );
end;
$function$;

create function public.get_player_view(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  authorized_player_id uuid;
  room_record app_private.rooms%rowtype;
  result jsonb;
begin
  authorized_player_id := app_private.assert_active_player(target_room_id);

  select room.* into strict room_record
  from app_private.rooms as room
  where room.id = target_room_id;

  result := pg_catalog.jsonb_build_object(
    'actor', 'PLAYER',
    'room', pg_catalog.jsonb_build_object(
      'id', room_record.id,
      'roomCode', room_record.room_code,
      'status', room_record.status::text,
      'stateVersion', room_record.state_version,
      'currentRoundId', room_record.current_round_id,
      'completedAt', room_record.completed_at,
      'expiresAt', room_record.expires_at
    ),
    'self', (
      select pg_catalog.jsonb_build_object(
        'playerId', player.id,
        'displayName', player.display_name,
        'costume', player.costume,
        'seatOrder', player.seat_order
      )
      from app_private.players as player
      where player.room_id = target_room_id
        and player.id = authorized_player_id
    ),
    'lobby', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'playerId', player.id,
          'displayName', player.display_name,
          'costume', player.costume,
          'seatOrder', player.seat_order
        ) order by player.seat_order
      )
      from app_private.players as player
      where player.room_id = target_room_id
    ), '[]'::jsonb)
  );

  if room_record.locked_at is null or room_record.story_id is null then
    return result;
  end if;

  result := result || pg_catalog.jsonb_build_object(
    'dossier', (
      select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'id', dossier.id,
        'knowledgePolicy', dossier.knowledge_policy_json,
        'content', dossier.dossier_json,
        'faction', case
          when room_record.status in ('REVEAL', 'COMPLETED')
            or coalesce((dossier.knowledge_policy_json ->> 'factionVisible')::boolean, false)
            then dossier.faction::text
          else null
        end
      ))
      from app_private.dossiers as dossier
      where dossier.room_id = target_room_id
        and dossier.player_id = authorized_player_id
    ),
    'missions', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', spec.id,
          'roundId', spec.round_id,
          'actionKind', spec.action_kind::text,
          'objective', spec.objective_text,
          'completionRule', spec.completion_rule_json,
          'stakes', spec.stakes_text,
          'successEffect', spec.success_effect_json,
          'status', state.status::text,
          'revision', state.revision,
          'deadlineAt', state.deadline_at,
          'acceptedAt', state.accepted_at,
          'completionRequestedAt', state.completion_requested_at,
          'resolvedAt', state.resolved_at
        ) order by round.sequence, spec.id
      )
      from app_private.mission_specs as spec
      join app_private.story_rounds as round
        on round.room_id = spec.room_id and round.id = spec.round_id
      left join app_private.mission_states as state
        on state.room_id = spec.room_id and state.mission_spec_id = spec.id
      where spec.room_id = target_room_id
        and spec.assigned_player_id = authorized_player_id
    ), '[]'::jsonb),
    'evidence', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', evidence.id,
          'kind', evidence.evidence_kind,
          'content', evidence.content_json,
          'audience', evidence.audience_json,
          'releasedAt', release.released_at
        ) order by release.released_at
      )
      from app_private.evidence_releases as release
      join app_private.evidence as evidence
        on evidence.room_id = release.room_id
        and evidence.story_id = release.story_id
        and evidence.id = release.evidence_id
      where release.room_id = target_room_id
        and app_private.audience_allows_player(
          evidence.audience_json,
          authorized_player_id
        )
    ), '[]'::jsonb),
    'releasedInterventions', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', release.id,
          'kind', preview.candidate_kind::text,
          'presentation', preview.preview_json,
          'releasedAt', release.released_at
        ) order by release.released_at
      )
      from app_private.intervention_releases as release
      join app_private.intervention_previews as preview
        on preview.room_id = release.room_id and preview.id = release.preview_id
      where release.room_id = target_room_id
        and app_private.audience_allows_player(
          preview.audience_json,
          authorized_player_id
        )
    ), '[]'::jsonb),
    'personalRevelations', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', spec.id,
          'content', spec.revelation_json,
          'releasedAt', state.released_at
        ) order by state.released_at
      )
      from app_private.accomplice_revelation_states as state
      join app_private.accomplice_revelations as spec
        on spec.room_id = state.room_id
        and spec.story_id = state.story_id
        and spec.id = state.revelation_spec_id
      where state.room_id = target_room_id
        and state.status = 'RELEASED'
        and spec.accomplice_player_id = authorized_player_id
    ), '[]'::jsonb),
    'events', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', event.id,
          'sequence', event.room_sequence,
          'stateVersion', event.state_version,
          'type', event.event_type,
          'metadata', event.public_metadata_json,
          'occurredAt', event.occurred_at
        ) order by event.room_sequence
      )
      from app_private.game_events as event
      where event.room_id = target_room_id
    ), '[]'::jsonb),
    'notebook', (
      select pg_catalog.jsonb_build_object(
        'id', note.id,
        'revision', note.revision,
        'notesText', note.notes_text,
        'suspects', coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'playerId', suspect.suspect_player_id,
              'suspectedRole', suspect.suspected_role::text
            ) order by suspect.suspect_player_id
          )
          from app_private.player_note_suspects as suspect
          where suspect.room_id = note.room_id
            and suspect.owner_player_id = note.player_id
        ), '[]'::jsonb)
      )
      from app_private.player_notes as note
      where note.room_id = target_room_id
        and note.player_id = authorized_player_id
    ),
    'submittedTheories', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', theory.id,
          'roundId', theory.round_id,
          'claim', theory.structured_claim_json,
          'explanation', theory.submitted_explanation,
          'submittedAt', theory.submitted_at
        ) order by theory.submitted_at
      )
      from app_private.player_theories as theory
      where theory.room_id = target_room_id
        and theory.player_id = authorized_player_id
    ), '[]'::jsonb),
    'finalAccusation', (
      select pg_catalog.jsonb_build_object(
        'id', accusation.id,
        'status', accusation.status::text,
        'revision', accusation.revision,
        'case', accusation.structured_case_json,
        'explanation', accusation.explanation_text,
        'submittedAt', accusation.submitted_at
      )
      from app_private.final_accusations as accusation
      where accusation.room_id = target_room_id
        and accusation.player_id = authorized_player_id
    )
  );

  if room_record.status in ('REVEAL', 'COMPLETED') then
    result := result || pg_catalog.jsonb_build_object(
      'reveal', app_private.build_shared_reveal(target_room_id)
    );
  end if;

  return result;
end;
$function$;

create function public.get_reveal_view(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  room_status app_private.room_state;
begin
  if not app_private.is_current_game_master(target_room_id)
    and not app_private.is_active_player(target_room_id) then
    raise exception using
      errcode = '42501',
      message = 'authorized room actor required';
  end if;

  select room.status into room_status
  from app_private.rooms as room
  where room.id = target_room_id;

  if room_status not in ('REVEAL', 'COMPLETED') then
    raise exception using
      errcode = '55000',
      message = 'reveal is not published';
  end if;

  return pg_catalog.jsonb_build_object(
    'roomId', target_room_id,
    'status', room_status::text,
    'reveal', app_private.build_shared_reveal(target_room_id)
  );
end;
$function$;

create function public.can_access_room_signals(target_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    auth.uid() is not null
    and (
      app_private.is_current_game_master(target_room_id)
      or app_private.is_active_player(target_room_id)
    );
$function$;

create policy room_signals_authorized_read
on public.room_signals
for select
to authenticated
using (public.can_access_room_signals(room_id));

grant select on table public.room_signals to authenticated;

revoke all on function public.get_game_master_view(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_player_view(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_reveal_view(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.can_access_room_signals(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.get_game_master_view(uuid) to authenticated;
grant execute on function public.get_player_view(uuid) to authenticated;
grant execute on function public.get_reveal_view(uuid) to authenticated;
grant execute on function public.can_access_room_signals(uuid) to authenticated;

revoke execute on function app_private.audience_allows_player(jsonb, uuid)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.build_shared_reveal(uuid)
  from public, anon, authenticated, service_role;

comment on function public.get_game_master_view(uuid) is
  'Actor-checked setup view before lock and complete Game Master view after lock.';
comment on function public.get_player_view(uuid) is
  'Actor-checked view containing only the active player authorized room state.';
comment on function public.get_reveal_view(uuid) is
  'Shared reveal and results for authorized room actors after publication.';
