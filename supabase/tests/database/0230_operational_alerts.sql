begin;
select no_plan();

select has_function(
  'public','resolve_ai_call_correlation',array['text'],
  'provider callbacks can recover their original safe correlation ID'
);
select has_function(
  'public','evaluate_operational_alerts',array[]::text[],
  'content-free alert thresholds are executable'
);
select ok(
  not has_function_privilege(
    'authenticated','public.evaluate_operational_alerts()','EXECUTE'
  ),
  'clients cannot inspect operational alerts'
);

select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into app_private.operational_events (
  correlation_id,event_type,severity,route_code,error_code
)
select pg_catalog.gen_random_uuid(),'MODEL_CALL_FAILED','ERROR',
  'STORY_GENERATION','PROVIDER_UNAVAILABLE'
from pg_catalog.generate_series(1,3);
select ok(
  public.evaluate_operational_alerts() @> '[{"code":"GENERATION_FAILURE_RATE","severity":"SEV-2","count":3}]'::jsonb,
  'three recent generation failures trigger the documented alert'
);

insert into app_private.operational_events (
  correlation_id,event_type,severity,route_code,metadata_json
)
select pg_catalog.gen_random_uuid(),
  case when sequence <= 3 then 'INTERVENTION_FALLBACK_STAGED'
    else 'INTERVENTION_MODEL_COMPLETED' end,
  'WARNING','INTERVENTION_REQUEST','{"source":"INTERVENTION"}'::jsonb
from pg_catalog.generate_series(1,10) as sequence;
select ok(
  public.evaluate_operational_alerts() @> '[{"code":"INTERVENTION_FALLBACK_RATE","severity":"SEV-3","count":3}]'::jsonb,
  'a fallback rate above twenty percent triggers the documented alert'
);

select * from finish();
rollback;
