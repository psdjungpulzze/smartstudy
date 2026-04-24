# FunSheep — "Teacher" Experience: Implementation Prompt

> **For the Claude session implementing this feature.** Read the entire document before writing any code. The persona research, design principles, and "what already exists" section are load-bearing — skipping them will produce either a parent-dashboard-with-more-rows (useless to real teachers) or a half-finished LMS (a product-strategy mistake).

---

## 0. Project context (what FunSheep is)

FunSheep is a Phoenix 1.7 / Elixir / LiveView test-prep product for K–12 students. The stack and rules:

- **Repo**: `/home/pulzze/Documents/GitHub/personal/funsheep`
- **Web**: `FunSheepWeb.*` under `lib/fun_sheep_web/`
- **Contexts**: `FunSheep.Accounts`, `FunSheep.Courses`, `FunSheep.Questions`, `FunSheep.Assessments`, `FunSheep.Engagement`, `FunSheep.Gamification`
- **Auth**: delegated to Interactor Account Server (JWT in session; `current_user["interactor_user_id"]`)
- **Roles** (`user_roles.role`): `:student | :parent | :teacher | :admin`
- **Jobs**: Oban (no notification queue yet — add one if you build notifications)
- **Mailer**: `FunSheep.Mailer` (Swoosh)
- **UI**: Tailwind per `.claude/rules/i/ui-design.md` — pill-shaped controls (`rounded-full`), cards `rounded-2xl`, primary green `#4CD964`, outlined icons stroke-width 1.5

You MUST read these project rules before coding:

- `/home/pulzze/Documents/GitHub/personal/funsheep/CLAUDE.md` — especially **ABSOLUTE RULE: NO FAKE, MOCK, OR HARDCODED CONTENT**
- `.claude/rules/i/ui-design.md`
- `.claude/rules/i/code-style.md`
- `.claude/rules/i/visual-testing.md` — Playwright verification is mandatory before marking UI tasks complete
- `.claude/rules/i/security.md`

---

## 1. What already exists (and what's broken about it)

| Concern | Where | State |
|---|---|---|
| Teacher role | `user_roles.role` enum (`:teacher`) | Present |
| Teacher-student link | `student_guardians` with `relationship_type: :teacher` | Present — invite flow at `/guardians` works for teachers too |
| School scoping | `user_roles.school_id`, `courses.school_id` | Columns exist; enforcement thin |
| `/teacher` dashboard | `FunSheepWeb.TeacherDashboardLive` (≈210 lines) | **Stub**. Loads a student list, but `readiness_score` and `last_active` are hardcoded to `nil`. Sort-by-readiness sorts on `nil`. No class/period concept, no item analysis, no grouping, no assignment, no standards, no pacing, no export, no parent comms. |
| Readiness engine | `FunSheep.Assessments.readiness_calculator`, `latest_readiness/2`, `readiness_trend/2`, `readiness_percentile/2` | Re-use |
| Question bank | `FunSheep.Questions` | Re-use. Check whether `question.standards` or similar exists; if not, add — see §8.4 |
| Practice engine | `FunSheep.Assessments.practice_engine` (per snapshot) | Re-use for assignment question selection |
| Activity summary | `FunSheep.Engagement.StudySessions.parent_activity_summary/1` | Works for single student — you will need a **cohort** variant |

**Before implementing any feature below, grep for existing functions that may already cover it.** If you see a `parent_*` helper doing roughly what you need for a single student, generalise to a cohort-capable helper rather than fork the code.

### Important inheritance note

Teachers are modelled as guardians (`student_guardians.relationship_type = :teacher`). The same invite flow, same auth check (`guardian_has_access?/2`), same "active link required" rule applies. Teachers differ from parents in **volume** (one parent has 1–3 kids; one teacher has 30–150 students across multiple sections) and in **authority** (teachers author assessments, assign work, report grades). The data model will need a **class/section** abstraction that parents don't need.

---

## 2. Who the teacher persona is (authored as a 15-year classroom veteran)

This section is written from the perspective of an experienced middle-school teacher who has taught through the shift from paper to 1:1 Chromebooks, survived three LMS migrations, sat on PLC data teams, written 504 and IEP referrals, and been audited by a FERPA-anxious district office. It is the ground truth against which every design decision should be checked.

### 2.1 What a real teacher's week looks like

Monday morning the teacher arrives with 28 students across 5 sections (140 total), a pacing calendar that says they're behind by four school days, an upcoming state test 11 weeks out, three IEP accommodations to honour, a new ELL student mid-term, and a PLC meeting Wednesday at 7:30 AM where they need to bring their common-assessment data. They are managing **people, not dashboards**. Every minute a tool adds to their load is a minute stolen from lesson planning or the 20 emails from parents they haven't returned. Every minute a tool saves — if it actually saves it — buys loyalty.

### 2.2 The three jobs a test-prep platform must do for a teacher

1. **Diagnose** — Where is each student *right now*, and where is the whole class? What are they ready for next, and what do I need to reteach before I can move on?
2. **Act** — Given the diagnosis, what do I do? Whole-class reteach? Break into small groups? Assign specific practice to specific students? Escalate to MTSS tier 2/3? Pull a kid for a conference?
3. **Report & communicate** — To parents, to admin, to the student, to the PLC, to myself (for my own planning). Every report must either (a) match the official gradebook, (b) be clearly framed as a supplement to it, or (c) I won't use it, because I cannot defend conflicting numbers in a parent meeting.

