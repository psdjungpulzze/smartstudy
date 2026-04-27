# Scalability Infrastructure Setup

One-time steps to wire up the infrastructure that was code-prepared in the
scalability hardening sprint. Each section is independent — do them in order.

---

## 1. PgBouncer (connection pooling)

**Why:** Cloud Run scales to many instances; each Ecto pool holds up to `pool_size`
Postgres connections. Without a pooler you hit Postgres's `max_connections` limit.

**Local test:**
```bash
docker compose --profile pgbouncer up -d pgbouncer_dev
# In .env.dev or your shell:
DATABASE_URL=ecto://postgres:postgres@localhost:5452/fun_sheep_dev iex -S mix phx.server
```

**Cloud (Cloud SQL + PgBouncer on Cloud Run):**
```bash
# Deploy PgBouncer as a sidecar or separate Cloud Run service
gcloud run deploy funsheep-pgbouncer \
  --image edoburu/pgbouncer:1.22.1 \
  --set-env-vars "DB_HOST=/cloudsql/<INSTANCE_CONNECTION_NAME>" \
  --set-env-vars "POOL_MODE=transaction,MAX_CLIENT_CONN=200,DEFAULT_POOL_SIZE=20" \
  --add-cloudsql-instances <INSTANCE_CONNECTION_NAME>

# Then update the app's DATABASE_URL secret to point at the PgBouncer service URL
gcloud secrets versions add DATABASE_URL --data-file=- <<< \
  "ecto://postgres:<PASSWORD>@<PGBOUNCER_CLOUD_RUN_URL>/fun_sheep_prod"
```

> **Note:** The app already sets `prepare: :unnamed` in `config/runtime.exs`, which
> is required for PgBouncer transaction mode. No code change needed.

---

## 2. Cloud SQL Read Replica

**Why:** Moves analytics/reporting queries off the primary DB.

```bash
# Create a read replica in the same region
gcloud sql instances create funsheep-db-replica \
  --master-instance-name=funsheep-db \
  --region=us-central1 \
  --tier=db-g1-small

# After creation, note the replica connection name:
gcloud sql instances describe funsheep-db-replica --format="value(connectionName)"

# Add DATABASE_READ_URL to Secret Manager
gcloud secrets create DATABASE_READ_URL --data-file=- <<< \
  "ecto://postgres:<PASSWORD>@/fun_sheep_prod?host=/cloudsql/<REPLICA_CONNECTION_NAME>"

# Grant Cloud Run access
gcloud secrets add-iam-policy-binding DATABASE_READ_URL \
  --member="serviceAccount:<CLOUD_RUN_SA>@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

The app reads `DATABASE_READ_URL` in `runtime.exs` and starts `FunSheep.RepoRead`
automatically when the var is present.

---

## 3. Cloud Memorystore Redis

**Why:** Shared cache (cohort percentiles, rate-limit counters) that works across
all Cloud Run instances. Without Redis, each instance has its own ETS-only cache.

```bash
# Create a Redis instance (basic tier, 1 GB)
gcloud redis instances create funsheep-redis \
  --size=1 \
  --region=us-central1 \
  --redis-version=redis_7_0 \
  --tier=basic

# Get the host IP
REDIS_HOST=$(gcloud redis instances describe funsheep-redis \
  --region=us-central1 --format="value(host)")
REDIS_PORT=$(gcloud redis instances describe funsheep-redis \
  --region=us-central1 --format="value(port)")

# Add to Secret Manager
gcloud secrets create REDIS_URL --data-file=- <<< "redis://${REDIS_HOST}:${REDIS_PORT}"
```

> **Network:** Cloud Memorystore is VPC-only. Make sure Cloud Run is configured
> with VPC access to the same network as the Redis instance (Serverless VPC Access
> connector or Direct VPC egress).

---

## 4. Cloud CDN

**Why:** Serves fingerprinted JS/CSS assets from edge, reducing latency and
Cloud Run traffic.

```bash
# Requires a Cloud Run load balancer (HTTPS LB with NEG backend)
# If not yet set up:
gcloud compute backend-services create funsheep-backend \
  --global --protocol=HTTP2

