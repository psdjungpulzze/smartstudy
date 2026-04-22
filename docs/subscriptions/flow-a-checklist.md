# Flow A — Student-initiated upsell — Delivery Checklist

Full spec: `~/s/funsheep-subscription-flows.md` §4, §7, §8, §9, §10, §12 (sections referenced inline).

**The conversion loop**: student hits ~85% of weekly cap → taps "Ask a grown-up" → picks linked guardian + pre-written reason → email + in-app notification fire to parent → parent accepts in ≤3 taps → Interactor Billing checkout completes → webhook unlocks student → live PubSub celebration toast.

Ship across 3 PRs in this worktree. Tick items only when tests AND (where applicable) visual verification pass.

---

## PR 1 — Scaffold + migrations (§7, §11.1)

### Data model

- [ ] Create `practice_requests` table (§7.1):
  - [ ] `id` uuid, `student_id` → `user_roles.id`, `guardian_id` → `user_roles.id` (nullable when sent to all linked)
  - [ ] `reason_code` enum(`:upcoming_test, :weak_topic, :streak, :other`)
  - [ ] `reason_text` text nullable (free-text if `reason_code = :other`)
  - [ ] `status` enum(`:pending, :viewed, :accepted, :declined, :expired, :cancelled`)
  - [ ] `sent_at, viewed_at, decided_at, expires_at` utc_datetime (expires = sent + 7d)
  - [ ] `parent_note` text nullable
  - [ ] `subscription_id` uuid nullable → `subscriptions.id`
  - [ ] `reminder_sent_at` utc_datetime nullable (enforces 1-reminder-max)
  - [ ] `metadata` map (immutable activity snapshot at request time)
  - [ ] timestamps
  - [ ] Indexes: `(student_id, status)`, `(guardian_id, status)`, `(expires_at)`
- [ ] Alter `subscriptions` table (§7.2):
  - [ ] Add `paid_by_user_role_id` → `user_roles.id` nullable, `on_delete: :nilify_all`
  - [ ] Add `origin_practice_request_id` → `practice_requests.id` nullable, `on_delete: :nilify_all`
  - [ ] Index on `paid_by_user_role_id`
- [ ] Add `user_roles.timezone` string nullable (§9.3 — needed for parent quiet-hours scheduling)
- [ ] Update `FunSheep.Billing.Subscription` schema with new fields
- [ ] Update `FunSheep.Accounts.UserRole` schema with `:timezone`
- [ ] Create `FunSheep.PracticeRequests.Request` schema mirroring the table
- [ ] Reversible migration (test `mix ecto.rollback` then `mix ecto.migrate`)
- [ ] `mix format`, `mix credo --strict`, `mix sobelow` pass

### Docs

- [ ] `docs/subscriptions/README.md` + flow-{a,b,c}-checklist.md committed (this PR)

---

## PR 2 — Flow A backend (§7.3, §7.4, §7.5, §11.2)

### `FunSheep.Billing` additions (§7.3)

Roll up existing `TestUsage` data — do NOT add a parallel counter table.

- [ ] `weekly_usage(user_role_id)` → `%{used, limit, remaining, resets_at}`
- [ ] `lifetime_usage(user_role_id)` → `%{used, limit, remaining}`
- [ ] `usage_state(user_role_id)` → `:fresh | :warming | :nudge | :ask | :hardwall` per §4.1 thresholds (0–50%, 50–70%, 70–85%, 85–99%, 100%)
- [ ] `can_start_test?(user_role_id)` → boolean
- [ ] Unit tests cover every threshold boundary

### `FunSheep.Accounts` additions (§7.4)

- [ ] `list_active_guardians_for_student(student_id)` — excludes `:revoked`
- [ ] `find_primary_guardian(student_id)` — returns single UserRole or nil

### `FunSheep.PracticeRequests` context (§7.5)

- [ ] `create/3` — student + guardian(s) + reason. Returns error if student already has a `:pending` request (one-at-a-time rule)
- [ ] `view/1` — transitions `:pending` → `:viewed`, stamps `viewed_at`, fires telemetry `request.viewed`
- [ ] `accept/2` — stamps `decided_at`, links `subscription_id`, fires `request.accepted`; idempotent via race-safe transaction with `SELECT ... FOR UPDATE` per §9.2
- [ ] `decline/3` — stamps `decided_at`, optional `parent_note`, fires `request.declined`; enforces 48h student re-ask cooldown
- [ ] `expire/1` — manual transition to `:expired`
- [ ] `list_pending_for_guardian/1`
- [ ] `count_pending_for_student/1`
- [ ] `send_reminder/1` — enforces max 1 reminder per request; stamps `reminder_sent_at`
- [ ] Request creation snapshots activity into `metadata`: streak, weekly minutes, weekly questions, accuracy, upcoming test (if any) — per §4.6 + §8.2 so email renders from immutable data

