#!/usr/bin/env bash
set -euo pipefail

# Simple helper to generate strong secrets and pgCat MD5.
# Usage:
#   ./infra/scripts/generate-secrets.sh [DB_APP_USER]
# Defaults:
#   DB_APP_USER=app_user

DB_APP_USER=${1:-app_user}
# Defaults for variables referenced in the template (avoid nounset errors)
POSTGRES_DB=${POSTGRES_DB:-peakstone}
POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER:-postgres}

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

# pgCat admin (for /admin endpoint)
PGCAT_ADMIN_USER=${PGCAT_ADMIN_USER:-pgcat}
PGCAT_ADMIN_PASSWORD=$(rand_b64 24)

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

# pgCat admin (used in pgcat.toml, not in compose)
PGCAT_ADMIN_USER=${PGCAT_ADMIN_USER}
PGCAT_ADMIN_PASSWORD=${PGCAT_ADMIN_PASSWORD}

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

# pgCat (minimal) config snippet — copy to your mounted /etc/pgcat.toml
#
#[general]
#host = "0.0.0.0"
#port = 6432
#admin_username = "${PGCAT_ADMIN_USER}"
#admin_password = "${PGCAT_ADMIN_PASSWORD}"
#
#[pools.${POSTGRES_DB}.users.0]
#username = "${DB_APP_USER}"
#password = "${DB_APP_PASS}"
#pool_size = 20
#min_pool_size = 1
#pool_mode = "session"
#
#[pools.${POSTGRES_DB}.shards.0]
#servers = [["postgres", 5432, "primary"]]
#database = "${POSTGRES_DB}"
EOF

echo "\nGenerated secrets. Above is a ready-to-paste .env snippet and a pgCat config snippet." >&2
