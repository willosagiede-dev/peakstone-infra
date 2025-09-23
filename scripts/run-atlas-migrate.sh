#!/usr/bin/env sh
set -eu

# Working dir is expected to be /workspace/atlas
DIR="migrations"

if [ ! -d "$DIR" ]; then
  echo "[atlas-migrate] No migrations dir found ($DIR). Skipping."
  exit 0
fi

set +e
count=$(ls -1 "$DIR"/*.sql 2>/dev/null | wc -l | tr -d ' ')
set -e
if [ "$count" = "0" ]; then
  echo "[atlas-migrate] No migration files present. Skipping."
  exit 0
fi

if [ -z "${ATLAS_URL:-}" ]; then
  echo "[atlas-migrate] ATLAS_URL not set. Aborting." >&2
  exit 2
fi

echo "[atlas-migrate] Applying migrations (allow-dirty) using $ATLAS_URL ..."
exec atlas migrate apply --dir "file://$DIR" --url "$ATLAS_URL" --allow-dirty

