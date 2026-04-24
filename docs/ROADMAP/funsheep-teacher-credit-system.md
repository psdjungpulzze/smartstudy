# FunSheep — Teacher Credit System ("Wool Credits")

**Status:** Planning  
**Date:** 2026-04-24  
**Author:** Product  
**Related:** `docs/ROADMAP/flock-shout-outs-and-credits.md` (shout-outs layer built on top of this)

---

## 0. TL;DR

Teachers earn "Wool Credits" by growing their classroom and contributing content. Each credit is worth one free month of FunSheep for any recipient. Teachers can keep credits for themselves, give them to students, or pass them to other teachers. This makes teachers the product's best growth channel: every classroom they build and every test they upload multiplies into subscription value they can distribute.

---

## 1. Business Goals

| Goal | Mechanism |
|------|-----------|
| Reduce student churn | Teachers gift months → students stay active even if parent hasn't converted |
| Accelerate teacher adoption | Tangible reward for every student onboarded and every piece of content contributed |
| Make teachers evangelists | A teacher with 30 students has 3 credits in hand — enough to gift months to their struggling students |
| Network-effect virality | Teacher invites more students → earns more credits → gifts more → more students engage → loop |

---

## 2. Credit Rules (Product Decisions)

### 2.1 Earning (teachers only)

| Activity | Credits Awarded | Implementation hook |
|----------|----------------|---------------------|
| 10 students accept invite | **+1 credit** | `student_guardians` status → `:active` |
| 2 textbooks/materials processed | **+1 credit** | `uploaded_materials` status → `:processed` |
| 4 test schedules created | **+1 credit** | `test_schedules` inserted |

Internally all credits are stored as **integer quarter-units** (1 credit = 4 quarter-units) to avoid floating-point arithmetic. The table below maps activities to quarter-units:

| Activity | Quarter-units |
|----------|--------------|
| 10 students accept invite | +4 |
| 1 material processed | +2 |
| 1 test schedule created | +1 |

Partial batches do not award early. A teacher with 9 students has 0 credits; at the 10th they receive 1. At student 20 they receive a second credit, etc.

### 2.2 Spending / Transferring

| Action | Quarter-unit cost | Effect on recipient |
|--------|------------------|---------------------|
| Give 1 credit to a student | −4 | Extends/creates student subscription by 30 days |
| Give 1 credit to another teacher | −4 | Adds +4 quarter-units to teacher's balance |
| Redeem 1 credit for own subscription | −4 | Extends/creates own subscription by 30 days |

Rules:
- Cannot give more than current balance (balance floored at 0).
- Recipient must be an active (non-suspended) user.
- Teachers may transfer to any student they are linked to OR to any teacher in the system.
- Students **cannot** earn or transfer credits — they can only receive them.

### 2.3 Credits Do Not Expire

Credits are permanent until spent. No expiry logic needed in Phase 1 or 2.

---

## 3. Database Schema

### 3.1 `wool_credits` — Immutable Event Ledger

Pattern mirrors `xp_events`: append-only, never updated. Balance = `SUM(delta)`.

```sql
CREATE TABLE wool_credits (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id        UUID NOT NULL REFERENCES user_roles(id) ON DELETE CASCADE,
  delta               INTEGER NOT NULL,                    -- quarter-units; positive = earn, negative = spend
  source              VARCHAR NOT NULL,                    -- see source enum below
  source_ref_id       UUID,                               -- FK to the record that triggered this entry
  metadata            JSONB NOT NULL DEFAULT '{}',
  inserted_at         TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
  -- NO updated_at — immutable
);

CREATE INDEX wool_credits_user_role_id_idx ON wool_credits (user_role_id);
CREATE INDEX wool_credits_source_ref_id_idx ON wool_credits (source_ref_id) WHERE source_ref_id IS NOT NULL;
```

**Source enum values:**

