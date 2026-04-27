# Playbook: Standardized Test Course

**Purpose:** Reusable guide for building any standardized test prep course on FunSheep (SAT, ACT, HSC, GRE, GMAT, MCAT, LSAT, IB, CLT, Bar Exam, etc.)
**Last updated:** 2026-04-25
**Reflects:** 4 test modes (Assessment, Practice, Quick Test, Exam Simulation)

---

## How to Use This Playbook

1. Read the "How We Build a Test Course" section to understand the repeatable pattern.
2. Find the target test's profile (SAT, ACT, HSC, GRE, etc.) or fill in the blank profile template.
3. Follow the 5 implementation phases in order.
4. The SAT section below is the fully worked example — all other tests follow the same shape.

---

## The 4 Test Modes

FunSheep has four distinct modes. Each is always available on every course — but only **Exam Simulation** requires test-specific configuration per playbook. The other three work automatically from any course with properly tagged questions.

| Mode | Engine | What It Is | Config Needed Per Test |
|------|--------|-----------|----------------------|
| **Assessment** | `Assessments.Engine` | Adaptive topic-by-topic session. Adjusts difficulty per answer. Advances when a topic is mastered or exhausted. Core diagnostic tool. | None — works from `section_id` tags on questions |
| **Practice** | `Assessments.PracticeEngine` | Weak-skill focused. Weights question selection by per-skill deficit. Interleaves 35% mastered skills for spaced retention. Re-ranks after every answer. | None — works from attempt history |
| **Quick Test** | `Assessments.QuickTestEngine` | Tinder-style card flipping. Four actions per card: "I Know This", "I Don't Know", Answer (graded), Skip. Great for quick warm-up or vocabulary drilling. | None |
| **Exam Simulation** | `Assessments.ExamSimulationEngine` | Full timed exam. Questions fixed at session start. Zero per-answer feedback. Auto-submits via `ExamTimeoutWorker` if session dies. Full pacing debrief on submit. | **Yes — `TestFormatTemplate` must be seeded per test** |

### Exam Simulation — Why It Needs Configuration

`ExamSimulationEngine` uses a `TestFormatTemplate` (stored as a JSONB `structure` map) to determine:
- How many sections the exam has
- How many questions per section
- What question types per section
- The total time limit

Without a seeded template, the engine falls back to `@default_question_count 40` and `@default_time_limit_seconds 2700` — a generic exam that bears no resemblance to the real test. **Always seed a `TestFormatTemplate` for standardized test courses.**

### Exam Simulation Format Template Shape

```elixir
%{
  "time_limit_minutes" => 134,        # total exam time in minutes
  "sections" => [
    %{
      "name" => "Reading & Writing — Module 1",
      "question_type" => "multiple_choice",
      "count" => 27,
      "time_limit_minutes" => 32,
      "chapter_ids" => []             # [] = all chapters; or restrict to specific chapters
    },
    # ... one entry per section/module
  ]
}
```

---

## How We Build a Test Course (The Pattern)

```
1. RESEARCH THE TEST
   - Sections, time limits, question counts per section
   - Domain/skill taxonomy → becomes Chapter → Section tree
   - Scoring system → calibrate ScorePredictor domain weights
   - Adaptive vs. linear → affects difficulty distribution targets
   - Special question types (essay, data interpretation, numeric entry, etc.)

2. DEFINE THE CONTENT TREE
   - Course → Chapter (one per domain) → Section (one per specific skill)
   - Minimum questions per Section: 20 easy / 30 medium / 20 hard = 70 total

3. SEED THE COURSE STRUCTURE
   - Use priv/repo/seeds/sat_courses.exs as the base pattern
   - catalog_test_type must be set (add to enum if new)
   - is_premium_catalog: true, processing_status: :pending
   - price_cents set per course, bundle record if applicable

4. QUESTION SOURCING (priority order)
   a. WebContentDiscoveryWorker — web-scraped real questions first
   b. AIQuestionGenerationWorker — fills sections below minimum threshold
   Both go through QuestionValidationWorker before becoming visible.
   NEVER publish unvalidated or fake questions.

5. SCORE PREDICTOR
   - Domain weights from official score report breakdown
   - Same FunSheep.ScorePredictor pattern, new weight map per test

6. PRICING
   - price_cents per course (admin-editable)
   - CourseBundle record for multi-course bundles
```

