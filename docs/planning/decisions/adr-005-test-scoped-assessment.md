# ADR-005: Test-Scoped Assessment and Readiness

## Status

Accepted

## Date

2026-04-23

## Context

FunSheep's learning loop (per `docs/PRODUCT_NORTH_STAR.md`) is "identify each student's weak topics and loop them on targeted practice until every in-scope skill reaches mastery." The word "in-scope" is load-bearing — it defines what "ready" means and what the practice loop is optimizing for.

Two candidate framings were considered for "in-scope":

| Framing | Unit of readiness | When is it useful? |
|---|---|---|
| **A. Course-scoped (global)** | One readiness score per student per course | Always available, but at cold start (new student) gives near-uniform low readiness everywhere — no signal for prioritization |
| **B. Test-scoped** | One readiness score per `TestSchedule` (name, deadline, chapter scope) | Carries a scope *and* a deadline — the two things the weak-topic loop needs to be actionable |

The product goal is inherently driven by upcoming tests. Students don't ask "am I 100% ready for AP Biology as a whole?" — they ask "am I ready for Friday's Finals?" Framing (A) violates North Star invariant I-15 at cold start (it labels skills on thin evidence — the student hasn't learned most of them yet). Framing (B) inherits both scope (which chapters count) and a forcing function (when they need to be ready), which is what lets weighted practice (I-5), interleaving (I-6), and the mastery target (I-9) actually converge.

A related question: what happens to skill mastery earned studying Test A when Test B is created with overlapping chapters? If mastery is test-scoped, the student has to re-earn it — wasteful and demotivating. If mastery is global and readiness is test-scoped, mastery transfers automatically.

Screenshot evidence from 2026-04-23 (see CR-001) showed the UI violating this framing: the `/assess` page asked students to pick raw upload filenames (`Biology Answers - 31.jpg`) as "question sources" — surfacing the OCR pipeline's plumbing as a student decision. The test's scope was already defined; the extra step was incoherent with the test-scoped model.

## Decision

### 1. Readiness is scoped to a `TestSchedule`

Every readiness score belongs to exactly one `TestSchedule`. A student may have multiple active tests, each with its own readiness score.

Implementation reference (already present in the codebase as of 2026-04-23):
- `FunSheep.Assessments.ReadinessScore` (`lib/fun_sheep/assessments/readiness_score.ex`) has a `test_schedule_id` FK and stores `aggregate_score`, `chapter_scores`, `skill_scores`, `calculated_at`.
- `FunSheep.Assessments.ReadinessCalculator.calculate/2` operates on `test_schedule.scope["chapter_ids"]` and computes an aggregate using weakest-N-average (N = 3 by default) across in-scope skill scores.

### 2. Skill mastery is global; readiness composition is test-scoped

A student's attempt history on a `section` (skill tag) lives at the skill level and is shared across tests. When a new test is created that includes a skill the student has already mastered, that mastery counts toward the new test's readiness immediately — no re-work.

The readiness *score* is the test-scoped composition: filter the student's skill-level records by the test's in-scope skills, then apply the weakest-N aggregate.

### 3. No global/course-wide assessment mode

The `/assess` route is always nested under a test: `/courses/:course_id/tests/:schedule_id/assess`. There is no global "Assess this course" entry point. When a student has zero upcoming tests, the home experience prompts them to create or select a test — assessment does not run without a scope.

### 4. No source-level filtering in student flows

Assessment does not ask the student which uploaded files to include. Source attribution (the `source_material_id` on a question) is an admin/debugging concern. Students see questions; admins see provenance.

### 5. Multiple tests → nearest-deadline default, pinnable override

When a student has more than one upcoming test, the Study Path and dashboard focus on **one primary test at a time**:

- **Default**: the test with the nearest future `test_date` is primary.
- **Override**: the student may pin a different test as primary (see "Open question" below for the pin mechanism).

The Study Path is always anchored to a single primary test because mixing weak-skill practice across multiple tests dilutes per-test focus and confuses "how much longer?" signaling. Readiness for non-primary tests is still computed and visible on the dashboard — only the active drilling is primary-only.

### 6. Empty-test state

