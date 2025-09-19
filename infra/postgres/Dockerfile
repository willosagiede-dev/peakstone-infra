FROM postgres:17.6

# Add PGDG repo for extra extensions
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends curl gnupg ca-certificates; \
  . /etc/os-release; \
  echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list; \
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    postgresql-contrib-17 \
    postgresql-17-pgaudit \
    postgresql-17-hypopg \
    postgresql-17-repack \
    postgresql-17-cron; \
  rm -rf /var/lib/apt/lists/*

# Note: shared_preload_libraries and pg_cron DB are set via docker-compose command flags.