| Source | Description |
|--------|-------------|
| `referral` | Batch of 10 students crossed; `source_ref_id` = last `student_guardian.id` that triggered the batch |
| `material_upload` | Textbook/material processed; `source_ref_id` = `uploaded_material.id` |
| `test_created` | Test schedule created; `source_ref_id` = `test_schedule.id` |
| `transfer_in` | Received from another teacher; `source_ref_id` = `credit_transfer.id` |
| `transfer_out` | Sent to student or teacher; `source_ref_id` = `credit_transfer.id` |
| `redemption` | Self-redeemed for own subscription month; `source_ref_id` = subscription.id (updated) |
| `admin_grant` | Admin comped credits; `source_ref_id` = nil, note in metadata |

### 3.2 `credit_transfers` — Transfer Records

```sql
CREATE TABLE credit_transfers (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_role_id     UUID NOT NULL REFERENCES user_roles(id),
  to_user_role_id       UUID NOT NULL REFERENCES user_roles(id),
  amount_quarter_units  INTEGER NOT NULL CHECK (amount_quarter_units > 0),
  note                  VARCHAR(255),
  inserted_at           TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
  -- NO updated_at — immutable
);

CREATE INDEX credit_transfers_from_idx ON credit_transfers (from_user_role_id);
CREATE INDEX credit_transfers_to_idx ON credit_transfers (to_user_role_id);
```

A transfer atomically inserts:
1. One `credit_transfers` row
2. One `wool_credits` row with `source: "transfer_out"`, `delta: -N` for the sender
3. One `wool_credits` row with `source: "transfer_in"`, `delta: +N` for the recipient

All three writes occur inside a single `Repo.transaction/1`.

### 3.3 Elixir Schemas

```elixir
# lib/fun_sheep/credits/wool_credit.ex
defmodule FunSheep.Credits.WoolCredit do
  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(referral material_upload test_created transfer_in transfer_out redemption admin_grant)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wool_credits" do
    field :delta, :integer
    field :source, :string
    field :source_ref_id, :binary_id
    field :metadata, :map, default: %{}

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  def changeset(credit, attrs) do
    credit
    |> cast(attrs, [:user_role_id, :delta, :source, :source_ref_id, :metadata])
    |> validate_required([:user_role_id, :delta, :source])
    |> validate_inclusion(:source, @sources)
    |> validate_number(:delta, other_than: 0)
  end
end

# lib/fun_sheep/credits/credit_transfer.ex
defmodule FunSheep.Credits.CreditTransfer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credit_transfers" do
    field :amount_quarter_units, :integer
    field :note, :string

    belongs_to :from_user_role, FunSheep.Accounts.UserRole
    belongs_to :to_user_role, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  def changeset(transfer, attrs) do
    transfer
    |> cast(attrs, [:from_user_role_id, :to_user_role_id, :amount_quarter_units, :note])
    |> validate_required([:from_user_role_id, :to_user_role_id, :amount_quarter_units])
    |> validate_number(:amount_quarter_units, greater_than: 0)
    |> check_constraint(:from_user_role_id,
      name: :credit_transfers_no_self_transfer,
      message: "cannot transfer to yourself"
    )
  end
end
```

---

## 4. Business Logic — `FunSheep.Credits` Context

```
lib/fun_sheep/credits/
  credits.ex               # public API
  wool_credit.ex           # schema
  credit_transfer.ex       # schema
```

### 4.1 Public API