gcloud compute backend-services add-backend funsheep-backend \
  --global \
  --network-endpoint-group=<CLOUD_RUN_NEG> \
  --network-endpoint-group-region=us-central1

# Enable CDN on the backend service
gcloud compute backend-services update funsheep-backend \
  --global \
  --enable-cdn \
  --cache-mode=CACHE_ALL_STATIC \
  --default-ttl=86400 \
  --max-ttl=604800
```

Assets under `/assets/` are already served with
`cache-control: public, max-age=31536000, immutable` (set in `endpoint.ex`),
so CDN will cache them at the edge automatically.

---

## 5. Push Notifications (Expo Push API)

No Firebase project or APNs certificate management required. The backend calls
Expo's push relay at `https://exp.host/--/api/v2/push/send`. Expo holds the
FCM and APNs credentials on behalf of all apps built with Expo.

### One-time: link the Expo project

```bash
# Install EAS CLI
npm install -g eas-cli

# Log in with the Expo account that owns the app
eas login

# Inside the mobile/ directory, initialise the EAS project
cd mobile && eas init

# Copy the printed projectId into mobile/app.json under extra.eas.projectId
```

### Optional: Expo access token (higher rate limits)

Without a token the unauthenticated tier allows 600 push requests/min — sufficient
for most apps. To raise this to 1,000 req/min, create a token at
https://expo.dev/accounts/<account>/settings/access-tokens and add it:

```bash
gcloud secrets create EXPO_ACCESS_TOKEN --data-file=- <<< "<token>"
```

### Register Deep Link in Interactor OAuth

The mobile app's PKCE redirect URI is `funsheep://auth/callback`. Add it to the
Interactor OAuth client's allowed redirect URIs:

- Dev/staging client: add `funsheep://auth/callback`
- Production client: add `funsheep://auth/callback`

Contact the Interactor team or update the client config in the Interactor admin panel.

---

## 6. OpenTelemetry (Tracing)

### Honeycomb
```bash
gcloud secrets create HONEYCOMB_API_KEY --data-file=- <<< "<your-honeycomb-api-key>"
gcloud secrets create OTEL_EXPORTER_OTLP_ENDPOINT --data-file=- <<< \
  "https://api.honeycomb.io"
```

### Google Cloud Trace (via OTel Collector sidecar)
Deploy the OTel Collector as a Cloud Run sidecar and set:
```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

---

## 7. Secret → Cloud Run wiring

After creating all secrets, grant access and mount them in the Cloud Run service:

```bash
SA="<CLOUD_RUN_SA>@developer.gserviceaccount.com"
for SECRET in DATABASE_URL DATABASE_READ_URL REDIS_URL \
              EXPO_ACCESS_TOKEN \
              HONEYCOMB_API_KEY OTEL_EXPORTER_OTLP_ENDPOINT; do
  gcloud secrets add-iam-policy-binding $SECRET \
    --member="serviceAccount:$SA" --role="roles/secretmanager.secretAccessor" 2>/dev/null || true
done

# Update the Cloud Run service to mount the new secrets
gcloud run services update funsheep \
  --update-secrets="DATABASE_READ_URL=DATABASE_READ_URL:latest" \
  --update-secrets="REDIS_URL=REDIS_URL:latest" \
  --update-secrets="EXPO_ACCESS_TOKEN=EXPO_ACCESS_TOKEN:latest" \
  --update-secrets="OTEL_EXPORTER_OTLP_ENDPOINT=OTEL_EXPORTER_OTLP_ENDPOINT:latest" \
  --update-secrets="HONEYCOMB_API_KEY=HONEYCOMB_API_KEY:latest"
```