---

## FunSheep Architecture Primitives (What Already Exists)

| Need | Field / Module |
|------|---------------|
| Test type tagging | `Course.catalog_test_type` — enum includes: sat, act, ap, ib, hsc, clt, lsat, bar, gmat, mcat, gre |
| Domain → Skill hierarchy | `Chapter` = Domain, `Section` = Skill |
| Passage-based questions | `QuestionGroup.stimulus_type: :reading_passage` |
| Multiple choice | `Question.question_type: :multiple_choice` |
| Numeric free-entry | `Question.question_type: :numeric` |
| Difficulty levels | `easy` / `medium` / `hard` on Question |
| Paid access gating | `CourseEnrollment.access_type: "alacarte"` or `"subscription"` |
| Access tier | `Course.access_level: "premium"` |
| Admin CRUD | `admin_courses_live.ex` + `admin_question_review_live.ex` |
| Adaptive practice engine | Section-level mastery, North Star I-1 through I-16 |
| Free preview | `Course.sample_question_count` (default 10) |

**New work needed for any test course (one-time, already planned for SAT):**
- `price_cents`, `currency`, `price_label` on `Course` table
- `course_bundles` table
- Admin price editor + chapter/section CRUD + manual question creation
- Score Predictor module per test

---

## Blank Test Profile Template

Fill this in before implementing a new test:

```
TEST_NAME:
CATALOG_TEST_TYPE:          # must match Course.catalog_test_type enum
SECTIONS:
  - name:
    time_limit_minutes:
    question_count:
    question_types:         # multiple_choice | numeric | essay | etc.
    domains:
      - name:
        weight_pct:
        skills:
          - name:           # becomes a Section
SCORING:
  total_range:
  section_ranges:
  domain_weights:           # used in ScorePredictor
ADAPTIVE:                   # yes/no, describe mechanism
CALCULATOR:                 # always | math_only | never
SPECIAL_NOTES:              # anything unique vs. SAT
PRICE_CENTS_DEFAULT:
BUNDLE:                     # name, courses included, price_cents
MIN_QUESTIONS_PER_SECTION:  # default: 70 (20 easy / 30 medium / 20 hard)

# Exam Simulation — TestFormatTemplate (REQUIRED)
EXAM_SIMULATION_TEMPLATE:
  time_limit_minutes:       # total exam time
  sections:
    - name:                 # e.g. "Section 1 — Module 1"
      question_type:        # multiple_choice | numeric | mixed
      count:                # number of questions
      time_limit_minutes:   # per-section time limit
      chapter_ids: []       # [] = all chapters in course

# Test Modes — notes (Assessment/Practice/Quick Test need no config)
TEST_MODE_NOTES:
  assessment:               # any special guidance for adaptive diagnostics
  practice:                 # any special guidance for weak-skill practice
  quick_test:               # any special guidance for card-flip sessions
  exam_simulation:          # link to EXAM_SIMULATION_TEMPLATE above
```

---

## Implementation Phases (Apply to Every Test)

### Phase 1 — Foundation (2–3 days)
- Migration: add pricing fields to `courses` if not present
- Migration: `course_bundles` table if not present
- Seed script: create course(s), chapters, sections
- **Seed `TestFormatTemplate`** for Exam Simulation (see test profile for structure)
- Admin: price editor, chapter/section CRUD, manual question creation
- Access gate: paywall in course detail LiveView

### Phase 2 — Question Sourcing (3–5 days)
- `WebContentDiscoveryWorker` — test-specific search queries per Section
- `QuestionValidationWorker` — test-specific validation rules
- `AIQuestionGenerationWorker` — gap-fill where web scraping falls short
- Enforce minimum coverage before marking course `:ready`