### Oban workers (§9.3, §11.2)

- [ ] `FunSheep.Workers.RequestExpiryWorker` — cron-style hourly, transitions `:pending` past `expires_at` → `:expired`, emits `request.expired` telemetry
- [ ] `FunSheep.Workers.ParentRequestEmailWorker` — dispatches Swoosh email via `FunSheep.Mailer`; honors 10pm–7am parent-local quiet hours (fallback student tz, then UTC); emits `request.email_sent` telemetry
- [ ] Worker tests cover: quiet-hours deferral, missing timezone → UTC fallback, reminder enforcement

### Telemetry events (§9.4)

- [ ] Emit `[:fun_sheep, :practice_request, :created]`
- [ ] Emit `[:fun_sheep, :practice_request, :email_sent]`
- [ ] Emit `[:fun_sheep, :practice_request, :viewed]`
- [ ] Emit `[:fun_sheep, :practice_request, :accepted]`
- [ ] Emit `[:fun_sheep, :practice_request, :declined]`
- [ ] Emit `[:fun_sheep, :practice_request, :expired]`

### Coverage & quality gates

- [ ] `mix test --cover` ≥ 80%
- [ ] `mix format`, `mix credo --strict`, `mix sobelow` all pass
- [ ] No `mix compile` while the user's dev server is running (memory)

---

## PR 3 — Flow A UI + end-to-end loop (§4, §8, §11.3)

### Student usage meter (§4.1)

Persistent pill + dashboard card. Reuses `TestUsage` via `Billing.weekly_usage/1`.

- [ ] `FunSheepWeb.BillingComponents.usage_meter/1` LiveComponent
- [ ] Pill copy maps to `usage_state`:
  - `:fresh` → "🐑 10 free practice left this week"
  - `:warming` → "🐑 6 free practice left — nice streak"
  - `:nudge` → "🐑 3 left this week — great momentum"
  - `:ask` → "🐑 1 left — ask a grown-up for more?"
  - `:hardwall` → "🌿 Weekly practice complete — unlock more?"
- [ ] Pill visible on every authenticated student page (embed in app-bar layout)
- [ ] Larger card variant on student dashboard
- [ ] Never uses words "limit," "quota," "paywall"
- [ ] No red/warning colours until hardwall (and even there, stays encouraging)
- [ ] Dark-mode compliant (per `.claude/rules/i/ui-design.md`)
- [ ] Accessibility: contrast ≥ 4.5:1

### Soft pre-prompt at 70% (§4.2)

- [ ] Dashboard card "You're on a 🔥 roll this week..." with [Ask a grown-up] button
- [ ] Dismissible with "Not yet" link — hidden until next threshold (85%)
- [ ] Dismissal persisted (likely per-user session or a lightweight row)

### The Ask card at 85% (§4.3)

- [ ] Bigger dashboard card with §4.3 draft copy (dry-humour parenthetical intact)
- [ ] Single green `#4CD964` `rounded-full` CTA: "💚 Ask a grown-up"
- [ ] Only renders when `Billing.usage_state == :ask` AND no `:pending` request exists AND student is not already paid

### Request-builder modal (§4.4)

- [ ] Opens from Ask card — ≤2 taps to send
- [ ] Step 1: radio list of linked guardians (auto-select if 1; fallback to §4.8 invite flow if 0)
- [ ] Step 2: radio of 4 reason codes — first 3 pre-written, 4th is Other with 140-char textarea
- [ ] **Never pre-tick a reason** — student must actively choose (§10)
- [ ] Green send button; under-button copy: "Your parents will love this..."
- [ ] 800ms confetti animation on send (not longer — kids 10+ resent cartoonish over-celebration)
- [ ] Activity snapshot (streak, minutes, accuracy, upcoming test) written to `metadata` at send time

### Student waiting state (§4.5)

