# CR-001: Assessment should be test-scoped, not source-scoped

**Date**: 2026-04-23
**Requested By**: Peter Jung
**Priority**: P1 (High) — blocks the core learning loop from working as designed
**Status**: Scoped (2026-04-23) — codebase exploration revised scope significantly (see "Revised Scope After Exploration" below)

---

## Summary

The assessment flow currently asks students to pick **file-level question sources** (e.g. `Biology Answers - 31.jpg`) to include. It should instead run inside the scope of an **upcoming test** (FR-006 / FR-006b), with the student seeing chapters/skills — not upload filenames.

---

## Revised Scope After Exploration (2026-04-23)

Exploration of the worktree revealed that **most of the test-scoped foundation is already built** — only the setup-phase source picker and a few additions remain. Corrections to the original analysis:

| Original claim | Reality |
|---|---|
| Readiness must be migrated from course-scoped to test-scoped | **Already done.** `ReadinessScore` schema (`lib/fun_sheep/assessments/readiness_score.ex:23`) has `test_schedule_id` FK. `ReadinessCalculator.calculate/2` (`lib/fun_sheep/assessments/readiness_calculator.ex:22`) operates on `test_schedule.scope["chapter_ids"]` with a weakest-N-average aggregate (`:20`, N=3). Skill mastery is per-section (global) and transfers across tests as required. |
| Remove global `/assess` nav entry | **Not present.** The router has exactly one assessment route: `/courses/:course_id/tests/:schedule_id/assess` (`lib/fun_sheep_web/router.ex:104`). Student nav (`lib/fun_sheep_web/components/layouts.ex:117`) exposes Learn / Courses / Practice / Flocks — no Assess tab. |
| `TestSchedule` entity needs to be added | **Exists.** `lib/fun_sheep/assessments/test_schedule.ex` has `name`, `test_date`, `scope` (chapter_ids), `target_readiness_score`, calendar sync fields. |

### Remaining work (smaller than the original task list)

1. **Remove the source-picker setup phase from `AssessmentLive`** — this is the real user-visible fix from the screenshot. `Questions.list_question_sources/1` (`lib/fun_sheep/questions.ex:974`) returns raw `uploaded_materials.file_name` and `AssessmentLive` routes into a `:setup` phase (`lib/fun_sheep_web/live/assessment_live.ex:18`) whenever `question_sources != []`, rendering the picker at `:725`. Remove that phase entirely — assessment starts directly on the test's scope.
2. **Add primary-test selection** — no `is_primary` flag on `TestSchedule` today. Add one (or keep state-free and use nearest-deadline by default, with an override).
3. **Fix the OCR "answer key as source" bug (separate PR)** — `lib/fun_sheep/workers/question_extraction_worker.ex:50-71` has no material-type guard; every OCR'd file becomes a question source. `UploadedMaterial` has no `material_type` field. Add classification (user-declared on upload + optional LLM heuristic) and filter at extraction time.
4. **Update tests** — remove source-picker test paths in `test/fun_sheep_web/live/assessment_live_test.exs`; cover the new direct-launch flow.

### Deferred / already-met

- Migration of readiness storage → already test-scoped.
- Remove global Assess nav / route → nothing to remove.
- Schema additions for `tests` / scope → already present.

---

## Current State

Observed on `funsheep.com/courses/{id}/.../tests/{id}/assess` (screenshot captured 2026-04-23):

- Page title: **Finals - AP Biology** (test-scoped in the URL and header)
- Body: a "Question Sources" picker listing raw file names:
  - `Biology 3 - 47.jpg` (6 questions)
  - `Biology Chapter 39 - 4.jpg` (21 questions)
  - `Biology Answers - 31.jpg` (148 questions)
- Footer: "175 questions selected" → green **Start Assessment** button

Three problems:

1. **Wrong abstraction.** Students see OCR upload artifacts. They care about topics/chapters, not which file the ingestion pipeline processed.
2. **Data-hygiene leak.** `Biology Answers - 31.jpg` looks like an answer key file was indexed as a question source. Exposing sources surfaces a content-pipeline bug directly to the student.
3. **Redundant step.** The scope is already defined by the test ("Finals"). Re-asking the student to pick files inside a test they already scoped is an extra, confusing step.

