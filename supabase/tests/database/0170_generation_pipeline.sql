begin;

select no_plan();

select has_function('public', 'start_story_generation', array['uuid','bigint','uuid','text','text','text','text','text'], 'generation start command exists');
select has_function('public', 'claim_generation_job', array['uuid','text'], 'durable worker lease command exists');
select has_function('public', 'lock_generated_story', array['uuid','text','jsonb','text','text'], 'atomic story lock command exists');
select has_function('public', 'purge_terminal_generation_sources', array[]::text[], 'terminal source purge sweeper exists');

select col_is_null('app_private', 'story_generation_jobs', 'source_purged_at', 'source purge marker starts nullable');
select has_column('app_private', 'story_generation_jobs', 'lease_expires_at', 'generation jobs have durable leases');

select throws_ok(
  $$select public.claim_generation_job('00000000-0000-4000-8000-000000000001', 'worker')$$,
  '42501', 'service role required',
  'authenticated callers cannot claim private generation work'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$select public.purge_terminal_generation_sources()$$,
  'the service-role purge sweep is idempotent when no work is due'
);

insert into auth.users (id) values
  ('b1000000-0000-4000-8000-000000000001'),
  ('b1000000-0000-4000-8000-000000000002'),
  ('b1000000-0000-4000-8000-000000000003'),
  ('b1000000-0000-4000-8000-000000000004'),
  ('b1000000-0000-4000-8000-000000000005');

insert into app_private.rooms (
  id, room_code, host_auth_user_id, status, config_json,
  scoring_profile_version, duration_profile_version, duration_minutes,
  host_guidance_acknowledged_at, room_consent_confirmed_at
) values (
  'b2000000-0000-4000-8000-000000000001', 'GENLOCK1',
  'b1000000-0000-4000-8000-000000000001', 'LOBBY',
  '{"setupLocked":true,"playerCount":4,"murdererCount":1,"accompliceCount":0,"innocentCount":3,"murdererAware":true}'::jsonb,
  'score-v1', 'duration-v1', 30,
  app_private.current_database_time(), app_private.current_database_time()
);
insert into app_private.room_host_principals (room_id, auth_user_id)
values ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001');
insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume,
  host_background, seat_order, fictional_use_acknowledged_at
) values
  ('b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Aditi','aditi','Detective','Private host note 1',1,app_private.current_database_time()),
  ('b3000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000001','Kabir','kabir','Ghost','Private host note 2',2,app_private.current_database_time()),
  ('b3000000-0000-4000-8000-000000000003','b2000000-0000-4000-8000-000000000001','Meera','meera','Witch','Private host note 3',3,app_private.current_database_time()),
  ('b3000000-0000-4000-8000-000000000004','b2000000-0000-4000-8000-000000000001','Zoya','zoya','Astronaut','Private host note 4',4,app_private.current_database_time());
insert into app_private.room_memberships (
  room_id, auth_user_id, player_id, status, request_kind,
  approved_by_auth_user_id, last_seen_at, joined_at
)
select
  'b2000000-0000-4000-8000-000000000001',
  ('b1000000-0000-4000-8000-' || pg_catalog.lpad((seat_order + 1)::text, 12, '0'))::uuid,
  id, 'ACTIVE', 'INITIAL_CLAIM', 'b1000000-0000-4000-8000-000000000001',
  app_private.current_database_time(), app_private.current_database_time()
from app_private.players where room_id = 'b2000000-0000-4000-8000-000000000001';
insert into app_private.player_descriptions (
  room_id, author_player_id, subject_player_id, description_text, response_status
)
select author.room_id, author.id, subject.id,
  'Private fixture description ' || author.seat_order || '-' || subject.seat_order,
  'SUBMITTED'
from app_private.players as author
join app_private.players as subject on subject.room_id = author.room_id and subject.id <> author.id
where author.room_id = 'b2000000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
create temporary table generation_started as
select public.start_story_generation(
  'b2000000-0000-4000-8000-000000000001', 0,
  'b4000000-0000-4000-8000-000000000001',
  'gpt-6.1-sol', 'gpt-6-astra', 'story-prompt-v1', '0.1.0', 'story-validator-v1'
) as result;

