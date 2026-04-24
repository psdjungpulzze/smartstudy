# FunSheep Admin Section — Build-Out Plan

> **How to use this file:** open a fresh Claude Code session inside
> `/home/pulzze/Documents/GitHub/personal/funsheep/` and paste this entire
> file as your first user message. It is self-contained — every file path,
> route, API endpoint, schema reference, and acceptance criterion is here.
>
> Implement in the order shown (Phase 1 → 4). Each phase is shippable on its
> own. **Do not** ship Phase 4 features until Phase 1 is in production.

---

## 0. Why this exists

FunSheep already has a minimal admin surface — `/admin` with users, courses,
materials, question review, audit log, MFA, and Oban Web at `/admin/jobs`.
What's missing is **operational visibility** (where is the system burning
money, where are jobs failing, what's the per-user story) and **lifecycle
management for things FunSheep delegates to Interactor** (agents, workflows,
credentials, billing).

This plan covers both. It also gives clear "build here" vs. "deep-link to
Interactor console" decisions for each surface, so the admin section stays
focused instead of trying to re-implement the Interactor console.

---

## 1. Architectural principles

These are non-negotiable for every page in this plan:

1. **Audit-first.** Every privileged action goes through
   `FunSheep.Admin.record/1` (`lib/fun_sheep/admin.ex:34`). No exceptions.
2. **Read-side queries live in the FunSheep DB when possible.** Don't poll
   Interactor from page load — derive state from local tables (`ai_calls`,
   `oban_jobs`, etc.) and refresh from Interactor on user demand.
3. **No new permissions model.** Auth is the existing
   `FunSheepWeb.LiveHelpers.require_admin` on-mount hook + the `:admin` role
   in `user_roles`. Don't introduce sub-roles unless a phase requires it
   (none here do).
4. **Reuse the Interactor design system.** All UI uses the patterns already
   in `lib/fun_sheep_web/live/admin_*.ex`: `bg-white rounded-2xl shadow-md`
   cards, `#4CD964` primary green, pill-shaped buttons, `text-[#1C1C1E]`
   headings, `text-[#8E8E93]` labels. See `.claude/rules/i/ui-design.md`.
5. **Honest failure.** When Interactor or any external service is
   unreachable, show the error directly. Never fall back to fake data.
   See `CLAUDE.md` "ABSOLUTE RULE" section.
6. **Deep-link, don't duplicate.** For features Interactor's own console
   handles well (workflow definition editor, OAuth client config, learned
   semantic mappings), open `https://console.interactor.com/...` in a new
   tab rather than rebuilding the UI.
7. **Local fixtures for tests.** Every Interactor API call must be wrapped
   in a behaviour or use a configurable HTTP client so tests can stub
   without hitting the network.

---

## 2. Inventory: what exists today

### 2.1 Existing admin LiveViews (DO NOT rebuild)

| Page | Route | File | Owns |
|---|---|---|---|
| Dashboard | `/admin` | `lib/fun_sheep_web/live/admin_dashboard_live.ex` | User counts by role, course total, flagged questions, last 10 audit log entries, link cards to subsections |
| Users | `/admin/users` | `lib/fun_sheep_web/live/admin_users_live.ex` | Paginated list (25/page), search by email/name, filter by role, suspend/unsuspend, promote/demote, impersonate |
| Courses | `/admin/courses` | `lib/fun_sheep_web/live/admin_courses_live.ex` | Paginated list, search, processing status, question count, delete |
| Materials | `/admin/materials` | `lib/fun_sheep_web/live/admin_materials_live.ex` | Paginated list, search by filename, filter by OCR status, re-run OCR, delete |
| Question Review | `/admin/questions/review` | `lib/fun_sheep_web/live/admin_question_review_live.ex` | Validator queue, approve / edit & approve / reject |
| Audit Log | `/admin/audit-log` | `lib/fun_sheep_web/live/admin_audit_log_live.ex` | Paginated read-only feed, 50/page |
| MFA Settings | `/admin/settings/mfa` | `lib/fun_sheep_web/live/admin_mfa_settings_live.ex` | Per-admin TOTP enrollment |
| Oban Web | `/admin/jobs` | mounted in `router.ex:158-162` | Queues, jobs, retries, dead-letter |

### 2.2 Auth model (DO NOT change)

- Admin-ness = Interactor profile `metadata.role == "admin"` AND a local
  `user_roles` row with `role: :admin`.
- LiveView guard: `FunSheepWeb.LiveHelpers.require_admin/2` (`lib/fun_sheep_web/live/live_helpers.ex:60-80`)
  raises `NotFoundError` (404) for non-admins — security by obscurity.
- Plug guard for non-LiveView routes: `FunSheepWeb.Plugs.RequireAdmin`
  (`lib/fun_sheep_web/plugs/require_admin.ex:11-17`).
- Suspension: `suspended_at` on `user_roles` blocks login.
- Impersonation: 30 min TTL via `FunSheep.Admin.start_impersonation/2`
  (`lib/fun_sheep/admin.ex:193`). Audit-logged.
- Bootstrap admin: `mix funsheep.admin.grant --user-id <id>` in
  `lib/mix/tasks/funsheep.admin.grant.ex`.

### 2.3 Existing query helpers to reuse

