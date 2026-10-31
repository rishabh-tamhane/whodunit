-- OPS-01/OPS-03: content-free AI usage ledger and atomic spend/concurrency caps.

alter table app_private.operational_events
  drop constraint operational_events_metadata_allowlist,
  add constraint operational_events_metadata_allowlist check (
    metadata_json - array[
      'attempt','count','phase','source','fallback','deletedCount',
      'remainingCount','inputTokens','outputTokens','latencyMs',
      'estimatedCostMicrousd','budgetReason'
    ]::text[] = '{}'::jsonb
  );

create table app_private.ai_call_reservations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  correlation_id uuid not null,
  room_hash text not null,
  call_kind text not null,
  model_id text not null,
  status text not null default 'RESERVED',
  reserved_cost_microusd bigint not null,
  actual_cost_microusd bigint,
  input_tokens integer,
  output_tokens integer,
  provider_response_id text,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  settled_at timestamp with time zone,
  expires_at timestamp with time zone not null default app_private.current_database_time() + interval '30 minutes',
  constraint ai_call_reservations_room_hash_shape check (room_hash ~ '^[0-9a-f]{64}$'),
  constraint ai_call_reservations_kind_supported check (call_kind in ('STORY','INTERVENTION')),
  constraint ai_call_reservations_status_supported check (status in ('RESERVED','COMPLETED','FAILED')),
  constraint ai_call_reservations_reserved_positive check (reserved_cost_microusd > 0),
  constraint ai_call_reservations_actual_nonnegative check (actual_cost_microusd is null or actual_cost_microusd >= 0),
  constraint ai_call_reservations_tokens_nonnegative check (
    (input_tokens is null or input_tokens >= 0)
    and (output_tokens is null or output_tokens >= 0)
  ),
  constraint ai_call_reservations_settlement_consistent check (
    (status = 'RESERVED' and settled_at is null and actual_cost_microusd is null)
    or (status <> 'RESERVED' and settled_at is not null and actual_cost_microusd is not null)
  )
);

create unique index ai_call_reservations_provider_response_unique_idx
  on app_private.ai_call_reservations (provider_response_id)
  where provider_response_id is not null;
create index ai_call_reservations_monthly_cost_idx
  on app_private.ai_call_reservations (created_at, status);
create index ai_call_reservations_room_cost_idx
  on app_private.ai_call_reservations (room_hash, created_at);

alter table app_private.ai_call_reservations enable row level security;
revoke all on table app_private.ai_call_reservations
  from public, anon, authenticated, service_role;

create function public.reserve_ai_call(
  target_room_id uuid,
  request_correlation_id uuid,
  requested_call_kind text,
  requested_model_id text,
  maximum_cost_microusd bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  room_hash_value text;
  reservation_id uuid;
  monthly_committed bigint;
  room_committed bigint;
  active_story_calls integer;
  month_start timestamp with time zone := pg_catalog.date_trunc(
    'month', app_private.current_database_time()
  );
begin
  perform app_private.assert_service_role();
  if requested_call_kind not in ('STORY','INTERVENTION')
    or requested_model_id is null or pg_catalog.length(requested_model_id) not between 1 and 100
    or maximum_cost_microusd not between 1 and 2000000
  then
    raise exception using errcode='22023', message='invalid AI call reservation';
  end if;
  if not exists (select 1 from app_private.rooms where id=target_room_id) then
    raise exception using errcode='P0002', message='room not found';
  end if;
  room_hash_value := pg_catalog.encode(extensions.digest(
    pg_catalog.convert_to(target_room_id::text,'UTF8'),'sha256'
  ),'hex');

  -- One lock makes the aggregate checks and insert atomic across instances.
  perform pg_catalog.pg_advisory_xact_lock(881721044);
  update app_private.ai_call_reservations
  set status='FAILED', actual_cost_microusd=reserved_cost_microusd,
    settled_at=app_private.current_database_time()
  where status='RESERVED' and expires_at <= app_private.current_database_time();

  select coalesce(pg_catalog.sum(coalesce(actual_cost_microusd,reserved_cost_microusd)),0)
  into monthly_committed
  from app_private.ai_call_reservations where created_at >= month_start;
  if monthly_committed + maximum_cost_microusd > 75000000 then
    return pg_catalog.jsonb_build_object('allowed',false,'reason','MONTHLY_HARD_CAP');
  end if;

  select coalesce(pg_catalog.sum(coalesce(actual_cost_microusd,reserved_cost_microusd)),0)
  into room_committed
  from app_private.ai_call_reservations where room_hash=room_hash_value;
  if room_committed + maximum_cost_microusd > 3000000 then
    return pg_catalog.jsonb_build_object('allowed',false,'reason','ROOM_HARD_CAP');
  end if;

  if requested_call_kind='STORY' then
    select pg_catalog.count(*) into active_story_calls
    from app_private.ai_call_reservations
    where call_kind='STORY' and status='RESERVED';
    if active_story_calls >= 10 then
      return pg_catalog.jsonb_build_object('allowed',false,'reason','STORY_CONCURRENCY_CAP');
    end if;
  end if;

  insert into app_private.ai_call_reservations (
    correlation_id,room_hash,call_kind,model_id,reserved_cost_microusd
  ) values (
    request_correlation_id,room_hash_value,requested_call_kind,
    requested_model_id,maximum_cost_microusd
  ) returning id into reservation_id;
  return pg_catalog.jsonb_build_object(
    'allowed',true,'reservationId',reservation_id,
    'reservedCostMicrousd',maximum_cost_microusd
  );
end;
$function$;

create function public.settle_ai_call(
  target_reservation_id uuid,
  provider_response_id text,
  final_input_tokens integer,
  final_output_tokens integer,
  actual_cost_microusd bigint,
  final_status text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  perform app_private.assert_service_role();
  if final_status not in ('COMPLETED','FAILED')
    or final_input_tokens < 0 or final_output_tokens < 0
    or actual_cost_microusd < 0
  then
    raise exception using errcode='22023', message='invalid AI call settlement';
  end if;
  update app_private.ai_call_reservations
  set status=final_status, provider_response_id=settle_ai_call.provider_response_id,
    input_tokens=final_input_tokens, output_tokens=final_output_tokens,
    actual_cost_microusd=settle_ai_call.actual_cost_microusd,
    settled_at=app_private.current_database_time()
  where id=target_reservation_id and status='RESERVED';
  if not found then
    raise exception using errcode='55000', message='AI call reservation is not active';
  end if;
end;
$function$;

revoke all on function public.reserve_ai_call(uuid,uuid,text,text,bigint)
  from public,anon,authenticated,service_role;
revoke all on function public.settle_ai_call(uuid,text,integer,integer,bigint,text)
  from public,anon,authenticated,service_role;
grant execute on function public.reserve_ai_call(uuid,uuid,text,text,bigint) to service_role;
grant execute on function public.settle_ai_call(uuid,text,integer,integer,bigint,text) to service_role;
