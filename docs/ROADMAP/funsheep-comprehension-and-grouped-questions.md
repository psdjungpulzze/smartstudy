# FunSheep — Comprehension & Grouped Question Formats: Strategy, Architecture & Roadmap

> **For the Claude session implementing this feature.** Read the entire document before writing a single line of code. Comprehension and grouped question formats require a new database abstraction — `QuestionGroup` — that sits above the existing `questions` table and aligns every rendering path, grading path, AI generation path, and adaptive engine to the same schema. Skipping any section will produce a question type that looks right in isolation but breaks the adaptive loop, the coverage auditor, or the validation pipeline.

---

## 0. Why Comprehension Requires a New Abstraction

FunSheep currently models questions as fully standalone rows. A question has `content`, `answer`, `options`, and links to a course → chapter → section hierarchy. Every question is self-contained.

**Comprehension questions break this model.** A reading comprehension set on the SAT consists of one 700-word passage followed by 10 questions. All 10 questions share the passage. The passage is not a question. It cannot live in `content` of one of the questions (which question? all of them redundantly?). It is stimulus material — context that frames multiple questions.

The same problem appears in every high-stakes exam format we need to support:

| Format | Stimulus | Questions per group |
|---|---|---|
| SAT Reading | 500–900 word literary/informational passage | 10–11 |
| ACT Reading | 700-word passage (4 per test) | ~10 |
| AP English (synthesis essay) | 6–7 primary source excerpts | 1 essay |
| AP US History DBQ | 7 primary source documents | 1 essay |
| MCAT Passage | 500-word science passage | 4–7 |
| USMLE Clinical Vignette | 200-word patient case | 1–3 follow-up |
| GRE Reading Comprehension | 200–450 word passage | 1–4 |
| LSAT Reading Comprehension | 450-word passage | 5–7 |
| TOEFL Reading | 700-word academic passage | 10 |
| IELTs Reading | 900-word passage | 13–14 |
| AP Bio/Chem stimulus set | Table, graph, or experimental data | 3–5 |

**The fix**: introduce a `QuestionGroup` schema as the shared stimulus container. Questions keep their existing schema and gain an optional `question_group_id` FK. A nil FK means "standalone question" — the existing model. A non-nil FK means "part of a comprehension set." The adaptive engine, the rendering layer, the question generation pipeline, and the coverage auditor all need to understand this distinction.

---

## 1. Full Taxonomy of Question Formats

This section maps every question format relevant to FunSheep's target tests to a storage strategy and grading strategy. This is the authoritative reference for deciding whether a new format needs a `QuestionGroup`, a new question type enum value, or just a new rendering branch.

### 1.1 Formats That Require a QuestionGroup (Stimulus-Bound)

These formats **require** a `QuestionGroup` because the stimulus is shared across multiple questions or is too large to embed in a single `content` field.

| Format | Stimulus Type | Questions | Grading |
|---|---|---|---|
| **Reading Comprehension** | Prose passage (fiction, non-fiction, dual texts) | MCQ, short-answer | Exact match (MCQ) / FreeformGrader with passage context |
| **Data Interpretation** | Table, chart, graph, or multi-panel data set | MCQ, short-answer | Exact match / FreeformGrader |
| **Clinical Vignette (USMLE)** | Patient case description | MCQ (single best answer) | Exact match |
| **Science Passage (MCAT)** | Dense science passage with experiments | MCQ | Exact match |
| **Primary Sources Set (AP History)** | 3–7 historical documents | Essay | EssayGrader (see essay ROADMAP) |
| **Synthesis Sources (AP English)** | 5–7 argumentative/literary excerpts | Essay | EssayGrader |
| **Dual Passage** | Two related passages (Passage 1 + 2) | MCQ, comparison questions | Exact match / FreeformGrader |
| **Audio Comprehension** | Audio transcript (for future audio support) | MCQ, short-answer | Exact match / FreeformGrader |

### 1.2 New Standalone Question Type Formats

These formats require new `question_type` enum values but do **not** require a `QuestionGroup`. They can stand alone or appear inside a group.

| Format | Description | Current Status | Grading |
|---|---|---|---|
| **Multi-Select MCQ** | "Choose ALL that apply" — 2+ correct answers | Missing | Full-set exact match; optional partial credit |
| **Cloze (Fill-in-the-blank)** | Sentence or paragraph with one or more blanks to complete | Missing | Exact match per blank; optional FreeformGrader for semantic matching |
| **Matching** | Match items from Column A to Column B | Missing | Full-set match; partial credit per pair optional |
| **Ordering / Sequencing** | Arrange items in the correct sequence | Missing | Full-sequence match; partial credit by longest common subsequence |
| **Numeric Grid-In** | Student types a number (no options shown) | Missing | Numeric tolerance comparison (e.g., within 1%) |

### 1.3 Formats Already Planned or Partially Implemented

