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
- **Why:** Without this, "similar question" and "harder question on the same topic" cannot be implemented faithfully.
- **How to verify:** `questions.section_id` is non-null for every question surfaced in adaptive flows, and the classification is trusted (`:ai_classified` or `:admin_reviewed`).

### 2. Adaptive assessment: confirm then probe

**I-2.** A wrong answer MUST trigger a **confirmation question on the same skill tag** before concluding the skill is weak.
- **Why:** One wrong answer can be a slip. Two wrong on the same skill is a signal.

**I-3.** A correct answer at the current difficulty target MAY trigger a **harder question on the same skill tag** to probe depth.
- **Why:** A teacher checks for depth once they see surface competence.

**I-4.** A skill is flagged **WEAK** only after ≥2 wrong answers (confirmation reached) or after failing the depth-probe.
- **Why:** Labels drive the downstream loop; a single data point is not enough evidence.

### 3. Weak-topic practice: weighted, interleaved, re-rankable

**I-5.** Practice selection MUST weight candidates by **per-skill deficit** (lower mastery → higher selection probability).

**I-6.** Practice sessions MUST **deliberately interleave** a configurable fraction of previously-mastered skills (default 20–30%).

**I-7.** Within a single session, selection MUST **re-rank based on live performance**.

### 4. Study Path & readiness run until 100%

**I-8.** The Study Path MUST remain active above 80% readiness and continue serving drills for any skill below its mastery bar.

**I-9.** Per-skill **mastery** = **N correct in a row at or above medium difficulty** (initial N = 3, tunable).

**I-10.** Overall **readiness** MUST reflect the weakest in-scope skills (e.g. weakest-N average), not a naive chapter average.

### 5. Personalization: hobbies, tutor, video

**I-11.** `question.hobby_context` MUST be populated at AI generation time from the student's stored hobbies when hobbies are set.

**I-12.** The Tutor system prompt MUST include the student's current weak skills and selected hobbies, and explicitly use hobbies in analogies.

**I-13.** Interactor mock mode MUST be OFF in staging and production; true only in `:test`.

**I-14.** Video lessons MUST be linked to **skill tags** (not only courses) and surfaced on "I don't know"/wrong-answer events.

### 6. Failure honesty

**I-15.** When data is insufficient to diagnose, the system MUST say so explicitly rather than label on thin evidence.

**I-16.** When AI generation fails, the feature MUST surface the failure — no hardcoded fallbacks masquerading as personalized output.

---

## Terms

| Term | Definition |
|------|------------|
| **Skill tag** | Fine-grained concept, backed by `sections` (a section = one skill). |
| **Mastery (per skill)** | N correct in a row at ≥medium difficulty. Default N = 3. |
| **Weak skill** | Flagged after ≥2 confirmed wrong answers or a failed depth-probe. |
| **Readiness (overall)** | Scalar ∈ [0, 100] reflecting the weakest in-scope skills. 100 requires every skill mastered. |
| **Depth probe** | Harder-than-target question on the same skill tag after a correct answer. |
| **Interleaving** | Deliberate mixing of mastered-skill questions into a weak-skill practice session. |

---

## How to Use This Document

- **Before starting** a learning-flow task: re-read the invariants relevant to it.
- **During review**: if a diff touches question selection, assessment, practice, tutor, study path, or personalization, check it against the matching invariants.
- **When in doubt**: default to failing honestly (I-15, I-16) over shipping a plausible-looking but thin implementation.

---

## References

- `docs/project-idea-intake.md` — full product vision and rationale (source)
- `docs/discovery/requirements.md` — formal FRs (FR-007 adaptive assessment, FR-008 readiness, FR-010 practice, FR-015 hobbies, FR-009 study guides)
- `CLAUDE.md` — the "NO FAKE CONTENT" rule

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-21 | Peter Jung (with Claude) | Initial North Star, derived from the April 21 product-validation audit |
