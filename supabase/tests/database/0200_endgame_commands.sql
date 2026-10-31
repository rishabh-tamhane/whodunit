begin;
select no_plan();

select has_function(
  'public','open_final_accusations',array['uuid','bigint','uuid'],
  'Game Master early-verdict command exists'
);
select has_function(
  'public','save_final_accusation',array['uuid','bigint','jsonb','text'],
  'owner-private final-case save exists'
);
select has_function(
  'public','submit_final_accusation',array['uuid','bigint','uuid'],
  'immutable final-case submission command exists'
);
select has_function(
  'public','close_final_accusations',array['uuid','bigint','uuid','uuid[]','boolean'],
  'frozen scoring command exists'
);
select has_function(
  'public','publish_reveal',array['uuid','bigint','uuid'],
  'shared reveal publication command exists'
);
select has_function(
  'public','complete_room',array['uuid','bigint','uuid'],
  'case-file completion command exists'
);
select ok(
  not has_function_privilege(
    'authenticated','app_private.score_frozen_endgame(uuid,uuid,uuid)','EXECUTE'
  ),
  'clients cannot bypass the public scoring command boundary'
);

select * from finish();
rollback;
