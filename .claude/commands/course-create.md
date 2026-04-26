# /course-create — Course Builder

Creates all DB records for a course at runtime — no code changes needed.

Supports two course types:
- **Premium catalog course** — standardized test prep (SAT, ACT, AP, GRE, etc.) with pricing, exam simulation, and score predictor
- **School course** — regular subject course (Algebra 2, AP Biology for a school, etc.), free and school-linked

## Usage

```
/course-create ACT
/course-create "GRE Verbal"
/course-create "Algebra 2"
/course-create "AP Biology"

# With a textbook reference (Amazon URL or direct PDF link)
/course-create SAT https://www.amazon.com/Official-SAT-Study-Guide-2020/dp/1457312190
/course-create "AP Biology" https://example.com/campbell-biology.pdf
```

Textbook URLs are optional. When provided, the course is linked to the textbook so question generation can draw from its content (PDF) or its metadata improves web discovery queries (Amazon).

---

## Step-by-step Instructions

### Step 1 — Parse arguments from `$ARGUMENTS`

Split on whitespace. The first token(s) form the test name; any token starting with `http` is a textbook URL.

- Test name: everything before the URL (e.g. `"SAT"`, `"GRE Verbal"`)
- Textbook URL: optional, one of:
  - **Amazon URL** — `amazon.com/...` — for book metadata (title, ISBN, author)
  - **Direct PDF URL** — ending in `.pdf` or clearly a file — for full-content OCR

If a textbook URL is provided, proceed to **Step 1a** before continuing to Step 2.

### Step 1a — Resolve textbook URL (only when a URL was provided)

**Amazon URL:**
1. Use WebFetch to load the Amazon product page
2. Extract from the HTML:
   - Book title from `<span id="productTitle">` or the `<title>` tag
   - ISBN-13 from the product details section (look for "ISBN-13" label)
   - Author from `#bylineInfo .author`
3. Search OpenLibrary with: `TextbookSearch.search_openlibrary(subject, title)` pattern:
   - Use WebFetch on `https://openlibrary.org/search.json?q=<title>&limit=3&lang=en`
   - Match by ISBN if available, otherwise take the first result
   - Extract: `openlibrary_key`, `isbn`, `author`, `publisher`
4. Build the `textbook` object for the spec:
   ```json
   {
     "amazon_url": "https://www.amazon.com/...",
     "title": "The Official SAT Study Guide 2020",
     "author": "College Board",
     "isbn": "1457312190",
     "openlibrary_key": "/works/OL..."
   }
   ```

**Direct PDF URL:**
1. No pre-fetching needed — the CourseBuilder will download and OCR it at creation time
2. Build the `textbook` object for the spec:
   ```json
   {
     "pdf_url": "https://example.com/sat-guide.pdf",
     "title": "Official SAT Study Guide"
   }
   ```
   The title is optional but helpful for logging. Infer it from the URL filename if not provided.

**If URL resolution fails** (page unreachable, no ISBN found):
- Continue without a textbook — log a warning but do not abort course creation
- Omit the `textbook` key from the spec entirely

### Step 1.5 — Ask course type

**Before doing anything else, ask the user:**

> Is **"[course name]"** a **premium catalog course** (standardized test prep with pricing and exam simulation) or a **regular school course** (free, linked to a school)?

Wait for their answer before continuing.

- If **premium** → continue to Step 2 (existing flow below).
- If **school course** → jump to the **School Course Path** section at the bottom of this file.

---

## Premium Course Path

### Step 2 — Check for an existing embedded profile

Check the **Known Test Profiles** section at the bottom of this file.

- If a profile for the requested test name exists there, use those COURSE_SPEC JSON objects directly — skip to Step 5.
- If no profile exists, proceed to Step 3 to research the test and Step 4 to build the spec.

> Note: If a textbook URL was provided (Step 1a), inject the resolved `textbook` object into each spec before running (it is omitted from the embedded profiles).

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

