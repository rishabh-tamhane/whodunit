begin;

select plan(46);

create or replace function pg_temp.capture_sqlstate(
  command text,
  force_deferred_constraints boolean default false
)
returns text
language plpgsql
as $function$
begin
  execute command;

  if force_deferred_constraints then
    set constraints all immediate;
    set constraints all deferred;
  end if;

  return null;
exception
  when others then
    if force_deferred_constraints then
      set constraints all deferred;
    end if;

    return sqlstate;
end;
$function$;

select has_table('app_private', 'player_notes', 'player notebooks exist');
select has_table(
  'app_private',
  'player_note_suspects',
  'notebook suspect drafts exist'
);
select has_table('app_private', 'player_theories', 'submitted theories exist');
select has_table(
  'app_private',
  'player_theory_suspects',
  'theory suspect snapshots exist'
);
select has_table(
  'app_private',
  'player_theory_evidence',
  'theory evidence snapshots exist'
);
select has_table(
  'app_private',
  'final_accusations',
  'final accusation drafts and submissions exist'
);
select has_table(
  'app_private',
  'final_accusation_suspects',
  'final accusation suspect selections exist'
);
select has_table(
  'app_private',
  'final_accusation_evidence',
  'final accusation evidence selections exist'
);

select ok(
  not pg_catalog.has_table_privilege(
    'anon',
    'app_private.player_notes',
    'SELECT'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'app_private.final_accusations',
    'SELECT'
  ),
  'API roles cannot directly read player-private or submitted state'
);

select is(
  (
    select pg_catalog.count(*)::integer
    from information_schema.columns as c
    where c.table_schema = 'app_private'
      and c.table_name in (
        'player_notes',
        'player_note_suspects',
        'player_theories',
        'player_theory_suspects',
        'player_theory_evidence',
        'final_accusations',
        'final_accusation_suspects',
        'final_accusation_evidence'
      )
      and c.column_name = 'room_id'
      and c.is_nullable = 'NO'
  ),
  8,
  'every private or submitted-state row has required room scope'
);

insert into auth.users (id)
values
  ('d0000000-0000-4000-8000-000000000001'),
  ('d0000000-0000-4000-8000-000000000002');

insert into app_private.rooms (id, room_code, host_auth_user_id, state_version)
values
  (
    'd1000000-0000-4000-8000-000000000001',
    'PRIVATEA',
    'd0000000-0000-4000-8000-000000000001',
    1
  ),
  (
    'd1000000-0000-4000-8000-000000000002',
    'PRIVATEB',
    'd0000000-0000-4000-8000-000000000002',
    1
  );

insert into app_private.room_host_principals (id, room_id, auth_user_id)
values
  (
    'd2000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000001'
  ),
  (
    'd2000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd0000000-0000-4000-8000-000000000002'
  );

set constraints all immediate;

insert into app_private.players (
  id, room_id, display_name, display_name_normalized, costume, seat_order
)
values
  (
    'd3000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'Leela', 'leela', 'Ghost', 1
  ),
  (
    'd3000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'Dev', 'dev', 'Pirate', 2
  ),
  (
    'd3000000-0000-4000-8000-000000000003',
    'd1000000-0000-4000-8000-000000000002',
    'Noor', 'noor', 'Vampire', 1
  );

insert into app_private.story_generation_jobs (
  id, room_id, idempotency_key, status, phase, input_snapshot_json,
  model_id, prompt_version, story_schema_version, validator_version,
  started_at, finished_at
)
values
  (
    'd4000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd4100000-0000-4000-8000-000000000001',
    'SUCCEEDED', 'COMPLETE', '{}'::jsonb,
    'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
    app_private.current_database_time(), app_private.current_database_time()
  ),
  (
    'd4000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd4100000-0000-4000-8000-000000000002',
    'SUCCEEDED', 'COMPLETE', '{}'::jsonb,
    'gpt-6.1-sol', 'prompt-v1', 'story-v1', 'validator-v1',
    app_private.current_database_time(), app_private.current_database_time()
  );

insert into app_private.canonical_stories (
  id, room_id, source_generation_job_id, story_schema_version,
  scoring_profile_version, prompt_version, model_id, package_json,
  package_checksum, solution_checksum, locked_at
)
values
  (
    'd5000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd4000000-0000-4000-8000-000000000001',
    'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
    decode(repeat('41', 32), 'hex'), decode(repeat('42', 32), 'hex'),
    app_private.current_database_time()
  ),
  (
    'd5000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd4000000-0000-4000-8000-000000000002',
    'story-v1', 'score-v1', 'prompt-v1', 'gpt-6.1-sol', '{}'::jsonb,
    decode(repeat('51', 32), 'hex'), decode(repeat('52', 32), 'hex'),
    app_private.current_database_time()
  );

