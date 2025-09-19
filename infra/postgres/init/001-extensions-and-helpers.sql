-- Extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS hypopg;
/* Optional if you actually use them during runtime: */
-- CREATE EXTENSION IF NOT EXISTS pg_qualstats;
-- CREATE EXTENSION IF NOT EXISTS pg_repack; -- usually used via CLI during maintenance

-- JWT helpers
create schema if not exists common;

create or replace function common.jwt_sub() returns uuid
language sql stable as $$
  select (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid
$$;

create or replace function common.jwt_org_id() returns uuid
language sql stable as $$
  select (current_setting('request.jwt.claims', true)::jsonb->>'org_id')::uuid
$$;

-- Supabase-compat shim (optional)
create schema if not exists auth;
create or replace function auth.uid() returns uuid
language sql stable as $$ select common.jwt_sub() $$;

-- Anon role PostgREST expects
do $$
begin
  if not exists (select from pg_roles where rolname = 'web_anon') then
    create role web_anon noinherit;
  end if;
end$$;
