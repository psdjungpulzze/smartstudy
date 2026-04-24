# FunSheep: Auto-Populate Courses & Upcoming Tests from External LMS/School Apps

> **How to use this file:** open a fresh Claude Code session inside
> `/home/pulzze/Documents/GitHub/personal/funsheep/` and paste the contents
> of this file as your first user message. It is self-contained — all context,
> file paths, endpoints, schemas, and acceptance criteria are here.

---

## 1. Goal

When a FunSheep student (or parent) connects an external school app — **Google
Classroom**, **Canvas LMS**, or **ParentSquare** — FunSheep must automatically
populate their:

- **Courses** (`FunSheep.Courses.Course`) — one row per imported class.
- **Upcoming tests / assessments** (`FunSheep.Assessments.TestSchedule`) —
  one row per assignment/quiz/test with a due date.

The integration must:

1. Use **Interactor Credential Management** for OAuth/token storage
   (no custom OAuth, no custom token refresh).
2. Use **Interactor Service Knowledge Base (SKB)** to look up provider
   metadata (service_id, scopes, base URL) — do **not** hardcode service
   URLs in FunSheep where SKB can answer them.
3. Use **Interactor webhooks** for credential lifecycle events
   (`credential.revoked`, `credential.refreshed`, `credential.expired`).
4. **Fail honestly.** If a sync can't reach the provider, mark the connection
   errored and show the user — never insert placeholder/mock courses or
   fake due dates. Read `/home/pulzze/Documents/GitHub/personal/funsheep/CLAUDE.md`
   section "ABSOLUTE RULE: NO FAKE, MOCK, OR HARDCODED CONTENT" — **this is
   load-bearing**.

---

## 2. What already exists (do not rebuild)

Read these first — they are scaffolded and working:

| File | Purpose |
|---|---|
| `lib/fun_sheep/interactor/auth.ex` | GenServer that exchanges `client_id/client_secret` for an Interactor JWT and caches it. |
| `lib/fun_sheep/interactor/client.ex` | `Client.get/1`, `Client.post/2`, `Client.put/3` — injects token, retries on 429, handles mock mode. |
| `lib/fun_sheep/interactor/credentials.ex` | Thin wrapper on `/api/v1/credentials/*`. Has `initiate_oauth/1`, `list_credentials/1`, `get_token/1`. Will need to add `delete_credential/1` and `get_credential/1`. |
| `lib/fun_sheep/interactor/knowledge_base.ex` | Talks to User Knowledge Base (port 4005) — **not** SKB. You will need a new `FunSheep.Interactor.ServiceKnowledgeBase` module for SKB (port 4003, `/api/services/*`). |
| `lib/fun_sheep_web/controllers/webhook_controller.ex` | Already handles `POST /api/webhooks/interactor` with `credential.*` branches. Extend these, don't duplicate. |
| `lib/fun_sheep/courses/course.ex` + `courses.ex` | Course schema + context. `metadata :map` field is available for external-id tagging. |
| `lib/fun_sheep/assessments/test_schedule.ex` + `assessments.ex` | TestSchedule schema + context. `scope :map` field is available. |
| `lib/fun_sheep/accounts/user_role.ex` | Has `interactor_user_id` — **this is the `external_user_id`** for Interactor Credential APIs. |
| `config/{config,dev,runtime,test}.exs` | `interactor_mock`, `interactor_core_url`, `interactor_client_id/secret` all wired. `interactor_mock: true` in test and by default; `false` in dev. |
| Router `/api/webhooks/interactor` | Already mounted. |

**Do not modify `FunSheep.Interactor.Auth` or `Client` unless genuinely
broken.** They are used by other Interactor features (agents, workflows,
credentials, UKB) already shipped.

---

## 3. Interactor flow (the canonical path)