These formats are covered by other ROADMAP documents. Do not re-implement them here; this document only defines how they interact with `QuestionGroup`.

| Format | Status | Related ROADMAP |
|---|---|---|
| `free_response` (short text) | Implemented (binary grading) | `funsheep-scored-freeform-grading.md` (upgrades to rubric scoring) |
| `true_false` | Implemented | — |
| `multiple_choice` (single answer) | Implemented | — |
| Essay (500–1500 words, exam rubric) | Planned | `funsheep-essay-tests.md` |
| Questions with images / graphs | Planned | `funsheep-questions-with-images-and-graphs.md` |

### 1.4 Formats to Explicitly Defer

These formats have real-exam equivalents but should not be built now due to UI complexity, unclear demand, or dependency on unbuilt infrastructure.

| Format | Why Deferred |
|---|---|
| **Hotspot (click on image region)** | Requires image support to be stable first (`funsheep-questions-with-images-and-graphs.md`); precise pixel-region hit-testing in LiveView is non-trivial |
| **Drag-and-drop (visual)** | Matching and ordering can launch with click-to-select UI; drag-and-drop is an enhancement pass |
| **Audio comprehension** | No audio ingestion pipeline exists; requires separate roadmap |
| **Interactive diagram** | Too complex for initial delivery; build after image support is complete |

---

## 2. Data Model

### 2.1 New: `question_groups` Table

The `QuestionGroup` is the stimulus container. It holds the shared passage, data set, vignette, or source set. Questions point to it; it does not embed questions.

```elixir
defmodule FunSheep.Questions.QuestionGroup do
  use Ecto.Schema

  schema "question_groups" do
    field :stimulus_type, Ecto.Enum, values: [
      :reading_passage,     # Prose passage (SAT, ACT, LSAT, GRE, TOEFL, IELTS)
      :data_set,            # Table, chart, graph, or multi-panel data (AP Bio/Chem, ACT Science)
      :clinical_vignette,   # Patient case (USMLE, NCLEX)
      :science_passage,     # Dense experiment/research passage (MCAT)
      :primary_sources,     # Historical documents set (AP History DBQ)
      :synthesis_sources,   # Argumentative/literary excerpts (AP English)
      :dual_passage,        # Two related passages (SAT Passage 1 + 2)
      :audio_transcript     # Reserved for future audio support
    ]

    field :stimulus_title, :string          # Optional: "Passage 1: 'The Migration of Monarchs'"
    field :stimulus_content, :string        # The passage/case/data as markdown-safe plain text
    field :stimulus_html, :string           # Optional: rich-formatted version (tables, footnotes)
    field :word_count, :integer             # Computed at insert; used for reading level estimate
    field :reading_level, :string           # Flesch-Kincaid grade level (computed)
    field :difficulty, Ecto.Enum, values: [:easy, :medium, :hard]

    # Provenance — mirrors Question provenance fields
    field :source_type, Ecto.Enum, values: [:web_scraped, :user_uploaded, :ai_generated, :curated]
    field :generation_mode, :string
    field :grounding_refs, :map, default: %{}

    # Validation — groups go through the same validation pipeline as questions
    field :validation_status, Ecto.Enum,
      values: [:pending, :passed, :needs_review, :failed],
      default: :pending
    field :validation_score, :float
    field :validation_report, :map, default: %{}
    field :validated_at, :utc_datetime

    # Metadata — flexible bag for exam-specific properties
    # e.g.: %{"exam" => "SAT", "test_year" => 2024, "section" => "Reading Test 1"}
    field :metadata, :map, default: %{}

    # Hierarchy
    belongs_to :course, FunSheep.Courses.Course
    belongs_to :chapter, FunSheep.Courses.Chapter
    belongs_to :section, FunSheep.Courses.Section
    belongs_to :school, FunSheep.Geo.School
    belongs_to :source_material, FunSheep.Content.UploadedMaterial

    has_many :questions, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end
end
```

**Key design decisions:**

- `stimulus_content` stores plain text (markdown-safe). `stimulus_html` stores rich formatting when needed (tables with colspan, footnotes, dual-column layout). Renderers prefer `stimulus_html` when present.
- `word_count` and `reading_level` are computed at insert by a simple helper — they are not validated by the AI. They help the admin UI show passage difficulty at a glance.
- The group carries provenance fields (`source_type`, `generation_mode`, `grounding_refs`) that mirror Question provenance. A comprehension group may have been extracted from an uploaded past exam paper, scraped from an AP Central practice page, or generated by AI.
- Validation mirrors Question validation. A group with `validation_status: :passed` and at least one question with `validation_status: :passed` is visible to students.

### 2.2 Changes to `questions` Table

Two new fields on the existing `questions` table:

```elixir
# In migration
alter table(:questions) do
  add :question_group_id, references(:question_groups, type: :binary_id, on_delete: :nilify_all), null: true
  add :group_sequence, :integer, null: true  # 1, 2, 3... within the group
end

create index(:questions, [:question_group_id])
create index(:questions, [:question_group_id, :group_sequence])
```

**Rules:**
- `question_group_id: nil` — standalone question. Existing behavior unchanged.
- `question_group_id: <uuid>` — grouped question. Must have `group_sequence >= 1`.
- `group_sequence` is only meaningful when `question_group_id` is non-nil. Nullable to avoid adding a constraint to all existing rows.
- `on_delete: :nilify_all` — if a group is deleted, its questions become standalone (not deleted). This preserves question history.

### 2.3 New Question Type Enum Values

Add four new values to the `question_type` enum. These require a PostgreSQL `ALTER TYPE` migration (safe on Postgres 10+):

```sql
ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'multi_select';
ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'cloze';
ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'matching';
ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'ordering';
ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'numeric';
```

| New Type | Description | `options` field shape | `answer` field shape |
|---|---|---|---|
| `multi_select` | Choose all correct answers (2+) | Same as `multiple_choice`: `%{"a" => "...", "b" => "...", ...}` | Sorted comma-separated keys: `"a,c"` |
| `cloze` | Fill blanks in a passage/sentence | `%{"blanks" => [%{"id" => "1", "hint" => "noun", "word_bank" => [...]}]}` | `%{"1" => "photosynthesis", "2" => "chlorophyll"}` |
| `matching` | Match left-side items to right-side items | `%{"left" => ["A", "B", "C"], "right" => ["1", "2", "3"]}` | `%{"A" => "2", "B" => "3", "C" => "1"}` |
| `ordering` | Arrange items in correct sequence | `%{"items" => ["E", "D", "B", "A", "C"]}` (shuffled) | `"A,B,C,D,E"` (correct order, comma-separated) |
| `numeric` | Enter a number (no options) | `%{"unit" => "mg/dL", "tolerance_pct" => 1}` | `"126"` (as string; compared with tolerance) |

**Why `answer` is still a string/map and not a richer type:**
The existing grading pipeline, AI generation prompts, and admin import tooling all assume `answer` is a string. Keeping it serialized (comma-separated keys, JSON-encoded maps) avoids a migration on all existing rows and keeps the grading boundary simple: compare `question.answer` vs `attempt.answer_given`.

### 2.4 `options` Field Conventions (Complete Reference)

| Type | `options` shape |
|---|---|
| `multiple_choice` | `%{"a" => "text", "b" => "text", "c" => "text", "d" => "text"}` |
| `true_false` | `%{"true" => "True", "false" => "False"}` |
| `multi_select` | `%{"a" => "text", "b" => "text", "c" => "text", "d" => "text", "e" => "text"}` |
| `cloze` | `%{"blanks" => [%{"id" => "1", "word_bank" => ["word1", ...], "hint" => nil}], "passage" => "The __1__ process..."}` |
| `matching` | `%{"left" => ["item A", "item B", ...], "right" => ["match 1", "match 2", ...]}` |
| `ordering` | `%{"items" => ["step C", "step A", "step B"]}` (pre-shuffled for display) |
| `numeric` | `%{"unit" => "ml", "tolerance_pct" => 2, "min" => 0, "max" => 999}` |
| `short_answer` | `nil` |
| `free_response` | `nil` |

---

## 3. Grading Architecture

### 3.1 Grading Matrix

| Type | Grader Module | `is_correct` logic | Partial credit |
|---|---|---|---|
| `multiple_choice` | `ExactGrader` | `answer_given == question.answer` | No |
| `true_false` | `ExactGrader` | `answer_given == question.answer` | No |
| `multi_select` | `MultiSelectGrader` (new) | All selected keys must equal all correct keys | Optional (see 3.3) |
| `short_answer` | `FreeformGrader` | AI semantic match ≥ threshold | No (binary) |
| `free_response` | `ScoredFreeformGrader` (from freeform ROADMAP) | score ≥ 7 → correct | Yes (rubric score) |
| `cloze` | `ClozeGrader` (new) | All blanks correct → correct; else incorrect | Optional (% blanks correct) |
| `matching` | `MatchingGrader` (new) | All pairs correct → correct | Optional (% pairs correct) |
| `ordering` | `OrderingGrader` (new) | Exact sequence match | Optional (LCS-based %) |
| `numeric` | `NumericGrader` (new) | `abs(answer - correct) / correct <= tolerance_pct / 100` | No |

### 3.2 Comprehension Questions and Grading Context

When a question has a `question_group_id`, grading context must include the stimulus. For AI-graded types (`short_answer`, `free_response`) inside a comprehension group, the grader injects the passage into the system prompt:

