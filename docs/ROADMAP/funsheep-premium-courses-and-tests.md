# FunSheep — Premium Courses & Standardized Test Prep: Strategy & Roadmap

> **For the Claude session implementing this feature.** Read the entire document before writing a single line of code. The monetization framing, the catalog structure, and the access-control design are all load-bearing. Skipping any section produces a generic paywall with no competitive advantage.

---

## 0. Context & Purpose

FunSheep is an AI-powered study platform built on Phoenix/LiveView/Elixir. Today it helps students with their own uploaded course materials. The next growth lever is **curated, curriculum-aligned content for high-stakes standardized tests** — content that is expensive to prepare, that every motivated student needs, and that parents will pay a premium for.

**The core bet**: a student who opens FunSheep for their own AP Chemistry notes, then discovers a professionally built SAT Math course sitting right there, will stay — and their parents will pay.

This document covers:
1. The standardized test catalog (what to build)
2. The monetization model (how to price and gate)
3. The technical architecture (what needs to change in the codebase)
4. The UI/UX flows (how it looks and feels)
5. The phased rollout plan

---

## 1. The Standardized Test Catalog

### 1.1 Tier 1 — Launch Catalog (High Volume, High Willingness-to-Pay)

These are the tests every parent recognizes by name. Build these first.

#### SAT (Scholastic Assessment Test)
- **Audience**: US high school students (11th–12th grade), 2.2M+ test-takers/year
- **Subjects to cover**:
  - SAT Reading & Writing (Evidence-based)
  - SAT Math (No Calculator + Calculator)
  - SAT Math (Advanced: Algebra, Problem Solving, Data Analysis, Advanced Math)
- **Format**: Digital adaptive test (since 2024 College Board shift to DSAT)
  - 2 sections × 2 modules each
  - Reading/Writing: 54 questions in 64 min
  - Math: 44 questions in 70 min
  - Score range: 400–1600
- **Course structure**:
  - One master "SAT Prep" course with 4 sub-courses (chapters = topic areas)
  - Each chapter = one testable skill cluster (e.g., "Linear equations", "Command of evidence")
  - 500+ questions per subject, question-type tagged (multiple choice, student-produced response)
- **Premium tier**: Paid subscription required (monthly or annual)

#### ACT (American College Testing)
- **Audience**: US high school students, 1.4M+ test-takers/year; dominant in Midwest/South
- **Subjects**:
  - ACT English (grammar, punctuation, style)
  - ACT Math (pre-algebra through trigonometry)
  - ACT Reading (prose fiction, social studies, humanities, natural sciences)
  - ACT Science (data interpretation, research summaries, conflicting viewpoints)
  - ACT Writing (optional essay — separately gated)
- **Format**: 4 scored sections + optional writing; 215 questions total in ~3h 35m
- **Course structure**: One master "ACT Prep" course with 5 sub-courses (English, Math, Reading, Science, Writing)
- **Premium tier**: Paid subscription required

#### AP (Advanced Placement) — College Board
- **Audience**: US high school students in advanced courses; 5.1M+ exams taken per year
- **Scope**: 38 AP subjects — build the top 15 by exam volume first
- **Top 15 by volume** (2023 College Board data):
  1. AP English Language & Composition
  2. AP US History
  3. AP Calculus AB
  4. AP English Literature & Composition
  5. AP US Government & Politics
  6. AP Biology
  7. AP Psychology
  8. AP Statistics
  9. AP World History: Modern
  10. AP Chemistry
  11. AP Environmental Science
  12. AP Human Geography
  13. AP Computer Science Principles
  14. AP Macroeconomics
  15. AP Physics 1
- **Format per exam**: Free-response + multiple-choice sections; 3 hours
- **Course structure**: One course per AP subject; chapters = major curriculum units per College Board Course & Exam Descriptions (CEDs)
- **Access model**: AP courses are individually purchasable **or** included in the Annual subscription (see §2)

#### IB (International Baccalaureate)
- **Audience**: Students in IB Diploma Programme worldwide; ~180k DP candidates/year; growing fast in international schools
- **Key subjects** (HL and SL variants):
  - IB Mathematics: Analysis & Approaches (AA)
  - IB Mathematics: Applications & Interpretation (AI)
  - IB Biology, Chemistry, Physics
  - IB History, Economics, Business Management
  - IB English A: Literature
- **Format**: Internal Assessments (IAs) + external exams with paper-1/paper-2/paper-3 structure
- **Course structure**: One course per IB subject+level combo (e.g., "IB Biology HL", "IB Math AA SL")
- **Premium tier**: Annual subscription or individual IB bundle purchase

---

### 1.2 Tier 2 — Secondary Catalog (Regional High-Value Markets)