```
┌──────────┐    1. click "Connect Canvas"     ┌──────────────────┐
│ Student  │ ─────────────────────────────► │ FunSheep backend │
└──────────┘                                   └────────┬─────────┘
                                                        │ 2. POST /api/v1/oauth/initiate
                                                        │    { service_id, external_user_id,
                                                        │      scopes, success_redirect_url }
                                                        ▼
                                               ┌──────────────────┐
                                               │    Interactor    │
                                               │  (core.interactor.com)
                                               └────────┬─────────┘
                                                        │ 3. returns authorization_url
                                                        ▼
┌──────────┐   4. redirect to authorization_url ┌──────────────────┐
│ Student  │ ◄───────────────────────────────── │ FunSheep backend │
└────┬─────┘                                    └──────────────────┘
     │ 5. authorizes on provider (Canvas/Google/…)
     ▼
┌────────────────┐   6. provider → Interactor callback
│ Canvas/Google  │ ─────────────────────────────►┌──────────────────┐
└────────────────┘                                │    Interactor    │  (stores credential)
                                                  └────────┬─────────┘
                                                           │ 7. redirect to success_redirect_url
                                                           │    ?credential_id=…&service_id=…
                                                           ▼
                                                  ┌──────────────────┐
                                                  │ FunSheep backend │ 8. save IntegrationConnection,
                                                  │                  │    enqueue IntegrationSyncWorker
                                                  └────────┬─────────┘
                                                           │ 9. GET /api/v1/credentials/{id}/token
                                                           │    → access_token
                                                           ▼
                                                  ┌──────────────────┐
                                                  │  Provider API    │  (Canvas/Google Classroom)
                                                  └──────────────────┘
                                                           │ 10. courses + assignments
                                                           ▼
                                                   upsert into FunSheep DB,
                                                   broadcast PubSub dashboard update.
```

**Interactor endpoints you will call (full docs:
`docs/i/interactor-docs/integration-guide/03-credential-management.md`):**

| Verb | Path | Use |
|---|---|---|
| POST | `/api/v1/oauth/initiate` | Start OAuth for a service |
| GET | `/api/v1/credentials?external_user_id=<id>` | List a user's credentials |
| GET | `/api/v1/credentials/{id}` | Credential detail |
| GET | `/api/v1/credentials/{id}/token` | Fresh access token for the provider |
| POST | `/api/v1/credentials/{id}/refresh` | Force refresh |
| DELETE | `/api/v1/credentials/{id}` | Revoke |

**SKB endpoints (full docs:
`interactor-workspace/service-knowledge-base/README.md` and
`interactor-workspace/service-knowledge-base/lib/service_knowledge_base_web/router.ex`):**

| Verb | Path | Use |
|---|---|---|
| GET | `/api/services/:id_or_slug` | Resolve `google_classroom` / `canvas` → service definition (incl. `api_base_url`, default auth provider, default scopes) |
| GET | `/api/services/:id_or_slug/capabilities` | List the capabilities (AI-agent-friendly operations) |
| POST | `/api/services/search` | Semantic search (use this to answer "find me LMS services") |

SKB runs on `http://localhost:4003` locally; production
`https://skb.interactor.com`. Configure via `interactor_skb_url` — add it to
`config/*.exs` alongside `interactor_ukb_url`.

---

## 4. Provider-specific adapters

Each provider gets its own adapter module implementing a common behaviour:

```elixir
defmodule FunSheep.Integrations.Provider do
  @callback service_id() :: String.t()           # SKB slug, e.g. "google_classroom"
  @callback default_scopes() :: [String.t()]
  @callback list_courses(access_token :: String.t(), opts :: keyword) ::
              {:ok, [map]} | {:error, term}
  @callback list_assignments(access_token :: String.t(), external_course_id :: String.t(), opts :: keyword) ::
              {:ok, [map]} | {:error, term}
  @callback normalize_course(raw :: map) :: map       # returns attrs for FunSheep.Courses.Course
  @callback normalize_assignment(raw :: map, local_course_id :: Ecto.UUID.t(), user_role_id :: Ecto.UUID.t()) :: map | :skip
end
```

**Provider details:**

### Google Classroom
- SKB slug: `google_classroom`
- Scopes: `https://www.googleapis.com/auth/classroom.courses.readonly`,
  `https://www.googleapis.com/auth/classroom.coursework.me.readonly`
- Endpoints:
  - `GET https://classroom.googleapis.com/v1/courses?courseStates=ACTIVE`
  - `GET https://classroom.googleapis.com/v1/courses/{courseId}/courseWork`
- Test type heuristic: treat coursework with `workType == "ASSIGNMENT"` or
  `"SHORT_ANSWER_QUESTION"` or `"MULTIPLE_CHOICE_QUESTION"` as assignments;
  those with "test" / "quiz" / "exam" in `title` (case-insensitive) get
  imported as TestSchedule rows. Other coursework → skip (or stash in
  metadata for later).