### Phase 3 — Purchase Flow (2–3 days)
- Catalog: course visible with price badge
- Paywall component with single + bundle pricing options
- Stripe checkout → webhook → `CourseEnrollment` creation
- Subscription auto-enroll for qualifying plan tiers
- Preview: `sample_question_count` free questions visible to all

### Phase 4 — Score Predictor (1–2 days)
- `FunSheep.<TestName>.ScorePredictor` module with domain weights
- Domain readiness heatmap (green/yellow/red)
- "Predicted Score" widget (shown after ≥10 questions per domain)
- Study plan CTA surfacing 2 weakest domains

### Phase 5 — Admin Dashboard (1 day)
- Enrollment count, avg predicted score, completion rate
- Domain coverage heatmap (questions per section × difficulty)
- Flag under-covered sections, trigger re-generation

---

## SAT — Fully Worked Example

### Product Decisions
| Decision | Choice |
|----------|--------|
| Pricing | $29/course, $49 bundle (Math + RW) |
| Packaging | Two separate courses: SAT Math + SAT Reading & Writing |
| Question sourcing | Web-scraped first → AI gap-fill; both post-validation |
| Admin control | Full CRUD over courses, chapters, sections, questions |

### Test Structure (Digital SAT, 2024+)

| Attribute | Detail |
|-----------|--------|
| Total time | 2 hr 14 min + 10-min break |
| Total questions | 98 |
| Format | Digital, multistage adaptive |
| Scoring | 400–1600 total; 200–800 per section |
| Calculator | Always available (built-in Desmos) |
| Negative marking | None |

**Adaptive mechanism:** Module 1 (same for all) → Hard Module 2 (score ceiling 800) or Easy Module 2 (ceiling ~550) based on Module 1 performance.

#### Reading & Writing (54Q | 64 min)
| Domain | % | ~Q | Key Skills |
|--------|---|----|-----------|
| Craft & Structure | 28% | 13–15 | Words in Context, Text Structure, Cross-Text Connections |
| Information & Ideas | 26% | 12–14 | Central idea, Evidence, Inferences |
| Expression of Ideas | 20% | ~11 | Rhetorical purpose, Transitions, Parallel structure |
| Standard English Conventions | 26% | 11–15 | Punctuation, Subject-verb, Pronoun, Verb tense, Modifiers, Run-ons |

#### Math (44Q | 70 min)
| Domain | % | ~Q | Key Skills |
|--------|---|----|-----------|
| Algebra | 35% | ~15 | Linear equations/functions/inequalities, systems |
| Advanced Math | 35% | ~15 | Quadratics, polynomials, exponentials, function notation |
| Problem-Solving & Data Analysis | 15% | ~7 | Ratios, %, statistics, probability, graphs |
| Geometry & Trigonometry | 15% | ~7 | Area/volume, Pythagorean theorem, right triangle trig, circles |

Geometry formulas on reference sheet. Trig formulas NOT provided.

#### Score Percentiles
| Score | Percentile |
|-------|-----------|
| 1050 | 50th — national average |
| 1300 | 86th |
| 1400 | 94th — very competitive |
| 1500 | 98th — Ivy League range |

### Content Tree

