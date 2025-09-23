# PeakStone Infra (Dokploy)

This repo contains the shared “backend as a service” stack for PeakStone:
- Postgres 17.6 (custom image with pg_cron, pgaudit, etc.)
- pgCat connection pooler
- PostgREST (REST over RLS)
- Hasura CE (GraphQL + subscriptions)
- MinIO + imgproxy
- pgAdmin
- MinIO bootstrap job (mc)
- Docker Compose (no version key)
- Centralized logging: Loki + Promtail + Grafana (MinIO object store)

## Secrets to set

Populate `.env.example` (copy to `.env`) with strong values:
- POSTGRES_SUPERPASS: 24–32 char random
- JWT_SECRET: 32 bytes random (hex or base64)
- HASURA_ADMIN_SECRET: 32 bytes random
- MINIO_ROOT_PASS: 24–32 char random
- S3_APP_SECRET_KEY: 24–32 char random
- IMGPROXY_KEY_HEX: 32-byte hex (64 hex chars)
- IMGPROXY_SALT_HEX: 16-byte hex (32 hex chars)
- PGADMIN_EMAIL / PGADMIN_PASSWORD: real email + strong password
 - pgCat admin: choose `PGCAT_ADMIN_USER` and a strong `PGCAT_ADMIN_PASSWORD` (used to secure pgCat admin APIs)
 - Logging: `LOKI_ACCESS_KEY` / `LOKI_SECRET_KEY`, `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`
 - App DB roles: `DB_AUTHENTICATOR_PASSWORD` (PostgREST) and `HASURA_DB_PASSWORD` (Hasura)
 - Migrations: `DB_MIGRATOR_PASSWORD` (Atlas migrator user)

### pgCat config (0.2.5 minimal)

Mount a minimal config to `/etc/pgcat.toml`. The pool name must match your database (e.g., `postgres`). Passwords are plain (this setup uses the Postgres superuser for simplicity).

Example:

```
[general]
host = "0.0.0.0"
port = 6432
admin_username = "pgcat"
admin_password = "change-this-strong"

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
[pools.postgres]
pool_mode = "session"       # Hasura needs session; PostgREST can use transaction if you run a second pgcat
default_role = "primary"    # route to primary by default

[pools.postgres.users.0]
username = "postgres"       # replace with POSTGRES_SUPERUSER if different
password = "<POSTGRES_SUPERPASS>"  # replace with your superuser password
pool_size = 20
min_pool_size = 1

[pools.postgres.shards.0]
database = "postgres"       # replace with POSTGRES_DB
servers = [
  ["postgres", 5432, "primary"]  # Docker service name + port
]
```

Notes:
- Ensure the pool section key matches your database name (e.g., `postgres`).

Pinning pgCat image
- Compose accepts `PGCAT_IMAGE`. To pin to a stable tag (e.g., v0.2.5):
  - Set in `.env`: `PGCAT_IMAGE=ghcr.io/postgresml/pgcat:v0.2.5` (or `:latest`)
  - Confirm the tag exists in the registry you’re pulling from.

- Common pitfalls
- If pgCat logs show it tries `127.0.0.1` or `database = "postgres"`, update your mounted `/etc/pgcat.toml`:
  - Use `servers = [["postgres", 5432, "primary"]]` (the Docker service name on the internal network)
  - Set `database = "${POSTGRES_DB}"` (e.g., `postgres`)
  - Ensure `username`/`password` match `POSTGRES_SUPERUSER`/`POSTGRES_SUPERPASS`

### Generate examples

# 32 bytes hex (JWT, Hasura)
openssl rand -hex 32

# 24-char base64 (general secrets)
openssl rand -base64 24

# imgproxy: key (32 bytes hex) and salt (16 bytes hex)
IMGPROXY_KEY_HEX=$(openssl rand -hex 32)
IMGPROXY_SALT_HEX=$(openssl rand -hex 16)
echo $IMGPROXY_KEY_HEX
echo $IMGPROXY_SALT_HEX

##

### One-shot generator script

You can generate a complete .env snippet with:

chmod +x scripts/generate-secrets.sh (if needed)