A platform that does only #1 is a dashboard — I already have four of those and ignore three. A platform that does all three well is a tool I'll actively teach to a colleague.

### 2.3 What teachers repeatedly ask for (research + practitioner consensus)

From the research (NWEA 2026 tool roundup; Edutopia on time-saving tech; Hanover PLC best practices; Iowa Reading Research Center on flexible grouping; Kim et al. on data-driven grouping; district PLC handbooks; Edweek FERPA explainer):

- **Real-time formative signal** — during-class checks for understanding, instant misconception detection, not a dashboard I check at 10pm
- **Standards-aligned everything** — every item tagged to Common Core / state standard; mastery reported by standard, not just percentage correct
- **Item analysis with distractor view** — for any assessment item: % correct, time per student, which wrong answers were chosen (distractor reveals which misconception), and a click-through to the specific students who chose each option
- **Flexible small-group formation** — suggest groupings of 3–6 based on current mastery, let me override, regenerate when data changes
- **Tiered intervention support (RTI/MTSS)** — surface which students are responding to Tier 1, who needs Tier 2 (5–15% of class), who needs Tier 3 (1–5%); give me the evidence trail for referral paperwork
- **Time-saving authoring** — generate a short-answer quiz from a chapter; generate an exit ticket on a standard; auto-grade objective items; surface subjective items I need to grade myself
- **Differentiated assignment** — assign different question sets to different students/groups from the same launch action
- **Parent communication that honours school norms** — in-app message + email, visible audit trail, bulk template sends, co-signing with admin for disciplinary content, no texting after hours without explicit opt-in
- **Export everything** — CSV for the school SIS, PDF for IEP/504 meetings, printable class report for a substitute
- **Rostering integration** — Clever / ClassLink / Google Classroom / Canvas; I am not typing in 140 names
- **Gradebook interoperability** — read-only passthrough or one-click grade export at minimum; we do not want a second gradebook of truth

### 2.4 Pain points that cause a teacher to abandon a platform within one grading period

These are the landmines. If the implementation steps on any of them, teachers will churn within 6 weeks regardless of feature quality.

1. **Analytics disagree with the gradebook.** If the teacher's gradebook shows a student at 72% and FunSheep shows a "readiness score" of 41%, the teacher has to defend both numbers at conferences and will stop trusting the platform. Fix: always label FunSheep metrics as **readiness** or **mastery**, never as **grade**; never lead with "score" without the qualifier.
2. **One extra data-entry step.** Teachers will not manually enter rosters, pacing, or standards if any other tool already has that data. Every friction step is a churn risk.
3. **Privacy surprises.** A student's score made visible to a parent in a way the teacher didn't anticipate, or a classmate's result leaked through a leaderboard, will trigger a district-level escalation. FERPA violations are career risk.
4. **Analytics on too-small samples.** A "mastery score" built from 3 questions is noise. Teachers can spot it instantly and lose trust in the entire product.
5. **AI-generated content with errors.** If an auto-generated question has a wrong key or a mis-tagged standard, the teacher has to defend it to a parent. One bad item costs more trust than ten good ones earn.
6. **No clear path to "do something."** Dashboards that diagnose without offering actions train the teacher to tune them out. Every diagnostic view must terminate in a button that creates an action (assign, group, message, flag).

### 2.5 Persona-level design heuristic

> **The best teacher tool is the one that makes the next 10 minutes of class visibly better.** If a feature cannot be traced to "teacher does X differently tomorrow and a student benefits," cut it.

---

## 3. Design principles (non-negotiable)

1. **Teachers see their cohort; nothing more.** Authorization at the context edge. A teacher linked to student S1 in class C1 must never see student S2 in a different teacher's class at the same school unless a `class_enrollments` relationship explicitly grants it.
2. **Class/section is a first-class concept.** A teacher has multiple classes; a student can be in multiple classes; a class has a teacher, a course, and a schedule. Do not simulate this by re-interpreting the `student_guardians` table — add a real data model (§8.2).
3. **Every number comes with a denominator.** Show sample size, not just a percentage. "3/5 correct" next to "60% mastery." Teachers will not trust a % shown without its N.
4. **Always provide a next action.** Any diagnostic view ends in a button: *assign, group, message, export, flag for MTSS*. A view that only shows a number is banned.
5. **Readiness ≠ grade.** Never label a FunSheep metric as "grade" anywhere in UI or export. Always "readiness" or "mastery." This is the single biggest trust-preservation rule.
6. **FERPA-safe by default.** Teacher-to-teacher visibility requires explicit sharing (e.g., a PLC share). No accidental all-school leaderboards. Data exports carry a FERPA notice.
7. **Time saved is the metric.** Every feature must be traceable to a time saving or an outcome improvement. If it takes more time than a teacher's current workflow, it will lose.
8. **Students see everything their teachers see about them.** Same transparency rule as the parent design. No secret teacher surveillance views.
9. **No fake data, ever.** Per `CLAUDE.md` absolute rule — if a metric cannot be computed from real student activity (too few attempts, brand-new class, disconnected roster), the UI shows an honest empty-state or "not enough data yet." Never a plausible-looking fake.
10. **Visual testing is mandatory.** Every LiveView touched or created goes through the `visual-tester` agent at mobile / tablet / desktop, light and dark, before you mark a task complete.

