-- Finalize mission-failure results before the append-only command receipt is written.

create or replace function public.adjudicate_mission(
  target_room_id uuid, target_mission_id uuid, expected_state_version bigint,
  idempotency_key uuid, decision text, extension_minutes integer default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_record app_private.rooms%rowtype;
  state_record app_private.mission_states%rowtype;
  spec_record app_private.mission_specs%rowtype;
  receipt_id uuid := pg_catalog.gen_random_uuid();
  request_hash bytea;
  replay jsonb;
  next_version bigint;
  target_status app_private.mission_status;
  has_consequence boolean := false;
  result jsonb;
begin
  perform app_private.lock_room(target_room_id);
  perform app_private.assert_current_game_master(target_room_id);
  request_hash := app_private.command_request_hash(
    'ADJUDICATE_MISSION',
    pg_catalog.jsonb_build_object(
      'missionId',target_mission_id,
      'decision',decision,
      'extensionMinutes',extension_minutes
    )
  );
  replay := app_private.command_replay(
    target_room_id,idempotency_key,'ADJUDICATE_MISSION',request_hash
  );
  if replay is not null then return replay; end if;

  select room.* into strict room_record
  from app_private.rooms as room where room.id=target_room_id;
  if room_record.state_version<>expected_state_version
    or room_record.status<>'IN_PROGRESS' then
    raise exception using errcode='40001',message='stale or inactive room state';
  end if;
  select state.* into strict state_record
  from app_private.mission_states as state
  join app_private.mission_specs as spec
    on spec.room_id=state.room_id and spec.id=state.mission_spec_id
  where state.room_id=target_room_id and spec.id=target_mission_id
  for update of state;
  select spec.* into strict spec_record
  from app_private.mission_specs as spec
  where spec.room_id=target_room_id and spec.id=target_mission_id;
  if spec_record.round_id <> room_record.current_round_id then
    raise exception using errcode='55000',message='mission is not in the current round';
  end if;

  if decision='APPROVE' and state_record.status='COMPLETION_REQUESTED' then
    target_status := 'COMPLETED';
  elsif decision='REJECT' and state_record.status='COMPLETION_REQUESTED' then
    target_status := 'ACCEPTED';
  elsif decision='FAIL'
    and state_record.status in ('ASSIGNED','ACCEPTED','COMPLETION_REQUESTED') then
    target_status := 'FAILED';
  elsif decision='WAIVE'
    and state_record.status in (
      'ASSIGNED','ACCEPTED','COMPLETION_REQUESTED','CONSEQUENCE_PENDING'
    ) then
    target_status := 'WAIVED';
  elsif decision='EXTEND'
    and state_record.status in ('ACCEPTED','COMPLETION_REQUESTED')
    and extension_minutes between 1 and 60 then
    target_status := state_record.status;
  else
    raise exception using errcode='55000',message='invalid mission adjudication';
  end if;

  if decision='FAIL' and spec_record.failure_consequence_id is not null then
    if not exists (
      select 1 from app_private.consequence_specs as consequence
      where consequence.room_id=target_room_id
        and consequence.id=spec_record.failure_consequence_id
        and coalesce(
          (consequence.eligibility_rule_json ->> 'afterFailedMission')::boolean,
          false
        )
        and consequence.eligibility_rule_json -> 'roundIds'
          @> pg_catalog.jsonb_build_array(room_record.current_round_id::text)
    ) then
      raise exception using errcode='55000',message='mission consequence is not eligible';
    end if;
    has_consequence := true;
    target_status := 'CONSEQUENCE_PENDING';
  end if;

  next_version := room_record.state_version + 1;
  result := pg_catalog.jsonb_build_object(
    'missionId',target_mission_id,
    'status',target_status::text,
    'stateVersion',next_version::text,
    'replayed',false
  );
  perform app_private.record_command(
    receipt_id,target_room_id,idempotency_key,'ADJUDICATE_MISSION',
    'GAME_MASTER',auth.uid(),null,request_hash,expected_state_version,
    next_version,result,'MISSION_ADJUDICATED',target_mission_id,
    'GAMEPLAY_CHANGED'
  );
  if has_consequence then
    -- Preserve the audited mission state machine while the immutable command
    -- receipt already carries the final client-visible result.
    update app_private.mission_states
    set status='FAILED',revision=revision+1,
      resolved_at=app_private.current_database_time(),
      updated_at=app_private.current_database_time()
    where id=state_record.id;
    insert into app_private.consequence_states (
      room_id,story_id,consequence_spec_id,source_mission_state_id,
      eligible_by_command_receipt_id
    ) values (
      target_room_id,room_record.story_id,spec_record.failure_consequence_id,
      state_record.id,receipt_id
    ) on conflict (story_id,consequence_spec_id) do nothing;
    update app_private.mission_states
    set status='CONSEQUENCE_PENDING',revision=revision+1,
      updated_at=app_private.current_database_time()
    where id=state_record.id;
  else
    update app_private.mission_states
    set status=target_status,
      revision=revision+1,
      deadline_at=case when decision='EXTEND'
        then app_private.current_database_time()
          + pg_catalog.make_interval(mins=>extension_minutes)
        else deadline_at end,
      completion_requested_at=case when decision='REJECT'
        then null else completion_requested_at end,
      resolved_at=case when decision in ('APPROVE','FAIL','WAIVE')
        then app_private.current_database_time() else resolved_at end,
      updated_at=app_private.current_database_time()
    where id=state_record.id;
  end if;
  update app_private.rooms
  set state_version=next_version,updated_at=app_private.current_database_time()
  where id=target_room_id;
  return result;
end;
$function$;

revoke all on function public.adjudicate_mission(uuid,uuid,bigint,uuid,text,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.adjudicate_mission(uuid,uuid,bigint,uuid,text,integer)
  to authenticated;
