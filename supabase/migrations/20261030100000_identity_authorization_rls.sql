-- DB-10: authenticated-principal helpers, closed RLS, and safe discovery.

-- app_private is defense in depth: it is outside the exposed schema, has no
-- API-role grants, and every table also denies rows through RLS unless a later
-- migration deliberately adds a narrowly scoped policy.
do $block$
declare
  private_table record;
begin
  for private_table in
    select relation.oid::pg_catalog.regclass as qualified_name
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'app_private'
      and relation.relkind in ('r', 'p')
  loop
    execute pg_catalog.format(
      'alter table %s enable row level security',
      private_table.qualified_name
    );
  end loop;
end;
$block$;

revoke all on schema app_private from anon, authenticated, service_role;
revoke all on all tables in schema app_private
  from anon, authenticated, service_role;
revoke all on all sequences in schema app_private
  from anon, authenticated, service_role;
revoke execute on all functions in schema app_private
  from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema app_private
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema app_private
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema app_private
  revoke execute on functions from public, anon, authenticated, service_role;

create function app_private.current_auth_user_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $function$
  select auth.uid();
$function$;

create function app_private.is_current_game_master(target_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from app_private.rooms as room
    join app_private.room_host_principals as principal
      on principal.room_id = room.id
      and principal.auth_user_id = room.host_auth_user_id
      and principal.ended_at is null
    where room.id = target_room_id
      and room.host_auth_user_id = auth.uid()
  );
$function$;

create function app_private.active_player_id(target_room_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select membership.player_id
  from app_private.room_memberships as membership
  where membership.room_id = target_room_id
    and membership.auth_user_id = auth.uid()
    and membership.status = 'ACTIVE'
  limit 1;
$function$;

create function app_private.is_active_player(target_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.active_player_id(target_room_id) is not null;
$function$;

create function app_private.assert_current_game_master(target_room_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
    or not app_private.is_current_game_master(target_room_id) then
    raise exception using
      errcode = '42501',
      message = 'current Game Master authorization required';
  end if;
end;
$function$;

create function app_private.assert_active_player(
  target_room_id uuid,
  expected_player_id uuid default null
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  authorized_player_id uuid;
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'active player authorization required';
  end if;

  authorized_player_id := app_private.active_player_id(target_room_id);

  if authorized_player_id is null
    or (
      expected_player_id is not null
      and authorized_player_id <> expected_player_id
    ) then
    raise exception using
      errcode = '42501',
      message = 'active player authorization required';
  end if;

  return authorized_player_id;
end;
$function$;

-- Internal command functions call exactly one of the assertion helpers after
-- locking the room row. Neither helper is exposed to an API role; user-facing
-- command RPCs are granted individually from public in their owning migration.
comment on function app_private.assert_current_game_master(uuid) is
  'Private command guard for the authoritative current Game Master.';
comment on function app_private.assert_active_player(uuid, uuid) is
  'Private command guard returning the caller active player identity.';

revoke execute on function app_private.current_auth_user_id()
  from public, anon, authenticated, service_role;
revoke execute on function app_private.is_current_game_master(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.active_player_id(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.is_active_player(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.assert_current_game_master(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function app_private.assert_active_player(uuid, uuid)
  from public, anon, authenticated, service_role;

create function public.lookup_room_lobby(submitted_room_code text)
returns table (
  room_id uuid,
  room_code text,
  room_status text,
  player_id uuid,
  display_name text,
  costume text,
  seat_order smallint,
  slot_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  normalized_room_code text;
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated guest session required';
  end if;

  normalized_room_code := pg_catalog.upper(pg_catalog.btrim(submitted_room_code));

  if normalized_room_code !~ '^[A-Z0-9]{4,12}$' then
    return;
  end if;

  return query
  select
    room.id,
    room.room_code,
    room.status::text,
    player.id,
    player.display_name,
    player.costume,
    player.seat_order,
    case
      when exists (
        select 1
        from app_private.room_memberships as active_membership
        where active_membership.room_id = room.id
          and active_membership.player_id = player.id
          and active_membership.status = 'ACTIVE'
      ) then 'OCCUPIED'
      when exists (
        select 1
        from app_private.room_memberships as pending_membership
        where pending_membership.room_id = room.id
          and pending_membership.player_id = player.id
          and pending_membership.status = 'PENDING'
      ) then 'PENDING'
      else 'AVAILABLE'
    end
  from app_private.rooms as room
  join app_private.players as player on player.room_id = room.id
  where room.room_code = normalized_room_code
    and room.status in ('DRAFT', 'LOBBY')
  order by player.seat_order;
end;
$function$;

revoke all on function public.lookup_room_lobby(text)
  from public, anon, authenticated, service_role;
grant execute on function public.lookup_room_lobby(text) to authenticated;

comment on function public.lookup_room_lobby(text) is
  'Room-code discovery returning only names, costumes, seat order, and slot availability.';
