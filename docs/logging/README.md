# Centralized Logging with Loki, Alloy, Grafana (MinIO backend)

What
-
- Loki stores log chunks and indexes in MinIO (bucket `loki`) using TSDB with 7-day retention.
- Grafana Alloy (River) collects Docker logs (opt-in via `logging=alloy`) and ships logs to Loki.
- Grafana provides UI to query (LogQL), explore, dashboard, and live tail logs.

Access
-
- Grafana is exposed via Dokploy Domains (keep Loki/Alloy internal).
- Example domain: https://grafana.dev.your-domain.com (set `DOMAIN_GRAFANA` in env and deploy).

Environment Variables (set via .env or Dokploy)
-
```
# Dedicated MinIO credentials used by Loki (AWS SDK)
LOKI_ACCESS_KEY=REPLACE_ME
LOKI_SECRET_KEY=REPLACE_ME
MINIO_ENDPOINT=http://minio:9000
AWS_REGION=us-east-1

# Grafana bootstrap
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=REPLACE_ME
ENVIRONMENT=dev
```

Notes:
- `minio-init` will create the `loki` bucket and, if `LOKI_ACCESS_KEY/LOKI_SECRET_KEY` are provided, it will create a least‑privilege MinIO user and attach a policy limited to the `loki` bucket.

Compose
-
- Start all services (includes Alloy):
  - `docker compose up -d`
- Start only logging services:
  - `docker compose up -d grafana loki alloy`
- Stop/remove only logging services:
  - `docker compose stop grafana loki alloy && docker compose rm -f grafana loki alloy`

MinIO bucket initialization
-
- The `minio-init` job now also creates the `loki` bucket automatically. If not using `minio-init`, you can create it manually with `mc`.

Opt-in scraping via labels
-
Add labels only to services you want collected (avoid noise/high cardinality):

```yaml
services:
  api:
    # ... existing config ...
    labels:
      logging: "alloy"
      service: "api"
      env: "${ENVIRONMENT:-dev}"
      org: "peakstone"

  storage:
    labels:
      logging: "alloy"
      service: "storage"
      env: "${ENVIRONMENT:-dev}"
      org: "peakstone"

  graphql:
    labels:
      logging: "alloy"
      service: "graphql"
      env: "${ENVIRONMENT:-dev}"
      org: "peakstone"

  pgcat:
    labels:
      logging: "alloy"
      service: "pooler"
      env: "${ENVIRONMENT:-dev}"
      org: "peakstone"
```

Quick snippet to copy into your compose
-
```yaml
# --- Example: API service (add labels for logging) ---
# services:
#   api:
#     # ... your image/config ...
#     labels:
#       - logging=alloy
#       - service=api
#       - env=${ENVIRONMENT:-dev}
#       - org=peakstone
```

How to search (LogQL examples)
-
```logql
{service="api", env="dev"} |= "error"
sum by (service) (rate({level="error"}[5m]))
{service="api"} |~ "HTTP/1\\.1\" 5\\d\\d"
```

Tips
-
- Live tail: Grafana → Explore → toggle “Live”.
- Default data source is provisioned as `Loki`.
- A starter dashboard is provisioned under folder "Logging" → "Starter: Logs Overview".

App JSON logging (API)
-
- Label your API service with `logging=alloy` and `service=api` in `docker-compose.yml` (or in Dokploy service labels).
- Emit structured JSON to stdout. Alloy extracts fields `level`, `msg`, `component`, `event`, `user_id`, `request_id` and promotes a subset as labels (see config.alloy).

Node (pino) example:
```js
// minimal pino
const pino = require('pino');
const logger = pino();

function authSuccess(userId, reqId) {
  logger.info({ component: 'auth', event: 'login_success', user_id: userId, request_id: reqId }, 'login ok');
}

function authFail(userId, reqId) {
  logger.warn({ component: 'auth', event: 'login_failed', user_id: userId, request_id: reqId }, 'login failed');
}
```

Go (log/slog) example:
```go
logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
logger.Info("login ok", "component", "auth", "event", "login_success", "user_id", uid, "request_id", rid)
```

Query examples:
- `{service="api", component="auth", event="login_failed"}`
- `sum by (event) (rate({service="api", component="auth"}[5m]))`

Rollback
-
- Stop/remove logging services and remove labels from any services you no longer want collected:
  - `docker compose stop grafana loki alloy && docker compose rm -f grafana loki alloy`

Acceptance checklist
-
- [ ] `loki`, `alloy`, and `grafana` containers are healthy.
- [ ] MinIO shows `loki` bucket and objects after a few minutes.
- [ ] Visiting Grafana domain authenticates and shows Loki as the default data source.
- [ ] Logs from at least `api` and `storage` appear in Grafana → Explore within 1–2 minutes.
- [ ] Sample LogQL queries return results.
- [ ] Removing the `logging=alloy` label stops ingest for that service.
