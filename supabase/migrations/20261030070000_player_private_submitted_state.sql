-- DB-07: owner-only drafts and immutable submitted investigation state.

create type app_private.suspected_role as enum (
  'MURDERER',
  'ACCOMPLICE'
);

alter table app_private.evidence_releases
  add constraint evidence_releases_room_story_evidence_unique unique (
    room_id,
    story_id,
    evidence_id
  );

create table app_private.player_notes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  player_id uuid not null,
  revision bigint not null default 0,
  notes_text text not null default '',
  created_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint player_notes_room_player_unique unique (room_id, player_id),
  constraint player_notes_room_player_id_revision_unique unique (
    room_id,
    player_id,
    id,
    revision
  ),
  constraint player_notes_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete cascade,
  constraint player_notes_revision_nonnegative check (revision >= 0),
  constraint player_notes_size_limit check (
    pg_catalog.char_length(notes_text) <= 10000
  ),
  constraint player_notes_times_ordered check (updated_at >= created_at)
);

create table app_private.player_note_suspects (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  owner_player_id uuid not null,
  note_id uuid not null,
  notebook_revision bigint not null,
  suspect_player_id uuid not null,
  suspected_role app_private.suspected_role not null,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint player_note_suspects_owner_suspect_unique unique (
    room_id,
    owner_player_id,
    suspect_player_id
  ),
  constraint player_note_suspects_note_revision_fk foreign key (
    room_id,
    owner_player_id,
    note_id,
    notebook_revision
  ) references app_private.player_notes (room_id, player_id, id, revision)
    on delete cascade deferrable initially deferred,
  constraint player_note_suspects_suspect_room_fk foreign key (
    room_id,
    suspect_player_id
  ) references app_private.players (room_id, id) on delete cascade,
  constraint player_note_suspects_other_player check (
    owner_player_id <> suspect_player_id
  ),
  constraint player_note_suspects_revision_nonnegative check (
    notebook_revision >= 0
  )
);

create table app_private.player_theories (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  player_id uuid not null,
  round_id uuid not null,
  submitted_state_version bigint not null,
  structured_claim_json jsonb not null,
  submitted_explanation text,
  command_receipt_id uuid not null,
  submitted_at timestamp with time zone not null default app_private.current_database_time(),
  constraint player_theories_room_story_id_unique unique (room_id, story_id, id),
  constraint player_theories_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint player_theories_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint player_theories_round_room_story_fk foreign key (
    room_id,
    story_id,
    round_id
  ) references app_private.story_rounds (room_id, story_id, id) on delete restrict,
  constraint player_theories_command_room_fk foreign key (
    room_id,
    command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint player_theories_state_version_nonnegative check (
    submitted_state_version >= 0
  ),
  constraint player_theories_claim_object check (
    pg_catalog.jsonb_typeof(structured_claim_json) = 'object'
  ),
  constraint player_theories_explanation_limit check (
    submitted_explanation is null
    or pg_catalog.char_length(submitted_explanation) <= 2000
  )
);

create table app_private.player_theory_suspects (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  theory_id uuid not null,
  suspect_player_id uuid not null,
  suspected_role app_private.suspected_role not null,
  constraint player_theory_suspects_theory_player_unique unique (
    theory_id,
    suspect_player_id
  ),
  constraint player_theory_suspects_theory_room_story_fk foreign key (
    room_id,
    story_id,
    theory_id
  ) references app_private.player_theories (room_id, story_id, id)
    on delete cascade,
  constraint player_theory_suspects_player_room_fk foreign key (
    room_id,
    suspect_player_id
  ) references app_private.players (room_id, id) on delete restrict
);

create table app_private.player_theory_evidence (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  theory_id uuid not null,
  evidence_id uuid not null,
  constraint player_theory_evidence_theory_evidence_unique unique (
    theory_id,
    evidence_id
  ),
  constraint player_theory_evidence_theory_room_story_fk foreign key (
    room_id,
    story_id,
    theory_id
  ) references app_private.player_theories (room_id, story_id, id)
    on delete cascade,
  constraint player_theory_evidence_released_room_story_fk foreign key (
    room_id,
    story_id,
    evidence_id
  ) references app_private.evidence_releases (room_id, story_id, evidence_id)
    on delete restrict
);

create table app_private.final_accusations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  player_id uuid not null,
  status app_private.accusation_status not null default 'DRAFT',
  revision bigint not null default 0,
  structured_case_json jsonb not null default '{}'::jsonb,
  explanation_text text,
  submitted_state_version bigint,
  submission_command_receipt_id uuid,
  submitted_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint final_accusations_room_story_id_unique unique (room_id, story_id, id),
  constraint final_accusations_story_player_unique unique (story_id, player_id),
  constraint final_accusations_room_story_player_id_revision_unique unique (
    room_id,
    story_id,
    player_id,
    id,
    revision
  ),
  constraint final_accusations_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete restrict,
  constraint final_accusations_story_room_fk foreign key (room_id, story_id)
    references app_private.canonical_stories (room_id, id) on delete cascade,
  constraint final_accusations_command_room_fk foreign key (
    room_id,
    submission_command_receipt_id
  ) references app_private.command_receipts (room_id, id) on delete restrict,
  constraint final_accusations_revision_nonnegative check (revision >= 0),
  constraint final_accusations_case_object check (
    pg_catalog.jsonb_typeof(structured_case_json) = 'object'
  ),
  constraint final_accusations_explanation_limit check (
    explanation_text is null
    or pg_catalog.char_length(explanation_text) <= 4000
  ),
  constraint final_accusations_submission_shape check (
    (
      status = 'DRAFT'
      and submitted_state_version is null
      and submission_command_receipt_id is null
      and submitted_at is null
    )
    or (
      status = 'SUBMITTED'
      and submitted_state_version is not null
      and submitted_state_version >= 0
      and submission_command_receipt_id is not null
      and submitted_at is not null
      and submitted_at >= created_at
    )
  ),
  constraint final_accusations_times_ordered check (updated_at >= created_at)
);

