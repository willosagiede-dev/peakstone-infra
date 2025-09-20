# PeakStone Infra (Dokploy)

This repo contains the shared “backend as a service” stack for PeakStone:
- Postgres 17.6 (custom image with pg_cron, pgaudit, etc.)
- pgCat (two pools: transaction + session)
- PostgREST (REST over RLS)
- Hasura CE (GraphQL + subscriptions)
- MinIO + imgproxy
- pgAdmin
- MinIO bootstrap job (mc)
- Docker Compose (no version key)

## Quick start

1) **Create the repo & push**
git init peakstone-infra && cd peakstone-infra
# add all files from this folder structure
git add .
git commit -m "infra: initial stack"
git branch -M main
# on GitHub/GitLab, create an empty repo then:
git remote add origin <YOUR_GIT_REMOTE_URL>
git push -u origin main

## Secrets to set

Populate `infra/.env.example` (copy to `infra/.env`) with strong values:
- POSTGRES_SUPERPASS: 24–32 char random
- DB_APP_PASS: 24–32 char random
- JWT_SECRET: 32 bytes random (hex or base64)
- HASURA_ADMIN_SECRET: 32 bytes random
- MINIO_ROOT_PASS: 24–32 char random
- S3_APP_SECRET_KEY: 24–32 char random
- IMGPROXY_KEY_HEX: 32-byte hex (64 hex chars)
- IMGPROXY_SALT_HEX: 16-byte hex (32 hex chars)
- PGADMIN_EMAIL / PGADMIN_PASSWORD: real email + strong password
 - pgCat admin: choose `PGCAT_ADMIN_USER` and a strong `PGCAT_ADMIN_PASSWORD` (used to secure pgCat admin APIs)

### pgCat config (minimal)

Use the minimal config format (v1.2.0) and mount it to `/etc/pgcat.toml`. The pool name must match your database (e.g., `peakstone`). Passwords are plain: use `DB_APP_USER` and `DB_APP_PASS` you generated.

Example:

```
[general]
host = "0.0.0.0"
port = 6432
admin_username = "pgcat"
admin_password = "change-this-strong"

[pools.peakstone.users.0]
username = "app_user"
password = "appsecret"
pool_size = 20
min_pool_size = 1
pool_mode = "session"

[pools.peakstone.shards.0]
servers = [["postgres", 5432, "primary"]]
database = "peakstone"
```

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

# pgCat md5 for app_user (replace pass/user if different)
DB_APP_PASS="appsecret"; DB_APP_USER="app_user";
echo -n "md5$(printf "%s" "$DB_APP_PASS$DB_APP_USER" | md5)"


Paste the resulting `md5...` value into both `password` entries for `app_user` in `infra/pgcat/pgcat.toml`.

### One-shot generator script

You can generate a complete .env snippet and the pgCat MD5 with:

./infra/scripts/generate-secrets.sh
# defaults DB_APP_USER to app_user
# or use -- ./infra/scripts/generate-secrets.sh [DB_APP_USER] -- to generate with your custom DB_APP_USER


It prints:
- Ready-to-paste env lines for `infra/.env`
- pgCat admin credentials
- A ready-to-copy pgCat minimal config snippet

## Notes

- MinIO policy now follows `MINIO_BUCKET` dynamically during bootstrap; no manual edits needed.
- Ensure your Traefik/Dokploy network exists (`dokploy-network`) before bringing the stack up.
  - You can customize the network name via `PROXY_NETWORK` in `infra/.env`.
- PostgREST uses role `web_anon`, created in the Postgres init script.

### Service settings

- MinIO client image (mc)
  - `minio-init` uses `${MINIO_MC_IMAGE}`; default is `minio/mc:latest`.
  - If you want to pin, set `MINIO_MC_IMAGE` in `infra/.env` to a valid tag from the mc repository (e.g., `minio/mc:RELEASE.<date>` that actually exists).
  - MinIO server image is set via `MINIO_IMAGE` (default `minio/minio:latest`). Pin this to a specific release if you need a known console version.

- imgproxy allowed sources
  - Set `IMGPROXY_ALLOWED_SOURCES` in `infra/.env` to a comma‑separated list of URL prefixes that imgproxy is allowed to fetch from.
  - Example (production): `https://s3.internal.example.com/`
  - Example (local): `http://localhost:9000/` or `http://minio:9000/`
  - Keep it as tight as possible to avoid pulling from arbitrary hosts.