select is(
  (select status::text from app_private.rooms where id = 'b2000000-0000-4000-8000-000000000001'),
  'GENERATING',
  'a ready room enters GENERATING without exposing partial story content'
);
select ok(
  (select input_snapshot_json::text not like '%author_player_id%'
    from app_private.story_generation_jobs
    where id = (select (result ->> 'jobId')::uuid from generation_started)),
  'the immutable generation snapshot removes description authorship'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
update app_private.story_generation_jobs
set provider_response_ids_json = '{"story":"resp_generation_test_1"}'::jsonb
where id = (select (result ->> 'jobId')::uuid from generation_started);
select is(
  public.record_generation_webhook(
    'event-generation-1','resp_generation_test_1','response.completed',
    pg_catalog.repeat('11',32)
  ) ->> 'duplicate',
  'false',
  'the first signed provider delivery records one durable receipt'
);
select is(
  public.record_generation_webhook(
    'event-generation-1','resp_generation_test_1','response.completed',
    pg_catalog.repeat('11',32)
  ) ->> 'duplicate',
  'true',
  'a replayed provider delivery is detected before any work is scheduled'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.webhook_receipts
    where provider_event_id = 'event-generation-1'),
  1,
  'a replay cannot create a second receipt'
);
select is(
  public.record_generation_webhook(
    'event-generation-unknown','resp_unknown','response.completed',
    pg_catalog.repeat('22',32)
  ) ->> 'known',
  'false',
  'an unknown provider response is acknowledged without touching a room'
);
select is(
  public.record_generation_webhook(
    'event-generation-2','resp_generation_test_1','response.failed',
    pg_catalog.repeat('33',32)
  ) ->> 'duplicate',
  'false',
  'an out-of-order provider event records a receipt for fresh-state reconciliation'
);
select is(
  (select status::text from app_private.story_generation_jobs
    where id = (select (result ->> 'jobId')::uuid from generation_started)),
  'PENDING',
  'webhook receipt order cannot mutate the generation job directly'
);
select public.claim_generation_job(
  (select (result ->> 'jobId')::uuid from generation_started),
  'pgTAP-worker'
);

