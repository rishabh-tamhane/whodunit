begin;

select plan(38);

select has_function(
  'public', 'get_game_master_view', array['uuid'],
  'Game Master projection RPC exists'
);
select has_function(
  'public', 'get_player_view', array['uuid'],
  'player projection RPC exists'
);
select has_function(
  'public', 'get_reveal_view', array['uuid'],
  'shared reveal projection RPC exists'
);
select has_function(
  'public', 'can_access_room_signals', array['uuid'],
  'signal authorization helper exists'
);
select policies_are(
  'public', 'room_signals', array['room_signals_authorized_read'],
  'room signals have one actor-scoped read policy'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.get_player_view(uuid)', 'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon', 'public.get_player_view(uuid)', 'EXECUTE'
  ),
  'only authenticated sessions may call actor projections'
);

insert into auth.users (id)
values
  ('d0000000-0000-4000-8000-000000000001'),
  ('d0000000-0000-4000-8000-000000000002'),
  ('d0000000-0000-4000-8000-000000000003'),
  ('d0000000-0000-4000-8000-000000000004'),
  ('d0000000-0000-4000-8000-000000000005'),
  ('d0000000-0000-4000-8000-000000000006');

insert into app_private.rooms (
  id, room_code, host_auth_user_id, status, state_version
)
values (
  'd1000000-0000-4000-8000-000000000001',
  'PROJECT1', 'd0000000-0000-4000-8000-000000000001',
  'LOBBY', 3
);

insert into app_private.room_host_principals (
  id, room_id, auth_user_id, started_at, ended_at
)
values (
  'd2000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-000000000005',
  app_private.current_database_time() - interval '2 hours',
  app_private.current_database_time() - interval '1 hour'
);

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values (
  'd2000000-0000-4000-8000-000000000002',
  'd1000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-000000000001'
);

set constraints all immediate;

insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume, seat_order
)
values
  (
    'd3000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'Anaya', 'anaya', 'Witch', 1
  ),
  (
    'd3000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'Vikram', 'vikram', 'Pirate', 2
  );

insert into app_private.room_memberships (
  id, room_id, auth_user_id, player_id, status, request_kind,
  approved_by_auth_user_id, last_seen_at, joined_at
)
values
  (
    'd4000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000001',
    'ACTIVE', 'INITIAL_CLAIM',
    'd0000000-0000-4000-8000-000000000001',
    app_private.current_database_time(), app_private.current_database_time()
  ),
  (
    'd4000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000003',
    'd3000000-0000-4000-8000-000000000002',
    'ACTIVE', 'INITIAL_CLAIM',
    'd0000000-0000-4000-8000-000000000001',
    app_private.current_database_time(), app_private.current_database_time()
  );

insert into app_private.room_memberships (
  id, room_id, auth_user_id, player_id, status, request_kind
)
values (
  'd4000000-0000-4000-8000-000000000003',
  'd1000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-000000000004',
  'd3000000-0000-4000-8000-000000000002',
  'PENDING', 'INITIAL_CLAIM'
);

insert into app_private.player_descriptions (
  room_id, author_player_id, subject_player_id, description_text
)
values (
  'd1000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000002',
  'raw generation input must never leak'
);

insert into app_private.story_generation_jobs (
  id, room_id, idempotency_key, status, phase, input_snapshot_json,
  blueprint_json, playable_content_json, model_id, prompt_version,
  story_schema_version, validator_version, started_at, finished_at
)
values (
  'd5000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5100000-0000-4000-8000-000000000001',
  'SUCCEEDED', 'COMPLETE',
  '{"rawDescription":"raw generation input must never leak"}'::jsonb,
  '{"privateDraft":true}'::jsonb, '{"privateDraft":true}'::jsonb,
  'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
  app_private.current_database_time(), app_private.current_database_time()
);

insert into app_private.canonical_stories (
  id, room_id, source_generation_job_id, story_schema_version,
  scoring_profile_version, prompt_version, model_id, package_json,
  package_checksum, solution_checksum, locked_at
)
values (
  'd6000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol',
  '{"title":"The Glass Palace","secret":"whole canonical truth"}'::jsonb,
  decode(repeat('41',32),'hex'), decode(repeat('42',32),'hex'),
  app_private.current_database_time()
);

insert into app_private.canonical_solutions (
  id, room_id, story_id, victim_json, solution_json
)
values (
  'd6100000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000001',
  '{"name":"The Curator"}'::jsonb,
  '{"murdererPlayerIds":["d3000000-0000-4000-8000-000000000002"]}'::jsonb
);

insert into app_private.story_rounds (
  id, room_id, story_id, sequence, title, target_duration_seconds,
  public_event_json
)
values (
  'd7000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000001',
  1, 'The Search', 600, '{}'::jsonb
);

insert into app_private.dossiers (
  id, room_id, story_id, player_id, faction,
  knowledge_policy_json, dossier_json
)
values
  (
    'd7100000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001',
    'INNOCENT', '{"factionVisible":true}'::jsonb,
    '{"role":"Archivist","privateSecret":"Anaya dossier"}'::jsonb
  ),
  (
    'd7100000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000002',
    'MURDERER', '{"factionVisible":false}'::jsonb,
    '{"role":"Collector","privateSecret":"Vikram dossier"}'::jsonb
  );

