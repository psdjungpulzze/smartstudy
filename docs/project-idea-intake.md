# Project Idea Intake

Use this document to capture your initial project idea. Don't worry about structure or completeness - just get your thoughts down. Claude will help refine and structure this during the discovery phase.

---

## The Idea

*Describe what you want to build in your own words. Be as detailed or rough as you like.*

StudySmart is an AI-powered adaptive study platform that helps students prepare for exams. It creates personalized courses by discovering and organizing educational content (textbooks, online resources, videos), extracts and generates practice questions, then uses adaptive testing to identify knowledge gaps and guide students toward test readiness. Think of it as an intelligent tutor that knows exactly what you need to study, tracks your progress per topic, and provides a "Tinder-style" mobile quick-test experience for on-the-go review.

---

## Problem / Opportunity

*What problem does this solve? Or what opportunity does it address?*

Students waste time studying topics they already know while neglecting weak areas. Current study tools are static — they don't adapt to individual knowledge levels. StudySmart solves this by:
- Automatically discovering and organizing course content from multiple sources
- Using adaptive/progressive testing to precisely identify what a student knows vs. doesn't know
- Providing targeted study guides pointing to exact textbook pages and reference materials
- Giving a real-time "Test Readiness" score so students know when they're prepared

---

## Users

*Who will use this? List anyone you can think of.*

- Students (primary): K-12 and higher education, preparing for school exams, standardized tests (e.g., AP Biology), etc.
- Parents: Monitor children's test readiness and study progress, manage multiple children
- Teachers: Manage class rosters, monitor student progress, assign practice activities
- Platform admins: Manage users, courses, and platform settings via separate admin portal
- Diverse demographics: Multiple countries, school systems, languages, grade levels
- Mobile-first users who want quick study sessions on the go

---

## Key Features (Brain Dump)

*List features, capabilities, or things users should be able to do. Don't filter - just dump everything.*

### Phase 1: Subject/Course Creation

#### 1. Subject Setup (Multi-Stage Input)

**Stage 1 — Demographics/Context:**
- **Role selection: Student / Parent / Teacher**
- Country / State
- District / School
- Subject / Class (for students/teachers)
- Grade level (for students)
- Gender
- Nationality

**Stage 2 — Hobbies (for question & explanation personalization):**
- Research hobbies relevant to the student's demographics (region, gender, age, nationality)
- Store hobby domain knowledge in Interactor User Knowledge Base (UKB) — e.g., what KPOP is, who BTS/BlackPink members are, relevant names/terms/scenarios
- Present hobby options to student for selection
- Store student's hobby preferences in Interactor User Profiles
- **Purpose**: Use hobbies to contextualize questions and explanations
  - Example: Korean female HS junior in Saratoga, CA who likes KPOP → "Jenny and JongKuk had 100,000 followers. If Jenny lost 50,000 followers, what percentage did she lose?"
  - Ideally, generated questions AND explanations reference the student's hobbies
  - Fallback to generic when hobby context doesn't fit

**Stage 3 — Material Upload:**
- Student uploads their own materials (textbooks, PDFs, images, notes)

#### 2. Course/Lesson Creation — Content Discovery

**2a. Match existing courses:**
- Check if similar courses already exist in the system
- Present matches to the student for confirmation
- If confirmed, build lessons based on the existing course structure

**2b. Create new course (if no match):**

*Subject identification & chapter/section classification:*
- Identify the subject and break it into chapters and sections
- Store the classification structure in DB
- Track page numbers and associate images/PDF pages so that when asking questions, the system can show students the specific textbook or supplement material page

*Online question search:*
- Search for publicly available practice/exam questions online
- Search across HTML pages, PDFs, Google Docs, etc.
- Store all found questions with their source links

*Online lesson/video discovery:*
- Search for online lessons and videos (e.g., YouTube transcripts, Khan Academy)
- Evaluate and rank by relevance/quality

*Question creation & extraction:*
- Extract questions from uploaded files using intelligent page and section identification
- If creating new questions, base them on searched/discovered materials
- Store all extracted/found questions with source attribution (links)
- Classify each question by chapter/section so students can see which textbook area the question relates to
- Example workflow:
  - Extract questions from "Test Prep Series AP Biology"
  - Extract questions from "Chapter Review" sections of each chapter
  - Verify extracted question count matches expected question numbers
  - Ensure every question has an associated answer
- If source material is PDF or image, perform OCR (see OCR-first pipeline below)

**2c. OCR-First Processing Pipeline (Token Cost Optimization):**
- Instead of sending entire uploaded files (PDFs, images) directly to the LLM, first extract text and images via OCR
- This significantly reduces AI token costs by only sending relevant text chunks to the LLM for question extraction, classification, etc.
- Extraction must preserve mapping metadata for each chunk:
  - Source file name
  - Page number
  - Bounding box / position on page
  - Section/chapter (if detectable)
  - Associated images with their position context