| Function | File:line | Use |
|---|---|---|
| `Admin.record/1` | `lib/fun_sheep/admin.ex:34` | Write audit log row — call after every mutation |
| `Admin.list_audit_logs/1` | `lib/fun_sheep/admin.ex:51` | Paginated audit feed |
| `Accounts.list_users_for_admin/1` | `lib/fun_sheep/accounts.ex:267` | Paginated users with search/role filter |
| `Accounts.count_users_by_role/0` | `lib/fun_sheep/accounts.ex:285` | Map of `%{role => count}` |
| `Courses.list_courses_for_admin/1` | `lib/fun_sheep/courses.ex:25` | Paginated courses, preloaded school + creator |
| `Content.list_materials_for_admin/1` | `lib/fun_sheep/content.ex` (~line 40) | Paginated materials with status filter |
| `Questions.count_questions_needing_review/0` | `lib/fun_sheep/questions.ex` | Validator queue count |
| `AIUsage.log_call/1` | `lib/fun_sheep/ai_usage.ex:35` | (Already wired into `Agents.chat/3`) |

### 2.4 Telemetry already in place

- `ai_calls` table — every Interactor call logged. Columns: `provider`,
  `model`, `assistant_name`, `source` (call-site label), `prompt_tokens`,
  `completion_tokens`, `total_tokens`, `token_source` (`"interactor"` |
  `"estimated"`), `env`, `duration_ms`, `status` (`"ok"` | `"error"` |
  `"timeout"`), `error`, `metadata` (jsonb), `inserted_at`.
- Indexes: `inserted_at`, `(provider, inserted_at)`, `(source, inserted_at)`,
  `(env, inserted_at)`.
- `lib/fun_sheep_web/telemetry.ex` — Phoenix request times, DB query times,
  VM metrics. `periodic_measurements/0` is empty — extend in Phase 3.
- `admin_audit_logs` table — every admin mutation logged.

### 2.5 Workers (visible via Oban Web; FunSheep-domain wrapper missing)