```
SAT Math (price_cents: 2900)
├── Algebra
│   ├── Linear Equations in One Variable
│   ├── Linear Equations in Two Variables
│   ├── Linear Functions and Graphs
│   ├── Systems of Two Linear Equations
│   ├── Linear Inequalities
│   └── Word Problems: Setting Up Equations
├── Advanced Math
│   ├── Quadratic Equations — Factoring
│   ├── Quadratic Equations — Completing the Square
│   ├── Quadratic Equations — Quadratic Formula
│   ├── Quadratic Functions — Vertex and Axis of Symmetry
│   ├── Polynomial Functions
│   ├── Exponential Functions and Growth
│   ├── Function Notation and Composition
│   └── Radical and Absolute Value Functions
├── Problem-Solving & Data Analysis
│   ├── Ratios, Rates, and Proportions
│   ├── Percentages
│   ├── Unit Conversion
│   ├── Statistics — Central Tendency
│   ├── Statistics — Spread and Distribution
│   ├── Two-Way Tables
│   ├── Probability
│   └── Data Interpretation — Graphs and Charts
└── Geometry & Trigonometry
    ├── Lines and Angles
    ├── Triangle Properties
    ├── Area and Perimeter
    ├── Circles — Arc, Sector, Central Angle
    ├── Volume
    ├── Pythagorean Theorem
    ├── Right Triangle Trigonometry
    └── Unit Circle and Special Angles

SAT Reading & Writing (price_cents: 2900)
├── Craft & Structure
│   ├── Words in Context — Meaning
│   ├── Words in Context — Tone and Connotation
│   ├── Text Structure and Purpose
│   └── Cross-Text Connections
├── Information & Ideas
│   ├── Central Idea and Details
│   ├── Evidence — Textual Support
│   ├── Evidence — Graphic and Data Integration
│   └── Inferences
├── Expression of Ideas
│   ├── Rhetorical Goals and Purpose
│   ├── Transitions
│   └── Parallel Structure and Style
└── Standard English Conventions
    ├── Punctuation — Commas
    ├── Punctuation — Semicolons and Colons
    ├── Punctuation — Dashes and Parentheses
    ├── Subject-Verb Agreement
    ├── Pronoun-Antecedent Agreement
    ├── Pronoun Case
    ├── Verb Tense and Consistency
    ├── Modifier Placement
    └── Run-Ons, Fragments, and Sentence Boundaries

SAT Full Prep Bundle — $49 → enrolls in both courses above
```

### Schema Changes (SAT triggers these; reused by all future tests)

```elixir
# Migration: add_pricing_to_courses
alter table(:courses) do
  add :price_cents, :integer, null: true
  add :currency, :string, default: "usd"
  add :price_label, :string
end

# Migration: create_course_bundles
create table(:course_bundles, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :name, :string, null: false
  add :price_cents, :integer, null: false
  add :currency, :string, default: "usd"
  add :course_ids, {:array, :binary_id}, null: false
  add :is_active, :boolean, default: true
  timestamps()
end
```

### Score Predictor

```elixir
defmodule FunSheep.SAT.ScorePredictor do
  @rw_weights %{
    craft_and_structure: 0.28,
    information_and_ideas: 0.26,
    expression_of_ideas: 0.20,
    standard_english_conventions: 0.26
  }

  @math_weights %{
    algebra: 0.35,
    advanced_math: 0.35,
    problem_solving_data_analysis: 0.15,
    geometry_trigonometry: 0.15
  }

  def predict_section_score(domain_mastery_map, :math),
    do: weighted_mastery(@math_weights, domain_mastery_map)
  def predict_section_score(domain_mastery_map, :reading_writing),
    do: weighted_mastery(@rw_weights, domain_mastery_map)

  defp weighted_mastery(weights, mastery_map) do
    weighted_avg = Enum.reduce(weights, 0.0, fn {domain, weight}, acc ->
      acc + Map.get(mastery_map, domain, 0.0) * weight
    end)
    round(200 + weighted_avg * 600)
  end
end
```

### Test Modes — SAT-Specific Guidance

| Mode | Value for SAT Students | Notes |
|------|----------------------|-------|
| **Assessment** | Identifies which domains are weak before a student wastes time on strong areas. Use early in prep cycle. | No config needed. Works automatically from section-tagged questions. |
| **Practice** | Drill weak domains until mastered. Interleaving keeps already-strong domains fresh. | No config needed. Recommended after first Assessment session. |
| **Quick Test** | Fast daily warm-up. Good for vocabulary (Words in Context) and grammar rules (SEC). | No config needed. 20 cards, ~5 min. |
| **Exam Simulation** | The flagship mode for SAT prep. Full 2h14m timed experience with pacing debrief. Students experience real exam pressure. | **Requires seeded `TestFormatTemplate` — see below.** |

