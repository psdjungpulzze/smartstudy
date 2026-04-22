# FunSheep Product North Star

> **Read this before implementing or reviewing any learning-flow change.**
> The invariants below are enforceable claims about what the code must do.
> If a proposed change would violate an invariant, stop and raise it to the user.

---

## The Product Goal (One Sentence)

**Intelligently identify each student's weak topics and loop them on targeted practice — with personalized explanations and an AI tutor — until every in-scope skill reaches mastery (100% readiness).**

Everything else (UI polish, gamification, dashboards, exports) serves this loop.

---

## The Core Learning Loop

```
          ┌─────────────────────────────────────────┐
          │                                         │
          ▼                                         │
   ┌───────────┐    wrong     ┌───────────────┐     │
   │ Diagnose  │─────────────▶│ Confirm       │     │
   │ (assess)  │              │ (same skill)  │     │
   └─────┬─────┘              └───────┬───────┘     │
         │ correct                    │ still wrong │
         ▼                            ▼             │
   ┌───────────┐              ┌───────────────┐     │
   │ Depth     │              │ Mark skill    │     │
   │ probe     │              │ WEAK          │     │
   │ (harder)  │              └───────┬───────┘     │
   └───────────┘                      │             │
                                      ▼             │
                            ┌───────────────┐       │
                            │ Weak-topic    │       │
                            │ practice loop │───────┘
                            │ (interleaved) │   until per-skill
                            └───────────────┘   mastery
```

Termination: each in-scope skill hits mastery → overall readiness = 100% → Study Path ends.

---

## Invariants (MUST)

Each invariant has a **Why** (the pedagogical reason) and a **How to verify** (how code should prove it).

### 1. Skill tagging is the foundation

**I-1.** Every question MUST carry a fine-grained **skill tag** beyond `chapter_id` and the `easy/medium/hard` enum.
- **Why:** Without this, "similar question" and "harder question on the same topic" cannot be implemented faithfully — the existing `chapter_id` is too coarse and `difficulty` has no topical meaning.
- **How to verify:** `questions.skill_tag` (or equivalent FK) is non-null for every question surfaced to students. A question with no skill tag is not shown.

### 2. Adaptive assessment: confirm then probe

**I-2.** A wrong answer MUST trigger a **confirmation question on the same skill tag** before the engine concludes the skill is weak or moves on.
- **Why:** One wrong answer can be a slip. Two wrong on the same skill is a signal.
- **How to verify:** Trace `record_answer/2` on wrong → next question has matching `skill_tag`. Test in `assessments/engine_test.exs`.

**I-3.** A correct answer at the current difficulty target MAY trigger a **harder question on the same skill tag** to probe depth, bounded so the assessment still terminates.
- **Why:** A teacher checks for depth once they see surface competence.
- **How to verify:** When depth-probe fires, the next question is `skill_tag == current.skill_tag AND difficulty > current.difficulty`.

**I-4.** A skill is flagged **WEAK** only after ≥2 wrong answers (confirmation reached) or after failing the depth-probe.
- **Why:** Labels drive the whole downstream loop; a single data point is not enough evidence.
- **How to verify:** No code path writes `skill_mastery.status = :weak` on a single wrong answer.

### 3. Weak-topic practice: weighted, interleaved, re-rankable

**I-5.** Practice selection MUST weight candidates by **per-skill deficit** (lower mastery → higher selection probability).
- **Why:** A student weak in fractions and slightly weak in geometry should see mostly fractions, not a uniform random mix.
- **How to verify:** The selection query's ORDER BY / weight includes per-skill mastery score; test with synthetic fixtures.