### Canvas LMS
- SKB slug: `canvas` (verify via `GET /api/services/canvas`)
- Canvas is **multi-tenant per institution** — each school has its own host
  (`<school>.instructure.com`). The credential should carry the host in
  `metadata.api_base_url`; if the SKB service record doesn't supply it,
  prompt the user for their Canvas URL before starting OAuth.
- Scopes: `url:GET|/api/v1/courses`, `url:GET|/api/v1/courses/:id/assignments`
- Endpoints:
  - `GET {host}/api/v1/courses?enrollment_state=active&per_page=100`
  - `GET {host}/api/v1/courses/{course_id}/assignments?per_page=100`
- Treat every assignment with `due_at` in the future as a `TestSchedule`.

### ParentSquare
- ParentSquare does **not** publish an open OAuth API. For v1, skip full
  implementation — ship a provider module stub that renders a disabled
  "Coming soon" button and logs that SKB returned no verified service.
- In the follow-up, investigate: (a) district admin API access,
  (b) email-forwarding ingestion via Interactor email workflows.
- Document this limitation in `docs/i/guides/integrations.md`.

---

## 5. Data model changes

### New schema: `integration_connections`

```elixir
schema "integration_connections" do
  field :provider, Ecto.Enum, values: [:google_classroom, :canvas, :parentsquare]
  field :service_id, :string                    # SKB slug at time of connect
  field :credential_id, :string                 # Interactor credential id
  field :external_user_id, :string              # == user_role.interactor_user_id
  field :status, Ecto.Enum,
    values: [:pending, :active, :syncing, :error, :expired, :revoked],
    default: :pending
  field :last_sync_at, :utc_datetime
  field :last_sync_error, :string
  field :metadata, :map, default: %{}           # canvas host, scopes granted, etc.

  belongs_to :user_role, FunSheep.Accounts.UserRole

  timestamps(type: :utc_datetime)
end
```

Index: `unique(:user_role_id, :provider)` — one connection per provider per user-role.

### Course + TestSchedule tagging

Prefer adding columns (query performance) to a dedicated namespace:

```elixir
# in courses migration
add :external_provider, :string      # "google_classroom" | "canvas" | nil (user-created)
add :external_id, :string            # provider's course id
add :external_synced_at, :utc_datetime
add :import_status, :string, default: "active"
  # values: "pending_acceptance" | "active" | "declined"
  # Imported courses start as "pending_acceptance"; student must accept.
  # Manually-created courses go straight to "active".

create unique_index(:courses, [:created_by_id, :external_provider, :external_id],
       where: "external_provider IS NOT NULL")
```

```elixir
# in test_schedules migration
add :external_provider, :string
add :external_id, :string
add :external_synced_at, :utc_datetime
add :dedup_status, :string, default: "active"
  # values: "active" | "superseded"
  # When two synced rows resolve to the same test (same day + fuzzy topic),
  # the lower-scoring one is set to "superseded" — never hard-deleted.
```

Same external-identity columns on `test_schedules`. Keep `metadata` for
provider-native blobs (rubric urls, module ids, etc.).

**Migration rule:** additive only. No backfill required — existing
manually-created courses have `external_provider: NULL` and
`import_status: "active"`.

---

## 6. File-by-file implementation plan

Create/modify these (order matters for TDD):

1. **Migration**
   `priv/repo/migrations/{ts}_create_integration_connections.exs`
   `priv/repo/migrations/{ts+1}_add_external_identity_to_courses_and_schedules.exs`

2. **Schemas + context**
   - `lib/fun_sheep/integrations/integration_connection.ex` (schema)
   - `lib/fun_sheep/integrations.ex` (context: `create_connection/1`,
     `get_connection/1`, `list_for_user/1`, `mark_status/3`, `mark_synced/1`,
     `mark_errored/2`, `delete_connection/1`)
   - Extend `FunSheep.Courses` context with:
     - `list_pending_courses/1` — courses with `import_status: "pending_acceptance"` for a user
     - `accept_courses/2` — bulk-sets `import_status: "active"` on a list of ids
     - `decline_courses/2` — bulk-sets `import_status: "declined"`
     - `search_pending_courses/2` — filtered by subject/provider/teacher name (for Find More Courses)
   - `lib/fun_sheep/integrations/provider.ex` (behaviour)
   - `lib/fun_sheep/integrations/providers/google_classroom.ex`
   - `lib/fun_sheep/integrations/providers/canvas.ex`
   - `lib/fun_sheep/integrations/providers/parent_square.ex` (stub)
   - `lib/fun_sheep/integrations/registry.ex` — maps provider atom → module

