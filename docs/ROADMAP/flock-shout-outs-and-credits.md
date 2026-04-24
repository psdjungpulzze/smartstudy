# Flock Shout Outs & Teacher Credits

**Status:** Planning  
**Date:** 2026-04-24  
**Scope:** Gamification › Social Recognition + Teacher Incentive Economy

---

## Overview

Two interlocked features that make the Flock page a place students and teachers actually want to visit:

1. **Shout Out Section** — weekly spotlight cards on the Flock page that name the student who did the most of each notable activity (tests taken, textbooks uploaded, tests created, etc.). Students become the star; peers see who is grinding.

2. **Teacher Credit Economy** — teachers accumulate "Wool Credits" by growing their classroom and contributing content. Credits are transferable and unlock extra subscription months for the recipient. A shout out category calls out the most generous teacher.

These features are additive to the existing XP/streak gamification — they layer social recognition on top of the FP economy rather than replacing it.

---

## Current Architecture (Relevant Parts)

- **Flock leaderboard** (`LeaderboardLive`, route `/leaderboard`) has two tabs: *Leaderboard* and *Achievements*. The new Shout Out tab goes here.
- **XP economy** lives in `xp_events` (immutable audit trail) and `gamification.ex`.
- **Uploaded materials** tracked in `uploaded_materials` (content uploads by any role).
- **Test schedules** (`test_schedules`) cover teacher-created and integration-synced assessments.
- **Student–Teacher relationships** managed via `student_guardians` (status: `:active`).
- **Billing** tracked in `subscriptions` (current month, plan).

---

## Feature 1 — Shout Out Section

### 1.1 Categories

| ID | Label | Icon | Metric | Source |
|----|-------|------|--------|--------|
| `most_xp` | Most Active | ⚡ | FP earned this week | `xp_events.inserted_at` |
| `most_tests_taken` | Test Taker | 🎯 | Assessments + quick tests completed | `question_attempts` count per session |
| `most_textbooks_uploaded` | Bookworm | 📚 | Uploaded materials processed | `uploaded_materials.status = :processed` |
| `most_tests_created` | Test Builder | ✍️ | Test schedules created (manual + integration) | `test_schedules.inserted_at` |
| `longest_streak` | Streak Star | 🔥 | Current streak days | `streaks.current_streak` |
| `most_generous_teacher` | Giving Back | 🎁 | Wool Credits given to others | `credit_transfers.from_user_role_id` (teacher role only) |

The `most_generous_teacher` category is inactive until Phase 2 (Credits) ships.

### 1.2 Computation Model

Shout outs are **pre-computed** once per week (Sunday 23:55 UTC) and stored in a `shout_outs` table. This avoids expensive real-time aggregations on the Flock page.

```
shout_outs
  id              :binary_id PK
  category        :string          -- one of the category IDs above
  user_role_id    :binary_id FK → user_roles
  period          :string          -- "weekly" | "monthly"
  period_start    :date
  period_end      :date
  metric_value    :integer         -- raw count/score for display
  inserted_at     :utc_datetime
```

Only one active record per `(category, period)` at a time. The computation job soft-retires the previous winner by leaving historical rows (no deletion).

### 1.3 Oban Job

`FunSheep.Workers.ComputeShoutOutsWorker`

- Scheduled: every Sunday 23:55 UTC via Oban cron
- Queries each category independently (6 queries → 6 rows inserted)
- Wraps in a transaction; if any query fails the whole batch is skipped and the job retries
- Categories with no eligible data (e.g., nobody uploaded anything that week) skip gracefully — no winner is recorded

### 1.4 UI — New "Shout Outs" Tab in LeaderboardLive

Add a third tab alongside *Leaderboard* and *Achievements*.

**Layout:**

```
┌────────────────────────────────────────────────────────────┐
│  ⭐  Stars of the Week  ⭐                                  │
│  Week of Apr 21 – Apr 27                                   │
├────────────┬────────────┬────────────┬────────────────────┤
│  [Avatar]  │  [Avatar]  │  [Avatar]  │     …              │
│  ⚡Most    │  🎯Test    │  📚Books   │                    │
│  Active    │  Taker     │  worm      │                    │
│  Jordan S. │  Maya L.   │  Kai P.    │                    │
│  1,420 FP  │  18 tests  │  5 books   │                    │
├────────────┴────────────┴────────────┴────────────────────┤
│  Want to appear here? Keep learning — the week resets      │
│  every Monday!                                             │
└────────────────────────────────────────────────────────────┘
```