./scripts/generate-secrets.sh


It prints:
- Ready-to-paste env lines for `.env`
- pgCat admin credentials
- A ready-to-copy pgCat (0.2.5 minimal) config snippet (using postgres user)

## Notes

- MinIO policy now follows `MINIO_BUCKET` dynamically during bootstrap; no manual edits needed.
- Ensure your Traefik/Dokploy network exists (`dokploy-network`) before bringing the stack up.
  - You can customize the network name via `PROXY_NETWORK` in `.env`.
- PostgREST uses role `web_anon` if present.

### Service settings

- MinIO client image (mc)
  - `minio-init` uses `${MINIO_MC_IMAGE}`; default is `minio/mc:latest`.
  - If you want to pin, set `MINIO_MC_IMAGE` in `.env` to a valid tag from the mc repository (e.g., `minio/mc:RELEASE.<date>` that actually exists).
  - MinIO server image is set via `MINIO_IMAGE` (default `minio/minio:latest`). Pin this to a specific release if you need a known console version.

- imgproxy allowed sources
  - Set `IMGPROXY_ALLOWED_SOURCES` in `.env` to a comma‑separated list of URL prefixes that imgproxy is allowed to fetch from.
  - Example (production): `https://s3.internal.example.com/`
  - Example (local): `http://localhost:9000/` or `http://minio:9000/`
  - Keep it as tight as possible to avoid pulling from arbitrary hosts.

## Healthchecks & Startup

- Postgres includes a healthcheck (`pg_isready`).
- Dependent services now wait on Postgres healthy.
- A one‑off `db-bootstrap` job sets up least‑privilege roles, grants, and passwords for app connections.

## Database Migrations (Atlas)

- We use Atlas (ariga.io/atlas) for versioned migrations.
- Repo layout:
  - `atlas/migrations/` stores migration files.
- One‑off job: `atlas-migrate` runs `atlas migrate apply --dir file://migrations --url ${ATLAS_URL}` before app services start.
- Configure URL in `.env` (or Dokploy):
  - `ATLAS_URL` (use `db_migrator` credentials for the target env)
  - Note: DDL on existing objects may require ownership. We set schema ownership to `db_migrator` for a new DB to simplify this.

Local dev flow
- Apply with URL: `docker compose run --rm atlas-migrate atlas migrate apply --dir file://migrations --url $ATLAS_URL`
- Diff (from dev DB): run Atlas locally on your machine against dev DB and write files under `atlas/migrations`.

Deploy flow (Dokploy)
- Ensure `ATLAS_URL` is set in the environment to your target DB.
- `atlas-migrate` runs automatically in the compose (one‑off) and app services depend on its success.

## Migrating from Supabase

This stack can receive your data from Supabase Cloud. A few tips make it smooth:

- Ownership & privileges
  - Schemas are owned by `db_migrator`. Restore with ownership stripped and re‑owned to `db_migrator` to avoid role mismatches.
  - Use `pg_restore` flags: `--no-owner --no-privileges --role=db_migrator`.

- Supabase-specific roles & policies
  - Supabase often references roles `anon`, `authenticated`, `service_role` in policies. Our bootstrap creates these as `NOLOGIN` placeholders so `CREATE POLICY` doesn’t fail.
  - We also provide a compatibility function `auth.uid()` (postgres/init/010-auth-compat.sql) that reads the user id from PostgREST's JWT claims or Hasura's session header so existing policies using `auth.uid()` continue to work.
  - If you plan to replace RLS with your own (PostgREST/Hasura), exclude policies from the dump or adjust after restore.

- Supabase extensions/schemas
  - Exclude Supabase-only schemas you don’t need (e.g., `supabase_*`, `auth`, `realtime`) to keep your DB lean.
  - Only include extensions you actually use; our image ships common ones (pg_stat_statements, pgaudit, pg_cron, etc.).