#### HSC (Higher School Certificate — Australia/NSW)
- **Audience**: ~80k NSW students per year; also used in ACT/Tasmania
- **Key subjects**:
  - HSC Mathematics Advanced
  - HSC Mathematics Extension 1 & 2
  - HSC English Standard & Advanced
  - HSC Chemistry, Biology, Physics
  - HSC Modern History, Ancient History, Economics, Business Studies
  - HSC Legal Studies, Software Design & Development
- **Format**: 3-hour exams; multiple choice + extended response
- **Course structure**: One course per HSC subject; chapters = HSC syllabus dot-points (the actual prescriptions, numbered)
- **Access model**: Annual subscription; strong price sensitivity — consider a lower-cost "HSC tier"

#### CLT (Classic Learning Test)
- **Audience**: Classical/Christian school students in the US; growing 20–30% per year; 50k+ test-takers
- **Subjects**:
  - CLT Verbal Reasoning (grammar, vocabulary in context, reading)
  - CLT Quantitative Reasoning (arithmetic through pre-calculus)
  - CLT Essay
- **Format**: 3 sections; 120 questions + essay; 2h 30m
- **Course structure**: One master "CLT Prep" course; chapters = CLT skill domains
- **Audience note**: Classical school families skew high-income + high-intent → strong premium candidates
- **Premium tier**: Paid subscription required

#### PSAT/NMSQT & PSAT 8/9
- **Audience**: US 8th–11th graders (practice for SAT; NMSQT qualifies for National Merit Scholarship)
- **Same structure as SAT** but lower ceiling score (1520 max)
- **Build as**: Subset of SAT Prep course with PSAT-specific difficulty calibration + National Merit context

---

### 1.3 Tier 3 — Professional & Graduate-Level Tests (Premium-Premium Tier)

These command the highest individual willingness-to-pay. Adults, not students. Different conversion psychology.

#### LSAT (Law School Admission Test)
- **Audience**: Law school applicants in the US/Canada; ~170k test-takers/year
- **Sections**:
  - Logical Reasoning (now 2 sections → 1 section in 2024 digital format)
  - Analytical Reasoning (Logic Games)
  - Reading Comprehension
- **Format**: 4 scored sections + writing sample; unscored experimental section; score 120–180
- **Course structure**: 4 sub-courses; chapters = question type families (conditional reasoning, parallel reasoning, grouping games, etc.)
- **Price point**: Adults pay significantly more — consider standalone pricing ($49–$99/month for professional tier)

#### Bar Exam (MBE + State Components)
- **Audience**: Law school graduates; 65k+ examinees/year
- **Components**:
  - MBE (Multistate Bar Examination): 200 MCQs across 7 subjects
    - Civil Procedure, Constitutional Law, Contracts, Criminal Law & Procedure, Evidence, Real Property, Torts
  - MEE (Multistate Essay Examination): 6 essay prompts
  - MPT (Multistate Performance Test): legal document drafting
- **State-specific**: Each state has additional components; California and New York are the largest markets
- **Course structure**: MBE as primary course; MEE/MPT as add-on sub-courses; state-specific supplements
- **Price point**: Bar prep is a $500–$3,000 market (Themis, Barbri, Kaplan). FunSheep can undercut dramatically with AI at $99/month

#### GMAT (Graduate Management Admission Test)
- **Audience**: MBA applicants; ~200k test-takers/year
- **Sections** (2024 GMAT Focus Edition):
  - Quantitative Reasoning (23 questions, 45 min)
  - Verbal Reasoning (23 questions, 45 min)
  - Data Insights (20 questions, 45 min)
- **Score range**: 205–805
- **Course structure**: 3 sub-courses; chapters = question type families

#### MCAT (Medical College Admission Test)
- **Audience**: Pre-med students; ~125k test-takers/year
- **Sections**:
  - Biological & Biochemical Foundations of Living Systems (59 questions)
  - Chemical & Physical Foundations of Biological Systems (59 questions)
  - Psychological, Social, & Biological Foundations of Behavior (59 questions)
  - Critical Analysis & Reasoning Skills (53 questions)
- **Total**: 230 questions, 7.5 hours
- **Depth requirement**: Extremely high — biochemistry, organic chemistry, physics, psychology, sociology all in one exam
- **Course structure**: 4 sub-courses; this is the most content-intensive offering on the catalog
- **Price point**: Kaplan MCAT prep runs $449–$2,499. FunSheep at $99–$199/month is compelling

#### GRE (Graduate Record Examination — ETS)
- **Audience**: Graduate school applicants; ~700k test-takers/year (largest graduate test)
- **Sections**:
  - Analytical Writing (2 essays)
  - Verbal Reasoning (2 sections × 20 questions)
  - Quantitative Reasoning (2 sections × 20 questions)
- **Course structure**: 3 sub-courses; strong overlap with GMAT verbal — share question bank where applicable

---

### 1.4 Tier 4 — International Growth Markets