insert into app_private.story_rounds (
  id, room_id, story_id, sequence, title, target_duration_seconds,
  public_event_json
)
values
  (
    'd6000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd5000000-0000-4000-8000-000000000001',
    1, 'Investigation', 600, '{}'::jsonb
  ),
  (
    'd6000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd5000000-0000-4000-8000-000000000002',
    1, 'Investigation', 600, '{}'::jsonb
  );

insert into app_private.evidence (
  id, room_id, story_id, round_id, evidence_kind, content_json,
  release_rule_json, audience_json
)
values
  (
    'd7000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd5000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'PHYSICAL', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  ),
  (
    'd7000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'd5000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'TESTIMONY', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  ),
  (
    'd7000000-0000-4000-8000-000000000003',
    'd1000000-0000-4000-8000-000000000002',
    'd5000000-0000-4000-8000-000000000002',
    'd6000000-0000-4000-8000-000000000002',
    'PHYSICAL', '{}'::jsonb, '{}'::jsonb, '{}'::jsonb
  );

insert into app_private.command_receipts (
  id, room_id, idempotency_key, command_name, actor_type,
  request_hash, expected_state_version, result_state_version,
  response_status, result_json
)
values
  (
    'd8000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd8100000-0000-4000-8000-000000000001',
    'PLAYER_SUBMISSION', 'SYSTEM', decode(repeat('61', 32), 'hex'),
    0, 1, 200, '{}'::jsonb
  ),
  (
    'd8000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd8100000-0000-4000-8000-000000000002',
    'PLAYER_SUBMISSION', 'SYSTEM', decode(repeat('62', 32), 'hex'),
    0, 1, 200, '{}'::jsonb
  );

insert into app_private.evidence_releases (
  id, room_id, story_id, evidence_id, released_in_round_id,
  release_reason, command_receipt_id
)
values
  (
    'd9000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'd5000000-0000-4000-8000-000000000001',
    'd7000000-0000-4000-8000-000000000001',
    'd6000000-0000-4000-8000-000000000001',
    'STANDALONE', 'd8000000-0000-4000-8000-000000000001'
  ),
  (
    'd9000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000002',
    'd5000000-0000-4000-8000-000000000002',
    'd7000000-0000-4000-8000-000000000003',
    'd6000000-0000-4000-8000-000000000002',
    'STANDALONE', 'd8000000-0000-4000-8000-000000000002'
  );

insert into app_private.player_notes (
  id, room_id, player_id, notes_text
)
values (
  'da000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'The clock stopped before midnight.'
);

select is(
  (select revision::integer from app_private.player_notes
    where id = 'da000000-0000-4000-8000-000000000001'),
  0,
  'a notebook begins at revision zero'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_notes (
      room_id, player_id, revision
    ) values (
      'd1000000-0000-4000-8000-000000000002',
      'd3000000-0000-4000-8000-000000000003', 1
    )
  $sql$),
  '23514',
  'a notebook cannot begin at a later revision'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_note_suspects (
      room_id, owner_player_id, note_id, notebook_revision,
      suspect_player_id, suspected_role
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'da000000-0000-4000-8000-000000000001', 0,
      'd3000000-0000-4000-8000-000000000003', 'MURDERER'
    )
  $sql$),
  '23503',
  'a notebook cannot select a suspect from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_note_suspects (
      room_id, owner_player_id, note_id, notebook_revision,
      suspect_player_id, suspected_role
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'da000000-0000-4000-8000-000000000001', 0,
      'd3000000-0000-4000-8000-000000000001', 'MURDERER'
    )
  $sql$),
  '23514',
  'a player cannot select themselves as a notebook suspect'
);

insert into app_private.player_note_suspects (
  id, room_id, owner_player_id, note_id, notebook_revision,
  suspect_player_id, suspected_role
)
values (
  'db000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'da000000-0000-4000-8000-000000000001', 0,
  'd3000000-0000-4000-8000-000000000002', 'MURDERER'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.player_note_suspects
    where owner_player_id = 'd3000000-0000-4000-8000-000000000001'),
  1,
  'notebook suspect drafts are keyed to their owner'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_notes
    set revision = 0, notes_text = 'stale write',
      updated_at = app_private.current_database_time()
    where id = 'da000000-0000-4000-8000-000000000001'
  $sql$),
  'P4091',
  'a stale notebook revision conflicts'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_notes
    set revision = 1, notes_text = 'partial write',
      updated_at = app_private.current_database_time()
    where id = 'da000000-0000-4000-8000-000000000001'
  $sql$, true),
  '23503',
  'a notebook revision cannot commit without its suspect draft revision'
);

set constraints all deferred;
update app_private.player_note_suspects
set notebook_revision = 1
where id = 'db000000-0000-4000-8000-000000000001';
update app_private.player_notes
set revision = 1, notes_text = 'Updated private notes',
  updated_at = app_private.current_database_time()
