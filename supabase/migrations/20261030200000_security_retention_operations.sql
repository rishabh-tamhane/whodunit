-- SEC/REL/OPS: abuse budgets, retention, reconciliation, and safe telemetry.

alter table app_private.rooms
  add column inactivity_expires_at timestamp with time zone;

create table app_private.rate_limit_windows (
  scope text not null,
  key_hash text not null,
  window_started_at timestamp with time zone not null,
  request_count integer not null default 0,
  expires_at timestamp with time zone not null,
  primary key (scope, key_hash, window_started_at),
  constraint rate_limit_scope_supported check (
    scope in ('IP_ROUTE', 'PRINCIPAL_ROUTE', 'ROOM')
  ),
  constraint rate_limit_key_hash_shape check (key_hash ~ '^[0-9a-f]{64}$'),
  constraint rate_limit_count_positive check (request_count > 0),
  constraint rate_limit_window_ordered check (expires_at > window_started_at)
);

create table app_private.operational_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  correlation_id uuid not null,
  event_type text not null,
  severity text not null,
  route_code text,
  room_hash text,
  duration_ms integer,
  status_code integer,
  error_code text,
  metadata_json jsonb not null default '{}'::jsonb,
  occurred_at timestamp with time zone not null default app_private.current_database_time(),
  constraint operational_events_type_present check (event_type ~ '^[A-Z][A-Z0-9_]{2,99}$'),
  constraint operational_events_severity_supported check (severity in ('INFO','WARNING','ERROR')),
  constraint operational_events_room_hash_shape check (room_hash is null or room_hash ~ '^[0-9a-f]{64}$'),
  constraint operational_events_duration_nonnegative check (duration_ms is null or duration_ms >= 0),
  constraint operational_events_status_range check (status_code is null or status_code between 100 and 599),
  constraint operational_events_metadata_object check (pg_catalog.jsonb_typeof(metadata_json) = 'object'),
  constraint operational_events_metadata_allowlist check (
    metadata_json - array[
      'attempt','count','phase','source','fallback','deletedCount',
      'remainingCount','inputTokens','outputTokens','latencyMs'
    ]::text[] = '{}'::jsonb
  )
);

create table app_private.room_deletion_audit (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_hash text not null,
  lifecycle_state app_private.room_state not null,
  deletion_reason text not null,
  deleted_counts_json jsonb not null,
  deleted_at timestamp with time zone not null default app_private.current_database_time(),
  constraint room_deletion_audit_hash_shape check (room_hash ~ '^[0-9a-f]{64}$'),
  constraint room_deletion_audit_reason_supported check (
    deletion_reason in ('COMPLETED_EXPIRED','INCOMPLETE_INACTIVE')
  ),
  constraint room_deletion_audit_counts_object check (
    pg_catalog.jsonb_typeof(deleted_counts_json) = 'object'
  )
);

alter table app_private.rate_limit_windows enable row level security;
alter table app_private.operational_events enable row level security;
alter table app_private.room_deletion_audit enable row level security;
revoke all on table app_private.rate_limit_windows, app_private.operational_events,
  app_private.room_deletion_audit from public, anon, authenticated, service_role;

create function app_private.set_room_inactivity_deadline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.inactivity_expires_at := case
    when new.status in ('DRAFT','LOBBY') then new.updated_at + interval '7 days'
    when new.status in ('READY_TO_START','IN_PROGRESS','FINAL_ACCUSATIONS','REVEAL')
      then new.updated_at + interval '30 days'
    else null
  end;
  return new;
end;
$function$;

create trigger rooms_set_inactivity_deadline
before insert or update of status, updated_at on app_private.rooms
for each row execute function app_private.set_room_inactivity_deadline();

update app_private.rooms
set inactivity_expires_at = case
  when status in ('DRAFT','LOBBY') then updated_at + interval '7 days'
  when status in ('READY_TO_START','IN_PROGRESS','FINAL_ACCUSATIONS','REVEAL')
    then updated_at + interval '30 days'
  else null
end;

create function app_private.touch_room_from_private_draft()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update app_private.rooms
  set updated_at = app_private.current_database_time()
  where id = new.room_id and status not in ('GENERATING','COMPLETED');
  return new;
end;
$function$;

create trigger player_notes_touch_room_activity
after insert or update on app_private.player_notes
for each row execute function app_private.touch_room_from_private_draft();
create trigger final_accusations_touch_room_activity
after insert or update on app_private.final_accusations
for each row execute function app_private.touch_room_from_private_draft();
create trigger player_descriptions_touch_room_activity
after insert or update of description_text, response_status on app_private.player_descriptions
for each row execute function app_private.touch_room_from_private_draft();