| Test | Market | Notes |
|---|---|---|
| **A-Levels** (UK/CIE) | UK, HK, Singapore, Malaysia, Africa | Art-to-Zoology subject spread; exam board variants (OCR, Edexcel, CIE) |
| **GCSE** | UK Year 10–11 | Precursor to A-Levels; Math/English/Sciences most critical |
| **Gaokao prep** | China (diaspora, international) | Political sensitivity; focus on math/sciences for diaspora market |
| **JEE / NEET** | India | JEE: engineering entrance; NEET: medical entrance; massive market |
| **DSE** | Hong Kong | Post-secondary entrance; math + sciences |
| **VCE** | Victoria, Australia | Similar to HSC; separate syllabus |
| **IELTS / TOEFL** | Global ESL | English proficiency; massive total addressable market |

---

## 2. Monetization Model

### 2.1 Subscription Tiers (Extending the Existing Model)

The existing model has:
- **Free**: 50 lifetime tests + 20/week
- **Monthly**: $30/month — unlimited tests on own courses
- **Annual**: $90/year — unlimited tests on own courses

**Extend to:**

| Plan | Price | What's Included |
|---|---|---|
| **Free** | $0 | Own-course practice (50 lifetime + 20/week cap). Browse premium catalog; view syllabus only. |
| **Standard Monthly** | $30/month | Unlimited tests on **own courses** + access to **any 1 premium test catalog** (user picks) |
| **Standard Annual** | $90/year | Unlimited tests on own courses + access to **any 3 premium test catalogs** |
| **Premium Monthly** | $59/month | Unlimited own courses + **full premium catalog access** (SAT, ACT, all AP, IB, HSC, CLT) |
| **Premium Annual** | $149/year | Same as Premium Monthly + professional tier tests (LSAT, GMAT, GRE, Bar Exam, MCAT) |
| **Professional Monthly** | $99/month | Adults preparing for professional exams (LSAT, Bar, GMAT, MCAT, GRE) — no school-tier content |
| **Course à la carte** | $9.99–$29.99 (one-time) | Buy access to a single premium course forever (e.g., "AP Biology forever") |

**Design constraint**: The existing `subscription.plan` field is a string with values `{free, monthly, annual}`. Extension requires a migration to add new plan values while keeping backward compatibility. Keep old plan names as-is and add new ones (`premium_monthly`, `premium_annual`, `professional_monthly`, `alacarte`).

### 2.2 Course-Level Access Control (The Missing Piece)

Today all courses are visible to all authenticated users. Premium catalog courses will be gated as follows:

```
CourseAccessLevel:
  :public       — fully free, anyone can access (student's own uploaded courses)
  :preview      — anyone can view syllabus + sample questions (first 10 per chapter)
  :standard     — requires standard or premium subscription (or à la carte purchase)
  :premium      — requires premium or professional subscription
  :professional — requires professional subscription only
```

The `Course` schema needs a new field: `access_level` (Ecto.Enum). Existing courses default to `:public`.

### 2.3 Premium Course Catalog — Content Sourcing Strategy

**Critical rule (from CLAUDE.md)**: Every piece of content shown to users must come from a real source. AI generation that actually ran, OCR extraction from real materials, or user input. No fake/hardcoded questions.

For the premium catalog, questions come from:
1. **AI-generated questions** aligned to official curriculum documents (College Board CEDs, ATAR syllabus, etc.) — the AI generation pipeline already exists
2. **OCR of licensed official prep materials** — where FunSheep obtains or partners for licensed materials
3. **Community contributions** — teacher-submitted questions that pass the existing quality validation pipeline

**Sourcing workflow for each premium course**:
1. Ingest the official curriculum document (PDF of CED, syllabus guide, etc.) via OCR pipeline
2. Generate questions per topic using existing AI question generation
3. Run through existing quality validation
4. Tag each question with: `source_type` (ai_generated | community | licensed), `difficulty` (1–5), `topic_tags`, `exam_year` (if from real exams)

### 2.4 Teacher Revenue Share ("Wool Credits")

The existing `funsheep-teacher-credit-system.md` proposes a credit system for teacher contributions. For the premium catalog, extend this:
- Teachers who contribute questions to a premium course earn Wool Credits
- Wool Credits are convertible to subscription time or platform credit
- Quality gate: questions that reach 80%+ student engagement receive double credits
- This creates a flywheel: teachers contribute → premium catalog grows → more subscriptions → more credits to distribute

---

## 3. Technical Architecture

### 3.1 Schema Changes

