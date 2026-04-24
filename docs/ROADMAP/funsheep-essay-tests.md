# FunSheep — Essay Tests: Strategy, Architecture & Roadmap

> **For the Claude session implementing this feature.** Read the entire document before writing a single line of code. Essays are architecturally different from every other question type in FunSheep. The auto-save design, the grading rubric system, the exam-specific prompts, the UI layout, and the discovery pipeline all need to change. Skipping any section will produce a broken experience for students spending an hour writing an answer.

---

## 0. Why Essays Require a Separate Roadmap

FunSheep already handles `free_response` questions — short text answers graded by `FreeformGrader` with binary ✓/✗ and by `ScoredFreeformGrader` (planned) with a 0–10 rubric. Essays are fundamentally different:

| Dimension | Free Response | Essay |
|---|---|---|
| Length | 1–4 sentences (< 100 words) | 250–1,500+ words |
| Time on page | 30–120 seconds | 20–60+ minutes |
| Risk of data loss | Trivial | Catastrophic (1 hour of work) |
| Grading criteria | Factual accuracy, completeness | Thesis, evidence, analysis, organization, style |
| Model varies | Haiku / Sonnet sufficient | Claude Opus (complex rhetorical judgment) |
| Rubric | Generic 4-criterion rubric | Exam-specific (College Board 6-pt, GRE 0-6, Bar IRAC) |
| Sources | No sources needed | Some types require reading 3–6 provided passages first |
| Study reference | Video chips + textbook page | Model response + rubric annotations |

A `free_response` graded like an essay, or an essay squeezed into the existing practice flow, fails the student. This is its own question type, its own mode, and its own pipeline.

---

## 1. The Exam Landscape — What "Essay" Means Per Test

The premium catalog (`funsheep-premium-courses-and-tests.md`) includes many tests with essay components. Here is exactly what each requires — the grading methodology must match the real exam.

### 1.1 AP English Language & Composition (College Board)

**3 essay types per exam (2025 rubric):**

| Essay Type | Task | Time | Rubric |
|---|---|---|---|
| **Synthesis** | Craft an argument using ≥3 of 6–7 provided sources | 40 min | 6-point (see below) |
| **Rhetorical Analysis** | Analyze how a rhetorician builds argument in a passage | 40 min | 6-point (see below) |
| **Argument** | Defend, challenge, or qualify a proposition | 40 min | 6-point (see below) |

**The College Board 6-Point Rubric (2025):**

| Criterion | Points | What is evaluated |
|---|---|---|
| **Thesis** | 0–1 | Does the response present a defensible claim that responds to the prompt? |
| **Evidence & Commentary** | 0–4 | Is evidence selected and used to support a clear line of reasoning? Does the student explain how the evidence connects to the thesis? |
| **Sophistication** | 0–1 | Does the response demonstrate nuanced understanding, complexity, or purposeful stylistic choices? (Only ~5–15% of students earn this.) |

