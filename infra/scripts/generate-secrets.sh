#!/usr/bin/env bash
set -euo pipefail

# Simple helper to generate strong secrets and pgCat MD5.
# Usage:
#   ./infra/scripts/generate-secrets.sh [DB_APP_USER]
# Defaults:
#   DB_APP_USER=app_user

DB_APP_USER=${1:-app_user}

rand_b64() { openssl rand -base64 "$1"; }
rand_hex() { openssl rand -hex "$1"; }

# Generate values
POSTGRES_SUPERPASS=$(rand_b64 24)
DB_APP_PASS=$(rand_b64 24)
JWT_SECRET=$(rand_hex 32)          # 32 bytes hex
HASURA_ADMIN_SECRET=$(rand_hex 32) # 32 bytes hex
MINIO_ROOT_PASS=$(rand_b64 24)
S3_APP_SECRET_KEY=$(rand_b64 24)
IMGPROXY_KEY_HEX=$(rand_hex 32)    # 32 bytes hex -> 64 chars
IMGPROXY_SALT_HEX=$(rand_hex 16)   # 16 bytes hex -> 32 chars
PGADMIN_PASSWORD=$(rand_b64 24)

# Compute pgCat MD5 for app_user: md5 + md5(DB_APP_PASS + DB_APP_USER)
compute_md5_concat() {
  local concat="$1$2"
  if command -v md5 >/dev/null 2>&1; then
    # macOS: md5 -q prints hash only
    echo -n "md5$(printf %s "$concat" | md5 -q 2>/dev/null || printf %s "$concat" | md5 | awk '{print $NF}')"
  elif command -v md5sum >/dev/null 2>&1; then
    echo -n "md5$(printf %s "$concat" | md5sum | awk '{print $1}')"
  else
    echo "Error: neither md5 nor md5sum found on PATH" >&2
    exit 1
  fi
}

PGCAT_MD5_APP_USER=$(compute_md5_concat "$DB_APP_PASS" "$DB_APP_USER")

cat <<EOF
# ---- Copy/paste into infra/.env (adjust emails/domains) ----
POSTGRES_DB=peakstone
POSTGRES_SUPERUSER=postgres
POSTGRES_SUPERPASS=${POSTGRES_SUPERPASS}
TZ=UTC

DB_APP_USER=${DB_APP_USER}
DB_APP_PASS=${DB_APP_PASS}

JWT_SECRET=${JWT_SECRET}
HASURA_ADMIN_SECRET=${HASURA_ADMIN_SECRET}
HASURA_CORS=https://app.example.com,https://backoffice.example.com

MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASS=${MINIO_ROOT_PASS}
MINIO_BUCKET=uploads
MINIO_ALIAS=minio
S3_APP_ACCESS_KEY=psappaccess
S3_APP_SECRET_KEY=${S3_APP_SECRET_KEY}

IMGPROXY_KEY_HEX=${IMGPROXY_KEY_HEX}
IMGPROXY_SALT_HEX=${IMGPROXY_SALT_HEX}
IMGPROXY_BASE_URL=https://s3.internal.example.com/
IMGPROXY_ALLOWED_SOURCES=https://s3.internal.example.com/

PGADMIN_EMAIL=admin@example.com
PGADMIN_PASSWORD=${PGADMIN_PASSWORD}

# Domains (example placeholders)
DOMAIN_API=api.internal.example.com
DOMAIN_GQL=gql.internal.example.com
DOMAIN_FILES=s3.internal.example.com
DOMAIN_MINIO_CONSOLE=minio.internal.example.com
DOMAIN_IMG=img.internal.example.com
DOMAIN_PGADMIN=dbadmin.internal.example.com
# Traefik/Dokploy network name
PROXY_NETWORK=dokploy-network
# Optional: pin mc to match your MinIO server release
# MINIO_MC_IMAGE=minio/mc:RELEASE.2025-04-22T22-12-26Z
# -----------------------------------------------------------

# pgCat password for app_user (paste into infra/pgcat/pgcat.toml):
# pools.peakstone_tx.users."${DB_APP_USER}".password = "${PGCAT_MD5_APP_USER}"
# pools.peakstone_session.users."${DB_APP_USER}".password = "${PGCAT_MD5_APP_USER}"
EOF

echo "\nGenerated secrets. Above is a ready-to-paste .env snippet and pgCat MD5." >&2
