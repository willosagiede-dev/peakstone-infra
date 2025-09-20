-- Extensions only (other schema/roles deferred)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE EXTENSION IF NOT EXISTS btree_gin;
-- CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS hypopg;
-- Optional:
-- CREATE EXTENSION IF NOT EXISTS pg_repack;  -- usually used via CLI during maintenance
-- CREATE EXTENSION IF NOT EXISTS pg_qualstats; -- requires separate install