- Extracted images must be stored with references back to their source page and position, so they can be displayed to students alongside questions (e.g., "See Figure 3.2 on page 47")
- Only after OCR extraction, send relevant text segments to the LLM for intelligent processing (question extraction, classification, answer association)

**2d. Link reference materials to questions:**
- Associate each question with relevant textbook pages and reference materials
- Tag each question with its topic
- Tag/categorize each question per school (district/school from student's profile) so questions can be filtered and reused within the same school context

### Phase 1: Test Preparation

#### 1. Test Scope & Schedule Setup
- Select subject
- Select chapters + sub-chapters to cover
- Specify test type (if school provided a format/sample)
- **Set test date** — schedule the upcoming exam
  - Dashboard shows upcoming tests sorted by date with countdown
  - Readiness score displayed in context of schedule ("3 days left, readiness: 72%")
  - Notifications/reminders as test date approaches
- **Upload test format** (if available from school) — see Test Format Replication below

#### 2. Assessment Phase (Adaptive/Progressive Testing)

**Goal:** Identify what the student knows and doesn't know.

**Adaptive testing methodology:**
- Test at least 3 questions per topic
- If the student gets any of the 3 wrong, adaptively test again to verify the gap
- Start with easy questions, progressively increase difficulty to test depth of knowledge
- Copyright compliance: Never use exact questions from copyrighted sources — change numbers or words slightly to create derivative questions
  - Store all newly created derivative questions in DB for future reuse
- Always use stored questions first; only generate new questions after the student has exhausted the stored pool
- Keep full question history:
  - Track correct/incorrect per attempt
  - Support filtering to extract only correct or only incorrect answered questions
- For open-ended/free-response questions, use AI agent to evaluate and correct student answers; also provide associated model answers

**Weakness analysis output — Test Readiness:**
- Show test scope coverage
- Per-chapter score
- Per-topic score
- Aggregate into an estimated total test score

**Study guide generation:**
- Identify topics the student needs to study more
- Show specific textbook pages and reference material links for weak areas

#### 3. Practice Tests

**Goal:** Practice questions the student is scoring lower on.

- User experience similar to Assessment phase
- Repetitive cycle: test → show results → provide learning materials → re-test
- Focus on weak areas identified during assessment

#### 4. Test Format Replication (Exam Simulation)

**Goal:** Generate practice tests that exactly replicate the student's real exam format.

- Student uploads a test format/sample from their school (PDF, image)
- AI analyzes the format to identify:
  - Number of questions per section
  - Question types (multiple choice, short answer, essay, etc.)
  - Point distribution
  - Section structure and order
  - Time limits (if specified)
- System generates practice tests matching the exact format:
  - Same structure, question types, count, and point distribution
  - Questions drawn from the test scope topics
  - All questions validated via multi-agent pipeline (FR-012)
- **Timed mode**: Student can take the practice test with a countdown matching real exam duration
- **Scheduling integration**: Format-matched practice tests are recommended/surfaced a few days before the scheduled test date
  - e.g., "Your AP Bio exam is in 3 days — take a practice test in your exam format"
- Student can generate multiple practice tests in the same format for repeated practice

#### 5. Mobile Quick Tests

**Goal:** Quick, card-based review — "Tinder for studying."

- Swipeable card-based question UI
- For each question card, the student can:
  - **"I know this"** — Mark as known and skip to next
  - **"I don't know this"** — Show a short explanation first, then provide links to video lessons and other resources (use in-product browser if needed)
  - **Answer** — Provide an answer interface (similar to assessment/practice test)
  - **Skip** — Move to next without marking
- Track all responses to feed into the Test Readiness score

### Cross-Cutting Features

**Dynamic question generation (multi-agent validation):**
- If no questions exist for a topic, generate them using AI
- Derivative questions use simple word and number changes
- When possible, contextualize with student's hobby preferences (e.g., KPOP references in math problems)
- Multi-agent pipeline ensures 100% answer correctness:
  1. **Agent 1 (Question Creator)**: Creates derivative question with modified numbers/words + hobby context
  2. **Agent 2 (Answer Creator)**: Independently solves the new question
  3. **Agent 3 (Validator)**: Cross-checks question, answer, and original source for consistency
- Only questions passing all 3 agents are stored in DB for future reuse
- Failed validations logged but never shown to students

**Export / Print:**
- Export study materials (weak areas, study guides) to Google Docs, Word Docs, PDF, etc.
- Support flexible export to various formats

**Test Readiness Dashboard:**
- Test scope overview
- Per-chapter score
- Per-topic score
- Aggregate estimated test score

**Multi-language support:**
- Support multiple languages (refer to interactor-website for implementation patterns)

### Parent & Teacher Features

**Parent features:**
- Link to multiple children's student accounts (invite code or confirmation)
- Parent dashboard showing all linked children's readiness scores at a glance
- Drill into individual child's per-chapter and per-topic progress
- Notifications when test dates approach and readiness is low

**Teacher features:**
- Create classes and add students (bulk add or invite codes)
- Class dashboard with aggregate and per-student readiness scores
- Highlight struggling students below a configurable threshold
- Assign targeted practice tests to specific students
- Track completion and improvement over time

**Admin portal:**
- Separate admin login via Interactor Admin JWT (not User JWT)
- User management: view, edit roles, deactivate accounts
- Platform-wide analytics: usage, courses, questions, trends
- Content moderation: review flagged questions, failed validations

---

## Inspirations / References

*Are there similar products? Screenshots? Competitors? Things you like or don't like?*

- Khan Academy (lesson discovery, structured courses)
- Quizlet (card-based review)
- Tinder (swipe UX for mobile quick tests)
- AP Test Prep books (question extraction model)
- Adaptive testing platforms (progressive difficulty)

---

## Technical Thoughts (Optional)

*Any technical ideas, constraints, or preferences you already have in mind.*

- Elixir / Phoenix / LiveView stack (per project CLAUDE.md)
- OCR-first pipeline: Google Cloud Vision OCR to extract text + images from uploads before sending to LLM to minimize token costs (~98% accuracy, ~$1.50/1K pages)
- Multi-language support following interactor-website patterns
- In-product browser for viewing external lesson links (mobile)
- **Image/file storage strategy:** Store locally during development (e.g., `priv/static/uploads/`), with a storage abstraction layer so it can be swapped to AWS S3 later via config change without code rewrite
- Questions categorized per school to enable school-specific question pools and reuse

### Interactor Platform Integration (MANDATORY)

**This application MUST make full use of Interactor platform services instead of building custom equivalents.** The interactor-workspace submodule contains the full platform. See `docs/i/interactor-docs/integration-guide/` and `docs/i/account-server-docs/integration-guide/` for API details.

#### Service Mapping: StudySmart Feature → Interactor Service

| StudySmart Feature | Interactor Service | How It's Used |
|----|----|----|
| **End-user authentication** | Account Server (User JWT, OAuth/OIDC) | Student/parent/teacher login, registration, MFA. Role stored in user `metadata.role`. |
| **Admin authentication** | Account Server (Admin JWT) | Separate admin portal login for platform management. Distinct from end-user auth. |
| **Role enforcement** | Application layer | StudySmart reads `metadata.role` from user record and enforces permissions per route/action. Not enforced at Interactor auth layer. |
| **Hobby domain knowledge** | User Knowledge Base (UKB) | Store hobby domain knowledge (KPOP facts, BTS members, sports terms) for semantic retrieval by agents during question/explanation generation |
| **Curriculum/subject knowledge** | User Knowledge Base (UKB) | Store curriculum outlines, topic taxonomies, and subject domain knowledge for semantic retrieval by content discovery and question generation agents |
| **Student progress data** | User Database (UDB) | Agent-queryable data layer for student progress (scores, completion, readiness). Dynamic tables with per-user isolation. Parents/teachers query linked students' data via agents. |
| **Question extraction from uploads** | AI Agents (Assistants + Tools) | Create a dedicated assistant with OCR tool callbacks to extract questions from processed text |
| **Content discovery (online)** | AI Agents (Assistants + Tools) | Assistant with web search/scraping tools to find questions, videos, lessons |
| **Answer evaluation (free-response)** | AI Agents (Rooms + Messages) | Chat room per assessment session; agent evaluates student answers in real-time |
| **Question generation** | AI Agents (Assistants) | Dedicated assistant to generate derivative questions (copyright-safe) |
| **Study guide generation** | AI Agents (Assistants) | Assistant that analyzes weakness data and generates targeted study guides |
| **Adaptive testing flow** | Workflows (State Machine) | Model the assessment as a workflow: test → evaluate → branch (easy/hard) → report |
| **Course creation pipeline** | Workflows (State Machine) | Multi-step workflow: setup → content discovery → question extraction → classification → review |
| **Student preferences & context** | AI Agents (User Profiles) | Store grade, school, nationality, hobbies, learning preferences per `external_user_id` |
| **Real-time AI responses** | Webhooks & SSE | Stream agent responses during assessment and chat-based tutoring |
| **External service access (YouTube, Google Docs export)** | Credential Management | Store OAuth tokens for Google, YouTube APIs; auto-refresh handled by Interactor |
| **Per-student usage tracking** | Billing Server | Track AI usage per student via `external_user_id` allocations |
| **Question bank DB access by agents** | Data Sources | Connect StudySmart's PostgreSQL so agents can query existing questions before generating new ones |
| **Specialized agent delegation** | Supporting Assistants | Orchestrator agent delegates to specialized agents (question extractor, content discoverer, evaluator) |
| **External service discovery** | Service Knowledge Base | Search for connectable services (YouTube, Khan Academy, Google Docs) |

#### Interactor AI Agent Architecture

```
┌─────────────────────────┐
│  StudySmart Orchestrator │  (Primary assistant)
│  Assistant               │
└──────────┬──────────────┘
           │ delegates specialized tasks
     ┌─────┼─────────┬──────────────┬───────────────┐
     ▼     ▼         ▼              ▼               ▼
┌────────┐┌────────┐┌────────────┐┌──────────────┐┌──────────┐
│Question││Content ││Assessment  ││Study Guide   ││Question  │
│Extract ││Discover││Evaluator   ││Generator     ││Generator │
│Agent   ││Agent   ││Agent       ││Agent         ││Agent     │
└────────┘└────────┘└────────────┘└──────────────┘└──────────┘
```

#### Interactor Workflow: Adaptive Assessment

```
┌────────┐    ┌──────────┐    ┌──────────────┐
│ Start  │───>│ Ask Q(s) │───>│ Evaluate     │
│ (set   │    │ (action) │    │ Answers      │
│ scope) │    └──────────┘    └──────┬───────┘
└────────┘                          │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              ┌──────────┐   ┌──────────┐    ┌───────────┐
              │ Increase │   │ Repeat   │    │ Move to   │
              │ Difficulty│   │ Topic    │    │ Next Topic│
              │ (action) │   │ (action) │    │ (action)  │
              └─────┬────┘   └────┬─────┘    └─────┬─────┘
                    └─────────────┼─────────────────┘
                                  ▼
                           ┌────────────┐
                           │ Generate   │
                           │ Readiness  │──> Terminal
                           │ Report     │
                           └────────────┘
```

---

## What Success Looks Like

*How would you know this project succeeded?*

- Students can set up a course and have questions + materials auto-discovered in minutes
- Adaptive assessment accurately identifies knowledge gaps within a single session
- Test Readiness score correlates with actual exam performance
- Mobile quick-test experience is engaging enough for daily use
- Students can export targeted study guides for offline review

---

## Open Questions

*Things you're unsure about or need to figure out.*

- Exact adaptive testing algorithm (research best practices for progressive difficulty)
- Copyright boundaries for question derivation — how much modification is "enough"?
- Hobby-based personalization: how exactly does this influence the study experience?
- OCR accuracy requirements and fallback for low-quality scans
- Scope of "online lesson discovery" — which platforms beyond YouTube and Khan Academy?
- OCR tool selection: Tesseract (free/local) vs. cloud OCR (Google Vision, AWS Textract) — tradeoff between cost, accuracy, and image extraction quality
- S3 migration timeline: when to move from local storage to AWS S3 (at what scale / user count?)

---

## Priority / Timeline

*Any constraints on when this needs to ship or what's most important?*

Development Phase 1 covers:
1. Subject/Course creation (setup, content discovery, question extraction)
2. Test preparation (assessment, practice tests, mobile quick tests)

Core priority order:
1. Course creation + question extraction pipeline
2. Adaptive assessment engine
3. Test Readiness scoring
4. Practice tests
5. Mobile quick tests
6. Export/print functionality

---

## Deployment Preferences (Optional)

*Where and how should this run? Any infrastructure preferences or constraints?*

```
[To be determined during planning phase]
```

### Deployment Considerations

| Consideration | Your Preference |
|---------------|-----------------|
| **Hosting** | [To be determined] |
| **Database** | PostgreSQL (per stack) |
| **CI/CD** | GitHub Actions |
| **Environments** | dev / staging / prod |
| **Release Strategy** | [To be determined] |

*Don't worry if you're unsure - these can be decided during planning. See `docs/phases/06-deployment/` for detailed deployment guidance.*

---

# What Happens Next

Once you've filled this out (even partially), use `/start-discovery` and share this document. Claude will:

1. **Extract and organize** your ideas into structured requirements
2. **Identify gaps** and ask clarifying questions
3. **Generate** user stories, stakeholder analysis, and a requirements document
4. **Suggest** a path forward into the planning phase

You don't need to fill out every section - write what you know, and the discovery process will help fill in the rest.