create table app_private.final_accusation_suspects (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  owner_player_id uuid not null,
  accusation_id uuid not null,
  accusation_revision bigint not null,
  suspect_player_id uuid not null,
  suspected_role app_private.suspected_role not null,
  constraint final_accusation_suspects_accusation_player_unique unique (
    accusation_id,
    suspect_player_id
  ),
  constraint final_accusation_suspects_accusation_revision_fk foreign key (
    room_id,
    story_id,
    owner_player_id,
    accusation_id,
    accusation_revision
  ) references app_private.final_accusations (
    room_id,
    story_id,
    player_id,
    id,
    revision
  ) on delete cascade deferrable initially deferred,
  constraint final_accusation_suspects_player_room_fk foreign key (
    room_id,
    suspect_player_id
  ) references app_private.players (room_id, id) on delete restrict
);

create table app_private.final_accusation_evidence (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  story_id uuid not null,
  owner_player_id uuid not null,
  accusation_id uuid not null,
  accusation_revision bigint not null,
  evidence_id uuid not null,
  constraint final_accusation_evidence_accusation_evidence_unique unique (
    accusation_id,
    evidence_id
  ),
  constraint final_accusation_evidence_accusation_revision_fk foreign key (
    room_id,
    story_id,
    owner_player_id,
    accusation_id,
    accusation_revision
  ) references app_private.final_accusations (
    room_id,
    story_id,
    player_id,
    id,
    revision
  ) on delete cascade deferrable initially deferred,
  constraint final_accusation_evidence_released_room_story_fk foreign key (
    room_id,
    story_id,
    evidence_id
  ) references app_private.evidence_releases (room_id, story_id, evidence_id)
    on delete restrict
);

create index player_theories_room_player_submitted_idx
  on app_private.player_theories (room_id, player_id, submitted_at desc);
create index player_theory_suspects_room_player_idx
  on app_private.player_theory_suspects (room_id, suspect_player_id);
create index final_accusations_room_status_idx
  on app_private.final_accusations (room_id, status, submitted_at);

