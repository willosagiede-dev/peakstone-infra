-- Idempotent roles, grants, and passwords for least-privilege setup
-- Variables provided by psql: DB_AUTHENTICATOR_PASSWORD, HASURA_DB_PASSWORD, DB_MIGRATOR_PASSWORD

-- Create roles if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'db_authenticator') THEN
    CREATE ROLE db_authenticator LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hasura') THEN
    CREATE ROLE hasura LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'read_only') THEN
    CREATE ROLE read_only NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'db_migrator') THEN
    CREATE ROLE db_migrator LOGIN;
  END IF;
  -- Compatibility roles sometimes referenced in Supabase policies
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
END
$$;

-- Set passwords for login roles
ALTER ROLE db_authenticator WITH LOGIN PASSWORD :'DB_AUTHENTICATOR_PASSWORD';
ALTER ROLE hasura WITH LOGIN PASSWORD :'HASURA_DB_PASSWORD';
ALTER ROLE db_migrator WITH LOGIN PASSWORD :'DB_MIGRATOR_PASSWORD';

-- Allow db_migrator to create schemas in this database (needed for Atlas revisions schema)
DO $$
BEGIN
  EXECUTE format('GRANT CREATE, TEMPORARY ON DATABASE %I TO db_migrator;', current_database());
END
$$;

-- Pre-create Atlas revision schemas (idempotent) and own them by db_migrator
CREATE SCHEMA IF NOT EXISTS atlas_schema AUTHORIZATION db_migrator;
CREATE SCHEMA IF NOT EXISTS atlas_schema_revisions AUTHORIZATION db_migrator;

-- App auth pattern: authenticator can assume app_user and web_anon
GRANT web_anon TO db_authenticator;
GRANT app_user TO db_authenticator;

-- Schemas used by PostgREST (adjust as needed)
-- Keep this in sync with PGRST_DB_SCHEMAS
DO $$
DECLARE s text;
DECLARE r record;
BEGIN
  FOREACH s IN ARRAY ARRAY['public','common','people','pipeline','activities','leads','docs'] LOOP
    -- Ensure schema exists and is owned by db_migrator
    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I AUTHORIZATION db_migrator;', s);
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC;', s);
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO web_anon, app_user, hasura, read_only;', s);
    -- Allow db_migrator to create objects (new objects will be owned by db_migrator)
    EXECUTE format('GRANT USAGE, CREATE ON SCHEMA %I TO db_migrator;', s);
    -- Make db_migrator the schema owner (new DBs only; safe if already owner)
    EXECUTE format('ALTER SCHEMA %I OWNER TO db_migrator;', s);

    -- Existing objects
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO web_anon, read_only;', s);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO app_user, hasura;', s);
    EXECUTE format('GRANT USAGE ON ALL SEQUENCES IN SCHEMA %I TO app_user, hasura;', s);

    -- Future objects created by db_migrator: grant defaults to app roles
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE db_migrator IN SCHEMA %I GRANT SELECT ON TABLES TO web_anon, read_only;', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE db_migrator IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user, hasura;', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE db_migrator IN SCHEMA %I GRANT USAGE ON SEQUENCES TO app_user, hasura;', s);

    -- Transfer ownership of existing relations in the schema to db_migrator (idempotent)
    FOR r IN
      SELECT c.relkind, c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = s AND c.relkind IN ('r','p','v','m','S')
    LOOP
      IF r.relkind IN ('r','p') THEN
        EXECUTE format('ALTER TABLE %I.%I OWNER TO db_migrator;', s, r.relname);
      ELSIF r.relkind = 'S' THEN
        EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO db_migrator;', s, r.relname);
      ELSIF r.relkind = 'v' THEN
        EXECUTE format('ALTER VIEW %I.%I OWNER TO db_migrator;', s, r.relname);
      ELSIF r.relkind = 'm' THEN
        EXECUTE format('ALTER MATERIALIZED VIEW %I.%I OWNER TO db_migrator;', s, r.relname);
      END IF;
    END LOOP;
  END LOOP;
END
$$;

-- Optional: keep pgaudit broader than ddl if desired
-- ALTER SYSTEM SET pgaudit.log = 'ddl,role,read,write';
-- SELECT pg_reload_conf();
