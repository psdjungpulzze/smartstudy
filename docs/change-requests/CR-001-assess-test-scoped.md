# CR-001: Assessment should be test-scoped, not source-scoped

**Date**: 2026-04-23
**Requested By**: Peter Jung
**Priority**: P1 (High) — blocks the core learning loop from working as designed

---

## Summary

The assessment flow currently asks students to pick **file-level question sources** (e.g. `Biology Answers - 31.jpg`) to include. It should instead run inside the scope of an **upcoming test** (FR-006 / FR-006b), with the student seeing chapters/skills — not upload filenames.

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

### Tasks

- [ ] Clarify FR-007 in `docs/discovery/requirements.md` to explicitly require a test scope (FR-006 linkage)
- [ ] ADR: test-scoped readiness + Study Path (primary test, nearest-deadline default, multi-test overlap behavior)
- [ ] Remove `QuestionSources` picker UI and its route/handler
- [ ] Change `/assess` to require an active test (redirect to test picker/creator if none)
- [ ] Remove global Assess nav entry; replace with Tests list or a Test-CTA
- [ ] Migrate readiness storage from course-scoped → test-scoped
- [ ] Add "primary test" selection (pin) with nearest-deadline default
- [ ] Audit OCR classification pipeline for answer-key files being indexed as question sources (separate PR — bug fix for (c))
- [ ] Update integration/LiveView tests to seed a Test before invoking Assess

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
