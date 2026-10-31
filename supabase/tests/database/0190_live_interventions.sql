begin;
select no_plan();

select has_function(
  'public','request_intervention',array['uuid','bigint','uuid'],
  'bounded Discussion Stalled request command exists'
);
select has_function(
  'public','stage_intervention_preview',
  array['uuid','uuid','uuid','uuid','text','text','text','text','integer','integer','integer','text'],
  'canonical preview staging function exists'
);
select has_function(
  'public','resolve_intervention',array['uuid','uuid','bigint','uuid','text'],
  'transactional intervention approval and rejection command exists'
);
select has_function(
  'app_private','intervention_candidates',array['uuid','uuid','integer'],
  'fresh canonical candidate engine exists'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'app_private.intervention_candidates(uuid,uuid,integer)',
    'EXECUTE'
  ),
  'clients cannot bypass the public intervention command boundary'
);
select col_not_null(
  'app_private','intervention_requests','provider_input_tokens',
  'provider input-token accounting is always recorded'
);
select col_not_null(
  'app_private','intervention_requests','provider_output_tokens',
  'provider output-token accounting is always recorded'
);
select col_not_null(
  'app_private','intervention_requests','provider_latency_ms',
  'provider latency accounting is always recorded'
);

select * from finish();
rollback;