3. **SKB client**
   - `lib/fun_sheep/interactor/service_knowledge_base.ex`
     (`get_service/1`, `list_capabilities/1`, `search_services/1`)
   - Add `interactor_skb_url` to config files.

4. **Credential wrapper additions**
   Extend `lib/fun_sheep/interactor/credentials.ex` with
   `get_credential/1` and `delete_credential/1`. No new module.

5. **Oban worker**
   `lib/fun_sheep/workers/integration_sync_worker.ex`
   - `perform/1` takes `%{"connection_id" => id}`
   - Fetches credential token → calls provider → upserts courses &
     schedules → **runs test deduplication** → broadcasts
     `PubSub "user:#{user_role_id}"` `{:integrations_synced, summary}`.
   - **Test deduplication** (inside the worker, after upsert):
     1. For each newly-synced `TestSchedule`, query the same user's schedules
        where `due_at` falls on the same calendar day.
     2. Group by fuzzy topic (Jaro-Winkler ≥ 0.85 after stripping noise
        words: "chapter", "unit", "quiz", "test", "exam").
     3. Within each group, keep the row with the **highest test quality
        score** (see the test scoring spec in
        `docs/ROADMAP/confidence-based-scoring.md` and
        `docs/ROADMAP/funsheep-platform-quality-assessment.md`). If scores
        are equal, keep earlier `inserted_at`.
     4. Set `dedup_status: "superseded"` on the losers. Do **not** delete.
        Log each suppression: `{kept_id, superseded_id, reason}`.
   - Queue: add `:integrations` to `config :fun_sheep, Oban, queues:` with
     `limit: 3`.

6. **HTTP controller + routes**
   - `lib/fun_sheep_web/controllers/integration_controller.ex`
     - `GET /integrations/connect/:provider` →
       `Credentials.initiate_oauth/1` with
       `success_redirect_url: url(~p"/integrations/callback")`,
       redirect user to returned `authorization_url`.
     - `GET /integrations/callback?credential_id=&service_id=` →
       create/update `IntegrationConnection`, enqueue sync worker,
       redirect to `/integrations` with a flash.
     - `DELETE /integrations/:id` → call
       `Credentials.delete_credential/1`, mark connection revoked.
   - Add to authenticated router scope in
     `lib/fun_sheep_web/router.ex` — follows existing LiveView/controller
     split pattern.

7. **Webhook extension**
   Extend `webhook_controller.ex` `handle_credential_event/2`:
   - `credential.revoked` / `credential.expired` → mark matching
     connection `:revoked` / `:expired`, broadcast PubSub.
   - `credential.refreshed` → clear `last_sync_error`, update
     `last_ok_at` (add field if useful).

8. **LiveView UI** — see §8 (Course Discovery & Acceptance UX) for the
   full UX spec of the two discovery surfaces; implement them here.
   - `lib/fun_sheep_web/live/integrations_live.ex` — list connections,
     one card per available provider, "Connect" / "Disconnect" / "Sync now"
     actions, shows last_sync_at + error.
   - **`/courses` page**: add "Find More Courses" section (search + multi-
     select, bulk-accept bar). See §8.A.
   - **Dashboard**: zero-state and bottom "Suggested Courses" strip.
     See §8.B.
   - Add a compact **"Connected apps"** section to
     `dashboard_live.ex` (student) and `parent_dashboard_live.ex` above
     the existing "upcoming tests" card. If no connections: a call-to-action
     "Connect your school app to auto-import courses & tests".
   - Route: `live "/integrations", IntegrationsLive, :index` (in the
     authenticated `live_session`).
   - Visual language: **must** follow
     `/home/pulzze/Documents/GitHub/personal/funsheep/CLAUDE.md` design
     system — primary green `#4CD964`, pill-shaped buttons, `rounded-2xl`
     cards, dark mode support. Run `/interactor-design-guide` skill
     to validate.