create function app_private.enforce_player_note_revision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    if exists (
      select 1 from app_private.rooms as r where r.id = old.room_id
    ) then
      raise exception using
        errcode = '23514',
        message = 'final accusation cannot be deleted while its room exists',
        constraint = 'final_accusations_record_permanent';
    end if;

    return old;
  end if;

  if tg_op = 'INSERT' then
    if new.revision <> 0 then
      raise exception using
        errcode = '23514',
        message = 'player notebook must begin at revision zero',
        constraint = 'player_notes_initial_revision';
    end if;

    return new;
  end if;

  if (new.room_id, new.player_id) is distinct from (old.room_id, old.player_id) then
    raise exception using
      errcode = '23514',
      message = 'player notebook ownership is immutable',
      constraint = 'player_notes_identity_immutable';
  end if;

  if new.revision <> old.revision + 1 then
    raise exception using
      errcode = '40001',
      message = 'stale player notebook revision',
      constraint = 'player_notes_revision_conflict';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_final_accusation_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'DRAFT' or new.revision <> 0 then
      raise exception using
        errcode = '23514',
        message = 'final accusation must begin as a revision-zero draft',
        constraint = 'final_accusations_initial_state';
    end if;

    return new;
  end if;

  if (new.room_id, new.story_id, new.player_id) is distinct from
    (old.room_id, old.story_id, old.player_id) then
    raise exception using
      errcode = '23514',
      message = 'final accusation ownership is immutable',
      constraint = 'final_accusations_identity_immutable';
  end if;

  if old.status = 'SUBMITTED' then
    raise exception using
      errcode = '23514',
      message = 'submitted final accusation is immutable',
      constraint = 'final_accusations_submitted_immutable';
  end if;

  if new.revision <> old.revision + 1 then
    raise exception using
      errcode = '40001',
      message = 'stale final accusation revision',
      constraint = 'final_accusations_revision_conflict';
  end if;

  if new.status not in ('DRAFT', 'SUBMITTED') then
    raise exception using
      errcode = '23514',
      message = 'invalid final accusation transition',
      constraint = 'final_accusations_valid_transition';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_accusation_selection_mutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_accusation_id uuid;
  target_room_id uuid;
  parent_status app_private.accusation_status;
begin
  target_accusation_id := case when tg_op = 'DELETE' then old.accusation_id
    else new.accusation_id end;
  target_room_id := case when tg_op = 'DELETE' then old.room_id
    else new.room_id end;

  if not exists (
    select 1 from app_private.rooms as r where r.id = target_room_id
  ) then
    if tg_op = 'DELETE' then
      return old;
    end if;

    return new;
  end if;

  select a.status
  into parent_status
  from app_private.final_accusations as a
  where a.id = target_accusation_id
  for update;

  if parent_status = 'SUBMITTED' then
    raise exception using
      errcode = '23514',
      message = 'submitted final accusation selections are immutable',
      constraint = 'final_accusation_selections_submitted_immutable';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$function$;

create trigger player_notes_enforce_revision
before insert or update on app_private.player_notes
for each row execute function app_private.enforce_player_note_revision();

create trigger final_accusations_enforce_transition
before insert or update or delete on app_private.final_accusations
for each row execute function app_private.enforce_final_accusation_transition();

create trigger final_accusation_suspects_enforce_mutable
before insert or update or delete on app_private.final_accusation_suspects
for each row execute function app_private.enforce_accusation_selection_mutable();

create trigger final_accusation_evidence_enforce_mutable
before insert or update or delete on app_private.final_accusation_evidence
for each row execute function app_private.enforce_accusation_selection_mutable();

create trigger player_theories_immutable
before update or delete on app_private.player_theories
for each row execute function app_private.enforce_room_record_immutable();

create trigger player_theory_suspects_immutable
before update or delete on app_private.player_theory_suspects
for each row execute function app_private.enforce_room_record_immutable();

create trigger player_theory_evidence_immutable
before update or delete on app_private.player_theory_evidence
for each row execute function app_private.enforce_room_record_immutable();

revoke all on function app_private.enforce_player_note_revision()
  from public, anon, authenticated;
revoke all on function app_private.enforce_final_accusation_transition()
  from public, anon, authenticated;
revoke all on function app_private.enforce_accusation_selection_mutable()
  from public, anon, authenticated;

comment on table app_private.player_notes is
  'Owner-only notebook content keyed to stable player identity, never auth user.';
comment on table app_private.player_theories is
  'Immutable submitted investigation snapshot visible only through projections.';
comment on table app_private.final_accusations is
  'Owner-only revisioned draft that becomes immutable submitted gameplay state.';
