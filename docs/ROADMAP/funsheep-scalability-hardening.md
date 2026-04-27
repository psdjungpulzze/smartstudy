# FunSheep Scalability Hardening

**Status:** Planning  
**Category:** Infrastructure  
**Scope:** Make frontend, backend, database, and cache independently scalable to support mobile launch growth

---

## 1. Problem Summary

The compute tier (Cloud Run) already auto-scales horizontally. Everything else is a bottleneck:

| Layer | Issue |
|-------|-------|
| Database | Single Cloud SQL Postgres — all instances share it, no read replicas, no pooling proxy |
| Connection pool | No PgBouncer; at 3 API × 10 + 2 worker × 50 = 130 simultaneous connections, pool exhaustion is documented (April 2026 incident) |
| Assessment state | ETS cache is node-local; lost on instance crash or reconnect to different node |
| Tutor sessions | GenServer registry is node-local; not cluster-aware |
| Static assets | Served by Phoenix directly; no CDN; competes with API traffic |
| Shared cache | Doesn't exist; cohort percentiles, rate-limit state duplicated per instance |
| Worker scaling | Fixed at 2–5 instances; not driven by queue depth |
| Health check | `/health` returns 200 even when DB is unreachable; Cloud Run can't detect sick instances |

---

## 2. Target Architecture

```
                        ┌─────────────────────┐
                        │   Cloud CDN / CF    │  ← static assets cached globally
                        └──────────┬──────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                   │                    │
     ┌────────▼────────┐ ┌────────▼────────┐  ┌───────▼───────┐
     │  API instances  │ │  API instances  │  │  API instance │
     │  (Cloud Run)    │ │  (Cloud Run)    │  │  (Cloud Run)  │
     └────────┬────────┘ └────────┬────────┘  └───────┬───────┘
              └────────────────────┼────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                   │                    │
     ┌────────▼────────┐ ┌────────▼────────┐  ┌───────▼───────┐
     │  PgBouncer      │ │  Redis          │  │  Horde        │
     │  (pooling)      │ │  (shared cache) │  │  (registry)   │
     └────────┬────────┘ └─────────────────┘  └───────────────┘
              │
   ┌──────────┴──────────┐
   │                     │
┌──▼─────────┐  ┌────────▼───────┐
│  Primary   │  │  Read Replica  │
│  Postgres  │  │  Postgres      │
└────────────┘  └────────────────┘
```

---

## 3. Phase 1 — Database Hardening (Highest Priority)

**Goal:** Remove Postgres as the single point of failure and connection bottleneck.

### 3a. PgBouncer Connection Proxy

**Problem:** Each Cloud Run instance opens its own Ecto pool. At modest scale (3 API + 2 worker instances), the app needs 130 simultaneous Postgres connections. Cloud SQL max_connections defaults to ~100 on small instances.

**Fix:** Deploy PgBouncer as a sidecar or shared proxy.

**Options (pick one):**

| Option | Pros | Cons |
|--------|------|------|
| Cloud SQL Auth Proxy + PgBouncer sidecar | Simple, no extra infra | One proxy per Cloud Run instance |
| Managed PgBouncer on Cloud SQL | Google manages it | Limited config |
| AlloyDB (Postgres-compatible) | Built-in connection pooling | Migration effort, cost |
| **Supabase Pooler (Supavisor)** | Drop-in, external, transaction mode | Extra network hop |

**Recommended:** Start with Cloud SQL's built-in connection pool (available in Cloud SQL Enterprise Plus) or deploy a standalone PgBouncer on Cloud Run with `min_pool_size=2`, `max_pool_size=25`, `pool_mode=transaction`.

**Config change (runtime.exs):**
```elixir
# Point DATABASE_URL at PgBouncer, not Cloud SQL directly
# PgBouncer listens on port 6432, forwards to Cloud SQL
pool_size: System.get_env("POOL_SIZE", "5") |> String.to_integer()
# Pool size per instance drops to 5 since PgBouncer manages the real connections
```

**Deliverables:**
- [ ] Deploy PgBouncer (Cloud Run service or Cloud SQL built-in)
- [ ] Update `DATABASE_URL` in all Cloud Run services to point at PgBouncer
- [ ] Reduce per-instance `POOL_SIZE` from 10→5 (API) and 50→10 (worker)
- [ ] Verify Oban works in transaction-mode pooling (it does, with `prepare: :unnamed`)
- [ ] Load test: simulate 10 API instances, verify no pool exhaustion

### 3b. Read Replica for Heavy Read Queries

**Problem:** Assessment state, cohort percentiles, leaderboard queries, course content — all reads that don't need to hit the primary.