```elixir
defmodule FunSheep.Credits do
  # Returns integer balance in CREDITS (not quarter-units) for display
  @spec get_balance(user_role_id :: binary()) :: non_neg_integer()

  # Returns raw quarter-unit balance
  @spec get_balance_quarter_units(user_role_id :: binary()) :: non_neg_integer()

  # Returns full ledger for a teacher (for UI activity feed)
  @spec list_ledger(user_role_id :: binary(), opts :: keyword()) :: [WoolCredit.t()]

  # Award credit to a teacher from a specific source event (idempotent by source_ref_id)
  @spec award_credit(
    teacher_user_role_id :: binary(),
    source :: String.t(),
    quarter_units :: pos_integer(),
    source_ref_id :: binary() | nil,
    metadata :: map()
  ) :: {:ok, WoolCredit.t()} | {:error, :already_awarded} | {:error, Ecto.Changeset.t()}

  # Transfer N credits (full credits, not quarter-units) from teacher to another user
  @spec transfer_credits(
    from_user_role_id :: binary(),
    to_user_role_id :: binary(),
    credits :: pos_integer(),
    note :: String.t() | nil
  ) :: {:ok, CreditTransfer.t()} | {:error, :insufficient_balance} | {:error, :invalid_recipient} | {:error, Ecto.Changeset.t()}

  # Redeem N credits to extend own subscription
  @spec redeem_for_subscription(user_role_id :: binary(), credits :: pos_integer()) ::
    {:ok, Subscription.t()} | {:error, :insufficient_balance} | {:error, Ecto.Changeset.t()}
end
```

### 4.2 Idempotency for Award

`award_credit/5` queries for an existing row with the same `source_ref_id` before inserting. If found, returns `{:error, :already_awarded}`. This prevents double-awarding when Oban jobs retry.

```elixir
defp already_awarded?(source_ref_id) when not is_nil(source_ref_id) do
  Repo.exists?(from w in WoolCredit, where: w.source_ref_id == ^source_ref_id)
end
defp already_awarded?(_), do: false
```

### 4.3 Referral Batch Logic

Referral credits are trickier because they are awarded per **batch of 10**, not per individual student. The worker needs to:

1. Count total active students for the teacher.
2. Compute how many full batches of 10 have been crossed: `batches = div(total_students, 10)`.
3. Count how many referral credits have already been awarded: `awarded = count_awards(:referral, teacher_id)`.
4. If `batches > awarded`, award `(batches - awarded) * 4` quarter-units in one ledger entry.

The `source_ref_id` for referral entries is set to the `student_guardian.id` of the student who pushed the count into the next batch (the "milestone student"). This is used for idempotency.

---

## 5. Oban Workers

### 5.1 `CreditReferralCheckWorker`

**Trigger:** Enqueued when a `student_guardians` row transitions to `status: :active` (in `Accounts.accept_guardian_invite/1` and `Accounts.claim_guardian_invite_by_token/2`).

```elixir
defmodule FunSheep.Workers.CreditReferralCheckWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"teacher_user_role_id" => teacher_id, "student_guardian_id" => sg_id}}) do
    with {:ok, count} <- Credits.count_active_students(teacher_id),
         batches = div(count, 10),
         awarded = Credits.count_referral_awards(teacher_id),
         true <- batches > awarded do
      delta = (batches - awarded) * 4
      Credits.award_credit(teacher_id, "referral", delta, sg_id, %{student_count: count})
    else
      false -> :ok  # no new batch crossed
      err -> err
    end
  end
end
```

### 5.2 `CreditMaterialUploadWorker`

**Trigger:** Enqueued when `uploaded_materials` status transitions to `:processed` (inside the material processing pipeline, same place `ProcessCourseWorker` is enqueued).

```elixir
defmodule FunSheep.Workers.CreditMaterialUploadWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"uploaded_material_id" => material_id}}) do
    material = Materials.get_material!(material_id)
    uploader = Accounts.get_user_role!(material.user_role_id)

    if uploader.role == :teacher do
      Credits.award_credit(uploader.id, "material_upload", 2, material_id, %{})
    else
      :ok
    end
  end
end
```

Quarter-units = 2 (= 0.5 credit). Two uploads = 1 full credit.

### 5.3 `CreditTestCreatedWorker`

**Trigger:** Enqueued when a `test_schedules` row is inserted with a teacher as creator (in `Classrooms.create_test_schedule/2` or equivalent).