**Textbook field (optional):** Include when the user provided a URL. Use one of these two shapes:

```json
// Amazon URL — resolved to OpenLibrary metadata, linked as course.textbook_id
"textbook": {
  "amazon_url": "https://www.amazon.com/Official-SAT-Study-Guide-2020/dp/1457312190",
  "title": "The Official SAT Study Guide 2020",
  "author": "College Board",
  "isbn": "1457312190",
  "openlibrary_key": "/works/OL12345M"
}

// Direct PDF — downloaded and queued for OCR, questions generated from actual content
"textbook": {
  "pdf_url": "https://example.com/sat-prep-book.pdf",
  "title": "Official SAT Study Guide"
}
```

If URL resolution failed (Amazon blocked, PDF unreachable), omit the `textbook` key entirely — never include a broken URL.

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

## School Course Path

Used when the user answers "school course" at Step 1.5. No pricing, no exam simulation, no score predictor.

### School Step 1 — Collect course details

Ask the user for the following. Collect them all in one question if possible:

> To create "**[course name]**" as a school course I need a few details:
> 1. **Grade** — what grade level? (e.g. 9, 10, 11, 12, College)
> 2. **School** — which school is this for? (name, or "any" if not school-specific)
> 3. **Subject** — one-line descriptor (e.g. Mathematics, English, Biology)
> 4. **Description** — one sentence describing the course (or skip for a default)

Wait for their answers before continuing.

### School Step 2 — Resolve school (if named)

If the user named a specific school, look it up:

```bash
cd /home/pulzze/Documents/GitHub/personal/funsheep-builder && ~/.asdf/shims/mix funsheep.school.find --name '<school name>'
```

This returns a `school_id` UUID if found, or an empty result if not. If no match, proceed without a school_id (the course will be visible across all schools).

### School Step 3 — Build the SCHOOL_COURSE_SPEC JSON

```json
{
  "course_type": "school",
  "name": "Algebra 2",
  "subject": "Mathematics",
  "grade": "10",
  "description": "Second-year algebra covering polynomial functions, rational expressions, exponential and logarithmic functions, sequences, and an introduction to statistics.",
  "school_id": "uuid-or-null",
  "chapters": [
    {
      "name": "Polynomial Functions",
      "sections": [
        "Factoring Polynomials",
        "End Behavior and Zeros",
        "Polynomial Long Division"
      ]
    }
  ]
}
```

**Rules:**
- `course_type` must be `"school"` — this tells the Mix task to skip premium fields
- `school_id`: UUID string if resolved, `null` if not school-specific
- `grade`: string — `"9"`, `"10"`, `"11"`, `"12"`, or `"College"`
- `subject`: concise lowercase descriptor matching the subject area
- `chapters`: 4–8 chapters based on the standard curriculum for this course/grade
- Each chapter should have 4–7 sections — specific skills or units, not vague categories
- If you're not certain of the curriculum, use WebSearch: `"<course name> <grade> curriculum outline common core"`

### School Step 4 — Run the Mix task

```bash
cd /home/pulzze/Documents/GitHub/personal/funsheep-builder && ~/.asdf/shims/mix funsheep.course.create --spec '<JSON>'
```

Same command as the premium path. The `"course_type": "school"` field in the spec tells the task to create a public, unpriced course.

### School Step 5 — Report results

```
## Course Created: Algebra 2

- Course ID: <uuid>
- Grade: 10
- School: Saratoga High School (or "all schools")
- Chapters: 6 (Polynomial Functions, Rational Expressions, ...)
- Total Sections: 28
- Access: Public (free)
- Status: pending

### Next steps
1. Review at http://localhost:4000/admin/courses/<id>
2. Click "Generate Questions" to start AI question generation
3. Review generated questions, then publish
```

---

## Known Test Profiles

The following profiles are fully researched and ready to use. When a test below is requested, **use these specs directly — skip Steps 3 and 4.** Do not re-research a test that already has a profile.

