# External LMS & School-App Integrations

FunSheep auto-populates a student's courses and upcoming tests by
syncing from the school apps they already use. OAuth, token storage,
and token refresh are owned by **Interactor Credential Management** —
FunSheep never stores provider access/refresh tokens, and it never
fabricates course or assignment data when a provider is unreachable
(see CLAUDE.md "ABSOLUTE RULE: NO FAKE, MOCK, OR HARDCODED CONTENT").

## Providers

| Provider | Slug | Status | What gets imported |
|---|---|---|---|
| Google Classroom | `google_classroom` | ✅ Supported | Active courses + coursework titled "test" / "quiz" / "exam" / "midterm" / "final" / "assessment" with a due date |
| Canvas LMS | `canvas` | ✅ Supported | Active courses + every assignment with a future `due_at` |
| ParentSquare | `parentsquare` | ⏳ Coming soon | — |

### ParentSquare limitation

ParentSquare does not publish an open OAuth API that exposes
student-level course data. Until we have a verified Service Knowledge
Base (SKB) record and/or a district-admin integration path (or an
email-forwarding ingestion pipeline via Interactor email workflows),
the ParentSquare card renders as a disabled "Coming soon" in the UI
and the provider module refuses to initiate OAuth.

Roadmap for ParentSquare:

1. Queue an SKB discovery via `/iw-discovery`.
2. Investigate district-admin API access + email-forwarding ingestion.
3. Revisit once SKB has a verified service record.

## Flow

```text
Student → Connect button → /integrations/connect/:provider
                           │
                           ▼
                 Credentials.initiate_oauth/1 ──► Interactor
                           │                         │
                           │   authorization_url     │
                           ◄─────────────────────────┘
                           │
                           ▼
             Student authorises on provider
                           │
                           ▼
                Interactor → /integrations/callback
                 ?credential_id=…&service_id=…
                           │
                           ▼
          Integrations.upsert_connection/1
                           │
                           ▼
          IntegrationSyncWorker (Oban :integrations queue)
                           │
                           ▼
             Credentials.get_token/1 ──► Interactor
                           │                 │
                           │  access_token   │
                           ◄─────────────────┘
                           │
                           ▼
                   Provider adapter
                           │
          ┌────────────────┴────────────────┐
          ▼                                 ▼
  Courses.create_course          Assessments.create_test_schedule
   (upsert by external id)        (upsert by external id)
          │                                 │
          └────────────────┬────────────────┘
                           ▼
       broadcast {:integration_event, :synced, summary}
```

## Modules

| Module | Responsibility |
|---|---|
| `FunSheep.Integrations` | Context — CRUD on `integration_connections` + status helpers + PubSub |
| `FunSheep.Integrations.IntegrationConnection` | Schema — one row per (user_role, provider) |
| `FunSheep.Integrations.Provider` | Behaviour adapters implement |
| `FunSheep.Integrations.Registry` | Maps provider atom → adapter module (overridable in tests) |
| `FunSheep.Integrations.Providers.GoogleClassroom` | Google Classroom adapter |
| `FunSheep.Integrations.Providers.Canvas` | Canvas LMS adapter (needs institution host) |
| `FunSheep.Integrations.Providers.ParentSquare` | Stub — declares `supported?/0 == false` |
| `FunSheep.Interactor.ServiceKnowledgeBase` | Thin client for SKB (`/api/services/*`) |
| `FunSheep.Interactor.Credentials` | Extended with `get_credential/1` and `delete_credential/1` |
| `FunSheep.Workers.IntegrationSyncWorker` | Oban worker (`:integrations` queue) |
| `FunSheepWeb.IntegrationController` | OAuth connect / callback / disconnect / sync-now |
| `FunSheepWeb.IntegrationsLive` | Integrations management page |

## Configuration

| Key | Default | Purpose |
|---|---|---|
| `:fun_sheep, :interactor_skb_url` | `http://localhost:4003` (dev) / `https://skb.interactor.com` (prod) | SKB base URL |
| `:fun_sheep, Oban, :queues, :integrations` | `3` | Concurrency for sync worker |
| `:fun_sheep, :integrations_provider_modules` | `%{}` | Test-only override — map `provider_atom => MockModule` |

## Honest-failure guarantees

The sync worker follows the CLAUDE.md "no fake content" rule:

1. If `Credentials.get_token/1` fails, the worker `mark_errored`s the
   connection and returns `{:error, reason}` — **no** course or test
   schedule rows are written.
2. If the provider returns `{:error, _}` (401 / 403 / 5xx), same behaviour.
3. If the provider returns an empty list, no rows are written and the
   connection flips to `:active` with `last_sync_at` set — this is
   distinct from an error.
4. All errors surface in the UI via `last_sync_error` (text column).
5. Webhook events `credential.revoked` / `credential.expired` /
   `credential.refreshed` flip connection status and broadcast PubSub.

## Adding a new provider

1. Add the atom to `IntegrationConnection.@providers` and `@statuses` as needed.
2. Create `FunSheep.Integrations.Providers.<Name>` implementing `FunSheep.Integrations.Provider`.
3. Register the module in `FunSheep.Integrations.Registry.@defaults`.
4. Add a human label in `Registry.label/1` and UI polish in
   `FunSheepWeb.IntegrationsLive` (emoji + description).
5. Write provider tests covering `normalize_course/1` and `normalize_assignment/3`.
6. Confirm the SKB slug exists via `curl $SKB_URL/api/services/<slug>`.

## Testing

- Unit: `test/fun_sheep/integrations/providers/*_test.exs` — normalisers + behaviour contracts.
- Context: `test/fun_sheep/integrations_test.exs` — CRUD, upsert, status transitions, PubSub.
- Worker: `test/fun_sheep/workers/integration_sync_worker_test.exs` — uses `FunSheep.Integrations.Providers.Fake` registered via `:integrations_provider_modules` to test happy + honest-failure + idempotency paths.
- Controller: `test/fun_sheep_web/controllers/integration_controller_test.exs`.
- LiveView: `test/fun_sheep_web/live/integrations_live_test.exs`.
- Webhook: `test/fun_sheep_web/controllers/webhook_credential_event_test.exs`.

Run the integration-feature slice with:

```bash
mix test test/fun_sheep/integrations_test.exs \
         test/fun_sheep/integrations/ \
         test/fun_sheep/workers/integration_sync_worker_test.exs \
         test/fun_sheep_web/controllers/integration_controller_test.exs \
         test/fun_sheep_web/live/integrations_live_test.exs \
         test/fun_sheep_web/controllers/webhook_credential_event_test.exs \
         test/fun_sheep/interactor/service_knowledge_base_test.exs
```

## Out of scope (v1)

- Teacher-side bulk connect / rostering — planned for Teacher Phase 5.
- Bi-directional sync (posting FunSheep results back to provider).
- Grade / submission sync.
- Provider-webhook push-to-refresh — we currently rely on on-demand sync
  and periodic polling; a cron-style Oban schedule is a follow-up.
- ParentSquare full integration — see limitation above.
