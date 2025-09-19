-- Extensions
create extension if not exists pg_stat_statements;
create extension if not exists pg_cron;
create extension if not exists pgaudit;
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists btree_gin;
create extension if not exists btree_gist;
create extension if not exists citext;
create extension if not exists unaccent;
create extension if not exists hypopg;
create extension if not exists pg_qualstats;

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
