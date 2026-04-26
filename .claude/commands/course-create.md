# /course-create — Standardized Test Course Builder

Creates all DB records for a standardized test course at runtime — no code changes needed.

## Usage

```
/course-create ACT
/course-create "GRE Verbal"
/course-create "HSC Mathematics Advanced"
```

---

## Step-by-step Instructions

### Step 1 — Parse the test name from `$ARGUMENTS`

The argument is the test name (e.g. `ACT`, `GRE`, `HSC Mathematics Advanced`).

### Step 2 — Check for an existing playbook profile

Read `docs/playbooks/standardized-test-course.md`.

- If a profile for the given test name exists in that file, skip to Step 4 using the profile data.
- If no profile exists, proceed to Step 3.

### Step 3 — Research the test (only when no profile exists)

Use WebSearch to find the following information about the test:
- Official sections (e.g. Math, English, Reading, Science for ACT)
- Time limits per section and total
- Question counts per section
- Question format (multiple choice, grid-in, essay, etc.)
- Number of answer options per MCQ (4 or 5)
- Adaptive vs. linear delivery
- Scoring scale (e.g. 1–36 composite for ACT, 200–800 per section for SAT)
- Domain/skill breakdown with approximate weights (% of questions per domain)
- Official prep resources (College Board, ACT.org, ETS, etc.)

Use at minimum 2 searches:
1. `"<TestName> official test format sections question count time limits"`
2. `"<TestName> domain breakdown score weights college prep"`

### Step 4 — Build the COURSE_SPEC JSON

Construct one or more `COURSE_SPEC` objects (one per section of the test, e.g. ACT Math and ACT English are separate courses).

**COURSE_SPEC format:**

```json
{
  "name": "ACT Math",
  "test_type": "act",
  "subject": "mathematics",
  "grades": ["10", "11", "12", "College"],
  "description": "Complete ACT Math preparation covering all six content domains. Adaptive practice targets your weak areas.",
  "price_cents": 2900,
  "currency": "usd",
  "chapters": [
    {
      "name": "Pre-Algebra",
      "sections": ["Number Theory", "Fractions and Decimals", "Ratios and Proportions"]
    }
  ],
  "exam_simulation": {
    "time_limit_minutes": 60,
    "sections": [
      {
        "name": "Math",
        "question_type": "multiple_choice",
        "count": 60,
        "time_limit_minutes": 60
      }
    ]
  },
  "score_predictor_weights": {
    "pre_algebra": 0.23,
    "elementary_algebra": 0.17,
    "intermediate_algebra_coordinate_geometry": 0.17,
    "plane_geometry": 0.23,
    "trigonometry": 0.07,
    "statistics_probability": 0.13
  },
  "generation_config": {
    "prompt_context": "ACT Math — linear exam, 60 multiple-choice questions, 60 minutes, calculator permitted throughout. Questions test Pre-Algebra (23%), Elementary Algebra (17%), Intermediate Algebra/Coordinate Geometry (17%), Plane Geometry (23%), Trigonometry (7%), Statistics & Probability (13%).",
    "validation_rules": {
      "mcq_option_count": 5,
      "answer_labels": ["A", "B", "C", "D", "E"]
    }
  }
}
```

**Rules for building the spec:**
- `test_type` must be lowercase, no spaces (e.g. `"act"`, `"gre"`, `"hsc"`, `"lsat"`)
- `subject` must be one of: `"mathematics"`, `"english_language"`, `"reading"`, `"science"`, `"verbal"`, `"quantitative"`, `"writing"`, or a concise lowercase descriptor
- `grades` is always an array of strings — for most standardized tests use `["10", "11", "12", "College"]`
- `chapters` map directly to domains/content areas of the test
- `sections` within a chapter are the specific skills tested in that domain
- Keep `sections` arrays to 3–8 items per chapter — concrete skill names, not vague categories
- `score_predictor_weights` keys must be lowercase-underscored versions of chapter names (e.g. "Pre-Algebra" → `"pre_algebra"`)
- `score_predictor_weights` values must sum to 1.0
- `generation_config.prompt_context` should be 1–2 sentences: test name, format (adaptive/linear), question count, time limit, and domain distribution
- `generation_config.validation_rules.mcq_option_count`: 4 for most tests, 5 for ACT
- `generation_config.validation_rules.answer_labels`: `["A","B","C","D"]` for 4-option, `["A","B","C","D","E"]` for 5-option

**Bundle:** Only include a `bundle` key on the LAST spec in a multi-course test (when creating all courses together). Example:

```json
{
  "bundle": {
    "name": "ACT Full Prep Bundle",
    "description": "Complete ACT preparation — Math, English, Reading, and Science. Save vs. buying separately.",
    "price_cents": 7900,
    "course_names": ["ACT Math", "ACT English", "ACT Reading", "ACT Science"]
  }
}
```

`course_names` lists ALL courses in the bundle (they must exist in the DB when the bundle is created).

### Step 5 — Run the Mix task

For each spec (one per course), run:

```bash
cd /home/pulzze/Documents/GitHub/personal/funsheep-builder && ~/.asdf/shims/mix funsheep.course.create --spec '<JSON>'
```

Where `<JSON>` is the compact (single-line) JSON spec. Use `Jason.encode!/1` style encoding — no line breaks inside the JSON argument.

If creating multiple courses that share a bundle, run them in order (Math first, then English, etc.) and include the `bundle` key only on the last spec.

### Step 6 — Report results

After all tasks complete, print a summary:

```
## Course Created: ACT Math

- Course ID: <uuid>
- Chapters: 6 (Pre-Algebra, Elementary Algebra, Intermediate Algebra, Coordinate Geometry, Plane Geometry, Trigonometry)
- Total Sections: 24
- Exam Simulation Template: "ACT Math — Full Exam" (60 questions, 60 min)
- Bundle: (none — run again with English, Reading, Science to create bundle)
- Status: pending (questions will be generated after admin triggers processing)

### Next steps
1. Review the course structure at http://localhost:4000/admin/course-builder
2. Click "Generate Questions" to start AI question generation
3. Review generated questions, then click "Publish" to make the course live
```

---

## Known Test Profiles

Check `docs/playbooks/standardized-test-course.md` for pre-researched profiles before using WebSearch.

Currently profiled:
- SAT (see `priv/repo/seeds/sat_courses.exs` for the existing implementation)

Tests needing profiling (use WebSearch if these are requested):
- ACT (Math, English, Reading, Science)
- GRE (Verbal Reasoning, Quantitative Reasoning)
- GMAT (Verbal, Quantitative, Integrated Reasoning)
- LSAT (Logical Reasoning, Analytical Reasoning, Reading Comprehension)
- MCAT (Biology/Biochemistry, C/P, CARS, Psych/Soc)
- AP (varies by subject — check College Board)
- IB (varies by subject and HL/SL)
- HSC (varies by state and subject)
