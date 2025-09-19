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
    postgresql-17-contrib \
    postgresql-17-pgaudit \
    postgresql-17-hypopg \
    postgresql-17-repack \
    postgresql-17-cron \
    postgresql-17-qualstats; \
  rm -rf /var/lib/apt/lists/*

# Preload libraries needed by some extensions and configure pg_cron
# (The sample file is copied into new clusters by the official image.)
RUN echo "shared_preload_libraries = 'pg_stat_statements,pgaudit,pg_cron,pg_qualstats'" >> /usr/local/share/postgresql/postgresql.conf.sample \
 && echo "cron.database_name = 'postgres'" >> /usr/local/share/postgresql/postgresql.conf.sample