# AI-Scored Freeform Grading — Feature Roadmap

**Status**: Planning  
**Scope**: Replace binary correct/incorrect grading for short-answer and free-response questions with a 0–10 AI-scored rubric, explanation of the score, and integration with premium plans and study references.  
**Depends on**: `FunSheep.Questions.FreeformGrader`, `question_attempts` schema, `assessment_live.ex`, `quick_practice_live.ex`, premium subscription gating (`funsheep-premium-courses-and-tests.md`), study references (`funsheep-study-references.md`)

---

## 0. Why This Matters — The Problem Today

FunSheep currently grades freeform questions (`:short_answer`, `:free_response`) with a binary signal: **correct** or **incorrect**. The existing `FreeformGrader` uses Claude Haiku to answer `{correct: true|false, feedback: "..."}`.

This fails students in three ways:

1. **A student who writes "mitosis occurs when a cell divides its nucleus" gets the same ❌ as a student who writes "mitosis is photosynthesis."** Those are not the same mistake. One student is 80% there; the other has a fundamental misunderstanding. The adaptive engine treats them identically.

2. **"Incorrect" with a one-sentence feedback note doesn't help a student rewrite their answer.** They don't know which part was right, which was wrong, and what they need to add. This conflicts directly with North Star invariant I-15 (honest, actionable feedback).

3. **Free-response questions are the majority of AP, IB, LSAT, Bar, GRE, and GMAT exam scoring.** A student preparing for an AP Biology FRQ who sees only ✓/✗ receives no exam-realistic feedback. This undercuts the premium catalog value proposition entirely.

The solution is a **scored grading engine** that:
- Returns a **score from 0 to 10** (not a percentage — a concrete, human-readable number like "4 out of 10")
- Explains **why** the score is what it is (what the student got right, what they missed, and what a full-credit answer includes)
- Maps that score back to binary `is_correct` for the adaptive engine, preserving all existing North Star invariants
- Is gated as a **premium feature** (scored grading requires more tokens and a more capable model)
- Surfaces **study references** when a student scores below a mastery threshold

---

## 1. Current Architecture (Read Before Changing)

### 1.1 What Exists

**`FunSheep.Questions.Grading.correct?/2`**  
(`lib/fun_sheep/questions/grading.ex`)  
The binary correctness check used everywhere. For freeform types: `normalize(submitted) == normalize(answer)` (trim + downcase). Does not use AI.

**`FunSheep.Questions.FreeformGrader.grade/2`**  
(`lib/fun_sheep/questions/freeform_grader.ex`)  
The existing AI grader. Uses Claude Haiku at temperature 0.1. Returns `{:ok, %{correct: boolean, feedback: string | nil}}`. Falls back to exact match on any failure. Used in `assessment_live.ex` via `Task.async` for freeform questions. **NOT used in `quick_practice_live.ex`** — that still uses exact match only.

**`question_attempts` schema**  
(`lib/fun_sheep/questions/question_attempt.ex`)  
Fields: `answer_given`, `is_correct`, `time_taken_seconds`, `difficulty_at_attempt`. No score field.

**Adaptive engine**  
(`lib/fun_sheep/assessments/engine.ex`)  
`record_answer/4` consumes `is_correct :: boolean`. Wrong answer → `:confirm` pending; second wrong → `:weak`; correct → continues probing. This logic is correct and must not change.

### 1.2 What Must Be Preserved

- All existing North Star invariants (I-1 through I-16) are satisfied by the current architecture. Scored grading must not regress any of them.
- The `is_correct` flag continues to drive the adaptive engine. The score maps to `is_correct` via a threshold (≥ 7 = correct), not the other way around.
- `FreeformGrader.grade/2` must continue to work as-is for free users. Do not modify it — add alongside it.
- The fallback to exact match on AI failure must remain. If the scored grader fails, fall back to `FreeformGrader.grade/2`, not to exact match directly (two levels of fallback).

---

## 2. Scoring Design

### 2.1 The 0–10 Scale

| Score | Label | Meaning | Maps to `is_correct` |
|-------|-------|---------|----------------------|
| 0 | No credit | Answer is blank, completely off-topic, or contradicts the concept | false |
| 1–3 | Minimal | Shows awareness of the topic but fundamental misunderstanding or critical gaps | false |
| 4–6 | Partial | Core concept partially correct; missing significant components or contains errors | false |
| 7–8 | Mostly correct | Correct core claim, minor omissions or imprecision; acceptable on most exams | **true** |
| 9–10 | Full credit | Complete, accurate, appropriately detailed; would receive full marks on the real exam | **true** |