9. **Tests** — **mandatory**, no exceptions
   - `test/fun_sheep/integrations_test.exs` — context CRUD,
     honest-failure paths.
   - `test/fun_sheep/integrations/providers/*_test.exs` — given a
     recorded fixture, `normalize_course/1` + `normalize_assignment/2`
     produce the expected attrs. Use fixture JSON files in
     `test/support/fixtures/integrations/`.
   - `test/fun_sheep/workers/integration_sync_worker_test.exs` — mocks the
     provider module (use `Mox` — check if already in `mix.exs`; if not,
     add it and define `FunSheep.Integrations.ProviderBehaviour`).
   - `test/fun_sheep_web/controllers/integration_controller_test.exs` —
     redirect + callback flows. Use `interactor_mock: true` (default in
     test env), which makes `Client.post/2` return stub data.
   - `test/fun_sheep_web/live/integrations_live_test.exs` — render,
     click "Connect Canvas", click "Disconnect", status transitions.
   - Run `mix test --cover`. **Coverage must stay ≥ 80% overall.** If
     the diff drops coverage below that, add more tests.

10. **Docs**
    - `docs/i/guides/integrations.md` — new guide: how the feature
      works, what each provider supports, ParentSquare limitation.
    - Update `docs/ROADMAP.md` if it lists "LMS integration" items — set
      them to complete / in progress.
    - **Don't** touch `docs/setup/` — that's the proprietary setup
      methodology (read CLAUDE.md "Setup Documentation" section).

---

## 7. Acceptance criteria

A fresh student who:

1. Logs in (use the prod test student from `.env.credentials` — never
   paste creds inline, read them at test time — see memory
   `reference_prod_test_student`).
2. Goes to `/integrations` → sees three provider cards: Google
   Classroom & Canvas show a green **Connect** button; ParentSquare
   shows a disabled **Coming soon** state with a one-liner.
3. Clicks **Connect Google Classroom** → Interactor redirects to
   Google → authorizes → returns to `/integrations` with a success
   flash and the card now says "Connected — syncing…".
4. Within ~30 s, goes to `/dashboard`:
   - **If this is their first connection (zero active courses):** the
     main content area shows the "Suggested Courses" panel with all
     pending-acceptance courses and a bulk-accept bar — not just an
     empty state or a spinner.
   - **If they already have active courses:** a "Suggested Courses"
     strip appears at the bottom listing up to 3 pending courses.
5. Goes to `/courses` → "Find More Courses" section shows the same
   pending courses, grouped by provider. The search bar filters results
   as the student types.
6. Selects 2 courses via checkboxes → sticky bar shows "Accept (2)" →
   clicks it → both courses become active and disappear from the pending
   list. A success toast names the accepted courses.
7. Clicks **Accept All** on the remaining courses → all are accepted in
   one click.
8. Declines a course → it disappears from the discovery section (hidden,
   not hard-deleted).
9. Clicks **Disconnect** → card resets to Connect, connection record
   marked revoked, Interactor credential deleted.
10. If Google revokes externally, the webhook flips the connection to
    `:revoked` and the UI updates via PubSub.

**Test deduplication criteria:**
- If two synced TestSchedule rows have the same `due_at` date and a
  Jaro-Winkler similarity ≥ 0.85 on their cleaned titles, only the
  higher-scoring one has `dedup_status: "active"`. The other is
  `"superseded"` and must not appear in the Upcoming Tests list.

**Failure-mode criteria:**
- If `Client.get("/api/v1/credentials/{id}/token")` returns an error,
  the worker must set `status: :error`, write `last_sync_error`, and
  **must not** create any Course or TestSchedule rows for that run.
- If the provider returns 401/403, same as above.
- The LiveView must surface the error (never a silent empty state).

**Tech gates (CLAUDE.md mandatory):**
- `mix format --check-formatted` passes.
- `mix compile --warnings-as-errors` passes.
- `mix test --cover` passes, coverage ≥ 80%.
- `mix sobelow` clean (or new warnings justified in the PR body).
- LiveView tests exist for `IntegrationsLive`.
- **Playwright visual verification done** via
  `./scripts/i/visual-test.sh start` — see CLAUDE.md
  "Mandatory visual verification" section. Screenshot the connected
  state and the empty state. A claim of "UI done" without Playwright
  evidence will be rejected (see memory `feedback_visual_verify_ui`).