- [ ] Dashboard card: "Request sent to {{Guardian name}} 💌 · Sent {{relative time}} ago"
- [ ] After 24h without response: softer nudge + "Send a reminder" button (enforces max 1)
- [ ] On expire (>7d): card flips to "This request expired — feel free to send a new one"
- [ ] On decline: shows parent_note if present, else default decline copy (§8.4)
- [ ] No excessive badging or notification — respect student patience

### Parent notification — email (§4.6.1, §8.1, §8.2)

- [ ] `FunSheepWeb.Emails.ParentRequestEmail` Swoosh template — HTML + text
- [ ] Ship **Variant A only** from §8.1 ("The rare parent-win"); Variant B stubbed behind `:parent_request_email_variant` feature flag (default `:a`)
- [ ] Uses real `UserRole.display_name` — never placeholder
- [ ] Real streak / weekly minutes / weekly questions / accuracy from activity snapshot
- [ ] If no upcoming test, omit the test line entirely — do NOT fabricate
- [ ] Shows BOTH monthly and annual plans
- [ ] Cancel-anytime language visible
- [ ] Polite-decline link rendered prominently (trust + ethical commitment)
- [ ] FERPA / privacy note
- [ ] Unsubscribe link
- [ ] **Quiet hours enforced**: worker does not send 10pm–7am parent-local (`Oban.Job.schedule_at` to next valid window); falls back to student tz then UTC
- [ ] Subject line uses Variant A option (testable; don't hardcode a single string — pull from template module)

### Parent notification — in-app (§4.6.2, §8.3)

- [ ] Card at top of `/parent` dashboard: "💚 {{Student name}} just asked for unlimited practice"
- [ ] Shows the student's chosen reason
- [ ] `[See the evidence and decide]` opens modal with full email content (minus scaffolding) + green checkout CTA + polite-decline link
- [ ] Dismissible per-request (does not kill the request — just hides the card until next login)
- [ ] Only renders if parent has ≥1 `:pending` request on a student linked via an `:active` `student_guardians` row (§9.1 authorization)

### Parent decision → checkout → activation (§4.7, §9.2)

- [ ] **Accept path**:
  - [ ] 1-page confirm screen — plan choice (annual highlighted), price, unlocks, "who pays" clarity, cancel-anytime note
  - [ ] `Billing.create_checkout/4` called with `metadata.student_user_role_id` AND `metadata.practice_request_id`
  - [ ] `create_checkout` is idempotent on `practice_request_id` (§9.2) — a second parent tapping Accept does not create a second Stripe session
  - [ ] Webhook fires → `Billing.activate_subscription/2` with `user_role_id = student`, `paid_by_user_role_id = parent`, `origin_practice_request_id = request.id`
  - [ ] Webhook handler short-circuits if subscription for that student is already `:active` (§4.9)
  - [ ] DB-level `SELECT ... FOR UPDATE` when flipping `practice_request.status` → `:accepted` (race safety §9.2)
  - [ ] Phoenix.PubSub event to student LiveView — meter updates + celebration toast within 5s (§12)
  - [ ] Post-checkout parent landing: "✅ Unlocked" + [Send them a note] secondary CTA
- [ ] **Decline path**:
  - [ ] Single-screen confirm (no guilt trip) with optional "Send a kind note back"
  - [ ] Student sees parent_note if written, else default kind copy
  - [ ] Request enters `:declined` — 48h cooldown before next ask
- [ ] **Ignore path**:
  - [ ] No parent action within 7 days → `RequestExpiryWorker` transitions to `:expired`
  - [ ] Student sees expiry copy (§4.5)

### Edge cases

- [ ] **No linked guardian (§4.8)**: Ask button opens invite-grown-up flow; two-part email fires on invite-accept (guardian-invite + request-preview)
- [ ] **Multiple linked guardians (§4.9)**: default "all grown-ups"; student may pick one; first to purchase wins; other gets "{{Other parent}} already handled this" note
- [ ] **Already paid (§4.10)**: Ask card does not surface; race creates return `{:error, :already_paid}` → friendly "You're already unlimited! 🎉"

### Teacher guard on `/subscription` (§6.3, §8.5)

Small but critical — keeps Flow C's teacher-never-sees-billing invariant in place.

- [ ] If `SubscriptionLive` mounts with `role: :teacher`, render §8.5 copy instead of plan picker: "Teachers don't need a subscription — FunSheep is free for educators..."
- [ ] Link back to teacher dashboard (or `/` if none)

### Tests (§4.11, §9.5)

- [ ] LiveView tests for student usage meter at **every** state (below 50% / 50–70% / 70–85% / 85–99% / 100%)
- [ ] LiveView test for pre-prompt render + dismiss
- [ ] LiveView test for Ask card gating (only at `:ask`, only when no `:pending`, only when `!paid?`)
- [ ] LiveView test for request-builder modal — ≤2 taps to send, pre-selected reason is rejected
- [ ] LiveView test for waiting state transitions (pending → viewed → accepted/declined/expired)
- [ ] LiveView test for parent in-app card + modal
- [ ] Worker test: email dispatch respects quiet hours
- [ ] Worker test: expiry transitions `:pending` rows past `expires_at`
- [ ] Worker test: reminder enforcement (max 1)
- [ ] Integration test: full happy path (student hits 20/20 → opens modal → sends → Swoosh dev mailbox receives → parent accepts → fake webhook → subscription activates → PubSub event received)
- [ ] Race condition test: two parents accepting concurrently produces exactly ONE subscription
- [ ] Teacher `/subscription` renders free-for-educators copy, not plan picker
- [ ] Coverage ≥ 80% overall (`mix test --cover`)
- [ ] `mix format --check-formatted`, `mix credo --strict`, `mix sobelow` clean

### Visual verification (mandatory — `.claude/rules/i/visual-testing.md`)

Use `scripts/i/visual-test.sh start` (never port 4040). Capture light + dark at 375, 768, 1440.

- [ ] Student meter states × 5 (dashboard card variant)
- [ ] Student meter pill × 3 key states (fresh, ask, hardwall)
- [ ] Pre-prompt card (70%)
- [ ] Ask card (85%)
- [ ] Request-builder modal (each step)
- [ ] Waiting card (pending / reminder-available / declined / expired)
- [ ] Parent email (Swoosh dev mailbox — desktop + mobile widths via devtools)
- [ ] Parent in-app card + modal on `/parent`
- [ ] Accept-confirm screen + "Unlocked" landing
- [ ] Decline-confirm screen
- [ ] Teacher `/subscription` free-for-educators page

---

## What NOT to do (§10) — enforced via code review

- [ ] No parallel billing system. Only `FunSheep.Billing` + `FunSheep.Interactor.Billing`.
- [ ] No direct new Stripe code — Interactor Billing Server is the only supported path.
- [ ] No fabricated activity metrics anywhere. (CLAUDE.md absolute rule.)
- [ ] No default-selected reason on the student's ask.
- [ ] Ask card hidden if student is already paid.
- [ ] No email sends 10pm–7am parent-local.
- [ ] Max 1 reminder per request.
- [ ] Accepted subscriptions must unlock the student UI within seconds — PubSub, not polling.
- [ ] Decline flow has the same friction level as Accept.
- [ ] No leaderboards of "other parents upgraded."
- [ ] No trial auto-conversion (there is no trial in this plan).
- [ ] Do not change the 50-lifetime / 20-weekly caps or the $30/$90 pricing.
- [ ] Never `mix compile` while dev server is running (memory).
- [ ] Never start a test server on 4040; use `./scripts/i/visual-test.sh start`.

---

## Regression surface (must still work after Flow A ships)

- [ ] Existing `/subscription` flow for self-purchase (adult learners, parents buying for themselves in Flow B)
- [ ] `/guardians` invite flow
- [ ] Student test-taking from `:fresh` through `:nudge` states
- [ ] Webhook controller for existing Interactor Billing events (activate/cancel for non-Flow-A purchases)
- [ ] Admin role paths (no accidental gating)
- [ ] Existing `FunSheep.Billing.check_test_allowance/2` behaviour for teachers/parents (still returns `:ok` without DB writes)

---

## Done criteria (§12 — the end-state sanity check)

- [ ] Student on free tier with 20/20 can send a request in 2 taps including reason pick
- [ ] Parent receives well-rendered email within seconds (respecting quiet hours) AND in-app card on dashboard
- [ ] Parent accepts in 3 taps → student unlocked within 5 seconds of checkout completion
- [ ] Parent declines in 2 taps without shame → student sees a kind message
- [ ] Request auto-expires in 7 days → student can re-ask after cooldown
- [ ] Telemetry fires for every state transition
- [ ] `/subscription` continues to work for direct purchase
- [ ] Tests ≥ 80% coverage, LiveView tests for every route, all lints pass, no `mix sobelow` findings
- [ ] No fake content anywhere — every metric pulled from real activity