**Mastery threshold**: ≥ 7 = `is_correct: true`. Configurable per question or test format in a future phase; hardcoded at 7 for MVP.

**Partial credit affects study recommendations, not the adaptive engine.** A score of 5 still drives `:confirm` pending in the engine (same as score of 1). The engine tracks binary skill state. Partial credit is displayed to the student and used to surface study references.

### 2.2 Rubric Criteria

The AI evaluates each freeform response against four dimensions. The AI assigns points to each, and the total maps to the 0–10 score:

| Criterion | Max Points | Description |
|-----------|-----------|-------------|
| **Factual Accuracy** | 4 | Is the core scientific/factual claim correct? Penalizes misconceptions, inverted causality, wrong examples. |
| **Completeness** | 3 | Does the answer address all required components from the reference answer? Penalizes missing key terms, skipped steps, or absent mechanisms. |
| **Clarity & Logic** | 2 | Is the answer coherent? Is the explanation followable? Does the student demonstrate understanding or just recite vocabulary? |
| **Terminology** | 1 | Are domain-specific terms used correctly? Partial credit for correct usage of some terms even if others are missing. |

**Total: 10 points.** The rubric is embedded in the system prompt and the AI is instructed to score each criterion independently before summing.

### 2.3 Response Format

The scored grader requests the following JSON from the LLM:

```json
{
  "score": 4,
  "max_score": 10,
  "criteria": [
    {"name": "factual_accuracy", "earned": 2, "max": 4, "comment": "Cell wall correctly identified as rigid, but student reversed the roles of osmosis and diffusion."},
    {"name": "completeness", "earned": 1, "max": 3, "comment": "Missing: selectively permeable membrane, tonicity, plasmolysis."},
    {"name": "clarity", "earned": 1, "max": 2, "comment": "Explanation is understandable but incomplete."},
    {"name": "terminology", "earned": 0, "max": 1, "comment": "No domain-specific terms used."}
  ],
  "feedback": "Your answer correctly identifies that plant cells have a cell wall, but the main concept is inverted: osmosis drives water into the cell (turgid) when the cell is in a hypotonic environment, not out of it. A full-credit answer would explain: hypotonic solution → water enters via osmosis → turgor pressure increases → wall prevents rupture. The cell becomes turgid, not plasmolyzed.",
  "improvement_hint": "Try re-reading the concept of tonicity. A quick way to remember: hypo = hypotonic = water goes IN (low solute outside). Then connect that to what turgor pressure does to a plant cell.",
  "is_correct": false
}
```

**Note on `is_correct` in the response**: The AI also outputs this flag as a cross-check. The actual `is_correct` stored in the DB is computed server-side as `score >= 7`, not taken from the AI's flag. The AI's flag is logged for audit but not used for grading decisions (avoids prompt injection attacks where the AI is manipulated into claiming a wrong answer is correct).

---

## 3. Architecture

### 3.1 New Module: `FunSheep.Questions.ScoredFreeformGrader`

**File**: `lib/fun_sheep/questions/scored_freeform_grader.ex`

```
FunSheep.Questions.ScoredFreeformGrader
  behaviour: FunSheep.Interactor.AssistantSpec
  assistant_name: "funsheep_scored_grader"
  model: "claude-sonnet-4-6"   ← upgrade from Haiku; scoring requires nuanced judgment
  temperature: 0.1             ← deterministic
  max_tokens: 512              ← longer because of criteria breakdown
  
  Public API:
    grade(question, student_answer) :: {:ok, GradeResult.t()} | {:error, reason}
  
  GradeResult type:
    %{
      score: integer (0-10),
      max_score: 10,
      is_correct: boolean,     # always score >= 7, computed server-side
      feedback: string,        # human-readable explanation
      improvement_hint: string | nil,
      criteria: [CriterionResult.t()],
      grader: :scored_ai | :binary_ai | :exact_match  # which path was taken
    }
  
  Fallback chain:
    1. Try ScoredFreeformGrader (Sonnet) → on success: return scored result
    2. On failure: fall back to FreeformGrader (Haiku) → return binary result with score inferred (correct=10, incorrect=0)
    3. On failure: fall back to Grading.correct? → return binary result, score inferred
```