Specs are shown pretty-printed for readability. Compact to a single line before passing to the Mix task (remove all newlines and extra spaces inside the JSON string).

If a textbook URL was provided by the user, inject the `textbook` object (resolved in Step 1a) into each spec before running.

---

### SAT (Digital SAT 2024+)

Two courses: **SAT Math** and **SAT Reading & Writing**. Run Math first, then RW with the bundle appended.

The Digital SAT is adaptive (multistage): two modules per section, with Module 2 difficulty calibrated to Module 1 performance. All MCQ use 4 answer choices (A–D). Some Math questions are student-produced response (no answer choices).

**Score range:** 200–800 per section, 400–1600 composite.

#### Course 1 — SAT Math

```json
{
  "name": "SAT Math",
  "test_type": "sat",
  "subject": "mathematics",
  "grades": ["10", "11", "12", "College"],
  "description": "Complete Digital SAT Math preparation covering all four content domains. Adaptive practice identifies and targets your weak areas across Algebra, Advanced Math, Problem-Solving, and Geometry.",
  "price_cents": 2900,
  "currency": "usd",
  "chapters": [
    {
      "name": "Algebra",
      "sections": [
        "Linear Equations in One Variable",
        "Linear Equations in Two Variables",
        "Linear Functions and Graphs",
        "Systems of Two Linear Equations",
        "Linear Inequalities",
        "Word Problems: Setting Up Equations"
      ]
    },
    {
      "name": "Advanced Math",
      "sections": [
        "Quadratic Equations — Factoring",
        "Quadratic Equations — Completing the Square",
        "Quadratic Equations — Quadratic Formula",
        "Quadratic Functions — Vertex and Axis of Symmetry",
        "Polynomial Functions",
        "Exponential Functions and Growth",
        "Function Notation and Composition",
        "Radical and Absolute Value Functions"
      ]
    },
    {
      "name": "Problem-Solving & Data Analysis",
      "sections": [
        "Ratios, Rates, and Proportions",
        "Percentages",
        "Unit Conversion",
        "Statistics — Central Tendency",
        "Statistics — Spread and Distribution",
        "Two-Way Tables",
        "Probability",
        "Data Interpretation — Graphs and Charts"
      ]
    },
    {
      "name": "Geometry & Trigonometry",
      "sections": [
        "Lines and Angles",
        "Triangle Properties",
        "Area and Perimeter",
        "Circles — Arc, Sector, Central Angle",
        "Volume",
        "Pythagorean Theorem",
        "Right Triangle Trigonometry",
        "Unit Circle and Special Angles"
      ]
    }
  ],
  "exam_simulation": {
    "time_limit_minutes": 70,
    "sections": [
      {
        "name": "Module 1",
        "question_type": "multiple_choice",
        "count": 22,
        "time_limit_minutes": 35
      },
      {
        "name": "Module 2",
        "question_type": "multiple_choice",
        "count": 22,
        "time_limit_minutes": 35
      }
    ]
  },
  "score_predictor_weights": {
    "algebra": 0.35,
    "advanced_math": 0.35,
    "problem_solving_data_analysis": 0.15,
    "geometry_trigonometry": 0.15
  },
  "generation_config": {
    "prompt_context": "Digital SAT Math — adaptive multistage exam, 44 questions across two 22-question modules (35 min each), 70 minutes total, calculator permitted throughout. Questions cover Algebra (35%), Advanced Math (35%), Problem-Solving and Data Analysis (15%), and Geometry and Trigonometry (15%). Most questions are 4-option multiple choice (A–D); approximately 20% are student-produced response with no answer choices.",
    "validation_rules": {
      "mcq_option_count": 4,
      "answer_labels": ["A", "B", "C", "D"]
    }
  }
}
```

#### Course 2 — SAT Reading & Writing (with bundle)