```elixir
defmodule FunSheep.Workers.CreditTestCreatedWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_schedule_id" => schedule_id}}) do
    schedule = Classrooms.get_test_schedule!(schedule_id)
    creator  = Accounts.get_user_role!(schedule.user_role_id)

    if creator.role == :teacher do
      Credits.award_credit(creator.id, "test_created", 1, schedule_id, %{})
    else
      :ok
    end
  end
end
```

Quarter-units = 1 (= 0.25 credit). Four test schedules = 1 full credit.

---

## 6. Subscription Extension

When credits are redeemed — either via `transfer_credits/4` (for student/teacher recipients) or `redeem_for_subscription/2` (self-redeem) — the billing layer is extended:

```elixir
defp extend_subscription(user_role_id, credits) do
  days = credits * 30
  sub = Billing.get_or_create_subscription(user_role_id)

  new_end =
    case sub.status do
      s when s in [:active] ->
        DateTime.add(sub.current_period_end, days, :day)
      _ ->
        DateTime.add(DateTime.utc_now(), days, :day)
    end

  sub
  |> Ecto.Changeset.change(%{
    plan: "monthly",
    status: "active",
    current_period_start: sub.current_period_start || DateTime.utc_now(),
    current_period_end: new_end
  })
  |> Repo.update()
end
```

Key points:
- If the subscription is `active`, extend `current_period_end` forward.
- If `expired` or `cancelled`, restart as a fresh active subscription from today.
- Set `plan: "monthly"` so the student gets unlimited tests for the gifted period.
- This does **not** touch Interactor Billing Server — credits are a FunSheep-native benefit and bypass Stripe entirely.

---

## 7. UI/UX Design

### 7.1 Teacher Dashboard — "Wool Credits" Section

New section in `TeacherDashboardLive` (or `TeacherLive`, whichever houses the teacher home).

```
┌────────────────────────────────────────────────────┐
│ 🧶 Wool Credits                    Balance: 3 cr   │
│                                                    │
│ Progress toward next credit:                       │
│  Students ████████░░ 8/10   (2 more to earn +1)   │
│  Materials ██░░░░░░░░ 1/2   (1 more to earn +1)   │
│  Tests     ███░░░░░░░ 3/4   (1 more to earn +1)   │
│                                                    │
│ Give a credit to:                                  │
│  [🔍 Search student or teacher…    ] [Give 1 cr]  │
│                                                    │
│ Activity                                           │
│  +1 cr  ← 10 students joined       Apr 20         │
│  +0.5cr ← Algebra textbook         Apr 18         │
│  –1 cr  → Jordan Smith (1 month)   Apr 15         │
│  +0.25  ← Chapter 4 quiz created   Apr 12         │
└────────────────────────────────────────────────────┘
```

**Interaction details:**
- Balance shows full credits (integer), e.g., "3 cr". Fractional balance ("3.5 cr") is shown as "3 cr 2/4" in the activity log but rounded to nearest 0.25 in the progress bars.
- Progress bars show how many actions until the next credit per category.
- Search box calls `Accounts.search_user_roles/2` filtered to `:student` or `:teacher` role. Students shown are limited to the teacher's own class (linked via `student_guardians`). Teachers shown are app-wide.
- "Give 1 cr" button disabled when balance < 1.
- On submit: confirm dialog "Give 1 Wool Credit (= 1 free month) to [Name]?" then call `Credits.transfer_credits/4`.
- Activity log shows last 20 ledger entries with human-readable descriptions.

### 7.2 Student Credit Notification

When a student receives a credit:
- In-app notification: "🎁 Your teacher gave you 1 free month of FunSheep! Tap to redeem."
- Email via `StudentCreditEmailWorker` (new worker, queue: `:notifications`).
- Student sees a "Redeem" button on their subscription page.

### 7.3 Redemption Flow (Student)

Route: existing `/subscription` page, new panel when `pending_credits > 0`.

