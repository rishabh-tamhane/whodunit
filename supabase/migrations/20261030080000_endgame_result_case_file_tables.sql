-- DB-08: frozen endgame inputs, deterministic results, reveal, and case file.

create table app_private.scoring_snapshots (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_profile_version text not null,
  scoring_profile_checksum bytea not null,
  story_package_checksum bytea not null,
  solution_checksum bytea not null,
  frozen_input_checksum bytea not null,
  source_state_version bigint not null,
  source_last_event_sequence bigint not null,
  frozen_input_json jsonb not null,
  finalized_at timestamp with time zone not null default app_private.current_database_time(),
  constraint scoring_snapshots_room_unique unique (room_id),
  constraint scoring_snapshots_room_story_id_unique unique (room_id, story_id, id),
  constraint scoring_snapshots_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint scoring_snapshots_checksums_length check (
    pg_catalog.octet_length(scoring_profile_checksum) = 32
    and pg_catalog.octet_length(story_package_checksum) = 32
    and pg_catalog.octet_length(solution_checksum) = 32
    and pg_catalog.octet_length(frozen_input_checksum) = 32
  ),
  constraint scoring_snapshots_profile_version_present check (
    pg_catalog.char_length(pg_catalog.btrim(scoring_profile_version)) > 0
  ),
  constraint scoring_snapshots_versions_nonnegative check (
    source_state_version >= 0 and source_last_event_sequence >= 0
  ),
  constraint scoring_snapshots_input_object check (
    pg_catalog.jsonb_typeof(frozen_input_json) = 'object'
  )
);

create table app_private.player_scores (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_snapshot_id uuid not null,
  player_id uuid not null,
  final_accusation_id uuid not null,
  total_points integer not null,
  breakdown_json jsonb not null,
  explanation text not null,
  constraint player_scores_snapshot_player_unique unique (
    scoring_snapshot_id,
    player_id
  ),
  constraint player_scores_room_story_id_unique unique (room_id, story_id, id),
  constraint player_scores_snapshot_room_story_fk foreign key (
    room_id,
    story_id,
    scoring_snapshot_id
  ) references app_private.scoring_snapshots (room_id, story_id, id)
    on delete cascade,
  constraint player_scores_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint player_scores_accusation_room_story_fk foreign key (
    room_id,
    story_id,
    final_accusation_id
  ) references app_private.final_accusations (room_id, story_id, id)
    on delete restrict,
  constraint player_scores_breakdown_object check (
    pg_catalog.jsonb_typeof(breakdown_json) = 'object'
  ),
  constraint player_scores_explanation_present check (
    pg_catalog.char_length(pg_catalog.btrim(explanation)) between 1 and 4000
  )
);

create table app_private.theory_scores (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_snapshot_id uuid not null,
  theory_id uuid not null,
  player_id uuid not null,
  points integer not null,
  breakdown_json jsonb not null,
  explanation text not null,
  constraint theory_scores_snapshot_theory_unique unique (
    scoring_snapshot_id,
    theory_id
  ),
  constraint theory_scores_snapshot_room_story_fk foreign key (
    room_id,
    story_id,
    scoring_snapshot_id
  ) references app_private.scoring_snapshots (room_id, story_id, id)
    on delete cascade,
  constraint theory_scores_theory_room_story_fk foreign key (
    room_id,
    story_id,
    theory_id
  ) references app_private.player_theories (room_id, story_id, id)
    on delete restrict,
  constraint theory_scores_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint theory_scores_breakdown_object check (
    pg_catalog.jsonb_typeof(breakdown_json) = 'object'
  ),
  constraint theory_scores_explanation_present check (
    pg_catalog.char_length(pg_catalog.btrim(explanation)) between 1 and 4000
  )
);

create table app_private.faction_results (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_snapshot_id uuid not null,
  faction app_private.faction not null,
  won boolean not null,
  result_json jsonb not null,
  explanation text not null,
  constraint faction_results_snapshot_faction_unique unique (
    scoring_snapshot_id,
    faction
  ),
  constraint faction_results_snapshot_room_story_fk foreign key (
    room_id,
    story_id,
    scoring_snapshot_id
  ) references app_private.scoring_snapshots (room_id, story_id, id)
    on delete cascade,
  constraint faction_results_result_object check (
    pg_catalog.jsonb_typeof(result_json) = 'object'
  ),
  constraint faction_results_explanation_present check (
    pg_catalog.char_length(pg_catalog.btrim(explanation)) between 1 and 4000
  )
);