**AP US History** uses a similar 6-point rubric for Long Essay Questions (LEQs) and a 7-point rubric for Document-Based Questions (DBQs), where the extra point comes from sourcing (explaining why the source's perspective is relevant). This distinction matters for grading prompts.

### 1.2 AP US History — DBQ (Document-Based Question)

**Special structure**: Student reads 7 primary source documents, then writes a historical argument essay using them as evidence.

| Criterion | Points |
|---|---|
| Thesis / Claim | 0–1 |
| Contextualization (historical context prior to the documents) | 0–1 |
| Evidence: Document Use (uses ≥3 docs to support argument) | 0–3 |
| Evidence: Outside Evidence (brings in knowledge not in docs) | 0–1 |
| Analysis & Reasoning: Sourcing (POV, purpose, audience, context of docs) | 0–1 |
| Analysis & Reasoning: Complexity | 0–1 |
| **Total** | **0–7** |

DBQs are architecturally complex: the student needs to read source passages during the essay. FunSheep needs a split-panel layout for this.

### 1.3 GRE Analytical Writing (ETS)

**2 tasks:**
- **"Analyze an Issue"**: 30 min — defend a position on a given issue; evaluate the complexity of the problem
- **"Analyze an Argument"**: 30 min — critique the logical soundness of an argument (do NOT share your own view)

**ETS Scoring: 0–6 holistic scale**

| Score | Label | Criteria |
|---|---|---|
| 6 | Outstanding | Insightful, well-organized, precise language; considers complexity; compelling evidence |
| 5 | Strong | Well-developed analysis; minor lapses in clarity |
| 4 | Adequate | Competent analysis; some supporting reasons; adequate but imprecise |
| 3 | Limited | Limited analysis; uneven development; some reasoning errors |
| 2 | Flawed | Serious weaknesses in reasoning; limited evidence |
| 1 | Deficient | Fundamental deficiencies; coherence problems |
| 0 | No Score | Off-topic, not in English, or blank |

### 1.4 LSAT Argumentative Writing (LSAC)

- **Format**: 50 minutes (15 min prewriting + 35 min writing)
- **Task**: Choose between two options and argue for one using provided criteria
- **Score**: **Unscored** — sent to law schools alongside the LSAT score as a writing sample
- **Grading for practice purposes**: Law schools read it holistically — does the student argue coherently? Is the reasoning logical? Is the writing professional?

**Implication for FunSheep**: LSAT Writing practice sessions must be graded for quality of argument and writing, not for a numeric score. The AI should mimic law school admissions reader judgment: "would this writing sample raise or lower your opinion of this applicant?"

### 1.5 Bar Exam — Multistate Essay Examination (MEE)

- **Format**: 6 essays, 30 minutes each
- **Grading method**: NCBE recommends a **0–6 relative scale** — grading is rank-ordered against other examinees in the same jurisdiction, not absolute
- **What graders look for**: IRAC structure (Issue → Rule → Application → Conclusion), responsiveness to the question, clarity, conciseness
- **NCBE publishes model answers** — these should be stored per essay prompt and shown to students after submission

### 1.6 IB Internal Assessments (Essay format)

- Subject-specific: Biology IA, History IA, Economics IA, English A Individual Oral
- Graded by subject-specific criteria (IB publishes criterion descriptors per subject)
- Scores vary by subject (typically 0–20 across 4–6 criteria)

### 1.7 ACT Writing (Optional)

- **Time**: 40 minutes
- **Rubric**: 4 dimensions × 6 points = 24 raw, converted to 2–12 composite
  - Ideas and Analysis
  - Development and Support
  - Organization
  - Language Use and Conventions

### 1.8 CLT Essay

- **Format**: 35 minutes
- **Task**: Argument essay responding to a philosophical or literary prompt
- **Score**: Sent to colleges; CLT publishes its own rubric

---

## 2. What Must Change — Gap Analysis vs. Current Architecture

The Explore agent confirmed:

| Current State | Gap |
|---|---|
| Question types: `multiple_choice`, `true_false`, `short_answer`, `free_response` | No `:essay` type |
| `question_attempts.answer_given` is a plain `:string` | Essays are too long for a string column; need a TEXT-typed dedicated draft table |
| StateCache + SessionStore: session reconnection only | No draft auto-save for in-progress answers |
| `FreeformGrader` (Haiku, binary) + `ScoredFreeformGrader` (Sonnet, 0–10) | Essays need Opus-level judgment and exam-specific rubrics |
| 4-criterion generic rubric (factual accuracy, completeness, clarity, terminology) | Wrong for essays; need thesis/evidence/analysis/org/sophistication |
| Practice flow: one question at a time, timed per question | Essays need 40–60 min uninterrupted single-question sessions |
| Assessment live flow: rapid submit cycle | Essay live must hold a single prompt for the full session |
| Study references: video chips + textbook page | Essays need model responses as the primary reference |
| Discovery (OCR pipeline): extracts questions and answers | Does not extract essay rubrics or source passage context |

---

## 3. The Auto-Save Problem — Design and Implementation

### 3.1 Why This Is the Hardest Part

A student who spends 45 minutes writing an AP synthesis essay and loses their work due to a page refresh, network dropout, or accidental navigation is not just frustrated — they will never trust FunSheep again. This is a safety-critical feature.

### 3.2 What Other Platforms Do

- **Canvas LMS**: Students historically complained about missing draft-save (see Canvas community forums). Canvas's Rich Content Editor now auto-restores text on accidental exit. This is the minimum bar.
- **Google Docs**: Auto-saves every few seconds; "last edited X seconds ago" indicator.
- **Khanmigo**: Essay text persists across sessions — students can return to a draft.
- **Real AP exam (digital)**: The Bluebook app auto-saves the student's response locally and syncs to the server. Students are told: "Your answer is automatically saved."

### 3.3 The `essay_drafts` Table

A dedicated draft table is the right design:

```sql
CREATE TABLE essay_drafts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id     UUID NOT NULL REFERENCES user_roles(id),
  question_id      UUID NOT NULL REFERENCES questions(id),
  schedule_id      UUID REFERENCES test_schedules(id),
  body             TEXT NOT NULL DEFAULT '',
  word_count       INTEGER NOT NULL DEFAULT 0,
  last_saved_at    UTCDATETIME NOT NULL DEFAULT now(),
  started_at       UTCDATETIME NOT NULL DEFAULT now(),
  time_elapsed_seconds INTEGER NOT NULL DEFAULT 0,
  submitted        BOOLEAN NOT NULL DEFAULT false,
  submitted_at     UTCDATETIME,
  inserted_at      UTCDATETIME NOT NULL,
  updated_at       UTCDATETIME NOT NULL,
  UNIQUE (user_role_id, question_id, schedule_id)
);

CREATE INDEX essay_drafts_user_role_id_idx ON essay_drafts (user_role_id);
CREATE INDEX essay_drafts_question_id_idx ON essay_drafts (question_id);
```

**Why not `question_attempts` for drafts?** The attempt table records a completed, graded answer. An in-progress essay draft is not an attempt — it is mutable, ungraded, and must survive server restarts. Mixing draft state with attempt state would complicate the adaptive engine and break every query that reads attempts.

### 3.4 Auto-Save Protocol

```
Client-side (LiveView):
  - debounce: 2 seconds after last keystroke → push_event("essay_draft_changed", {body, word_count})
  - heartbeat: every 30 seconds while page is focused → push elapsed time

Server-side (handle_event "essay_draft_changed"):
  - upsert essay_draft (UPSERT ON CONFLICT)
  - update `last_saved_at`, `word_count`, `time_elapsed_seconds`
  - push_event back: "draft_saved" with timestamp (client shows "Saved 2s ago")

Server-side (mount / reconnect):
  - Check for existing essay_draft WHERE user_role_id = X AND question_id = Y AND NOT submitted
  - If found: restore body into the textarea socket assign
  - Show unobtrusive banner: "Your draft was restored from [time]."
```

**The save indicator UI:**
```
Auto-saved · 2 seconds ago   [word count: 312 words]
```
- Small, muted secondary text, bottom-left of the essay editor
- Never a spinner — use a subtle "saved" tick icon that fades in on save
- If save fails: turn the indicator red: "Save failed — retrying..."

### 3.5 Timer

Essays are timed on the real exam. FunSheep must show a timer:

```
[39:47 remaining]  ← count-down, yellow at 10 min, red at 5 min
```

- Timer state is stored in `essay_drafts.time_elapsed_seconds` (synced via heartbeat)
- If time runs out: soft-submit (auto-submit current draft) OR show "Time's up — you can still finish and submit"
- **Do not hard-cut the student.** The real digital AP exam allows a grace period. FunSheep should do the same: timer expires → indicator turns red + alert → student can still write for 5 more minutes but sees the warning.
- Timer preference can be disabled per student (useful for accommodations or timed-practice-without-pressure use cases — future scope).

---

## 4. Essay Mode — A Separate UI Experience

### 4.1 Why a New Mode Is Needed

The current `assessment_live.ex` and `quick_practice_live.ex` are designed for rapid question cycling: question → answer → grade → next. An essay requires:
- A full-screen writing environment (no question list, no "next question" CTA)
- A persistent session that can last 40–60 minutes
- A sidebar for source documents (DBQ, AP Synthesis) — or a toggle for sources
- A timer displayed at all times
- No distractions — the student should be in a focused writing context

### 4.2 Essay Mode Route

```
/courses/:course_id/essay/:question_id
/courses/:course_id/schedule/:schedule_id/essay/:question_id
```

### 4.3 Essay Live Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ← Back  │  AP English Language — Synthesis Essay        [39:47] [Submit] │
├──────────────────────────────────────────────────────────────────────────┤
│                        │                                                  │
│  PROMPT & SOURCES      │   YOUR RESPONSE                                  │
│  (left panel,          │                                                  │
│   scrollable)          │   ┌──────────────────────────────────────────┐   │
│                        │   │                                          │   │
│  [Prompt Text]         │   │  Start writing here...                   │   │
│                        │   │                                          │   │
│  Sources:              │   │  (textarea, full height, grows)          │   │
│  [Source A ↗]          │   │                                          │   │
│  [Source B ↗]          │   │                                          │   │
│  [Source C ↗]          │   └──────────────────────────────────────────┘   │
│  [Source D ↗]          │                                                  │
│  [Source E ↗]          │   Auto-saved · 3s ago         312 words          │
│  [Source F ↗]          │                                                  │
│                        │   [What is this rubric? ↗]                       │
│                        │                                                  │
└──────────────────────────┴──────────────────────────────────────────────-─┘
```

**Design rules:**
- Left panel: collapsible on mobile; always visible on desktop if sources exist
- Right panel: full-width if no sources
- No AppBar drawer navigation during an active essay session (distraction-free)
- "Back" is a destructive action if draft exists — show confirmation modal: "Your draft will be saved. You can return and complete this essay later."
- "What is this rubric?" opens a slide-in panel showing the grading rubric criteria and scoring breakdown for this essay type

### 4.4 Submission Confirmation

Before final submit, show a modal:

```
┌─────────────────────────────────────────────┐
│  Submit your essay?                         │
│                                             │
│  312 words · 22 minutes elapsed             │
│                                             │
│  Once submitted, your essay will be graded  │
│  by AI. You cannot edit it after submitting.│
│                                             │
│  [Submit Essay]  [Go Back and Edit]         │
└─────────────────────────────────────────────┘
```

---

## 5. Essay Grading Architecture

### 5.1 New Module: `FunSheep.Questions.EssayGrader`

Essays require a more capable model and exam-specific rubrics. The module architecture:

```
FunSheep.Questions.EssayGrader
  behaviour: FunSheep.Interactor.AssistantSpec
  assistant_name: "funsheep_essay_grader"
  model: "claude-opus-4-7"      ← Opus; essays require sophisticated rhetorical judgment
  temperature: 0.2              ← slightly more than ScoredFreeformGrader; essay judgment has valid subjectivity
  max_tokens: 1024              ← longer; rubric breakdown + comprehensive feedback

  Public API:
    grade(question, rubric_template, student_essay) :: {:ok, EssayGradeResult.t()} | {:error, reason}

  EssayGradeResult type:
    %{
      total_score: integer,
      max_score: integer,
      is_correct: boolean,       # score / max_score >= mastery_threshold (configurable per rubric)
      criteria: [CriterionResult.t()],
      overall_feedback: string,  # 2–3 paragraph evaluation
      strengths: [string],       # 2–3 specific strengths the student demonstrated
      improvements: [string],    # 2–3 specific, actionable improvements
      model_response_hint: string | nil,  # brief note on what a top-scoring answer includes
      grader: :essay_ai | :fallback_binary
    }

  Fallback chain:
    1. EssayGrader (Opus) → on success: return essay result
    2. On failure → ScoredFreeformGrader (Sonnet) → return scored result with generic rubric
    3. On failure → FreeformGrader (Haiku) → return binary result
```

**Why Opus, not Sonnet?**
AP essays, GRE Issue tasks, Bar MEE answers, and LSAT writing samples require the kind of holistic rhetorical and legal judgment that distinguishes a 5/6 from a 6/6. Claude Sonnet handles factual correctness well (sufficient for `free_response`). Essay grading requires nuanced assessment of argumentation quality, sophistication of analysis, and persuasiveness — the domains where Opus provides materially better judgment.

### 5.2 Rubric Templates System

The generic 4-criterion rubric in `ScoredFreeformGrader` is wrong for essays. Each exam type uses its own criteria with its own names and point values. Rubric templates live in the database:

**Migration: `essay_rubric_templates` table**

```sql
CREATE TABLE essay_rubric_templates (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name             VARCHAR(100) NOT NULL,    -- e.g., "ap_english_lang_synthesis_2025"
  exam_type        VARCHAR(50) NOT NULL,     -- e.g., "ap_english_lang", "gre_aw", "bar_mee"
  essay_type       VARCHAR(50),             -- e.g., "synthesis", "rhetorical_analysis", "argument", "issue", "argument_critique"
  max_score        INTEGER NOT NULL,
  mastery_threshold FLOAT NOT NULL DEFAULT 0.75,  -- score / max_score >= this = "correct"
  criteria         JSONB NOT NULL,           -- array of {name, display_name, max_points, description, weight}
  grading_guidance TEXT NOT NULL,            -- injected into system prompt as rubric instructions
  model_answer_notes TEXT,                  -- what a top-scoring answer includes
  source          VARCHAR(50) NOT NULL,      -- 'college_board', 'ets', 'ncbe', 'ib', 'act', 'clt', 'custom'
  published        BOOLEAN NOT NULL DEFAULT false,
  inserted_at      UTCDATETIME NOT NULL,
  updated_at       UTCDATETIME NOT NULL,
  UNIQUE(exam_type, essay_type)
);
```

**Seeded rubric templates (launch set):**

| `exam_type` | `essay_type` | `max_score` | Source |
|---|---|---|---|
| `ap_english_lang` | `synthesis` | 6 | College Board 2025 |
| `ap_english_lang` | `rhetorical_analysis` | 6 | College Board 2025 |
| `ap_english_lang` | `argument` | 6 | College Board 2025 |
| `ap_us_history` | `leq` | 6 | College Board |
| `ap_us_history` | `dbq` | 7 | College Board |
| `ap_english_lit` | `literary_analysis` | 6 | College Board 2025 |
| `gre_aw` | `issue` | 6 | ETS holistic |
| `gre_aw` | `argument_critique` | 6 | ETS holistic |
| `bar_mee` | `essay` | 6 | NCBE relative |
| `act_writing` | `essay` | 24 | ACT (4×6) |
| `clt` | `essay` | 6 | CLT rubric |
| `ib_history` | `essay` | 15 | IB HL criteria |

**Example: AP English Language Synthesis rubric criteria JSONB:**

```json
[
  {
    "name": "thesis",
    "display_name": "Thesis / Claim",
    "max_points": 1,
    "description": "Presents a defensible thesis that responds to the prompt with a defensible claim and establishes a clear line of reasoning. Does not merely restate or rephrase the prompt.",
    "examples_of_full_credit": "A well-constructed claim that addresses the complexity of the issue with a nuanced position.",
    "examples_of_zero": "A restatement of the prompt, or a claim that is too general to be defensible."
  },
  {
    "name": "evidence_commentary",
    "display_name": "Evidence & Commentary",
    "max_points": 4,
    "description": "Uses evidence from at least 3 sources. Commentary explains how evidence supports the line of reasoning. Higher scores demonstrate how evidence develops the argument, not just illustrates it.",
    "scoring_guide": {
      "4": "Consistently uses evidence purposefully; commentary explains how evidence develops argument; reasoning is sustained throughout",
      "3": "Uses evidence to support reasoning; commentary sometimes explains significance",
      "2": "Uses evidence but commentary is limited; evidence is summarized rather than analyzed",
      "1": "Uses evidence with little or no commentary",
      "0": "Restates thesis only; no evidence used"
    }
  },
  {
    "name": "sophistication",
    "display_name": "Sophistication",
    "max_points": 1,
    "description": "Demonstrates a complex understanding of the rhetorical situation. Typically: develops a nuanced argument, considers multiple perspectives, uses stylistic choices purposefully, or situates the argument in a broader context.",
    "note": "Only approximately 5–15% of responses earn this point. Reserve it for essays that genuinely demonstrate complexity — not just ones that are well-written.",
    "examples_of_full_credit": "Acknowledges the limitations of one's own argument; considers alternative interpretations; uses irony, analogy, or other rhetorical moves purposefully."
  }
]
```

### 5.3 Link Rubric Templates to Questions

Questions of type `:essay` must reference a rubric template:

**Migration: `questions` table — add rubric foreign key**

```sql
ALTER TABLE questions 
  ADD COLUMN essay_rubric_template_id UUID REFERENCES essay_rubric_templates(id),
  ADD COLUMN essay_time_limit_minutes INTEGER,    -- e.g., 40 for AP, 30 for Bar
  ADD COLUMN essay_word_limit INTEGER,            -- nil = no limit
  ADD COLUMN essay_word_target INTEGER,           -- suggested minimum (e.g., 300 for AP)
  ADD COLUMN essay_source_documents JSONB;        -- [{title, body, citation}] for DBQ/Synthesis
```

**Schema update** (`lib/fun_sheep/questions/question.ex`):
- Add `:essay` to the `question_type` enum
- Add the four new fields above
- Update `Question.essay?/1` helper: returns `question.question_type == :essay`

### 5.4 `question_attempts` Changes for Essays

When an essay is submitted and graded, record the result in `question_attempts`:

```sql
ALTER TABLE question_attempts
  ADD COLUMN essay_draft_id UUID REFERENCES essay_drafts(id),
  ADD COLUMN essay_word_count INTEGER;
```

The `answer_given` column already stores text; the essay body (potentially 1,500+ words) will be stored there. Verify the column type is `text` (not `varchar(N)`) before the migration. If it is `varchar`, alter the column type.

The `score`, `score_max`, `score_feedback`, `grader_path` fields from `funsheep-scored-freeform-grading.md` Phase 1 must be implemented first — essay grading reuses those columns. Do not duplicate them.

### 5.5 Grading System Prompt Design

The `EssayGrader` system prompt is dynamic — it injects the rubric template at grading time:

```
You are a rigorous but fair academic grader evaluating a student's essay practice response.

Context:
  Exam: {rubric_template.exam_type} — {rubric_template.essay_type}
  Maximum score: {rubric_template.max_score} points
  Grading source: {rubric_template.source} ({rubric_template.name})

RUBRIC:
{rubric_template.grading_guidance}

Criteria breakdown:
{for each criterion in rubric_template.criteria}
  {criterion.display_name} (max {criterion.max_points} points):
    {criterion.description}
    {if criterion.scoring_guide} Scoring guide: {criterion.scoring_guide}
{end}

Grading philosophy:
  - Be consistent. Grade as a trained human grader would, not as a lenient tutor.
  - Partial credit: award partial points where the criterion is partially met.
  - Never award a sophistication/complexity point unless genuinely earned.
  - The overall_feedback must be 2–3 paragraphs: what the student did well overall, what was the core weakness, and what a higher-scoring essay would look like.
  - The improvements list must be specific and actionable: "In your second paragraph, your evidence from Source B is quoted but not analyzed — explain WHY this supports your thesis."
  - Do not fabricate rubric requirements not in the criteria above.

Output: a single JSON object with this exact schema:
{
  "total_score": <integer>,
  "max_score": <integer>,
  "criteria": [{"name": <string>, "earned": <int>, "max": <int>, "comment": <string>}],
  "overall_feedback": <string>,
  "strengths": [<string>, <string>],
  "improvements": [<string>, <string>],
  "model_response_hint": <string>,
  "is_correct": <bool>
}
No markdown. No prose outside the JSON.
```

**Note on `is_correct`**: Server-side only — `total_score / max_score >= rubric_template.mastery_threshold`. The AI's `is_correct` field is logged but never used for adaptive decisions (same security rule as in `funsheep-scored-freeform-grading.md` §2.3).

### 5.6 Streaming Grading Feedback

Opus grading of a 600-word essay takes 8–15 seconds. Students must not stare at a blank screen.

**Streaming strategy**: The `EssayGrader` uses Claude streaming. The feedback renders progressively:

```
Grading your essay...

Checking: Thesis ████░░░░░░
Checking: Evidence & Commentary ██████░░░
Checking: Sophistication ██████████

[Full feedback appears here as it streams...]
```

Implementation: Use the streaming `AssistantSpec` variant. The LiveView receives a `{:essay_grading_stream, chunk}` PubSub message per token and renders into a streaming feedback card. Use the existing `FunSheep.Progress.Event` shape — this is a long-running operation.

### 5.7 The `essay_grading_jobs` Oban Worker

Do not grade synchronously in the LiveView. Use Oban:

```
Student clicks [Submit Essay]
  ↓
EssayDrafts.submit_draft(draft_id, user_role_id)  → marks draft.submitted = true
  ↓
Inserts Oban job: EssayGradingWorker (draft_id, question_id, user_role_id, schedule_id)
  ↓
LiveView subscribes to: "essay_grading:#{draft_id}" PubSub topic
  ↓
Shows: "Grading your essay..." with streaming progress
  ↓
EssayGradingWorker runs:
  1. Load draft + question + rubric_template
  2. Call EssayGrader.grade/3 (streaming)
  3. Broadcast each chunk to PubSub topic
  4. On completion: record question_attempt, mark essay_draft.submitted_at, broadcast final result
  5. On failure: broadcast error, retry up to 3× (Oban retry policy)
  ↓
LiveView renders final EssayFeedbackCard
```

**Why Oban?** The grading call can take 10–15 seconds and must survive server restarts, LiveView disconnects, and mobile backgrounding. Oban provides retry safety. This follows the same pattern as the OCR pipeline and question generation workers.

---

## 6. Discovery Stage Enhancements

The user specifically raised this: different tests grade essays differently. The discovery pipeline must extract rubric criteria from course materials when essays are involved.

### 6.1 Current Discovery Gap

Today, when a teacher uploads a course syllabus or a school test schedule, the OCR pipeline extracts:
- Question text
- Answer options (MC)
- Correct answer
- Chapter / section assignment

It does **not** extract:
- Essay prompts
- Essay rubric criteria (often in the teacher's rubric sheet)
- Source passages for DBQ/synthesis essay questions
- Time limits per essay
- Point values per essay criterion

### 6.2 `EssayRubricExtractor` Worker

New Oban worker: `FunSheep.Workers.EssayRubricExtractorWorker`

Trigger: when a material is ingested and `material_kind` classification returns `essay_rubric_sheet`, `test_guidelines`, or `exam_scoring_guide`.

**Extraction prompt:**

```
You are processing an educational document that may contain essay grading rubrics or scoring criteria.

Extract all essay rubric criteria you find. For each rubric, return:
{
  "essay_type": string,
  "criteria": [{"name": string, "max_points": integer, "description": string}],
  "total_max_points": integer,
  "instructions": string (any special instructions for the grader or student)
}

If no rubric criteria are found, return {"found": false}.
Do not invent criteria not present in the document.
```

**Output**: If found, create or suggest an `essay_rubric_template` record for admin review. Do not auto-publish — the admin must confirm.

### 6.3 Question Generation for Essay Prompts

The AI question generation pipeline already creates `free_response` questions. Add a new classification branch: if the generated question would require 250+ words, classify it as `:essay` and:

1. Attempt to infer `essay_type` from the course's exam type (`ap_english_lang` → suggest `synthesis`, `argument`, or `rhetorical_analysis` based on prompt structure)
2. Assign the matching seeded `essay_rubric_template_id` if a match exists
3. Set `essay_time_limit_minutes` from the known exam time limits
4. If the question requires source documents (synthesis, DBQ): flag for human admin review — do not auto-generate source passages

**DBQ and Synthesis source passages require admin input.** AI can draft placeholder passages, but the No Fake Content rule applies: sources must be real (actual historical documents, real articles) or explicitly labeled as AI-generated practice passages. Mark them clearly:

```
[Practice Source — AI Generated]
Source A: "On the Industrial Revolution's Environmental Impact"
(This is an AI-generated practice source. It is not a real historical document.)
```

---

## 7. Study References for Essays

The existing `funsheep-study-references.md` defines three tiers of study references. Essays need a fourth resource type: **model responses**.

### 7.1 Model Response Resource Type

Extend `video_resources`-style architecture with a new `model_responses` table:

```sql
CREATE TABLE essay_model_responses (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id            UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  score                  INTEGER NOT NULL,  -- what score this model earns on its rubric
  max_score              INTEGER NOT NULL,
  essay_rubric_template_id UUID NOT NULL REFERENCES essay_rubric_templates(id),
  body                   TEXT NOT NULL,
  annotations            JSONB,            -- [{criterion, start_char, end_char, note}] for inline rubric callouts
  source                 VARCHAR(30) NOT NULL,  -- 'admin_authored', 'college_board_released', 'ai_generated'
  label                  VARCHAR(50),      -- e.g., 'Full Credit (6/6)', 'Partial Credit (4/6)', 'Low Score (2/6)'
  published              BOOLEAN NOT NULL DEFAULT false,
  inserted_at            UTCDATETIME NOT NULL,
  updated_at             UTCDATETIME NOT NULL
);
```

**Why annotations?** A model response is most valuable when students can see *which parts* of the essay earned *which criterion*. Inline annotations ("This sentence earns the Thesis point because...") tied to character ranges in the body allow an interactive model response viewer — click a highlighted passage to see the rubric note.

### 7.2 When to Show Model Responses

Show after the student submits and receives their score. **Never before submission** — seeing a model answer before writing is not practice, it is copying.

Display:
```
[Your Essay: 3 / 6 — Partial Credit]
[Your feedback...]

──────────────────────────────────────────
See a model response:
  [Full Credit Example (6/6)]
  [Similar Score (3/6)]
──────────────────────────────────────────
```

Both options open a slide-in panel with the model response and inline annotations. The 3/6 example is especially valuable — it shows the student what a response at their level looks like vs. what bumped it up.

### 7.3 Tier 2 — Topic Study Hub for Essay Types

Extend the Study Hub (`/courses/:id/study/:section_id`) with essay-specific content:

```
[How to Write a Synthesis Essay]

[Concept Overview]   ← AI-generated, hobby-personalized (existing)
[Video Lessons]      ← Khan Academy writing videos (existing video_resources)
[Rubric Guide]       ← Interactive rubric breakdown: what each criterion means
[Annotated Model Response]  ← NEW: a well-annotated high-scoring essay for this type
[Your Recent Essays on this type]
  ← Shows your 3 most recent essay attempts with scores
  ← Tapping expands to show your essay text + the rubric breakdown
```

---

## 8. Premium Plan Integration

### 8.1 Essay Grading is Premium-Only

Grading with Opus on a 1,000-word essay is expensive — approximately 15–25× the token cost of grading a free_response with Haiku binary grading. Essay features must be gated:

| Feature | Free | Standard | Premium / Professional |
|---|---|---|---|
| See essay prompts (read-only) | ✓ | ✓ | ✓ |
| Write an essay draft | ✗ | ✗ | ✓ |
| AI essay grading (Opus, exam rubric) | ✗ | ✗ | ✓ |
| Model response access (post-grading) | ✗ | ✗ | ✓ |
| Essay on own-course questions | ✗ | ✗ | ✓ |
| DBQ / Synthesis with source documents | ✗ | ✗ | ✓ |

**Rationale**: Unlike scored freeform grading (which is a premium enhancement to existing practice), essay mode is a completely different experience. It requires Opus model calls, long session persistence infrastructure, and model response authoring. This is genuinely premium capability.

**Free user experience**: On an essay-type question, show the prompt with a locked overlay:

```
[Essay Prompt visible]
─────────────────────────────────
  ✍️ Essay practice requires a Premium subscription.
  AI-graded essays use exam-specific rubrics to give
  you the kind of feedback a real AP grader would give.
  
  [Unlock with Premium →]   [Learn more]
```

### 8.2 Premium Catalog Connection

The premium catalog (`funsheep-premium-courses-and-tests.md`) includes several high-essay-volume exams. The essay experience is the **primary differentiator** for those courses:

| Premium Course | Essay Volume | Value Prop |
|---|---|---|
| AP English Language & Composition | 3 essays per practice test | Full AP-style Synthesis, Rhetorical Analysis, Argument grading |
| AP US History | DBQ + LEQ per test | College Board-aligned 6/7-point rubrics |
| AP English Literature | Literary analysis essays | Close reading + argumentation rubric |
| GRE Full Prep | Issue + Argument tasks | ETS holistic 0–6 scoring |
| LSAT Prep | Argumentative Writing | Law school admissions reader perspective |
| Bar Exam (MEE) | 6 essays per full practice test | IRAC rubric grading + model NCBE answers |
| ACT Writing | 1 essay per practice test | 4-dimension 0-24 rubric |

### 8.3 Upsell Moment at Essay Boundary

When a free/standard user encounters an essay question mid-assessment:

```
┌──────────────────────────────────────────────────────────┐
│   ✍️ Essay Question                                       │
│                                                           │
│   This test includes an essay. To practice with          │
│   AI grading, upgrade to Premium.                        │
│                                                           │
│   With Premium:                                          │
│   ✓ Real AP-style grading rubric (Thesis, Evidence,      │
│     Commentary, Sophistication)                          │
│   ✓ 2-3 paragraph detailed feedback                     │
│   ✓ Annotated model responses to compare                │
│   ✓ Specific, actionable improvements                   │
│                                                           │
│   [Upgrade to Premium — $59/month]                       │
│   [Skip this essay for now]  ← text link                 │
└──────────────────────────────────────────────────────────┘
```

"Skip this essay" still records the question as skipped in the adaptive engine — the student's assessment is not blocked, just incomplete on this question.

---

## 9. Adaptive Engine Compatibility

The engine uses `is_correct :: boolean` and does not know about essays directly. Map essay scores to `is_correct` via `rubric_template.mastery_threshold`:

```elixir
is_correct = result.total_score / result.max_score >= rubric_template.mastery_threshold
Engine.record_answer(state, question_id, essay_body, is_correct)
```

**Mastery thresholds by exam type:**

| Exam | Mastery Threshold | Rationale |
|---|---|---|
| AP English (0–6) | ≥ 4/6 (67%) | A score of 4/6 is "adequate" and close to the AP exam average |
| GRE AW (0–6) | ≥ 4/6 (67%) | ETS considers 4 an "adequate" performance |
| Bar MEE (0–6) | ≥ 3/6 (50%) | "Relative" grading — 3/6 is median; passing is relative |
| ACT Writing (0–24) | ≥ 15/24 (63%) | ACT's national average is ~16–17/24 |

**Essay questions and the adaptive engine:**

The engine in its current form (`engine.ex`) treats every question type identically. Essay questions need special handling:
- An essay cannot be repeated in the same session (too slow)
- The `:confirm` pending state (second wrong answer triggers a follow-up) should use a different `free_response` question to confirm weakness, not another essay
- Essays should count as "high-confidence, low-frequency" questions in the spaced repetition algorithm — high weight, not revisited in the same session

Add `engine_opts: %{no_same_session_repeat: true, confirmation_type: :free_response}` to essay question records. The engine reads this and adjusts its probing strategy.

---

## 10. Phased Implementation Plan

### Phase 0 — Database Foundation (Week 1)

**Goal**: Schema in place; no visible user change.

Tasks:
1. Migration: `essay_drafts` table
2. Migration: `essay_rubric_templates` table + seed with AP Eng Lang, GRE AW, Bar MEE rubrics
3. Migration: `essay_model_responses` table
4. Migration: add `:essay` to `question_type` enum in `questions`
5. Migration: add `essay_rubric_template_id`, `essay_time_limit_minutes`, `essay_word_limit`, `essay_word_target`, `essay_source_documents`, `essay_draft_id`, `essay_word_count` to `questions` and `question_attempts`
6. Elixir schemas: `EssayDraft`, `EssayRubricTemplate`, `EssayModelResponse` modules
7. Context: `FunSheep.Essays` — `create_draft/3`, `upsert_draft/4`, `submit_draft/2`, `get_draft/3`, `list_model_responses/2`
8. Unit tests for all context functions and schemas

**Exit criteria**: Can create, upsert, and retrieve essay drafts. Can query rubric templates. Zero regressions.

---

### Phase 1 — Auto-Save Infrastructure (Week 2)

**Goal**: The auto-save protocol works end to end.

Tasks:
1. `EssayLive` LiveView at `/courses/:id/essay/:question_id` — basic scaffold (prompt + textarea)
2. Client-side debounce (2s after keystroke) pushing `essay_draft_changed` event
3. Server heartbeat handler (every 30s) updating `time_elapsed_seconds`
4. Draft restoration on mount (check for existing `essay_draft`)
5. "Saved 2s ago" indicator + word count display
6. "Back" navigation guard: confirmation modal if draft exists and not submitted
7. Timer component: countdown, yellow/red warnings, soft-submit on expiry

Tests:
- LiveView test: keystroke → debounce → `upsert_draft` called → "Saved" indicator
- Reconnect test: mount with existing draft → body restored to textarea
- Timer test: elapsed time synced across mount/remount

**Exit criteria**: Student can write 500 words, navigate away, return, and find their text restored exactly.

---

### Phase 2 — Essay Grader Backend (Week 3)

**Goal**: `EssayGrader` module works and is tested in isolation.

Tasks:
1. `FunSheep.Questions.EssayGrader` module (`AssistantSpec` behaviour)
2. Dynamic system prompt construction (injects rubric template)
3. Streaming response handling with PubSub broadcast
4. JSON parsing and validation of `EssayGradeResult`
5. Three-level fallback chain (Opus → Sonnet scored → Haiku binary)
6. `EssayGradingWorker` Oban worker
7. Register `funsheep_essay_grader` assistant in Interactor (Opus, 0.2 temp, 1024 tokens)
8. `Billing.subscription_has_essay_grading?/1` function
9. `EssayDrafts.submit_draft/2` → enqueues Oban job

Tests:
- Unit tests: rubric injection, JSON parsing, fallback paths
- Test that `is_correct` is always server-computed (`total_score / max_score >= threshold`)
- Test malformed responses (missing fields, score > max_score)
- Test Oban worker: successful grade → attempt recorded; failure → retry

**Exit criteria**: Can call `EssayGrader.grade/3` with a real AP Synthesis prompt and a student essay; receives a valid `EssayGradeResult` with criteria breakdown.

---

### Phase 3 — Essay Mode UI (Week 4)

**Goal**: Full essay writing and submission experience for premium users.

Tasks:
1. Full `EssayLive` layout: prompt panel + sources (collapsed by default for non-DBQ) + writing panel
2. Submission confirmation modal
3. Streaming grading progress (Oban job streams via PubSub → LiveView renders)
4. `EssayFeedbackCard` component: total score + criteria breakdown + strengths + improvements
5. Model response viewer (slide-in panel) — empty state if no model responses exist yet
6. Premium gate: locked overlay for free/standard users with upgrade CTA
7. "Rubric Guide" slide-in panel (what each criterion means)
8. Playwright visual tests: full golden path (premium user writes essay, submits, sees graded feedback); locked state (free user)

Design validation: use `ui-design` skill to validate `EssayFeedbackCard` and `EssayLive` layout before marking complete.

**Exit criteria**: Playwright screenshots confirm premium user can write, submit, wait for streaming grade, see criteria breakdown with strengths/improvements. Free user sees locked overlay.

---

### Phase 4 — Study References Integration (Week 5)

**Goal**: Model responses available; Topic Study Hub extended for essays.

Tasks:
1. Admin UI: `/admin/courses/:id/model_responses` — upload/author model responses per question, with annotation support
2. Model response viewer: inline annotations (click highlight → criterion tooltip)
3. Extend Topic Study Hub (`StudyHubLive`) with essay section: rubric guide + model response(s) + recent own essays
4. Post-assessment summary: add essay score column for tests containing essay questions (premium users)
5. Study references Tier 1: after essay graded below mastery, show "See model response" chip below feedback card

Tests:
- Admin: can create model response, set annotations, publish
- StudyHubLive: shows model response section when essay question is for that section
- EssayFeedbackCard: "model response" chip appears when graded below mastery, opens slide-in

**Exit criteria**: Student graded 3/6, sees chip, opens model response, sees inline annotations mapping to rubric.

---

### Phase 5 — Discovery Pipeline Enhancements (Week 6+)

**Goal**: OCR/ingestion pipeline can detect and extract essay rubrics.

Tasks:
1. `material_kind` classifier: add `essay_rubric_sheet` classification type
2. `EssayRubricExtractorWorker`: extract criteria from rubric sheets
3. Admin review UI: review AI-extracted rubrics, approve/reject, link to `essay_rubric_templates`
4. Question generation: detect essay-type prompts (≥250 word responses expected) and assign rubric template at generation
5. DBQ/Synthesis source document workflow: admin can attach real source documents to essay questions
6. Test: rubric sheet PDF → extracted criteria → admin review → published rubric template

**Exit criteria**: Admin uploads an AP English Lang rubric handout; worker extracts thesis/evidence/sophistication criteria; admin confirms and links to AP question bank.

---

### Phase 6 — Professional Exam Polish (Month 2–3)

Depends on premium catalog Phase 4–5 (LSAT, Bar, GRE courses live).

Tasks:
1. LSAT Writing: "admissions reader perspective" grading mode (no numeric score; narrative evaluation)
2. Bar MEE: IRAC rubric + NCBE model answer seeding (NCBE publishes practice MEE answers)
3. GRE AW: two-task session (Issue + Argument back-to-back, 30 min each)
4. ACT Writing: 4-dimension rubric (Ideas/Analysis, Development/Support, Organization, Language)
5. IB subject-specific rubrics: ingestion from IB guide PDFs
6. Essay analytics dashboard (admin): average scores by essay type, rubric criterion heat map (which criteria do students struggle with most?)

---

## 11. Metrics & Success Criteria

| Metric | Target | How to Measure |
|---|---|---|
| Essay draft loss rate (user reports work lost) | 0% | Support tickets tagged "lost essay" |
| Auto-save success rate | > 99.9% | `EssayDrafts.upsert_draft` success rate |
| Essay grading latency (p95) | < 15 seconds | Oban job duration |
| Essay grader fallback rate (Opus → Sonnet) | < 5% | `grader` field in results |
| Criteria breakdown expansion rate | > 40% of graded essays | `criteria_breakdown_expanded` event |
| Model response view rate (after sub-mastery grade) | > 30% | `model_response_viewed` event |
| Essay re-attempt rate (tried again after below-mastery) | > 25% | Subsequent `essay_drafts` for same `question_id` |
| Premium conversion from essay upsell modal | > 3% | `essay_upgrade_modal_shown` → `subscription_started` funnel |

---

## 12. Edge Cases and Error Handling

| Case | Handling |
|---|---|
| Student navigates away during essay | Draft auto-saved; restoration on return |
| Server restart during active essay session | Oban job survives restart; draft persisted in DB |
| Grading takes > 30 seconds | Show "Still grading..." after 15s; retry logic in Oban worker |
| Essay body is blank on submit | Short-circuit: score 0, `is_correct: false`, no Opus call |
| Essay body is very short (< 50 words) | Grade normally; AI will note "insufficient length" in feedback |
| Essay question has no rubric template assigned | Fall back to `ScoredFreeformGrader` with generic rubric; flag for admin review |
| Free user somehow reaches essay mode | Redirect to locked preview with upgrade CTA |
| DBQ/Synthesis sources missing from question | Hide sources panel; note in prompt: "Source documents are not available for this practice question" |
| Grading fails after 3 Oban retries | Store error in `question_attempts.score_feedback`; notify student: "Grading failed — try resubmitting" |
| Essay timer expires | Soft-submit with 5-minute grace; show red warning; auto-submit after grace |

---

## 13. Open Questions (Require Product Decision Before Phase 3)

1. **Retakes**: Can a student rewrite and resubmit an essay after seeing their score? Real AP/GRE exams do not allow retakes, but for practice purposes, rewriting is valuable. Recommendation: yes, allow resubmission; create a new `essay_draft` + `question_attempt`; show score history (attempt 1: 3/6 → attempt 2: 5/6).

2. **Timer enforcement**: Should the timer be enforced (hard-cut at 40+5 min) or advisory (shown, but student can take longer)? The real exam enforces it. For practice, making it advisory reduces anxiety and helps students focus on writing quality. Recommendation: advisory by default with an opt-in "exam mode" that enforces the cut-off.

3. **Model response authoring at scale**: Publishing model responses for every essay question in a course of 400+ questions is expensive. Who authors them? Options: (a) AI generates them at course creation time, labeled "AI-Generated Practice Model"; (b) teachers submit and earn Wool Credits; (c) admin authors for high-value essay types only. Recommendation: (a) for launch, (b) for scale.

4. **Rubric threshold for own-course essays**: Students who upload their own course materials may include essay questions from their teacher. The teacher's rubric may be different from any seeded template. Should own-course essay prompts use the generic 4-criterion rubric or attempt to extract the teacher's criteria? Recommendation: attempt extraction via `EssayRubricExtractorWorker`; fall back to generic rubric with disclaimer.

5. **LSAT Writing numeric score vs. narrative**: The LSAT essay is not scored. Law schools read it holistically. Should FunSheep give a numeric score anyway (for practice gamification) or provide only a narrative evaluation? Recommendation: provide a narrative evaluation plus a "law school reader impression" (Positive / Neutral / Negative) instead of a numeric score. More realistic and more useful.

6. **Essay question in assessment flow interruption**: When the adaptive engine schedules an essay question mid-assessment, the student leaves the rapid-cycle assessment flow for a 40-minute essay session, then returns. Does the engine wait? Recommendation: the assessment session is paused while the essay is active; the engine resumes with the essay result when the student returns. This requires a new `essay_in_progress` state on `assessment_session_states`.

---

## 14. What Not to Build Now

| Idea | Why Not Now |
|---|---|
| Peer review of essays (student grades another student) | Moderation complexity; defer to Phase 6+ |
| Essay plagiarism detection | Not a priority for test prep; students are practicing, not being graded for admissions |
| Rich text editor (bold, italics, headings) | AP/GRE/Bar essays are plain prose; formatting tools are a distraction and not available on the real exam |
| Essay collaboration (multiple students writing together) | No use case in solo test prep context |
| Human grader review queue | Operational overhead; AI grading is the product; human review is a future escalation path |
| Show essays to parents in progress | Parent dashboard doesn't exist; defer |
| Export essay with feedback to PDF | Useful but not critical; defer |
| Flashcard-style essay vocabulary | Out of scope for this roadmap; part of study references |

---

## 15. Related Roadmap Documents

| Document | Relationship |
|---|---|
| `funsheep-scored-freeform-grading.md` | Must implement Phase 1 (scored grader backend) **before** essay grader; the essay grader is its exam-level extension. The `score`, `score_max`, `score_feedback`, `grader_path` columns from that roadmap must exist before Phase 0 here. |
| `funsheep-premium-courses-and-tests.md` | Essay mode is the primary differentiator for AP English, GRE, LSAT, Bar MEE, and ACT Writing premium courses. Implement essay before launching those courses. |
| `funsheep-study-references.md` | `essay_model_responses` is a new resource type alongside `video_resources`. Study Hub Tier 2 must be extended to include model responses for essay questions. |
| `funsheep-readiness-by-topic.md` | Essay scores feed readiness data; the readiness dashboard should show essay score averages per topic |
| `confidence-based-scoring.md` | "Don't Know / Not Sure / I Know" confidence signals are less natural for essays (you wouldn't choose "not sure" before writing for 40 min). Consider disabling confidence signals on essay questions. |
| `funsheep-teacher-credit-system.md` | Teachers who author model responses earn Wool Credits; this scales model response authoring without admin bottleneck. |

---

## 16. Implementation Notes for Claude Sessions

### What Exists (Do Not Rebuild)
- `FunSheep.Questions.FreeformGrader` — reuse as Fallback 2; do not modify
- `FunSheep.Questions.ScoredFreeformGrader` (from `funsheep-scored-freeform-grading.md`) — reuse as Fallback 1; must be implemented first
- `FunSheep.Assessments.StateCache` + `SessionStore` — essay draft is a separate table, not these; do not replace them
- `FunSheep.Progress.Event` PubSub shape — use as-is for streaming grading progress
- Oban job infrastructure — follow existing worker patterns in `lib/fun_sheep/workers/`
- `FunSheep.Interactor.AssistantSpec` behaviour — implement it; register `funsheep_essay_grader` in Interactor before deploying

### What Needs Building (From Scratch)
- `FunSheep.Essays` context + `EssayDraft`, `EssayRubricTemplate`, `EssayModelResponse` schemas
- `FunSheep.Questions.EssayGrader` module (Opus, streaming)
- `FunSheep.Workers.EssayGradingWorker` Oban worker
- `FunSheep.Workers.EssayRubricExtractorWorker` Oban worker
- `FunSheepWeb.EssayLive` LiveView
- `EssayFeedbackCard` component
- `EssayTimerComponent` component
- `EssaySourcesPanel` component (for DBQ/Synthesis)
- `ModelResponseViewer` component (with annotation support)

### Mandatory Rules (From CLAUDE.md)
- **No fake content**: Model responses must be explicitly labeled `source: 'ai_generated'` and marked as practice — never presented as official College Board or NCBE responses
- **No fake content**: Essay prompts must come from real AI generation runs or real exam materials, not hardcoded strings
- **Progress feedback**: Grading is a long-running operation (10–15s); must show streaming progress per the mandatory progress feedback rule
- **Playwright testing**: All essay UI (write, submit, grading, feedback card) must be Playwright-tested before marking complete
- **Interactor Billing**: Essay grading gate goes through `FunSheep.Billing.subscription_has_essay_grading?/1` — do not hardcode plan checks in the LiveView
- **Mix format**: Run `mix format` before committing
- **Test coverage**: > 80% — write tests for every context function and the grader fallback chain