create function public.consume_rate_limit(
  bucket_scope text,
  bucket_key_hash text,
  maximum_requests integer,
  window_seconds integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  now_at timestamp with time zone := app_private.current_database_time();
  window_at timestamp with time zone;
  current_count integer;
begin
  perform app_private.assert_service_role();
  if bucket_scope not in ('IP_ROUTE','PRINCIPAL_ROUTE','ROOM')
    or bucket_key_hash !~ '^[0-9a-f]{64}$'
    or maximum_requests not between 1 and 10000
    or window_seconds not between 1 and 86400
  then
    raise exception using errcode = '22023', message = 'invalid rate-limit configuration';
  end if;
  window_at := pg_catalog.to_timestamp(
    pg_catalog.floor(extract(epoch from now_at) / window_seconds)
      * window_seconds
  );
  insert into app_private.rate_limit_windows (
    scope, key_hash, window_started_at, request_count, expires_at
  ) values (
    bucket_scope, bucket_key_hash, window_at, 1,
    window_at + pg_catalog.make_interval(secs => window_seconds)
  )
  on conflict (scope, key_hash, window_started_at) do update
  set request_count = app_private.rate_limit_windows.request_count + 1
  returning request_count into current_count;
  if pg_catalog.random() < 0.01 then
    delete from app_private.rate_limit_windows where expires_at < now_at - interval '1 hour';
  end if;
  return pg_catalog.jsonb_build_object(
    'allowed', current_count <= maximum_requests,
    'count', current_count,
    'limit', maximum_requests,
    'retryAfterSeconds', greatest(0, pg_catalog.ceil(
      extract(epoch from (window_at + pg_catalog.make_interval(secs => window_seconds) - now_at))
    )::integer)
  );
end;
$function$;

create function public.record_operational_event(
  correlation_id uuid,
  event_type text,
  severity text,
  route_code text,
  room_hash text,
  duration_ms integer,
  status_code integer,
  error_code text,
  metadata_json jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare inserted_id uuid;
begin
  perform app_private.assert_service_role();
  insert into app_private.operational_events (
    correlation_id, event_type, severity, route_code, room_hash,
    duration_ms, status_code, error_code, metadata_json
  ) values (
    correlation_id, event_type, severity, route_code, room_hash,
    duration_ms, status_code, error_code, coalesce(metadata_json, '{}'::jsonb)
  ) returning id into inserted_id;
  return inserted_id;
end;
$function$;

create function public.reconcile_stale_generation_jobs()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  job record;
  recoverable_ids uuid[] := '{}'::uuid[];
  failed_count integer := 0;
  next_version bigint;
begin
  perform app_private.assert_service_role();
  for job in
    select candidate.* from app_private.story_generation_jobs as candidate
    where candidate.status in ('PENDING','RUNNING')
      and candidate.updated_at <= app_private.current_database_time() - interval '15 minutes'
    order by candidate.updated_at
    limit 10
    for update skip locked
  loop
    perform app_private.lock_room(job.room_id);
    if job.attempt_count >= 3
      or job.created_at <= app_private.current_database_time() - interval '2 hours'
    then
      update app_private.story_generation_jobs
      set status = 'FAILED', sanitized_error_code = 'STALE_RECOVERY_EXHAUSTED',
        finished_at = app_private.current_database_time(),
        purge_due_at = app_private.current_database_time(),
        lease_owner = null, lease_expires_at = null,
        updated_at = app_private.current_database_time()
      where id = job.id;
      update app_private.rooms
      set status = 'LOBBY', state_version = state_version + 1,
        updated_at = app_private.current_database_time()
      where id = job.room_id and story_id is null
      returning state_version into next_version;
      perform app_private.purge_generation_source(job.id);
      perform app_private.append_identity_event(
        job.room_id, next_version, 'GENERATION_FAILED', 'SYSTEM', null, null,
        job.id, 'GENERATION_CHANGED'
      );
      failed_count := failed_count + 1;
    else
      update app_private.story_generation_jobs
      set lease_owner = null, lease_expires_at = null,
        updated_at = app_private.current_database_time()
      where id = job.id;
      recoverable_ids := pg_catalog.array_append(recoverable_ids, job.id);
    end if;
  end loop;
  return pg_catalog.jsonb_build_object(
    'recoverableJobIds', recoverable_ids,
    'failedCount', failed_count
  );
end;
$function$;

create function public.cleanup_expired_rooms(batch_size integer default 25)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  target record;
  deleted_count integer := 0;
  completed_count integer := 0;
  incomplete_count integer := 0;
  reason text;
  room_hash text;
  counts jsonb;
begin
  perform app_private.assert_service_role();
  if batch_size not between 1 and 100 then
    raise exception using errcode = '22023', message = 'cleanup batch size must be between 1 and 100';
  end if;
  for target in
    select room.* from app_private.rooms as room
    where (
      room.status = 'COMPLETED'
      and room.expires_at <= app_private.current_database_time()
    ) or (
      room.status <> 'COMPLETED' and room.status <> 'GENERATING'
      and room.inactivity_expires_at <= app_private.current_database_time()
    )
    order by coalesce(room.expires_at, room.inactivity_expires_at), room.id
    limit batch_size for update skip locked
  loop
    reason := case when target.status = 'COMPLETED'
      then 'COMPLETED_EXPIRED' else 'INCOMPLETE_INACTIVE' end;
    room_hash := pg_catalog.encode(extensions.digest(
      pg_catalog.convert_to(target.id::text, 'UTF8'), 'sha256'
    ), 'hex');
    counts := pg_catalog.jsonb_build_object(
      'players', (select pg_catalog.count(*) from app_private.players where room_id = target.id),
      'memberships', (select pg_catalog.count(*) from app_private.room_memberships where room_id = target.id),
      'events', (select pg_catalog.count(*) from app_private.game_events where room_id = target.id),
      'stories', (select pg_catalog.count(*) from app_private.canonical_stories where room_id = target.id),
      'caseFiles', (select pg_catalog.count(*) from app_private.case_files where room_id = target.id)
    );
    insert into app_private.room_deletion_audit (
      room_hash, lifecycle_state, deletion_reason, deleted_counts_json
    ) values (room_hash, target.status, reason, counts);
    delete from app_private.rooms where id = target.id;
    deleted_count := deleted_count + 1;
    if reason = 'COMPLETED_EXPIRED' then completed_count := completed_count + 1;
    else incomplete_count := incomplete_count + 1; end if;
  end loop;

  delete from auth.users as auth_user
  where auth_user.is_anonymous
    and auth_user.created_at <= app_private.current_database_time() - interval '30 days'
    and not exists (
      select 1 from app_private.room_memberships as membership
      where membership.auth_user_id = auth_user.id
    )
    and not exists (
      select 1 from app_private.room_host_principals as principal
      where principal.auth_user_id = auth_user.id
    );
  return pg_catalog.jsonb_build_object(
    'deletedCount', deleted_count,
    'completedCount', completed_count,
    'incompleteCount', incomplete_count,
    'remainingEligible', (
      select pg_catalog.count(*) from app_private.rooms as room
      where (room.status = 'COMPLETED' and room.expires_at <= app_private.current_database_time())
        or (room.status not in ('COMPLETED','GENERATING')
          and room.inactivity_expires_at <= app_private.current_database_time())
    )
  );
end;
$function$;

alter function public.get_actor_view(uuid) rename to get_actor_view_without_retention;
revoke all on function public.get_actor_view_without_retention(uuid)
  from public, anon, authenticated, service_role;
create function public.get_actor_view(target_room_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  projection jsonb;
  retention_deadline timestamp with time zone;
begin
  projection := public.get_actor_view_without_retention(target_room_id);
  select case when room.status = 'COMPLETED' then room.expires_at
    else room.inactivity_expires_at end
  into retention_deadline from app_private.rooms as room where room.id = target_room_id;
  return pg_catalog.jsonb_set(
    projection, '{room,retentionDeadline}',
    pg_catalog.to_jsonb(retention_deadline), true
  );
end;
$function$;

revoke all on function app_private.set_room_inactivity_deadline()
  from public, anon, authenticated, service_role;
revoke all on function app_private.touch_room_from_private_draft()
  from public, anon, authenticated, service_role;
revoke all on function public.consume_rate_limit(text,text,integer,integer)
  from public, anon, authenticated, service_role;
revoke all on function public.record_operational_event(uuid,text,text,text,text,integer,integer,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.reconcile_stale_generation_jobs()
  from public, anon, authenticated, service_role;
revoke all on function public.cleanup_expired_rooms(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.get_actor_view(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.consume_rate_limit(text,text,integer,integer) to service_role;
grant execute on function public.record_operational_event(uuid,text,text,text,text,integer,integer,text,jsonb) to service_role;
grant execute on function public.reconcile_stale_generation_jobs() to service_role;
grant execute on function public.cleanup_expired_rooms(integer) to service_role;
grant execute on function public.get_actor_view(uuid) to authenticated;