insert into app_private.evidence (
  id, room_id, story_id, round_id, evidence_kind, content_json,
  release_rule_json, audience_json
)
values
  (
    'd7200000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd7000000-0000-4000-8000-000000000001',
    'PUBLIC_NOTE', '{"text":"A public clue"}', '{}',
    '{"visibility":"PUBLIC"}'
  ),
  (
    'd7200000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd7000000-0000-4000-8000-000000000001',
    'PRIVATE_NOTE', '{"text":"Only Vikram may see this"}', '{}',
    '{"playerIds":["d3000000-0000-4000-8000-000000000002"]}'
  );

insert into app_private.final_reveal_sections (
  id, room_id, story_id, sequence, section_kind, section_json
)
values (
  'd7300000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000001',
  1, 'SOLUTION', '{"text":"The final chapter"}'::jsonb
);

update app_private.rooms
set status = 'IN_PROGRESS',
  story_id = 'd6000000-0000-4000-8000-000000000001',
  current_round_id = 'd7000000-0000-4000-8000-000000000001',
  scoring_profile_version = 'score-v1',
  locked_at = app_private.current_database_time(),
  updated_at = app_private.current_database_time()
where id = 'd1000000-0000-4000-8000-000000000001';

set constraints all immediate;

insert into app_private.command_receipts (
  id, room_id, idempotency_key, command_name, actor_type,
  request_hash, expected_state_version, result_state_version,
  response_status, result_json
)
values (
  'd8000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd8100000-0000-4000-8000-000000000001',
  'PROJECTION_TEST', 'SYSTEM', decode(repeat('43',32),'hex'),
  2, 3, 200, '{}'::jsonb
);

insert into app_private.evidence_releases (
  id, room_id, story_id, evidence_id, released_in_round_id,
  release_reason, command_receipt_id
)
values
  (
    'd9000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd7200000-0000-4000-8000-000000000001',
    'd7000000-0000-4000-8000-000000000001',
    'GUARANTEED', 'd8000000-0000-4000-8000-000000000001'
  ),
  (
    'd9000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd7200000-0000-4000-8000-000000000002',
    'd7000000-0000-4000-8000-000000000001',
    'STANDALONE', 'd8000000-0000-4000-8000-000000000001'
  );

insert into app_private.game_events (
  id, room_id, room_sequence, state_version, event_type, actor_type,
  command_receipt_id, public_metadata_json, private_payload_json
)
values (
  'da000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  1, 3, 'PUBLIC_EVENT', 'SYSTEM',
  'd8000000-0000-4000-8000-000000000001',
  '{"headline":"safe public event"}',
  '{"secret":"private event payload"}'
);

insert into public.room_signals (room_id, state_version, change_type)
values (
  'd1000000-0000-4000-8000-000000000001', 3, 'GAMEPLAY_CHANGED'
);

insert into app_private.player_notes (id, room_id, player_id, notes_text)
values
  (
    'db000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001', 'Anaya private notebook'
  ),
  (
    'db000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000002', 'Vikram private notebook'
  );

insert into app_private.player_theories (
  id, room_id, story_id, player_id, round_id, submitted_state_version,
  structured_claim_json, submitted_explanation, command_receipt_id
)
values
  (
    'dc000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001',
    'd7000000-0000-4000-8000-000000000001', 3,
    '{"suspect":"Vikram"}', 'Anaya submitted theory',
    'd8000000-0000-4000-8000-000000000001'
  ),
  (
    'dc000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000002',
    'd7000000-0000-4000-8000-000000000001', 3,
    '{"suspect":"Anaya"}', 'Vikram submitted theory',
    'd8000000-0000-4000-8000-000000000001'
  );

insert into app_private.final_accusations (
  id, room_id, story_id, player_id, structured_case_json, explanation_text
)
values
  (
    'dd000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000001',
    '{"suspect":"Vikram"}', 'Anaya draft accusation'
  ),
  (
    'dd000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000002',
    '{"suspect":"Anaya"}', 'Vikram submitted accusation'
  );

update app_private.final_accusations
set status = 'SUBMITTED', revision = 1, submitted_state_version = 3,
  submission_command_receipt_id = 'd8000000-0000-4000-8000-000000000001',
  submitted_at = app_private.current_database_time(),
  updated_at = app_private.current_database_time()
where id = 'dd000000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  public.get_game_master_view(
    'd1000000-0000-4000-8000-000000000001'
  ) ->> 'actor',
  'GAME_MASTER',
  'the current host receives the Game Master projection'
);

select is(
  public.get_game_master_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{story,package,secret}',
  'whole canonical truth',
  'the Game Master receives the complete canonical package after lock'
);

select is(
  public.get_game_master_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{story,solution,canonicalSolution,murdererPlayerIds,0}',
  'd3000000-0000-4000-8000-000000000002',
  'the Game Master receives the canonical solution after lock'
);