The nav also exposes a global **Assess** tab. At cold start (first-time student), a global adaptive assessment has no meaningful signal — the student hasn't learned the majority of topics, so readiness is near-uniformly low everywhere. This violates I-15 (don't label on thin evidence) and undermines I-5 (weighted-by-deficit selection needs meaningful deficits).

---

## Proposed Change

### (a) Remove the source picker from `Assess`

The `/assess` route inside a test should launch the adaptive assessment directly on the test's scope. No file-source toggles. Ever.

Sources remain an **admin/question-review** concern (for content pipeline debugging and provenance auditing), but are not surfaced in student flows.

### (b) Make assessment always test-scoped

- Remove the global **Assess** nav entry.
- Assessment only exists as a step inside a **Test** (an `upcoming_test` entity with scope + optional date per FR-006/FR-006b).
- If the student lands on Assess without an active test: prompt them to **select an existing test or create one** before proceeding.
- Readiness score and Study Path become scoped to the active test, not global.
- Skill-level mastery (sections/skill tags) stays **global**: mastery earned while studying Test A transfers to Test B if skills overlap. Only the readiness *composition* is test-scoped.

### (c) Investigate the "answer key as source" data bug

Separate from the UX fix, a source named `Biology Answers - 31.jpg` with 148 questions suggests an answer-key file was OCR'd and indexed as a question bank. Root-cause and fix the ingestion classifier so answer keys don't populate the question pool.

### Multiple-test default

When a student has multiple upcoming tests, the Study Path defaults to the **nearest deadline**. The student may pin a different test as primary. When no test exists, the home state prompts test creation rather than surfacing a global assess.

---

## Reason for Change

- [x] Bug/defect discovered (UX leaks internal plumbing; possible content-pipeline bug)
- [x] Requirement drift (implementation diverged from FR-006/006b/007/008)
- [x] Aligns with North Star invariants I-5, I-8, I-10, I-15

**Context**: FR-006 already defines scope selection as chapter-level and "saved and used for all subsequent assessment/practice." FR-007 (Adaptive Assessment) and FR-008 (Test Readiness Dashboard) are both written around an upcoming test. The current implementation diverged from these by introducing a file-source picker and a global `/assess` tab. This CR re-aligns the implementation with the documented requirements and explicitly rules out a global assessment mode.

---

## Impact Assessment

| Area | Affected | Notes |
|------|----------|-------|
| Requirements | Clarify | FR-007 should explicitly state "operates within the scope of a Test (FR-006)". No new FRs. |
| Architecture | Yes | `readiness` becomes a property of a test, not of a course. Study Path state machine keyed on active test. |
| Database schema | Yes | Likely: `tests` gains "is_primary" flag or ordering; readiness calculations move to test-scoped query. Drop any `question_source_selections` join table if it exists. |
| API / LiveViews | Yes | Remove source-picker LiveView; change `/assess` route to require test context or redirect to test picker. |
| UI/UX | Yes | Remove source-picker page; update home/dashboard to show tests, not a global Assess CTA. |
| Tests | Yes | Integration tests for assessment must seed a test scope; remove source-selection test paths. |
| Documentation | Yes | Update FR-007 wording; update PRODUCT_NORTH_STAR references where applicable. |

### Files likely affected (to be confirmed during planning)

- `lib/funsheep_web/live/*assess*` — source picker LiveView
- `lib/funsheep/{assessments,tests,readiness}/*` — scope readiness to test
- `lib/funsheep_web/router.ex` — remove global Assess route or redirect it
- `priv/repo/migrations/` — migration(s) for readiness/test relationship
- `docs/discovery/requirements.md` — clarify FR-007 wording
- Ingestion pipeline for (c): wherever OCR output is classified as "question source"

---

## Recommended Approach

### Option A: Full test-scoped model (Recommended)

Ship (a), (b), (c) together as one coordinated change.

**Pros**:
- One coherent mental model for students; no transitional "global Assess + test-scoped readiness" hybrid.
- Fixes the invariant violation (I-15) at the root.
- Lets us remove code rather than gating it.