- Shout out cards are pill-shaped, colour-coded by category, with a subtle shimmer animation.
- If the current user is a winner, their card pulses green (`#4CD964`) and shows a "That's you! 🎉" badge.
- Each card links to the winner's public proof card (if they have one) or no-op if private.
- Empty state: "No data yet for this week — be the first to earn a shout out!"

### 1.5 Scope Boundaries (Phase 1)

- Winners are visible to **all peers in the user's flock** (same peer matching as leaderboard).
- No push notification for winning — ambient discovery only in Phase 1 (notifications in Phase 2).
- No opt-out in Phase 1 (add in Phase 2 if students request privacy).

---

## Feature 2 — Teacher Wool Credit Economy

> **Full implementation spec:** `docs/ROADMAP/funsheep-teacher-credit-system.md` — that document is the canonical reference for schema, Oban workers, context API, migration SQL, and testing requirements. The sections below summarise the credit economy as it integrates with Shout Outs; read the dedicated doc before implementing.

### 2.1 Credit Rules

**Earning credits (teachers only):**

| Trigger | Credits Awarded | Notes |
|---------|----------------|-------|
| 10 students accept invite | +1 credit | Counted per batch of 10; partial batches don't award yet |
| 1 textbook/material uploaded and processed | +0.5 credit | Rounds up at 1.0; i.e., 2 uploads = 1 credit |
| 1 test schedule created (manual or integration-synced) | +0.25 credit | 4 tests = 1 credit |

Internally credits are stored as **integers in quarter-units** (1 credit = 4 units) to avoid floats.

**Spending / transferring credits:**

| Action | Cost | Effect |
|--------|------|--------|
| Give 1 credit to a student | 1 credit | Extends student subscription by 1 month |
| Give 1 credit to another teacher | 1 credit | Adds 1 credit to teacher's balance |
| Redeem for own subscription | 1 credit | Extends own subscription by 1 month |

### 2.2 Schema

```
wool_credits (immutable event log — same pattern as xp_events)
  id              :binary_id PK
  user_role_id    :binary_id FK → user_roles  -- whose balance changes
  delta           :integer                    -- positive = earn, negative = spend (quarter-units)
  source          :string                     -- :referral | :textbook | :test_created | :transfer_in | :transfer_out | :redemption
  source_ref_id   :binary_id nullable         -- FK to student_guardian, uploaded_material, test_schedule, or credit_transfer
  metadata        :map default: {}
  inserted_at     :utc_datetime
  -- NO updated_at (immutable)

credit_transfers
  id              :binary_id PK
  from_user_role_id :binary_id FK → user_roles
  to_user_role_id   :binary_id FK → user_roles
  amount_credits    :integer                  -- in quarter-units
  note              :string nullable
  inserted_at       :utc_datetime
  -- NO updated_at
```

**Balance computation:** `SELECT SUM(delta) FROM wool_credits WHERE user_role_id = ?`. No denormalized balance column — keeps the audit trail authoritative.

### 2.3 Credit Earning Triggers (Oban Jobs)

| Job | Trigger | Logic |
|-----|---------|-------|
| `CreditReferralCheckWorker` | `student_guardians` row status → `:active` | Count teacher's total active students; award credits for each new batch of 10 crossed |
| `CreditUploadWorker` | `uploaded_materials` status → `:processed` | Award 2 quarter-units (0.5 credit) per material to the uploader if they are a teacher role |
| `CreditTestCreatedWorker` | `test_schedules` inserted | Award 1 quarter-unit (0.25 credit) to schedule creator if teacher role |

Each job checks if the specific event has already been credited (via `wool_credits.source_ref_id`) to prevent double-awarding on retries.

### 2.4 Transfer UI (Teacher Dashboard)

New section in `TeacherDashboardLive` — "Wool Credits":

```
┌─────────────────────────────────────────────────┐
│  🧶 Wool Credits                       Balance: 3│
│                                                  │
│  You've helped 30 students this month.           │
│                                                  │
│  Give a credit:  [Student name search…]  [Send]  │
│                  or  [Teacher name search…]       │
│                                                  │
│  Recent activity:                                │
│  + 1.0 cr  ← 10 students joined   Apr 20        │
│  + 0.5 cr  ← Algebra textbook     Apr 18        │
│  – 1.0 cr  → Jordan Smith (1 mo.) Apr 15        │
└─────────────────────────────────────────────────┘
```

- Search box uses existing `Accounts.search_user_roles/2`.
- Validation: cannot give more than current balance; recipient must be active.
- On submit → inserts `credit_transfer` + two `wool_credits` rows (−N for sender, +N for recipient) in a transaction → triggers subscription extension via `billing.ex`.