#### `courses` table — add access control fields
```sql
ALTER TABLE courses ADD COLUMN access_level varchar(20) NOT NULL DEFAULT 'public';
ALTER TABLE courses ADD COLUMN is_premium_catalog boolean NOT NULL DEFAULT false;
ALTER TABLE courses ADD COLUMN catalog_test_type varchar(50); -- 'sat', 'act', 'ap', 'ib', 'hsc', 'clt', 'lsat', 'bar', 'gmat', 'mcat', 'gre'
ALTER TABLE courses ADD COLUMN catalog_subject varchar(100); -- 'mathematics', 'biology', 'english_language', etc.
ALTER TABLE courses ADD COLUMN catalog_level varchar(20);    -- 'hl', 'sl', 'ab', 'bc', '1', '2', etc.
ALTER TABLE courses ADD COLUMN published_at utc_datetime;    -- nil = draft, set = live
ALTER TABLE courses ADD COLUMN published_by_id uuid REFERENCES user_roles(id);
ALTER TABLE courses ADD COLUMN sample_question_count integer NOT NULL DEFAULT 10;
```

#### `subscriptions` table — add new plan values and course access tracking
```sql
-- Extend plan enum (existing: free, monthly, annual)
-- Add: premium_monthly, premium_annual, professional_monthly
-- catalog_access: JSON array of test types user has selected access to (for standard plan's "pick 1/3" model)
ALTER TABLE subscriptions ADD COLUMN catalog_access jsonb NOT NULL DEFAULT '[]';
```

#### New table: `course_enrollments`
```sql
CREATE TABLE course_enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id uuid NOT NULL REFERENCES user_roles(id),
  course_id uuid NOT NULL REFERENCES courses(id),
  access_type varchar(20) NOT NULL, -- 'subscription', 'alacarte', 'free', 'gifted'
  access_granted_at utc_datetime NOT NULL,
  access_expires_at utc_datetime,   -- nil = permanent (à la carte)
  purchase_reference varchar(100),  -- Interactor checkout session ID for à la carte
  inserted_at utc_datetime NOT NULL,
  updated_at utc_datetime NOT NULL,
  UNIQUE(user_role_id, course_id)
);
```

#### New table: `premium_course_questions` (metadata for premium catalog questions)
```sql
-- Extends existing questions table with premium catalog metadata
CREATE TABLE premium_course_metadata (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL REFERENCES questions(id) UNIQUE,
  source_type varchar(30) NOT NULL, -- 'ai_generated', 'community', 'licensed'
  difficulty integer NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  topic_tags text[] NOT NULL DEFAULT '{}',
  exam_year integer,
  official_question_id varchar(100), -- for licensed content tracking
  inserted_at utc_datetime NOT NULL
);
```

### 3.2 New Context Functions

#### `FunSheep.Courses` — extend with access control
```elixir
# Check if a user can access a course
can_access_course?(user_role_id, course_id) :: :ok | {:error, :requires_subscription} | {:error, :requires_upgrade} | {:error, :not_enrolled}

# List premium catalog courses (public-facing browse)
list_premium_catalog(filters \\ []) :: [Course.t()]

# List courses accessible to a user (their own + enrolled premium)
list_accessible_courses(user_role_id) :: [Course.t()]

# Enroll a user in a premium course
enroll_in_course(user_role_id, course_id, access_type, opts \\ []) :: {:ok, CourseEnrollment.t()} | {:error, changeset}

# Check if a user is enrolled in a course
get_enrollment(user_role_id, course_id) :: CourseEnrollment.t() | nil

# Publish a premium course (admin only)
publish_course(course_id, admin_user_role_id) :: {:ok, Course.t()} | {:error, changeset}
```

#### `FunSheep.Billing` — extend with premium catalog logic
```elixir
# Check if a user's subscription grants access to a given course access_level
subscription_grants_access?(subscription, course) :: boolean

# Check if user can access a specific catalog test type under their plan
catalog_access_allowed?(user_role_id, test_type) :: :ok | {:error, :upgrade_required, %{current_plan: plan, required_plan: plan}}

# List catalog test types accessible under a plan
catalog_types_for_plan(plan) :: [String.t()]

# Initiate à la carte purchase for a single course
create_alacarte_checkout(user_role_id, course_id) :: {:ok, checkout_url} | {:error, reason}
```

### 3.3 Access Control Middleware

Add a `FunSheepWeb.Plugs.RequireCourseAccess` plug (or LiveView `on_mount` hook) that:
1. Loads the course from params
2. Checks `FunSheep.Courses.can_access_course?(user_role_id, course_id)`
3. On `:ok` — passes through
4. On `{:error, :requires_subscription}` — redirects to `/subscription?context=course&course_id=<id>`
5. On `{:error, :requires_upgrade}` — redirects to `/subscription?context=upgrade&from=<current_plan>&course_id=<id>`
6. On `{:error, :not_enrolled}` — shows course preview + enrollment CTA

### 3.4 Existing Flows to Preserve

- **Practice mode** (`/courses/:id/practice`) — stays free for own courses; gated for premium catalog courses
- **Test usage metering** (`FunSheep.Billing.check_test_allowance/2`) — still applies to premium catalog courses (premium subscription = unlimited, but still logged to `test_usages` for analytics)
- **Webhook activation flow** — extend `FunSheepWeb.WebhookController` to handle à la carte purchase events and call `enroll_in_course/4`