create temporary table generated_story as
with room_players as (
  select *, row_number() over (order by seat_order) as n
  from app_private.players where room_id = 'b2000000-0000-4000-8000-000000000001'
), round_data as (
  select * from (values
    ('b5000000-0000-4000-8000-000000000001'::uuid, 1, 'Arrival', 540),
    ('b5000000-0000-4000-8000-000000000002'::uuid, 2, 'Final Bell', 540)
  ) as rounds(id, sequence, title, seconds)
), consequence_data as (
  select * from (values
    ('b6000000-0000-4000-8000-000000000001'::uuid, 1),
    ('b6000000-0000-4000-8000-000000000002'::uuid, 2),
    ('b6000000-0000-4000-8000-000000000003'::uuid, 3)
  ) as consequences(id, severity)
)
select pg_catalog.jsonb_build_object(
  'schemaVersion','0.1.0','storyId','b7000000-0000-4000-8000-000000000001','murdererAware',true,
  'scoringProfileVersion','score-v1',
  'victim',pg_catalog.jsonb_build_object('id','b8000000-0000-4000-8000-000000000001','name','NPC Curator','biography','Fictional curator','isNpc',true),
  'solution',pg_catalog.jsonb_build_object('murdererPlayerIds',pg_catalog.jsonb_build_array('b3000000-0000-4000-8000-000000000001'),'accomplicePlayerIds','[]'::jsonb,'innocentPlayerIds',pg_catalog.jsonb_build_array('b3000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000003','b3000000-0000-4000-8000-000000000004'),'motive','Fictional rivalry','method','Stage illusion'),
  'characters',(select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('playerId',id,'faction',case when seat_order=1 then 'MURDERER' else 'INNOCENT' end)) from room_players),
  'dossiers',(select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',('b9000000-0000-4000-8000-'||pg_catalog.lpad(n::text,12,'0'))::uuid,'playerId',id,'faction',case when seat_order=1 then 'MURDERER' else 'INNOCENT' end,'knownMurdererPlayerIds',case when seat_order=1 then pg_catalog.jsonb_build_array('b3000000-0000-4000-8000-000000000001') else '[]'::jsonb end)) from room_players),
  'relationships','[]'::jsonb,'timeline','[]'::jsonb,
  'rounds',(select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',id,'sequence',sequence,'title',title,'targetDurationSeconds',seconds,'publicEvent','Fictional event') order by sequence) from round_data),
  'evidence','[]'::jsonb,'evidenceDependencies','[]'::jsonb,
  'consequences',(select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',id,'severity',severity,'title','Complication','description','Harmless fictional complication','fictionalOnly',true,'eligibility',pg_catalog.jsonb_build_object('roundIds',pg_catalog.jsonb_build_array('b5000000-0000-4000-8000-000000000001'),'afterFailedMission',true))) from consequence_data),
  'missions',(select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',('ba000000-0000-4000-8000-'||pg_catalog.lpad(((rounds.sequence-1)*4+players.n)::text,12,'0'))::uuid,'roundId',rounds.id,'assignedPlayerId',players.id,'actionKind','ASK_PLAYER','objective','Ask a fictional question','completionRule','Ask it aloud','stakes','A fictional clue','hostConfirmationGuidance','Confirm it was asked','successEffect',null,'failureConsequenceId','b6000000-0000-4000-8000-000000000001')) from room_players as players cross join round_data as rounds),
  'interventions',pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'id','bc000000-0000-4000-8000-000000000001',
    'roundId','b5000000-0000-4000-8000-000000000002',
    'strength',1,
    'candidateKind','DIRECTED_QUESTION',
    'canonicalEffect',pg_catalog.jsonb_build_object(
      'kind','ASK_QUESTION','question','Which public alibi needs another comparison?'
    ),
    'presentation','Ask the group which public alibi needs another comparison.',
    'eligibleAfterSeconds',0
  )),
  'accompliceRevelations','[]'::jsonb,'finalReveal','[]'::jsonb
) as package;

select throws_ok(
  pg_catalog.format(
    'select public.lock_generated_story(%L,%L,%L::jsonb,%L,%L)',
    (select result ->> 'jobId' from generation_started), 'pgTAP-worker',
    (
      select pg_catalog.jsonb_set(
        package,
        '{dossiers,1,id}',
        package #> '{dossiers,0,id}'
      )::text
      from generated_story
    ),
    pg_catalog.repeat('00',32), pg_catalog.repeat('11',32)
  ),
  '23505',
  'duplicate key value violates unique constraint "dossiers_pkey"',
  'a materialization constraint failure aborts the atomic story lock'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.canonical_stories
    where room_id='b2000000-0000-4000-8000-000000000001'),
  0,
  'a failed materialization leaves no partial canonical story'
);
select is(
  (select status::text from app_private.rooms
    where id='b2000000-0000-4000-8000-000000000001'),
  'GENERATING',
  'a failed materialization leaves the room recoverable before lock'
);

select lives_ok(
  pg_catalog.format(
    'select public.lock_generated_story(%L,%L,%L::jsonb,%L,%L)',
    (select result ->> 'jobId' from generation_started), 'pgTAP-worker',
    (select package::text from generated_story), pg_catalog.repeat('00',32), pg_catalog.repeat('11',32)
  ),
  'a validated exact-player package locks and materializes atomically'
);
select is(
  (select status::text from app_private.rooms where id = 'b2000000-0000-4000-8000-000000000001'),
  'READY_TO_START',
  'the successful atomic lock makes the room ready to start'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.mission_specs where room_id = 'b2000000-0000-4000-8000-000000000001'),
  8,
  'every generated mission is materialized'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.mission_states where room_id = 'b2000000-0000-4000-8000-000000000001'),
  8,
  'runtime mission state is initialized at the same commit'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.player_descriptions where room_id = 'b2000000-0000-4000-8000-000000000001' and description_text is not null),
  0,
  'raw descriptions are purged immediately after lock'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.players where room_id = 'b2000000-0000-4000-8000-000000000001' and host_background is not null),
  0,
  'host background notes are purged immediately after lock'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  public.get_player_view('b2000000-0000-4000-8000-000000000001') #>> '{dossier,faction}',
  'MURDERER',
  'an aware murderer sees their own faction while another player never does'
);
select is(
  pg_catalog.jsonb_array_length(
    public.get_actor_view('b2000000-0000-4000-8000-000000000001') -> 'missions'
  ),
  0,
  'the actor API does not reveal future missions before play starts'
);