create table app_private.player_awards (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_snapshot_id uuid not null,
  player_id uuid not null,
  award_code text not null,
  title text not null,
  description text not null,
  award_json jsonb not null default '{}'::jsonb,
  constraint player_awards_snapshot_code_unique unique (
    scoring_snapshot_id,
    award_code
  ),
  constraint player_awards_snapshot_room_story_fk foreign key (
    room_id,
    story_id,
    scoring_snapshot_id
  ) references app_private.scoring_snapshots (room_id, story_id, id)
    on delete cascade,
  constraint player_awards_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint player_awards_code_supported check (
    award_code ~ '^[A-Z][A-Z0-9_]{1,99}$'
  ),
  constraint player_awards_copy_present check (
    pg_catalog.char_length(pg_catalog.btrim(title)) between 1 and 100
    and pg_catalog.char_length(pg_catalog.btrim(description)) between 1 and 1000
  ),
  constraint player_awards_payload_object check (
    pg_catalog.jsonb_typeof(award_json) = 'object'
  )
);

create table app_private.reveal_publications (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_snapshot_id uuid not null,
  command_receipt_id uuid not null,
  publication_state_version bigint not null,
  scoring_profile_version text not null,
  scoring_profile_checksum bytea not null,
  story_package_checksum bytea not null,
  solution_checksum bytea not null,
  frozen_input_checksum bytea not null,
  reveal_checksum bytea not null,
  published_payload_json jsonb not null,
  published_at timestamp with time zone not null default app_private.current_database_time(),
  constraint reveal_publications_room_unique unique (room_id),
  constraint reveal_publications_room_story_id_unique unique (room_id, story_id, id),
  constraint reveal_publications_snapshot_room_story_fk foreign key (
    room_id,
    story_id,
    scoring_snapshot_id
  ) references app_private.scoring_snapshots (room_id, story_id, id)
    on delete restrict,
  constraint reveal_publications_command_room_fk foreign key (
    room_id,
    command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint reveal_publications_checksums_length check (
    pg_catalog.octet_length(scoring_profile_checksum) = 32
    and pg_catalog.octet_length(story_package_checksum) = 32
    and pg_catalog.octet_length(solution_checksum) = 32
    and pg_catalog.octet_length(frozen_input_checksum) = 32
    and pg_catalog.octet_length(reveal_checksum) = 32
  ),
  constraint reveal_publications_profile_version_present check (
    pg_catalog.char_length(pg_catalog.btrim(scoring_profile_version)) > 0
  ),
  constraint reveal_publications_state_version_nonnegative check (
    publication_state_version >= 0
  ),
  constraint reveal_publications_payload_object check (
    pg_catalog.jsonb_typeof(published_payload_json) = 'object'
  )
);

create table app_private.case_files (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  scoring_snapshot_id uuid not null,
  reveal_publication_id uuid not null,
  case_file_schema_version text not null,
  scoring_profile_version text not null,
  scoring_profile_checksum bytea not null,
  story_package_checksum bytea not null,
  solution_checksum bytea not null,
  frozen_input_checksum bytea not null,
  reveal_checksum bytea not null,
  content_checksum bytea not null,
  content_json jsonb not null,
  finalized_at timestamp with time zone not null default app_private.current_database_time(),
  constraint case_files_room_unique unique (room_id),
  constraint case_files_room_story_id_unique unique (room_id, story_id, id),
  constraint case_files_snapshot_room_story_fk foreign key (
    room_id,
    story_id,
    scoring_snapshot_id
  ) references app_private.scoring_snapshots (room_id, story_id, id)
    on delete restrict,
  constraint case_files_reveal_room_story_fk foreign key (
    room_id,
    story_id,
    reveal_publication_id
  ) references app_private.reveal_publications (room_id, story_id, id)
    on delete restrict,
  constraint case_files_checksums_length check (
    pg_catalog.octet_length(scoring_profile_checksum) = 32
    and pg_catalog.octet_length(story_package_checksum) = 32
    and pg_catalog.octet_length(solution_checksum) = 32
    and pg_catalog.octet_length(frozen_input_checksum) = 32
    and pg_catalog.octet_length(reveal_checksum) = 32
    and pg_catalog.octet_length(content_checksum) = 32
  ),
  constraint case_files_versions_present check (
    pg_catalog.char_length(pg_catalog.btrim(case_file_schema_version)) > 0
    and pg_catalog.char_length(pg_catalog.btrim(scoring_profile_version)) > 0
  ),
  constraint case_files_content_object check (
    pg_catalog.jsonb_typeof(content_json) = 'object'
  )
);

create index player_scores_room_total_idx
  on app_private.player_scores (room_id, total_points desc);
create index theory_scores_room_player_idx
  on app_private.theory_scores (room_id, player_id);
create index player_awards_room_player_idx
  on app_private.player_awards (room_id, player_id);

create function app_private.validate_scoring_snapshot_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_story app_private.canonical_stories%rowtype;
begin
  select story.*
  into source_story
  from app_private.canonical_stories as story
  where story.room_id = new.room_id
    and story.id = new.story_id;

  if not found
    or new.scoring_profile_version <> source_story.scoring_profile_version
    or new.story_package_checksum <> source_story.package_checksum
    or new.solution_checksum <> source_story.solution_checksum then
    raise exception using
      errcode = '23514',
      message = 'scoring snapshot does not match its canonical story',
      constraint = 'scoring_snapshots_canonical_source_match';
  end if;

  return new;
end;
$function$;

create trigger scoring_snapshots_validate_source
before insert or update on app_private.scoring_snapshots
for each row execute function app_private.validate_scoring_snapshot_source();

create function app_private.validate_player_score_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  accusation_player_id uuid;
  accusation_status app_private.accusation_status;
begin
  select accusation.player_id, accusation.status
  into accusation_player_id, accusation_status
  from app_private.final_accusations as accusation
  where accusation.room_id = new.room_id
    and accusation.story_id = new.story_id
    and accusation.id = new.final_accusation_id;

  if not found
    or accusation_status <> 'SUBMITTED'
    or accusation_player_id <> new.player_id then
    raise exception using
      errcode = '23514',
      message = 'player score requires that player''s submitted final accusation',
      constraint = 'player_scores_submitted_accusation_match';
  end if;

  return new;
end;
$function$;

create trigger player_scores_validate_source
before insert or update on app_private.player_scores
for each row execute function app_private.validate_player_score_source();

create function app_private.validate_theory_score_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  theory_player_id uuid;
begin
  select theory.player_id
  into theory_player_id
  from app_private.player_theories as theory
  where theory.room_id = new.room_id
    and theory.story_id = new.story_id
    and theory.id = new.theory_id;

  if not found or theory_player_id <> new.player_id then
    raise exception using
      errcode = '23514',
      message = 'theory score player does not own the submitted theory',
      constraint = 'theory_scores_owner_match';
  end if;

  return new;
end;
$function$;

create trigger theory_scores_validate_source
before insert or update on app_private.theory_scores
for each row execute function app_private.validate_theory_score_source();

create function app_private.validate_endgame_artifact_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_snapshot app_private.scoring_snapshots%rowtype;
  source_reveal app_private.reveal_publications%rowtype;
begin
  select snapshot.*
  into source_snapshot
  from app_private.scoring_snapshots as snapshot
  where snapshot.room_id = new.room_id
    and snapshot.story_id = new.story_id
    and snapshot.id = new.scoring_snapshot_id;

  if not found
    or new.scoring_profile_version <> source_snapshot.scoring_profile_version
    or new.scoring_profile_checksum <> source_snapshot.scoring_profile_checksum
    or new.story_package_checksum <> source_snapshot.story_package_checksum
    or new.solution_checksum <> source_snapshot.solution_checksum
    or new.frozen_input_checksum <> source_snapshot.frozen_input_checksum then
    raise exception using
      errcode = '23514',
      message = 'endgame artifact does not match its frozen scoring source',
      constraint = 'endgame_artifact_scoring_source_match';
  end if;

  if tg_table_name = 'case_files' then
    select reveal.*
    into source_reveal
    from app_private.reveal_publications as reveal
    where reveal.room_id = new.room_id
      and reveal.story_id = new.story_id
      and reveal.id = new.reveal_publication_id
      and reveal.scoring_snapshot_id = new.scoring_snapshot_id;

    if not found or new.reveal_checksum <> source_reveal.reveal_checksum then
      raise exception using
        errcode = '23514',
        message = 'case file does not match its reveal publication',
        constraint = 'case_files_reveal_source_match';
    end if;
  end if;

  return new;
end;
$function$;

create trigger reveal_publications_validate_source
before insert or update on app_private.reveal_publications
for each row execute function app_private.validate_endgame_artifact_source();

create trigger case_files_validate_source
before insert or update on app_private.case_files
for each row execute function app_private.validate_endgame_artifact_source();

revoke all on function app_private.validate_scoring_snapshot_source()
  from public, anon, authenticated;
revoke all on function app_private.validate_player_score_source()
  from public, anon, authenticated;
revoke all on function app_private.validate_theory_score_source()
  from public, anon, authenticated;
revoke all on function app_private.validate_endgame_artifact_source()
  from public, anon, authenticated;

comment on table app_private.scoring_snapshots is
  'One frozen, checksummed scoring input set per room.';
comment on table app_private.case_files is
  'One finalized, checksummed postgame artifact per room.';
