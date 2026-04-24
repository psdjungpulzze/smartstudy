# FunSheep — School Course Catalog & One-Click Enrollment

> **Implementation prompt.** Paste into a fresh Claude Code session inside
> `/home/pulzze/Documents/GitHub/personal/funsheep/`. Read every section before
> writing a line of code — the UX strategy and the schema decisions are both
> load-bearing.

**Status**: Planning
**Scope**: Student onboarding enhancement, course catalog discovery, enrollment
**Depends on**: `user_roles`, `schools`, `courses`, `test_schedules` (all exist)

---

## 0. The Problem This Solves

Students are reactive. Left to themselves they don't create courses, schedule
tests, or build a study plan — so the product feels empty after registration.
Teachers create the courses; students need a path from "just registered" to
"already taking practice tests" in under two minutes.

**The solution:** After a student sets their school and grade, FunSheep
immediately shows them every course already loaded for their school and grade.
One click per course adds it to their list. From there they're one more click
from taking their first practice session.

---

## 1. What Already Exists (Do NOT Rebuild)

| Concern | Where | Notes |
|---|---|---|
| Student schema | `FunSheep.Accounts.UserRole` | Has `grade` (string) and `school_id` (FK). Already the right place. |
| School schema & hierarchy | `FunSheep.Geo.School` | `lowest_grade`, `highest_grade`, `has_many :courses`. |
| Grade list + nearby logic | `FunSheep.Courses` | `@grade_order`, `nearby_grades/1` (±1 grade), `list_nearby_courses/3`. |
| Course schema | `FunSheep.Courses.Course` | `grade`, `school_id`, `created_by_id`, `subject`. Already indexed. |
| Test schedule | `FunSheep.Assessments.TestSchedule` | Current implicit "enrollment" mechanism. |
| School search | `FunSheep.Geo` | Look for `search_schools/1` or similar — if absent, add it. |
| Auth via Interactor | `FunSheep.Interactor.Auth` + `Client` | Do not touch. |
| Parent onboarding | `FunSheepWeb.ParentOnboardingLive` | Collects child grade — different flow, do not merge. |
| Teacher onboarding | `FunSheepWeb.TeacherOnboardingLive` | Creates courses — teachers feed the catalog students browse. |
| Dashboard | `FunSheepWeb.DashboardLive` | Add enrollment CTA / empty state here if profile is incomplete. |

---

## 2. Schema Changes

### 2a. `student_courses` — Explicit Enrollment Table

Currently "enrollment" is implicit: a student is associated with a course only
via `test_schedules`. That makes it impossible to track interest before a test
exists. Add a lightweight enrollment table.

```elixir
schema "student_courses" do
  belongs_to :user_role, FunSheep.Accounts.UserRole      # the student
  belongs_to :course, FunSheep.Courses.Course

  field :status, Ecto.Enum,
    values: [:active, :dropped, :completed],
    default: :active

  field :enrolled_at, :utc_datetime
  field :source, Ecto.Enum,
    values: [:self_enrolled, :onboarding, :guardian_assigned, :teacher_assigned],
    default: :self_enrolled

  timestamps(type: :utc_datetime)
end
```

Indexes:
- `unique_index(:student_courses, [:user_role_id, :course_id])`
- `index(:student_courses, [:user_role_id, :status])`
- `index(:student_courses, [:course_id])`

Migration: additive only. Existing relationships (via `test_schedules`) remain
valid — a student may have a test schedule for a course without a `student_courses`
row, and vice versa. The context layer must handle both.

### 2b. `user_roles` — Onboarding State

Add a field to track whether the student has completed the post-registration
setup wizard. Without this, every login prompts re-onboarding.

```elixir
# Migration: add to user_roles
add :onboarding_completed_at, :utc_datetime, null: true
```

A `nil` value means the wizard was never completed. A non-nil datetime means it
was completed (and when, for analytics). Do not use a boolean — the timestamp
is more useful.

---

## 3. New Context Functions

### `FunSheep.Courses`

```elixir
# List courses at a school for a specific grade (exact match + optional adjacent)
@spec list_courses_for_student(school_id :: Ecto.UUID.t(), grade :: String.t(), opts :: keyword) ::
        [Course.t()]
def list_courses_for_student(school_id, grade, opts \\ []) do
  # opts: adjacent_grades: true (default true), limit: 50
end

# List courses available nearby (same grade, any school) — fallback for empty schools
@spec list_courses_by_grade(grade :: String.t(), opts :: keyword) :: [Course.t()]
def list_courses_by_grade(grade, opts \\ []) do
  # used when school has no courses yet
end
```

