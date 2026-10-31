# Database migration conventions

The local Supabase stack is the only database dependency for development and
CI. Application code and tests run on the host; Postgres and the Supabase
services run in Docker.

## Schemas and privileges

- `app_private` owns application tables, canonical story data, raw inputs,
  command internals, and internal helper functions. It is not exposed through
  the Data API.
- `public` contains only reviewed RPC entry points and content-free signal or
  projection objects that must be exposed by Supabase.
- `anon` and `authenticated` receive no implicit object privileges. Every
  exposed function or safe table needs an explicit, narrow grant in its owning
  migration.
- Direct writes are not granted to API roles. State changes go through command
  functions that authorize the JWT principal and update state transactionally.

## Migration rules

1. Add forward-only, timestamp-prefixed files under `supabase/migrations`.
   Never edit a migration that has been deployed.
2. Fully qualify every application object, including objects referenced inside
   functions.
3. Every function sets an explicit `search_path`. Security-definer functions
   use an empty path and schema-qualify every referenced object.
4. Revoke function execution from `PUBLIC`, `anon`, and `authenticated` before
   granting the minimum required API role.
5. Keep constraints and authorization checks in the same migration as the
   object they protect, with matching pgTAP allow/deny tests.
6. Use explicit UUIDs and timestamps in deterministic seeds and fixtures.

Secure function template:

```sql
create function public.example_command()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Fully qualify every relation, type, and helper call.
end;
$function$;

revoke all on function public.example_command()
  from public, anon, authenticated;
grant execute on function public.example_command() to authenticated;
```

Run `CI=true npm run db:verify` to recreate the stack, replay every migration,
run pgTAP, and execute the HTTP/Auth integration smoke tests.