---

## 4. UI/UX Design

### 4.1 Premium Catalog Discovery Page

**Route**: `/catalog` (new)

**Layout**: Standard 3-panel (AppBar + Left Drawer + Main Content)

**Content**:
- Hero section: "Prep for the tests that matter most"
- Category tabs: `All | College Admission | AP Courses | International | Professional`
- Course cards in a responsive grid (3-col desktop, 2-col tablet, 1-col mobile)

**Premium Course Card** (extends existing course card):
```
┌─────────────────────────────────────┐
│ [AP] [BIOLOGY]                      │  ← test type badge + subject badge
│                                     │
│ AP Biology                          │  ← course name
│ College Board aligned               │  ← certification note
│                                     │
│ 8 Units · 430 questions             │  ← content stats
│ ★★★★☆  4.2 (1,240 students)         │  ← rating (when we have reviews)
│                                     │
│  [Start Practicing →]               │  ← green pill CTA (if enrolled)
│  [Unlock — $9.99 or Subscribe]      │  ← upsell CTA (if not enrolled)
└─────────────────────────────────────┘
```

**Locked course indicator**: A subtle lock icon overlay on the card thumbnail + a green "Unlock" badge in the corner.

### 4.2 Premium Course Detail Page

Extends `CourseDetailLive`. New elements for premium courses:
- **Access banner** (top of page, collapsible):
  - If enrolled: green banner "You have access to this course"
  - If preview: yellow banner "Preview mode — 10 questions per chapter. Subscribe or unlock for full access."
  - If locked: orange/red banner with upgrade CTA
- **Chapter list**: Shows all chapters; locked chapters show lock icon + chapter title (no content)
- **Sample questions**: First 10 questions per chapter always visible as preview
- **Enrollment options sidebar** (right pane):
  - Monthly / Annual subscription options (existing `SubscriptionLive` flows)
  - À la carte option: "Get this course forever — $9.99"
  - "Already subscribed? Activate this course" (for Standard plan users choosing their 1 or 3 catalogs)

### 4.3 Subscription Page Extensions

Extend `SubscriptionLive` with a new tab: **Catalog Access**

Content:
- Your current plan and which catalog types it includes
- For Standard plan: "You have 1 of 1 catalog slot. Choose your test:"
  - Radio buttons for SAT, ACT, AP, IB, etc.
  - "Save selection" → updates `subscriptions.catalog_access`
- For Premium Annual: "You have access to the full catalog including professional tests"
- "Unlock individual courses" section: list of à la carte purchased courses

### 4.4 Course Settings (Admin/Creator UI)

Extend `CourseDetailLive` edit mode with a new **Premium Settings** section (admin-only):

```
┌─ Premium Catalog Settings ─────────────────┐
│ Access Level:  [ Public ▼ ]                │
│ Test Type:     [ SAT ▼ ]                   │
│ Subject:       [ Mathematics ]             │
│ Level:         [ (not applicable) ]        │
│ À la carte price: [ $9.99 ]                │
│                                            │
│ Status: Draft                              │
│ [Publish Course]                           │
└────────────────────────────────────────────┘
```

### 4.5 Upgrade Interstitial (when hitting a locked premium course)

Full-screen interstitial (rendered as a LiveView modal/overlay):

```
┌──────────────────────────────────────────────┐
│                                              │
│   🐑  FunSheep Premium                       │
│                                              │
│   Unlock AP Biology — and every AP course   │
│                                              │
│   ✓ All 15 AP subjects                      │
│   ✓ 6,000+ practice questions                │
│   ✓ College Board aligned                   │
│   ✓ AI tutor for every question             │
│                                              │
│   [Subscribe — $149/year]  ← green pill     │
│   [Or get just AP Bio — $9.99 once]         │
│                                              │
│   [No thanks, go back]  ← text link         │
│                                              │
│   Already subscribed? [Sign in]             │
└──────────────────────────────────────────────┘
```

**Conversion psychology**:
- Show the breadth they're missing ("all 15 AP subjects") — not just the one they clicked
- Annual price anchoring ($149 vs. $59/month framing)
- À la carte option reduces anxiety for the undecided ("I can just try one")
- No dark patterns — "No thanks" is always clearly visible

---

## 5. Content Pipeline for Premium Courses

### 5.1 Course Generation Workflow

Each premium course follows this pipeline (extending the existing OCR + AI generation pipeline):