### `FunSheep.Enrollments`

New context module (thin — no business logic, just DB operations):

```elixir
defmodule FunSheep.Enrollments do
  # Enroll a student in a course (idempotent — no error on duplicate)
  @spec enroll(user_role_id :: Ecto.UUID.t(), course_id :: Ecto.UUID.t(), source :: atom) ::
          {:ok, StudentCourse.t()} | {:error, Ecto.Changeset.t()}
  def enroll(user_role_id, course_id, source \\ :self_enrolled)

  # Bulk enroll — used during onboarding when student selects multiple courses at once
  @spec bulk_enroll(user_role_id :: Ecto.UUID.t(), course_ids :: [Ecto.UUID.t()], source :: atom) ::
          {:ok, [StudentCourse.t()]} | {:error, term}
  def bulk_enroll(user_role_id, course_ids, source \\ :onboarding)

  # List enrollments for a student (with course preloaded)
  @spec list_for_student(user_role_id :: Ecto.UUID.t(), opts :: keyword) :: [StudentCourse.t()]
  def list_for_student(user_role_id, opts \\ [])

  # Check if enrolled
  @spec enrolled?(user_role_id :: Ecto.UUID.t(), course_id :: Ecto.UUID.t()) :: boolean
  def enrolled?(user_role_id, course_id)

  # Drop a course
  @spec drop(user_role_id :: Ecto.UUID.t(), course_id :: Ecto.UUID.t()) ::
          {:ok, StudentCourse.t()} | {:error, :not_found}
  def drop(user_role_id, course_id)
end
```

### `FunSheep.Geo`

Add school search if absent:

```elixir
@spec search_schools(query :: String.t(), opts :: keyword) :: [School.t()]
def search_schools(query, opts \\ []) do
  # opts: limit: 20, country_id: ..., state_id: ...
  # Use ilike on name, min 2 chars to trigger
end
```

### `FunSheep.Accounts`

Add:

```elixir
@spec complete_onboarding(user_role :: UserRole.t()) ::
        {:ok, UserRole.t()} | {:error, Ecto.Changeset.t()}
def complete_onboarding(user_role) do
  user_role
  |> Ecto.Changeset.change(onboarding_completed_at: DateTime.utc_now())
  |> Repo.update()
end

@spec onboarding_complete?(user_role :: UserRole.t()) :: boolean
def onboarding_complete?(user_role), do: !is_nil(user_role.onboarding_completed_at)
```

---

## 4. UX Flow — Student Onboarding Wizard

### Entry Points

1. **Post-registration redirect** — after `register_live.ex` creates the account,
   redirect to `/onboarding/student` instead of `/dashboard`.
2. **Dashboard nudge** — if a logged-in student has `onboarding_completed_at: nil`,
   show a dismissible banner: *"Set up your profile to see courses at your school →"*
   linking to `/onboarding/student`.

### Wizard Steps (`StudentOnboardingLive`)

**Route**: `live "/onboarding/student", StudentOnboardingLive, :index`
Put in the authenticated `live_session` — the student must be logged in.

---

#### Step 1 — Display Name & Grade

Fields:
- `display_name` (string, required, min 2 chars) — pre-filled from registration if available
- `grade` (select, required) — `~w(K 1 2 3 4 5 6 7 8 9 10 11 12 College Adult)`

No school selection here — keep this step fast. The student can skip straight
through by hitting **Next**.

---

#### Step 2 — School (Optional but Encouraged)

Two paths:

**Path A — Search and select:**
- Type-ahead search input (≥2 chars fires `Geo.search_schools/1`)
- Results shown as a list of school cards: name + city + type badge
- Student clicks one to select
- Shows confirmation: *"Liberty High School — Oakland, CA"* with a change link

**Path B — Skip:**
- *"I'll add my school later"* link at the bottom
- This is a valid path — not everyone knows their school's exact name
- Skipping sets `school_id: nil` and continues

**When school is selected and has no courses:** show a prominent creation prompt
directly on this step — not a passive note. The student should feel the next
action is clear (see §5 Empty State A for the exact treatment). The search/select
still succeeds; the creation prompt appears instead of a course list.

---

#### Step 3 — Course Catalog

This is the core of the feature. Two modes depending on whether courses exist.

##### Mode A — Courses exist at the school/grade

Show a catalog grouped by subject.

**Query logic (in order of preference):**
1. Courses at the student's school for their exact grade
2. Courses at the student's school for adjacent grades (±1)
3. Courses at any school for their exact grade — if school is nil or school has no courses
4. If truly empty: show empty state (see §5)

