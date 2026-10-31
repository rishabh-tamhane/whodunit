-- DB-09: database-enforced canonical, submitted, history, and result immutability.

create function app_private.enforce_canonical_story_locked()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_room_id uuid;
  room_locked_at timestamp with time zone;
begin
  target_room_id := case when tg_op = 'DELETE' then old.room_id else new.room_id end;

  select room.locked_at
  into room_locked_at
  from app_private.rooms as room
  where room.id = target_room_id;

  -- A room-first audited retention deletion removes the parent before its
  -- cascading child deletes fire. With no surviving room, there is no
  -- canonical truth left to protect.
  if not found then
    if tg_op = 'DELETE' then
      return old;
    end if;

    return new;
  end if;

  if room_locked_at is not null then
    raise exception using
      errcode = '23514',
      message = 'locked canonical story content is immutable',
      constraint = 'canonical_story_locked_immutable';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;

create function app_private.enforce_room_story_lock_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.locked_at is not null and (
    new.locked_at is distinct from old.locked_at
    or new.story_id is distinct from old.story_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'a room cannot replace or remove its locked story',
      constraint = 'rooms_story_lock_immutable';
  end if;

  return new;
end;
$function$;

create trigger rooms_enforce_story_lock_immutable
before update of story_id, locked_at on app_private.rooms
for each row execute function app_private.enforce_room_story_lock_immutable();

create trigger canonical_stories_locked_immutable
before insert or update or delete on app_private.canonical_stories
for each row execute function app_private.enforce_canonical_story_locked();

create trigger canonical_solutions_locked_immutable
before insert or update or delete on app_private.canonical_solutions
for each row execute function app_private.enforce_canonical_story_locked();

create trigger story_rounds_locked_immutable
before insert or update or delete on app_private.story_rounds
for each row execute function app_private.enforce_canonical_story_locked();

create trigger dossiers_locked_immutable
before insert or update or delete on app_private.dossiers
for each row execute function app_private.enforce_canonical_story_locked();

create trigger relationships_locked_immutable
before insert or update or delete on app_private.relationships
for each row execute function app_private.enforce_canonical_story_locked();

create trigger timeline_events_locked_immutable
before insert or update or delete on app_private.timeline_events
for each row execute function app_private.enforce_canonical_story_locked();

create trigger evidence_locked_immutable
before insert or update or delete on app_private.evidence
for each row execute function app_private.enforce_canonical_story_locked();

create trigger evidence_dependencies_locked_immutable
before insert or update or delete on app_private.evidence_dependencies
for each row execute function app_private.enforce_canonical_story_locked();

create trigger consequence_specs_locked_immutable
before insert or update or delete on app_private.consequence_specs
for each row execute function app_private.enforce_canonical_story_locked();

create trigger mission_specs_locked_immutable
before insert or update or delete on app_private.mission_specs
for each row execute function app_private.enforce_canonical_story_locked();

create trigger intervention_specs_locked_immutable
before insert or update or delete on app_private.intervention_specs
for each row execute function app_private.enforce_canonical_story_locked();

create trigger accomplice_revelations_locked_immutable
before insert or update or delete on app_private.accomplice_revelations
for each row execute function app_private.enforce_canonical_story_locked();

create trigger final_reveal_sections_locked_immutable
before insert or update or delete on app_private.final_reveal_sections
for each row execute function app_private.enforce_canonical_story_locked();

-- Finalized scoring and postgame rows are append-only from their first insert.
create trigger scoring_snapshots_immutable
before update or delete on app_private.scoring_snapshots
for each row execute function app_private.enforce_room_record_immutable();

create trigger player_scores_immutable
before update or delete on app_private.player_scores
for each row execute function app_private.enforce_room_record_immutable();

create trigger theory_scores_immutable
before update or delete on app_private.theory_scores
for each row execute function app_private.enforce_room_record_immutable();

create trigger faction_results_immutable
before update or delete on app_private.faction_results
for each row execute function app_private.enforce_room_record_immutable();

create trigger player_awards_immutable
before update or delete on app_private.player_awards
for each row execute function app_private.enforce_room_record_immutable();

create trigger reveal_publications_immutable
before update or delete on app_private.reveal_publications
for each row execute function app_private.enforce_room_record_immutable();

create trigger case_files_immutable
before update or delete on app_private.case_files
for each row execute function app_private.enforce_room_record_immutable();

-- Mutable runtime state may follow its validated transition graph, but it may
-- not be erased while the room survives.
create trigger mission_states_no_delete
before delete on app_private.mission_states
for each row execute function app_private.enforce_room_record_immutable();

create trigger consequence_states_no_delete
before delete on app_private.consequence_states
for each row execute function app_private.enforce_room_record_immutable();

create trigger intervention_requests_no_delete
before delete on app_private.intervention_requests
for each row execute function app_private.enforce_room_record_immutable();

create trigger accomplice_revelation_states_no_delete
before delete on app_private.accomplice_revelation_states
for each row execute function app_private.enforce_room_record_immutable();

-- Preserve submitted accusations during normal operation but allow the same
-- room-first cascade used by the audited retention procedure.
create or replace function app_private.enforce_final_accusation_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    if exists (
      select 1 from app_private.rooms as room where room.id = old.room_id
    ) then
      raise exception using
        errcode = '23514',
        message = 'final accusation cannot be deleted while its room exists',
        constraint = 'final_accusations_record_permanent';
    end if;

    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'DRAFT' or new.revision <> 0 then
      raise exception using
        errcode = '23514',
        message = 'final accusation must begin as a revision-zero draft',
        constraint = 'final_accusations_initial_state';
    end if;

    return new;
  end if;

  if (new.room_id, new.story_id, new.player_id) is distinct from
    (old.room_id, old.story_id, old.player_id) then
    raise exception using
      errcode = '23514',
      message = 'final accusation ownership is immutable',
      constraint = 'final_accusations_identity_immutable';
  end if;

  if old.status = 'SUBMITTED' then
    raise exception using
      errcode = '23514',
      message = 'submitted final accusation is immutable',
      constraint = 'final_accusations_submitted_immutable';
  end if;

  if new.revision <> old.revision + 1 then
    raise exception using
      errcode = '40001',
      message = 'stale final accusation revision',
      constraint = 'final_accusations_revision_conflict';
  end if;

  if new.status not in ('DRAFT', 'SUBMITTED') then
    raise exception using
      errcode = '23514',
      message = 'invalid final accusation transition',
      constraint = 'final_accusations_valid_transition';
  end if;

  return new;
end;
$function$;

revoke all on function app_private.enforce_canonical_story_locked()
  from public, anon, authenticated;
revoke all on function app_private.enforce_room_story_lock_immutable()
  from public, anon, authenticated;

comment on function app_private.enforce_canonical_story_locked() is
  'Rejects every canonical package mutation after the room lock commits.';