| Worker | Queue | Purpose |
|---|---|---|
| `AIQuestionGenerationWorker` | `ai` | Generate questions via Interactor agent |
| `CourseDiscoveryWorker` | `default` | Initial chapter/topic discovery (capped at 8-20 chapters — fixed in PR #17) |
| `EnrichCourseWorker` | `default` | Manual enrichment trigger |
| `EnrichDiscoveryWorker` | `default` | Re-discover from OCR text |
| `IngestWorker` | `ingest` | Bulk document upload pipeline |
| `MaterialRelevanceWorker` | `default` | Score material vs course subject |
| `OCRMaterialWorker` | `ocr` | Per-material OCR orchestrator |
| `PdfOcrDispatchWorker` | `pdf_ocr` | Submit PDF chunks to Google Vision |
| `PdfOcrPollerWorker` | `pdf_ocr` | Poll Google Vision for chunk results |
| `ProcessCourseWorker` | `default` | Course-creation orchestrator |
| `QuestionExtractionWorker` | `default` | Pattern-extract questions from OCR text |
| `QuestionValidationWorker` | `default` | Validate generated/extracted questions |
| `TextbookCompletenessWorker` | `default` | Check textbook coverage of curriculum |
| `WebContentDiscoveryWorker` | `default` | Web search for sources |
| `WebQuestionScraperWorker` | `default` | Web scrape practice questions |

### 2.6 Interactor integrations (what FunSheep already calls)

| File | Purpose | Endpoints used |
|---|---|---|
| `lib/fun_sheep/interactor/auth.ex` | OAuth2 client_credentials, token caching with 120s pre-expiry refresh | `POST /oauth/token` |
| `lib/fun_sheep/interactor/agents.ex` | Chat with assistants, list/create assistants, manage rooms | `POST /agents/{id}/rooms`, `POST /rooms/{id}/messages`, `GET /rooms/{id}/messages`, `POST /rooms/{id}/close`, `GET/POST /agents/assistants` |
| `lib/fun_sheep/interactor/profiles.ex` | User personalization (grade, hobbies, learning prefs) | `GET/PUT /profiles/{user_id}`, `GET /profiles/{user_id}/effective` |
| `lib/fun_sheep/interactor/credentials.ex` | 3rd-party OAuth (Google, etc.) | `POST /oauth/initiate`, `GET /credentials/{user_id}`, `GET /credentials/{id}/token` |
| `lib/fun_sheep/interactor/billing.ex` | Subscriptions, invoices, payments, usage limits | Full Billing Server client (~411 lines) |
| `lib/fun_sheep/interactor/workflows.ex` | (Defined; not currently called) | `POST /workflows`, `POST /instances`, etc. |
| `lib/fun_sheep/interactor/webhooks.ex` | Webhook signature verification | `POST /webhooks`, HMAC-SHA256 |

---

## 3. The plan: 4 phases

```
Phase 1 — Operational visibility (cost + jobs)        ~3-4 days
  ├─ /admin/usage/ai           AI token usage dashboard
  └─ /admin/jobs/failures      Job failure drill-down (FunSheep-domain)

Phase 2 — User & subscription depth                   ~3-4 days
  ├─ /admin/users/:id          Per-user profile + activity timeline
  └─ /admin/billing            Subscription health from Billing Server

Phase 3 — Interactor surface                          ~3-4 days
  ├─ /admin/interactor/agents  Agent registry + force-update flow
  ├─ /admin/interactor/credentials  Per-user OAuth status
  └─ /admin/interactor/profiles     Per-user personalization debugger

Phase 4 — Schools, flags, ops                         ~2-3 days
  ├─ /admin/geo                Schools/districts CRUD
  ├─ /admin/flags              Feature flags & kill switches
  └─ /admin/health             System health + maintenance mode
```

Phases are independent of each other. Ship each as its own PR.

---

## Phase 1 — Operational visibility

### 1.1 `/admin/usage/ai` — AI token usage dashboard

**Goal:** Answer "where is my OpenAI bill going?" in one page.

**Data source:** `ai_calls` table (already populated). No new Interactor
calls required.

**Sub-pages / sections:**

1. **Time-window picker** (top of page, sticky)
   - Buttons: 1h | 24h | 7d | 30d | custom (datetime-local pair)
   - Default: 24h
   - Filter chips next to it: env (prod/dev/test/all), provider (openai /
     anthropic / google / interactor / unknown / all), status (ok / error /
     timeout / all)
   - Persist filter choices in URL params so admins can share links

2. **Summary cards** (grid-cols-2 md:grid-cols-5)
   - Total calls (current window) + delta % vs prior window of same length
   - Total tokens (sum of `total_tokens`)
   - Estimated cost (USD) — see Pricing module below
   - Error rate (errors / total) with red highlight if > 5%
   - p50 / p95 latency (`duration_ms` percentiles)

3. **Time series** (full width, 240px tall)
   - Bucket: hour for ≤24h windows, day for ≤7d, week for >7d
   - Two stacked series: prompt_tokens, completion_tokens
   - Implementation: SVG path inline, no chart library. Pre-compute buckets
     server-side. Hover tooltip via `phx-hook` showing exact value.

4. **By assistant** (table)
   - Columns: assistant_name | calls | tokens (prompt / completion / total)
     | est. cost | avg ms | p95 ms | error count | last seen
   - Sort by total tokens desc. Click row → drill into recent calls (filter
     applied).

5. **By source** (table) — same columns as #4 but grouped on `source`
   (worker name or LiveView module). Identifies which call-site is
   spending the most.

6. **By model** (table) — same shape but grouped on `model`. Useful after
   downgrading a model to see cost drop.

7. **Recent errors** (table, last 25)
   - Columns: when | assistant | source | error (first 80 chars) | duration
   - Click row → opens detail drawer (see #9)

8. **Top 25 most expensive single calls** (table)
   - Columns: when | assistant | source | total_tokens | est. cost | model
   - Useful for catching outliers (e.g., a 50k-token validator batch)

9. **Detail drawer** (slide-in from right, 480px, dismissible)
   - Triggered by clicking any call row
   - Shows: full timestamp, all columns of `ai_calls`, full error message,
     pretty-printed `metadata` jsonb, "Copy as JSON" button

**Files to create:**

```
lib/fun_sheep/ai_usage.ex                       — extend with query functions
lib/fun_sheep/ai_usage/pricing.ex               — model → $ table
lib/fun_sheep_web/live/admin_ai_usage_live.ex   — the LiveView
test/fun_sheep/ai_usage_test.exs                — extend with new query tests
test/fun_sheep_web/live/admin_ai_usage_live_test.exs — LiveView mount/filter tests
```

**Files to modify:**

```
lib/fun_sheep_web/router.ex                     — add route under :admin live_session
lib/fun_sheep_web/live/admin_dashboard_live.ex  — add link card
```

**`AIUsage` query functions to add** (all take a `filters` map):

```elixir
@type filters :: %{
  optional(:since)          => DateTime.t(),
  optional(:until)          => DateTime.t(),
  optional(:env)            => String.t() | [String.t()] | :any,
  optional(:provider)       => String.t() | [String.t()] | :any,
  optional(:assistant_name) => String.t() | :any,
  optional(:source)         => String.t() | :any,
  optional(:status)         => String.t() | [String.t()] | :any
}

# All return shape: %{calls, prompt_tokens, completion_tokens, total_tokens,
#                    errors, p50_ms, p95_ms, est_cost_cents}
def summary(filters)
def summary_with_delta(filters)         # also returns prior-window deltas

# Returns [%{key, calls, prompt_tokens, completion_tokens, total_tokens,
#            est_cost_cents, avg_ms, p95_ms, errors, last_seen}, ...]
def by_assistant(filters)
def by_source(filters)
def by_model(filters)

# Returns [%{bucket_at, prompt_tokens, completion_tokens}, ...]
def time_series(filters, bucket_size)   # :hour | :day | :week

# Returns [%Call{}, ...]
def recent_calls(filters, limit)
def recent_errors(filters, limit)
def top_calls(filters, limit)           # ordered by total_tokens desc

def get_call!(id)
```

**Pricing module** (`lib/fun_sheep/ai_usage/pricing.ex`):

- Module attribute map: `%{"gpt-4o" => {2_50, 10_00}, "gpt-4o-mini" => {15, 60}, ...}` where values are `{input_per_M_cents, output_per_M_cents}`.
- `cost_cents(model, prompt_tokens, completion_tokens)` returns integer
  cents, or `nil` for unknown model.
- Format helper: `format_cost_cents(cents)` → `"$1.23"` or `"—"`.
- Initial table covers: gpt-4o, gpt-4o-mini, gpt-4-turbo, claude-opus-4-5,
  claude-sonnet-4-6, claude-haiku-4-5, gemini-1.5-pro, gemini-1.5-flash.
  Source pricing from each vendor's pricing page; comment with date checked.

**Acceptance criteria:**
- [ ] Page loads in < 500 ms with 100k rows in `ai_calls` (verify with
      `EXPLAIN ANALYZE` on each query)
- [ ] All filter combinations work and survive URL share/refresh
- [ ] Time-series chart renders SVG, no JS chart lib added to deps
- [ ] Cost shows `$X.XX` for known models, `—` for unknown
- [ ] Detail drawer opens on row click, closes with Esc and ✕
- [ ] Audit log entry written when admin opens this page (action
      `"admin.usage.ai.view"`) — yes, **viewing** is auditable here because
      the page exposes per-user token attribution
- [ ] Card on `/admin` dashboard linking here shows "$X.XX last 24h" and
      "Y calls"

**Tests:**
- `AIUsage.summary/1` aggregates correctly across filter combinations
- `AIUsage.summary_with_delta/1` handles empty prior window (delta = nil,
  not divide-by-zero)
- `AIUsage.time_series/2` produces correct bucket boundaries
- `AIUsage.by_*` functions zero-fill missing groups
- `Pricing.cost_cents/3` returns nil for unknown model, integer for known
- LiveView mount doesn't crash with empty `ai_calls` table
- LiveView filter change updates summary cards

---

### 1.2 `/admin/jobs/failures` — FunSheep-domain job failure drill-down

**Goal:** "Why is this course stuck?" Oban Web shows raw jobs; this page
shows them with FunSheep context (course name, material name, error
category).

**Data source:** Direct query of `oban_jobs` table joined to FunSheep domain
tables based on `args` jsonb.

**Sections:**

1. **Failure summary** (cards): total in last 24h, by worker (top 5),
   by error category (extract patterns: "Interactor unavailable",
   "OCR failed", "Validation rejected all")

2. **Failed jobs table** (paginated, 50/page)
   - Columns: when | worker | args summary (course name, material name,
     etc.) | attempt #/max | error (truncated) | actions
   - Action buttons per row: "Retry" (re-enqueues), "Cancel" (marks
     discarded), "View args" (opens drawer)
   - Filter: worker, error category, age

3. **Detail drawer** — full args, full error, all attempts history

**Files to create:**

```
lib/fun_sheep/admin/jobs.ex                     — query + retry helpers
lib/fun_sheep_web/live/admin_jobs_live.ex
test/fun_sheep/admin/jobs_test.exs
test/fun_sheep_web/live/admin_jobs_live_test.exs
```

**Implementation notes:**
- Query against `Oban.Job` schema directly (Oban exposes its schema).
- For each worker class, define a `summarize_args/1` function that takes
  the `args` map and returns a human-readable line. Live in
  `lib/fun_sheep/admin/jobs.ex`. E.g., for `OCRMaterialWorker`, look up
  the material by ID and return its file name.
- "Retry" calls `Oban.retry_job/1`. Audit-log it.
- "Cancel" calls `Oban.cancel_job/1`. Audit-log it.
- Error category is regex-derived from the error message. Categories:
  `:interactor_unavailable`, `:ocr_failed`, `:validation_rejected`,
  `:rate_limited`, `:timeout`, `:other`.

**Acceptance criteria:**
- [ ] Course name visible for any worker whose args include `course_id`
- [ ] Material file name visible for any worker whose args include
      `material_id`
- [ ] Retry button works and the job appears in `available` state
- [ ] Cancel button moves the job to `cancelled` state
- [ ] Audit log entry per retry / cancel
- [ ] Page loads in < 500 ms with 10k rows in `oban_jobs`
- [ ] Card on `/admin` dashboard showing failed-jobs count (red badge if > 0)

---

## Phase 2 — User & subscription depth

### 2.1 `/admin/users/:id` — Per-user detail page

**Goal:** Single source of truth for "tell me everything about this user
without impersonating them."

The existing `/admin/users` page is already a list. This adds a click-through
detail view.

**Sections:**

1. **Header card** — avatar, display name, email, role badges, status
   (active / suspended), created date, last login (if tracked; if not,
   add field in this phase)

2. **Quick actions** (button row) — Suspend / Unsuspend, Promote / Demote,
   Impersonate, Send password reset, Force MFA reset

3. **Activity timeline** (vertical list, last 50 events)
   - Pulls from: question_attempts, test_schedules, course_creations,
     audit_logs (where target = this user)
   - Each row: when, event icon, summary line ("Completed test X",
     "Added material Y to course Z", "Was suspended by admin@...")

4. **Courses owned** (table) — name, status, question count, created at,
   link to course detail

5. **Subscription** card (Phase 2.2 source)
   - Plan name, status, current period, next renewal, MRR
   - Link to `/admin/billing/:subscription_id`

6. **AI usage (this user)** — last 30 days
   - Calls, tokens, est. cost, top assistant
   - Pulls from `ai_calls` filtered on `metadata->>'user_id' = $1`
   - Requires: ensure `Agents.chat/3` includes `user_id` in metadata
     (currently optional per `lib/fun_sheep/interactor/agents.ex`)

7. **Interactor profile** (Phase 3.3 source) — collapsible
   - Grade, hobbies, learning preference, custom instructions
   - "View / edit in Interactor" button

8. **Credentials** (Phase 3.2 source) — collapsible
   - List of connected services with status icons
   - "Manage in Interactor" button

9. **Audit trail** (where this user is target) — last 25, link to full
   audit log filtered

**Files to create:**

```
lib/fun_sheep/admin/user_detail.ex              — aggregator: combines all sources
lib/fun_sheep_web/live/admin_user_detail_live.ex
test/fun_sheep/admin/user_detail_test.exs
test/fun_sheep_web/live/admin_user_detail_live_test.exs
```

**Files to modify:**

```
lib/fun_sheep_web/router.ex                     — add `live "/users/:id"` under :admin
lib/fun_sheep_web/live/admin_users_live.ex      — make rows clickable, navigate to detail
lib/fun_sheep/accounts/user_role.ex             — add `last_login_at` field if missing
lib/fun_sheep_web/controllers/auth/...          — set last_login_at on login
priv/repo/migrations/<ts>_add_last_login_at.exs — migration
lib/fun_sheep/interactor/agents.ex              — ensure user_id flows into ai_calls metadata
```

**Acceptance criteria:**
- [ ] All 9 sections render even when corresponding data is empty (no crash
      on a brand-new user)
- [ ] Quick actions still write audit log (route through existing
      `Admin.suspend_user/2`, etc.)
- [ ] Activity timeline aggregates from at least 4 sources, deduplicated,
      sorted desc by time
- [ ] Subscription, profile, credentials sections gracefully show "Not
      available" if Interactor is unreachable (don't crash)
- [ ] Audit log entry on page view (action `"admin.user.view"`, target is
      the user) — yes, viewing is privileged because the page surfaces
      profile + credentials
- [ ] Loads in < 800 ms for typical user

**Tests:**
- Aggregator combines 4+ sources correctly
- Page works for: brand-new user, suspended user, deleted-target audit
  entries, user with 0 courses, user with subscription, user without

---

### 2.2 `/admin/billing` — Subscription health

**Goal:** Visibility into Billing Server data without leaving FunSheep
admin. **Resolve open question first:** are subscriptions stored in
FunSheep or in Billing Server? Read `lib/fun_sheep/interactor/billing.ex`
and the actual `subscriptions` table (if any) in FunSheep DB to confirm.
Adjust this phase based on the answer.

**Assumption (verify):** subscriptions live in Billing Server, accessed
via `FunSheep.Interactor.Billing` client.

**Sections:**

1. **Cards** — total active subscriptions, MRR, churn last 30d, trial
   conversions last 30d

2. **Subscriptions table** (paginated)
   - Columns: subscriber email | plan | status (active / trialing /
     past_due / cancelled) | current period end | MRR | actions
   - Filter: plan, status, search by email

3. **Detail page** `/admin/billing/:subscription_id`
   - Plan, billing period, payment method on file, invoice history
   - Actions: Change plan (dropdown), Cancel, Reinstate, Send invoice,
     "Open Stripe portal for this customer" (calls
     `Billing.create_portal_session/1`)

4. **Recent invoices** (last 50)

**Files to create:**

```
lib/fun_sheep_web/live/admin_billing_live.ex
lib/fun_sheep_web/live/admin_billing_detail_live.ex
test/fun_sheep_web/live/admin_billing_live_test.exs
```

**Implementation notes:**
- Cache Billing Server responses for 60s (use `Cachex` or a simple ETS
  GenServer) to avoid hammering it on page reloads.
- Mock-mode fallback: existing `Billing` client supports mock mode for
  dev/test. Tests use mock mode; production uses real Billing Server.
- Every mutation (change plan, cancel, reinstate) writes audit log AND
  re-fetches the subscription to confirm.

**Acceptance criteria:**
- [ ] If Billing Server is unreachable, show "Billing service unavailable"
      banner; do not crash; do not show stale data older than 5 min
- [ ] Plan change requires confirmation dialog, audit-logged
- [ ] Cancel requires reason field, audit-logged
- [ ] Stripe portal link is single-use (re-fetched each click)

---

## Phase 3 — Interactor surface

These pages are the "Interactor admin from inside FunSheep" experience.

### 3.1 `/admin/interactor/agents` — Agent registry

**Goal:** Solve the pain documented at the end of PR #17 — "validator's
`assistant_attrs` only takes effect on first-provision; you'll need to
delete and recreate the assistant or update via Interactor console to
switch from gpt-4o to gpt-4o-mini."

**Sections:**

1. **Agent list** (table)
   - Columns: name | model (Interactor) | model (intended in code) |
     status (✅ in-sync / ⚠️ drift / ❌ missing) | calls last 24h |
     error rate | last seen
   - "Intended" is the value in `assistant_attrs/0` for each FunSheep agent
     (`question_validator`, `course_discovery`, `question_gen`, `tutor`).
   - "Drift" means the live config differs from what FunSheep code expects
     (e.g., model is gpt-4o but code says gpt-4o-mini).

2. **Per-agent actions**
   - "Force re-provision" → DELETE the assistant on Interactor, re-create
     from `assistant_attrs/0`. Confirmation dialog. Audit-logged.
   - "Send test message" → opens a small form, posts to the agent, shows
     reply inline. Useful for "is the agent reachable right now?"
   - "Open in Interactor console" → deep-link to
     `https://console.interactor.com/agents/assistants/{id}`
   - "View 24h call log" → links to `/admin/usage/ai?assistant_name=...`

3. **Drift summary card** (top of page) — count of agents with config drift,
   prominent if > 0

**Files to create:**

```
lib/fun_sheep/interactor/agent_registry.ex      — list + drift detection
lib/fun_sheep_web/live/admin_interactor_agents_live.ex
test/fun_sheep/interactor/agent_registry_test.exs
test/fun_sheep_web/live/admin_interactor_agents_live_test.exs
```

**Files to modify:**

```
lib/fun_sheep/interactor/agents.ex              — add `delete_assistant/1`, `update_assistant/2` if missing
```

**Implementation notes:**
- "Intended" config is collected by introspecting modules that define
  `assistant_attrs/0`. Use a behaviour: define
  `FunSheep.Interactor.AssistantSpec` with `@callback assistant_attrs() ::
  map()`, make `Validation`, `Tutor`, etc. implement it. Then list all
  modules implementing the behaviour at runtime.
- "Force re-provision" must DELETE then re-create — Interactor's UPDATE
  endpoint doesn't support model changes (per integration docs). Wrap in a
  transaction-like flow: take a snapshot of current config to a "rollback"
  metadata field on `audit_logs` so an admin can manually revert.
- Test sending: use a deterministic prompt like
  `"Reply with the literal string 'pong' and nothing else."` — failure to
  return "pong" within 10s = ❌.

**Acceptance criteria:**
- [ ] Drift detection works: change a model in code, observe ⚠️ on the page
- [ ] Force re-provision succeeds and updates the live model (verify via
      "Send test message" returning the new model in metadata)
- [ ] Force re-provision audit log includes both old and new config snapshot
- [ ] Test message handles timeout gracefully (10s limit)
- [ ] If Interactor is unreachable, page renders the table from
      `ai_calls`-derived data and marks Interactor status as "unreachable"

---

### 3.2 `/admin/interactor/credentials` — Per-user OAuth status

**Goal:** Troubleshoot "why can't this student export to Google Drive?"

**Sections:**

1. **Credentials by user** — search box, user picker
2. **Per-user view:**
   - List of connected services with status (active / expired / revoked)
   - Per credential: scopes, last used, expires_at, refresh status
   - Actions: "Force refresh" → calls Interactor refresh endpoint;
     "Revoke" → calls DELETE; "Re-initiate OAuth" → generates initiation
     URL for support to send to the user
3. **Recent revocations** (table) — for spotting patterns ("Google
   credentials revoked en masse")

**Files to create:**

```
lib/fun_sheep_web/live/admin_interactor_credentials_live.ex
test/fun_sheep_web/live/admin_interactor_credentials_live_test.exs
```

**Files to modify:**

```
lib/fun_sheep/interactor/credentials.ex         — add `force_refresh/1`, `revoke/1` if missing
```

**Acceptance criteria:**
- [ ] Force refresh succeeds for non-revoked credentials
- [ ] All actions audit-logged
- [ ] Page loads even when user has zero credentials
- [ ] Recent revocations shows credentials revoked outside FunSheep
      (requires webhook subscription — see backlog item below)

---

### 3.3 `/admin/interactor/profiles` — Personalization debugger

**Goal:** "Why is the tutor talking to this 5th-grader like a college
student?"

**Sections:**

1. **User picker** — search by email
2. **Profile editor** — display the user's Interactor profile (grade,
   hobbies, learning preference, custom instructions, memory facts).
   Editable inline.
3. **Effective profile preview** — show what the agent will actually see
   when called (merged default + user + context). Lets admin verify a
   change took effect.
4. **Test with this profile** — send a test prompt to a chosen agent,
   show the reply. Useful for verifying personalization works.

**Files to create:**

```
lib/fun_sheep_web/live/admin_interactor_profiles_live.ex
test/fun_sheep_web/live/admin_interactor_profiles_live_test.exs
```

**Acceptance criteria:**
- [ ] Edits write through `Profiles.update_profile/2` and audit-log
- [ ] "Effective profile" updates after every save
- [ ] Test message uses the user's profile context

---

## Phase 4 — Schools, flags, ops

### 4.1 `/admin/geo` — Schools/districts management

**Sections:** countries, states, districts, schools — CRUD pages, bulk
import via CSV, per-school metrics (student count, course count).

**Files to create:**

```
lib/fun_sheep_web/live/admin_geo_live.ex
lib/fun_sheep_web/live/admin_geo_school_detail_live.ex
test/fun_sheep_web/live/admin_geo_live_test.exs
```

**Existing context:** `lib/fun_sheep/geo.ex`. Reuse, add admin queries.

---

### 4.2 `/admin/flags` — Feature flags & kill switches

**Goal:** Disable features without code deploy. Critical when an upstream
service (OpenAI, Google Vision) starts failing platform-wide.

**Implementation: do NOT roll your own.** Use `:fun_with_flags` library.
Persist to FunSheep DB. Provide an admin UI for it.

**Initial flags to define:**
- `ai_question_generation_enabled` — kill switch for the
  `AIQuestionGenerationWorker`. When off, courses still process but
  question generation is skipped.
- `ocr_enabled` — kill switch for `OCRMaterialWorker`. When off, uploads
  queue but don't process.
- `interactor_calls_enabled` — global Interactor circuit breaker.
- `course_creation_enabled` — block new course creation during incidents.
- `signup_enabled` — close registration without taking the site down.

**Files to create:**

```
lib/fun_sheep/feature_flags.ex                  — thin wrapper over :fun_with_flags
lib/fun_sheep_web/live/admin_flags_live.ex
test/fun_sheep/feature_flags_test.exs
```

**Files to modify:** every worker named above to short-circuit when its
flag is off, returning `{:cancel, "feature_flag_disabled"}` from
`perform/1`.

**Acceptance criteria:**
- [ ] Toggling a flag takes effect within 1 second (no app restart)
- [ ] All toggles audit-logged
- [ ] Workers gated by flags log a clear message when disabled

---

### 4.3 `/admin/health` — System health + maintenance mode

**Sections:**

1. **Service status grid**
   - Postgres: connection pool size, slow queries
   - Oban: queue depths, workers running, dead letters
   - Interactor: latest call status from `ai_calls`, plus an active health
     ping
   - Google Vision: success rate from `ocr_pages` last hour
   - Email (Mailer): success rate
2. **Maintenance mode toggle** — when ON, all non-admin routes return
   503 with a message. Admin routes still work.
3. **Periodic measurements panel** — graphs for the last 24h of:
   request rate, p95 latency, error rate, ai_calls/hour. Source from
   `lib/fun_sheep_web/telemetry.ex` once `periodic_measurements/0` is
   wired (see file:line 86 — currently empty).

**Files to create:**

```
lib/fun_sheep/admin/health.ex                   — service ping helpers
lib/fun_sheep_web/live/admin_health_live.ex
lib/fun_sheep_web/plugs/maintenance_mode.ex     — 503 plug
test/fun_sheep_web/plugs/maintenance_mode_test.exs
```

**Files to modify:**

```
lib/fun_sheep_web/endpoint.ex                   — insert MaintenanceMode plug before router
lib/fun_sheep_web/telemetry.ex                  — populate periodic_measurements/0
lib/fun_sheep/feature_flags.ex                  — add `maintenance_mode` flag
```

---

## 4. Cross-cutting changes (apply across all phases)

### 4.1 Update `/admin` dashboard

Each phase adds a card to the dashboard. By the end of Phase 4, the
dashboard should have these cards (in addition to existing):

```
[AI usage 24h]      [Job failures]     [Subscriptions]
$X.XX last 24h      Y failed           Z active

[Schools]           [Feature flags]    [System health]
N schools           K toggled off      All systems ✅
```

Modify `lib/fun_sheep_web/live/admin_dashboard_live.ex` `render/1` to add
each card. Preload counts in `mount/3` via parallel `Task.async_stream`
to keep page-load latency flat.

### 4.2 Sidebar navigation

Currently `/admin/*` pages have no sidebar. Add one:

```
lib/fun_sheep_web/components/admin_sidebar.ex   — new shared component
```

Embed in every admin LiveView. Sections:
- Overview (`/admin`)
- Users (`/admin/users`)
- Courses (`/admin/courses`)
- Materials (`/admin/materials`)
- Question review (`/admin/questions/review`)
- Billing (`/admin/billing`) [Phase 2]
- Schools (`/admin/geo`) [Phase 4]
- ─── Operations ───
- AI usage (`/admin/usage/ai`) [Phase 1]
- Job failures (`/admin/jobs/failures`) [Phase 1]
- Background jobs (`/admin/jobs`) — Oban Web link
- System health (`/admin/health`) [Phase 4]
- Feature flags (`/admin/flags`) [Phase 4]
- ─── Interactor ───
- Agents (`/admin/interactor/agents`) [Phase 3]
- Credentials (`/admin/interactor/credentials`) [Phase 3]
- Profiles (`/admin/interactor/profiles`) [Phase 3]
- Audit log (`/admin/audit-log`)
- MFA (`/admin/settings/mfa`)

Active section highlighted with `bg-[#E8F8EB] text-[#3DBF55]`.

### 4.3 Add `:source` discipline to every Interactor call site

Currently `Agents.chat/3` accepts a `:source` opt that defaults to the
assistant name. For the dashboard to show meaningful "By source" data,
every call site should pass an explicit source. Audit pass:

```
grep -rn "Agents.chat(" lib/
```

For each call site, add `source: "<worker_name_or_module>"` to opts.
Examples: `"course_discovery_worker"`, `"question_validation_worker"`,
`"tutor_live"`, `"course_detail_live"`.

### 4.4 Webhook subscription for credential events

Phase 3.2 needs `credential.revoked` events. Subscribe at app boot:

```
lib/fun_sheep/application.ex                    — call Webhooks.subscribe(...) once
lib/fun_sheep_web/controllers/webhook_controller.ex — receive + verify + record
priv/repo/migrations/<ts>_create_credential_events.exs — store events
```

(This may already exist; check `lib/fun_sheep/interactor/webhooks.ex`
usage before building.)

---

## 5. What NOT to build

These belong in Interactor's own console — link out, don't rebuild:

- **OAuth client app management** — platform-level, not consumer-app-level
- **Org / app hierarchy management** — Interactor owns this
- **Workflow definition editor** — visual state-machine editor is an
  Interactor product. Surface workflow *instances* in FunSheep admin
  (Phase 3 backlog), but don't rebuild the editor.
- **Learned semantic mappings curation** — niche, console handles it
- **Service knowledge base** — reference data, not for FunSheep admin
- **JWKS / token issuance** — backend security, no UI

For each, where the page would belong, render a small card with text:
"Managed in Interactor console" + button "Open Interactor console" →
`https://console.interactor.com/...`

---

## 6. Non-functional requirements

Apply to every page in this plan:

- **Performance:** Each page initial render < 800 ms server-side. Use
  `EXPLAIN ANALYZE` on every new query; add indexes if a query hits >
  100ms on representative data.
- **Pagination:** Default 25 or 50 per page. Cursor-based for tables that
  can exceed 10k rows (audit log, ai_calls). Offset is fine elsewhere.
- **Empty states:** Every list/table renders a friendly empty state
  message. Never a blank box.
- **Error boundaries:** Catch Interactor / Billing / external service
  failures at the LiveView level, render an inline banner ("Service
  temporarily unavailable") instead of crashing.
- **Audit logging:** Every mutation, every page view that exposes
  per-user PII (user detail, profiles, credentials, ai-usage), every
  "force" action.
- **Tests:** Unit tests for every new query function. LiveView mount
  test for every new page. Integration test for at least one mutation
  path per page.
- **Visual verification:** After each phase ships, run the
  `visual-tester` agent on every new page (see
  `.claude/rules/i/visual-testing.md`).

---

## 7. Sequencing & dependencies

```
Phase 1.1 (AI usage)   — depends on nothing new
Phase 1.2 (Job failures) — depends on nothing new

Phase 2.1 (User detail) — depends on Phase 1.1 (uses ai_calls per-user)
                         AND change 4.3 (source discipline)
Phase 2.2 (Billing)     — depends on resolving "where do subscriptions live?" question

Phase 3.1 (Agents)      — depends on Interactor `delete_assistant`/`update_assistant` working
Phase 3.2 (Credentials) — depends on cross-cutting 4.4 (webhook subscription)
Phase 3.3 (Profiles)    — no new deps

Phase 4.1 (Geo)         — no new deps
Phase 4.2 (Flags)       — adding `:fun_with_flags` dependency
Phase 4.3 (Health)      — depends on populating telemetry periodic_measurements
```

Recommended ship order:
1. Phase 1.1
2. Cross-cutting 4.3 (source discipline)
3. Phase 1.2
4. Phase 2.1
5. Phase 4.2 (flags) — defensive, ship before going further
6. Phase 3.1
7. Phase 3.3
8. Phase 4.4 → Phase 3.2
9. Phase 2.2 (after billing scope question is answered)
10. Phase 4.1 + 4.3

Each step is a separate PR off `main` (NOT off `chore/north-star-rebuild`,
which has unrelated WIP — see memory entry).

---

## 8. Open questions to resolve before starting Phase 2

These came out of the Interactor research and need product/team answers:

1. **Where do FunSheep subscriptions live?** Local DB or Billing Server?
   Read `lib/fun_sheep/interactor/billing.ex` calls AND check FunSheep DB
   for any `subscriptions`-like table. If both exist, which is source of
   truth?
2. **Does FunSheep currently subscribe to any Interactor webhooks?** Search
   for `Webhooks.subscribe` or webhook controller route. If no, we need
   to add subscription for Phase 3.2 credential drift detection.
3. **What is the FunSheep admin's Interactor permissions level?** Can a
   FunSheep admin actually call `DELETE /api/v1/agents/assistants/{id}`,
   or are they read-only on Interactor's side? If read-only, Phase 3.1
   "force re-provision" needs a different approach (e.g., flag the agent
   as "needs ops attention" and require an Interactor admin to act).
4. **Is `https://console.interactor.com` the right deep-link host?**
   Confirm the production URL pattern; some deep-links assume this.

Don't block Phase 1 on these. Phase 1 has no Interactor dependencies.

---

## 9. Rejected ideas

For traceability, ideas considered and dropped:

- **LiveDashboard at `/admin/dashboard-phx`** — already available in dev
  via `/dev/live-dashboard`. Mounting in prod adds attack surface for
  little benefit; the bespoke `/admin/health` page (Phase 4) gives
  curated metrics instead.
- **Email template editor** — out of scope; templates are few and
  versioning them in code is fine for now.
- **API key / programmatic admin access** — premature; build when there's
  a concrete consumer.
- **Real-time SSE workflow viewer** — Interactor console handles this
  better; deep-link instead.
- **Per-school feature flags** — `:fun_with_flags` supports actor-scoped
  flags; if needed later, add a "school" actor type. Don't build until
  asked.

---

## 10. Quick reference: file map

Files this plan creates (in implementation order):

```
# Phase 1.1
lib/fun_sheep/ai_usage/pricing.ex
lib/fun_sheep_web/live/admin_ai_usage_live.ex
test/fun_sheep_web/live/admin_ai_usage_live_test.exs
# (extends lib/fun_sheep/ai_usage.ex and test/fun_sheep/ai_usage_test.exs)

# Phase 1.2
lib/fun_sheep/admin/jobs.ex
lib/fun_sheep_web/live/admin_jobs_live.ex
test/fun_sheep/admin/jobs_test.exs
test/fun_sheep_web/live/admin_jobs_live_test.exs

# Phase 2.1
lib/fun_sheep/admin/user_detail.ex
lib/fun_sheep_web/live/admin_user_detail_live.ex
test/fun_sheep/admin/user_detail_test.exs
test/fun_sheep_web/live/admin_user_detail_live_test.exs
priv/repo/migrations/<ts>_add_last_login_at_to_user_roles.exs

# Phase 2.2
lib/fun_sheep_web/live/admin_billing_live.ex
lib/fun_sheep_web/live/admin_billing_detail_live.ex
test/fun_sheep_web/live/admin_billing_live_test.exs

# Phase 3.1
lib/fun_sheep/interactor/agent_registry.ex
lib/fun_sheep/interactor/assistant_spec.ex     (behaviour)
lib/fun_sheep_web/live/admin_interactor_agents_live.ex
test/fun_sheep/interactor/agent_registry_test.exs
test/fun_sheep_web/live/admin_interactor_agents_live_test.exs

# Phase 3.2
lib/fun_sheep_web/live/admin_interactor_credentials_live.ex
test/fun_sheep_web/live/admin_interactor_credentials_live_test.exs
priv/repo/migrations/<ts>_create_credential_events.exs

# Phase 3.3
lib/fun_sheep_web/live/admin_interactor_profiles_live.ex
test/fun_sheep_web/live/admin_interactor_profiles_live_test.exs

# Phase 4.1
lib/fun_sheep_web/live/admin_geo_live.ex
lib/fun_sheep_web/live/admin_geo_school_detail_live.ex
test/fun_sheep_web/live/admin_geo_live_test.exs

# Phase 4.2
lib/fun_sheep/feature_flags.ex
lib/fun_sheep_web/live/admin_flags_live.ex
test/fun_sheep/feature_flags_test.exs

# Phase 4.3
lib/fun_sheep/admin/health.ex
lib/fun_sheep_web/live/admin_health_live.ex
lib/fun_sheep_web/plugs/maintenance_mode.ex
test/fun_sheep_web/plugs/maintenance_mode_test.exs

# Cross-cutting 4.2
lib/fun_sheep_web/components/admin_sidebar.ex
```

Files this plan modifies:

```
lib/fun_sheep_web/router.ex                     — every phase adds routes
lib/fun_sheep_web/live/admin_dashboard_live.ex  — every phase adds a card
lib/fun_sheep/ai_usage.ex                       — Phase 1.1 adds query fns
lib/fun_sheep/interactor/agents.ex              — Phase 3.1 adds delete/update
lib/fun_sheep/interactor/credentials.ex         — Phase 3.2 adds force_refresh/revoke
lib/fun_sheep/accounts/user_role.ex             — Phase 2.1 adds last_login_at
lib/fun_sheep_web/telemetry.ex                  — Phase 4.3 fills periodic_measurements
lib/fun_sheep/application.ex                    — Phase 3.2 webhook subscription
all workers                                      — Phase 4.2 flag gating + change 4.3 source labels
```

---

## 11. Definition of done (per phase)

A phase is "done" only when:

1. All listed files created/modified
2. All acceptance criteria boxes checked
3. `mix test` shows 0 new failures (pre-existing failures documented but
   not blocking)
4. `mix format --check-formatted` passes
5. `mix credo --strict` shows no new warnings on new files
6. Visual verification with `visual-tester` agent on every new page
7. PR reviewed, merged to `main`, and the new page is reachable in
   staging
8. Cross-cutting 4.1 (dashboard card) updated for the new page
9. Cross-cutting 4.2 (sidebar) updated to include the new section

---

End of plan.