---

## 4. Feature scope — phased

Deliver in five phases. Ship, review, and verify each phase before starting the next.

1. **Phase 1 — Foundations: classes, rosters, and a real dashboard**
2. **Phase 2 — Diagnosis: item analysis, standards mastery, cohort insight**
3. **Phase 3 — Action: flexible grouping, differentiated assignment, MTSS tier view**
4. **Phase 4 — Planning: pacing calendar, test scheduling, standards mapping**
5. **Phase 5 — Reporting, communication, and rostering integration**

Details follow.

---

## 5. Phase 1 — Foundations: classes, rosters, and a real dashboard

### 5.1 Data model: class/section

**New schemas — write Ecto migrations:**

```
classes
  id (uuid)
  name :: string                 e.g., "Period 3 — Algebra I"
  school_id :: uuid              nullable for freelance/homeschool teachers
  course_id :: uuid -> courses.id
  teacher_id :: uuid -> user_roles.id   (primary teacher; a class has exactly one primary)
  school_year :: string          e.g., "2025-2026"
  period :: string               nullable, e.g., "3"
  grade_level :: string          e.g., "9"
  archived_at :: utc_datetime    nullable (teachers keep old classes read-only)
  inserted_at, updated_at

class_enrollments
  id
  class_id -> classes.id
  student_id -> user_roles.id
  status :: enum(:invited, :active, :withdrawn)
  invited_at, joined_at, withdrawn_at
  inserted_at, updated_at

class_co_teachers                (optional; supports co-teaching & aides)
  id
  class_id -> classes.id
  co_teacher_id -> user_roles.id
  role :: enum(:co_teacher, :aide, :substitute, :admin_observer)
  starts_on, ends_on :: date (nullable)
  inserted_at, updated_at
```

Indexes: `classes(teacher_id, archived_at)`, `class_enrollments(class_id, status)`, `class_enrollments(student_id, status)`.

**New context**: `FunSheep.Classrooms` — `create_class/2`, `archive_class/1`, `add_student/2`, `remove_student/2`, `list_classes_for_teacher/1`, `list_active_students/1`, `list_co_teachers/1`, `teacher_has_access?/2`, `teacher_has_access_to_student?/2`.

Authorization rule: a teacher has access to a student iff they teach an active, non-archived class with an active enrolment for that student, **or** they are a co-teacher on such a class within their `starts_on..ends_on` window.

### 5.2 Relationship to existing `student_guardians`

Do NOT delete `student_guardians`. The existing guardian-style invite flow is convenient for individual-teacher / tutor use cases where no formal class exists. But for the school-teacher persona, we need classes.

**Rule**: if a teacher creates a class and adds a student, a matching `student_guardians` row with `relationship_type: :teacher` is created automatically (so downstream guardian-access checks continue to work). Inverse is also true — when a student is removed from every class with a teacher, the corresponding guardian row is revoked.

This keeps the two abstractions consistent without forking authorization code.

### 5.3 Rebuild `/teacher` dashboard

Replace the current stub. Route stays `/teacher`; split into:

- **`/teacher`** — classes overview (list of classes the teacher teaches)
- **`/teacher/classes/:class_id`** — single-class dashboard
- **`/teacher/classes/:class_id/students/:student_id`** — single-student drill-down