## Healthchecks & Startup

- Postgres includes a healthcheck (`pg_isready`).
- Dependent services now wait on Postgres healthy; pgCat waits on DB bootstrap to complete.

## Pin Images by Digest

For reproducible deployments, generate a pinned override file with image digests:

./infra/scripts/pin-images.sh
# Then use the override when deploying
docker compose -f infra/docker-compose.yml -f infra/docker-compose.pinned.yml up -d


Notes:
- This resolves and pins registry images (pgCat, PostgREST, Hasura, MinIO, mc, imgproxy, pgAdmin).
- The custom Postgres image is built locally (not pinned by digest here). To pin it, push to a registry first and reference the resulting digest.

## Run Locally (no Traefik)

This repo is designed for Traefik/Dokploy in production. For local testing without Traefik, use the provided override to expose ports on localhost.

1) Generate secrets and prepare .env
- Copy the example and fill with strong values:
  - cp infra/.env.example infra/.env
- Optional helper:
  - ./infra/scripts/generate-secrets.sh [DB_APP_USER]
  - Paste the output into infra/.env
- Copy the pgCat config example and fill passwords:
  - cp infra/pgcat/pgcat.toml.example infra/pgcat/pgcat.toml
  - Compute pgCat MD5 (the generator prints it) and update both entries in infra/pgcat/pgcat.toml, replacing md5__FILL_ME__.

2) Build the custom Postgres image
- Option A (local build):
  - docker compose -f infra/docker-compose.yml -f infra/docker-compose.build.yml build postgres
  - docker compose -f infra/docker-compose.yml -f infra/docker-compose.build.yml up -d postgres
  - This uses a local image tag: local/peakstone-postgres:17.6-exts
- Option B (pull from GHCR): set `POSTGRES_IMAGE` in `infra/.env` to the GHCR image you publish (see below), then skip local build.

3) Start the stack with local override
- docker compose -f infra/docker-compose.yml -f infra/docker-compose.local.yml up -d

4) Verify services
- Check status: docker compose -f infra/docker-compose.yml -f infra/docker-compose.local.yml ps
- Tail logs (e.g. postgres): docker compose -f infra/docker-compose.yml logs -f postgres

5) Access endpoints on localhost
- PostgREST: http://localhost:3000
- Hasura: http://localhost:8080/healthz (200 OK)
- MinIO API: http://localhost:9000 (S3)
- MinIO Console: http://localhost:9001
- imgproxy: http://localhost:8081
- pgAdmin: http://localhost:8082

6) Connect pgAdmin to pgCat
- Add a new server:
  - Name: PeakStone via pgCat
  - Host: pgcat
  - Port: 6432
  - Username: DB_APP_USER from .env
  - Password: DB_APP_PASS from .env
  - Database: POSTGRES_DB from .env (optional, can leave blank)

Notes
- If a localhost port is taken, edit infra/docker-compose.local.yml and change the left-hand port.
- For production/Dokploy, don’t use the local override. Use the main compose (and optional pinned override) with Traefik.

## Production Postgres Image (GHCR)

Build and publish your custom Postgres image to GHCR so Dokploy pulls it instead of building on the server.

1) Enable GitHub Packages for the repo
- Ensure Actions has packages: write permissions (this workflow sets it).

2) Build via GitHub Actions
- Trigger the workflow manually (Actions → Build Postgres Image → Run) or push changes under `infra/postgres/`.
- The workflow publishes:
  - ghcr.io/<OWNER>/peakstone-postgres:17.6-exts
  - ghcr.io/<OWNER>/peakstone-postgres:latest

3) Configure Dokploy to use the image
- Set `POSTGRES_IMAGE` in `infra/.env` (or Dokploy’s env UI) to your GHCR image, e.g.:
  - POSTGRES_IMAGE=ghcr.io/<OWNER>/peakstone-postgres:17.6-exts
- Make sure Dokploy can pull from GHCR (public is easiest). For private images, add registry credentials in Dokploy.

4) Deploy
- In Dokploy, point to `infra/docker-compose.yml` (and optional pinned override).
- Deploy; the server will pull your prebuilt Postgres image.