### SAT Exam Simulation — TestFormatTemplate

Seed one `TestFormatTemplate` per SAT course (Math and RW separately). The structure maps exactly to the real Digital SAT module layout.

**SAT Math — `TestFormatTemplate.structure`:**
```elixir
%{
  "name" => "SAT Math — Full Exam",
  "time_limit_minutes" => 70,
  "sections" => [
    %{
      "name" => "Math Module 1",
      "question_type" => "mixed",   # ~75% multiple_choice, ~25% numeric
      "count" => 22,
      "time_limit_minutes" => 35,
      "chapter_ids" => []           # all chapters (Algebra + Adv Math + PS&DA + Geo/Trig)
    },
    %{
      "name" => "Math Module 2",
      "question_type" => "mixed",
      "count" => 22,
      "time_limit_minutes" => 35,
      "chapter_ids" => []
    }
  ]
}
```

**SAT Reading & Writing — `TestFormatTemplate.structure`:**
```elixir
%{
  "name" => "SAT Reading & Writing — Full Exam",
  "time_limit_minutes" => 64,
  "sections" => [
    %{
      "name" => "Reading & Writing Module 1",
      "question_type" => "multiple_choice",
      "count" => 27,
      "time_limit_minutes" => 32,
      "chapter_ids" => []           # all chapters (Craft & Structure, Info & Ideas, etc.)
    },
    %{
      "name" => "Reading & Writing Module 2",
      "question_type" => "multiple_choice",
      "count" => 27,
      "time_limit_minutes" => 32,
      "chapter_ids" => []
    }
  ]
}
```

> **Note on adaptive simulation:** The real SAT routes Module 2 difficulty based on Module 1 score. FunSheep's `ExamSimulationEngine` currently selects all questions at session start (non-adaptive). A future enhancement can split Module 2 into hard/easy variants and route based on Module 1 result — but this is not in scope for the initial launch.

### Highest-ROI Study Areas
- **Math:** Algebra + Advanced Math = 70% of section — focus here first
- **RW:** Standard English Conventions (most rule-based, most teachable); Words in Context; Transitions

---

## ACT Quick Profile

| | ACT |
|--|-----|
| Sections | English (75Q/45min), Math (60Q/60min), Reading (40Q/35min), Science (40Q/35min) |
| Score | 1–36 composite |
| Adaptive | No — linear |
| Calculator | Math section only |
| Unique | Science section (interpreting experiments/data) — no SAT equivalent |
| catalog_test_type | `"act"` |
| Suggested packaging | 4 separate courses or 2 bundles: ACT Math+Science / ACT English+Reading |

---

## HSC Quick Profile (NSW, Australia)

| | HSC |
|--|-----|
| Subjects | ~50 (Maths Advanced, Maths Ext 1/2, English Advanced/Standard, Biology, Chemistry, Physics, Modern History, etc.) |
| Score | ATAR 0–99.95 (derived from HSC marks) |
| Adaptive | No |
| Unique | One course per subject — not a single "HSC" course |
| catalog_test_type | `"hsc"` |
| catalog_subject | `"mathematics_advanced"`, `"biology"`, `"english_advanced"`, etc. |

---

## GRE Quick Profile

| | GRE |
|--|-----|
| Sections | Verbal Reasoning (2×20Q/30min), Quantitative Reasoning (2×20Q/35min), Analytical Writing (2 essays) |
| Score | 130–170 per section; 0–6 AW |
| Adaptive | Section-level adaptive |
| Special types | Text Completion, Sentence Equivalence, Quantitative Comparison |
| catalog_test_type | `"gre"` |

---

## Success Metrics (Per Test Launch, 30-day targets)

| Metric | Target |
|--------|--------|
| Enrollments | ≥ 200 |
| Questions per course | ≥ 1,050 (15 sections × 70) |
| Web-scraped question % | ≥ 40% |
| Validation pass rate | ≥ 85% |
| Avg predicted score improvement (10+ sessions) | ≥ +50 points |
| Bundle uptake | ≥ 30% of purchasers |
