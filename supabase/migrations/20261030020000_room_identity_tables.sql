-- DB-02: room, player, membership, description, consent, and recovery storage.
-- DB-03 adds the cross-table Game Master/player exclusion triggers.

create table app_private.rooms (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_code text not null,
  host_auth_user_id uuid not null references auth.users (id) on delete restrict,
  status app_private.room_state not null default 'DRAFT',
  state_version bigint not null default 0,
  config_json jsonb not null default '{}'::jsonb,
  scoring_profile_version text,
  story_id uuid,
  current_round_id uuid,
  locked_at timestamp with time zone,
  sensitive_input_purge_pending boolean not null default false,
  host_guidance_acknowledged_at timestamp with time zone,
  room_consent_confirmed_at timestamp with time zone,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  expires_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint rooms_room_code_unique unique (room_code),
  constraint rooms_room_code_canonical check (
    room_code ~ '^[A-Z0-9]{4,12}$'
  ),
  constraint rooms_state_version_nonnegative check (state_version >= 0),
  constraint rooms_config_is_object check (
    pg_catalog.jsonb_typeof(config_json) = 'object'
  ),
  constraint rooms_story_lock_consistent check (
    (story_id is null and locked_at is null)
    or (story_id is not null and locked_at is not null)
  ),
  constraint rooms_completion_times_consistent check (
    (completed_at is null and expires_at is null)
    or (
      completed_at is not null
      and expires_at is not null
      and expires_at > completed_at
    )
  ),
  constraint rooms_audit_times_ordered check (updated_at >= created_at)
);

create table app_private.room_host_principals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  auth_user_id uuid not null references auth.users (id) on delete restrict,
  started_at timestamp with time zone not null default app_private.current_database_time(),
  ended_at timestamp with time zone,
  constraint room_host_principals_room_id_id_unique unique (room_id, id),
  constraint room_host_principals_room_auth_user_unique unique (
    room_id,
    auth_user_id
  ),
  constraint room_host_principals_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint room_host_principals_tenure_ordered check (
    ended_at is null or ended_at >= started_at
  )
);

create unique index room_host_principals_one_open_per_room_idx
  on app_private.room_host_principals (room_id)
  where ended_at is null;

create index room_host_principals_auth_user_idx
  on app_private.room_host_principals (auth_user_id, room_id);

create table app_private.players (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  display_name text not null,
  display_name_normalized text not null,
  costume text not null,
  host_background text,
  seat_order smallint not null,
  fictional_use_acknowledged_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint players_room_id_id_unique unique (room_id, id),
  constraint players_room_seat_unique unique (room_id, seat_order),
  constraint players_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint players_display_name_length check (
    pg_catalog.char_length(pg_catalog.btrim(display_name)) between 1 and 100
  ),
  constraint players_normalized_name_length check (
    pg_catalog.char_length(pg_catalog.btrim(display_name_normalized)) between 1 and 100
  ),
  constraint players_costume_length check (
    pg_catalog.char_length(pg_catalog.btrim(costume)) between 1 and 200
  ),
  constraint players_background_length check (
    host_background is null
    or pg_catalog.char_length(host_background) <= 1000
  ),
  constraint players_seat_order_supported check (seat_order between 1 and 12),
  constraint players_audit_times_ordered check (updated_at >= created_at)
);

create table app_private.room_memberships (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  auth_user_id uuid not null references auth.users (id) on delete restrict,
  player_id uuid not null,
  status app_private.membership_status not null default 'PENDING',
  request_kind app_private.claim_kind not null,
  replaces_membership_id uuid,
  approved_by_auth_user_id uuid references auth.users (id) on delete restrict,
  last_seen_at timestamp with time zone,
  joined_at timestamp with time zone,
  revoked_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint room_memberships_room_id_id_unique unique (room_id, id),
  constraint room_memberships_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint room_memberships_player_room_fk foreign key (room_id, player_id)
    references app_private.players (room_id, id) on delete cascade,
  constraint room_memberships_replaced_room_fk foreign key (
    room_id,
    replaces_membership_id
  ) references app_private.room_memberships (room_id, id) on delete restrict,
  constraint room_memberships_request_shape check (
    (request_kind = 'INITIAL_CLAIM' and replaces_membership_id is null)
    or (request_kind = 'RECONNECT' and replaces_membership_id is not null)
  ),
  constraint room_memberships_status_times check (
    (
      status = 'PENDING'
      and joined_at is null
      and revoked_at is null
      and approved_by_auth_user_id is null
    )
    or (
      status = 'ACTIVE'
      and joined_at is not null
      and revoked_at is null
      and approved_by_auth_user_id is not null
    )
    or (status = 'REVOKED' and revoked_at is not null)
  ),
  constraint room_memberships_revocation_ordered check (
    revoked_at is null or revoked_at >= created_at
  ),
  constraint room_memberships_audit_times_ordered check (updated_at >= created_at)
);

create unique index room_memberships_one_active_device_per_player_idx
  on app_private.room_memberships (room_id, player_id)
  where status = 'ACTIVE';