select is(
  pg_catalog.jsonb_array_length(
    public.get_game_master_view(
      'd1000000-0000-4000-8000-000000000001'
    ) #> '{submittedState,finalAccusations}'
  ),
  1,
  'the Game Master sees submitted accusations but not player drafts'
);

select ok(
  pg_catalog.strpos(
    public.get_game_master_view(
      'd1000000-0000-4000-8000-000000000001'
    )::text,
    'raw generation input must never leak'
  ) = 0
  and pg_catalog.strpos(
    public.get_game_master_view(
      'd1000000-0000-4000-8000-000000000001'
    )::text,
    'private notebook'
  ) = 0,
  'the Game Master projection excludes raw descriptions and notebooks'
);

select is(
  (select pg_catalog.count(*)::integer from public.room_signals),
  1,
  'the current Game Master can subscribe to content-free signals'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

select throws_ok(
  $sql$
    select public.get_game_master_view(
      'd1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '42501', 'current Game Master authorization required',
  'a former host cannot read the current Game Master view'
);

select is(
  (select pg_catalog.count(*)::integer from public.room_signals),
  0,
  'a former host cannot subscribe to room signals'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) ->> 'actor',
  'PLAYER',
  'an active player receives the player projection'
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{dossier,content,privateSecret}',
  'Anaya dossier',
  'a player receives only their own dossier'
);

select ok(
  not public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) ? 'story',
  'a pre-reveal player never receives the canonical story'
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{dossier,faction}',
  'INNOCENT',
  'a pre-reveal player receives their own authorized faction'
);

select is(
  pg_catalog.jsonb_array_length(
    public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    ) -> 'evidence'
  ),
  1,
  'a player receives released evidence only for an allowed audience'
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{notebook,notesText}',
  'Anaya private notebook',
  'a player receives their owner-only notebook'
);

select is(
  pg_catalog.jsonb_array_length(
    public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    ) -> 'submittedTheories'
  ),
  1,
  'a player receives only their own submitted theories'
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{finalAccusation,status}',
  'DRAFT',
  'a player receives their owner-only final accusation draft'
);

select ok(
  pg_catalog.strpos(
    public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    )::text,
    'private event payload'
  ) = 0
  and pg_catalog.strpos(
    public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    )::text,
    'Vikram private notebook'
  ) = 0,
  'the player view excludes event private payloads and another notebook'
);

select is(
  (select pg_catalog.count(*)::integer from public.room_signals),
  1,
  'an active player can subscribe to content-free signals'
);

select throws_ok(
  $sql$
    select public.get_game_master_view(
      'd1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '42501', 'current Game Master authorization required',
  'a player cannot call the Game Master projection'
);

select throws_ok(
  $sql$
    select public.get_reveal_view(
      'd1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '55000', 'reveal is not published',
  'an active player cannot fetch the solution before reveal'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);

select is(
  pg_catalog.jsonb_array_length(
    public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    ) -> 'evidence'
  ),
  2,
  'a targeted player receives both public and targeted released evidence'
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{notebook,notesText}',
  'Vikram private notebook',
  'a second player receives only the second player notebook'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);

select throws_ok(
  $sql$
    select public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '42501', 'active player authorization required',
  'a pending claimant cannot read a player view'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

select throws_ok(
  $sql$
    select public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '42501', 'active player authorization required',
  'an outsider cannot read a player view'
);

select is(
  (select pg_catalog.count(*)::integer from public.room_signals),
  0,
  'an outsider cannot subscribe to room signals'
);

reset role;

update app_private.rooms
set status = 'REVEAL', updated_at = app_private.current_database_time()
where id = 'd1000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{dossier,faction}',
  'INNOCENT',
  'the player true faction becomes visible during reveal'
);

select is(
  public.get_player_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{reveal,solution,canonicalSolution,murdererPlayerIds,0}',
  'd3000000-0000-4000-8000-000000000002',
  'the shared solution enters the player view only during reveal'
);

select is(
  public.get_reveal_view(
    'd1000000-0000-4000-8000-000000000001'
  ) #>> '{reveal,sections,0,content,text}',
  'The final chapter',
  'an active player can fetch the published dramatic reveal'
);

select is(
  pg_catalog.jsonb_array_length(
    public.get_reveal_view(
      'd1000000-0000-4000-8000-000000000001'
    ) #> '{reveal,submittedAccusations}'
  ),
  1,
  'submitted final accusations become shared only in the reveal'
);

select ok(
  not (public.get_reveal_view(
    'd1000000-0000-4000-8000-000000000001'
  ) -> 'reveal') ? 'caseFile',
  'the shared player reveal excludes the Game Master-only case file'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  public.get_reveal_view(
    'd1000000-0000-4000-8000-000000000001'
  ) ->> 'status',
  'REVEAL',
  'the current Game Master can fetch the shared reveal surface'
);

select throws_ok(
  $sql$
    select public.get_player_view(
      'd1000000-0000-4000-8000-000000000001'
    )
  $sql$,
  '42501', 'active player authorization required',
  'the dedicated Game Master still cannot receive player-only UI at reveal'
);

select * from finish();

rollback;