```elixir
# In FreeformGrader or ScoredFreeformGrader — new overload
def grade_with_context(question, answer_given, %QuestionGroup{} = group) do
  system_prompt = """
  You are grading a reading comprehension question.

  PASSAGE:
  #{group.stimulus_content}

  QUESTION: #{question.content}
  CORRECT ANSWER: #{question.answer}
  STUDENT ANSWER: #{answer_given}

  ...
  """
  # same rubric logic as standalone grading
end
```

For MCQ comprehension questions, no context injection is needed — the answer key is deterministic.

### 3.3 Partial Credit Architecture

Partial credit affects `score` and `score_max` on `QuestionAttempt`. It does **not** affect `is_correct` — that remains binary for the adaptive engine. This mirrors the design decision in `funsheep-scored-freeform-grading.md`.

Partial credit maps:
- `multi_select`: `score = (correct_selected / total_correct_options) * 10`; `is_correct = (score >= 10)` (all-or-nothing by default, but configurable per question via `options["partial_credit_mode"]`)
- `matching`: `score = (correct_pairs / total_pairs) * 10`
- `ordering`: `score = (lcs_length / total_items) * 10` where LCS = longest common subsequence of positions

### 3.4 New Grader Modules (Minimal Implementations)

```
lib/fun_sheep/questions/
├── multi_select_grader.ex    -- compare string-set after split(",") + sort
├── cloze_grader.ex           -- compare each blank independently
├── matching_grader.ex        -- compare each pair independently
├── ordering_grader.ex        -- LCS algorithm for partial credit
├── numeric_grader.ex         -- tolerance-aware numeric comparison
```

All graders implement the same contract:

```elixir
@callback grade(question :: Question.t(), answer_given :: String.t()) ::
  {:ok, %{correct: boolean(), score: float(), score_max: float(), feedback: String.t() | nil}}
```

---

## 4. AI Generation Pipeline

### 4.1 New Generation Modes

The existing `AiQuestionGenerationWorker` generates individual questions. Add a parallel worker for group-based generation:

```
lib/fun_sheep/workers/ai_group_generation_worker.ex
```

This worker:
1. Accepts a `stimulus_type` and a grounding reference (e.g., a source_material PDF page range, a discovered source URL, or curriculum text)
2. Calls Interactor AI agent `"funsheep_comprehension_generator"` (to be registered)
3. Receives back: `{group: {stimulus_type, stimulus_content, title}, questions: [...]}`
4. Inserts a `QuestionGroup` row, then N `Question` rows with `question_group_id` set
5. Enqueues `QuestionGroupValidationWorker` (new) for the whole group

**Agent prompt contract (JSON schema the agent must return):**

```json
{
  "stimulus": {
    "title": "string or null",
    "content": "string (the passage text)",
    "type": "reading_passage | data_set | clinical_vignette | ..."
  },
  "questions": [
    {
      "sequence": 1,
      "type": "multiple_choice | short_answer | multi_select | ...",
      "content": "string (question text)",
      "options": {...},
      "answer": "string",
      "explanation": "string",
      "difficulty": "easy | medium | hard"
    }
  ]
}
```

### 4.2 Comprehension Generation from Uploaded Materials

When a student uploads a past exam paper containing comprehension sections, the OCR pipeline currently extracts questions as standalone rows. It needs a new extraction mode:

`QuestionExtractionWorker` needs a `detect_groups: true` flag that:
1. Uses a multipage context window to detect "Passage: ..." headers followed by numbered questions
2. Creates a `QuestionGroup` for each detected passage
3. Associates extracted questions to the group via `question_group_id`

This is a separate sub-feature. Flag it as Phase 3 in the implementation order below.

### 4.3 Coverage Auditing for Groups

The Phase 6 coverage auditor (`Questions.coverage_by_chapter/1`, `coverage_by_section/1`) counts individual questions. Groups do not change this — each question in a group still carries `chapter_id` and `section_id`. Coverage counts remain per-question.

**However**, add a new coverage dimension: `coverage_by_stimulus_type/1` — how many groups of each stimulus type exist per chapter. This surfaces gaps like "Chapter 3 (Cell Division) has no reading passage sets, only standalone MCQs."

---

## 5. Rendering Architecture

### 5.1 Standalone vs. Grouped Rendering Decision

In every LiveView that renders questions (`assessment_live.ex`, `quick_practice_live.ex`, `quick_test_live.ex`), add a rendering branch at the outermost level:

```elixir
# Pseudo-code pattern for every question-rendering LiveView
case {question.question_group_id, question.question_type} do
  {nil, _}          -> render_standalone(question)
  {_id, _}          -> render_grouped(question, question.question_group)
end
```

Where `render_grouped/2` fetches the group stimulus and displays it alongside the question.

### 5.2 Passage Layout (Split-Panel)

Reading comprehension and clinical vignette groups need a split-panel layout:

```
┌─────────────────────────────────────────────────────────────────┐
│                         Question N of M                         │
├──────────────────────────┬──────────────────────────────────────┤
│  STIMULUS PANEL (sticky) │  QUESTION PANEL (scrollable)        │
│  max-w-[48%], overflow-y │                                      │
│  -auto, pr-4             │  Question text                       │
│                          │                                      │
│  [Passage title]         │  A. Option A                         │
│                          │  B. Option B                         │
│  Passage text scrolls    │  C. Option C ✓                       │
│  independently           │  D. Option D                         │
│                          │                                      │
│                          │  [Next →]                            │
└──────────────────────────┴──────────────────────────────────────┘
```

Implementation: Two-column grid in LiveView with `overflow-y-auto` on the left panel. The right panel is the existing question renderer.

**On mobile**: Stimulus collapses into an expandable "Read Passage" accordion above the question. Questions never show before the student has a way to access the passage.

### 5.3 Per-Type Rendering Components

| Type | Component | UI |
|---|---|---|
| `multiple_choice` | Existing | Radio buttons (unchanged) |
| `true_false` | Existing | Radio buttons (unchanged) |
| `multi_select` | `MultiSelectQuestion` (new) | Checkboxes; "Select all that apply" label; submit only enabled when ≥1 selected |
| `cloze` | `ClozeQuestion` (new) | Inline text inputs replacing `__N__` placeholders in rendered passage; or word-bank drag-and-drop as enhancement |
| `matching` | `MatchingQuestion` (new) | Left column with dropdown or click-to-match for each item; shuffle right column on render |
| `ordering` | `OrderingQuestion` (new) | Numbered items with ↑ / ↓ arrow buttons for reordering (Phase 1); drag-and-drop enhancement pass later |
| `numeric` | `NumericQuestion` (new) | Single text input with unit label; numeric keyboard on mobile |

### 5.4 Progress Indicators for Grouped Questions

When a student is working through a question group, show:

- **Group progress**: "Question 3 of 7 — Reading Comprehension Set"
- **Passage identifier**: "Passage 1: 'The Great Migration'"
- **Within-group navigation**: Previous / Next buttons that stay within the group before advancing to the next standalone question

After completing the full group, show a **Group Summary Card**: "You got 5 of 7 questions right in this set."

---

## 6. Adaptive Engine Integration

The adaptive engine (readiness scoring, question scheduling) currently operates on individual questions. Grouped questions require two clarifications:

### 6.1 Individual Scoring Preserved

Each question in a group is still scored individually. A `QuestionAttempt` row is created per question. The adaptive engine sees `is_correct` per question, not per group. This is correct — each question in a passage set may test a different reading skill.

### 6.2 Group Scheduling Policy

When the adaptive engine schedules a question that belongs to a group, it **must** schedule the entire group — not just the one question. Delivering question 4 of 7 without questions 1–3 is a broken experience.

**Scheduling rule**: When a question with `question_group_id` is selected, replace it in the queue with all questions in the group (ordered by `group_sequence`). The group is treated as an atomic unit from the scheduling perspective.

This requires a check in `AssessmentEngine.select_next_question/2`:

```elixir
case question.question_group_id do
  nil ->
    [question]
  group_id ->
    Questions.list_group_questions(group_id)
end
```

### 6.3 Readiness Impact

Section readiness is computed from `is_correct` on `QuestionAttempt` rows for questions in that section. Because comprehension questions still carry `section_id`, their attempts feed readiness normally. No change needed to the readiness calculation.

---

## 7. Validation Pipeline Extension

### 7.1 Group-Level Validation

Add `QuestionGroupValidationWorker` that validates:
1. Stimulus coherence: Is the passage self-contained? Does it have an identifiable topic?
2. Question-passage alignment: Do all questions in the group actually require the passage to answer?
3. Difficulty consistency: Are all questions at roughly the declared difficulty?
4. Minimum question count: Reject groups with fewer than 2 questions (a single question does not benefit from having a group)

The worker uses the same `Interactor.Agents.chat/3` pattern as the existing `QuestionValidationWorker`.

### 7.2 Student Visibility Rule Extension

A question in a group is visible to students only if:
- `question.validation_status == :passed`
- `question.question_group.validation_status == :passed`

Questions in an unvalidated group must not appear in practice, even if the individual question passed validation. The stimulus may be incoherent or misaligned.

---

## 8. Admin UI

### 8.1 Question Bank Extension

`question_bank_live.ex` currently shows a flat list of questions. Extend it to:

1. **Group indicator**: Questions with `question_group_id` show a "Set" badge with the group name and their position ("3/7")
2. **Group detail view**: Click a group badge to expand and see all questions in the group with the stimulus panel
3. **Group creation UI**: Admin can create a group by pasting a passage and then writing/importing questions into it
4. **Bulk type assignment**: When creating a group, admin sets the `stimulus_type` and the questions inherit it in their metadata