---

## 8. Course Discovery & Acceptance UX

### 8.A `/courses` → "Find More Courses"

The existing `/courses` page gains a **Find More Courses** section.

- **Where:** below the student's active course list (or as a tab/filter if
  the active list is long).
- **Contents:** all `import_status: "pending_acceptance"` courses for the
  current user, grouped by provider (Google Classroom → Canvas → …).
- **Search:** a text input that filters by subject name, provider, or teacher
  name via `Courses.search_pending_courses/2`. Search is live (phx-change),
  not a page reload.
- **Multi-select:** each course card has a visible checkbox. Selecting ≥ 1
  courses reveals a **sticky bottom action bar** with:
  - "Accept (N)" — primary green `#4CD964` pill button
  - "Decline (N)" — secondary outlined button
- **Accept All** shortcut button (above the list, right-aligned) that bulk-
  accepts every pending course in one click without requiring checkboxes.
- After acceptance, accepted courses disappear from this section and appear
  in the student's active course list immediately (optimistic UI via PubSub).
- If there are no pending courses: show an empty state with a "Connect your
  school app" CTA that links to `/integrations`.

### 8.B `/dashboard` → Suggested Courses

**Zero-state (student has no active courses):**
- The main content area of the dashboard is replaced by a full-width
  "Suggested Courses" panel — this is the **primary UX**, not a footnote.
- Shows pending-acceptance courses with the same multi-select + bulk-accept
  bar as §8.A.
- If the student also has no LMS connections: show the "Connect Google
  Classroom / Canvas" CTA as the very first element, above any course list.
- Zero state headline example: *"Get started — add your courses below."*

**Has active courses (normal state):**
- A **"Suggested Courses"** strip appears at the bottom of the dashboard,
  below the "Upcoming Tests" card.
- Shows up to 3 pending courses with checkboxes and an inline
  "Accept Selected" button.
- A "See all (N)" link navigates to `/courses#find-more`.
- Collapses (or hides entirely) once there are no more pending courses.

### 8.C Acceptance Model

| `import_status` | Meaning |
|---|---|
| `"pending_acceptance"` | Imported from LMS; awaiting student action. Visible in discovery surfaces only. |
| `"active"` | Student accepted. Appears in study plan, readiness tracking, and active course list. |
| `"declined"` | Student dismissed. Hidden from discovery unless "Show dismissed" filter is applied. |

Manually-created courses (`external_provider: nil`) always start as
`"active"` — the acceptance flow is only for LMS-imported courses.

### 8.D Test Deduplication UX

When the worker suppresses a duplicate test (§6 step 5), the student never
sees both entries. If a student later views "Sync history" (future feature),
they will see a log entry like:

> *"AP Bio Chapter 7 Quiz (Canvas, synced by Ms. Johnson) was auto-selected
> over a duplicate from Google Classroom because it had a higher quality
> score."*

No immediate user-facing notification is needed for v1 — the deduplication
is silent. Surface it only in the future "Sync history" view.

---

## 9. How to work with the Interactor submodule

You will probably want to look at SKB service definitions (to confirm
`canvas` and `google_classroom` slugs exist and what default scopes they
declare). That lives in the submodule at
`interactor-workspace/service-knowledge-base/`.

**You almost certainly do not need to modify the submodule.** If you do:

- Follow the 3-tier workflow in `interactor-workspace/CONSUMER_CLAUDE.md`
  (Tier 1 is a feature branch + PR on the service repo; Tiers 2 & 3 are
  automated). **Keep edits service-agnostic** — no FunSheep/consumer-app
  references in service-knowledge-base code (see memory
  `feedback_interactor_submodule_generic`).
- **Do not merge or deploy any Interactor repo** (hook-enforced — see
  memory `feedback_no_interactor_merge_or_deploy`). Open the PR and stop.

If SKB doesn't have a verified `canvas` or `google_classroom` record,
use `/iw-discovery` to queue a discovery — don't hardcode provider
metadata in FunSheep.

---

## 10. Local dev setup