```
╔══════════════════════════════════════════════════╗
║  🎁 Gift from your teacher!                      ║
║  You have 1 Wool Credit — worth 1 free month.   ║
║                                                  ║
║  [Redeem now — unlock unlimited tests for 30d]  ║
╚══════════════════════════════════════════════════╝
```

Redeeming calls `Credits.redeem_for_subscription/2` on the student's behalf and redirects to a success state.

### 7.4 Progress Nudges

When a teacher views their dashboard and is close to earning a batch credit, show an actionable prompt:
- "You have 8 active students — invite 2 more to earn a free month."
- "You've uploaded 1 textbook — add 1 more to earn a credit."
- "You've created 3 test schedules — add 1 more to earn a credit."

These are computed at mount time from the same balance query and require no additional DB calls.

---

## 8. Migration Plan

### Migration 1 — Tables

```elixir
defmodule FunSheep.Repo.Migrations.CreateWoolCreditTables do
  use Ecto.Migration

  def change do
    create table(:wool_credits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all), null: false
      add :delta, :integer, null: false
      add :source, :string, null: false
      add :source_ref_id, :binary_id
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end

    create index(:wool_credits, [:user_role_id])
    create index(:wool_credits, [:source_ref_id], where: "source_ref_id IS NOT NULL")

    create table(:credit_transfers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_user_role_id, references(:user_roles, type: :binary_id), null: false
      add :to_user_role_id, references(:user_roles, type: :binary_id), null: false
      add :amount_quarter_units, :integer, null: false
      add :note, :string, limit: 255
      timestamps(updated_at: false)
    end

    create index(:credit_transfers, [:from_user_role_id])
    create index(:credit_transfers, [:to_user_role_id])

    create constraint(:credit_transfers, :positive_amount, check: "amount_quarter_units > 0")
  end
end
```

### Migration 2 — Backfill Existing Teachers (Optional)

Optionally backfill credits for teachers who already have students/materials before this feature ships. Run as a one-off Mix task, not a migration, to keep migration files fast.

```bash
mix funsheep.backfill_teacher_credits
```

The task iterates all teachers, runs the same batch logic as the workers, and inserts ledger entries with `source: "admin_grant"` and a backfill note in metadata.

---

## 9. Implementation Phases

### Phase 1 — Core Ledger & Earning (Sprint 1)

| # | Task | Owner |
|---|------|-------|
| 1 | Migration: `wool_credits`, `credit_transfers` | Backend |
| 2 | `FunSheep.Credits` context: `award_credit/5`, `get_balance/1`, `get_balance_quarter_units/1`, `list_ledger/2` | Backend |
| 3 | `CreditReferralCheckWorker` + wire into `accept_guardian_invite` / `claim_guardian_invite_by_token` | Backend |
| 4 | `CreditMaterialUploadWorker` + wire into material processing pipeline | Backend |
| 5 | `CreditTestCreatedWorker` + wire into test schedule creation | Backend |
| 6 | Unit tests for context and workers | Backend |

### Phase 2 — Transfer & Redemption (Sprint 2)

| # | Task | Owner |
|---|------|-------|
| 1 | `Credits.transfer_credits/4` + subscription extension | Backend |
| 2 | `Credits.redeem_for_subscription/2` | Backend |
| 3 | `StudentCreditEmailWorker` | Backend |
| 4 | Teacher dashboard: "Wool Credits" section in `TeacherDashboardLive` | Frontend |
| 5 | Student redemption UI in `SubscriptionLive` | Frontend |
| 6 | In-app notification for student credit receipt | Frontend |
| 7 | Integration tests for full transfer → extend flow | Backend |
| 8 | Visual verify via Playwright | Frontend |

### Phase 3 — Shout Outs Integration (Sprint 3)

| # | Task | Owner |
|---|------|-------|
| 1 | `most_generous_teacher` category in `ComputeShoutOutsWorker` | Backend |
| 2 | Teacher shout out card in Flock page "Shout Outs" tab | Frontend |
| 3 | Backfill task for existing teachers | Backend |

