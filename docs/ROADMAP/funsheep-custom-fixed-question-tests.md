# FunSheep — Custom Fixed-Question Tests: Strategy & Roadmap

> **For the Claude session implementing this feature.** Read the entire document before writing a single line of code. The distinction between the current adaptive engine and a fixed-question test is load-bearing; conflating them produces broken UX and broken scoring.

---

## 0. Context & Purpose

FunSheep currently delivers **adaptive assessments**: the engine selects questions dynamically from the course question bank, adjusting difficulty based on student performance. This is powerful for identifying weak skills, but it means the test content is different for every student.

Some users need a **completely different contract**: they supply the exact questions and answers, and every student sees exactly those questions, in order or shuffled. Use cases:

- A **teacher** creates a chapter quiz from their own problem set (PDF, typed list, or image).
- A **parent** assembles a weekend review set from questions they clipped out of a workbook.
- A **student** types their flash-card deck into FunSheep and takes it as a timed self-test before tomorrow's exam.
- A **school admin** distributes a district-standardized quiz to all enrolled students.

This feature is called a **Custom Test** (internally: a `FixedTestBank` with a `FixedTestSession`). It sits alongside the existing adaptive flow, not inside it.

---

## 1. Feature Definition

### 1.1 What a Custom Test Is

A Custom Test is a named, versioned set of question-answer pairs authored directly by the creator (teacher/parent/student). The engine:

1. Serves exactly and only those questions — no questions are drawn from the course bank.
2. Marks each answer against the exact answer provided by the creator.
3. Does **not** run the adaptive skill-state machine (no `engine_state`, no `skill_states` map).
4. Produces a simple scorecard: correct / total, per-question breakdown.

### 1.2 What It Is Not

- Not a format template applied to the existing question bank.
- Not a subset-scope adaptive test.
- Not AI-generated questions. Creator-supplied content only.
- Not automatically connected to chapters/sections (though questions can optionally be tagged for readiness cross-reference).

### 1.3 Who Can Create Them

| Role | Can create | Can assign to | Notes |
|------|-----------|---------------|-------|
| Teacher | Yes | Any student they supervise | Full access; can set deadline, time limit, visibility |
| Parent | Yes | Their own child | Limited to household; cannot assign to other students |
| Student | Yes | Themselves only | Private self-test; cannot share upward |
| Admin | Yes | Any user in school | Bulk-assign to class rosters |

### 1.4 Differentiation from Adaptive Tests