```
Step 1: Syllabus Ingestion
  ↓ Upload official curriculum PDF (College Board CED, ATAR syllabus, etc.)
  ↓ OCR → structured text (existing pipeline)
  ↓ AI extracts: units, topics, learning objectives, content boundaries

Step 2: Question Generation per Topic
  ↓ For each topic cluster, AI generates N questions at difficulty 1–5
  ↓ Questions tagged: topic, difficulty, question_type, format (MCQ, FRQ, etc.)
  ↓ Distractors generated for MCQ (existing question generation)

Step 3: Quality Validation
  ↓ Existing validation pipeline (curriculum alignment, quality score, duplicates)
  ↓ AI-generated explanations for every question (existing tutor pipeline)
  ↓ Flag questions below quality threshold for human review

Step 4: Admin Review & Publishing
  ↓ Admin reviews flagged questions, rejects/approves
  ↓ Sets `published_at`, `access_level`, `catalog_test_type`
  ↓ Course goes live on `/catalog`

Step 5: Ongoing Improvement
  ↓ Student engagement signals (skip rate, time-on-question, retry rate) feed back
  ↓ Low-engagement questions get re-generated or flagged
  ↓ New official exam releases trigger incremental question updates
```

### 5.2 Question Volume Targets

| Test | Target Questions | Target Chapters |
|---|---|---|
| SAT (Full) | 800 | 12 |
| ACT (Full) | 600 | 10 |
| AP (per subject) | 400–600 | 6–9 (per College Board units) |
| IB (per subject/level) | 300–500 | 6–8 |
| HSC (per subject) | 300–400 | 5–8 |
| CLT (Full) | 300 | 6 |
| LSAT (Full) | 600 | 8 |
| Bar Exam (MBE) | 1,000 | 7 (one per MBE subject) |
| GMAT (Full) | 400 | 5 |
| MCAT (Full) | 1,200 | 4 |
| GRE (Full) | 500 | 5 |

### 5.3 Prioritized Content Build Order

Phase 1 (Launch): SAT, ACT, AP (top 5: Eng Lang, US History, Calc AB, Bio, Psych)
Phase 2 (Month 2–3): AP (remaining 10), IB (top 6 subjects), CLT
Phase 3 (Month 4–6): HSC (top 8 subjects), PSAT, IB (remaining subjects)
Phase 4 (Month 7–12): LSAT, GMAT, GRE, Bar Exam (MBE), MCAT
Phase 5 (Year 2): A-Levels, GCSE, JEE/NEET, VCE, DSE, IELTS/TOEFL

---

## 6. Promotional & Marketing Strategy

### 6.1 In-App Upsell Moments

| Trigger | Upsell Shown | Target Audience |
|---|---|---|
| Student completes own course practice → score shown | "Want to see how you'd score on the real SAT? Try our SAT prep course." | Students |
| Student's own course subject matches a premium catalog subject | Auto-suggest: "We have an official AP Chemistry course" | Students |
| Student hits weekly test limit | "You're almost there. Unlock unlimited tests + the SAT prep course for $9.99 this month." | Students → Parents |
| Parent logs in, views child's progress | "Add premium test prep for [child name] — includes SAT, ACT, all AP courses." | Parents |
| Teacher assigns a course | "Your school can get premium test prep at a reduced group rate." | Teachers → School admins |

### 6.2 Teacher & School Bundles

- **Classroom Tier**: $200/class/year — teacher can grant premium catalog access to all students in a class
  - Teacher pays once; all students in the class get standard premium access
  - Teacher dashboard shows class-wide progress on a premium catalog course
- **School Tier**: Custom pricing — district-wide access negotiations
  - Contact sales flow (simple form → email notification to FunSheep team)

### 6.3 Referral & Virality

**"Flock" mechanic** (from `flock-shout-outs-and-credits.md`):
- Student who refers a friend who subscribes gets 1 month free added to their subscription
- Teacher who gets 10+ students on premium gets a free school year
- "Share your score improvement" → social share card with FunSheep branding

### 6.4 Seasonal Promotions

| Period | Event | Offer |
|---|---|---|
| August–September | Back to School | 20% off annual subscription for first month |
| October | PSAT season | Free PSAT prep for first 30 days |
| November–December | SAT/ACT registration deadlines | "Prep now for March SAT" push |
| March–April | AP Exam season | Free AP preview for any 2 subjects |
| May | IB/AP Exam crunch | "Final week" intensive bundles |
| June–July | Bar Exam season | Professional tier promotion |

---

## 7. Phased Rollout Plan

### Phase 0: Foundation (Weeks 1–3) — Technical Infrastructure

**Goal**: Build the access control layer without any premium content yet.

**Tasks**:
1. Database migrations:
   - `access_level` column on `courses`
   - `catalog_access` column on `subscriptions`
   - New `course_enrollments` table
   - New `premium_course_metadata` table