**Always show a "Create a course" card** at the bottom of each subject group
and at the very bottom of the catalog, so creation is always one click away
even when courses do exist.

Display:
- Group courses by `subject` (Mathematics, English Language Arts, Science, etc.)
- Each course card shows: course name, grade label, chapter count, question count, teacher name
- A green **Add** button per card (becomes **Added ✓** after clicking)
- A **Select All** shortcut per subject group
- **[+ Create a course]** card at the bottom of the full list

**State management:**
- `selected_course_ids` — a `MapSet` in socket assigns, toggled per card click
- Persisted only on **Continue** — do not write to DB on every toggle
- On **Continue**: call `Enrollments.bulk_enroll/3` with `source: :onboarding`

##### Mode B — No courses at this school/grade

Skip to the full empty-state screen described in §5 Empty State A.
This is NOT a fallback buried at the bottom — it replaces the catalog view
entirely and makes creation/invitation the primary action.

---

#### Step 4 — Done

Summary screen:
- *"You're all set, [display_name]!"*
- List of courses just added (with subject icons); if none selected, show a
  single CTA: **"Create your first course →"**
- Primary CTA: **Start Practicing →** — goes to the first enrolled course's practice session
- Secondary: **Go to Dashboard**

On mount of this step, call `Accounts.complete_onboarding/1` to set the
timestamp.

---

## 5. Empty State Strategy

When a school has no courses, **creation and invitation are the primary actions**,
not an afterthought. The fallback to other-school courses is secondary — shown
as an option, not the headline.

### Empty State A — School selected, no courses (PRIMARY CASE)

This replaces Step 3 entirely when the school has zero courses.

```
┌─────────────────────────────────────────────────────────┐
│  🎉 You're the first from [School Name] on FunSheep!   │
│                                                         │
│  No courses have been added yet — you can change that.  │
│                                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  📖 Create a course  │  │  ✉️ Invite a teacher  │    │
│  │                      │  │                      │    │
│  │  Upload your         │  │  Your teacher can    │    │
│  │  textbook or add     │  │  add all the courses │    │
│  │  a subject manually. │  │  for your class.     │    │
│  │                      │  │                      │    │
│  │  [Create Course →]   │  │  [Invite Teacher →]  │    │
│  └──────────────────────┘  └──────────────────────┘    │
│                                                         │
│  ── or browse courses from other schools ──             │
│                                                         │
│  [Browse Grade [X] courses from other schools ↓]        │
└─────────────────────────────────────────────────────────┘
```

**Behavior:**
- **[Create Course →]** — saves wizard progress and redirects to
  `/courses/new?onboarding=true&school_id=...&grade=...` with pre-filled
  school and grade. After course creation, returns to wizard Step 4 (Done).
- **[Invite Teacher →]** — opens an inline email form. Submits via
  `Accounts.invite_guardian/3` with `relationship_type: :teacher`. Shows
  success: *"Invite sent to [email]. We'll notify you when they join."*
  Then continues to wizard Step 4 (Done) — student isn't blocked waiting
  for the teacher.
- **[Browse Grade X courses from other schools]** — expands an inline list
  of courses from any school at this grade. These are clearly labelled
  *"From [School Name]"*. The student can add them as a stopgap.
  Do NOT collapse the creation CTAs when this expands — keep them visible.

**Copy strategy:** "You're the first from [School]" is intentionally positive
framing. It signals opportunity, not failure. Avoid "No courses found" —
that reads as a dead end.

### Empty State B — No grade set

Do not advance to Step 3. Validate grade as required in Step 1 and block
progression until it's selected.

### Empty State C — No school set (wizard reached Step 3 via skip)

Show the grade-wide catalog from any school, with a subtle banner:
*"Add your school in Settings to see courses just for [School Name]."*
Creation CTA is still present at the bottom.

### Empty State D — No courses exist on the entire platform

Treat the same as Empty State A, but skip the "from other schools" expansion
option (there is nothing to show). The two creation cards are the only actions.

```
You're one of the first students on FunSheep!

Create the first course and start practicing today.
Or invite your teacher — they can build out your whole class in minutes.

[Create Course →]   [Invite Teacher →]

[Go to Dashboard →]  (secondary link, not a button)
```

Set `onboarding_completed_at` even here — never trap the student in the wizard.

---

## 6. Dashboard Integration

After onboarding, the Dashboard must show enrolled courses immediately.

### If onboarding complete and enrollments exist

