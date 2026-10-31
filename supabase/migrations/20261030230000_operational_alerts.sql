-- OPS-01/OPS-02: cross-system correlation lookup and content-free alert evaluation.

create function public.resolve_ai_call_correlation(provider_response_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare result uuid;
begin
  perform app_private.assert_service_role();
  if provider_response_id is null or pg_catalog.length(provider_response_id) not between 1 and 200 then
    return null;
  end if;
  select reservation.correlation_id into result
  from app_private.ai_call_reservations as reservation
  where reservation.provider_response_id=resolve_ai_call_correlation.provider_response_id;
  return result;
end;
$function$;

create function public.evaluate_operational_alerts()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  alerts jsonb := '[]'::jsonb;
  generation_failures integer;
  intervention_calls integer;
  intervention_fallbacks integer;
  webhook_errors integer;
  command_conflicts integer;
  rate_denials integer;
  deletion_backlog_runs integer;
  monthly_spend bigint;
begin
  perform app_private.assert_service_role();
  select pg_catalog.count(*) into generation_failures
  from app_private.operational_events
  where occurred_at >= app_private.current_database_time()-interval '15 minutes'
    and event_type='MODEL_CALL_FAILED' and route_code like 'STORY%';
  if generation_failures >= 3 then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','GENERATION_FAILURE_RATE','severity','SEV-2','count',generation_failures
    ));
  end if;

  select pg_catalog.count(*),
    pg_catalog.count(*) filter (where event_type='INTERVENTION_FALLBACK_STAGED')
  into intervention_calls,intervention_fallbacks
  from app_private.operational_events
  where occurred_at >= app_private.current_database_time()-interval '15 minutes'
    and event_type in ('INTERVENTION_MODEL_COMPLETED','INTERVENTION_FALLBACK_STAGED');
  if intervention_calls >= 10 and intervention_fallbacks*5 > intervention_calls then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','INTERVENTION_FALLBACK_RATE','severity','SEV-3','count',intervention_fallbacks
    ));
  end if;

  select pg_catalog.count(*) into webhook_errors
  from app_private.operational_events
  where occurred_at >= app_private.current_database_time()-interval '5 minutes'
    and event_type='WEBHOOK_REJECTED';
  if webhook_errors >= 5 then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','WEBHOOK_ERROR_RATE','severity','SEV-2','count',webhook_errors
    ));
  end if;

  select pg_catalog.count(*) into command_conflicts
  from app_private.operational_events
  where occurred_at >= app_private.current_database_time()-interval '15 minutes'
    and event_type='COMMAND_CONFLICT';
  if command_conflicts >= 10 then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','COMMAND_CONFLICT_VOLUME','severity','SEV-3','count',command_conflicts
    ));
  end if;

  select pg_catalog.count(*) into rate_denials
  from app_private.operational_events
  where occurred_at >= app_private.current_database_time()-interval '5 minutes'
    and event_type='RATE_LIMIT_DENIED';
  if rate_denials >= 50 then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','RATE_DENIAL_VOLUME','severity','SEV-2','count',rate_denials
    ));
  end if;

  select pg_catalog.count(*) into deletion_backlog_runs
  from (
    select (event.metadata_json->>'remainingCount')::integer as remaining_count
    from app_private.operational_events as event
    where event.event_type='MAINTENANCE_COMPLETED'
    order by event.occurred_at desc limit 3
  ) as recent where recent.remaining_count > 0;
  if deletion_backlog_runs = 3 then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','DELETION_BACKLOG','severity','SEV-2','count',deletion_backlog_runs
    ));
  end if;

  select coalesce(pg_catalog.sum(coalesce(actual_cost_microusd,reserved_cost_microusd)),0)
  into monthly_spend from app_private.ai_call_reservations
  where created_at >= pg_catalog.date_trunc('month',app_private.current_database_time());
  if monthly_spend >= 50000000 then
    alerts := alerts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'code','AI_MONTHLY_SPEND','severity',
      case when monthly_spend >= 75000000 then 'SEV-2' else 'SEV-3' end,
      'count',monthly_spend
    ));
  end if;
  return alerts;
end;
$function$;

revoke all on function public.resolve_ai_call_correlation(text)
  from public,anon,authenticated,service_role;
revoke all on function public.evaluate_operational_alerts()
  from public,anon,authenticated,service_role;
grant execute on function public.resolve_ai_call_correlation(text) to service_role;
grant execute on function public.evaluate_operational_alerts() to service_role;