```json
{
  "name": "SAT Reading & Writing",
  "test_type": "sat",
  "subject": "english_language",
  "grades": ["10", "11", "12", "College"],
  "description": "Complete Digital SAT Reading & Writing preparation covering all four content domains. Adaptive practice sharpens comprehension, rhetoric, and grammar across short, focused passages.",
  "price_cents": 2900,
  "currency": "usd",
  "chapters": [
    {
      "name": "Craft & Structure",
      "sections": [
        "Words in Context — Meaning",
        "Words in Context — Tone and Connotation",
        "Text Structure and Purpose",
        "Cross-Text Connections"
      ]
    },
    {
      "name": "Information & Ideas",
      "sections": [
        "Central Idea and Details",
        "Evidence — Textual Support",
        "Evidence — Graphic and Data Integration",
        "Inferences"
      ]
    },
    {
      "name": "Expression of Ideas",
      "sections": [
        "Rhetorical Goals and Purpose",
        "Transitions",
        "Parallel Structure and Style"
      ]
    },
    {
      "name": "Standard English Conventions",
      "sections": [
        "Punctuation — Commas",
        "Punctuation — Semicolons and Colons",
        "Punctuation — Dashes and Parentheses",
        "Subject-Verb Agreement",
        "Pronoun-Antecedent Agreement",
        "Pronoun Case",
        "Verb Tense and Consistency",
        "Modifier Placement",
        "Run-Ons, Fragments, and Sentence Boundaries"
      ]
    }
  ],
  "exam_simulation": {
    "time_limit_minutes": 64,
    "sections": [
      {
        "name": "Module 1",
        "question_type": "multiple_choice",
        "count": 27,
        "time_limit_minutes": 32
      },
      {
        "name": "Module 2",
        "question_type": "multiple_choice",
        "count": 27,
        "time_limit_minutes": 32
      }
    ]
  },
  "score_predictor_weights": {
    "craft_and_structure": 0.28,
    "information_and_ideas": 0.26,
    "expression_of_ideas": 0.20,
    "standard_english_conventions": 0.26
  },
  "generation_config": {
    "prompt_context": "Digital SAT Reading & Writing — adaptive multistage exam, 54 questions across two 27-question modules (32 min each), 64 minutes total. All questions are 4-option multiple choice (A–D). Each question is paired with a short passage (25–150 words). Content domains: Craft and Structure (28%), Information and Ideas (26%), Expression of Ideas (20%), Standard English Conventions (26%).",
    "validation_rules": {
      "mcq_option_count": 4,
      "answer_labels": ["A", "B", "C", "D"]
    }
  },
  "bundle": {
    "name": "SAT Full Prep Bundle",
    "description": "Complete Digital SAT preparation — Math and Reading & Writing. Adaptive practice across all eight content domains, two full-length exam simulations, and AI-powered explanations. Save vs. buying separately.",
    "price_cents": 4900,
    "currency": "usd",
    "course_names": ["SAT Math", "SAT Reading & Writing"]
  }
}
```

---

### Tests Without Embedded Profiles

Use **Steps 3 and 4** (WebSearch + spec construction) for these tests:

| Test | Courses to Create |
|------|-------------------|
| ACT | ACT Math, ACT English, ACT Reading, ACT Science (+ bundle) |
| GRE | GRE Verbal Reasoning, GRE Quantitative Reasoning (+ bundle) |
| GMAT | GMAT Verbal, GMAT Quantitative, GMAT Integrated Reasoning (+ bundle) |
| LSAT | LSAT Logical Reasoning, LSAT Analytical Reasoning, LSAT Reading Comprehension (+ bundle) |
| MCAT | MCAT Biology/Biochemistry, MCAT C/P, MCAT CARS, MCAT Psych/Soc (+ bundle) |
| AP | Varies by subject — check College Board for current exam format |
| IB | Varies by subject and HL/SL level |
| HSC | Varies by state and subject |

Once researched and validated, add new profiles to this file following the SAT format above.
