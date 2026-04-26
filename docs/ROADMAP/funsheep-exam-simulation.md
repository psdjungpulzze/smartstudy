# FunSheep — Exam Simulation Mode: Strategy & Roadmap

> **For the Claude session implementing this feature.** Read the entire document before writing a single line of code. Exam Simulation is a fourth test type that is architecturally distinct from the three existing modes. Its correctness depends on never showing feedback mid-session, enforcing real time pressure, and producing time-management analytics that no other mode collects. Skipping any section will produce an experience that fails students on exam day.

---

## 0. Why This Feature Exists

FunSheep's three existing test modes each serve a specific learning purpose:

| Mode | Purpose | Feedback cadence |
|------|---------|-----------------|
| **Assessment** | Identify weak skills (adaptive, diagnostic) | Per-question (graded live) |
| **Practice (Weak Concepts)** | Drill weak skills with spaced interleaving | Per-question (graded live) |
| **Quick Practice** | Mobile-first confidence check (I know / I don't know) | Per-card (instant) |

**What none of them teach**: how to perform under exam conditions.

A student who scores 92% readiness on daily drills may still collapse on the real exam because:

1. They've never had to pace 45 questions in 50 minutes.
2. They always skip hard questions but never come back (real exams demand a strategy).
3. They don't know which sections drain their time disproportionately.
4. They've never had to make a final commitment with no feedback — just a submit button.

**Exam Simulation** replicates the actual test experience: timed, section-structured, no mid-session feedback, flag-and-return, and ends with a full time-management debrief alongside the score. It is the bridge between "I know this material" and "I can perform on test day."

---

## 1. Feature Definition

### 1.1 What Exam Simulation Is

A timed, format-matched, no-feedback test run that:

1. Follows the real exam's section structure, question-type mix, and time limits from the course's `TestFormatTemplate`.
2. Draws questions from the course question bank (the same pool used by Assessment and Practice).
3. Shows **zero** per-question feedback until the student submits or time expires.
4. Tracks **per-question time** throughout, enabling a post-exam pacing debrief.
5. Produces a full scorecard and time-management analysis after completion.
6. Records results as a `StudySession` with type `:exam_simulation` and persists a separate `ExamSimulationSession` for the detailed breakdown.

### 1.2 What It Is Not

- Not an adaptive assessment (no skill-state machine, no depth probes).
- Not a custom fixed test (questions come from the bank, not creator-authored pairs).
- Not a daily practice drill (no interleaving weights, no re-ranking, no readiness update during session).
- Not timed practice with hints (no "I know / I don't know", no answer preview).

### 1.3 Core Invariants for This Mode

> These extend the Product North Star invariants and are binding on this feature's implementation.

**ES-1.** The student MUST NOT see whether an answer is correct or incorrect until the full exam is submitted or time expires. No color changes, no correct-answer reveals, no score tickers.

**ES-2.** The countdown timer MUST run in real time and MUST auto-submit the exam when it reaches zero. The server is the authoritative clock — client display is advisory only.

**ES-3.** The exam MUST follow the format structure (section count, question types, count per section) from the `TestFormatTemplate` linked to the student's `TestSchedule`. If no format template is linked, the default structure applies (see §3.3).

**ES-4.** Per-question time MUST be recorded server-side (not estimated client-side) to produce accurate pacing analytics.

**ES-5.** An in-progress exam session MUST survive page refresh, network disconnect, and server restart. The student MUST be able to resume within the same remaining time window.

**ES-6.** The exam MUST distinguish between "answered" and "flagged for review" at submission: unanswered questions are counted as wrong; flagged-but-answered questions are counted normally.

**ES-7.** Results (score, per-question breakdown, time analysis) MUST update the student's `ReadinessScore` snapshot — this is real performance data, not just engagement.

---

## 2. User Journeys

### 2.1 Student — Taking the Exam

```
Course Dashboard
  └─▶ [Take Exam Simulation] button (gated: must have test_schedule + format template)
        │
        ▼
  Pre-Exam Briefing screen
  ├── "This simulates your real exam."
  ├── Sections listed with question count + time allocation per section
  ├── "You will not see feedback until you submit."
  ├── [Start Exam] button
        │
        ▼
  Exam Interface (timer running)
  ├── Global countdown timer (top right, persistent)
  ├── Section tab bar (jump to any section)
  ├── Question pane (one question at a time, navigable within section)
  ├── Answer input (multiple choice / short answer / free response)
  ├── [Flag for Review] toggle per question
  ├── [Previous] / [Next] navigation
  ├── Section progress indicator (answered / total)
  └── [Submit Exam] button (confirmation dialog)
        │
        ▼  (on submit OR timer reaches 0)
  Results Screen
  ├── Overall score (correct / total, %)
  ├── Per-section scores
  ├── Time management debrief
  │    ├── Time used per section (vs. recommended)
  │    ├── Slowest questions (flagged for review)
  │    └── Time distribution chart
  ├── Question-by-question review (correct/wrong, your answer, correct answer)
  └── [Practice Weak Sections] → deep-links into Practice mode filtered to those sections
```

### 2.2 Parent / Teacher — Viewing Results

- Dashboard shows student's exam simulation history (scores + pacing trends).
- Can compare simulated exam scores to readiness score trend.
- No action required from parent/teacher during the exam.

---

## 3. Architecture

### 3.1 New Database Tables

#### `exam_simulation_sessions`

```sql
create table exam_simulation_sessions (
  id            uuid primary key default gen_random_uuid(),
  user_role_id  uuid not null references user_roles(id),
  course_id     uuid not null references courses(id),
  schedule_id   uuid references test_schedules(id),
  format_template_id uuid references test_format_templates(id),

  -- Session lifecycle
  status        varchar not null default 'in_progress',
  --   in_progress | submitted | timed_out | abandoned

  -- Time tracking (server-authoritative)
  time_limit_seconds  integer not null,
  started_at          utc_datetime not null,
  submitted_at        utc_datetime,
  elapsed_at_pause    integer,   -- seconds elapsed when last paused (NULL = never paused)
  -- NOTE: pausing is NOT allowed by default; this field supports "pause-allowed" config only

  -- Content
  question_ids_order  jsonb not null,  -- [uuid, ...] — order drawn at session start
  -- {"<question_id>": {"answer": "A", "flagged": false, "time_started_at": <ms>, "time_spent_seconds": 12}}
  answers             jsonb not null default '{}',

  -- Scoring (populated at submission)
  score_correct  integer,
  score_total    integer,
  score_pct      float,
  section_scores jsonb,  -- {"<section_name>": {"correct": 3, "total": 5, "time_seconds": 240}}

  inserted_at  utc_datetime not null,
  updated_at   utc_datetime not null
);

create index exam_simulation_sessions_user_role_id_idx
  on exam_simulation_sessions (user_role_id);
create index exam_simulation_sessions_course_id_idx
  on exam_simulation_sessions (course_id);
```

#### No new question-level tables needed
Per-question timing and answers live in the `answers` JSONB field of `exam_simulation_sessions`. This keeps grading and analytics fully contained in the session record.

### 3.2 Engine: `FunSheep.Assessments.ExamSimulationEngine`

Responsibilities:
1. **Build** the exam question set from the format template structure at session start.
2. **Track** per-question timing (server-side).
3. **Grade** the completed session (exact-match for MC/T/F, AI grading for SA/FR).
4. **Summarize** time-management analytics.

```elixir
defmodule FunSheep.Assessments.ExamSimulationEngine do
  @moduledoc """
  Builds and grades exam simulation sessions.

  This engine is intentionally NOT adaptive: question selection is fixed at
  session start and no per-answer feedback is shown until the exam is submitted.
  """

  @type section_spec :: %{
    name: String.t(),
    question_types: [atom()],
    count: pos_integer(),
    time_seconds: pos_integer()   # per-section time budget
  }

  @type exam_state :: %{
    session_id: Ecto.UUID.t(),
    course_id: Ecto.UUID.t(),
    sections: [section_spec()],
    questions: [map()],           # ordered list, immutable after start
    current_index: non_neg_integer(),
    answers: map(),               # question_id → %{answer, flagged, time_started_at, time_spent_seconds}
    time_limit_seconds: pos_integer(),
    started_at: DateTime.t(),
    status: :in_progress | :submitted | :timed_out
  }

  @spec build_session(course_id, schedule_id, format_template_id) ::
    {:ok, exam_state()} | {:error, reason()}
  def build_session(course_id, schedule_id, format_template_id) do
    # 1. Load format template → section specs
    # 2. For each section spec: query questions by (course_id, question_types, difficulty_mix)
    # 3. If bank is insufficient: return {:error, :insufficient_questions}
    # 4. Shuffle within each section (preserving section order)
    # 5. Persist exam_simulation_session record (status: :in_progress)
    # 6. Return exam_state (stored in ETS + DB via SessionStore)
  end

  @spec record_answer(exam_state(), question_id, answer, time_spent_seconds) :: exam_state()
  def record_answer(state, question_id, answer, time_spent_seconds) do
    # Update answers map — NO grading yet
  end

  @spec flag_question(exam_state(), question_id, boolean()) :: exam_state()
  def flag_question(state, question_id, flagged) do
    # Toggle flagged status in answers map
  end

  @spec submit(exam_state()) :: {:ok, ExamSimulationSession.t()} | {:error, reason()}
  def submit(state) do
    # 1. Grade all answers (synchronous for MC/T/F; async AI for SA/FR)
    # 2. Compute section_scores and time breakdown
    # 3. Persist final session record (status: :submitted)
    # 4. Enqueue ReadinessScore recalculation
    # 5. Enqueue StudySession record creation (type: :exam_simulation)
    # 6. Return completed session
  end

  @spec timeout(exam_state()) :: {:ok, ExamSimulationSession.t()}
  def timeout(state) do
    # Same as submit/1 — called by server-side timer (Oban job or Process.send_after)
  end

  @spec time_management_summary(ExamSimulationSession.t()) :: map()
  def time_management_summary(session) do
    # Returns per-section: time_used, time_budget, over/under, slowest_questions
  end
end
```

### 3.3 Default Exam Structure (When No Format Template)

When a course has no `TestFormatTemplate` linked to the schedule, use:

```
1 section — "General"
question count: min(total_bank_questions, 40)
question types: all available types in the course
time limit: 45 minutes
```

This default ensures the mode is always accessible, even for courses without a formal format.

### 3.4 Session Persistence (Reconnect Safety — ES-5)

The exam engine state is stored in two layers, identical to `AssessmentLive` today:

| Layer | Mechanism | TTL |
|-------|-----------|-----|
| Hot | ETS via `StateCache` | Process lifetime (~30 min) |
| Cold | PostgreSQL `exam_simulation_sessions` (answers JSONB) | Indefinite |

On `mount/3`, `ExamSimulationLive` checks:
1. ETS cache by `{user_role_id, session_id}` → resume from memory
2. DB query by `status: :in_progress` for this user + course → rebuild state from stored answers
3. No active session → render pre-exam briefing screen

**Remaining time** on reconnect = `time_limit_seconds - (DateTime.diff(now, started_at, :second) - total_paused_seconds)`. If already expired, auto-submit immediately.

### 3.5 Server-Authoritative Timer

The countdown timer MUST NOT rely solely on the client JavaScript clock. Strategy:

1. At session start, persist `started_at` and `time_limit_seconds` in the DB.
2. `ExamSimulationLive` mounts a `Process.send_after(self(), :tick, 1_000)` loop.
3. On each `:tick`, compute remaining from the server's `DateTime.utc_now()` minus `started_at`.
4. When remaining ≤ 0, call `ExamSimulationEngine.timeout/1` and redirect to results.
5. If the LiveView process dies (network drop), an **Oban job** scheduled at `started_at + time_limit_seconds + 30s` auto-submits any still-`in_progress` sessions as `:timed_out`.

```elixir
# Oban worker scheduled at session creation
defmodule FunSheep.Workers.ExamTimeoutWorker do
  use Oban.Worker, queue: :assessments

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
    case Assessments.get_exam_session(session_id) do
      %{status: :in_progress} = session ->
        ExamSimulationEngine.timeout(session)
      _ ->
        :ok  # already submitted
    end
  end
end
```

### 3.6 LiveView: `FunSheepWeb.ExamSimulationLive`

```
lib/funsheep_web/live/exam_simulation_live/
├── index.ex          # Route: /courses/:course_id/exam-simulation
├── exam.ex           # Main exam interface (timer, question pane, section nav)
└── results.ex        # Post-exam results + time management debrief
```

Key socket assigns:

```elixir
%{
  session: ExamSimulationSession.t(),
  engine_state: ExamSimulationEngine.exam_state(),
  current_section_index: integer(),
  current_question_index: integer(),
  remaining_seconds: integer(),       # refreshed every tick
  show_section_overview: boolean(),   # "overview" drawer showing all Q statuses
  submit_modal_open: boolean()
}
```

Key events:

| Event | Handler |
|-------|---------|
| `"answer"` | Record answer, advance to next if auto-advance enabled |
| `"flag"` | Toggle flagged status |
| `"navigate"` | Jump to section + question index |
| `"submit"` | Show confirmation modal |
| `"confirm_submit"` | Call engine submit, redirect to results |
| `:tick` | Refresh remaining_seconds; auto-submit if ≤ 0 |

### 3.7 Readiness Score Integration (ES-7)

After submission, enqueue `ReadinessCalculator.calculate_and_save/2` — the same function called after an Assessment session. The exam simulation answers feed into the same `question_attempts` table, so the calculator can incorporate them.

New `question_attempts.source` enum value: `:exam_simulation` (in addition to existing `:assessment`, `:practice`, `:quick_test`).

---

## 4. Question Selection Strategy

### 4.1 Format-Template-Driven Selection

Each section in the `TestFormatTemplate.structure` map specifies:
- `question_types`: list of allowed types (`:multiple_choice`, `:short_answer`, etc.)
- `count`: number of questions
- `difficulty_mix`: optional `{easy: 20, medium: 50, hard: 30}` percentages (defaults to mix proportional to bank)
- `chapter_filter`: optional list of chapter IDs (defaults to all in-scope chapters from `TestSchedule`)

```elixir
defp select_questions_for_section(section_spec, course_id, schedule_id) do
  chapters = section_spec[:chapter_filter] || all_in_scope_chapters(schedule_id)

  Questions.list_for_exam(
    course_id: course_id,
    chapter_ids: chapters,
    question_types: section_spec.question_types,
    difficulty_mix: section_spec[:difficulty_mix] || :proportional,
    count: section_spec.count
  )
end
```

### 4.2 When the Bank Is Insufficient

If a section requires 15 questions but the bank only has 9:
1. Use all 9.
2. Add a pre-exam warning: "Only 9 questions available for [Section Name]. Your practice bank may still be growing."
3. Do NOT block the exam — a partial exam is better than no exam.

### 4.3 Repeated Questions Across Sessions

A student may retake the exam multiple times (e.g., weekly before the real test). To avoid pure memorization:
- On a new session, sort available questions by `last_seen_in_exam ASC NULLS FIRST` (questions never seen in an exam are preferred).
- After exhausting unseen questions, shuffle all available.

---

## 5. Time Management Analytics

This is the primary differentiator of Exam Simulation over the other modes. After submission, the student sees:

### 5.1 Section Pacing Overview

| Section | Budget | Used | Status |
|---------|--------|------|--------|
| Multiple Choice | 35 min | 28 min | ✅ Under by 7 min |
| Free Response | 15 min | 22 min | ⚠️ Over by 7 min |

### 5.2 Question-Level Time Distribution

For each question: a bar showing time spent (green if < average, yellow if 1.5× average, red if 2× average or flagged but not returned to).

Insight callouts:
- "You spent 4 min on Question 14 (avg: 1.2 min). Students who spend > 2× average here often run out of time."
- "3 questions were flagged for review but you never returned to them. Each one was left blank."

### 5.3 Recommended Action After Exam

Based on the time debrief:
- If a section is consistently over budget across multiple exam simulations → surface a dedicated tip: "Consider spending max 2 min per [Section Name] question. See practice drills filtered to [Section Name]."
- Auto-link the "Practice Weak Sections" button to the exact sections where:
  - Score < 70% **and/or**
  - Time was over budget

---

## 6. UI Design Notes

### 6.1 Exam Mode UI Contract

The exam UI must visually signal "this is real" — distinct from the green-and-friendly practice UI:

- **Header**: Dark navy or charcoal (`#1E293B`) background to differentiate from practice.
- **Timer**: Prominent, top-right, turns **amber** at 20% time remaining, **red** at 10%.
- **Answer indicators**: Neutral grey dot per question in the section overview (not green/red — no feedback).
- **Submit button**: Disabled until at least one question is answered; confirmation dialog required ("Are you sure? This will end your exam. You have X questions unanswered.").
- **No tutor button** during the exam (AI tutor is hidden).
- **No readiness score ticker** during the exam.

### 6.2 Section Navigation

A horizontal tab bar (or collapsible drawer on mobile) shows section names and per-section progress: `Section 1 (12/20 answered)`. Students can jump freely between sections and between questions within a section.

### 6.3 Mobile Considerations

The Quick Practice mode is already mobile-first. Exam Simulation is intentionally desktop-forward (full exams on mobile are suboptimal UX) but MUST be usable on tablet and large-phone screens:
- Timer always visible (sticky header)
- Section navigation as a bottom sheet on mobile
- Question text scales with viewport

---

## 7. Billing & Access

### 7.1 Gating

Exam Simulation is a **premium feature** — available on paid plans only, alongside Assessment.

```elixir
# In ExamSimulationLive.mount/3
with :ok <- Billing.check_exam_simulation_allowance(user_role_id) do
  # proceed
else
  {:error, :not_subscribed} -> redirect to upgrade screen
end
```

### 7.2 Usage Limits

Per-month exam simulation runs are unlimited for paid subscribers (no extra gate beyond subscription).

---

## 8. Integration with Existing Features

### 8.1 Test Schedule

`exam_simulation_sessions.schedule_id` links to the student's `TestSchedule`. The test date drives the urgency indicator on the course dashboard: "7 days until AP Biology exam — take a full simulation now."

### 8.2 Readiness Dashboard

After a completed simulation, the readiness dashboard should show:
- A new "Exam Simulation" data point in the readiness history chart (distinct marker vs. assessment).
- Per-section scores from the simulation mapped to the chapter/skill grid.

### 8.3 Study Path

After a simulation with score < 70% in specific sections, the Study Path recommends those sections for the next practice session.

### 8.4 Essay Tests

When `funsheep-essay-tests.md` is implemented, Exam Simulation should support essay questions inline (with the auto-save and grading pipeline from that feature). Until then, if a format template includes `free_response` questions > 250 expected words, they are graded post-session by the AI grading pipeline (may take 30–60 seconds).

---

## 9. Implementation Plan

> **How to read this section.** Each phase lists granular, atomic todos — small enough that a single PR or a single Claude session can complete one without needing to read the rest. Every todo includes what file(s) to create or change, what behaviour to implement, and what to test. Complete phases in order; each phase's tests act as the acceptance gate for the next.

---

### Phase 1 — Database & Core Engine

**Goal:** Persist exam sessions to the database and implement the engine logic in pure Elixir (no LiveView yet). All behaviour in this phase is testable without a browser.

#### 1-A. Migrations

- [ ] **Migration: `exam_simulation_sessions` table**
  - File: `priv/repo/migrations/<timestamp>_create_exam_simulation_sessions.exs`
  - Columns (match §3.1 exactly): `id`, `user_role_id`, `course_id`, `schedule_id`, `format_template_id`, `status`, `time_limit_seconds`, `started_at`, `submitted_at`, `elapsed_at_pause`, `question_ids_order` (jsonb), `answers` (jsonb default `{}`), `score_correct`, `score_total`, `score_pct`, `section_scores` (jsonb), `inserted_at`, `updated_at`
  - `status` stored as `varchar` with a DB check constraint: `status IN ('in_progress','submitted','timed_out','abandoned')`
  - Indexes: `user_role_id`, `course_id`, composite `(user_role_id, status)` for active-session lookup
  - Foreign keys: `user_role_id → user_roles`, `course_id → courses`, `schedule_id → test_schedules` (nullable), `format_template_id → test_format_templates` (nullable)
  - Verify migration is reversible (`down` drops table)

- [ ] **Migration: add `:exam_simulation` to `question_attempts.source` enum**
  - File: `priv/repo/migrations/<timestamp>_add_exam_simulation_to_question_attempts_source.exs`
  - Existing enum values: `:assessment`, `:practice`, `:quick_test` — add `:exam_simulation`
  - If `source` is a Postgres enum type (`CREATE TYPE`): use `ALTER TYPE ... ADD VALUE`
  - If `source` is a varchar with a check constraint: update the constraint
  - Verify existing question_attempts rows are unaffected

- [ ] **Migration: add `:exam_simulation` to `study_sessions.session_type` enum**
  - Same approach as question_attempts above
  - Verify existing study_session rows are unaffected

#### 1-B. Ecto Schemas

- [ ] **Schema: `FunSheep.Assessments.ExamSimulationSession`**
  - File: `lib/funsheep/assessments/exam_simulation_session.ex`
  - Fields match migration columns
  - `status` as `Ecto.Enum` with values `[:in_progress, :submitted, :timed_out, :abandoned]`
  - `question_ids_order` as `{:array, :string}` (list of UUIDs)
  - `answers` as `:map` (arbitrary JSONB keyed by question_id)
  - `section_scores` as `:map`
  - `changeset/2` for creation (requires: `user_role_id`, `course_id`, `time_limit_seconds`, `started_at`, `question_ids_order`)
  - `submit_changeset/2` for scoring fields (`score_correct`, `score_total`, `score_pct`, `section_scores`, `submitted_at`)
  - `timeout_changeset/1` — same as submit but sets `status: :timed_out`
  - `answer_changeset/2` — accepts updated `answers` map for mid-session persistence
  - Virtual field `remaining_seconds` (not persisted, computed in context/liveview)

#### 1-C. Context Module

- [ ] **Context: `FunSheep.Assessments.ExamSimulations`**
  - File: `lib/funsheep/assessments/exam_simulations.ex`
  - Functions to implement:

  ```
  create_session(attrs) → {:ok, session} | {:error, changeset}
    - Validates required attrs
    - Inserts exam_simulation_sessions row

  get_active_session(user_role_id, course_id) → session | nil
    - Query: status = 'in_progress', ordered by started_at DESC, limit 1
    - Returns nil if none found

  get_session!(id) → session  (raises if not found)

  list_sessions_for_user(user_role_id, opts \\ []) → [session]
    - opts: [course_id: uuid, limit: integer, status: atom]
    - Default order: started_at DESC

  persist_answer(session, question_id, answer_data) → {:ok, session}
    - Merges new answer into answers JSONB
    - Uses answer_changeset, Repo.update

  mark_submitted(session, scoring_attrs) → {:ok, session}
    - Uses submit_changeset

  mark_timed_out(session) → {:ok, session}
    - Uses timeout_changeset; fills score fields from whatever was answered

  mark_abandoned(session) → {:ok, session}
    - Sets status: :abandoned, no score fields
  ```

#### 1-D. `Questions.list_for_exam/1` Query

- [ ] **New query function in `FunSheep.Questions`**
  - File: `lib/funsheep/questions.ex` (add function to existing module)
  - Signature: `list_for_exam(opts) → [Question.t()]`
  - Options: `course_id`, `chapter_ids`, `question_types`, `difficulty_mix` (`:proportional` | `%{easy: pct, medium: pct, hard: pct}`), `count`
  - Implementation:
    - Filter by course_id, chapter_ids, question_types (all optional)
    - If `difficulty_mix: :proportional` — fetch proportional to existing bank ratios
    - If `difficulty_mix: %{...}` — stratified sample: fetch `count × pct` per difficulty, fill gaps from other difficulties if a stratum is under-populated
    - Apply `ORDER BY RANDOM()` within each difficulty stratum (or within whole set for proportional)
    - Limit to `count` total
  - Edge case: if result count < requested count, return whatever is available (caller handles warning)

- [ ] **New query function: `Questions.exam_question_ids_seen_by_user/2`**
  - File: `lib/funsheep/questions.ex`
  - Signature: `exam_question_ids_seen_by_user(user_role_id, course_id) → [uuid]`
  - Joins `question_attempts` where `source = :exam_simulation`
  - Returns distinct question_ids seen in past exam simulations by this user
  - Used by engine for unseen-first question ordering (Phase 4)

#### 1-E. Engine Module

- [ ] **`FunSheep.Assessments.ExamSimulationEngine`**
  - File: `lib/funsheep/assessments/exam_simulation_engine.ex`
  - Implement all functions from §3.2 spec:

  **`build_session/3`** — `(user_role_id, course_id, opts)` where opts has `schedule_id`, `format_template_id`
  - Load `TestFormatTemplate` or use default structure (§3.3)
  - For each section spec, call `Questions.list_for_exam/1`
  - Flatten into ordered `question_ids_order` list, tracking section boundaries
  - Create DB record via `ExamSimulations.create_session/1`
  - Schedule `ExamTimeoutWorker` Oban job
  - Store state in ETS via `StateCache`
  - Return `{:ok, exam_state}` or `{:error, reason}` — reason `:insufficient_questions` if any section is empty

  **`record_answer/4`** — `(state, question_id, answer_text, time_spent_seconds)`
  - Update `answers` map in state: `%{question_id => %{answer: answer_text, flagged: current_flagged, time_spent_seconds: time_spent_seconds}}`
  - Persist to DB via `ExamSimulations.persist_answer/3` (write-through)
  - Return updated state

  **`flag_question/3`** — `(state, question_id, flagged_boolean)`
  - Toggle `flagged` in answers map for question_id
  - Persist to DB (answers update)
  - Return updated state

  **`navigate_to/3`** — `(state, section_index, question_index)`
  - Record `time_started_at: DateTime.utc_now()` for the question being navigated to
  - Return updated state (no DB write — timing recorded at answer or navigate-away)

  **`submit/1`** — `(state)`
  - Grade all answered questions: for each question_id in `question_ids_order`, call `grade_answer/3`
  - For unanswered questions: `is_correct: false`
  - Compute `score_correct`, `score_total`, `score_pct`
  - Compute `section_scores` map
  - Write `question_attempts` rows for each question (source: `:exam_simulation`)
  - Call `ExamSimulations.mark_submitted/2`
  - Enqueue `FunSheep.Workers.ReadinessRecalcWorker` for this user + schedule
  - Enqueue `StudySession` creation (type: `:exam_simulation`)
  - Cancel `ExamTimeoutWorker` Oban job (use job unique key or store job ID in session)
  - Return `{:ok, completed_session}`

  **`timeout/1`** — `(state | session_id)`
  - Accept either live state map (if LiveView is alive) or session_id string (from Oban worker)
  - If called with session_id: load session from DB, reconstruct minimal state
  - Same grading logic as `submit/1` but status becomes `:timed_out`

  **`grade_answer/3`** — `(question, answer_text, opts)` (private)
  - `multiple_choice` / `true_false`: case-insensitive exact match on `question.correct_answer`
  - `short_answer`: case-insensitive exact match first; if `question.metadata.ai_graded: true`, enqueue AI grading job and mark as pending
  - `free_response`: always enqueue AI grading job; mark as pending
  - Return `%{is_correct: boolean | :pending, score: float | nil}`

  **`section_for_question/2`** — `(state, question_id)` (private)
  - Given a question_id, return its section spec (name, index, time_budget)
  - Computed from `question_ids_order` and section boundaries

#### 1-F. Oban Worker

- [ ] **`FunSheep.Workers.ExamTimeoutWorker`**
  - File: `lib/funsheep/workers/exam_timeout_worker.ex`
  - Queue: `:assessments`
  - Args: `%{"session_id" => uuid, "user_role_id" => uuid}`
  - Scheduled at: `started_at + time_limit_seconds + 30` seconds (buffer for clock skew)
  - On perform: fetch session, if status is `:in_progress` call `ExamSimulationEngine.timeout/1`, else `:ok`
  - Use `unique: [period: :infinity, keys: [:session_id]]` to prevent duplicate timeout jobs

- [ ] **Register worker in Oban config**
  - File: `config/config.exs` (or `runtime.exs`)
  - Add `:assessments` queue if not already present with sufficient concurrency

#### 1-G. StateCache Integration

- [ ] **ETS cache key for exam simulation**
  - File: `lib/funsheep/assessments/state_cache.ex` (existing module)
  - Add new key prefix: `{:exam_simulation, user_role_id, session_id}`
  - Ensure `put/3`, `get/2`, `delete/2` work with this key shape
  - TTL: 30 minutes (same as assessment cache)

#### 1-H. Phase 1 Tests

- [ ] **Unit tests: `ExamSimulationEngine`**
  - File: `test/funsheep/assessments/exam_simulation_engine_test.exs`
  - Test cases:
    - `build_session/3` with full format template → correct question count per section
    - `build_session/3` with no format template → uses default structure (40 Qs, 45 min)
    - `build_session/3` when bank has fewer Qs than spec → returns available Qs, no error
    - `build_session/3` when a section has 0 questions → returns `{:error, :insufficient_questions}`
    - `record_answer/4` → updates answers map; flagged flag preserved
    - `flag_question/3` toggle on/off
    - `navigate_to/3` → records `time_started_at`
    - `submit/1` → correct score computed; unanswered Qs counted as wrong
    - `submit/1` with all correct → `score_pct: 1.0`
    - `timeout/1` called with session_id from DB → same scoring as submit

- [ ] **Unit tests: `ExamSimulations` context**
  - File: `test/funsheep/assessments/exam_simulations_test.exs`
  - Test `create_session`, `get_active_session`, `persist_answer`, `mark_submitted`, `mark_timed_out`
  - Verify `get_active_session/2` returns nil after submit

- [ ] **Unit tests: `Questions.list_for_exam/1`**
  - File: `test/funsheep/questions_test.exs` (add cases)
  - Stratified difficulty mix returns correct ratio
  - When bank is smaller than count, returns all available
  - Excludes questions not matching `question_types` filter

- [ ] **Unit tests: `ExamSimulationSession` changeset**
  - File: `test/funsheep/assessments/exam_simulation_session_test.exs`
  - Valid changeset with required fields
  - Invalid: missing `user_role_id`, missing `time_limit_seconds`

- [ ] **Run `mix test` and `mix test --cover`; coverage for new modules must be ≥ 80%**

---

### Phase 2 — LiveView & Session Lifecycle

**Goal:** A student can open the exam, answer questions, and submit — the full UI flow works end-to-end in a browser. No time management analytics yet (Phase 3).

#### 2-A. Router

- [ ] **Add routes to `FunSheepWeb.Router`**
  - File: `lib/funsheep_web/router.ex`
  - Routes to add (within authenticated scope):
    ```
    live "/courses/:course_id/exam-simulation",          ExamSimulationLive.Index,   :index
    live "/courses/:course_id/exam-simulation/exam",     ExamSimulationLive.Exam,    :exam
    live "/courses/:course_id/exam-simulation/results/:session_id", ExamSimulationLive.Results, :results
    ```
  - Verify routes don't conflict with existing `/courses/:id/...` patterns

#### 2-B. Pre-Exam Briefing (`ExamSimulationLive.Index`)

- [ ] **File: `lib/funsheep_web/live/exam_simulation_live/index.ex`**
  - `mount/3`:
    - Load course by `params["course_id"]`
    - Load current user's test schedule for this course
    - Load format template (from schedule or course default)
    - Check billing: `Billing.check_exam_simulation_allowance/1` — redirect to upgrade if not subscribed
    - Check for active in-progress session: if one exists, show "Resume" option
    - Check minimum bank size: if < 30 in-scope questions, show disabled state with explanation
    - Assigns: `course`, `schedule`, `format_preview` (sections with Q count + time), `has_active_session`, `bank_too_small`
  - `handle_event("start_exam", ...)`:
    - Call `ExamSimulationEngine.build_session/3`
    - On `{:ok, state}` → redirect to `/courses/:id/exam-simulation/exam`
    - On `{:error, :insufficient_questions}` → assign error flash
  - `handle_event("resume_exam", ...)`:
    - Redirect to `/courses/:id/exam-simulation/exam` (exam LiveView will pick up active session)
  - Template: show exam briefing card
    - Title: "Full Exam Simulation"
    - Subtitle: "Experience the real test. Timed. No hints. No feedback until you submit."
    - Sections table: section name | question count | time budget
    - Total: X questions · Y minutes
    - Warning badge (amber) if question count < spec count ("Your practice bank is still growing — this exam will have N questions instead of M")
    - "You will not see correct answers until you submit" disclaimer
    - [Start Exam] button (green, disabled if bank too small)
    - If active session: [Resume Exam] button + "You have N minutes remaining" callout

#### 2-C. Exam Interface (`ExamSimulationLive.Exam`)

- [ ] **File: `lib/funsheep_web/live/exam_simulation_live/exam.ex`**
  - `mount/3`:
    - Load course
    - Check billing (guard against URL manipulation)
    - Try ETS cache for active exam state → if miss, query DB for in-progress session
    - If no active session → redirect back to index
    - Compute `remaining_seconds` from `DateTime.utc_now() - state.started_at`
    - If `remaining_seconds ≤ 0` → call `ExamSimulationEngine.timeout/1` → redirect to results
    - Schedule first tick: `Process.send_after(self(), :tick, 1_000)`
    - Assigns: `engine_state`, `current_section_index: 0`, `current_question_index: 0`, `remaining_seconds`, `show_overview: false`, `submit_modal_open: false`

  - `handle_info(:tick, socket)`:
    - Recompute `remaining_seconds = time_limit - elapsed_seconds`
    - If ≤ 0: call engine timeout, redirect to results
    - If ≤ 10% of total: assign `timer_urgency: :critical` (red)
    - If ≤ 20% of total: assign `timer_urgency: :warning` (amber)
    - Else: assign `timer_urgency: :normal`
    - Schedule next tick: `Process.send_after(self(), :tick, 1_000)`
    - Return `{:noreply, socket}`

  - `handle_event("answer", %{"question_id" => id, "answer" => value}, socket)`:
    - Compute `time_spent_seconds` (from when this question was navigated to)
    - Call `ExamSimulationEngine.record_answer/4`
    - Update socket assigns
    - Do NOT reveal correctness — no color change, no feedback assign
    - Auto-advance to next question after 300ms (via `push_event` or assign `auto_advance: true`)

  - `handle_event("flag", %{"question_id" => id}, socket)`:
    - Call `ExamSimulationEngine.flag_question/3` with toggled value
    - Update socket assigns

  - `handle_event("navigate", %{"section" => si, "question" => qi}, socket)`:
    - Record departure time for current question
    - Call `ExamSimulationEngine.navigate_to/3`
    - Update `current_section_index`, `current_question_index`

  - `handle_event("prev", _, socket)` / `handle_event("next", _, socket)`:
    - Decrement/increment question index within section; wrap to prev/next section at boundaries

  - `handle_event("toggle_overview", _, socket)`:
    - Toggle `show_overview` assign

  - `handle_event("open_submit_modal", _, socket)`:
    - Count unanswered questions
    - Assign `submit_modal_open: true`, `unanswered_count`

  - `handle_event("close_submit_modal", _, socket)`:
    - Assign `submit_modal_open: false`

  - `handle_event("confirm_submit", _, socket)`:
    - Call `ExamSimulationEngine.submit/1`
    - On `{:ok, session}` → redirect to `/courses/:id/exam-simulation/results/#{session.id}`
    - On `{:error, _}` → flash error, keep exam open

  - **Template layout** (desktop-first, functional mobile):
    ```
    ┌─────────────────────────────────────────────────────────────┐
    │ [≡ Overview]  Section 1 (12/20)  Section 2 (3/15)  [⏱ MM:SS red/amber/normal] │
    ├─────────────────────────────────────────────────────────────┤
    │ Question 14 of 35                              [🚩 Flag]    │
    │                                                             │
    │  Question text...                                           │
    │                                                             │
    │  ○ A) Answer option                                         │
    │  ○ B) Answer option                                         │
    │  ○ C) Answer option          (neutral grey, no color leak)  │
    │  ○ D) Answer option                                         │
    │                                                             │
    ├─────────────────────────────────────────────────────────────┤
    │ [← Previous]                              [Next →]          │
    │                             [Submit Exam] (disabled until 1 answer) │
    └─────────────────────────────────────────────────────────────┘
    ```
    - Answer state indicators in question overview grid: `○` unanswered, `●` answered, `⚑` flagged (neutral colors only — no green/red)
    - Timer: `MM:SS` format; text color driven by `timer_urgency` assign
    - Submit modal: lists unanswered count, flagged-but-answered count; two buttons: [Cancel] [Submit Anyway]

  - **Exam mode visual contract** (§6.1):
    - Override app layout header: hide AI tutor button, hide readiness score, apply dark navy header
    - No sidebar (full-width exam interface)

#### 2-D. Results Screen (`ExamSimulationLive.Results`)

- [ ] **File: `lib/funsheep_web/live/exam_simulation_live/results.ex`**
  - `mount/3`:
    - Load `ExamSimulationSession` by `params["session_id"]`
    - Verify session belongs to current user (403 if not)
    - If session status is `:in_progress` → session was just submitted, may still be grading SA/FR async — show "grading in progress" state with polling
    - Load full question details for review (preload questions from `question_ids_order`)
    - Build `question_review_list`: ordered list of `%{question, your_answer, is_correct, time_spent_seconds, flagged}`
    - Build `section_summary`: `[%{name, correct, total, time_used_seconds, time_budget_seconds}]`
    - Assigns: `session`, `question_review_list`, `section_summary`, `show_question_index: nil`

  - `handle_event("show_question", %{"index" => i}, socket)`:
    - Toggle expanded question review at index i

  - `handle_event("practice_weak_sections", _, socket)`:
    - Identify weak sections: `score < 0.7` OR `time_used > time_budget`
    - Extract section_ids from those sections
    - Redirect to practice with `?section_ids=<csv>` query param (which PracticeLive already understands — verify and add if not)

  - **Template layout**:
    ```
    Score: 28 / 40  (70%)   [✅ Submitted | ⏰ Timed Out]

    ── Section Scores ──────────────────────────────────────────
    Multiple Choice   18/25  (72%)   ⏱ 32min used / 35min budget  ✅
    Free Response      3/ 8  (38%)   ⏱ 22min used / 15min budget  ⚠️ Over budget

    ── Question Review ─────────────────────────────────────────
    Q1  ● Correct   1.2min   [expand ▼]
    Q2  ✗ Wrong     3.8min   ⚑ Flagged  [expand ▼]
      └─ Your answer: B  |  Correct: C
         [explanation text if available]
    Q3  ✗ Unanswered  —
    ...

    ── Actions ─────────────────────────────────────────────────
    [Practice Weak Sections →]  [Retake Exam]  [Back to Course]
    ```
    - Score circle / gauge (visual, not just number)
    - "Timed Out" badge if `status: :timed_out`
    - Section over-budget shown in amber with clock icon
    - [Practice Weak Sections] button: only shown if any section < 70% or over budget; disabled if none

#### 2-E. Session Persistence & Reconnect (ES-5)

- [ ] **ETS cache store on every state mutation**
  - In `record_answer`, `flag_question`, `navigate_to`: always call `StateCache.put({:exam_simulation, user_role_id, session_id}, state)`
  - In `ExamSimulationLive.Exam` mount: try `StateCache.get({:exam_simulation, user_role_id, session_id})` first

- [ ] **DB fallback reconstruction**
  - When ETS misses: load `exam_simulation_sessions` row by `(user_role_id, status: :in_progress)`
  - Reconstruct `exam_state` struct from DB row (question_ids_order, answers, started_at, time_limit_seconds)
  - Load full question maps by IDs (needed for display)
  - Re-store in ETS

- [ ] **Reconnect time calculation**
  - `remaining = time_limit_seconds - DateTime.diff(utc_now, started_at, :second)`
  - If ≤ 0: auto-submit, redirect to results
  - Document this logic in a module comment

#### 2-F. Billing Gate

- [ ] **`Billing.check_exam_simulation_allowance/1`**
  - File: `lib/funsheep/billing.ex` (add function)
  - Check user's subscription includes exam simulation access (same tier as Assessment)
  - Return `:ok` or `{:error, :not_subscribed}`
  - Used in: `ExamSimulationLive.Index.mount/3`, `ExamSimulationLive.Exam.mount/3`

#### 2-G. Phase 2 Tests

- [ ] **LiveView tests: `ExamSimulationLive.Index`**
  - File: `test/funsheep_web/live/exam_simulation_live/index_test.exs`
  - Test: mount renders briefing screen with course name and section list
  - Test: "start_exam" event redirects to exam page when bank is sufficient
  - Test: "start_exam" shows error flash when bank has 0 questions in a required section
  - Test: billing-not-subscribed → renders upgrade prompt (mock `Billing.check_exam_simulation_allowance`)
  - Test: active in-progress session → "Resume" button visible
  - Test: `bank_too_small` when < 30 in-scope questions → Start button disabled

- [ ] **LiveView tests: `ExamSimulationLive.Exam`**
  - File: `test/funsheep_web/live/exam_simulation_live/exam_test.exs`
  - Test: mount loads in-progress session from DB, shows correct question
  - Test: mount with no active session → redirects to index
  - Test: mount with expired time → auto-submits, redirects to results
  - Test: "answer" event updates answer, does NOT change question color/class to green/red
  - Test: "flag" event toggles flag indicator in overview
  - Test: "navigate" event changes current_section_index and current_question_index
  - Test: "next" at last question in section → advances to next section
  - Test: "open_submit_modal" → submit_modal_open: true, unanswered_count correct
  - Test: "confirm_submit" → session marked submitted, redirected to results
  - Test: `:tick` message reduces remaining_seconds
  - Test: `:tick` with remaining_seconds ≤ 0 → triggers timeout, redirects to results
  - Test: page refresh (remount) → session restored from ETS cache
  - Test: ETS cache miss → session restored from DB

- [ ] **LiveView tests: `ExamSimulationLive.Results`**
  - File: `test/funsheep_web/live/exam_simulation_live/results_test.exs`
  - Test: mount loads session, renders score and section breakdown
  - Test: shows "Timed Out" badge for timed_out sessions
  - Test: question review shows correct/wrong/unanswered with answer text
  - Test: "practice_weak_sections" event redirects with correct section_ids param
  - Test: accessing another user's session_id → 403

- [ ] **Run `mix test` — all tests pass**
- [ ] **Visual verification: start test server with `scripts/i/visual-test.sh start`**
  - Navigate to briefing screen, screenshot
  - Start an exam, answer 3 questions, screenshot
  - Submit, screenshot results screen
  - Verify timer renders, section tabs render, answer options are plain grey (no colour feedback)

---

### Phase 3 — Analytics, Integrations & Notifications

**Goal:** The results screen shows time management analytics. Readiness scores incorporate exam simulation data. Study Path surfaces exam-based recommendations. Parent/teacher can see results.

#### 3-A. Time Management Analytics Module

- [ ] **`FunSheep.Assessments.ExamAnalytics`**
  - File: `lib/funsheep/assessments/exam_analytics.ex`

  **`section_pacing/1`** — `(session) → [section_pacing_t]`
  ```
  section_pacing_t = %{
    name: String.t(),
    budget_seconds: integer,
    used_seconds: integer,
    delta_seconds: integer,   # positive = over, negative = under
    status: :on_track | :over | :under,
    question_count: integer
  }
  ```
  - Compute `used_seconds` by summing `time_spent_seconds` from `answers` for each section's question IDs
  - Retrieve `budget_seconds` from `section_scores` or format template

  **`question_time_distribution/1`** — `(session) → [question_time_t]`
  ```
  question_time_t = %{
    position: integer,
    question_id: Ecto.UUID.t(),
    time_spent_seconds: integer,
    avg_time_seconds: float,     # across all students who answered this Q (or session avg)
    relative_speed: :fast | :normal | :slow | :very_slow,
    flagged: boolean,
    answered: boolean,
    is_correct: boolean | :pending
  }
  ```
  - `relative_speed` thresholds: `:slow` if > 1.5× avg, `:very_slow` if > 2× avg
  - For now, use session-internal average (per-question cohort avg is a Phase 4 enhancement)

  **`insight_callouts/1`** — `(session) → [String.t()]`
  - Generate human-readable insights:
    - If ≥ 1 section over budget: "You spent {N} minutes over budget on {Section}. Consider a per-question time limit of {budget/count} minutes."
    - If flagged questions were never returned to: "You flagged {N} questions for review but didn't return to {M} of them."
    - If a single question took > 3× average: "Question {i} took {T} minutes — that's {X}× the session average."
    - If timed_out and > 5 unanswered: "Time ran out with {N} questions unanswered. Try reserving the last 5 minutes to guess remaining questions."

  **`weak_sections/1`** — `(session) → [section_name: String.t()]`
  - Returns sections where score < 0.70 OR time_used > time_budget
  - Used by "Practice Weak Sections" button

- [ ] **Wire analytics into Results LiveView**
  - In `ExamSimulationLive.Results.mount/3`:
    - Call `ExamAnalytics.section_pacing/1` → assign `section_pacing`
    - Call `ExamAnalytics.question_time_distribution/1` → assign `question_times`
    - Call `ExamAnalytics.insight_callouts/1` → assign `insights`
    - Call `ExamAnalytics.weak_sections/1` → assign `weak_sections`
  - Update template:
    - Add section pacing table (§5.1 layout)
    - Add per-question time bar chart (simple CSS bar chart, no JS charting library required)
    - Add insight callout cards (amber background)

#### 3-B. Readiness Score Integration (ES-7)

- [ ] **Verify `question_attempts` rows are written at submit**
  - In `ExamSimulationEngine.submit/1`: after grading, insert one `question_attempt` row per question
  - Fields: `user_role_id`, `question_id`, `is_correct`, `time_taken_seconds`, `difficulty_at_attempt`, `source: :exam_simulation`
  - Existing `ReadinessCalculator.calculate/2` will naturally pick up these attempts (no changes needed if it already queries all `question_attempts` for the user)
  - **Verify** `ReadinessCalculator` does not filter out `:exam_simulation` source — check the query and add it if missing

- [ ] **Enqueue readiness recalculation after exam submit**
  - In `ExamSimulationEngine.submit/1`: enqueue `ReadinessRecalcWorker` (already exists) with `{user_role_id, schedule_id}`
  - Verify worker is in the `:assessments` queue and has sufficient concurrency

- [ ] **Readiness dashboard: exam simulation marker**
  - File: `lib/funsheep_web/live/readiness_dashboard_live.ex` (existing)
  - In the readiness history chart data source: join `exam_simulation_sessions` (status: submitted/timed_out) alongside existing `readiness_scores`
  - Add a distinct data point type: `%{type: :exam_simulation, score: session.score_pct × 100, at: session.submitted_at}`
  - Render as a different marker shape/colour (e.g., diamond vs. circle) in the chart
  - Tooltip: "Exam Simulation — {score}% — {date}"

#### 3-C. Study Path Integration

- [ ] **`StudyPath` weak section recommendations**
  - File: `lib/funsheep/assessments/study_path.ex` (existing — add or modify recommendation logic)
  - After a completed exam simulation:
    - Identify sections with score < 70%
    - Map those section names → chapter IDs (via format template or question metadata)
    - Surface as `%{type: :exam_simulation_followup, chapter_ids: [...], priority: :high}` recommendation
  - In the Study Path UI: show callout "You scored {N}% on {Section} in your exam simulation. Drill it before your test." with [Practice Now] button

- [ ] **"Practice Weak Sections" deep-link from Results screen**
  - `ExamSimulationLive.Results` "practice_weak_sections" event (Phase 2 partially covered):
    - Get section names from `weak_sections`
    - Look up chapter_ids for those sections from the format template structure
    - Redirect to `/courses/:id/practice?chapter_ids=<csv>&source=exam_simulation`
  - Verify `PracticeLive` accepts and applies `chapter_ids` query param on mount (add if not present)

#### 3-D. Course Dashboard Button

- [ ] **Add "Take Exam Simulation" button to course dashboard**
  - File: find the course dashboard LiveView (likely `lib/funsheep_web/live/course_live/show.ex` or similar)
  - Conditions to show the button:
    - User has a linked `TestSchedule`
    - Subscription allows exam simulation (`Billing.check_exam_simulation_allowance/1`)
    - ≥ 30 in-scope questions in the bank
  - Urgency indicator: if test date ≤ 7 days away → amber badge "7 days until {Test Name} — simulate now"
  - Button states:
    - Normal: [Take Exam Simulation]
    - Active session: [Resume Exam (Xmin remaining)]
    - Too few questions: [Exam Simulation] (disabled, tooltip "Your question bank is still growing")
    - Not subscribed: [Exam Simulation 🔒] → upgrade flow

#### 3-E. Parent / Teacher Results View

- [ ] **Exam simulation in student progress views**
  - File: parent/teacher dashboard LiveView (find the student progress view used by parents/teachers)
  - Add "Exam Simulations" section or tab showing:
    - List of completed sessions (date, score, time-out vs. submitted)
    - Score trend chart (simple list of scores by date is sufficient MVP)
  - No sharing action needed — already visible to parent/teacher for their supervised student
  - Verify data query scope: parent/teacher can only see sessions for students they supervise (use existing `supervised_user_ids/1` or equivalent)

#### 3-F. Phase 3 Tests

- [ ] **Unit tests: `ExamAnalytics`**
  - File: `test/funsheep/assessments/exam_analytics_test.exs`
  - `section_pacing/1` with over-budget section → status: :over
  - `section_pacing/1` with under-budget section → status: :under
  - `question_time_distribution/1` → slow/very_slow thresholds correct
  - `insight_callouts/1` with timed-out session + unanswered → includes time-management insight
  - `insight_callouts/1` with flagged-unvisited questions → includes flag insight
  - `weak_sections/1` → sections below 0.70 or over budget returned; sections above not included

- [ ] **Integration test: exam submit → question_attempts written → readiness recalc enqueued**
  - File: `test/funsheep/assessments/exam_simulation_engine_test.exs` (add integration cases)
  - Use `Oban.Testing` to verify worker enqueued after submit

- [ ] **LiveView tests: Results screen analytics**
  - Update `test/funsheep_web/live/exam_simulation_live/results_test.exs`
  - Test: section pacing table renders with correct budget/used values
  - Test: insight callout appears for over-budget section

- [ ] **LiveView tests: "Practice Weak Sections" redirect**
  - Test: clicking "Practice Weak Sections" redirects to `/courses/:id/practice?chapter_ids=...`

- [ ] **Run `mix test` — all tests pass**
- [ ] **Visual verification** (test server):
  - Complete a full exam session (submit)
  - Screenshot results screen showing analytics section
  - Confirm time bars render; confirm insight callout appears

---

### Phase 4 — Polish, Edge Cases & Hardening

**Goal:** The feature handles all edge cases gracefully, works well on mobile, is accessible, and avoids question repetition on retakes.

#### 4-A. Unseen-First Question Selection

- [ ] **Wire `Questions.exam_question_ids_seen_by_user/2` into `ExamSimulationEngine.build_session/3`**
  - Load seen question IDs for this user + course
  - In `Questions.list_for_exam/1`, add `exclude_ids` option: if `seen_ids` is non-empty, prefer questions NOT in `seen_ids` by ordering `CASE WHEN id = ANY(:seen_ids) THEN 1 ELSE 0 END ASC` before `RANDOM()`
  - After exhausting unseen, fill remaining slots with seen questions (shuffled)

- [ ] **Test: second exam session for same user has lower overlap with first**
  - Not a strict test (randomness), but verify that at least N of M questions differ when bank is ≥ 2× session size

#### 4-B. Retake Cooldown (pending product decision — default: 24h)

- [ ] **`ExamSimulations.cooldown_remaining/2`** — `(user_role_id, course_id) → {:ok, :ready} | {:ok, {:cooldown, seconds_remaining}}`
  - Query: `SELECT MAX(submitted_at) FROM exam_simulation_sessions WHERE user_role_id = $1 AND course_id = $2 AND status IN ('submitted','timed_out')`
  - If last submitted < 24h ago: return `{:ok, {:cooldown, remaining_seconds}}`
  - If no prior session or last > 24h ago: return `{:ok, :ready}`
- [ ] **Wire cooldown into `ExamSimulationLive.Index.mount/3`**
  - If in cooldown: show disabled state with "Next simulation available in Xh Ym"
  - [Start Exam] button disabled

#### 4-C. Minimum Question Bank Gate

- [ ] **`ExamSimulations.bank_sufficient?/2`** — `(user_role_id, course_id) → boolean`
  - Count in-scope questions: `SELECT COUNT(*) FROM questions WHERE course_id = $1 AND chapter_id = ANY($2)`
  - Return `count >= 30`
- [ ] **Wire into Index mount** (Phase 2 had a placeholder — implement the real check here)
- [ ] **If insufficient bank during `build_session`**: return `{:error, :bank_too_small}` with count; LiveView renders specific user-facing message

#### 4-D. Mobile Layout Pass

- [ ] **Exam interface — mobile breakpoints**
  - File: `ExamSimulationLive.Exam` template
  - Timer: pinned to top bar on all screen sizes
  - Section navigation: on mobile (< 768px), replace horizontal tab bar with bottom sheet drawer (`fixed bottom-0 w-full`)
  - Question overview grid: 5 dots per row max on mobile vs. 10 on desktop
  - Answer options: full-width tap targets (min 44px height per WCAG touch target guidance)
  - "Submit Exam" button: full-width on mobile, bottom of screen
  - Test on 375px (iPhone SE) and 768px (iPad) widths

- [ ] **Results screen — mobile**
  - Section pacing table: horizontally scrollable on small screens
  - Question review: expandable cards stack vertically (already row-based, verify spacing)

#### 4-E. Accessibility Pass (WCAG AA)

- [ ] **Timer**
  - Add `aria-live="polite"` region that announces remaining time every minute and on urgency changes (not every second — too noisy)
  - At timeout: announce "Time is up. Your exam has been submitted."

- [ ] **Answer options**
  - `role="radiogroup"` on option container, `role="radio"` on each option
  - `aria-checked="true/false"` on selected option
  - Keyboard navigation: Tab to focus group, arrow keys to cycle options, Space/Enter to select

- [ ] **Flag button**
  - `aria-label="Flag question X for review"` / `aria-pressed="true/false"`

- [ ] **Section navigation**
  - Section tabs: `role="tab"` / `aria-selected="true/false"` / `tablist` wrapper
  - "N of M answered" progress: include as `aria-label` on tab

- [ ] **Submit modal**
  - `role="dialog"` / `aria-modal="true"` / focus trap when open
  - Confirmation button: `aria-describedby` pointing to the warning text

- [ ] **Results screen**
  - Section pacing table: `<caption>` element for screen readers
  - Correct/wrong per question: use text ("Correct" / "Wrong" / "Unanswered"), not color alone

- [ ] **Color contrast**
  - Timer amber/red text on dark navy: verify ≥ 4.5:1 ratio
  - "Over budget" amber on light background: verify ratio

#### 4-F. Graceful Degradation: AI Grading Pending State

- [ ] **Results screen: pending AI grades**
  - If `is_correct: :pending` for any SA/FR question: show spinner / "Grading..." for that question
  - Poll via `Phoenix.LiveView.send_update` or PubSub: when AI grading completes, push updated score to LiveView
  - Final score section: show "Final score updating..." until all AI grades resolve
  - Timeout: if AI grading not complete within 5 minutes, mark as `:grading_failed`, show "Manual review needed" for that question

- [ ] **Oban worker: `FunSheep.Workers.ExamGradingWorker`**
  - Triggered by submit for SA/FR questions
  - Uses existing `ScoredFreeformGrader` or `EssayGrader` (same as Assessment)
  - On completion: updates the `answers` JSONB entry for the question, recalculates `score_correct` / `score_pct`, broadcasts `{:exam_grading_complete, session_id}` via PubSub

#### 4-G. Final Validation Checklist

- [ ] **All ES-1 through ES-7 invariants tested**
  - ES-1: verify no CSS class reveals correctness during exam (grep templates for `correct`, `wrong`, `green`, `red` within exam.html.heex — none allowed except timer urgency)
  - ES-2: verify auto-submit at tick ≤ 0 in LiveView test
  - ES-3: verify section structure matches format template in engine unit test
  - ES-4: verify `time_spent_seconds` is computed server-side (no client clock dependency)
  - ES-5: verify reconnect test passes (ETS miss → DB fallback → correct remaining time)
  - ES-6: verify unanswered questions counted as wrong in submit unit test
  - ES-7: verify `question_attempts` rows written and `ReadinessRecalcWorker` enqueued

- [ ] **Run full test suite: `mix test --cover`**
  - Overall coverage remains ≥ 80%
  - New modules `ExamSimulationEngine`, `ExamSimulations`, `ExamAnalytics` individually ≥ 80%

- [ ] **Run `mix credo --strict`** — no new violations

- [ ] **Run `mix sobelow`** — no new security issues

- [ ] **Final visual verification** (test server, Playwright agent):
  - Full exam flow: briefing → start → answer → flag → navigate → submit
  - Timeout flow: set time_limit to 5 seconds in test session, verify auto-submit fires
  - Results screen with analytics
  - Mobile viewport screenshots (375px)
  - Reconnect flow: answer a question, refresh page, verify answer persists and timer is correct

---

### Phase Summary

| Phase | Deliverable | Gate to proceed |
|-------|-------------|-----------------|
| **1** | DB migrations + engine + Oban worker | All engine unit tests pass; `mix test --cover` ≥ 80% for new modules |
| **2** | Full LiveView flow (briefing → exam → results stub) | LiveView tests pass; visual screenshots show no colour feedback during exam |
| **3** | Analytics, readiness integration, course dashboard button | Analytics unit tests pass; integration test confirms readiness recalc enqueued; visual confirms analytics render |
| **4** | Mobile, accessibility, unseen-first, cooldown, graceful AI grading | Full test suite passes; WCAG checklist complete; `mix credo --strict` clean |

---

## 10. Open Questions

| Question | Decision needed by | Impact |
|----------|--------------------|--------|
| **Pause allowed?** | Product | If yes: add `elapsed_at_pause` tracking and a resume flow. Default: NO (mirrors real exam conditions). Teacher/admin can override per-schedule. |
| **Section time limits enforced separately?** | Product | Real SAT enforces per-section clocks. Default: global timer only (simpler). Per-section enforcement is a Phase 2+ enhancement. |
| **Minimum question bank size to offer the mode?** | Product | If a course has < 20 questions, exam simulation is nearly meaningless. Suggested gate: ≥ 30 questions in scope before showing the button. |
| **Retake cooldown?** | Product | Prevent gaming readiness score by retaking immediately until a lucky score. Suggested: 24h cooldown between exam simulations per course. |
| **Share results with parent/teacher?** | Product | Exam simulation results should probably flow to parent/teacher dashboard the same way Assessment results do. Flag if this needs a separate notification. |
| **AP-style DBQ (multi-passage essays)?** | Future | Block `free_response` questions with `metadata.subtype: :dbq` from exam simulation until the Essay Tests feature lands. |

---

## 11. Success Metrics

| Metric | Target |
|--------|--------|
| Students who take ≥1 exam simulation before their test date | > 40% of students with a linked TestSchedule |
| Post-simulation readiness delta (simulation score vs. prior readiness) | Correlation ≥ 0.7 (simulation should predict final readiness) |
| "Practice Weak Sections" click-through from results screen | > 25% of completed simulations |
| Session abandonment rate (left without submitting, not timed-out) | < 15% |
| Time-to-submit after entering exam (proxy for engagement depth) | > 60% of sessions use ≥ 70% of time allotment |

---

## 12. Relationship to North Star Invariants

This feature adds a fourth point in the core learning loop (after diagnose → confirm → practice):

```
          ┌────────────────────────────────────────────┐
          │                                            │
          ▼                                            │
   ┌───────────┐    wrong     ┌──────────────────┐    │
   │ Diagnose  │─────────────▶│ Confirm + Probe   │    │
   │ (assess)  │              └────────┬─────────┘    │
   └─────┬─────┘                       │              │
         │ correct                     ▼              │
         ▼                    ┌──────────────────┐    │
   ┌───────────┐              │ Weak-topic       │    │
   │ Practice  │◀─────────────│ practice loop    │────┘
   │ (drills)  │  readiness   └──────────────────┘
   └─────┬─────┘   improves
         │
         ▼  (when readiness high + test date approaching)
   ┌───────────────────────────┐
   │  EXAM SIMULATION          │
   │  (full test, timed, no    │
   │   hints, pacing debrief)  │
   └───────────────────────────┘
         │
         ▼
   Time management debrief
   + targeted weak-section practice
```

Exam Simulation does not replace Assessment or Practice — it comes after them, when the student believes they are ready. It answers the question: "Am I actually ready for test day, not just for my daily drills?"

**North Star invariants respected:**
- **I-1** (skill tagging): Questions drawn from the same skill-tagged bank; no untagged questions in exam sessions.
- **I-15** (fail honestly): If insufficient questions exist, warn and explain — never silently serve a shorter exam than specified without disclosure.
- **I-16** (no fake fallbacks): Exam simulation never generates fake questions or scores; grading failures surface as explicit error states.
- **ES-1 through ES-7**: New invariants specific to this mode (§1.3 above).