- Example commands
  - All-in-one (recommended for clean import):
    - Dump: `pg_dump -Fc --no-owner --no-privileges "$SUPABASE_URL" -f all.dump`
    - Restore: `pg_restore -d "$TARGET_URL" --no-owner --no-privileges --role=db_migrator -j4 all.dump`
  - Schema/data split:
    - Schema: `pg_dump -Fc --schema-only --no-owner --no-privileges "$SUPABASE_URL" -f schema.dump`
    - Data: `pg_dump -Fc --data-only "$SUPABASE_URL" -f data.dump`
    - Restore schema: `pg_restore -d "$TARGET_URL" --no-owner --no-privileges --role=db_migrator -j4 schema.dump`
    - Restore data: `pg_restore -d "$TARGET_URL" --role=db_migrator -j4 data.dump`
  - Target URL example: `TARGET_URL=postgres://db_migrator:${DB_MIGRATOR_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable`

- Post-restore sanity
  - Run `VACUUM ANALYZE;` (optional but recommended).
  - Check sequences (pg_restore usually sets them correctly).
  - Verify app access via PostgREST and Hasura with least‑privilege roles.

## Image Versions

- Images are controlled via tags in `docker-compose.yml` or `.env`.
- If you need fully reproducible builds, pin images by digest manually in your compose or registry automation. This repo no longer includes a digest pinning script.

## Local Usage

This repo targets Traefik/Dokploy deployments. For local testing, you can still run the stack directly:

1) Prepare `.env`
- Copy example and fill values: `cp .env.example .env`
- Optional helper: `./scripts/generate-secrets.sh` and paste into `.env`
- Copy pgCat config example and fill passwords (using postgres user):
  - `cp pgcat/pgcat.toml.example pgcat/pgcat.toml`
  - Set username/password to POSTGRES_SUPERUSER/POSTGRES_SUPERPASS

2) Start the stack
- `docker compose up -d`

3) Verify services
- `docker compose ps`
- Tail logs (e.g. postgres): `docker compose logs -f postgres`

## Production Postgres Image (GHCR)

Build and publish your custom Postgres image to GHCR so Dokploy pulls it instead of building on the server.

1) Enable GitHub Packages for the repo
- Ensure Actions has packages: write permissions (this workflow sets it).

2) Build via GitHub Actions
- Trigger the workflow manually (Actions → Build Postgres Image → Run) or push changes under `postgres/`.
- The workflow publishes:
  - ghcr.io/<OWNER>/peakstone-postgres:17.6-exts
  - ghcr.io/<OWNER>/peakstone-postgres:latest

3) Configure Dokploy to use the image
- Set `POSTGRES_IMAGE` in `.env` (or Dokploy’s env UI) to your GHCR image, e.g.:
  - POSTGRES_IMAGE=ghcr.io/<OWNER>/peakstone-postgres:17.6-exts
- Make sure Dokploy can pull from GHCR (public is easiest). For private images, add registry credentials in Dokploy.

4) Deploy
- In Dokploy, point to `docker-compose.yml`.
- Deploy; the server will pull your prebuilt Postgres image.

## Logging: API labels example

To opt-in your API service for centralized logging, add labels like this to your `docker-compose.yml` (or via Dokploy service labels):

```yaml
# --- Example: API service (add labels for logging) ---
# services:
#   api:
#     # ... your image/config ...
#     labels:
#       - logging=promtail
#       - service=api
#       - env=${ENVIRONMENT:-dev}
#       - org=peakstone
```

## Logging: Grafana Access

- Domain: set `DOMAIN_GRAFANA` in `.env` (Dokploy maps the domain to service `grafana`).
- Login: `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` from `.env`.
- Data source: Loki is pre-provisioned and set as default.
- Explore logs: Grafana → Explore → select `Loki` → run queries.
- Example queries:
  - `{service="api"} |= "error"`
  - `sum by (service) (rate({env="dev"}[5m]))`
  - `{service="postgres", component="auth"}`
- Quick control (logging only):
  - Up: `docker compose up -d grafana loki promtail`
  - Down: `docker compose stop grafana loki promtail && docker compose rm -f grafana loki promtail`
  - Status: `docker compose ps grafana loki promtail`
- Security: Only `grafana` is exposed via Traefik. `loki` and `promtail` remain internal.