Show an **"My Courses"** section above the existing upcoming-tests card:

- Horizontal scroll card row on mobile; 3-column grid on desktop
- Each card: course name, subject color stripe, chapter count, readiness badge (if any test exists)
- **+ Add More Courses** card at the end → `/courses/search`

### If onboarding complete but no enrollments (student skipped or school was empty)

Show an action card — not a passive banner — with two equal-weight options:

```
┌───────────────────────────────────────────────────────┐
│  Ready to start practicing?                           │
│                                                       │
│  [Browse courses at my school]  [Create a course +]  │
│                                                       │
│  or  [Invite my teacher →]  (link, not button)       │
└───────────────────────────────────────────────────────┘
```

This is shown above the test schedule section until the student has at least
one enrolled course. Once they enroll in one course, it disappears.

### If onboarding NOT complete (`onboarding_completed_at: nil`)

Show a prominent inline card as the #1 dashboard item:

```
┌───────────────────────────────────────────────────────┐
│  See courses at your school — takes 2 minutes         │
│                                                       │
│  [Get Started →]                                      │
└───────────────────────────────────────────────────────┘
```

This does NOT auto-redirect. It disappears once `onboarding_completed_at` is set.

---

## 7. Course Search Page Enhancement

`CourseSearchLive` already exists. Two additions:

1. **Enrolled badge** — if the student is enrolled in a course (via `Enrollments.enrolled?/2`),
   show a green "Enrolled" badge on the card instead of an "Add" button.

2. **"Your School" filter** — add a prominent filter chip at the top:
   *"My school ([School Name])"* — pre-selected by default when the student
   has a school set. Clicking removes the filter to show all.

No full rebuild — extend what's there.

---

## 8. File-by-File Plan

### Migrations (in order)

1. `priv/repo/migrations/{ts}_create_student_courses.exs` — new enrollment table
2. `priv/repo/migrations/{ts+1}_add_onboarding_completed_at_to_user_roles.exs` — new field

### Schemas & Contexts

3. `lib/fun_sheep/enrollments/student_course.ex` — new schema
4. `lib/fun_sheep/enrollments.ex` — new context
5. `lib/fun_sheep/courses.ex` — add `list_courses_for_student/3`, `list_courses_by_grade/2`
6. `lib/fun_sheep/geo.ex` — add `search_schools/2` if absent
7. `lib/fun_sheep/accounts.ex` — add `complete_onboarding/1`, `onboarding_complete?/1`

### LiveViews

8. `lib/fun_sheep_web/live/student_onboarding_live.ex` — new, 4-step wizard
9. `lib/fun_sheep_web/live/student_onboarding_live.html.heex` — new
10. `lib/fun_sheep_web/live/dashboard_live.ex` — extend for enrolled courses + incomplete-onboarding CTA
11. `lib/fun_sheep_web/live/course_search_live.ex` — extend with enrolled badge + school filter

### Router

12. `lib/fun_sheep_web/router.ex` — add `live "/onboarding/student", StudentOnboardingLive, :index`
    in the authenticated `live_session`. Redirect post-registration here.

### Register Flow

13. `lib/fun_sheep_web/live/register_live.ex` — change the success redirect from
    `/dashboard` to `/onboarding/student` for new student registrations.

### Teacher Invite from Onboarding

14. Reuse `Accounts.invite_guardian/3` with `relationship_type: :teacher` for the
    "Invite Teacher" CTA in Empty State A. The wizard collects only an email address
    (one field, inline, no modal required). On success:
    - Show *"Invite sent to [email]. We'll let you know when they join."*
    - Set `onboarding_completed_at` and advance to Step 4.
    No new context function needed — the existing invite path handles this.

15. `lib/fun_sheep_web/live/course_new_live.ex` — accept `?onboarding=true&school_id=X&grade=Y`
    query params and pre-fill those fields. After successful create, redirect to
    `/onboarding/student?step=done` instead of the course detail page.

---

## 9. Tests (Mandatory — No Exceptions)

Every file above must have corresponding tests. CLAUDE.md requires ≥ 80% coverage.

### Context Tests

- `test/fun_sheep/enrollments_test.exs`
  - `enroll/3` — happy path, duplicate (idempotent), invalid IDs
  - `bulk_enroll/3` — multiple courses, partial failure handling
  - `drop/2` — happy path, not-enrolled
  - `list_for_student/2` — with preloads

- `test/fun_sheep/courses_test.exs` (extend existing)
  - `list_courses_for_student/3` — school match, grade match, adjacent grades fallback
  - `list_courses_by_grade/2` — cross-school lookup

