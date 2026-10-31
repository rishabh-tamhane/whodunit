-- DB-03: dedicated Game Master identity and room-first serialization.

create function app_private.lock_room(target_room_id uuid)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $function$
  select r.id
  from app_private.rooms as r
  where r.id = target_room_id
  for update;
$function$;

create function app_private.assert_room_host_tenure(target_room_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  current_host_id uuid;
  open_host_id uuid;
  open_tenure_count integer;
begin
  select r.host_auth_user_id
  into current_host_id
  from app_private.rooms as r
  where r.id = target_room_id;

  -- Cascading room deletion removes tenure history in the same transaction.
  if not found then
    return;
  end if;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.min(h.auth_user_id::text)::uuid
  into open_tenure_count, open_host_id
  from app_private.room_host_principals as h
  where h.room_id = target_room_id
    and h.ended_at is null;

  if open_tenure_count <> 1 then
    raise exception using
      errcode = '23514',
      message = 'room must have exactly one open Game Master tenure',
      constraint = 'room_host_tenure_exactly_one_open';
  end if;

  if open_host_id is distinct from current_host_id then
    raise exception using
      errcode = '23514',
      message = 'room current Game Master must match the open tenure',
      constraint = 'room_host_tenure_matches_current_host';
  end if;

  if exists (
    select 1
    from app_private.room_host_principals as h
    join app_private.room_memberships as m
      on m.room_id = h.room_id
      and m.auth_user_id = h.auth_user_id
    where h.room_id = target_room_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'a current or former Game Master cannot have a player membership',
      constraint = 'room_host_principal_never_player';
  end if;
end;
$function$;

create function app_private.check_room_host_tenure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  affected_room_id uuid;
begin
  if tg_table_name = 'rooms' then
    affected_room_id := new.id;
  elsif tg_op = 'DELETE' then
    affected_room_id := old.room_id;
  else
    affected_room_id := new.room_id;
  end if;

  perform app_private.assert_room_host_tenure(affected_room_id);
  return null;
end;
$function$;

create function app_private.enforce_membership_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' and (
    new.room_id,
    new.auth_user_id,
    new.player_id,
    new.request_kind,
    new.replaces_membership_id
  ) is distinct from (
    old.room_id,
    old.auth_user_id,
    old.player_id,
    old.request_kind,
    old.replaces_membership_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'membership identity and claim origin are immutable',
      constraint = 'room_membership_identity_immutable';
  end if;

  if app_private.lock_room(new.room_id) is null then
    raise exception using
      errcode = '23503',
      message = 'membership room does not exist',
      constraint = 'room_memberships_room_fk';
  end if;

  if exists (
    select 1
    from app_private.room_host_principals as h
    where h.room_id = new.room_id
      and h.auth_user_id = new.auth_user_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'a current or former Game Master cannot claim a player slot',
      constraint = 'room_membership_host_principal_exclusion';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_host_principal_identity()
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
        message = 'Game Master tenure history cannot be deleted while its room exists',
        constraint = 'room_host_principal_history_permanent';
    end if;

    return old;
  end if;

  if tg_op = 'UPDATE' then
    if (
      new.room_id,
      new.auth_user_id,
      new.started_at
    ) is distinct from (
      old.room_id,
      old.auth_user_id,
      old.started_at
    ) then
      raise exception using
        errcode = '23514',
        message = 'Game Master tenure identity is immutable',
        constraint = 'room_host_principal_identity_immutable';
    end if;

    if old.ended_at is not null
      and new.ended_at is distinct from old.ended_at then
      raise exception using
        errcode = '23514',
        message = 'a closed Game Master tenure cannot change or reopen',
        constraint = 'room_host_principal_closed_immutable';
    end if;
  end if;

  if app_private.lock_room(new.room_id) is null then
    raise exception using
      errcode = '23503',
      message = 'Game Master tenure room does not exist',
      constraint = 'room_host_principals_room_fk';
  end if;

  if exists (
    select 1
    from app_private.room_memberships as m
    where m.room_id = new.room_id
      and m.auth_user_id = new.auth_user_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'a player principal cannot become Game Master in the same room',
      constraint = 'room_host_principal_player_exclusion';
  end if;

  return new;
end;
$function$;

create function app_private.enforce_room_host_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' and new.id is distinct from old.id then
    raise exception using
      errcode = '23514',
      message = 'room identity is immutable',
      constraint = 'rooms_id_immutable';
  end if;

  if exists (
    select 1
    from app_private.room_memberships as m
    where m.room_id = new.id
      and m.auth_user_id = new.host_auth_user_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'a player principal cannot become the room Game Master',
      constraint = 'rooms_current_host_player_exclusion';
  end if;

  return new;
end;
$function$;

create trigger room_memberships_enforce_identity
before insert or update on app_private.room_memberships
for each row execute function app_private.enforce_membership_identity();

create trigger room_host_principals_enforce_identity
before insert or update or delete on app_private.room_host_principals
for each row execute function app_private.enforce_host_principal_identity();

create trigger rooms_enforce_host_identity
before insert or update on app_private.rooms
for each row execute function app_private.enforce_room_host_identity();

create constraint trigger rooms_check_host_tenure
after insert or update on app_private.rooms
deferrable initially deferred
for each row execute function app_private.check_room_host_tenure();

create constraint trigger room_host_principals_check_tenure
after insert or update or delete on app_private.room_host_principals
deferrable initially deferred
for each row execute function app_private.check_room_host_tenure();

revoke all on function app_private.lock_room(uuid)
  from public, anon, authenticated;
revoke all on function app_private.assert_room_host_tenure(uuid)
  from public, anon, authenticated;
revoke all on function app_private.check_room_host_tenure()
  from public, anon, authenticated;
revoke all on function app_private.enforce_membership_identity()
  from public, anon, authenticated;
revoke all on function app_private.enforce_host_principal_identity()
  from public, anon, authenticated;
revoke all on function app_private.enforce_room_host_identity()
  from public, anon, authenticated;

comment on function app_private.lock_room(uuid) is
  'Shared first lock for claim, approval, reconnect, recovery, and host commands.';
comment on function app_private.assert_room_host_tenure(uuid) is
  'Commit-time invariant: one open tenure matches the current room Game Master.';

-- Validate any rows created between DB-02 and this migration before the new
-- deferred triggers become the sole enforcement mechanism.
do $validation$
declare
  candidate_room_id uuid;
begin
  for candidate_room_id in
    select r.id from app_private.rooms as r
  loop
    perform app_private.assert_room_host_tenure(candidate_room_id);
  end loop;
end;
$validation$;