### 8.2 Group Validation Queue

A new admin view: `/admin/question-groups/review` listing groups with `validation_status: :needs_review`. Each group shows the stimulus alongside all its questions for human review.

---

## 9. Implementation Phases

### Phase 0 — Foundation (Schema & Migration)

**Duration estimate**: 1–2 days  
**Prerequisites**: Nothing  
**Deliverables**:
- Migration: create `question_groups` table
- Migration: add `question_group_id` and `group_sequence` to `questions`
- Migration: add new `question_type` enum values (`multi_select`, `cloze`, `matching`, `ordering`, `numeric`)
- `QuestionGroup` schema + context functions in `FunSheep.Questions`
- `Questions.list_group_questions/1`
- `Questions.coverage_by_stimulus_type/1`
- Basic tests: schema validation, group creation, FK integrity

### Phase 1 — New Standalone Question Types (No Group Required)

**Duration estimate**: 2–3 days  
**Prerequisites**: Phase 0  
**Deliverables**:
- `MultiSelectGrader`, `ClozeGrader`, `MatchingGrader`, `OrderingGrader`, `NumericGrader` modules
- Rendering components: `MultiSelectQuestion`, `ClozeQuestion`, `MatchingQuestion`, `OrderingQuestion`, `NumericQuestion`
- Wire into `assessment_live.ex` and `quick_practice_live.ex`
- Extend `QuestionAttempt` to store `score` and `score_max` (needed for partial credit)
- AI generation prompt templates for each new type
- Tests: each grader, each rendering component

### Phase 2 — Reading Comprehension (Groups + Split-Panel Rendering)

**Duration estimate**: 3–4 days  
**Prerequisites**: Phase 0  
**Deliverables**:
- `QuestionGroup` stimulus rendering (split-panel layout)
- Adaptive engine group scheduling patch
- `QuestionGroupValidationWorker` Oban worker
- AI group generation: `AiGroupGenerationWorker` + Interactor agent registration
- Admin question bank group indicator and group detail view
- Group progress indicators in practice UI
- Group summary card after group completion
- Tests: split-panel render, group scheduling, validation worker

### Phase 3 — Comprehension Extraction from Uploaded Materials

**Duration estimate**: 2–3 days  
**Prerequisites**: Phase 2, OCR pipeline stability  
**Deliverables**:
- `QuestionExtractionWorker` `detect_groups: true` mode
- Passage detection heuristics (header patterns: "Questions 1–10 refer to the following passage...")
- Tests: passage detection accuracy on sample SAT/MCAT PDFs

### Phase 4 — Multi-Passage and Primary Sources (DBQ / Synthesis)

**Duration estimate**: 2 days  
**Prerequisites**: Phase 2, essay ROADMAP Phase 1 (for essay grading)  
**Deliverables**:
- `dual_passage` stimulus type rendering (Passage 1 / Passage 2 tabs or stacked)
- `primary_sources` stimulus type rendering (numbered source cards, collapsible)
- Integration with Essay grading for DBQ essay questions inside a group

---

## 10. Migration Safety Notes

### PostgreSQL `ALTER TYPE ADD VALUE` Constraints

Adding enum values to a PostgreSQL enum type is **safe** and does not require a table rewrite. However, new enum values cannot be used in the same transaction that adds them. Use `Ecto.Migration.execute/1` for each `ALTER TYPE` and run them in their own migration file (not bundled with table alterations).

```elixir
defmodule FunSheep.Repo.Migrations.AddNewQuestionTypes do
  use Ecto.Migration

  def up do
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'multi_select'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'cloze'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'matching'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'ordering'"
    execute "ALTER TYPE question_type ADD VALUE IF NOT EXISTS 'numeric'"
  end

  def down do
    # PostgreSQL does not support removing enum values without recreating the type.
    # Acceptable: leave the values; they are only used if questions have that type.
    :ok
  end
end
```

### `question_group_id` FK with `on_delete: :nilify_all`

When a `QuestionGroup` is deleted, all associated `questions.question_group_id` values are set to NULL. This means the questions become standalone rather than being deleted. This is correct — question attempts reference questions, not groups. Deleting a group should never cascade to question attempts.

---

## 11. File Map