2. Schema updates: `FunSheep.Courses.Course`, `FunSheep.Billing.Subscription`, new `CourseEnrollment` schema
3. New context functions: `can_access_course?/2`, `enroll_in_course/4`, `subscription_grants_access?/2`
4. Access control plug/hook: `RequireCourseAccess`
5. Wire access control into all course LiveViews (`CourseDetailLive`, `PracticeLive`, `QuickTestLive`, `TestScheduleLive`, etc.)
6. Tests: unit tests for all new context functions, integration tests for access control flows

**Deliverable**: Access control is wired up but all existing courses remain `:public` — no visible user change.

### Phase 1: Premium Catalog Browsing (Weeks 4–5) — Discovery UI

**Goal**: Users can browse the premium catalog (even though no real content exists yet).

**Tasks**:
1. New route: `/catalog`
2. `CatalogLive` LiveView with:
   - Category tabs (College Admission, AP, International, Professional)
   - Course card grid with lock/unlock state
   - Filtering: by test type, subject, grade level
3. Extend `CourseDetailLive` with:
   - Access banner (enrolled / preview / locked)
   - Enrollment options sidebar (right pane)
   - Admin premium settings section
4. Extend `SubscriptionLive`:
   - New "Catalog Access" tab
   - Standard plan catalog type selector
5. Upgrade interstitial modal
6. New plan tiers in subscription UI (Premium Monthly $59, Premium Annual $149, Professional $99)
7. Visual testing (Playwright) for all new UI

**Deliverable**: Users can browse the (empty) premium catalog, see upgrade flows, and conceptually understand the product. Admins can create draft premium courses.

### Phase 2: First Premium Content (Weeks 6–10) — SAT & ACT Launch

**Goal**: Launch SAT and ACT courses with real AI-generated content.

**Tasks**:
1. Admin pipeline tooling: batch course creation with curriculum PDF ingestion
2. Generate SAT Math course (target: 400 questions)
3. Generate SAT Reading & Writing course (target: 400 questions)
4. Generate ACT full course bundle (target: 600 questions across 5 sections)
5. Admin review workflow: approve/reject questions, set difficulty
6. Publish SAT + ACT to `/catalog` with `access_level: :standard`
7. Activate real à la carte Stripe products (coordinate with Interactor Billing team)
8. Activate new subscription plan tiers (coordinate with Interactor Billing team)
9. Email marketing: announce SAT + ACT prep to existing user base

**Deliverable**: Paying users can access SAT + ACT prep. First à la carte purchases are live.

### Phase 3: AP Courses (Weeks 11–16)

**Goal**: Top 15 AP courses live on the platform.

**Tasks**:
1. Generate AP courses 1–5 (English Language, US History, Calc AB, Bio, Psych)
2. Admin review + publish AP courses 1–5
3. Generate AP courses 6–15
4. Admin review + publish all AP courses
5. AP course "unit" structure aligned to College Board CEDs (units are numbered + named exactly per CB)
6. Teacher/class bundle pricing for AP courses
7. "AP Score Predictor" feature: after N practice questions, show projected AP exam score band (1–5)

**Deliverable**: Full AP prep catalog live.

### Phase 4: International Tests (Weeks 17–22)

**Goal**: IB, HSC, CLT live on the platform.

**Tasks**:
1. IB curriculum ingestion (IB guide PDFs)
2. Generate IB courses (top 6 subjects × HL + SL = 12 courses)
3. Generate HSC courses (top 8 subjects)
4. Generate CLT course bundle
5. Regional pricing: consider AUD pricing for HSC, EUR/GBP for IB
6. "International" filter in catalog browse

**Deliverable**: International premium catalog live.

### Phase 5: Professional Tests (Weeks 23–36)

**Goal**: LSAT, GMAT, GRE, Bar Exam, MCAT.

**Tasks**:
1. Design "Professional" account type (adults, no school affiliation required)
2. Professional tier pricing + Interactor Billing integration
3. LSAT: logic games section requires structured question types beyond current MCQ — extend question schema for ordering/grouping answer formats
4. Bar Exam (MBE): 7-subject course bundle, MBE-specific question format
5. GMAT: Data Insights section requires table/graph question rendering
6. MCAT: Passage-based questions (one passage → 4–7 questions) require passage linking in schema
7. GRE: Vocabulary-intensive; word list feature for verbal section
8. Professional marketing: LinkedIn ads, law school subreddits, MCAT forums

**Deliverable**: Professional test prep catalog live.

---

## 8. Metrics & Success Criteria

### 8.1 North Star Metric

**Premium Catalog Monthly Recurring Revenue (MRR)** — distinct from the test-activity subscription MRR.

### 8.2 Phase 1 Success Criteria (by end of Phase 2)
- [ ] SAT + ACT courses have 500+ active enrolled users
- [ ] À la carte conversion rate ≥ 2% of catalog page visitors
- [ ] Premium subscription upgrade rate ≥ 5% of users who hit the upgrade interstitial
- [ ] Net Promoter Score from premium users ≥ 60