| Property | Adaptive (today) | Custom Fixed (new) |
|----------|-----------------|-------------------|
| Question source | Course question bank (AI-generated, OCR'd) | Creator-authored Q&A pairs |
| Question selection | Engine chooses based on skill/difficulty | Fixed order (or shuffled) |
| Grading | Per-attempt difficulty scoring, skill-state | Simple correct/incorrect match |
| Readiness impact | Updates readiness scores | Does NOT update readiness scores |
| Session state model | `AssessmentSessionState` (engine_state JSON) | `FixedTestSession` (simpler) |
| Reuse | Implicit (bank always available) | Explicit versioned bank; can be retaken |
| Visual marker | Standard test icon | **Custom Test badge** (distinct color/icon) |

---

## 2. Data Model

### 2.1 New Schema: `fixed_test_banks`

```
fixed_test_banks
  id                  uuid PK
  title               string NOT NULL
  description         text
  created_by_id       uuid FK → user_roles.id NOT NULL
  course_id           uuid FK → courses.id (nullable — can be standalone)
  visibility          enum(private, shared_link, class, school) default private
  shuffle_questions   boolean default false
  time_limit_minutes  integer (nullable = untimed)
  max_attempts        integer default null (null = unlimited)
  version             integer default 1
  archived_at         timestamp (null = active)
  inserted_at         timestamp
  updated_at          timestamp
```

**Visibility semantics:**
- `private` — only creator + explicitly assigned users can take it
- `shared_link` — anyone with the link can take it (no auth required, or auth-gated TBD)
- `class` — all students in creator's class(es) can see it
- `school` — all students at creator's school can see it

### 2.2 New Schema: `fixed_test_questions`

```
fixed_test_questions
  id                  uuid PK
  bank_id             uuid FK → fixed_test_banks.id NOT NULL
  position            integer NOT NULL  (1-based, display order)
  question_text       text NOT NULL
  answer_text         text NOT NULL     (the canonical correct answer)
  question_type       enum(multiple_choice, short_answer, true_false) default multiple_choice
  options             jsonb             (for MC: [{value, label}]; null for short_answer)
  explanation         text              (optional; shown after answer)
  points              integer default 1
  image_url           string            (optional question image)
  inserted_at         timestamp
  updated_at          timestamp
```

**Why a separate table and not `questions`?** The existing `questions` table is tightly coupled to:
- Course/chapter/section hierarchy (classification, `section_id NOT NULL` for adaptive eligibility)
- Validation/classification pipeline (status fields, AI scoring)
- Source material provenance

Custom test questions bypass all of that. A clean separation avoids poisoning the adaptive question bank with unvalidated/unclassified content and prevents the ABSOLUTE RULE from requiring AI validation for every typed question.

### 2.3 New Schema: `fixed_test_assignments`

```
fixed_test_assignments
  id                  uuid PK
  bank_id             uuid FK → fixed_test_banks.id NOT NULL
  assigned_by_id      uuid FK → user_roles.id NOT NULL
  assigned_to_id      uuid FK → user_roles.id NOT NULL   (the student)
  due_at              timestamp (nullable)
  note                text (optional teacher note)
  inserted_at         timestamp
```

### 2.4 New Schema: `fixed_test_sessions`

```
fixed_test_sessions
  id                  uuid PK
  bank_id             uuid FK → fixed_test_banks.id NOT NULL
  user_role_id        uuid FK → user_roles.id NOT NULL
  assignment_id       uuid FK → fixed_test_assignments.id (nullable for self-tests)
  status              enum(in_progress, completed, abandoned) default in_progress
  started_at          timestamp
  completed_at        timestamp (null until done)
  time_taken_seconds  integer (null until done)
  score_correct       integer
  score_total         integer
  answers             jsonb    (array of {question_id, answer_given, is_correct, time_taken_seconds})
  inserted_at         timestamp
  updated_at          timestamp
```

**Why not reuse `AssessmentSessionState`?** That table has a composite PK on `(user_role_id, schedule_id)` designed for one active session per schedule. Custom tests allow multiple attempts (if `max_attempts` allows), so sessions need their own PK. Also, the `engine_state` blob is unnecessary here.

### 2.5 Relationship to Existing Schemas

```
TestSchedule                   FixedTestBank
  └─ (optional link)           └─ fixed_test_questions
       bank_id (nullable)           (question data lives here)
  └─ format_template_id        └─ fixed_test_assignments
       (existing adaptive)          └─ user_roles (student)
                                └─ fixed_test_sessions
                                     (attempt history)
```

**Optional bridge:** A `TestSchedule` can optionally reference a `fixed_test_bank_id`. If set, the assessment engine is bypassed and the fixed delivery engine runs instead. This lets teachers attach a custom quiz to a test date in the calendar without creating a second scheduling concept.

Add nullable `fixed_test_bank_id uuid` to `test_schedules`.

---

## 3. Question Authoring UX

### 3.1 Entry Points

1. **Teacher/parent/student Dashboard → "Create Custom Test"** button (new item in left sidebar or floating action)
2. **Test Schedule creation flow** → option to "attach a fixed question bank" instead of (or in addition to) a format template
3. **Course page → "Create Quiz for this Course"** shortcut (pre-fills `course_id`)

### 3.2 Authoring Flow

```
Step 1 — Test Info
  ┌────────────────────────────────────────────────────┐
  │ Title: [________________________]                  │
  │ Description (optional): [___________]              │
  │ Course (optional): [dropdown]                      │
  │ Time limit: [untimed ▾] or [45] minutes            │
  │ Shuffle questions: [ ] Yes                         │
  │ Max attempts: [unlimited ▾]                        │
  └────────────────────────────────────────────────────┘

Step 2 — Add Questions
  [+ Add Question] [Import from text ▾] [Import image ▾]

  For each question:
  ┌────────────────────────────────────────────────────┐
  │ Q1  [Type: Multiple Choice ▾]           [↑][↓][🗑] │
  │ Question: [_____________________________________]   │
  │                                                    │
  │ ○ Option A: [___________]  ← Correct               │
  │ ○ Option B: [___________]                          │
  │ ○ Option C: [___________]                          │
  │ ○ Option D: [___________]                          │
  │ [+ Add option]                                     │
  │                                                    │
  │ Explanation (optional): [___________]              │
  │ Points: [1]                                        │
  └────────────────────────────────────────────────────┘

Step 3 — Visibility & Assign
  Visibility: [Private ▾]
  
  Assign to students: [search/select]
  Due date: [optional date picker]
  Note: [optional message]

  [Save Draft] [Publish & Assign]
```

### 3.3 Bulk Import

**Paste-from-text parser** (AI-assisted, same pattern as `FormatParser`):

Input text format (flexible):
```
1. What is the powerhouse of the cell?
   a) Nucleus
   b) Mitochondria *
   c) Ribosome
   d) Golgi apparatus

2. True or False: DNA is double-stranded.
   Answer: True
```

Parser (using Haiku, low cost) extracts:
```json
[
  {
    "position": 1,
    "question_text": "What is the powerhouse of the cell?",
    "question_type": "multiple_choice",
    "options": [
      {"value": "a", "label": "Nucleus"},
      {"value": "b", "label": "Mitochondria"},
      {"value": "c", "label": "Ribosome"},
      {"value": "d", "label": "Golgi apparatus"}
    ],
    "answer_text": "b"
  },
  {
    "position": 2,
    "question_text": "True or False: DNA is double-stranded.",
    "question_type": "true_false",
    "answer_text": "true"
  }
]
```

User reviews extracted questions in the authoring UI before saving. No questions are saved until user explicitly confirms.

**Image import** (Phase 2): Upload a worksheet image → OCR → same paste parser. Uses existing OCR pipeline infrastructure.

---

## 4. Test Delivery Engine

### 4.1 New Module: `FunSheep.FixedTests`

Context functions:
```elixir
# Bank CRUD
create_bank(attrs)
update_bank(bank, attrs)
archive_bank(bank)
get_bank!(id)
list_banks_by_creator(user_role_id)

# Questions
add_question(bank, attrs)
update_question(question, attrs)
delete_question(question)
reorder_questions(bank, [{id, position}])
bulk_import_questions(bank, parsed_questions)

# Assignments
assign_bank(bank, assigned_by, student_user_role_ids, opts)
list_assignments_for_student(user_role_id)
list_assignments_by_creator(user_role_id)

# Sessions
start_session(bank_id, user_role_id, assignment_id \\ nil)
submit_answer(session, question_id, answer)
complete_session(session)
get_session!(id)
list_sessions_for_bank(bank_id)
list_sessions_for_student(user_role_id)
```

### 4.2 New LiveView: `FixedTestLive`

Route: `/tests/fixed/:session_id`

State:
```elixir
%{
  session: %FixedTestSession{},
  bank: %FixedTestBank{},
  questions: [%FixedTestQuestion{}],  # in display order (shuffled if bank.shuffle_questions)
  current_index: 0,
  answers: %{question_id => answer_text},
  timer_ref: reference | nil,         # for countdown if time_limit set
  elapsed_seconds: 0,
  phase: :taking | :reviewing | :complete
}
```

Delivery modes:
- **Linear**: one question at a time; cannot go back (strict mode, optional)
- **Free navigation**: all questions visible, student can jump (default)

### 4.3 Grading

For multiple_choice and true_false: exact string match on `answer_text`.

For short_answer: **Phase 1** — creator provides the canonical answer; grading is exact string match (case-insensitive, trimmed). UI shows "Mark as correct / incorrect" override so teacher can review borderline answers.

**Phase 2**: AI-assisted short_answer grading (same Haiku-based pattern already used for free_response in the adaptive engine).

### 4.4 Results Scorecard

After completing:

```
Results — "Chapter 5 Quiz" by Ms. Johnson
──────────────────────────────────────────
Score: 8 / 10 (80%)  ⏱ 7:34

Q1  ✓  What is the powerhouse of the cell?
       Your answer: Mitochondria
Q2  ✗  Which organelle processes proteins?
       Your answer: Mitochondria
       Correct:     Golgi apparatus
       Explanation: The Golgi apparatus packages and ships proteins.
...

[Retake] [Done]
```

Creator view additionally shows:
- Per-question accuracy across all takers
- Student-level breakdown (for assigned tests)
- Export to CSV

---

## 5. Access Control & Visibility

### 5.1 Who Can See a Custom Test

A student can take a test if ANY of these is true:
1. They are the creator (self-test)
2. They have a `fixed_test_assignments` row pointing to them
3. The bank's `visibility` is `class` and they are in the creator's class
4. The bank's `visibility` is `school` and they are enrolled at the same school
5. The bank's `visibility` is `shared_link` and they have the link

### 5.2 Attempt Limits

If `bank.max_attempts` is not null, `count(fixed_test_sessions where bank_id AND user_role_id AND status = :completed)` must be < max_attempts before starting a new session.

### 5.3 Guardian Oversight

Parents can:
- See completed sessions for their child (scores + per-question breakdown)
- Create and assign tests to their child
- Cannot see in-progress sessions (privacy)

---

## 6. Visual Identity — "Custom Test" Badge

Custom tests must be clearly distinguishable from AI-adaptive tests everywhere they appear. The CLAUDE.md product north star applies only to adaptive readiness; custom tests operate under a different contract.

**Badge style**: A purple/indigo pill label `Custom Test` (distinct from the green adaptive test markers) wherever the bank appears:
- Upcoming tests dashboard
- Test schedule list
- Student dashboard notifications

**Icon**: Use a checklist/clipboard icon (not the brain/adaptive icon used for adaptive tests).

This visual distinction is important because:
1. Custom tests do NOT update readiness scores (students should not expect that)
2. The grading contract is different (exact match vs. adaptive skill scoring)
3. Parents and students need to know whether the AI or a human chose these questions

---

## 7. Notifications

When a teacher or parent assigns a custom test:
1. Student receives an in-app notification: "Ms. Johnson assigned you a new Custom Test: 'Chapter 5 Quiz' — due Friday"
2. If the student has email/push enabled (per existing `notification_prefs`): external notification
3. Parent is notified when their child completes an assigned test (same as existing completion notifications)

No new notification types needed; route through existing `FunSheep.Notifications` pipeline.

---

## 8. Readiness Score Integration

**Custom tests do NOT update readiness scores.** This is intentional:
- Readiness is computed from the adaptive engine which uses validated, classified questions from the bank
- Custom questions are unvalidated; mixing them into readiness would corrupt the signal
- The product north star invariants I-1 through I-16 apply only to the adaptive flow

What IS tracked from custom tests:
- Raw attempt history in `fixed_test_sessions` for the creator to see
- Aggregate per-question accuracy (to help creator improve their question set)
- Completion status per assigned student (for teacher/parent records)

**Future (Phase 3 — optional):** Optionally allow teachers to "promote" a custom test question into the validated question bank via a lightweight review flow. This would bridge the two worlds for power-user teachers.

---

## 9. Phased Rollout

### Phase 1 — Core (MVP)

**Goal**: Teachers and parents can create, assign, and review fixed question tests.

- [ ] DB migrations: `fixed_test_banks`, `fixed_test_questions`, `fixed_test_assignments`, `fixed_test_sessions`
- [ ] `FunSheep.FixedTests` context (CRUD, assignment, sessions)
- [ ] `FixedTestBankLive` — authoring LiveView (create/edit/delete bank + questions)
- [ ] `FixedTestLive` — taking LiveView (linear navigation, timer, submit)
- [ ] `FixedTestResultsLive` — scorecard (student view, creator view)
- [ ] Assignment creation (select students by name/class, set due date)
- [ ] Student dashboard: pending/upcoming custom tests list
- [ ] Custom Test badge + visual differentiation
- [ ] Basic notifications on assignment
- [ ] Tests: context unit tests, LiveView tests, session grading tests

### Phase 2 — Bulk Import & Image

**Goal**: Reduce friction for teachers who already have question sets.

- [ ] Paste-from-text parser (AI/Haiku) + preview/edit before import
- [ ] Image upload → OCR → parser (reuse existing OCR workers)
- [ ] Short-answer soft grading: teacher can override machine match
- [ ] CSV export of results for creator
- [ ] Class-level visibility (assign to entire class at once)

### Phase 3 — Advanced

**Goal**: Power-user features and ecosystem integration.

- [ ] Question promotion to adaptive bank (teacher review flow)
- [ ] Shared-link mode (public/semi-public distribution)
- [ ] AI-assisted short_answer grading (Haiku)
- [ ] Version history for banks (track edits)
- [ ] Duplicate / fork an existing bank
- [ ] Analytics: per-question difficulty curve across all takers
- [ ] Attach custom test to TestSchedule calendar entry

---

## 10. Technical Considerations

### 10.1 Avoiding Adaptive Engine Entanglement

The adaptive engine (`FunSheep.Assessments.Engine`) must not be modified for this feature. Custom test delivery is a separate code path. The `AssessmentLive` LiveView and `SessionStore` are not touched. The only shared infrastructure is:

- `UserRole` — same auth/access model
- `FunSheep.Notifications` — same notification pipeline
- `StudentGuardian` — same guardian relationship for visibility checks
- Optional: `TestSchedule.fixed_test_bank_id` FK (Phase 3 bridge only)

### 10.2 Session Recovery

Unlike adaptive sessions (which must survive server restarts mid-answer for complex state), fixed test sessions only need to survive page reload. The `answers` jsonb column on `fixed_test_sessions` is updated on every answer submission (upsert). On reconnect, the LiveView re-hydrates from the DB row.

### 10.3 Question Ordering and Shuffle

If `bank.shuffle_questions = true`, the question order is randomized **once at session start** and stored in the session (`answers` array preserves submission order, `questions_order` jsonb stores the shuffled question ID list). This ensures:
- The student sees a consistent order during their session (page reload keeps same order)
- Different students get different orders

Add `questions_order jsonb` to `fixed_test_sessions`.

### 10.4 Multiple Correct Answers (MC)

The `options` jsonb for multiple-choice allows marking multiple options as correct (e.g., "select all that apply"). `answer_text` stores a comma-separated sorted list of correct option values. The UI renders checkboxes instead of radio buttons when `question.options` has more than one answer flagged. Phase 1 can defer multi-select (single correct answer only).

### 10.5 No Fake Content Rule

The no-fake-content rule from `CLAUDE.md` applies: the paste-from-text parser runs real AI inference. If the AI parse fails, the UI shows an error — it does NOT silently create partially-parsed or placeholder questions. The creator must always explicitly confirm imported questions before they are saved.

---

## 11. Open Questions (to Resolve Before Implementation)

1. **Short-answer grading UX in Phase 1**: Should the creator be forced to review all short-answer responses manually, or auto-grade with an "override" button? Recommendation: auto-grade with override.

2. **Anonymous / shared-link mode**: Is this needed in Phase 1, or can we defer? Recommendation: defer to Phase 2.

3. **Does a custom test show up in the student's pinned test countdown?** It can if the assignment has a `due_at` date, but it should not count toward readiness. Recommendation: show in "Upcoming" list but not pin-able and no readiness percentage.

4. **Notification delivery**: Should custom test assignments use the same `digest_frequency` prefs or always deliver immediately? Recommendation: immediate push + in-app; respect existing email digest.

5. **Score display precision**: Show raw score (8/10) or percentage or both? Recommendation: both (80% — 8 of 10 correct).

---

## 12. Success Metrics

- Number of custom test banks created per week (creation engagement)
- Number of assignments sent (teacher activation)
- Test completion rate (assigned → completed %)
- Repeat-use rate (creator edits/reuses same bank for next cohort)
- NPS from teachers who use the feature (qualitative)

---

*Last updated: 2026-04-24*