| New/Changed File | Purpose | Phase |
|---|---|---|
| `priv/repo/migrations/XXXXXX_create_question_groups.exs` | `question_groups` table | 0 |
| `priv/repo/migrations/XXXXXX_add_group_fields_to_questions.exs` | `question_group_id`, `group_sequence` | 0 |
| `priv/repo/migrations/XXXXXX_add_new_question_types.exs` | New enum values | 0 |
| `priv/repo/migrations/XXXXXX_add_score_to_question_attempts.exs` | `score`, `score_max` on attempts | 1 |
| `lib/fun_sheep/questions/question_group.ex` | Schema | 0 |
| `lib/fun_sheep/questions.ex` | Add `list_group_questions/1`, `coverage_by_stimulus_type/1`, group CRUD | 0 |
| `lib/fun_sheep/questions/multi_select_grader.ex` | Multi-select grading | 1 |
| `lib/fun_sheep/questions/cloze_grader.ex` | Cloze grading | 1 |
| `lib/fun_sheep/questions/matching_grader.ex` | Matching grading | 1 |
| `lib/fun_sheep/questions/ordering_grader.ex` | Ordering + LCS partial credit | 1 |
| `lib/fun_sheep/questions/numeric_grader.ex` | Numeric tolerance grading | 1 |
| `lib/fun_sheep/workers/ai_group_generation_worker.ex` | AI comprehension group generation | 2 |
| `lib/fun_sheep/workers/question_group_validation_worker.ex` | Group-level validation | 2 |
| `lib/fun_sheep_web/components/question_group_stimulus.ex` | Stimulus panel component | 2 |
| `lib/fun_sheep_web/components/multi_select_question.ex` | Multi-select checkboxes | 1 |
| `lib/fun_sheep_web/components/cloze_question.ex` | Cloze inline blanks | 1 |
| `lib/fun_sheep_web/components/matching_question.ex` | Matching column UI | 1 |
| `lib/fun_sheep_web/components/ordering_question.ex` | Ordering arrow UI | 1 |
| `lib/fun_sheep_web/components/numeric_question.ex` | Numeric text input | 1 |
| `lib/fun_sheep_web/components/question_group_progress.ex` | "Q 3 of 7 in this set" | 2 |
| `lib/fun_sheep_web/components/question_group_summary.ex` | Post-group "5/7 correct" card | 2 |
| `lib/fun_sheep_web/live/assessment_live.ex` | Extend: grouped rendering, scheduling patch | 2 |
| `lib/fun_sheep_web/live/quick_practice_live.ex` | Extend: grouped rendering | 2 |
| `lib/fun_sheep_web/live/quick_test_live.ex` | Extend: grouped rendering | 2 |
| `lib/fun_sheep_web/live/question_bank_live.ex` | Group badge, group detail view, group creation UI | 2 |
| `test/fun_sheep/questions/multi_select_grader_test.exs` | | 1 |
| `test/fun_sheep/questions/cloze_grader_test.exs` | | 1 |
| `test/fun_sheep/questions/matching_grader_test.exs` | | 1 |
| `test/fun_sheep/questions/ordering_grader_test.exs` | | 1 |
| `test/fun_sheep/questions/numeric_grader_test.exs` | | 1 |
| `test/fun_sheep/questions/question_group_test.exs` | Schema + context tests | 0 |
| `test/fun_sheep_web/live/assessment_live_group_test.exs` | Split-panel rendering, group navigation | 2 |

---

## 12. Open Questions (Require Product Decision Before Implementation)

1. **Partial credit and the adaptive engine**: The adaptive engine currently uses binary `is_correct`. Should partial credit ever influence adaptive scheduling? For example, should a student who scored 7/10 on a matching question advance more slowly than one who scored 10/10? Recommendation: no — keep the binary gate for the adaptive engine and reserve partial credit for the student-facing score display only. This keeps the invariants in `PRODUCT_NORTH_STAR.md` clean.

2. **Cloze word bank vs. open entry**: Should cloze questions always show a word bank (limited MCQ feel), or sometimes require open free-text entry per blank? Word bank is easier to grade (exact match) and more like real TOEFL fill-in questions. Open entry requires per-blank FreeformGrader calls. Recommendation: launch with word-bank only; open-entry cloze is an enhancement pass.

3. **Group size limits**: Should there be a maximum number of questions per group enforced at the schema level? Real SAT passages have 10–11 questions. MCAT passages have 4–7. LSAT passages have 5–7. Recommendation: soft limit of 15 questions per group via a changeset validation; no hard DB constraint. Admin can override if needed.

4. **Ordering partial credit default**: Is partial credit on ordering opt-in (per question) or opt-in for the grader (always compute it, always store it)? Recommendation: always compute LCS-based partial score and store it in `score`/`score_max`; whether to display it to the student is a UI-level flag on the question's `metadata`.

5. **Coverage auditing for groups**: Currently `coverage_by_section/1` counts questions. Should it count groups or questions? A section might have 3 standalone MCQs + 1 comprehension group with 7 questions. From a coverage perspective, 10 questions exist, but only 1 passage set. Both metrics are useful. Recommendation: track both — existing question count (unchanged) + new group count — and surface both in the admin coverage dashboard.

6. **Comprehension in quick practice vs. full assessment**: Quick practice sessions present 1 question at a time, randomized. A comprehension group cannot be split — all 7 questions must appear together. Should comprehension groups be excluded from quick practice entirely (only appear in full assessments), or should quick practice enter "group mode" when it draws a grouped question? Recommendation: quick practice enters group mode automatically when a grouped question is drawn; the session temporarily extends by the remaining questions in the group. This is a better experience than excluding comprehension from casual practice.