When a student has zero upcoming tests, the student home state is a test-creation CTA (or a test picker if any exist). The Dashboard / Learn / Practice nav may still expose browsing, but adaptive assessment and the weak-topic loop do not run.

## Consequences

### Positive

- Aligns implementation with the North Star invariants, especially I-5 (deficit-weighted selection needs meaningful per-skill deficits — test scope provides them), I-8/I-10 (readiness bounded to in-scope skills), and I-15 (no labeling on thin evidence).
- "How much longer?" is naturally answerable: `test_date - today` plus readiness delta.
- Skill mastery transfers between tests with overlapping chapters — students aren't punished for taking two related tests.
- Removes an entire UX surface (the source picker) and a class of student confusion (raw filenames as a decision).
- Eliminates a vector for the "answer-key file indexed as question source" bug to surface in student flows (the bug still exists in the ingestion pipeline — see CR-001 section (c) — but it no longer shows up on the assess page).

### Negative / tradeoffs

- Students with zero upcoming tests have a gated experience. Adding the "create a test" friction is deliberate but adds one more onboarding step.
- Multiple upcoming tests require a primary-selection UI. Auto-nearest-deadline is a fine default but the pin mechanism is still TBD (see Open Questions).
- Teacher/parent rollup views (FR-013, FR-022) need to decide whether they show readiness per test, an aggregate across active tests, or both. Not blocking this ADR but requires a follow-up on those FRs.

## Alternatives Considered

### Alternative 1: Course-scoped readiness with test-scoped filtering at display time

Keep readiness as one-per-course (simpler storage model) and filter to in-scope chapters only for display. Rejected — this forces every consumer to know the test scope at read time, and the aggregate across an entire course is meaningless for a student studying one specific test.

### Alternative 2: Global assessment as a "browse mode"

Keep a global `/assess` that runs without a test, as an optional "see what I know overall" feature. Rejected — the cold-start signal problem applies (new students would see uniformly low readiness), and every student path to needing this actually goes through a test (school assignments, exam prep). Adding it would be product complexity without demand.

### Alternative 3: Test-scoped mastery

Reset skill mastery per test. Rejected — penalizes students for overlapping tests and fights the core claim that skills are the unit of learning, not tests.

## Implementation Status (as of 2026-04-23)

| Piece | Status |
|---|---|
| `ReadinessScore` has `test_schedule_id` FK | ✅ Present since prior work |
| `ReadinessCalculator` scoped to `test_schedule.scope` | ✅ Present |
| Skill mastery global (per `sections` / skill tag) | ✅ Present |
| `/assess` requires test context (no global route) | ✅ Present |
| No global Assess nav entry | ✅ Confirmed absent |
| No source-level filtering in `/assess` | ✅ Fixed in this PR (removed `:setup` phase and source picker) |
| Primary-test selection (nearest-deadline default + pin override) | ⏳ Planned — see CR-001 Task 7 |
| Empty-test home state | ⏳ Existing behavior unverified — audit as part of Task 7 |

## Open Questions

1. **Primary-test override mechanism.** Star icon on a test card? A "Focus here" button on the readiness dashboard? A settings pane? Deciding this is product work — open to product input before implementing.
2. **Teacher/parent rollups.** FR-013, FR-022 — does a parent see readiness per test, or a rolled-up "how ready is my child across everything coming up"? Probably the latter as a primary view with per-test drill-down. Decide during teacher/parent UX passes.
3. **Empty-test home state.** Today's home screen behavior when a student has no tests is not audited. Before shipping primary-test selection, confirm what the new empty state should be (CTA to create a test? browse mode for chapters without assessment?).

## References

- `docs/PRODUCT_NORTH_STAR.md` — invariants I-5, I-8, I-10, I-15
- `docs/change-requests/CR-001-assess-test-scoped.md` — the change request that drove this ADR
- `docs/discovery/requirements.md` — FR-006, FR-006b, FR-007, FR-008
- Code: `lib/fun_sheep/assessments/readiness_calculator.ex`, `lib/fun_sheep/assessments/readiness_score.ex`, `lib/fun_sheep/assessments/test_schedule.ex`