**Cons**:
- Touches readiness calculation, Study Path, home screen, nav — not a small diff.
- Needs a migration path for any existing users with global-assessment data (likely small N today; verify in prod).

**Effort**: Medium

### Option B: UI-only fix, keep global model

Replace the file-source picker with a chapter picker but keep global `/assess`.

**Pros**: Small diff.
**Cons**: Doesn't fix the cold-start signal problem; readiness stays globally framed; leaves a global Assess tab that still violates I-15 at signup. Not recommended.

**Effort**: Small

---

## Implementation Plan

### Phase to Revisit

- [x] Discovery — tighten FR-007 wording to explicitly require test scope
- [x] Planning — ADR for test-scoped readiness data model
- [x] Implementation — per tasks below

### Tasks (revised post-exploration)

- [x] **Remove source-picker setup phase from `AssessmentLive`** — delete `:setup` phase, launch engine directly on `test_schedule.scope` *(PR #100, `dc093bd`)*
- [x] **Add primary-test selection** with nearest-deadline default + manual pin override *(PR #100, `41442f5`)*
- [x] **Fix OCR answer-key ingestion bug** — added `:answer_key` to `UploadedMaterial` enum + filename heuristic in `UploadController.normalize_kind/2` *(PR #100, `199caf6`; bundled rather than split into a separate PR)*
- [x] Clarify FR-007 wording in `docs/discovery/requirements.md` to explicitly require FR-006 scope linkage *(PR #100, `8b38f71`)*
- [x] ADR documenting the test-scoped pattern + primary-test rule *(PR #100, ADR-005)*
- [x] Update LiveView tests for new direct-launch flow; remove source-picker tests *(PR #100)*

### Follow-up tasks (post-PR #100)

- [x] **7a — Primary-test selection UI** (pin star on dashboard, Focus badge, options-first empty state) *(PR #100, `41442f5` + `029de29`)*
- [x] **7b — Promote LMS in `/profile/setup` onboarding** *(PR #102, `432e3e7`)*
- [x] **Material-classification backfill runbook** *(PR #102, `fee95c5`)*
- [ ] **7c — Teacher creates test for linked students** (new primitive, separate ADR)
- [ ] **7d — Parent/teacher create-test-on-behalf-of-student** (extension of student flow)

### Deferred / already complete

- ~~Migrate readiness storage from course-scoped → test-scoped~~ (already done)
- ~~Change `/assess` to require an active test~~ (already enforced by route)
- ~~Remove global Assess nav entry~~ (none exists)

### Documents to Update

- [ ] `docs/discovery/requirements.md` (FR-007)
- [ ] New ADR in `docs/adrs/` (test-scoped readiness)
- [ ] `docs/PRODUCT_NORTH_STAR.md` if any invariant wording benefits from the test-scoped framing

---

## Open Questions

1. **Existing user data**: how many users have assessment history today? If non-trivial, do we migrate old global-readiness to a synthetic "catch-all test," or drop it and re-derive once the user creates their first test?
2. **Teacher/parent views (FR-013, FR-022)**: do parents want to see readiness per test, or a rolled-up "overall" across tests? Probably the rolled-up view is a simple aggregate — confirm with parent-experience notes.
3. **Empty-test state**: when a student has zero upcoming tests, what's the default home screen — "create your first test" CTA, or a chapters-only learn-mode that isn't gated on a test?

---

## Rollback Plan

If the new flow regresses, feature-flag the route: `/assess` falls back to the previous source-picker LiveView. Revert the readiness migration with its `down/0` (must be reversible — verify during implementation).

---

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-04-23 | Peter Jung + Claude | Initial request, drafted from screenshot review of `funsheep.com/.../finals/assess` |
| 2026-04-23 | Peter Jung + Claude | Post-exploration scope revision — most test-scoping already implemented; remaining work is source-picker removal + primary-test + OCR bug |
| 2026-04-24 | Peter Jung + Claude | PR #100 merged: source-picker removed, ADR-005 + requirements aligned, primary-test pin shipped, answer-key filename heuristic shipped. Follow-up PR #102: onboarding LMS step (7b) + material-classification runbook. 7c/7d still open for future work. |