## Least‑Privilege DB Roles

- A `db-bootstrap` one‑off container (runs after Postgres healthy) creates roles and grants, and sets passwords:
  - Roles: `web_anon` (NOLOGIN), `app_user` (NOLOGIN), `db_authenticator` (LOGIN), `hasura` (LOGIN), `read_only` (NOLOGIN), `db_migrator` (LOGIN)
  - Grants & ownership: application schemas are owned by `db_migrator`; app_user/hasura get DML; web_anon/read_only get SELECT.
  - Defaults: future objects created by `db_migrator` grant SELECT to web_anon/read_only and DML to app_user/hasura.
  - Auth pattern: `db_authenticator` can `SET ROLE` to `web_anon` or `app_user`.
- Connections (via pgCat):
  - PostgREST: `postgres://db_authenticator:${DB_AUTHENTICATOR_PASSWORD}@pgcat:6432/${POSTGRES_DB}`
  - Hasura: `postgres://hasura:${HASURA_DB_PASSWORD}@pgcat:6432/${POSTGRES_DB}`
- If your DB is already initialized, this job safely applies changes idempotently.

## Traefik Labels and Dokploy Networking

- Purpose: The `traefik.*` labels in `docker-compose.yml` tell Dokploy’s built‑in Traefik how to route inbound HTTPS traffic to each service and which internal port to forward to.
- Assumptions:
  - External network: `dokploy-network` (configurable via `PROXY_NETWORK` in `.env`).
  - Domains: set `DOMAIN_*` variables in `.env` (e.g., `DOMAIN_API`, `DOMAIN_GQL`, `DOMAIN_FILES`, `DOMAIN_GRAFANA`).
  - TLS: Traefik terminates TLS (LetsEncrypt) at the edge; containers stay on the internal network.
- Exposure policy:
  - Only `grafana` is intentionally exposed for the logging stack.
  - `loki` and `promtail` remain internal with no public routes.

Not using Dokploy/Traefik?
- Option A — Keep labels, run your own Traefik:
  - Ensure your Traefik instance joins the same Docker network (e.g., `dokploy-network`), has ACME configured, and honors the labels.
- Option B — Remove labels and expose host ports directly:
  - Delete the `traefik.*` labels for any service you want to expose and add `ports:` bindings. Point your DNS (A/AAAA records) to the host, and terminate TLS with your chosen proxy (Nginx/Caddy) or use plain HTTP for local.
  - Example (PostgREST):
    - Remove the `traefik.*` labels under `services.postgrest`.
    - Add:
      - `ports: ["3000:3000"]`
  - Example (Grafana):
    - Remove `traefik.*` labels under `services.grafana`.
    - Add:
      - `ports: ["3000:3000"]`

Notes
- If you keep Traefik, do not also publish the same service ports on the host to avoid conflicts.
- If you change the network name, update `PROXY_NETWORK` and ensure the network exists before `docker compose up`.

## More on Logging

- Detailed setup, labels, queries, and troubleshooting live in `docs/logging/README.md`.

## Database Access (Ports and Best Practices)

- Recommended: keep database ports closed publicly.
  - Do not expose `postgres:5432` or `pgcat:6432` to the Internet.
  - Inside the Docker network, services connect to `postgres:5432` and `pgcat:6432` directly.
- Admin access options:
  - Use `pgadmin` (exposed via Traefik at `DOMAIN_PGADMIN`).
  - Use a VPN (e.g., Tailscale/WireGuard) to reach the host’s private network and connect to pgCat on `6432`.
  - Use a short‑lived SSH tunnel when needed:
    - `ssh -L 6432:localhost:6432 user@your-host` → connect client to `localhost:6432` (pgCat)
    - `ssh -L 5432:localhost:5432 user@your-host` → Postgres direct (only if required)
- Local development (optional):
  - For local only, you may temporarily publish ports with an override file, e.g. `ports: ["5432:5432"]` under `postgres` or `ports: ["6432:6432"]` under `pgcat`.
  - Avoid publishing ports in production; rely on Traefik + VPN/SSH for secure access.