The `grader` field in the result tells the UI which path was taken. When the grader is `:exact_match` or `:binary_ai`, the score is synthesized (0 or 10) and the UI should suppress the criteria breakdown (no point showing fake rubric scores).

### 3.2 Database Changes

#### `question_attempts` — extend schema

**Migration**: add scoring fields

```sql
ALTER TABLE question_attempts
  ADD COLUMN score integer,                -- 0-10, null for MC/TF or if grader didn't run
  ADD COLUMN score_max integer DEFAULT 10, -- always 10 for now; extensible
  ADD COLUMN score_feedback text,          -- AI explanation text
  ADD COLUMN grader_path varchar(30);      -- 'scored_ai' | 'binary_ai' | 'exact_match'
```

These fields are **nullable** — existing rows and MC/TF questions have no score. Score is populated only for `:short_answer` and `:free_response` questions graded by a scored grader.

**Schema update** (`lib/fun_sheep/questions/question_attempt.ex`):

```elixir
field :score,          :integer
field :score_max,      :integer, default: 10
field :score_feedback, :string
field :grader_path,    :string
```

**Note**: `is_correct` remains the authoritative flag for all downstream logic. The score is display-only from the engine's perspective.

### 3.3 Premium Gating

Scored grading is a **premium feature**. The invocation path changes based on the user's subscription:

```
Student submits freeform answer
  │
  ├─── Free user ──────────────────────────► FreeformGrader.grade/2 (Haiku, binary)
  │                                          Display: ✓ Correct / ✗ Incorrect + feedback
  │
  └─── Premium/Professional user ─────────► ScoredFreeformGrader.grade/2 (Sonnet, scored)
                                             Display: "4 / 10 — here's why..."
                                             + criteria breakdown
                                             + improvement hint
                                             + study references if score < 7
```

**Where the gate lives**: In `assessment_live.ex` and `quick_practice_live.ex`, before spawning the grader task, check `FunSheep.Billing.subscription_has_scored_grading?(user_role_id)`. This returns `true` if the user has premium_monthly, premium_annual, or professional_monthly plan.

Free users always use `FreeformGrader.grade/2`. They are never aware the scored grader exists (no upsell nag inside the grading flow; upsell happens elsewhere).

### 3.4 System Prompt Design

The system prompt for `ScoredFreeformGrader` (key sections):

```
You are a precise academic grader for a high-stakes test preparation platform.

Your task: grade a student's freeform answer against a reference answer using a 10-point rubric.

Scoring rubric:
  Factual Accuracy  (0–4): Is the core claim correct? Penalize misconceptions and inverted causality.
  Completeness      (0–3): Are all required components present? Penalize missing mechanisms or steps.
  Clarity & Logic   (0–2): Is the explanation coherent and does it show understanding (not just recall)?
  Terminology       (0–1): Are domain terms used correctly?

Grading philosophy:
  - Be generous with valid paraphrasing and scientific equivalents.
  - Be strict about factual errors, especially inverted or contradictory claims.
  - A student who partially understands should receive partial credit, not zero.
  - The improvement_hint must be specific and actionable — tell them exactly what to add or fix.
  - Do not fabricate content. If the reference answer is insufficient to grade, say so in the feedback.

Output a single JSON object. No markdown, no prose outside the JSON.
Schema: {"score": int, "max_score": 10, "criteria": [...], "feedback": "...", "improvement_hint": "...", "is_correct": bool}
```

**Temperature 0.1** keeps scores consistent across retries. **Max tokens 512** allows the full criteria breakdown without truncation.

### 3.5 Interactor Assistant Registration

The `ScoredFreeformGrader` implements `FunSheep.Interactor.AssistantSpec`, so it appears in the admin Interactor Agents page (`/admin/interactor/agents`) and drift is detected automatically. Create the assistant in Interactor before deploying.

---

## 4. UI Design

### 4.1 Score Display Component

A new `score_badge` component renders the scored result:

```
┌─────────────────────────────────────────────────────────────┐
│  4 / 10  ·  Partial Credit                                  │  ← score + label
│                                                             │
│  Your answer correctly identifies that plant cells have a   │  ← feedback paragraph
│  cell wall, but the main concept is inverted: osmosis       │
│  drives water INTO the cell in a hypotonic environment...   │
│                                                             │
│  ▼ See breakdown                                            │  ← collapsed by default
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Factual Accuracy:  ██░░░░   2 / 4  Osmosis direction │  │
│  │  Completeness:      █░░░░░   1 / 3  Missing tonicity  │  │
│  │  Clarity:           █░░░░░   1 / 2  Understandable    │  │
│  │  Terminology:       ░░░░░░   0 / 1  No terms used     │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  💡 Try re-reading tonicity: hypo = water goes IN...        │  ← improvement_hint
└─────────────────────────────────────────────────────────────┘
```

**Design rules** (per design system):
- Score number: large, left-aligned, `text-2xl font-bold`
- Score color: red ≤ 4, yellow 5–6, green ≥ 7 (matches `#FF3B30`, `#FFCC00`, `#4CD964`)
- Breakdown: collapsed by default, expands on tap — keeps the feedback card compact
- Improvement hint: indented with a `💡` prefix, muted secondary color, slightly smaller font
- Cards: `rounded-2xl` per design system
- The breakdown is only shown when `grader_path == :scored_ai` — suppress for binary fallback

### 4.2 Assessment Live Integration

**File**: `lib/fun_sheep_web/live/assessment_live.ex`

Current flow (lines 229–245): spawns `Task.async(FreeformGrader.grade(...))`.

**New flow**:
```elixir
grader = if premium_user?, do: ScoredFreeformGrader, else: FreeformGrader
task = Task.async(fn -> grader.grade(question, answer) end)
```

The task result is now `{:ok, %GradeResult{} | %{correct: bool, feedback: string}}`. Both are handled by `apply_grading_result/6`, which extracts `is_correct` from either shape. Score data is stored in `question_attempts` when present.

**Progress indicator**: Scored grading takes ~2–3 seconds (Sonnet is slower than Haiku). The existing "Grading your answer..." spinner (if it exists) should remain. If there is none, add one — per the mandatory progress feedback rule, the student must see feedback that grading is in progress.

### 4.3 Practice Live Integration

**File**: `lib/fun_sheep_web/live/quick_practice_live.ex`

Currently uses only `Grading.correct?` (exact match) — no AI grading at all.

Add AI grading for freeform questions in practice, matching the assessment flow:
- Premium user: `ScoredFreeformGrader`
- Free user: `FreeformGrader`
- MC/TF: unchanged (`Grading.correct?`)

The practice flow must handle the async nature correctly — spawn a task, show spinner, apply result on receive.

### 4.4 Study References Integration

When a student receives a score below the mastery threshold (< 7), the scored feedback panel triggers study references display (per `funsheep-study-references.md` Tier 1 — Reactive):

```
[Score panel: 4 / 10 — Partial Credit]
[Feedback + criteria breakdown]
──────────────────────────────────
  ▶ Khan Academy · 4:32  ·  📄 p. 47   ← video chip + textbook chip
──────────────────────────────────
[Tutor CTA buttons]
```