**Fix:** Create a Cloud SQL read replica. Add a second `Repo` in the app pointed at the replica.

**Implementation:**
```elixir
# lib/fun_sheep/repo_read.ex
defmodule FunSheep.RepoRead do
  use Ecto.Repo,
    otp_app: :fun_sheep,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
```

```elixir
# config/runtime.exs
config :fun_sheep, FunSheep.RepoRead,
  url: System.get_env("DATABASE_READ_URL") || System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("READ_POOL_SIZE") || "5")
```

**Queries to move to RepoRead (high-impact):**
- `Assessments.get_schedule_state/2`
- `Assessments.cohort_percentiles/1`
- `Courses.list_courses/1`
- `Leaderboard` queries
- `Questions.list_by_schedule/2`

**Deliverables:**
- [ ] Create Cloud SQL read replica
- [ ] Add `FunSheep.RepoRead` module
- [ ] Update `DATABASE_READ_URL` env var in deploy script
- [ ] Migrate read-heavy context functions to use `RepoRead`
- [ ] Monitor replication lag (alert if > 5 seconds)

### 3c. Health Check — Database Connectivity

**Problem:** `/health` returns `{"status":"ok"}` even when the database is unreachable. Cloud Run cannot detect sick instances.

**Fix:**

```elixir
# lib/fun_sheep_web/controllers/health_controller.ex
def index(conn, _params) do
  case Ecto.Adapters.SQL.query(FunSheep.Repo, "SELECT 1", []) do
    {:ok, _} -> json(conn, %{status: "ok"})
    {:error, _} -> conn |> put_status(503) |> json(%{status: "degraded", reason: "db"})
  end
end
```

**Deliverables:**
- [ ] Update `HealthController` to check DB connectivity
- [ ] Set Cloud Run `--health-check-path=/health` explicitly
- [ ] Set `--health-check-interval=10s`, `--health-check-failure-threshold=3`

---

## 4. Phase 2 — Distributed State (Medium Priority)

**Goal:** Eliminate node-local state that causes data loss on instance failure or reconnect.

### 4a. Assessment State → Postgres (Persistent)

**Problem:** `FunSheep.Assessments.StateCache` stores active assessment sessions in ETS with a 2-hour TTL. If the instance crashes or the user reconnects to a different node, the session is gone.

**Fix:** Replace ETS cache with a Postgres-backed session table. Use the existing `assessments` schema or add a lightweight `assessment_sessions` table.

```sql
CREATE TABLE assessment_sessions (
  id bigserial PRIMARY KEY,
  user_role_id bigint NOT NULL REFERENCES user_roles(id),
  schedule_id bigint NOT NULL REFERENCES test_schedules(id),
  state jsonb NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '2 hours'
);
CREATE UNIQUE INDEX ON assessment_sessions (user_role_id, schedule_id);
CREATE INDEX ON assessment_sessions (expires_at);
```

ETS for hot-path reads remains as a write-through cache (read ETS → if miss, read Postgres → write ETS):

```elixir
def get_state(user_role_id, schedule_id) do
  case :ets.lookup(@table, {user_role_id, schedule_id}) do
    [{_, state}] -> {:ok, state}
    [] -> load_from_db(user_role_id, schedule_id)
  end
end
```

**Deliverables:**
- [ ] Migration: `assessment_sessions` table
- [ ] Update `StateCache` to write-through to Postgres
- [ ] Periodic sweeper clears expired rows (extend `StuckValidationSweeperWorker`)
- [ ] Load test: kill one instance mid-session, verify user can resume on another node

### 4b. Tutor Session Registry → Horde (Cluster-Aware)

**Problem:** `FunSheep.Tutor.SessionRegistry` is a local `Registry`. If the instance running a tutor session crashes, the session is orphaned. The browser reconnects to a different node, which has no record of the session.

**Fix:** Replace with `Horde.Registry` + `Horde.DynamicSupervisor` for cluster-wide process distribution.

**Dependencies to add (mix.exs):**
```elixir
{:horde, "~> 0.9"}
```

**Implementation sketch:**
```elixir
# Replace:
{Registry, keys: :unique, name: FunSheep.Tutor.SessionRegistry}

# With:
{Horde.Registry, name: FunSheep.Tutor.SessionRegistry, keys: :unique, members: :auto},
{Horde.DynamicSupervisor, name: FunSheep.Tutor.SessionSupervisor, strategy: :one_for_one, members: :auto}
```

Process lookups remain identical (`Horde.Registry` implements the same `Registry` API). Horde rebalances processes across nodes on join/leave.