where id = 'da000000-0000-4000-8000-000000000001';
set constraints all immediate;

select is(
  (select revision::integer from app_private.player_notes
    where id = 'da000000-0000-4000-8000-000000000001'),
  1,
  'a complete optimistic notebook save advances one revision'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_notes
    set revision = 2, notes_text = repeat('x', 10001),
      updated_at = app_private.current_database_time()
    where id = 'da000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'notebook prose has a bounded size'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_notes (room_id, player_id)
    values (
      'd1000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'each player has one stable notebook'
);

insert into app_private.player_theories (
  id, room_id, story_id, player_id, round_id, submitted_state_version,
  structured_claim_json, submitted_explanation, command_receipt_id
)
values (
  'dc000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'd6000000-0000-4000-8000-000000000001', 1,
  '{"motive":"jealousy"}'::jsonb, 'My submitted explanation',
  'd8000000-0000-4000-8000-000000000001'
);

select is(
  (select pg_catalog.count(*)::integer from app_private.player_theories
    where player_id = 'd3000000-0000-4000-8000-000000000001'),
  1,
  'a player can create an immutable submitted theory snapshot'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_theories (
      room_id, story_id, player_id, round_id, submitted_state_version,
      structured_claim_json, command_receipt_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000003',
      'd6000000-0000-4000-8000-000000000001', 1, '{}'::jsonb,
      'd8000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23503',
  'a theory owner cannot come from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_theories (
      room_id, story_id, player_id, round_id, submitted_state_version,
      structured_claim_json, command_receipt_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'd6000000-0000-4000-8000-000000000002', 1, '{}'::jsonb,
      'd8000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23503',
  'a submitted theory cannot use another story round'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_theories (
      room_id, story_id, player_id, round_id, submitted_state_version,
      structured_claim_json, command_receipt_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'd6000000-0000-4000-8000-000000000001', 1, '[]'::jsonb,
      'd8000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23514',
  'submitted structured theory claims must be JSON objects'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_theory_evidence (
      room_id, story_id, theory_id, evidence_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'dc000000-0000-4000-8000-000000000001',
      'd7000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'a theory cannot cite unreleased evidence'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_theory_suspects (
      room_id, story_id, theory_id, suspect_player_id, suspected_role
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'dc000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000003', 'MURDERER'
    )
  $sql$),
  '23503',
  'a theory cannot select a suspect from another room'
);

insert into app_private.player_theory_suspects (
  id, room_id, story_id, theory_id, suspect_player_id, suspected_role
)
values (
  'dd000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'dc000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000002', 'MURDERER'
);
insert into app_private.player_theory_evidence (
  id, room_id, story_id, theory_id, evidence_id
)
values (
  'de000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'dc000000-0000-4000-8000-000000000001',
  'd7000000-0000-4000-8000-000000000001'
);

select is(
  (
    select (
      (select pg_catalog.count(*) from app_private.player_theory_suspects
        where theory_id = 'dc000000-0000-4000-8000-000000000001')
      + (select pg_catalog.count(*) from app_private.player_theory_evidence
        where theory_id = 'dc000000-0000-4000-8000-000000000001')
    )::integer
  ),
  2,
  'submitted theory suspect and evidence selections are stored as snapshots'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_theories
    set submitted_explanation = 'overwritten'
    where id = 'dc000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted theory prose cannot be overwritten'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.player_theories
    where id = 'dc000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted theory snapshots cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.player_theory_suspects
    set suspected_role = 'ACCOMPLICE'
    where id = 'dd000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted theory suspect selections cannot be overwritten'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.player_theory_evidence (
      room_id, story_id, theory_id, evidence_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'dc000000-0000-4000-8000-000000000001',
      'd7000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'submitted theory evidence selections cannot be duplicated'
);

insert into app_private.final_accusations (
  id, room_id, story_id, player_id, structured_case_json
)
values (
  'df000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001', '{}'::jsonb
);

select is(
  (select status::text from app_private.final_accusations
    where id = 'df000000-0000-4000-8000-000000000001'),
  'DRAFT',
  'a final accusation begins as an owner-only draft'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_accusations (
      room_id, story_id, player_id, status, revision,
      submitted_state_version, submission_command_receipt_id, submitted_at
    ) values (
      'd1000000-0000-4000-8000-000000000002',
      'd5000000-0000-4000-8000-000000000002',
      'd3000000-0000-4000-8000-000000000003',
      'SUBMITTED', 0, 1, 'd8000000-0000-4000-8000-000000000002',
      app_private.current_database_time()
    )
  $sql$),
  '23514',
  'a final accusation cannot be inserted already submitted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_accusations (
      room_id, story_id, player_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001'
    )
  $sql$),
  '23505',
  'a player has one final accusation record per story'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_accusations (
      room_id, story_id, player_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000003'
    )
  $sql$),
  '23503',
  'a final accusation owner cannot come from another room'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.final_accusations
    set revision = 0, explanation_text = 'stale',
      updated_at = app_private.current_database_time()
    where id = 'df000000-0000-4000-8000-000000000001'
  $sql$),
  'P4091',
  'a stale final accusation draft revision conflicts'
);

