begin;

select plan(3);

select has_schema('auth', 'the local Auth schema exists');
select has_table('auth', 'users', 'the local Auth users table exists');
select is(
  (
    select count(*)::integer
    from supabase_migrations.schema_migrations
    where version = '20261030000000'
  ),
  1,
  'the foundation migration replayed exactly once'
);

select * from finish();

rollback;