**Deliverables:**
- [ ] Add `horde` dependency
- [ ] Replace `Registry` with `Horde.Registry` in `application.ex`
- [ ] Replace `DynamicSupervisor` (if used) with `Horde.DynamicSupervisor`
- [ ] Test: two-node cluster, kill node A, verify tutor session migrates to node B

### 4c. Redis — Shared Cache Layer

**Problem:** Cohort percentile calculations, rate-limit counters, and session hints are computed per-instance. With 5+ instances, this is wasteful and inconsistent.

**Service:** Cloud Memorystore (Redis) — managed, private VPC, no auth overhead.

**Use cases:**

| Data | TTL | Current location |
|------|-----|-----------------|
| Cohort percentile bands | 1 hour | ETS (per-instance) |
| Rate-limit counters (LLM, Vision API) | 1 minute | None (unmanaged) |
| Course metadata | 24 hours | None (DB every time) |
| Push token lookup | 1 hour | None (DB every time) |

**Library:** `Redix` (lightweight Redis client for Elixir).

```elixir
# mix.exs
{:redix, "~> 1.5"}
```

**Config:**
```elixir
# config/runtime.exs
config :fun_sheep, :redis_url, System.get_env("REDIS_URL")
```

**Deliverables:**
- [ ] Provision Cloud Memorystore Redis instance (1 GB, same VPC as Cloud Run)
- [ ] Add `REDIS_URL` to all Cloud Run services
- [ ] Add `Redix` to `mix.exs` and start in `application.ex`
- [ ] Migrate cohort percentile cache to Redis
- [ ] Add rate-limit counter module using Redis `INCR` + `EXPIRE`
- [ ] Apply rate-limit counters to Anthropic + Vision API clients

---

## 5. Phase 3 — Static Asset CDN (Quick Win)

**Goal:** Stop Phoenix from serving static assets under load. Offload to a global CDN.

### Option A — Cloud CDN (Simplest)

Enable Cloud CDN on the Cloud Run service's load balancer. Zero code changes.

- Google manages edge caching globally
- Static assets (CSS, JS, images) cached at the edge after first request
- `cache_manifest.json` already provides content-addressable URLs (cache-busting is built in)
- Cost: ~$0.008/GB served from cache

**Steps:**
1. Expose Cloud Run behind a Google Cloud Load Balancer (HTTPS)
2. Enable Cloud CDN on the backend service
3. Set `Cache-Control: public, max-age=31536000, immutable` for `/assets/*` in `endpoint.ex`

**Endpoint change:**
```elixir
# lib/fun_sheep_web/endpoint.ex
plug Plug.Static,
  at: "/assets",
  from: :fun_sheep,
  gzip: true,
  headers: %{"cache-control" => "public, max-age=31536000, immutable"}
```

### Option B — GCS + Cloud CDN (Best for high scale)

Upload `priv/static/assets/` to a GCS bucket during deploy. Serve via Cloud CDN-backed GCS URL. Phoenix never touches asset traffic.

**Deploy script addition:**
```bash
gsutil -m rsync -r -c priv/static/assets gs://$ASSETS_BUCKET/assets/
```

**Endpoint change:** Remove `Plug.Static` for assets; point `<script src>` / `<link href>` at `https://cdn.funsheep.com/assets/...`.

**Deliverables (Option A first, Option B later):**
- [ ] Option A: Enable Cloud CDN on Cloud Run load balancer
- [ ] Set `Cache-Control: immutable` headers for `/assets/*`
- [ ] Verify cache hit rate in Cloud CDN dashboard after 24h
- [ ] Option B (Phase 4): GCS asset bucket + CDN for zero Phoenix asset traffic

---

## 6. Phase 4 — Worker Auto-Scaling

**Goal:** Worker instances scale with queue depth, not a fixed 2–5 ceiling.

**Problem:** Workers are deployed with `min-instances=2 max-instances=5`. If 50 PDF OCR jobs arrive simultaneously, you're stuck at 5 instances with 3 concurrent OCR slots each = 15 concurrent — and the queue backs up.

### Option A — Cloud Run scaling by queue depth (custom metric)

1. Export Oban queue depth as a custom Cloud Monitoring metric from the worker
2. Configure Cloud Run to scale on that metric

**Oban depth export (Telemetry):**
```elixir
:telemetry.attach("oban-queue-depth", [:oban, :queue, :depth], fn _, measurements, meta, _ ->
  GoogleCloud.Monitoring.write_metric("oban_queue_depth", measurements.count, %{queue: meta.queue})
end, nil)
```

### Option B — Separate Cloud Run service per high-volume queue

Split the monolithic worker into queue-specific services:

| Service | Queues | Scale policy |
|---------|--------|-------------|
| `funsheep-worker-ocr` | ocr, pdf_ocr | Scale on queue depth |
| `funsheep-worker-ai` | ai, ai_validation | Scale on queue depth |
| `funsheep-worker-default` | default, notifications, ingest, integrations, ebook, course_setup | Fixed 1–2 |

Each service sets `RUN_OBAN_WORKERS=ocr,pdf_ocr` etc. to activate only its queues.

**Deliverables:**
- [ ] Export Oban queue depth as Cloud Monitoring custom metric
- [ ] Configure Cloud Run scaling policy on queue depth metric
- [ ] (Phase 5) Split worker into queue-specific services for independent scaling

---

## 7. Phase 5 — Observability

Before scaling further, add visibility so bottlenecks are caught before users notice them.

### Metrics to track

| Metric | Alert threshold | Tool |
|--------|----------------|------|
| DB connection pool saturation | > 80% | Telemetry → Cloud Monitoring |
| Oban queue depth per queue | > 50 jobs | Oban telemetry |
| Redis hit rate | < 80% | Redix instrumentation |
| Cloud SQL CPU | > 70% | Cloud Monitoring (built-in) |
| Cloud SQL replication lag | > 5s | Cloud Monitoring |
| API p99 latency | > 2s | Cloud Run built-in |
| Worker job failure rate | > 5% | Oban.Telemetry |
| External API error rate | > 2% | Req telemetry |

### APM

Add `opentelemetry` + `opentelemetry_exporter` (OTLP to Cloud Trace or Honeycomb):

```elixir
# mix.exs
{:opentelemetry, "~> 1.4"},
{:opentelemetry_exporter, "~> 1.8"},
{:opentelemetry_phoenix, "~> 2.0"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_oban, "~> 1.1"}
```

**Deliverables:**
- [ ] Add OpenTelemetry libraries
- [ ] Export traces to Cloud Trace (zero infra cost, already in GCP)
- [ ] Add pool saturation alert (Cloud Monitoring)
- [ ] Add Oban queue depth dashboard
- [ ] Add replication lag alert

---

## 8. Implementation Order & Priorities

| # | Change | Priority | Effort | Impact |
|---|--------|----------|--------|--------|
| 1 | PgBouncer connection proxy | P0 | 1 day | Prevents crash at modest scale |
| 2 | Fix `/health` — DB check | P0 | 2 hours | Cloud Run detects sick instances |
| 3 | Read replica + `RepoRead` | P1 | 2 days | Halves primary DB write pressure |
| 4 | Assessment state → Postgres | P1 | 2 days | No data loss on instance crash |
| 5 | Cloud CDN for static assets | P1 | 4 hours | Faster load, less Phoenix bandwidth |
| 6 | Redis shared cache | P2 | 2 days | Consistent caching across instances |
| 7 | Horde for tutor registry | P2 | 2 days | Cluster-aware session management |
| 8 | Worker auto-scaling by queue depth | P2 | 3 days | Queue depth doesn't back up |
| 9 | OpenTelemetry + dashboards | P2 | 2 days | Visibility before problems become outages |
| 10 | GCS asset bucket (Option B CDN) | P3 | 1 day | Zero Phoenix asset traffic at scale |
| 11 | Per-queue worker services | P3 | 3 days | Independent OCR/AI/default scaling |

---

## 9. What Does NOT Need to Change

- **Cloud Run deployment** — already horizontally scalable, no changes needed
- **Oban job queue logic** — Postgres-backed, leader election, Lifeline all work at scale
- **Cookie-based sessions** — stateless, scales to any number of instances
- **DNS clustering** — peer discovery works, no changes needed for Horde (it uses `members: :auto`)
- **Feature flags (FunWithFlags)** — Postgres LISTEN/NOTIFY sync already cluster-aware
- **LiveView WebSocket** — handles reconnect gracefully once assessment state is in Postgres

---

## 10. Open Questions

1. **Cloud SQL tier for read replica:** Standard or Enterprise Plus? Enterprise Plus includes built-in connection pooling (could replace PgBouncer).
2. **Redis size:** 1 GB is sufficient for cohort cache + rate counters at current scale. Revisit at 10k DAU.
3. **PgBouncer mode:** Transaction mode is required for Oban (prepared statements must be disabled). Confirm `prepare: :unnamed` in Ecto config.
4. **Horde quorum:** With 2-node cluster (minimum for workers), Horde needs careful quorum config to avoid split-brain. Test failover with 2 and 3 nodes.
5. **CDN and LiveView:** LiveView WebSocket connections cannot be CDN-cached. CDN only applies to static assets and non-WebSocket HTTP. Confirm CDN rules exclude `/live/*` and `/socket/*` paths.

---

*Last updated: 2026-04-26*