---

## 13. Metrics for Success

| Metric | Target | Measurement |
|---|---|---|
| Reading comprehension group creation → validation pipeline success rate | >85% | `validation_status: :passed` on first attempt |
| Comprehension group scheduling delivers full group (not partial) | 100% | Zero `question_attempts` for mid-group questions without prior-group attempts |
| Cloze/matching/ordering grader accuracy vs. human-graded sample | >95% | Manual audit of 100 graded attempts per type |
| Split-panel render time (passage + first question) | <300ms | LiveView telemetry |
| Mobile passage accordion UX abandonment rate | <20% | `passage_accordion_closed` events before completing any question in group |
| Questions per group (distribution health) | Avg 4–7 for reading, 3–5 for data sets | Admin analytics |

---

## 14. What Not to Build Now

| Idea | Why Not Now |
|---|---|
| Hotspot / click-region questions | Requires stable image support (`funsheep-questions-with-images-and-graphs.md`) |
| Drag-and-drop (visual) for matching/ordering | Enhancement pass; arrow buttons are sufficient for v1 |
| Audio comprehension | No audio ingestion pipeline; separate roadmap needed |
| Peer-graded short-answer comprehension | Moderation risk; out of scope for solo study |
| Group-level timer (timed passage sets, like SAT Reading) | Useful for exam simulation; defer to exam-mode feature |
| Cross-group comparison questions ("In both Passage 1 and Passage 2...") | This is the `dual_passage` stimulus type; build in Phase 4 |
| Teacher-authored comprehension sets | Teacher content pipeline is separate; defer to teacher credit system roadmap |

---

## 15. Related Roadmap Documents

| Document | Relationship |
|---|---|
| `funsheep-essay-tests.md` | DBQ and Synthesis essay questions are essays **inside a QuestionGroup** with `stimulus_type: :primary_sources` or `:synthesis_sources`. Phase 4 here integrates with the essay grader. |
| `funsheep-scored-freeform-grading.md` | Comprehension short-answer questions use `ScoredFreeformGrader`; the grader must be extended to accept passage context as a parameter. |
| `funsheep-questions-with-images-and-graphs.md` | `data_set` stimulus type requires image rendering. Images ROADMAP must be stable before data-interpretation groups can work end-to-end. |
| `funsheep-readiness-by-topic.md` | Comprehension questions still carry `section_id` and feed readiness normally; no change needed. |
| `funsheep-custom-fixed-question-tests.md` | Fixed tests can include full comprehension groups. The test builder must select groups atomically (not individual questions from a group). |
| `funsheep-premium-courses-and-tests.md` | SAT Reading, LSAT, MCAT, and TOEFL are flagship premium courses. They cannot launch without comprehension group support. |

---

## 16. Implementation Notes for Claude Sessions

### What Exists (Do Not Rebuild)
- `FunSheep.Questions.Question` schema — extend with new FK and new enum values only; do not alter existing fields
- `FunSheep.Questions.FreeformGrader` — reuse as-is for short-answer comprehension; add a `grade_with_context/3` overload
- `FunSheep.Interactor.Agents` — reuse for AI group generation; register new agent in Interactor before running the worker
- `Oban` workers pattern — follow `lib/fun_sheep/workers/ai_question_generation_worker.ex` as the canonical pattern
- `FunSheep.Progress.Event` PubSub shape — use for streaming group generation progress

### What Needs Building (From Scratch)
- `QuestionGroup` schema, migration, and context functions
- All five new grader modules
- All five new question-type rendering components
- Split-panel `QuestionGroupStimulus` component
- `AiGroupGenerationWorker` + Interactor agent spec
- `QuestionGroupValidationWorker`
- Group progress and summary components
- Admin group management UI in `question_bank_live.ex`

### Mandatory Rules (From CLAUDE.md)
- **No fake content**: Passage content must come from real AI generation, real uploaded materials, or curated sources. No hardcoded lorem ipsum passages in migrations or seeds.
- **No fake content**: Answer keys for comprehension questions must be generated by a real AI run or manually entered by a teacher/admin. Never hardcode answer keys in code.
- **Progress feedback**: Group generation is long-running (multiple questions + passage). Must emit `FunSheep.Progress.Event` updates during generation per the mandatory progress rule.
- **Playwright testing**: Split-panel comprehension UI, multi-select checkboxes, cloze blanks, and matching/ordering UIs must all be Playwright-tested before marking complete.
- **Mix format**: Run `mix format` before committing.
- **Test coverage**: >80% on all new modules. Group scheduling patch in `assessment_live.ex` is critical path — 100% coverage required on the scheduling branch.
