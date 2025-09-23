#!/usr/bin/env bash
set -euo pipefail

host="${POSTGRES_HOST:-postgres}"
db="${POSTGRES_DB:?POSTGRES_DB required}"
user="${POSTGRES_USER:?POSTGRES_USER required}"
export PGPASSWORD="${PGPASSWORD:?PGPASSWORD (superuser password) required}"

echo "[db-bootstrap] Waiting for Postgres at ${host}..."
until pg_isready -h "$host" -U "$user" -d "$db" >/dev/null 2>&1; do
  sleep 2
done
echo "[db-bootstrap] Postgres is ready. Applying roles/grants..."

psql -h "$host" -U "$user" -d "$db" \
  -v DB_AUTHENTICATOR_PASSWORD="${DB_AUTHENTICATOR_PASSWORD:?DB_AUTHENTICATOR_PASSWORD required}" \
  -v HASURA_DB_PASSWORD="${HASURA_DB_PASSWORD:?HASURA_DB_PASSWORD required}" \
  -v DB_MIGRATOR_PASSWORD="${DB_MIGRATOR_PASSWORD:?DB_MIGRATOR_PASSWORD required}" \
  -f /scripts/db-bootstrap.sql

echo "[db-bootstrap] Completed roles and grants setup."