**I-6.** Practice sessions MUST **deliberately interleave** a configurable fraction of previously-mastered skills (default 20–30%).
- **Why:** Spaced practice across topics (Bjork's desirable difficulty) improves long-term retention. Accidental interleaving from backfill does not count.
- **How to verify:** `PracticeEngine.build_session/*` takes an `interleave_ratio` and honors it on non-empty mastered pools.

**I-7.** Within a single session, selection MUST **re-rank based on live performance** — if the student is tanking, shift to easier/more-foundational skills; if acing, raise difficulty.
- **Why:** Static question lists waste a session when early signals say the plan is wrong.
- **How to verify:** The session state updates after each answer and the next question reflects the update.

### 4. Study Path & readiness run until 100%

**I-8.** The Study Path MUST remain active above 80% readiness and continue serving drills for any skill below its mastery bar — there is no 80% stopping point.
- **Why:** The product promise is "practice until 100% readiness." Ending at 80% breaks the promise.
- **How to verify:** UI test: a student at 82% with one below-mastery skill still sees a next-step CTA on `/dashboard`.

**I-9.** Per-skill **mastery** is defined as: **N correct in a row at or above medium difficulty** (initial N = 3, tunable). Single-session high score does not equal mastery.
- **Why:** Spaced success, not lucky streaks, is what we're optimizing for.
- **How to verify:** `mastery?/1` pure function with property tests covering streak/difficulty permutations.

**I-10.** Overall **readiness** displayed to the student MUST reflect the weakest in-scope skill, not a naive chapter-score average that can mask a deficit (e.g., weighted by deficit, or "lowest-N-average").
- **Why:** A 95%-in-7-chapters-and-20%-in-1 student should see a readiness that reflects the gap, not 83%.
- **How to verify:** Unit test `ReadinessCalculator` with skewed fixtures.

### 5. Personalization: hobbies, tutor, video

**I-11.** `question.hobby_context` MUST be populated at AI generation time from the student's stored hobbies when hobbies are set; leave null only when no hobby context fits the skill.
- **Why:** The whole "if Jungkook..." feature is dead until this field is written.
- **How to verify:** `AIQuestionGenerationWorker` reads hobbies → passes them to the generator prompt → persists `hobby_context`. Integration test against a student with hobbies.

**I-12.** The Tutor system prompt MUST include the student's **current weak skills** and **selected hobbies** whenever available; the tutor must be explicitly instructed to use hobbies in analogies.
- **Why:** Context-free tutoring is a substitute teacher who hasn't read the student's file.
- **How to verify:** `build_context/*` snapshot test showing hobbies and weak-skill list in the prompt.

**I-13.** Interactor mock mode MUST be OFF in staging and production (`:fun_sheep, :interactor_mock` must default false and be true only in `:test`).
- **Why:** A silently-mocked tutor looks real but delivers generic output; users lose trust.
- **How to verify:** Config tests per env; assertion in startup.

**I-14.** Video lessons MUST be linked to **skill tags** (not only to courses) and surfaced in the practice UI on "I don't know this" or wrong-answer events for skills that have video matches.
- **Why:** Videos sitting in `discovered_sources` with no student-facing path have zero pedagogical value.
- **How to verify:** Schema has `video_lessons.skill_tag` (or a join table). LiveView test: wrong-answer reveal includes video CTA when matches exist.

### 6. Failure honesty

**I-15.** When data is insufficient to diagnose (e.g., fewer than the minimum attempts per skill), the system MUST say so explicitly rather than label the skill weak/strong on thin evidence.
- **Why:** Extends the "no fake content" rule to diagnostic outputs. A fabricated weak-topic label is as harmful as a fabricated question.
- **How to verify:** Mastery status has an `:insufficient_data` state that is rendered honestly in UI.

**I-16.** When AI generation fails (tutor, question gen, explanations), the feature surfaces the failure — it MUST NOT fall back to hardcoded generic content masquerading as personalized output.
- **Why:** Reinforces the project-wide no-fake-content rule for every AI touchpoint.
- **How to verify:** Code review — no `"""Here is a hint about #{chapter}"""` templates in user-visible explanation paths.

---

## Terms

| Term | Definition |
|------|------------|
| **Skill tag** | A fine-grained concept identifier, finer than `chapter_id`. In this codebase, backed by the existing `sections` table (a `section` is one skill). A question has exactly one primary skill (section_id). |
| **Mastery (per skill)** | N correct in a row at ≥medium difficulty for that skill. Default N = 3. Not a single-session aggregate. |
| **Weak skill** | A skill flagged after ≥2 confirmed wrong answers or a failed depth-probe. |
| **Readiness (overall)** | A scalar ∈ [0, 100] that reflects the weakest in-scope skill, not a naive average. 100 is reached only when every in-scope skill is at mastery. |
| **Depth probe** | A harder-than-target question on the same skill tag after a correct answer, used to detect ceiling. |
| **Interleaving** | Deliberate mixing of mastered-skill questions into a weak-skill practice session at a configurable ratio (default 20–30%). |

---

## Non-Goals (Scope Guard)

The following are explicitly **not** part of the North Star. Proposing work here requires separate justification:
- Lesson authoring / content-creation tools for teachers
- Social features (study groups, public leaderboards beyond the existing in-app leaderboard)
- Native mobile apps (web-first, mobile-responsive)
- Human tutoring / real-time chat with humans
- Payment UX beyond Interactor billing integration

---

## How to Use This Document

- **Before starting** a learning-flow task: re-read the invariants relevant to it.
- **During review**: if a diff touches question selection, assessment, practice, tutor, study path, or personalization, check it against the matching invariants.
- **When in doubt**: default to failing honestly (I-15, I-16) over shipping a plausible-looking but thin implementation.

---

## References

- `docs/project-idea-intake.md` — full product vision and rationale (source)
- `docs/discovery/requirements.md` — formal FRs; especially:
  - **FR-007** Adaptive Assessment (I-2, I-3, I-4)
  - **FR-008** Test Readiness Dashboard (I-8, I-10)
  - **FR-010** Practice Tests (I-5, I-6, I-7)
  - **FR-015** Hobby-Based Personalization (I-11, I-12)
  - **FR-009** Study Guide Generation (I-14)
- `CLAUDE.md` — the "NO FAKE CONTENT" rule (I-15, I-16 reinforce it for diagnostics)

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-21 | Peter Jung (with Claude) | Initial North Star, derived from the April 21 product-validation audit |
