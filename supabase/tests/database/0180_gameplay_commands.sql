begin;
select no_plan();

select has_function('public','get_actor_view',array['uuid'],'actor-aware projection exists');
select has_function('public','save_player_notebook',array['uuid','bigint','text','jsonb'],'private revisioned notebook command exists');
select has_function('public','submit_player_theory',array['uuid','bigint','uuid','jsonb','text'],'immutable theory submission command exists');
select has_function('public','start_game',array['uuid','bigint','uuid'],'idempotent game-start command exists');
select has_function('public','advance_round',array['uuid','bigint','uuid'],'manual round-advance command exists');
select has_function('public','player_mission_command',array['uuid','uuid','bigint','uuid','text'],'assigned-player mission command exists');
select has_function('public','adjudicate_mission',array['uuid','uuid','bigint','uuid','text','integer'],'Game Master mission adjudication exists');
select has_function('public','resolve_canonical_release',array['uuid','uuid','bigint','uuid','text','text'],'canonical release command exists');
select ok(
  exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='room_signals'
  ),
  'content-free room signals are published for Realtime invalidation'
);

select throws_ok(
  $$select public.get_actor_view('00000000-0000-4000-8000-000000000001')$$,
  '42501','authorized room actor required',
  'an unaffiliated principal cannot fetch an actor projection'
);

select * from finish();
rollback;