**Classes overview** (`/teacher`): card per class showing
- Class name, period, course, student count
- Average readiness across the class (with sample size — see principle #3)
- Distribution bar: % of class in `at-risk` / `approaching` / `on-track` / `exceeding` buckets (bucket thresholds configurable; default 0–40 / 40–60 / 60–80 / 80–100)
- Upcoming test if any scheduled (§9 — Phase 4)
- "Open class" CTA

Empty state: "No classes yet. Create your first class." → leads to a create-class wizard that asks for course, period, year, and (optionally) CSV/Clever roster import. In Phase 1 deliver manual add-by-email only; rostering is Phase 5.

**Single-class dashboard** (`/teacher/classes/:class_id`): tabs or sub-sections for
- **Roster** — actually load real `readiness_score` (latest readiness vs the class's most-relevant upcoming test or the course aggregate) and real `last_active` (max `study_sessions.completed_at` for that student). Fix the current stub.
- **Overview** — aggregate cards: average readiness (with N), activity sparkline (class practice minutes/day over last 30 days), % of class with a session in last 7 days, average weekly practice minutes
- **At-risk students** — the teacher's most-used view: list of students in the bottom bucket, with evidence and a "take action" affordance (Phase 3 wires the action)

Data sources:
- `FunSheep.Classrooms.list_active_students/1`
- `FunSheep.Assessments.latest_readiness/2` (or a cohort variant)
- `FunSheep.Engagement.StudySessions.cohort_activity_summary/1` — **new function** generalising the existing `parent_activity_summary/1`

**Single-student drill-down** (`/teacher/classes/:class_id/students/:student_id`): reuse or factor out the same components the parent dashboard uses for a single student (activity timeline, topic mastery map, readiness trend). If those components exist at this point (they may be in progress from the Parent work), import them; if not, build shared components under `FunSheepWeb.StudentLive.Shared.*` so the parent and teacher dashboards render the same student view with role-appropriate framing.

### 5.4 Acceptance criteria (Phase 1)

- [ ] Migrations for `classes`, `class_enrollments`, `class_co_teachers` run cleanly and rollback safely
- [ ] `FunSheep.Classrooms` context complete with authorization helpers
- [ ] `/teacher`, `/teacher/classes/:class_id`, `/teacher/classes/:class_id/students/:student_id` live and functional
- [ ] Roster view shows **real** readiness and last-active values (the current stub's biggest bug fixed)
- [ ] Empty states render correctly — no fake data
- [ ] LiveView tests: mount for each route in authorised / unauthorised / empty / populated states; create-class wizard; add-student-by-email
- [ ] Unit tests for `Classrooms` context
- [ ] Coverage ≥ 80%; `mix format`, `mix credo --strict`, `mix sobelow` all pass
- [ ] Visual verification at 375/768/1440 light+dark

---

## 6. Phase 2 — Diagnosis: item analysis, standards mastery, cohort insight

This is the phase that earns teacher trust. It answers the questions they ask out loud during PLC meetings.

### 6.1 Item analysis view

For any assessment session or question set a teacher's class has completed, the teacher can open an **item analysis** view:

- Table of questions, each row: stem preview, standard tag (§6.3), % of class correct, median time-on-item, difficulty tier
- Click any question to expand: distractor distribution (for multiple-choice: what % chose each option, including the correct one), list of students who got it right / wrong (linked to their drill-down), median time per outcome
- Button: **"Reteach this standard"** — pins the standard to the teacher's reteach queue (Phase 3)
- Button: **"Assign similar practice"** — opens the assignment modal (Phase 3) pre-filled with the standard and the students who got the item wrong

**Implementation**:
- New module `FunSheep.Assessments.ItemAnalysis` — functions `item_stats_for_class/2`, `distractor_distribution/2`, `students_by_outcome/2`
- Back every % with its N (sample size). If N < 5, show "too few responses for reliable analysis."
- Route: `/teacher/classes/:class_id/assessments/:assessment_id/items` or similar.

### 6.2 Cohort mastery heatmap

Grid: students (rows) × chapters or standards (columns), cell colour = mastery band. Teacher-era tool of trade. Should:
- Sort students by a dimension (alpha / readiness / at-risk first / by group)
- Sort columns by standard / chapter / difficulty
- Click a column → reteach / assign (§6.1 actions)
- Click a cell → that student's drill-down for that topic
- Support a "focus" filter that narrows columns to the standards a selected upcoming test covers

**Implementation**:
- `FunSheep.Assessments.cohort_mastery_matrix(class_id, opts)` returning `%{students: [...], dimensions: [...], cells: %{{student_id, dim_id} => score_or_nil}}`
- Honour `nil` for "no attempts yet" — do not silently fill with 0 (that would mis-display untested skills as failed)

### 6.3 Standards tagging — data model addition

If the question schema does not already have a standards field, add:

```
question_standards                   (many-to-many)
  id
  question_id -> questions.id
  standard_id -> standards.id
  confidence :: float (0.0–1.0; for AI-suggested tags)
  tagged_by :: enum(:author, :ai, :teacher)
  inserted_at

standards
  id
  framework :: enum(:common_core, :ngss, :state, :ib, :custom)
  state_code :: string (nullable; e.g., "CA" for California-specific)
  code :: string   e.g., "CCSS.MATH.CONTENT.8.EE.A.2"
  title :: string
  description :: text
  grade_level :: string
  parent_standard_id :: uuid (nullable; for clusters)
  inserted_at, updated_at
```

Seed the `standards` table from Common Core math + ELA as a starting set. Use a real seed script that pulls from an authoritative source or a reviewed fixture — do **not** invent standard codes. If the seed is not yet available, document that standards tagging is "pending data" rather than ship fake codes.

### 6.4 Standards-based mastery report

For each class, for each standard covered by the class's course:
- Class-wide mastery %
- Distribution (histogram of student mastery for that standard)
- Trend over last 4 weeks
- Click → list of students at each mastery band → drill-down

This is the view a teacher brings to a PLC meeting. It should be **exportable as PDF** with a professional header (class name, teacher, date range, standard count, method note). Phase 5 wires export.

### 6.5 Acceptance criteria (Phase 2)

- [ ] Item analysis view renders for any completed class assessment, with real distractor data
- [ ] Cohort mastery heatmap renders with correct cells; null cells rendered distinctively from zero cells
- [ ] Standards data model added; seeded with a real Common Core subset (or documented as pending-data with a feature flag that hides standards UI until seed lands)
- [ ] Standards-based mastery report view lives
- [ ] All percentages show denominators; N<5 views show the "too few responses" notice
- [ ] Tests: unit for `ItemAnalysis` and `cohort_mastery_matrix`; LiveView tests for each new route
- [ ] Coverage ≥ 80%; lints pass; visual verification

---

## 7. Phase 3 — Action: flexible grouping, differentiated assignment, MTSS

This phase turns diagnostic views into interventions.

### 7.1 Flexible grouping tool

Teacher selects a class, a dimension (a chapter, a standard, or an upcoming test), a target group size (3–6), and a strategy (`:homogeneous_needs_work` for targeted reteach, `:heterogeneous` for peer-supported groups, `:homogeneous_advanced` for enrichment). The system:

1. Pulls the mastery matrix for that dimension
2. Clusters students accordingly (simple k-means on the score dimension for homogeneous; stratified pairing for heterogeneous)
3. Produces N groups with explanation cards ("Group 3: Emma, Javier, Priya — all scored 45–55% on Rational Expressions; suggest targeted reteach on inverse operations")
4. Teacher can **override**: drag-and-drop between groups, rename, lock a student, regenerate
5. Save as a named `grouping` that persists until archived (teacher might use it for a week of intervention blocks)

**Schema**:

```
groupings
  id
  class_id -> classes.id
  teacher_id -> user_roles.id
  name :: string
  dimension_type :: enum(:chapter, :standard, :test_schedule)
  dimension_id :: uuid
  strategy :: enum(:homogeneous_needs_work, :heterogeneous, :homogeneous_advanced, :custom)
  target_size :: integer
  archived_at :: utc_datetime (nullable)
  inserted_at, updated_at

grouping_members
  id
  grouping_id -> groupings.id
  student_id -> user_roles.id
  group_label :: string   e.g., "A", "B", "Reteach-1"
  inserted_at, updated_at
```

**Context**: `FunSheep.Classrooms.Grouping` — `suggest/2`, `persist/2`, `regenerate/1`, `override_member/3`, `archive/1`.

### 7.2 Differentiated assignment

Teacher creates an **assignment** — a set of questions (pulled from the bank by standard, chapter, or AI-generated) targeted at one or more groups, individual students, or the whole class. Assignment has a due date, optional time cap, and visibility rules.

**Rules**:
- A teacher can target: whole class, one or more groupings, or an explicit student list
- Assignments from different groupings in the same class can coexist — different students get different work
- Questions are resolved at student-session-start time via the existing practice engine; **do not denormalise** a question list into the assignment table
- Students see the assignment on their dashboard with a "start" CTA
- Teacher sees completion and performance roll-up in real time, drilling into per-student and per-item views (reusing Phase 2 components)

**Schema**:

```
assignments
  id
  class_id -> classes.id
  teacher_id -> user_roles.id
  title :: string
  description :: text
  chapter_ids :: array of uuid (nullable)
  standard_ids :: array of uuid (nullable)
  grouping_id :: uuid (nullable)
  target_type :: enum(:class, :grouping, :students)
  target_student_ids :: array of uuid (nullable; only if target_type = :students)
  question_count :: integer
  difficulty_target :: enum(:auto, :easy, :medium, :hard)
  time_limit_minutes :: integer (nullable)
  due_at :: utc_datetime (nullable)
  status :: enum(:draft, :published, :closed)
  published_at :: utc_datetime (nullable)
  closed_at :: utc_datetime (nullable)
  inserted_at, updated_at

assignment_submissions
  id
  assignment_id -> assignments.id
  student_id -> user_roles.id
  study_session_id -> study_sessions.id (nullable; created when student starts)
  started_at, submitted_at :: utc_datetime (nullable)
  status :: enum(:not_started, :in_progress, :submitted, :late, :excused)
  inserted_at, updated_at
```

Enforce sane caps: question_count ≤ 40, time_limit_minutes between 0–240 or null. Document them in the UI as policy, not just error copy ("Assignments over 40 items tend to fatigue students and reduce data quality; break into multiple shorter assignments").

### 7.3 MTSS / RTI tiered view

For a selected class, show a three-lane view:

- **Tier 1 (core instruction)** — students responding to standard practice. Expected 80–90% of class. Green lane.
- **Tier 2 (strategic)** — students below target on ≥2 consecutive weekly snapshots, or below 50% on the class's primary upcoming test's scope. Expected 5–15%. Yellow lane.
- **Tier 3 (intensive)** — students below target on ≥4 weeks, or below 30% on the primary test scope, or with an active `at_risk_flag` (schema below). Expected 1–5%. Red lane.

**For each Tier 2/3 student**, the card shows:
- Current readiness + trend
- Weakest 2 standards
- Last 5 session summary
- History of support (prior assignments completed, prior groupings that included them, prior notes)
- Buttons: **"Flag for MTSS referral"** (creates a referral record — schema below), **"Assign targeted practice"** (Phase 7.2), **"Add to intervention group"** (Phase 7.1), **"Message parent"** (Phase 5)

**Schema** (intervention notes for evidence trail — critical for referral documentation):

```
intervention_flags
  id
  student_id -> user_roles.id
  class_id -> classes.id
  flagged_by -> user_roles.id (teacher)
  tier :: enum(:tier_2, :tier_3, :referred_sped, :referred_ell, :referred_504, :resolved)
  reason :: text
  evidence_snapshot :: jsonb  (captured at flag time — readiness, weak standards, recent activity)
  resolved_at :: utc_datetime (nullable)
  inserted_at, updated_at
```

**Why the snapshot is critical**: MTSS referral paperwork requires evidence of the condition at the time of referral, not as it looks today. Without a snapshot, the platform is legally and procedurally useless to the teacher. Capture readiness + weak-standard list + recent activity JSON at the moment the flag is created. Do not compute it dynamically on view.

### 7.4 Acceptance criteria (Phase 3)

- [ ] Flexible grouping tool produces deterministic groupings from real mastery data; supports override; persists
- [ ] Assignment creation, publish, submission flow end-to-end with real questions
- [ ] Students see assigned work on their dashboard; performance aggregates correctly back to teacher view
- [ ] MTSS tier view renders with real tier classification derived from real data; evidence snapshot captured at flag
- [ ] Referral record survives subsequent data changes (immutable snapshot)
- [ ] Tests: grouping algorithm unit tests with seeded real attempt data; assignment end-to-end LiveView test; MTSS flag round-trip test
- [ ] Coverage ≥ 80%; lints; visual verification

---

## 8. Phase 4 — Planning: pacing, test scheduling, standards mapping

### 8.1 Test schedule authoring (teacher-facing)

The `test_schedules` table already exists (student-facing). Add a teacher-authoring flow: `/teacher/classes/:class_id/tests`. Teacher can:

- Create a test schedule tied to the class: name, date, scope (chapters, standards), format template
- Set a target readiness score for the class and per-student
- Student-visible countdown on student dashboard once published
- Auto-generates weekly readiness snapshots via a new Oban job (`FunSheep.Workers.WeeklyReadinessSnapshotWorker`) that runs Sundays and computes per-student readiness against upcoming tests; needed for Phase 2 trend data

### 8.2 Pacing calendar

A Gantt-style calendar view per class: `/teacher/classes/:class_id/pacing`. Rows are chapters or units; bars span planned start–end dates. Teacher can:

- Drag bars to reschedule
- Mark a chapter `:complete`; system then checks whether the class has actually practised on it (via `question_attempts` / `study_sessions` grouped by chapter) and warns if the class has <50% coverage of the chapter's questions attempted — a behaviour teachers describe as "calendar lies"
- See a pacing-health indicator: ahead / on-track / behind, based on today's date vs. the chapter schedule

**Schema**:

```
class_pacing
  id
  class_id -> classes.id
  chapter_id -> chapters.id
  planned_start :: date
  planned_end :: date
  actual_completed_at :: date (nullable)
  inserted_at, updated_at
```

### 8.3 Scope-and-sequence awareness

When a teacher creates an assignment or a grouping, the pacing calendar informs suggestions:
- "You haven't scheduled Ratios and Proportions yet — are you sure you want to assign these questions?"
- "This test covers 8 standards your class hasn't practised on — consider scheduling them first."

This is a **soft** check — teacher can override — but it surfaces the inconsistency instead of hiding it.

### 8.4 Acceptance criteria (Phase 4)

- [ ] Test schedule creation from teacher flow; student-side surfaces correctly
- [ ] Weekly readiness snapshot Oban worker runs reliably; job test seeded
- [ ] Pacing calendar renders and persists drag-reschedule
- [ ] "Calendar lies" warning fires when completion is marked without coverage evidence
- [ ] Scope-and-sequence warnings surface in assignment and grouping flows
- [ ] Tests; lints; coverage ≥ 80%; visual verification

---

## 9. Phase 5 — Reporting, communication, and rostering

### 9.1 Reports & export

Teacher-initiated exports:

- **PDF class progress report** — cover page with class meta, per-student summary, per-standard mastery, footer with FERPA notice. Template: `FunSheepWeb.TeacherPdf.class_progress/2` using a PDF library already in the project if present; otherwise add `chromic_pdf` or `pdf_generator`.
- **CSV roster + scores** — columns: student name, email, grade, readiness (latest), % activity days in last 30, last active. Scoped to a single class. Downloadable from `/teacher/classes/:class_id/export`.
- **Per-student IEP/504 snapshot PDF** — on-demand from single-student drill-down; includes evidence snapshot, 90-day activity, standards mastery history.

Every export is served over a short-lived signed token, logged in an `export_log` table (student_id, teacher_id, type, created_at). Exports are not cached — always regenerated from fresh data.

### 9.2 Teacher → parent communication

Teachers can send messages to a student's linked guardians (parents):
- In-app message + email
- Templates: positive note, concern note, missing-work note, meeting request
- Audit trail: every send logged; visible to admin and to the student (design principle #8)
- **Defaults**: no messages outside 7am–7pm local unless the teacher explicitly overrides; no bulk-sends > 30 recipients without an admin-visible confirmation
- Parent can reply (threads store in `teacher_messages` / `teacher_message_replies`)

**Schema**:

```
teacher_messages
  id
  teacher_id -> user_roles.id
  class_id -> classes.id (nullable; for 1:1 messages outside a class)
  student_id -> user_roles.id
  subject :: string
  body :: text
  template_used :: string (nullable)
  sent_at :: utc_datetime
  inserted_at, updated_at

teacher_message_recipients
  id
  teacher_message_id -> teacher_messages.id
  guardian_id -> user_roles.id
  delivered_at, read_at :: utc_datetime (nullable)
  inserted_at, updated_at
```

Email via Swoosh; in-app via a new `notifications` table or the dashboard message widget. Students see a "your teacher contacted your parent about X" note on their own dashboard (transparency rule).

### 9.3 Rostering integration (discovery + first connector)

Deliver one rostering connector; suggest starting with **Google Classroom** (broadest reach in K-12) or **Clever** (most common district SSO). The integration must:

- OAuth from teacher into Google Classroom (or district-initiated Clever SSO)
- Pull course and student list; upsert into `classes` and `class_enrollments`
- Record a `roster_sync` audit row per sync with counts (added / updated / skipped / errored)
- Respect district-level scope: if admin disables auto-sync, teacher sees a read-only roster

**Schema**:

```
roster_sources
  id
  class_id -> classes.id
  provider :: enum(:google_classroom, :clever, :classlink, :canvas, :manual)
  external_id :: string
  last_synced_at :: utc_datetime
  sync_status :: enum(:pending, :syncing, :active, :error)
  sync_error_message :: text (nullable)
  inserted_at, updated_at

roster_syncs
  id
  roster_source_id -> roster_sources.id
  added_count, updated_count, skipped_count, errored_count :: integer
  started_at, completed_at :: utc_datetime
  inserted_at
```

This is the largest item in Phase 5 and may warrant breaking into its own sub-phase. Deliver **discovery + design doc + one connector** in this phase; defer Canvas/ClassLink to a later phase.

### 9.4 PLC share (collegial sharing within a school)

Allow a teacher to share a cohort mastery view or item analysis with another teacher in the same school for a bounded window (default 14 days). This is the product-level translation of PLC practice — collegial data review for targeted instruction.

**Schema**:

```
plc_shares
  id
  shared_by -> user_roles.id
  shared_with -> user_roles.id
  resource_type :: enum(:cohort_mastery, :item_analysis, :standards_report)
  resource_id :: uuid
  class_id -> classes.id (for FERPA scoping)
  expires_at :: utc_datetime
  access_note :: text (optional — why shared)
  revoked_at :: utc_datetime (nullable)
  inserted_at
```

Shared views render with a "Shared by Ms. Park — expires Apr 30" header and are read-only. No drill-down to individual students unless the shared-with teacher also has class access to that student. This is the FERPA guardrail.

### 9.5 Acceptance criteria (Phase 5)

- [ ] PDF and CSV export work end-to-end; audit log records each export
- [ ] Teacher → parent messaging with audit trail; student transparency notice; time-of-day default; admin-visible bulk-send confirmation
- [ ] One rostering connector (Google Classroom or Clever) live with audit and error handling
- [ ] PLC share with expiry, revocation, and FERPA-safe cross-teacher access
- [ ] Tests; lints; coverage ≥ 80%; visual verification; email templates checked in Swoosh dev mailbox at desktop + mobile widths

---

## 10. Cross-cutting technical requirements

### 10.1 Authorization

Every data-fetch called from a teacher flow checks `Classrooms.teacher_has_access?/2` or `Classrooms.teacher_has_access_to_student?/2`. Centralise; call at context-function entry; never rely on LiveView to enforce. Co-teachers check against `class_co_teachers` with active date window.

### 10.2 Query performance

- Cohort queries (mastery matrix, item analysis across 140 students) must be benchmarked. Target: full-class mastery matrix render in <300ms for a 40-student class, <1s for 150.
- Preload associations in context layer; no LiveView N+1.
- Consider materialised views or Cachex-backed memoisation (15-min TTL) for cohort mastery at the `(class_id, dimension)` key.

### 10.3 Timezone

Teachers and their classes are in one timezone (usually the school's). Add `classes.timezone` (default from teacher's `user_roles.timezone`, fall back to UTC). All "today / this week" boundaries bucket by class timezone.

### 10.4 Internationalisation

Wrap all teacher-facing strings in `gettext`. Standards-framework labels (Common Core, NGSS, etc.) are product content, not UI chrome — keep them in the data, not in translations.

### 10.5 Testing requirements

Per `CLAUDE.md`:

- LiveView tests for every new teacher route, covering: unauthenticated, teacher-with-no-classes, teacher-with-one-class-one-student, teacher-with-multi-class-multi-student, teacher-with-archived-class, student-mistakenly-visiting-teacher-route (must redirect), admin-visiting (must allow), parent-visiting-teacher-route (must redirect)
- Unit tests for every `Classrooms`, `ItemAnalysis`, `Grouping`, `Assignment` function with realistic test fixtures (real students, real attempts, real readiness rows)
- Grouping algorithm determinism test (same seed + same data → same groups)
- MTSS tier classification test — verify the snapshot is immutable after flag
- Performance test (or at least documented benchmark) for the cohort mastery query at 40, 100, 150 students
- `mix test --cover` overall coverage ≥ 80%
- Before marking any phase complete, run the `visual-tester` agent at mobile / tablet / desktop in both light and dark mode

### 10.6 Commits and branching

- Branch naming: `feature/teacher-experience-phase-<n>-<slug>`
- One PR per phase (not one giant PR)
- Commit prefixes: `feat(teacher):`, `test(teacher):`, `refactor(teacher):`, `fix(teacher):`
- Origin must be `smartstudy`, not `product-dev-template` — if git push targets the wrong remote, stop and ask
- Do not bypass pre-commit hooks (no `--no-verify`)

### 10.7 Shared components with the Parent experience

The Parent experience (see `funsheep-parent-experience.md` in the same directory) produces shared components:

- Activity timeline
- Topic mastery map (per-student)
- Study heatmap
- Wellbeing signal reframing

If the Parent work is shipped or in-progress when you start, **import those components** from `FunSheepWeb.StudentLive.Shared.*`. If the Parent work has not started, you may implement these first under the shared namespace — but communicate clearly in the PR that you've staked out a shared surface, so the parent-experience engineer can plug in.

### 10.8 What you must NOT do

- Do **not** delete or refactor the existing `student_guardians` table or the `/guardians` invite flow. Classes complement it; they don't replace it.
- Do **not** seed fake classes, fake rosters, fake standards codes, or fake item analysis. Per `CLAUDE.md`: if you need test data, create real data through the real flows.
- Do **not** label any metric "grade" anywhere — always "readiness" or "mastery."
- Do **not** expose teacher-cohort data across schools or across teachers without an explicit PLC share record.
- Do **not** build a full LMS. We integrate with the existing gradebook; we don't replace it.
- Do **not** auto-send messages to parents at night. Defaults matter.
- Do **not** `mix compile` while a dev server is running — the Phoenix live-reloader handles recompilation.
- Do **not** start a test server on port 4040; use `./scripts/i/visual-test.sh start` for an isolated port.
- Do **not** merge or deploy Interactor-workspace repos; those are human-only per hook-enforced policy.

---

## 11. Before you start

1. Start a todo list with `TaskCreate`: one parent task per phase, one child task per numbered subsection. Mark one `in_progress` at a time.
2. Read, in order:
   - Existing `TeacherDashboardLive` (`lib/fun_sheep_web/live/teacher_dashboard_live.ex`) — understand how little is there
   - `FunSheep.Accounts.StudentGuardian` + `list_students_for_guardian`, `invite_guardian`, `accept_guardian_invite`, `guardian_has_access?`
   - `FunSheep.Assessments` public API
   - `FunSheep.Questions` schema to confirm whether a standards field exists
   - Router: `lib/fun_sheep_web/router.ex` — the `:authenticated` live_session and existing `/teacher` mount
   - The Parent implementation prompt at `~/s/funsheep-parent-experience.md` and — if it's been started — the Parent code, so you can share components
3. Confirm dev environment: `mix deps.get && mix ecto.setup && iex -S mix phx.server`. Create 1 teacher, 1 class, 10 real students, and run real practice sessions for 3–5 of them so you have real cohort data to render against. Do not seed fake activity.
4. Pick Phase 1. Build the data model before any LiveView work. Do not try to render class views against `student_guardians` as a shortcut — you will have to redo everything when you add `classes`.

---

## 12. What "done" looks like (whole project)

- A teacher with a roster of 30 students across 3 class sections can: see each class, drill into a class, see real readiness per student, drill into any student, run item analysis on any completed assessment, view cohort mastery by standard, form flexible groups, assign differentiated practice, flag MTSS candidates with evidence snapshots, schedule upcoming tests, manage a pacing calendar, export PDF/CSV reports, message parents with an audit trail, and sync a roster from Google Classroom or Clever.
- A teacher with no classes yet sees honest empty states and a fast create-class path.
- A teacher from one school never sees a student from another school unless a PLC share authorises it.
- Teacher views show readiness, mastery, and activity — never "grade."
- Every percentage carries its denominator.
- All exports carry a FERPA notice and are logged.
- Every view that diagnoses ends in a button that does something.
- Tests ≥ 80% coverage, LiveView tests for every route, all lints pass.
- The existing Parent experience continues to work; where both roles need the same student-view, components are shared, not forked.

If at any point during implementation a feature starts to feel like a dashboard-for-the-sake-of-a-dashboard (diagnose without act), stop and re-read §2.4 and §2.5 — a feature that doesn't change what a teacher does tomorrow is a feature we are not shipping.

---

## 13. Questions to ask before starting

If any of the following are unclear after reading the code, ask the user before writing implementation:

1. Is there a specific school / district design partner driving this, or is this generalised? (Affects rostering connector priority in Phase 5 — Clever if district-led, Google Classroom if broader.)
2. Does the product already have a Common Core (or other) standards seed, or is §6.3 introducing standards data for the first time? If the latter, which framework(s) are in scope? (US Common Core? IB? UK National Curriculum?)
3. Is there an existing gradebook integration requirement (read-only sync or grade passback)? This determines whether Phase 5 stays at "export" or must go further.
4. Is there a cap on class size the platform should support? (Impacts performance budget for Phase 2 cohort queries.)
5. Is a "sub-account" flow required — a teacher logging in while an aide assists — or is co-teaching the only multi-user-on-class case?

Answer these, then begin Phase 1.