```bash
# Workspace: run Interactor locally so the OAuth flow actually works.
cd interactor-workspace
./dev-env.sh set full-local
./dev-services.sh start
./dev-services.sh status   # verify 4001/4002/4003/4004/4005 are up

# Back in FunSheep
cd ..
mix deps.get
mix ecto.migrate
./dev-app.sh              # your usual dev server entry point

# For automated UI tests, use an isolated port (never 4040):
PORT=$(./scripts/i/visual-test.sh start)
# ... do Playwright work at http://localhost:$PORT ...
./scripts/i/visual-test.sh stop
```

Interactor config in `config/dev.exs`: `interactor_mock: false`,
`interactor_core_url: http://localhost:4002`. With `mock_mode? == false`,
`Client.post/2` will actually hit Interactor — you need services
running for the OAuth flow to complete end-to-end.

**Never run `mix compile` while the dev server is running** (memory
`feedback_no_mix_compile`). The live reloader handles it.

---

## 11. Git / PR workflow for FunSheep

FunSheep origin is **smartstudy**, not `product-dev-template`. Verify
with `git remote -v` before pushing — if it's wrong, fix it (memory
`project_remote_origin_smartstudy`).

Work on a feature branch (`feature/integrations-auto-populate` or
similar). PR title under 70 chars. Keep the PR body tight: what changed,
why, and the Playwright screenshot proving the UI works.

Use the `/git-pr-new` skill if you want guided PR creation.

---

## 12. What NOT to do

- ❌ Don't write a custom OAuth handler in FunSheep. Interactor owns
  OAuth.
- ❌ Don't store provider access/refresh tokens in FunSheep's DB.
  `IntegrationConnection` only stores `credential_id`; always re-fetch
  the live token from `/api/v1/credentials/{id}/token`.
- ❌ Don't hardcode a list of "known providers" with baked-in base URLs
  or scopes. Ask SKB at runtime (cache the answer in ETS/Cachex if
  needed).
- ❌ Don't insert fake/placeholder courses when the API is down. Set
  `status: :error` and let the UI show the retry CTA.
- ❌ Don't skip LiveView tests or Playwright verification.
- ❌ Don't create a "Plan" doc or an analysis doc in the repo — work
  from this prompt and conversation context (feedback memory).
- ❌ Don't merge or deploy anything in the `interactor-workspace/`
  submodules.

---

## 13. Suggested order of operations

1. Read the three CLAUDE.md files (top-level, `interactor-workspace/`,
   `interactor-workspace/service-knowledge-base/`) and memory at
   `~/.claude/projects/.../memory/MEMORY.md`.
2. Confirm SKB has `google_classroom` and `canvas`:
   `curl http://localhost:4003/api/services/google_classroom`.
3. Write the migration + schema + context + behaviour module. Tests first.
4. Write the SKB client + extend Credentials wrapper. Tests.
5. Implement Google Classroom adapter against a recorded fixture. Tests.
6. Implement Canvas adapter against a recorded fixture. Tests.
7. ParentSquare stub.
8. Oban worker. Tests with mocked provider.
9. Controller + routes. Tests.
10. LiveView + dashboard:
    - `/courses` "Find More Courses" section (search + multi-select + bulk-accept bar).
    - Dashboard zero-state (Suggested Courses as main content) and bottom strip.
    - LiveView tests for both surfaces.
11. Webhook extensions. Tests.
12. Run `mix format && mix compile --warnings-as-errors && mix test --cover && mix sobelow`.
13. Start the dev stack, walk through the flow in a browser, take
    Playwright screenshots of:
    - Dashboard zero-state showing Suggested Courses panel.
    - `/courses` Find More Courses with ≥ 1 pending course.
    - Bulk-accept action bar after selecting 2 courses.
    - Dashboard bottom strip after accepting some courses.
14. Open the PR.

---

## 14. Out of scope for this PR

- Teacher-side bulk connect (classroom rostering — the teacher accepts on
  behalf of all students in a class). This is the natural v2 after
  individual acceptance lands.
- "Show dismissed courses" filter (reveal `status: "declined"` courses
  in Find More Courses so students can un-decline).
- Sync history / deduplication audit view (show the student which tests
  were auto-selected and why — §8.D notes this for a future release).
- Bi-directional sync (posting FunSheep results back to Google Classroom).
- Grade sync / submission sync.
- Push-to-refresh via provider webhooks (rely on on-demand + periodic
  polling for v1; add a cron-style Oban schedule later).
- ParentSquare full integration (stubbed, see §4).

These go in `docs/ROADMAP.md` as follow-ups.