**Rules**:
- Show study references after score < 7 only (not after full credit)
- If score ≥ 7: no study references (student got it, don't suggest they need to study)
- If score < 7 and no video resources exist for the section: no empty state — just omit the chip row
- Study references are always below the score panel, never replacing it

**Implementation**: The existing study references preload (`Resources.list_videos_for_section`) runs on question load. The score panel conditionally renders the chip row based on the grade result.

### 4.5 Assessment Summary Enhancement

Post-assessment summary already shows weak/strong topics. For premium users, add a "Score distribution" column to the freeform question summary:

```
[Cell Membrane Transport]  4/10 avg  ✗ Needs Work  [Study →]
```

This is only shown for test formats that include freeform question types.

---

## 5. Premium Plan Integration

### 5.1 Feature Gate

Scored grading is included in the following plans (per `funsheep-premium-courses-and-tests.md`):

| Plan | Scored Grading | Binary Grading |
|------|---------------|----------------|
| Free | ✗ | ✓ |
| Standard Monthly ($30/mo) | ✗ | ✓ |
| Standard Annual ($90/yr) | ✗ | ✓ |
| **Premium Monthly ($59/mo)** | ✓ | — |
| **Premium Annual ($149/yr)** | ✓ | — |
| **Professional Monthly ($99/mo)** | ✓ | — |
| À la carte (single course) | ✓ (while enrolled) | — |

**Rationale**: Claude Sonnet costs ~6× more per token than Haiku, and freeform grading with a full rubric uses ~3× more tokens than binary grading. The incremental cost is meaningful at scale. Scored grading is genuinely a premium capability — the depth of feedback is materially better.

### 5.2 Upsell Moment (Soft, Not Aggressive)

Free users who submit a freeform answer see the binary feedback as today. Below the binary feedback card, a one-line subtle upsell:

```
[✗ Incorrect — Your answer missed the core mechanism.]
[Upgrade to Premium to see your score and what to improve →]  ← secondary link, muted
```

This is the **only** place the upsell appears in the grading flow. No modal, no interstitial, no repeated prompts.

### 5.3 Connection to Premium Exam Catalog

The scored grading is the **primary differentiator** for the premium AP/IB/professional exam catalog. AP Biology FRQs, LSAT logical reasoning open answers, Bar MEE essays — all require rubric-based scoring. When implementing the premium catalog (`funsheep-premium-courses-and-tests.md`), the scored grader is already available for use with those question types.

For professional exams (Bar MEE, GMAT essays, GRE essays), the rubric criteria and weights should be **exam-specific** in a future phase (Bar exams have published scoring rubrics; use them). The MVP rubric (four generic criteria) is sufficient for launch.

---

## 6. Adaptive Engine Compatibility

The existing engine (`lib/fun_sheep/assessments/engine.ex`) must not change. The score feeds forward into it as a binary flag only:

```elixir
# In apply_grading_result or equivalent
is_correct = scored_result.score >= 7
Engine.record_answer(state, question_id, answer, is_correct)
```

**Partial credit and the engine**: A score of 5/10 ("partially correct") still marks the skill as pending and triggers a follow-up question. This is intentional — a student who is 50% right on a concept has not demonstrated mastery and should be tested again. The scored display tells them what to improve; the engine continues its probe until they hit ≥ 7.

This is consistent with North Star invariants I-2 (confirm on wrong) and I-3 (depth probe on correct). The threshold of 7 defines "correct" for the engine's purposes, not "any partial credit."

---

## 7. Implementation Phases

### Phase 1 — Backend: Scored Grader Module (Week 1)

**Goal**: The scored grader works and is tested in isolation.

**Tasks**:
1. Create `FunSheep.Questions.ScoredFreeformGrader` module
   - `AssistantSpec` behavior implementation
   - System prompt construction (four-criterion rubric)
   - JSON response parsing and validation
   - Three-level fallback chain (scored → binary → exact match)
   - `grader_path` flag in result
2. Register `funsheep_scored_grader` assistant in Interactor (Sonnet, 0.1 temp, 512 tokens)
3. Add migration: `score`, `score_max`, `score_feedback`, `grader_path` to `question_attempts`
4. Update `QuestionAttempt` schema and changeset
5. Update `Questions.record_attempt_with_stats/1` to accept and store score fields
6. Add `FunSheep.Billing.subscription_has_scored_grading?/1` function

**Tests**:
- Unit tests for `ScoredFreeformGrader` (mock Interactor response, test JSON parsing, test all fallback paths)
- Test malformed responses (missing fields, non-integer score, score out of range)
- Test that `is_correct` is always computed server-side (`score >= 7`), never taken from AI flag
- Migration test

**Exit criteria**: `ScoredFreeformGrader.grade/2` returns a valid `GradeResult` struct when given a real question and answer. Fallbacks work. Score is stored in `question_attempts`.

---

### Phase 2 — Integration: Wire into Assessment and Practice (Week 2)

**Goal**: Premium users see scored feedback; free users see binary feedback.

**Tasks**:
1. Update `assessment_live.ex`:
   - Check `Billing.subscription_has_scored_grading?/1` before spawning grader task
   - Pass correct grader module to the async task
   - Handle both result shapes in `apply_grading_result/6`
   - Pass `score`, `criteria`, `improvement_hint` to socket assigns
2. Update `quick_practice_live.ex`:
   - Add async AI grading for freeform questions (currently missing entirely)
   - Apply same premium gate
   - Show spinner while grading (mandatory per progress-feedback rule)
3. Update `Questions.record_attempt_with_stats/1` to accept new fields
4. Add `subscription_has_scored_grading?` check in Billing context

**Tests**:
- LiveView integration test: freeform answer submission → task spawned → receives result → assigns updated
- Test premium path: scored result stored with score fields populated
- Test free path: binary result stored, score fields nil
- Test fallback: when ScoredFreeformGrader errors, falls back to FreeformGrader result

**Exit criteria**: Premium user submits freeform answer in assessment, score is stored in DB, socket assigns contain score + criteria. Free user path unchanged.

---

### Phase 3 — UI: Score Display (Week 3)

**Goal**: Students see the scored feedback card with breakdown.

**Tasks**:
1. Create `score_badge` LiveView component
   - Score number + label
   - Color coding (red/yellow/green)
   - Collapsible criteria breakdown with progress bars
   - Improvement hint section
   - Suppresses breakdown when `grader_path != :scored_ai`
2. Wire into `assessment_live.ex` answer feedback section (replace plain ✓/✗ for premium users)
3. Wire into `quick_practice_live.ex` post-answer feedback section
4. Add subtle upsell chip for free users below binary feedback
5. Playwright visual test: screenshot all four states (scored correct, scored partial, scored wrong, binary free-user)

**Design validation**: Use `ui-design` skill to validate score_badge component against design system before marking complete.

**Exit criteria**: Playwright screenshots show scored feedback card correctly for premium user on a freeform question. Criteria breakdown expands/collapses. Color coding matches score thresholds.

---

### Phase 4 — Study References Integration (Week 4)

**Goal**: Study references appear below scored feedback when score < 7.

**Tasks**:
1. In practice_live: preload `Resources.list_videos_for_section(question.section_id)` on question load
2. Add chip row to score_badge component (rendered conditionally: score < 7 AND resources exist)
3. Video chip: source icon + duration; links open in new tab
4. Textbook chip: "p. XX" from question figures if present
5. Assessment summary: add score average column for freeform questions (premium users only)
6. Playwright test: wrong freeform answer with seeded video resource → chip appears; correct answer → no chip

**Exit criteria**: Student scores 4/10 on a freeform practice question, sees the score panel, and sees a Khan Academy chip below it pointing to the relevant section video.

---

### Phase 5 — Exam-Specific Rubrics (Future / Month 2+)

**Goal**: Premium catalog exams (AP, IB, LSAT, Bar) use their official published rubric criteria instead of the generic four-criterion rubric.

**Tasks**:
1. Add optional `rubric_template` field to `Question` schema (JSONB or references a `rubric_templates` table)
2. `ScoredFreeformGrader` checks for `rubric_template` on the question and injects it into the system prompt if present
3. Admin pipeline: import official AP/IB/Bar rubric criteria at course creation time
4. AP Biology FRQ rubrics specifically: College Board publishes point-level rubrics for official practice FRQs — map these at question creation
5. UI: when a rubric template is present, rename the generic criteria headers with the exam-specific terms (e.g., "Scientific Reasoning" instead of "Clarity & Logic" for AP Bio)

**Note**: This phase depends on the premium catalog (`funsheep-premium-courses-and-tests.md`) Phase 3 (AP courses). Do not implement before AP courses are in the system.

---

## 8. Edge Cases and Error Handling

| Case | Handling |
|------|----------|
| AI returns score outside 0–10 | Clamp to range; log warning; mark `grader_path: :scored_ai` but flag as anomaly |
| AI returns non-integer score | Round to nearest integer; log |
| Criteria sum ≠ total score | Use AI-provided total `score`, not criteria sum; log the discrepancy for monitoring |
| Interactor returns HTTP error | Fall back to `FreeformGrader.grade/2` |
| `FreeformGrader` also fails | Fall back to `Grading.correct?`; `grader_path: :exact_match` |
| Grading takes > 10 seconds | Task timeout; fall back to binary grader |
| Student submits empty answer | Short-circuit: `score: 0, is_correct: false, feedback: "No answer provided."` — no AI call |
| Reference answer is empty | Log error; fall back to binary grader; do not send blank reference to AI |
| Score is exactly 7 | `is_correct: true` — threshold is inclusive at 7 |
| Free user submits freeform | Never calls `ScoredFreeformGrader`; binary path only |

---

## 9. Monitoring and Analytics

New events to track:

| Event | Payload |
|-------|---------|
| `freeform_graded` | `{grader_path, score, is_correct, question_type, plan_tier, latency_ms}` |
| `scored_grader_fallback` | `{reason: :interactor_error | :parse_error | :timeout, fallback_path}` |
| `criteria_breakdown_expanded` | `{question_id, score}` — student tapped "See breakdown" |
| `improvement_hint_viewed` | `{question_id}` |
| `study_ref_shown_after_score` | `{question_id, score, resource_count}` |

**Alerting**:
- `scored_grader_fallback` rate > 5% of freeform attempts → page on-call (Interactor assistant may be down or drifted)
- Average `latency_ms` for scored path > 8s → investigate Sonnet latency or switch to streaming approach

---

## 10. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Fallback rate (scored → binary | exact) | < 5% of scored grading attempts | `freeform_graded` event, `grader_path != :scored_ai` |
| Scored grading latency (p95) | < 6 seconds | `latency_ms` in `freeform_graded` |
| Criteria breakdown expansion rate | > 30% of scored wrong answers | `criteria_breakdown_expanded` events |
| Study reference shown → video click rate | > 15% | `study_ref_shown_after_score` → `video_resource_clicked` |
| Student re-attempt rate (tried again after scored wrong) | > 40% | Subsequent `question_attempts` for same question |
| Readiness improvement for users with scored grading vs binary | Measurable positive delta (baseline: 30 days post-activation) | A/B cohort if available |

---

## 11. Open Questions

1. **Score threshold = 7**: Is 7/10 the right mastery threshold for adaptive engine purposes? AP Biology FRQs are graded out of specific point totals (often 4 or 8 points); a strict ≥ 7 might not map naturally. Consider making the threshold configurable per `test_format_template` rather than hardcoded.

2. **Partial credit and spaced repetition**: If a student consistently scores 6/10 (always "incorrect" to the engine), they get stuck in the weak loop without improving. Should the practice engine have a "partial progress" state between `:weak` and `:probing`? This requires changes to the adaptive engine (non-trivial — separate roadmap decision).

3. **Streaming scored grading**: Sonnet can stream. The score could appear first, then the feedback, then the criteria. This would feel more responsive. Worth implementing in Phase 3 if latency becomes a user complaint.

4. **Model selection**: `claude-sonnet-4-6` is the current choice. Claude Haiku 4.5 is faster and cheaper; Claude Opus 4.7 is more capable for complex rubrics (especially Bar/MCAT). Consider per-exam-type model selection in Phase 5.

5. **Exam-specific rubric storage**: Should rubric templates live in the `questions` table (one per question) or in a separate `rubric_templates` table (reused across many questions in a section)? Section-level rubrics are more maintainable for bulk updates (e.g., College Board releases a new rubric) but require a join. Decide before Phase 5.

6. **Upsell copy**: The upsell chip for free users says "Upgrade to Premium to see your score and what to improve." This might be too explicit. Consider A/B testing against "See a detailed score for this answer" or just silently not showing it and letting Premium users discover it on upgrade.

---

## 12. What Not to Build (Scope Boundaries)

| Idea | Why Not Now |
|------|------------|
| Score stored as `float` (e.g., 6.5/10) | Integer is cleaner for display and threshold comparison. Half-points add no value for adaptive logic. |
| Letter grade display (A, B, C...) | Score out of 10 is more actionable than a letter grade. AP uses point totals, not letters. |
| Student-contestable grades ("I disagree") | Adds moderation complexity. Defer to Phase 5+ if feedback data shows this is needed. |
| Peer review / human grader | Valid for professional exam prep but out of scope for this roadmap. |
| Scoring MCQ or T/F questions | Those have objective answers. Binary correct/incorrect is always appropriate for them. |
| Showing scored grading result to parents | Parent dashboard doesn't exist yet. Defer. |
| Changing existing `is_correct` semantics | `is_correct` stays binary and drives all adaptive logic unchanged. Score is additive, not a replacement. |

---

## 13. Related Roadmap Documents

- `funsheep-premium-courses-and-tests.md` — scored grading is the primary differentiator for AP/IB/professional exam prep courses; rubric expansion (Phase 5) depends on premium catalog Phase 3
- `funsheep-study-references.md` — Phase 4 of this roadmap wires scored feedback into the Tier 1 study references surface; implement study references Phase 1–2 first
- `confidence-based-scoring.md` — confidence + score is a powerful combined signal; these two features should be designed to coexist on the same feedback card
- `funsheep-readiness-by-topic.md` — scored grading produces richer readiness data; consider exposing score averages per topic in the readiness dashboard
- `funsheep-memory-span.md` — memory span uses `is_correct` signal; no changes needed but the scored grading threshold decision (7/10 = correct) feeds directly into memory span calculations
