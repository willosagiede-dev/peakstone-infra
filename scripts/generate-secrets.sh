#!/usr/bin/env bash
set -euo pipefail

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required but not found on PATH" >&2
  echo "Install openssl (e.g., brew install openssl or apt-get install openssl) and re-run." >&2
  exit 1
fi

# Simple helper to generate strong secrets and pgCat config hints.
# Usage:
#   chmod +x scripts/generate-secrets.sh (if needed)
#
#   ./scripts/generate-secrets.sh
#
# Defaults for variables referenced in the template (avoid nounset errors)
POSTGRES_DB=${POSTGRES_DB:-postgres}
POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER:-postgres}

rand_b64() { openssl rand -base64 "$1"; }
rand_hex() { openssl rand -hex "$1"; }

# Generate values
POSTGRES_SUPERPASS=$(rand_b64 24)
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
# ---- Copy/paste into .env (adjust emails/domains) and copy pgcat config below to your mounted /etc/pgcat.toml ----

# Postgres
POSTGRES_DB=postgres
POSTGRES_SUPERUSER=postgres
POSTGRES_SUPERPASS=${POSTGRES_SUPERPASS}
TZ=UTC # or America/Denver, pg_cron follows server TZ
POSTGRES_IMAGE=ghcr.io/willosagiede-dev/peakstone-postgres:17.6-exts

# JWT / Hasura
JWT_SECRET=${JWT_SECRET}
HASURA_ADMIN_SECRET=${HASURA_ADMIN_SECRET}
HASURA_CORS=https://app.example.com,https://backoffice.example.com

# MinIO
MINIO_IMAGE=minio/minio:latest
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASS=${MINIO_ROOT_PASS}
MINIO_BUCKET=uploads
MINIO_ALIAS=minio # mc alias name (not a secret)
# MinIO client (mc) image (optional):
# MINIO_MC_IMAGE=minio/mc:latest
S3_APP_ACCESS_KEY=psappaccess
S3_APP_SECRET_KEY=${S3_APP_SECRET_KEY}

# imgproxy (hex keys)
IMGPROXY_KEY_HEX=${IMGPROXY_KEY_HEX}
IMGPROXY_SALT_HEX=${IMGPROXY_SALT_HEX}
IMGPROXY_BASE_URL=https://s3.internal.example.com/
IMGPROXY_ALLOWED_SOURCES=https://s3.internal.example.com/

# pgAdmin
# Use a real email and a strong random password
PGADMIN_EMAIL=admin@example.com
PGADMIN_PASSWORD=${PGADMIN_PASSWORD}

# pgCat admin (used in pgcat.toml, not in compose)
PGCAT_ADMIN_USER=${PGCAT_ADMIN_USER}
PGCAT_ADMIN_PASSWORD=${PGCAT_ADMIN_PASSWORD}

# pgCat image (pin if needed); latest uses minimal config schema
PGCAT_IMAGE=ghcr.io/postgresml/pgcat:latest

# Domains (internal HTTPS via Dokploy Traefik)
DOMAIN_API=api.example.com
DOMAIN_GQL=gql.example.com
DOMAIN_FILES=s3.example.com
DOMAIN_MINIO_CONSOLE=minio.example.com
DOMAIN_IMG=img.example.com
DOMAIN_PGADMIN=dbadmin.example.com

# -----------------------------------------------------------
# Remove the section below from your .env

# pgCat (0.2.5 minimal) config snippet — copy to your mounted /etc/pgcat.toml

[general]
host = "0.0.0.0"
port = 6432
admin_username = "${PGCAT_ADMIN_USER}"
admin_password = "${PGCAT_ADMIN_PASSWORD}"

# Optional hardening
connect_timeout = 5000
idle_timeout    = 30000
healthcheck_timeout = 1000
healthcheck_delay   = 30000
ban_time = 60   # seconds; how long to ban a bad server
worker_threads = 5  # number of worker threads
autoreload = 15000

tcp_keepalives_idle = 5
tcp_keepalives_count = 5
tcp_keepalives_interval = 5

# Pool name matches DB clients connect to
[pools.${POSTGRES_DB}]
pool_mode = "session"   # Hasura needs session; PostgREST can use transaction if you run a second pgcat
default_role = "primary"    # route to primary by default

[pools.${POSTGRES_DB}.users.0]
username = "${POSTGRES_SUPERUSER}"
password = "${POSTGRES_SUPERPASS}"
pool_size = 20
min_pool_size = 1

[pools.${POSTGRES_DB}.shards.0]
database = "${POSTGRES_DB}"     # replace with POSTGRES_DB
servers = [
    ["postgres", 5432, "primary"]   # Docker service name + port
    # ["postgres-replica-1", 5432, "replica"],
]

EOF

echo "\nGenerated secrets. Above is a ready-to-paste .env snippet and a pgCat config snippet." >&2