---

## 10. Testing Requirements

### Unit Tests

```
test/fun_sheep/credits/credits_test.exs
  - get_balance returns 0 for new teacher
  - award_credit inserts ledger entry and updates balance
  - award_credit is idempotent (same source_ref_id → :already_awarded)
  - referral batches: 9 students → 0 credits, 10 → 1, 19 → 1, 20 → 2
  - transfer_credits fails with :insufficient_balance when balance too low
  - transfer_credits atomically writes credit_transfer + two wool_credits rows
  - redeem_for_subscription extends active subscription by 30 days
  - redeem_for_subscription creates new active subscription if none exists
```

### Worker Tests

```
test/fun_sheep/workers/credit_referral_check_worker_test.exs
  - awards credit when 10th student accepts
  - does not double-award if job retries
  - no-op when fewer than 10 students

test/fun_sheep/workers/credit_material_upload_worker_test.exs
  - awards 2 quarter-units for teacher uploader
  - no-op for student or parent uploader
  - idempotent on retry

test/fun_sheep/workers/credit_test_created_worker_test.exs
  - awards 1 quarter-unit for teacher creator
  - no-op for non-teacher creator
```

### LiveView Tests

```
test/fun_sheep_web/live/teacher_dashboard_live_test.exs
  - renders "Wool Credits" section with correct balance
  - renders progress bars with correct counts
  - search box filters to class students + all teachers
  - give credit button disabled when balance 0
  - give credit button submits and updates balance
  - activity log renders ledger entries
```

---

## 11. Open Questions

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | **Redemption: automatic or explicit?** When a teacher transfers a credit to a student, does the month apply immediately, or does the student click "Redeem"? | Explicit — gives the student a gift-opening moment and lets them hold credits to use later. |
| 2 | **Transfer scope: any teacher or only within school?** Can a teacher gift to any teacher in the system, or only teachers at the same school? | Any teacher in Phase 1 for simplicity; restrict by school in Phase 2 if abuse surfaces. |
| 3 | **Backfill policy for existing teachers?** Should teachers who already have 10+ students get credit retroactively? | Yes — run as one-off Mix task, capped at 5 credits per teacher to avoid giving away too much immediately. |
| 4 | **Material quality gate?** Should all uploaded materials earn credits, or only materials that pass validation? | Only `:processed` materials (already validated by pipeline) to prevent gaming with junk uploads. |
| 5 | **Integration-synced tests?** Do tests imported from Canvas/Google Classroom count toward the 4-test batch? | Yes, same rate — teacher's effort to connect an integration is worth rewarding. |
| 6 | **Credit display name?** "Wool Credits" fits the sheep theme. Is this the final name or should the UI also say "1 free month"? | Show both: "1 Wool Credit (= 1 free month)" in the give-credit flow; "Wool Credits" as the section header. |

---

## 12. Non-Goals

- Credits expiring — not in scope.
- Cash value / real-money redemption — subscription extension only.
- Student-to-student gifting — teachers only earn and send.
- Parent-earned credits — parents do not earn credits.
- Interactor Billing Server integration for credit redemption — handled natively in `billing.ex`.
- Credit marketplace or auction — not in scope.

---

## 13. Key Architecture Invariants

1. **`wool_credits` is append-only** — never update or delete rows; derive all state from `SUM(delta)`.
2. **Transfers are atomic** — `credit_transfer` + two `wool_credits` rows in one `Repo.transaction`.
3. **Award jobs are idempotent** — always check `source_ref_id` before inserting.
4. **Balance never goes negative** — enforce in `transfer_credits/4` and `redeem_for_subscription/2` before writing.
5. **Subscription extension is FunSheep-native** — do not call Interactor Billing Server; extend `current_period_end` directly.
6. **Teachers only** — `award_credit` callers must verify `user_role.role == :teacher` before calling; workers enforce this at the job level.
