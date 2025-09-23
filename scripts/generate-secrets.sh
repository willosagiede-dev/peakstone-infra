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

# Logging / Grafana / Loki
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASSWORD=$(rand_b64 24)
LOKI_ACCESS_KEY=$(rand_hex 20)
LOKI_SECRET_KEY=$(rand_b64 24)

# pgCat admin (for /admin endpoint)
PGCAT_ADMIN_USER=${PGCAT_ADMIN_USER:-pgcat}
PGCAT_ADMIN_PASSWORD=$(rand_b64 24)

# DB app roles
DB_AUTHENTICATOR_PASSWORD=$(rand_b64 24)
HASURA_DB_PASSWORD=$(rand_b64 24)
DB_MIGRATOR_PASSWORD=$(rand_b64 24)

cat <<EOF
# ---- Copy/paste into .env (adjust emails/domains) and copy pgcat config below to your mounted /etc/pgcat.toml ----

# --- Postgres Database ---
POSTGRES_DB=postgres
POSTGRES_SUPERUSER=postgres
POSTGRES_SUPERPASS=${POSTGRES_SUPERPASS}
TZ=UTC # or America/Denver, pg_cron follows server TZ

# Postgres custom image
POSTGRES_IMAGE=ghcr.io/willosagiede-dev/peakstone-postgres:17.6-exts

# Database app roles (least-privilege)
DB_AUTHENTICATOR_PASSWORD=${DB_AUTHENTICATOR_PASSWORD}
HASURA_DB_PASSWORD=${HASURA_DB_PASSWORD}
DB_MIGRATOR_PASSWORD=${DB_MIGRATOR_PASSWORD}

# JWT / Hasura
JWT_SECRET=${JWT_SECRET}
HASURA_ADMIN_SECRET=${HASURA_ADMIN_SECRET}
HASURA_CORS=https://app.example.com,https://backoffice.example.com

# Local bind paths for persisted data (adjust if not using Dokploy's ../files/ structure)
PG_DATA_HOST_DIR=../files/volumes/db
MINIO_DATA_HOST_DIR=../files/volumes/storage/minio_data
PGCAT_CONFIG_PATH=../files/volumes/pgcat.toml

# pgAdmin
PGADMIN_EMAIL=admin@example.com     # Use a real email
PGADMIN_PASSWORD=${PGADMIN_PASSWORD}

# pgCat image (pin if needed); latest uses minimal config schema
PGCAT_IMAGE=ghcr.io/postgresml/pgcat:latest

# --- MinIO Storage ---
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASS=${MINIO_ROOT_PASS}
MINIO_BUCKET=uploads
MINIO_ALIAS=minio # mc alias name (not a secret)

# Endpoint for MinIO inside the Docker network
MINIO_ENDPOINT=minio:9000
AWS_REGION=us-east-1

# S3 Access Keys
S3_APP_ACCESS_KEY=psappaccess
S3_APP_SECRET_KEY=${S3_APP_SECRET_KEY}

# MinIO images
MINIO_IMAGE=minio/minio:latest
MINIO_MC_IMAGE=minio/mc:latest      # MinIO client (mc) image

# imgproxy (hex keys)
IMGPROXY_KEY_HEX=${IMGPROXY_KEY_HEX}
IMGPROXY_SALT_HEX=${IMGPROXY_SALT_HEX}
IMGPROXY_BASE_URL=https://s3.internal.example.com/
IMGPROXY_ALLOWED_SOURCES=https://s3.internal.example.com/

# --- Domains (internal HTTPS via Dokploy Traefik) ---
DOMAIN_API=api.example.com      # → PostgREST
DOMAIN_GQL=gql.example.com      # → Hasura
DOMAIN_FILES=s3.example.com     # → MinIO (S3 API)
DOMAIN_MINIO_CONSOLE=minio.example.com  # → MinIO (S3 Console)
DOMAIN_IMG=img.example.com      # → imgproxy
DOMAIN_PGADMIN=dbadmin.example.com     # → pgAdmin
DOMAIN_GRAFANA=grafana.example.com     # → Grafana

# --- Logging stack (Loki/Promtail/Grafana) ---
# Grafana bootstrap credentials
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# Dedicated MinIO credentials used by Loki (via AWS SDK)
LOKI_ACCESS_KEY=${LOKI_ACCESS_KEY}
LOKI_SECRET_KEY=${LOKI_SECRET_KEY}

# Environment label for log streams
ENVIRONMENT=dev

# --- Atlas migrations ---
# Select env for atlas-migrate one-off job: dev|staging|prod
ATLAS_ENV=prod
# Connection URLs (do not commit real secrets; set in Dokploy for prod)
# Prefer a dedicated migrator role (db_migrator) for Atlas
ATLAS_DEV_URL=postgres://db_migrator:${DB_MIGRATOR_PASSWORD}@localhost:5432/${POSTGRES_DB}?sslmode=disable
ATLAS_STAGING_URL=postgres://db_migrator:${DB_MIGRATOR_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable
ATLAS_PROD_URL=postgres://db_migrator:${DB_MIGRATOR_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable

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
ban_time = 60
worker_threads = 5
autoreload = 15000

tcp_keepalives_idle = 5
tcp_keepalives_count = 5
tcp_keepalives_interval = 5

# Pool name matches DB clients connect to
[pools.${POSTGRES_DB}]
pool_mode = "session"
default_role = "primary"

[pools.${POSTGRES_DB}.users.0]
username = "db_authenticator"
password = "${DB_AUTHENTICATOR_PASSWORD}"
pool_size = 20
min_pool_size = 1

[pools.${POSTGRES_DB}.users.1]
username = "hasura"
password = "${HASURA_DB_PASSWORD}"
pool_size = 10
min_pool_size = 1

[pools.${POSTGRES_DB}.shards.0]
database = "${POSTGRES_DB}"
servers = [
    ["postgres", 5432, "primary"]   # Docker service name + port
    # ["postgres-replica-1", 5432, "replica"],
]

EOF

echo "\nGenerated secrets. Above is a ready-to-paste .env snippet and a pgCat config snippet." >&2