select lives_ok(
  $$select public.save_player_notebook(
    'b2000000-0000-4000-8000-000000000001', 0,
    'My owner-only notes', '[]'::jsonb
  )$$,
  'an active player creates an owner-only notebook'
);
select is(
  public.save_player_notebook(
    'b2000000-0000-4000-8000-000000000001', 0,
    'My revised owner-only notes', '[]'::jsonb
  ) ->> 'revision',
  '1',
  'notebook autosave increments its optimistic revision'
);
select throws_ok(
  $$select public.save_player_notebook(
    'b2000000-0000-4000-8000-000000000001', 0,
    'Stale overwrite', '[]'::jsonb
  )$$,
  'P4091', 'stale notebook revision',
  'a stale notebook write cannot overwrite a newer revision'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
create temporary table game_started as
select public.start_game(
  'b2000000-0000-4000-8000-000000000001',
  (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
  'bb000000-0000-4000-8000-000000000001'
) as result;
select is((select result ->> 'status' from game_started),'IN_PROGRESS','the Game Master starts active play manually');
select is(
  public.start_game(
    'b2000000-0000-4000-8000-000000000001', 0,
    'bb000000-0000-4000-8000-000000000001'
  ) ->> 'replayed',
  'true',
  'a duplicate command receipt replays without a second mutation'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  pg_catalog.jsonb_array_length(
    public.get_actor_view('b2000000-0000-4000-8000-000000000001') -> 'missions'
  ),
  1,
  'the actor API reveals only the current-round player mission'
);
select throws_ok(
  pg_catalog.format(
    'select public.player_mission_command(%L,%L,%s,%L,%L)',
    'b2000000-0000-4000-8000-000000000001',
    'ba000000-0000-4000-8000-000000000005',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000099',
    'ACCEPT'
  ),
  'P0002',
  'query returned no rows',
  'a player cannot bypass the projection to accept a future-round mission'
);
select is(
  public.player_mission_command(
    'b2000000-0000-4000-8000-000000000001',
    'ba000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000002','ACCEPT'
  ) ->> 'status',
  'ACCEPTED',
  'only the assigned active player accepts their mission'
);
select is(
  public.player_mission_command(
    'b2000000-0000-4000-8000-000000000001',
    'ba000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000003','REQUEST_COMPLETION'
  ) ->> 'status',
  'COMPLETION_REQUESTED',
  'the assigned player requests observable completion'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select is(
  public.adjudicate_mission(
    'b2000000-0000-4000-8000-000000000001',
    'ba000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000004','APPROVE',null
  ) ->> 'status',
  'COMPLETED',
  'only the Game Master adjudicates mission completion'
);
select is(
  public.adjudicate_mission(
    'b2000000-0000-4000-8000-000000000001',
    'ba000000-0000-4000-8000-000000000002',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000040','FAIL',null
  ) ->> 'status',
  'CONSEQUENCE_PENDING',
  'a failed mission activates only its eligible canonical consequence'
);
select is(
  public.resolve_canonical_release(
    'b2000000-0000-4000-8000-000000000001',
    'b6000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000041','CONSEQUENCE','RELEASE'
  ) ->> 'decision',
  'RELEASE',
  'the Game Master releases the prepared fictional consequence'
);
select is(
  (select status::text from app_private.mission_states
    where room_id='b2000000-0000-4000-8000-000000000001'
      and mission_spec_id='ba000000-0000-4000-8000-000000000002'),
  'CONSEQUENCE_RELEASED',
  'the failed mission records the released consequence exactly once'
);
select lives_ok(
  pg_catalog.format(
    'select public.advance_round(%L,%s,%L)',
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000005'
  ),
  'manual advance waives unfinished round missions without blocking play'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  public.submit_player_theory(
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000006',
    '{"suspects":[],"evidenceIds":[]}'::jsonb,
    'A submitted theory with no correctness response.'
  ) ->> 'correctness',
  null,
  'theory submission never returns a correctness signal'
);
select is(
  (select status::text from app_private.rooms
    where id='b2000000-0000-4000-8000-000000000001'),
  'IN_PROGRESS',
  'an early suspicion cannot end or auto-advance the game'
);
select is(
  (select pg_catalog.count(*)::integer from app_private.room_memberships
    where room_id='b2000000-0000-4000-8000-000000000001'
      and status='ACTIVE'),
  4,
  'an early suspicion cannot eliminate or revoke any player'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select ok(
  public.get_game_master_view('b2000000-0000-4000-8000-000000000001')::text
    not like '%My revised owner-only notes%',
  'the Game Master projection cannot read notebook text'
);

create temporary table intervention_requested as
select public.request_intervention(
  'b2000000-0000-4000-8000-000000000001',
  (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
  'bb000000-0000-4000-8000-000000000008'
) as result;
select is(
  (select result ->> 'status' from intervention_requested),
  'REQUESTED',
  'Discussion Stalled creates one bounded intervention request'
);
select ok(
  lower((select result -> 'context' from intervention_requested)::text)
    not like '%owner-only%'
  and lower((select result -> 'context' from intervention_requested)::text)
    not like '%submitted theory with no correctness%',
  'the intervention context excludes notebook and submitted theory prose'
);
create temporary table intervention_staged as
select public.stage_intervention_preview(
  'b2000000-0000-4000-8000-000000000001',
  ((select result ->> 'requestId' from intervention_requested))::uuid,
  null::uuid,null::uuid,'GENTLE','PROVIDER_TIMEOUT',null::text,null::text,
  0,0,12000,'PROVIDER_TIMEOUT'
) as result;
select is(
  (select result ->> 'selectionSource' from intervention_staged),
  'PREPARED_FALLBACK',
  'a provider timeout stages deterministic prepared canonical content'
);
select is(
  public.resolve_intervention(
    'b2000000-0000-4000-8000-000000000001',
    ((select result ->> 'requestId' from intervention_requested))::uuid,
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000009','REJECT'
  ) ->> 'status',
  'REJECTED',
  'the Game Master can reject a deterministic timeout fallback'
);
create temporary table invalid_ai_intervention_requested as
select public.request_intervention(
  'b2000000-0000-4000-8000-000000000001',
  (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
  'bb000000-0000-4000-8000-000000000080'
) as result;
create temporary table invalid_ai_intervention_staged as
select public.stage_intervention_preview(
  'b2000000-0000-4000-8000-000000000001',
  ((select result ->> 'requestId' from invalid_ai_intervention_requested))::uuid,
  'be000000-0000-4000-8000-000000000001'::uuid,null::uuid,
  'DIRECT','UNBLOCK_DISCUSSION','gpt-6.1-sol','resp-invalid-candidate',
  20,10,250,null::text
) as result;
select is(
  (select result ->> 'selectionSource' from invalid_ai_intervention_staged),
  'PREPARED_FALLBACK',
  'a model-selected ID outside the fresh canonical allowlist cannot stage AI content'
);
select is(
  public.resolve_intervention(
    'b2000000-0000-4000-8000-000000000001',
    ((select result ->> 'requestId' from invalid_ai_intervention_requested))::uuid,
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000081','APPROVE'
  ) ->> 'status',
  'RELEASED',
  'approval releases only the canonical fallback selected by the database'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  pg_catalog.jsonb_array_length(
    public.get_actor_view('b2000000-0000-4000-8000-000000000001')
      -> 'releasedInterventions'
  ),
  1,
  'players receive approved intervention content only after release'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  public.advance_round(
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bb000000-0000-4000-8000-000000000007'
  ) ->> 'status',
  'FINAL_ACCUSATIONS',
  'advancing the final round opens final accusations without a timer'
);
select ok(
  not exists (
    select 1 from app_private.game_events
    where room_id='b2000000-0000-4000-8000-000000000001'
      and (public_metadata_json::text like '%owner-only%' or private_payload_json::text like '%owner-only%')
  ),
  'append-only gameplay events contain no notebook or submitted prose'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select is(
  public.save_final_accusation(
    'b2000000-0000-4000-8000-000000000001', 0,
    '{"murdererPlayerIds":["b3000000-0000-4000-8000-000000000001"],"accomplicePlayerIds":[],"motive":"Fictional rivalry","method":"Stage illusion","evidenceIds":[]}'::jsonb,
    'Owner-only accusation draft.'
  ) ->> 'status',
  'DRAFT',
  'a player autosaves an owner-only revisioned final case'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select ok(
  public.get_game_master_view('b2000000-0000-4000-8000-000000000001')::text
    not like '%Owner-only accusation draft%',
  'the Game Master cannot read an accusation draft'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select is(
  public.submit_final_accusation(
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bd000000-0000-4000-8000-000000000001'
  ) ->> 'status',
  'SUBMITTED',
  'submission atomically exposes an immutable final case'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select is(
  pg_catalog.jsonb_array_length(
    public.get_game_master_view('b2000000-0000-4000-8000-000000000001')
      #> '{submittedState,finalAccusations}'
  ),
  1,
  'the Game Master sees submitted cases immediately but never drafts'
);
select is(
  public.close_final_accusations(
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bd000000-0000-4000-8000-000000000002',
    array[
      'b3000000-0000-4000-8000-000000000001',
      'b3000000-0000-4000-8000-000000000003',
      'b3000000-0000-4000-8000-000000000004'
    ]::uuid[], false
  ) ->> 'status',
  'SCORED',
  'the Game Master confirms every missing player and freezes scoring inputs'
);
select is(
  (select total_points from app_private.player_scores
    where room_id='b2000000-0000-4000-8000-000000000001'
      and player_id='b3000000-0000-4000-8000-000000000002'),
  60,
  'deterministic scoring awards murderer, full-set, motive, and method points'
);
select is(
  (select won from app_private.faction_results
    where room_id='b2000000-0000-4000-8000-000000000001'
      and faction='MURDERER'),
  true,
  'one of three innocent votes is not a strict majority, so the murderer wins'
);
select is(
  public.publish_reveal(
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bd000000-0000-4000-8000-000000000003'
  ) ->> 'status',
  'REVEAL',
  'the Game Master publishes the prepared truth and deterministic results'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select is(
  public.get_player_view('b2000000-0000-4000-8000-000000000001')
    #>> '{reveal,solution,canonicalSolution,motive}',
  'Fictional rivalry',
  'players receive the same canonical truth only after publication'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select is(
  public.complete_room(
    'b2000000-0000-4000-8000-000000000001',
    (select state_version from app_private.rooms where id='b2000000-0000-4000-8000-000000000001'),
    'bd000000-0000-4000-8000-000000000004'
  ) ->> 'status',
  'COMPLETED',
  'completion transaction finalizes the immutable Game Master case file'
);
select is(
  (select expires_at - completed_at from app_private.rooms
    where id='b2000000-0000-4000-8000-000000000001'),
  interval '30 days',
  'completed room expiry is exactly 30 days after completion'
);
select ok(
  (select content_json::text not like '%My revised owner-only notes%'
      and not pg_catalog.jsonb_path_exists(
        content_json,
        '$.submittedFinalAccusations[*] ? (@.status == "DRAFT")'::jsonpath
      )
    from app_private.case_files
    where room_id='b2000000-0000-4000-8000-000000000001'),
  'the complete case file excludes notebooks and unsubmitted accusation records'
);
select ok(
  (select content_json::text like '%Owner-only accusation draft%'
    from app_private.case_files
    where room_id='b2000000-0000-4000-8000-000000000001'),
  'submitted accusation prose is retained in the complete case file'
);
select ok(
  public.get_game_master_view('b2000000-0000-4000-8000-000000000001')
    #> '{results,caseFile,content}' is not null,
  'the completed Game Master projection includes the finalized case file'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select ok(
  not public.get_player_view('b2000000-0000-4000-8000-000000000001')
    ? 'results',
  'the completed player projection never receives the Game Master case file'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select throws_ok(
  pg_catalog.format(
    'select public.lock_generated_story(%L,%L,%L::jsonb,%L,%L)',
    (select result ->> 'jobId' from generation_started), 'pgTAP-worker',
    (select package::text from generated_story), pg_catalog.repeat('00',32), pg_catalog.repeat('11',32)
  ),
  '55000', 'generation lease is not owned',
  'a successfully locked room cannot regenerate'
);

select * from finish();
rollback;