- `test/fun_sheep/accounts_test.exs` (extend existing)
  - `complete_onboarding/1` — sets timestamp
  - `onboarding_complete?/1` — true when set, false when nil

### LiveView Tests

- `test/fun_sheep_web/live/student_onboarding_live_test.exs`
  - Renders Step 1 for new student
  - Grade selection updates assigns
  - School search renders results
  - Course catalog shows correct courses for grade/school
  - "Add" toggle works (updates `selected_course_ids`)
  - "Select All" in a subject group
  - Continue → `bulk_enroll` called → Step 4 shown
  - `complete_onboarding` called on Step 4 mount
  - Skip path (no school) → catalog falls back to grade-wide results
  - Empty state A rendered when school has no courses

- `test/fun_sheep_web/live/dashboard_live_test.exs` (extend existing)
  - Shows enrolled courses section when enrollments exist
  - Shows incomplete-onboarding CTA when `onboarding_completed_at: nil`
  - Does NOT show CTA when onboarding complete

- `test/fun_sheep_web/live/course_search_live_test.exs` (extend existing)
  - Enrolled badge visible when student is enrolled
  - "My school" filter chip visible and active when school set

---

## 10. Acceptance Criteria

A brand-new student who:

1. Registers via `/register`
2. Is redirected to `/onboarding/student`
3. Enters display name and selects **Grade 10**
4. Searches for their school, selects it
5. Sees a list of Grade 10 courses (and adjacent Grade 9/11 if needed)
6. Clicks **Add** on 3 courses
7. Clicks **Continue** → sees Done screen listing those 3 courses
8. Clicks **Go to Dashboard** → sees "My Courses" section with all 3 courses

**AND** a student who:
- Has registered but not completed onboarding
- Logs in → sees the "Set up your profile" CTA on dashboard
- Clicks it → returns to the wizard at Step 1

**AND** a student whose school has no courses:
- Selects their school in Step 2 → Step 3 shows Empty State A
- Sees "You're the first from [School]" headline — not an error message
- Both **Create a course** and **Invite a teacher** CTAs are visible and functional
- "Browse from other schools" is present but secondary (collapsed by default, expand on click)
- Clicking "Invite Teacher" → enters teacher email → success confirmation → advances to Step 4 (Done)
- Clicking "Create Course" → goes to `/courses/new` pre-filled → after creating, returns to Step 4

**AND** failure paths:
- No courses in entire platform → Empty State D, creation and invitation CTAs shown, student reaches dashboard
- Network error during school search → inline error, input stays editable (no crash)

---

## 11. Design System (Mandatory)

Follow CLAUDE.md design rules exactly:

- **Primary green** `#4CD964` for Add buttons and CTAs
- **Pill-shaped buttons** (`rounded-full`) for all actions
- **Course cards** `rounded-2xl` with subject color left-border stripe
- **Added ✓ state**: button becomes `bg-green-100 text-green-700 border border-green-300` (not filled green — distinguish from CTA)
- **Progress indicator** in wizard header: Step 1 of 4, Step 2 of 4, etc.
- **Dark mode** all components must support
- Validate with `/interactor-design-guide` before calling UI done

---

## 12. What NOT to Do

- ❌ Don't show fake courses or hardcoded subject names. If the DB is empty, show the honest empty state with creation CTAs.
- ❌ Don't bury the "Create a course" and "Invite a teacher" options below the fallback course list — they must be the primary actions when a school has no courses.
- ❌ Don't treat an empty school as an error. Frame it as an opportunity: "You're the first from [School]."
- ❌ Don't force school selection — it must be skippable. Many students don't know their school's exact registered name.
- ❌ Don't auto-redirect to onboarding on every login — only on first registration. The dashboard CTA handles subsequent logins.
- ❌ Don't write to `student_courses` on every card toggle — batch on Continue.
- ❌ Don't reuse the parent onboarding wizard. This is a separate LiveView.
- ❌ Don't run `mix compile` while the dev server is running (see memory `feedback_no_mix_compile`).
- ❌ Don't skip Playwright visual verification (see memory `feedback_visual_verify_ui`).

---

## 13. Out of Scope for This PR

- Auto-creating test schedules from enrolled courses (separate feature — student initiates)
- Teacher-side "assign students to course" (different flow — guardian-assigned source)
- AI-recommended courses based on learning history (future — no data yet for new students)
- Re-ordering / prioritizing enrolled courses
- Push notifications when new courses are added to the student's school