### 2.5 Subscription Extension

When a student or teacher receives a credit that is redeemed for a month:

1. Check `subscriptions` for the user.
2. If active: extend `current_period_end` by 30 days.
3. If expired/none: create a new subscription starting today + 30 days.
4. Log in `billing.ex` audit with source `:wool_credit`.

This does **not** touch Interactor Billing Server — credits are a FunSheep-native benefit layer.

### 2.6 Most Generous Teacher Shout Out

The `most_generous_teacher` shout out category aggregates:

```sql
SELECT from_user_role_id, SUM(amount_credits) as total_given
FROM credit_transfers
WHERE inserted_at >= period_start
  AND inserted_at < period_end
  AND from_user_role_id IN (SELECT id FROM user_roles WHERE role = 'teacher')
GROUP BY from_user_role_id
ORDER BY total_given DESC
LIMIT 1
```

Displayed in the Shout Outs tab of the Flock page alongside student shout outs.

---

## Implementation Phases

### Phase 1 — Student Shout Outs (no credits) ✦ 1 sprint

| # | Task | Notes |
|---|------|-------|
| 1 | Migration: create `shout_outs` table | |
| 2 | Gamification context: `compute_shout_outs/1`, `get_current_shout_outs/1` | Queries for 5 student categories |
| 3 | Oban worker: `ComputeShoutOutsWorker` | Sunday 23:55 UTC cron |
| 4 | LeaderboardLive: add "Shout Outs" tab | 3rd tab, shimmer card component |
| 5 | Shout out card component | Avatar, category, metric, "That's you!" highlight |
| 6 | Tests: unit (computation queries), LiveView (tab renders, empty state) | |
| 7 | Visual verify via Playwright | |

### Phase 2 — Teacher Credit Economy ✦ 1–2 sprints

| # | Task | Notes |
|---|------|-------|
| 1 | Migrations: `wool_credits`, `credit_transfers` | |
| 2 | Context: `FunSheep.Credits` | `get_balance/1`, `transfer_credits/3`, `redeem_for_month/2` |
| 3 | Oban workers: referral, upload, test-created credit jobs | |
| 4 | Billing integration: `extend_subscription_from_credit/2` | |
| 5 | TeacherDashboardLive: "Wool Credits" section | Balance, give form, recent activity |
| 6 | `most_generous_teacher` category in `ComputeShoutOutsWorker` | |
| 7 | Shout out tab: render teacher card alongside student cards | |
| 8 | Tests | |
| 9 | Visual verify | |

### Phase 3 — Notifications & Privacy (future)

- Push notification to winner when shout out is computed ("You're the Streak Star this week! 🔥")
- Opt-out toggle in user settings (privacy: hide me from shout outs)
- Month-level shout outs alongside weekly
- Credit gifting via shareable link

---

## Open Questions

1. **Flock scope for shout outs:** Should winners be from the user's personal flock (≤30 peers) or school-wide or app-wide? School-wide is more exciting but may be harder to attain for new users. Recommendation: school-wide for Phase 1, add flock-scoped as an option later.

2. **Credit redemption flow:** Should credit-to-month conversion be automatic on transfer, or should the recipient explicitly redeem it? Automatic is simpler; explicit gives students agency and allows gifting to others. Recommendation: explicit redemption via a "Redeem" button.

3. **Tie-breaking:** What if two students have the same metric? Tie-break by `inserted_at ASC` (first to reach the score wins) or show both? Recommendation: first-to-reach for simplicity.

4. **Credit unit naming:** "Wool Credits" fits the sheep theme but may confuse teachers expecting standard subscription language. Should the UI also say "1 month of FunSheep"? Recommendation: show both — "1 Wool Credit (= 1 free month for any student)".

5. **Integration-created tests:** Tests synced from Canvas/Google Classroom via `integrations.ex` become `test_schedules`. Should these count toward the teacher's `most_tests_created` metric and credit earning? Recommendation: yes, with same rate as manual tests.

---

## Non-Goals (explicit exclusions)

- Leaderboard for parents — not planned.
- Credits expiring — credits don't expire in Phase 1 or 2.
- Cash-out or real-money redemption — FunSheep credits are subscription-only benefits.
- Student-to-student credit gifting — students cannot earn or transfer credits (teachers only).
- Integration with Interactor Billing Server for credit redemption — subscription extension is handled directly in FunSheep's `billing.ex`.