### 8.3 Phase 2 Success Criteria (by end of Phase 4)
- [ ] $10,000 MRR from premium catalog subscriptions
- [ ] 15+ AP courses with ≥ 100 active students each
- [ ] International users (AU, UK, HK) represent ≥ 15% of premium catalog users
- [ ] Teacher classroom bundles: ≥ 20 classroom licenses sold

### 8.4 Phase 3 Success Criteria (end of Phase 5)
- [ ] $50,000 MRR total (catalog + professional tiers)
- [ ] Professional tests: LSAT + GMAT have ≥ 500 enrolled students each
- [ ] Bar Exam prep: recognized as alternative to Themis/Barbri by ≥ 3 law school forums
- [ ] À la carte revenue ≥ 20% of total premium catalog revenue

---

## 9. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AI-generated questions have factual errors | High | High | Quality validation pipeline; human admin review before publish; report-a-question button; periodic re-generation |
| College Board copyright challenge for AP content | Medium | High | Questions are AI-generated aligned to curriculum, not copied. Avoid reproducing verbatim official questions. Use topic tags, not exam year citations. |
| Content depth insufficient for MCAT / Bar (very technical) | High | Medium | Phase 5 delayed; bring in subject-matter expert reviewers; start with MBE only for Bar |
| Stripe à la carte product setup complexity in Interactor Billing | Medium | Medium | Coordinate with Interactor team early (Phase 0); define product catalog requirements before Phase 1 |
| Users game the "1 catalog slot" Standard plan | Low | Low | Server-side enforcement; `catalog_access` array capped at plan limit; changeable but logged |
| International pricing sensitivity (HSC/IB market) | Medium | Medium | A/B test pricing in Phase 4; consider PPP-adjusted pricing for AU/UK |
| Premium users expect 100% official question accuracy | High | High | Clear labeling: "AI-generated, curriculum-aligned" not "official College Board questions"; set expectations at enrollment |

---

## 10. Open Questions (Require Product Decision Before Implementation)

1. **À la carte pricing**: $9.99 per course — is this the right price point? Should AP Biology be $9.99 vs. Bar Exam at $29.99?
2. **Standard plan catalog slots**: "Pick 1 or 3" catalogs — is this UX complexity worth it, or should Standard just include all school-level tests and gate only professional?
3. **Free preview depth**: 10 questions per chapter — enough to demonstrate value without giving away the product?
4. **Score prediction feature (Phase 3)**: Is a "projected AP score" (1–5) a product promise we can deliver accurately enough?
5. **International content moderation**: HSC syllabus changes annually — who monitors and updates?
6. **Teacher classroom bundle pricing**: $200/class/year — is this competitive with existing SAT prep offerings?
7. **Passage-based questions for MCAT/GRE**: Does the current question schema support one passage → many questions? If not, schema extension required in Phase 5.

---

## 11. Implementation Notes for Claude Sessions

### What Exists (DO NOT Rebuild)
- `FunSheep.Billing` context — extend; do not fork
- `FunSheep.Interactor.Billing` HTTP client — add methods; do not replace
- `FunSheepWeb.SubscriptionLive` — extend with new tabs; do not rewrite
- `FunSheep.Courses` context — extend; do not refactor unrelated functions
- OCR + AI question generation pipeline — reuse for premium course content

### What Needs Building (From Scratch)
- `FunSheep.Courses.CourseEnrollment` schema + context functions
- `FunSheep.Catalog` context (or sub-namespace of `FunSheep.Courses`) for catalog-specific queries
- `FunSheepWeb.CatalogLive` LiveView + templates
- `FunSheepWeb.Plugs.RequireCourseAccess` or equivalent `on_mount` hook
- Course admin management UI (extend existing admin pages)
- Upgrade interstitial component

### Mandatory Rules (From CLAUDE.md)
- **No fake content**: Premium course questions must come from actual AI generation runs, not hardcoded strings
- **Progress feedback**: Course generation pipeline must show real-time progress (existing `FunSheep.Progress.Event` shape)
- **Playwright testing**: All new UI must be Playwright-tested before marking complete
- **Interactor Billing**: All payment flows go through Interactor Billing Server — do not add Stripe library directly
- **Mix format**: Run `mix format` before committing
- **Test coverage**: Maintain > 80% coverage — write tests for every new context function

---

## 12. Related Roadmap Documents

- `funsheep-subscription-flows.md` — parent/student subscription conversion flows (read first for billing context)
- `funsheep-school-course-catalog.md` — school-level course discovery (dovetails with classroom bundles)
- `funsheep-teacher-credit-system.md` — Wool Credits for teacher contributions to premium catalog
- `funsheep-peer-sharing.md` — community contributions to premium courses
- `funsheep-platform-quality-assessment.md` — quality validation that premium questions must pass
- `funsheep-student-onboarding.md` — where new premium students land after purchase