create unique index room_memberships_one_active_player_per_user_idx
  on app_private.room_memberships (room_id, auth_user_id)
  where status = 'ACTIVE';

create index room_memberships_room_status_idx
  on app_private.room_memberships (room_id, status);

create index room_memberships_auth_user_idx
  on app_private.room_memberships (auth_user_id, room_id);

create table app_private.player_descriptions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  author_player_id uuid not null,
  subject_player_id uuid not null,
  description_text text,
  submitted_at timestamp with time zone not null default app_private.current_database_time(),
  purged_at timestamp with time zone,
  updated_at timestamp with time zone not null default app_private.current_database_time(),
  constraint player_descriptions_room_author_subject_unique unique (
    room_id,
    author_player_id,
    subject_player_id
  ),
  constraint player_descriptions_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint player_descriptions_author_room_fk foreign key (
    room_id,
    author_player_id
  ) references app_private.players (room_id, id) on delete cascade,
  constraint player_descriptions_subject_room_fk foreign key (
    room_id,
    subject_player_id
  ) references app_private.players (room_id, id) on delete cascade,
  constraint player_descriptions_other_player check (
    author_player_id <> subject_player_id
  ),
  constraint player_descriptions_content_state check (
    (
      purged_at is null
      and description_text is not null
      and pg_catalog.char_length(pg_catalog.btrim(description_text)) between 1 and 500
    )
    or (purged_at is not null and description_text is null)
  ),
  constraint player_descriptions_purge_ordered check (
    purged_at is null or purged_at >= submitted_at
  ),
  constraint player_descriptions_update_ordered check (updated_at >= submitted_at)
);

create index player_descriptions_room_subject_idx
  on app_private.player_descriptions (room_id, subject_player_id);

create table app_private.host_recovery_tokens (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  room_id uuid not null,
  token_digest bytea not null,
  token_version integer not null default 1,
  expires_at timestamp with time zone not null,
  consumed_at timestamp with time zone,
  revoked_at timestamp with time zone,
  created_at timestamp with time zone not null default app_private.current_database_time(),
  constraint host_recovery_tokens_room_id_id_unique unique (room_id, id),
  constraint host_recovery_tokens_room_fk foreign key (room_id)
    references app_private.rooms (id) on delete cascade,
  constraint host_recovery_tokens_digest_length check (
    pg_catalog.octet_length(token_digest) = 32
  ),
  constraint host_recovery_tokens_version_positive check (token_version > 0),
  constraint host_recovery_tokens_expiry_ordered check (expires_at > created_at),
  constraint host_recovery_tokens_terminal_state check (
    not (consumed_at is not null and revoked_at is not null)
  ),
  constraint host_recovery_tokens_consumed_ordered check (
    consumed_at is null or consumed_at >= created_at
  ),
  constraint host_recovery_tokens_revoked_ordered check (
    revoked_at is null or revoked_at >= created_at
  )
);

create unique index host_recovery_tokens_one_active_per_room_idx
  on app_private.host_recovery_tokens (room_id)
  where consumed_at is null and revoked_at is null;

-- M0-02 owns the final description completeness rule. This view exposes only
-- its deterministic inputs so DB-02 does not silently decide that policy.
create view app_private.room_readiness_inputs
with (security_invoker = true)
as
select
  r.id as room_id,
  (
    select pg_catalog.count(*)
    from app_private.players as p
    where p.room_id = r.id
  ) as player_count,
  (
    select pg_catalog.count(*)
    from app_private.room_memberships as m
    where m.room_id = r.id and m.status = 'ACTIVE'
  ) as active_membership_count,
  (
    select pg_catalog.count(*)
    from app_private.players as p
    where p.room_id = r.id
      and p.fictional_use_acknowledged_at is not null
  ) as acknowledged_player_count,
  (
    select pg_catalog.count(*)
    from app_private.player_descriptions as d
    where d.room_id = r.id
      and d.description_text is not null
      and d.purged_at is null
  ) as submitted_description_count,
  r.host_guidance_acknowledged_at is not null as host_guidance_acknowledged,
  r.room_consent_confirmed_at is not null as room_consent_confirmed
from app_private.rooms as r;

comment on view app_private.room_readiness_inputs is
  'Deterministic generation-readiness inputs; M0-02 defines final completeness.';

comment on table app_private.rooms is
  'Room lifecycle and current Game Master authority; no player identity lives here.';
comment on table app_private.players is
  'Stable host-configured player slots. Duplicate display names are allowed.';
comment on table app_private.room_memberships is
  'Claim and device-binding history between auth principals and player slots.';
comment on table app_private.room_host_principals is
  'Permanent room-scoped history of current and former Game Master principals.';
comment on table app_private.player_descriptions is
  'Generation-only friend descriptions, keyed by stable player identities.';
comment on table app_private.host_recovery_tokens is
  'Hashed, rotating Game Master recovery credentials; plaintext is never stored.';