update app_private.final_accusations
set revision = 1, explanation_text = 'Dev had the key.',
  updated_at = app_private.current_database_time()
where id = 'df000000-0000-4000-8000-000000000001';

select is(
  (select revision::integer from app_private.final_accusations
    where id = 'df000000-0000-4000-8000-000000000001'),
  1,
  'a current final accusation draft advances one revision'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_accusation_suspects (
      room_id, story_id, owner_player_id, accusation_id,
      accusation_revision, suspect_player_id, suspected_role
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'df000000-0000-4000-8000-000000000001', 1,
      'd3000000-0000-4000-8000-000000000003', 'MURDERER'
    )
  $sql$),
  '23503',
  'a final accusation cannot select another room player'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_accusation_evidence (
      room_id, story_id, owner_player_id, accusation_id,
      accusation_revision, evidence_id
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'df000000-0000-4000-8000-000000000001', 1,
      'd7000000-0000-4000-8000-000000000002'
    )
  $sql$),
  '23503',
  'a final accusation cannot cite unreleased evidence'
);

insert into app_private.final_accusation_suspects (
  id, room_id, story_id, owner_player_id, accusation_id,
  accusation_revision, suspect_player_id, suspected_role
)
values (
  'e0000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'df000000-0000-4000-8000-000000000001', 1,
  'd3000000-0000-4000-8000-000000000002', 'MURDERER'
);
insert into app_private.final_accusation_evidence (
  id, room_id, story_id, owner_player_id, accusation_id,
  accusation_revision, evidence_id
)
values (
  'e1000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000001',
  'df000000-0000-4000-8000-000000000001', 1,
  'd7000000-0000-4000-8000-000000000001'
);

set constraints all deferred;
update app_private.final_accusation_suspects
set accusation_revision = 2
where id = 'e0000000-0000-4000-8000-000000000001';
update app_private.final_accusation_evidence
set accusation_revision = 2
where id = 'e1000000-0000-4000-8000-000000000001';
update app_private.final_accusations
set status = 'SUBMITTED', revision = 2, submitted_state_version = 1,
  submission_command_receipt_id = 'd8000000-0000-4000-8000-000000000001',
  submitted_at = app_private.current_database_time(),
  updated_at = app_private.current_database_time()
where id = 'df000000-0000-4000-8000-000000000001';
set constraints all immediate;

select is(
  (select status::text from app_private.final_accusations
    where id = 'df000000-0000-4000-8000-000000000001'),
  'SUBMITTED',
  'a current accusation draft becomes a fixed submitted snapshot'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.final_accusations
    set revision = 3, explanation_text = 'changed after submit',
      updated_at = app_private.current_database_time()
    where id = 'df000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted final accusation content cannot be overwritten'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.final_accusations
    where id = 'df000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted final accusation snapshots cannot be deleted'
);

select is(
  pg_temp.capture_sqlstate($sql$
    insert into app_private.final_accusation_suspects (
      room_id, story_id, owner_player_id, accusation_id,
      accusation_revision, suspect_player_id, suspected_role
    ) values (
      'd1000000-0000-4000-8000-000000000001',
      'd5000000-0000-4000-8000-000000000001',
      'd3000000-0000-4000-8000-000000000001',
      'df000000-0000-4000-8000-000000000001', 2,
      'd3000000-0000-4000-8000-000000000001', 'ACCOMPLICE'
    )
  $sql$),
  '23514',
  'submitted final accusation suspect selections cannot be added'
);

select is(
  pg_temp.capture_sqlstate($sql$
    update app_private.final_accusation_evidence
    set evidence_id = 'd7000000-0000-4000-8000-000000000002'
    where id = 'e1000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted final accusation evidence selections cannot be changed'
);

select is(
  pg_temp.capture_sqlstate($sql$
    delete from app_private.final_accusation_suspects
    where id = 'e0000000-0000-4000-8000-000000000001'
  $sql$),
  '23514',
  'submitted final accusation selections cannot be deleted'
);

select ok(
  not pg_catalog.has_function_privilege(
    'anon',
    'app_private.enforce_player_note_revision()',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'app_private.enforce_final_accusation_transition()',
    'EXECUTE'
  ),
  'API roles cannot invoke private-state transition triggers directly'
);

select * from finish();

rollback;
