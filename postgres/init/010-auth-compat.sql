-- Compatibility helpers for policies originally written for Supabase
-- Provides auth.uid() that works for both PostgREST and Hasura contexts.
-- Safe on new databases; idempotent on re-runs.

CREATE SCHEMA IF NOT EXISTS auth;

-- Return the authenticated user's UUID if present in JWT/headers.
-- Checks PostgREST's request.jwt.claims.sub first, then Hasura's x-hasura-user-id.
-- Uses exception handling to avoid errors if the value is not a valid UUID.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE
  t text;
  u uuid;
BEGIN
  -- PostgREST puts the whole JWT claims JSON into request.jwt.claims GUC
  -- Hasura sets x-hasura-user-id GUC when executing as a session user
  t := coalesce(
         (current_setting('request.jwt.claims', true)::json ->> 'sub'),
         current_setting('x-hasura-user-id', true)
       );
  IF t IS NULL OR t = '' THEN
    RETURN NULL;
  END IF;
  BEGIN
    u := t::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
  END;
  RETURN u;
END;
$$;

