# FunSheep System Architecture

## Document Information

| Field | Value |
|-------|-------|
| **Project** | FunSheep |
| **Version** | 1.0 |
| **Last Updated** | 2026-04-17 |
| **Author** | Peter Jung |
| **Status** | Draft |

---

## 1. System Overview

FunSheep is an AI-powered adaptive study platform built with Elixir/Phoenix/LiveView. It delegates authentication, AI agent orchestration, workflow automation, credential management, and billing to the Interactor platform rather than building custom equivalents.

### High-Level System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    USERS (Students, Parents, Teachers — Browser / Mobile Web)    │
│                                       │                                          │
│                              HTTPS (LiveView WebSocket)                          │
└───────────────────────────────────────┼──────────────────────────────────────────┘
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                         STUDYSMART PHOENIX APPLICATION                            │
│                                                                                   │
│  ┌──────────────┐  ┌──────────────────────────────┐  ┌────────────────────────┐  │
│  │  Web Layer   │  │      Business Logic           │  │  Interactor            │  │
│  │  (LiveView)  │──│      (Contexts)               │──│  Integration Layer     │  │
│  │              │  │                                │  │                        │  │
│  │  - Profile   │  │  - Accounts   - Readiness     │  │  - Auth   - Agents     │  │
│  │  - Courses   │  │  - Courses    - Content       │  │  - Workflows           │  │
│  │  - Assess    │  │  - Questions  - Hobbies       │  │  - Credentials         │  │
│  │  - Quick Test│  │  - Assessments- Export        │  │  - Webhooks - Billing  │  │
│  │  - Dashboard │  │                                │  │  - Profiles - KB       │  │
│  │  - Parent    │  │                                │  │  - UserDatabase        │  │
│  │  - Teacher   │  │                                │  │  - KnowledgeBase       │  │
│  │  - Admin     │  │                                │  │                        │  │
│  └──────────────┘  └──────────────────────────────┘  └───────────┬────────────┘  │
│                                   │                               │               │
│                    ┌──────────────┘                               │               │
│                    ▼                                              │               │
│  ┌──────────────────────────┐  ┌──────────────────┐              │               │
│  │  PostgreSQL (FunSheep) │  │  File Storage    │              │               │
│  │  courses, questions,     │  │  (Local → S3)    │              │               │
│  │  attempts, readiness,    │  │                  │              │               │
│  │  schedules, OCR pages    │  │  uploads/        │              │               │
│  └──────────────────────────┘  └──────────────────┘              │               │
└──────────────────────────────────────────────────────────────────┼───────────────┘
                                                                    │
                                    ┌───────────────────────────────┘
                                    ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                           INTERACTOR PLATFORM (External)                          │
│                                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐    │
│  │  Account Server   │  │  Interactor Core │  │  Billing Server              │    │
│  │  (auth.interactor │  │  (core.interactor│  │  (billing.interactor.com)    │    │
│  │   .com)           │  │   .com)          │  │                              │    │
│  │                   │  │                  │  │  - Per-student usage         │    │
│  │  - OAuth 2.0/OIDC │  │  - AI Agents     │  │  - Token consumption        │    │
│  │  - JWT (RS256)    │  │  - Workflows     │  │  - Allocation tracking      │    │
│  │  - JWKS endpoint  │  │  - Credentials   │  └──────────────────────────────┘    │
│  │  - User mgmt      │  │  - Webhooks/SSE  │                                     │
│  │  - Social login    │  │  - Data Sources  │  ┌──────────────────────────────┐    │
│  │  - Admin JWT tier  │  │  - User Profiles  │  │  User Knowledge Base (UKB)   │    │
│  │  - User metadata   │  │  - UKB            │  │  Hobby + curriculum domain   │    │
│  └──────────────────┘  │  - UDB            │  │  knowledge (port 4005)       │    │
│                         └──────────────────┘  └──────────────────────────────┘    │
│                                                                                   │
│                                               ┌──────────────────────────────┐    │
│                                               │  User Database (UDB)         │    │
│                                               │  Dynamic tables, per-user    │    │
│                                               │  isolation, NL queries       │    │
│                                               │  (port 4007)                 │    │
│                                               └──────────────────────────────┘    │
└───────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                           EXTERNAL SERVICES                                       │
│                                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐                │
│  │  Google Cloud     │  │  YouTube API     │  │  Google Docs API │                │
│  │  Vision (OCR)     │  │  (video search)  │  │  (export)        │                │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘                │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Technology Stack Summary

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.15+ |
| Framework | Phoenix 1.7+ |
| Frontend | Phoenix LiveView, TailwindCSS |
| Database | PostgreSQL with Ecto |
| Real-time | LiveView (WebSocket), Phoenix PubSub |
| Background Jobs | Oban |
| OCR | Google Cloud Vision API |
| AI/Agents | Interactor Core AI Agents API |
| Workflows | Interactor Core Workflows API |
| Auth (End Users) | Interactor Account Server — User JWT via OAuth 2.0 / OIDC |
| Auth (Admins) | Interactor Account Server — Admin JWT tier (separate portal) |
| Knowledge Base | Interactor UKB (port 4005) — hobby + curriculum domain knowledge |
| User Database | Interactor UDB (port 4007) — dynamic tables, NL queries over student data |
| Credentials | Interactor Core Credential Management |
| File Storage | Local filesystem (Phase 1), AWS S3 (Phase 2) |

---

## 2. Component Architecture

### 2.1 Phoenix Web Layer (LiveView)

All user-facing interactions happen through LiveView. No separate REST API is exposed in Phase 1. Users are routed to role-appropriate views after login based on `metadata.role`.

| LiveView Module | Role(s) | Responsibility |
|-----------------|---------|----------------|
| `StudentProfileLive` | student | Multi-stage profile setup (demographics, hobbies, material upload) |
| `CourseBrowseLive` | student | Browse existing courses, confirm matches, or trigger new course creation |
| `CourseDetailLive` | student | View course structure (chapters, sections), manage uploaded materials |
| `AssessmentLive` | student | Adaptive testing UI: question display, answer submission, real-time evaluation |
| `QuickTestLive` | student | Mobile card-swipe interface ("Tinder for studying") |
| `ReadinessDashboardLive` | student | Test readiness scores per chapter/topic, upcoming test countdown |
| `PracticeTestLive` | student | Practice tests focused on weak areas, repetitive test-learn cycle |
| `TestFormatLive` | student | Upload test format, view format-matched practice tests, timed test mode |
| `StudyGuideLive` | student | View generated study guides, export to PDF/Google Docs |
| `ScheduleLive` | student | Manage upcoming test dates, view countdowns, receive notifications |
| `ParentDashboardLive` | parent | Children list with per-child readiness overview and study progress |
| `ParentChildDetailLive` | parent | Per-child readiness scores, study guides, assessment history |
| `TeacherDashboardLive` | teacher | Class student list with aggregate readiness and study metrics |
| `TeacherClassReportLive` | teacher | Class-level reports: topic gaps, readiness distribution, student rankings |
| `GuardianInviteLive` | student | Accept/reject guardian (parent/teacher) link requests |
| `AdminDashboardLive` | admin | Platform admin: user management, system metrics (separate admin portal) |

### 2.2 Contexts (Business Logic)

Each context encapsulates a bounded domain. Contexts never call each other's internal functions directly; they communicate through their public API.

```
lib/fun_sheep/
├── accounts/                   # User profiles, role management, guardian relationships
│   ├── accounts.ex             # Context module
│   ├── student.ex              # Student schema
│   ├── user_role.ex            # Role schema (student/parent/teacher per user)
│   └── student_guardian.ex     # Parent/teacher → student relationship schema
│
├── courses/                    # Subjects, chapters, sections, course matching
│   ├── courses.ex
│   ├── course.ex
│   ├── chapter.ex
│   └── school.ex
│
├── questions/                  # Question bank, extraction, generation, tagging
│   ├── questions.ex
│   ├── question.ex
│   └── question_attempt.ex
│
├── assessments/                # Test scopes, schedules, adaptive state, history
│   ├── assessments.ex
│   ├── test_schedule.ex
│   ├── test_format_template.ex
│   └── assessment_session.ex
│
├── readiness/                  # Test readiness scoring
│   ├── readiness.ex
│   ├── readiness_score.ex
│   └── scoring_engine.ex
│
├── content/                    # Uploaded materials, OCR results
│   ├── content.ex
│   ├── uploaded_material.ex
│   └── ocr_page.ex
│
├── hobbies/                    # Hobby discovery, preferences
│   ├── hobbies.ex
│   ├── hobby.ex
│   └── student_hobby.ex
│
├── export/                     # PDF/Google Docs export
│   └── export.ex
│
└── study_guides/               # Generated study guides
    ├── study_guides.ex
    └── study_guide.ex
```

#### Context Responsibilities

**`Accounts`** -- User profile and role management. Authentication is fully delegated to Interactor Account Server. This context stores the local `student` record that maps to `external_user_id` in Interactor. Holds demographic data (country, state, district, school, grade, gender, nationality). Manages user roles (`user_roles` table: student, parent, teacher) and guardian relationships (`student_guardians` table: parent/teacher linked to students with invite/accept flow). Provides functions for role queries (`get_role/1`, `list_students_for_guardian/1`, `list_guardians_for_student/1`) and relationship lifecycle (`invite_guardian/2`, `accept_guardian/2`, `revoke_guardian/2`).

**`Courses`** -- Course lifecycle: creation, matching existing courses, chapter/section structure. Links to a `school` for per-school question filtering. Stores chapter hierarchy as ordered records with sub-chapter support.

**`Questions`** -- Central question bank. Each question is tagged with chapter, school, source URL, source page, type, and whether it was extracted or AI-generated. Tracks hobby context used in generation. Never exposes copyrighted questions directly; derivative questions are stored separately.

**`Assessments`** -- Manages test scheduling, scoping (which chapters/topics), format templates (uploaded test formats), and the adaptive testing state machine (current topic, difficulty level, questions asked). Records every answer attempt with timestamp.

**`Readiness`** -- Computes and stores readiness scores. Aggregate score is broken down per chapter and per topic. Scores update in real-time as assessment answers arrive. Provides the "Am I ready?" signal.

**`Content`** -- Handles uploaded materials (PDFs, images, notes). Manages the OCR pipeline status. Stores extracted text, bounding boxes, and image references per page. Provides the text chunks that are sent to Interactor AI agents for question extraction.

**`Hobbies`** -- Manages hobby discovery (based on demographics), hobby domain knowledge storage, and student preference selection. Feeds hobby context into question generation for personalized questions.

**`Export`** -- Generates PDF and Google Docs output from study guides and readiness data. Uses Interactor Credential Management for Google OAuth tokens.

**`StudyGuides`** -- Stores AI-generated study guides per test schedule. Each guide contains structured content pointing to weak topics and their associated textbook pages.

### 2.3 Interactor Integration Layer

This layer encapsulates all communication with Interactor platform services. Each module handles authentication, request formatting, and response parsing for its service domain.

```
lib/fun_sheep/interactor/
├── auth.ex                     # OAuth/OIDC with Account Server (User JWT + Admin JWT)
├── token_cache.ex              # GenServer: caches App JWT, auto-refreshes
├── agents.ex                   # AI Agent management (assistants, rooms, messages)
├── workflows.ex                # Workflow definitions and instance management
├── credentials.ex              # External service credential management
├── webhooks.ex                 # Webhook event processing
├── profiles.ex                 # User Profiles API (student preferences)
├── knowledge_base.ex           # User Knowledge Base — hobby + curriculum domain data (port 4005)
├── user_database.ex            # User Database — dynamic tables, NL queries (port 4007)
├── billing.ex                  # Usage tracking per student
└── client.ex                   # Shared HTTP client (Tesla/Req)
```

#### Integration Module Details

**`Interactor.Auth`** -- Implements OAuth 2.0 Authorization Code flow for all end-user login (students, parents, teachers). Redirects users to Account Server's hosted login page. Handles the callback, exchanges authorization code for JWT tokens, and verifies JWTs via the JWKS endpoint (`/.well-known/jwks.json`). Extracts `metadata.role` from the JWT/userinfo to determine the user's role. Also supports Admin JWT tier for platform administrators via separate `/api/v1/admin/login` endpoint. Manages App JWT via client credentials grant for machine-to-machine API calls.

**`Interactor.TokenCache`** -- GenServer that caches the App JWT (client credentials token). Tokens expire after 15 minutes; this process refreshes them proactively before expiry to avoid 401 errors on API calls.

**`Interactor.Agents`** -- Manages the 9 AI agents (see section 3). Creates and configures assistants, opens rooms per student session, sends messages, handles tool callback dispatching, and processes streaming responses.

**`Interactor.Workflows`** -- Creates and manages workflow definitions (course creation, adaptive assessment, test format replication). Starts workflow instances, resumes halted states (human-in-the-loop), and processes state transitions.

**`Interactor.Credentials`** -- Manages OAuth credentials for external services (Google OAuth for Docs export, YouTube API). Credentials are stored per `external_user_id` in Interactor with automatic token refresh.

**`Interactor.Webhooks`** -- Receives and validates webhook events from Interactor (agent responses, workflow state changes, credential status). Routes events to the appropriate context handler.

**`Interactor.Profiles`** -- Stores and retrieves student preferences (grade, school, nationality, hobbies, learning preferences) via Interactor's User Profiles API, keyed by `external_user_id`.

**`Interactor.KnowledgeBase`** -- Manages domain knowledge in Interactor's User Knowledge Base (UKB, port 4005). Stores and retrieves two categories of knowledge via semantic search: (1) Hobby domain knowledge -- when a hobby like "KPOP" is discovered, relevant factual data (member names, group details, common scenarios) is stored so agents can use it for personalized questions. (2) Curriculum/subject knowledge -- course syllabi, topic taxonomies, and reference material summaries are stored so agents can generate curriculum-aligned content.

**`Interactor.UserDatabase`** -- Integrates with Interactor's User Database service (UDB, port 4007). Registers FunSheep's PostgreSQL as a Data Source so that AI agents can query student data (readiness scores, assessment history, study progress) via natural language. Manages table registration, schema mapping, and per-user data isolation so agents only access data for the student they are serving.

**`Interactor.Billing`** -- Tracks AI token consumption per student via `external_user_id` allocations. Reports usage to Interactor's Billing Server.

**`Interactor.Client`** -- Shared HTTP client with middleware for authentication header injection, request logging, error handling, and retry logic.

---

## 3. Interactor AI Agent Architecture

### 3.1 Agent Overview

FunSheep uses 9 Interactor AI agents organized in an orchestrator-delegate pattern.

```
                        ┌───────────────────────────┐
                        │  FunSheep Orchestrator   │
                        │  (Primary Assistant)       │
                        │                            │
                        │  Routes tasks to the       │
                        │  appropriate specialist    │
                        └─────────────┬─────────────┘
                                      │
            ┌────────┬────────┬───────┼───────┬────────┬────────┬────────┐
            ▼        ▼        ▼       ▼       ▼        ▼        ▼        ▼
       ┌─────────┐┌─────────┐┌──────────┐┌─────────┐┌─────────┐┌──────────┐┌──────────┐┌──────────┐
       │ Hobby   ││ Content ││ Question ││ Assess- ││ Study   ││ Question ││ Answer   ││ Question │
       │Discovery││Discovery││ Extract- ││ ment    ││ Guide   ││ Creator  ││ Creator  ││ Validator│
       │ Agent   ││ Agent   ││ ion Agent││ Eval.   ││ Gen.    ││          ││          ││          │
       └─────────┘└─────────┘└──────────┘└─────────┘└─────────┘└──────────┘└──────────┘└──────────┘

       |-- Discovery Phase --|--- Content Processing --|-- Assessment --|--- Question Generation ---|
```

### 3.2 Agent Definitions

Each agent is registered as an Interactor Assistant with a specific system prompt, LLM model, and set of tools.

| Agent | Purpose | Key Tools | LLM Model |
|-------|---------|-----------|-----------|
| **Orchestrator** | Routes student requests to appropriate specialist agents | `delegate_to_agent`, `get_student_context` | gpt-4o |
| **Hobby Discovery** | Discovers relevant hobbies based on demographics; stores in UKB | `search_hobbies`, `store_hobby_knowledge` | gpt-4o |
| **Content Discovery** | Searches online for questions, videos, lessons for a course | `web_search`, `youtube_search`, `evaluate_content` | gpt-4o |
| **Question Extraction** | Extracts questions from OCR-processed text chunks | `parse_ocr_text`, `classify_question`, `store_question` | gpt-4o |
| **Assessment Evaluator** | Evaluates student answers, determines next difficulty level | `evaluate_answer`, `get_topic_progress`, `adjust_difficulty` | gpt-4o |
| **Study Guide Generator** | Analyzes weakness data and generates targeted study guides | `get_readiness_data`, `find_reference_pages`, `generate_guide` | gpt-4o |
| **Question Creator** | Creates derivative/personalized questions with hobby context | `get_source_question`, `get_hobby_context`, `create_derivative` | gpt-4o |
| **Answer Creator** | Independently solves generated questions to produce answers | `solve_question`, `show_work` | gpt-4o |
| **Question Validator** | Cross-checks question, answer, and source for correctness | `validate_answer`, `check_source_consistency`, `approve_or_reject` | gpt-4o |

### 3.3 Multi-Agent Question Validation Pipeline

All AI-generated questions pass through a three-stage validation pipeline before being stored:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Question Creator │────>│  Answer Creator   │────>│  Question        │
│                   │     │                   │     │  Validator       │
│  Creates question │     │  Independently    │     │                  │
│  with modified    │     │  solves the       │     │  Cross-checks:   │
│  numbers/words +  │     │  question (no     │     │  - Q matches     │
│  hobby context    │     │  access to        │     │    source intent │
│                   │     │  intended answer)  │     │  - A is correct  │
│  Output: question │     │                   │     │  - No copyright  │
│  + intended answer│     │  Output: computed  │     │    violation     │
│                   │     │  answer + work     │     │                  │
└──────────────────┘     └──────────────────┘     │  Output: PASS or │
                                                    │  FAIL + reason   │
                                                    └──────────────────┘
                                                             │
                                                    ┌────────┴────────┐
                                                    ▼                 ▼
                                              ┌──────────┐    ┌───────────┐
                                              │   PASS   │    │   FAIL    │
                                              │ Store in │    │ Log error │
                                              │ question │    │ Never     │
                                              │ bank     │    │ show to   │
                                              └──────────┘    │ student   │
                                                              └───────────┘
```

### 3.4 Tool Callbacks

Interactor agents invoke tools that callback to FunSheep's backend. These are POST endpoints that the agents call during execution.

```
POST /api/tools/callback/parse_ocr_text       → Content context
POST /api/tools/callback/store_question        → Questions context
POST /api/tools/callback/classify_question     → Questions context
POST /api/tools/callback/get_student_context   → Accounts + Hobbies contexts
POST /api/tools/callback/evaluate_answer       → Assessments context
POST /api/tools/callback/get_readiness_data    → Readiness context
POST /api/tools/callback/get_topic_progress    → Readiness context
POST /api/tools/callback/find_reference_pages  → Content context
POST /api/tools/callback/get_source_question   → Questions context
POST /api/tools/callback/get_hobby_context     → Hobbies + Interactor.KnowledgeBase
POST /api/tools/callback/validate_answer       → Questions context
POST /api/tools/callback/approve_or_reject     → Questions context
```

These endpoints are authenticated using the Interactor webhook signature mechanism.

---

## 4. Interactor Workflows

### 4.1 Course Creation Workflow

Models the multi-step process of creating a new course.

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  setup       │────>│ content_discovery │────>│ question_        │
│  (action)    │     │ (action)          │     │ extraction       │
│              │     │                   │     │ (action)         │
│  Validate    │     │  Content          │     │                  │
│  student     │     │  Discovery Agent  │     │  Question        │
│  input,      │     │  searches for     │     │  Extraction      │
│  create      │     │  materials,       │     │  Agent processes │
│  course      │     │  videos,          │     │  OCR text        │
│  record      │     │  existing Qs      │     │                  │
└──────────────┘     └──────────────────┘     └────────┬─────────┘
                                                        │
                                                        ▼
                     ┌──────────────────┐     ┌──────────────────┐
                     │  review          │<────│ classification   │
                     │  (halting)       │     │ (action)         │
                     │                  │     │                  │
                     │  Present         │     │  Classify Qs     │
                     │  results to      │     │  by chapter/     │
                     │  student for     │     │  section/topic,  │
                     │  confirmation    │     │  tag per school  │
                     │                  │     │                  │
                     └────────┬─────────┘     └──────────────────┘
                              │
                              ▼
                     ┌──────────────────┐
                     │  complete        │
                     │  (terminal)      │
                     │                  │
                     │  Course ready    │
                     │  for assessment  │
                     └──────────────────┘
```

**Workflow Definition:**

```json
{
  "name": "course_creation",
  "input_schema": {
    "type": "object",
    "properties": {
      "student_id": { "type": "string" },
      "course_id": { "type": "string" },
      "subject": { "type": "string" },
      "grade": { "type": "string" },
      "school_id": { "type": "string" }
    },
    "required": ["student_id", "course_id", "subject", "grade"]
  },
  "initial_state": "setup",
  "states": {
    "setup": { "type": "action" },
    "content_discovery": { "type": "action" },
    "question_extraction": { "type": "action" },
    "classification": { "type": "action" },
    "review": { "type": "halting" },
    "complete": { "type": "terminal" }
  }
}
```

### 4.2 Adaptive Assessment Workflow

Models the adaptive testing loop that identifies knowledge gaps.

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  set_scope   │────>│  ask_questions   │────>│  evaluate        │
│  (action)    │     │  (halting)       │     │  (action)        │
│              │     │                  │     │                  │
│  Load test   │     │  Present 3+      │     │  Assessment      │
│  schedule,   │     │  questions on    │     │  Evaluator       │
│  determine   │     │  current topic,  │     │  Agent grades    │
│  chapters    │     │  wait for        │     │  answers,        │
│  and topics  │     │  student answers │     │  determines      │
│              │     │                  │     │  mastery level   │
└──────────────┘     └──────────────────┘     └────────┬─────────┘
                              ▲                         │
                              │         ┌───────────────┼───────────────┐
                              │         ▼               ▼               ▼
                              │   ┌───────────┐  ┌───────────┐  ┌───────────┐
                              │   │ increase  │  │ repeat    │  │ next      │
                              │   │ difficulty│  │ topic     │  │ topic     │
                              │   │ (action)  │  │ (action)  │  │ (action)  │
                              │   │           │  │           │  │           │
                              │   │ Student   │  │ Student   │  │ Student   │
                              │   │ got all   │  │ got some  │  │ mastered  │
                              │   │ correct   │  │ wrong,    │  │ topic,    │
                              │   │ → harder  │  │ re-test   │  │ move on   │
                              │   │ questions │  │ with      │  │           │
                              │   │           │  │ variants  │  │           │
                              │   └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
                              │         └──────────────┬┘               │
                              │                        │                │
                              └────────────────────────┘                │
                                    (more topics left)                  │
                                                                        │
                                                          ┌─────────────┘
                                                          ▼ (all topics done)
                                                 ┌──────────────────┐
                                                 │ generate_report  │
                                                 │ (terminal)       │
                                                 │                  │
                                                 │ Study Guide Gen. │
                                                 │ Agent creates    │
                                                 │ readiness report │
                                                 │ + study guide    │
                                                 └──────────────────┘
```

### 4.3 Test Format Replication Workflow

Generates practice tests matching a student's uploaded exam format.

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  upload_format   │────>│  analyze_format  │────>│  generate_test   │
│  (halting)       │     │  (action)        │     │  (action)        │
│                  │     │                  │     │                  │
│  Student uploads │     │  AI analyzes:    │     │  Select/generate │
│  test sample     │     │  sections, Q     │     │  questions per   │
│  from school     │     │  types, counts,  │     │  format template │
│                  │     │  point dist.,    │     │  from test scope │
│                  │     │  time limits     │     │  topics          │
└──────────────────┘     └──────────────────┘     └────────┬─────────┘
                                                            │
                                                            ▼
                                                   ┌──────────────────┐
                                                   │  validate_test   │
                                                   │  (action)        │
                                                   │                  │
                                                   │  Multi-agent     │
                                                   │  validation on   │
                                                   │  all generated   │
                                                   │  questions       │
                                                   └────────┬─────────┘
                                                            │
                                                            ▼
                                                   ┌──────────────────┐
                                                   │  ready           │
                                                   │  (terminal)      │
                                                   │                  │
                                                   │  Practice test   │
                                                   │  stored and      │
                                                   │  available       │
                                                   └──────────────────┘
```

---

## 5. Data Model

### 5.1 Entity-Relationship Diagram

```
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│   schools    │       │   students   │       │   hobbies    │
│──────────────│       │──────────────│       │──────────────│
│ id (PK)      │       │ id (PK)      │       │ id (PK)      │
│ name         │◄──┐   │ ext_user_id  │   ┌──>│ name         │
│ country      │   │   │ school_id(FK)│───┘   │ category     │
│ state        │   │   │ name         │       │ region_rel.  │
│ district     │   │   │ grade        │       └──────┬───────┘
└──────────────┘   │   │ gender       │              │
       ▲           │   │ nationality  │    ┌─────────┴────────┐
       │           │   └──────┬───────┘    │ student_hobbies  │
       │           │          │            │──────────────────│
       │           │          │            │ student_id (FK)  │
       │           │          │            │ hobby_id (FK)    │
       │           │          │            │ specific_interests│
       │           │          │            └──────────────────┘
       │           │          │
┌──────┴───────┐   │   ┌──────┴────────────┐
│  user_roles  │   │   │ student_guardians │
│──────────────│   │   │──────────────────│
│ id (PK)      │   │   │ id (PK)          │
│ user_id      │   │   │ guardian_id      │ ← parent/teacher ext_user_id
│ role (enum)  │   │   │ student_id (FK)  │
│ school_id(FK)│───┘   │ relationship_type│ ← parent | teacher
└──────────────┘       │ status           │ ← pending | active
                       │ invited_at       │
                       │ accepted_at      │
                       └──────────────────┘
                   │          │
                   │   ┌──────┴───────────────────────────────────────┐
                   │   │                                              │
              ┌────┴───┴──────┐                              ┌────────┴────────┐
              │   courses     │                              │ uploaded_       │
              │───────────────│                              │ materials      │
              │ id (PK)       │                              │────────────────│
              │ subject       │                              │ id (PK)        │
              │ grade         │                              │ student_id(FK) │
              │ school_id(FK) │                              │ course_id (FK) │
              │ chapter_struct│                              │ file_path      │
              └───────┬───────┘                              │ ocr_status     │
                      │                                      └────────┬───────┘
                      │                                               │
              ┌───────┴───────┐                              ┌────────┴───────┐
              │   chapters    │                              │   ocr_pages    │
              │───────────────│                              │────────────────│
              │ id (PK)       │                              │ id (PK)        │
              │ course_id(FK) │                              │ material_id(FK)│
              │ name          │                              │ page_number    │
              │ order         │                              │ extracted_text │
              │ parent_id(FK) │                              │ bounding_boxes │
              └───────┬───────┘                              │ images (JSON)  │
                      │                                      └────────────────┘
              ┌───────┴───────┐
              │   questions   │         ┌──────────────────────┐
              │───────────────│         │  question_attempts   │
              │ id (PK)       │         │──────────────────────│
              │ content       │◄────────│ id (PK)              │
              │ answer        │         │ student_id (FK)      │
              │ type          │         │ question_id (FK)     │
              │ chapter_id(FK)│         │ correct (bool)       │
              │ school_id(FK) │         │ answer_given         │
              │ source_url    │         │ inserted_at          │
              │ source_page   │         └──────────────────────┘
              │ is_generated  │
              │ hobby_context │
              └───────────────┘


┌──────────────────────┐       ┌──────────────────────┐
│   test_schedules     │       │ test_format_templates │
│──────────────────────│       │──────────────────────│
│ id (PK)              │       │ id (PK)              │
│ student_id (FK)      │──┐    │ structure (JSON)     │
│ course_id (FK)       │  │    │  - sections          │
│ test_date            │  │    │  - question_types    │
│ scope (JSON)         │  │    │  - counts            │
│ format_template_id   │──┼───>│  - time_limit        │
│                      │  │    └──────────────────────┘
└──────────┬───────────┘  │
           │              │    ┌──────────────────────┐
           │              │    │   study_guides       │
           │              │    │──────────────────────│
           │              ├───>│ id (PK)              │
           │              │    │ student_id (FK)      │
           │              │    │ test_schedule_id(FK) │
           │              │    │ content (JSON)       │
           │              │    │ generated_at         │
           │              │    └──────────────────────┘
           │
           ▼
┌──────────────────────┐
│   readiness_scores   │
│──────────────────────│
│ id (PK)              │
│ student_id (FK)      │
│ test_schedule_id(FK) │
│ chapter_scores(JSON) │
│ topic_scores (JSON)  │
│ aggregate_score      │
└──────────────────────┘
```

### 5.2 Table Definitions

#### `students`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Internal ID |
| `external_user_id` | `string` | unique, not null | Interactor Account Server user ID |
| `school_id` | `binary_id` | FK → schools | Student's school |
| `name` | `string` | not null | Display name |
| `grade` | `string` | not null | Grade level |
| `gender` | `string` | | Gender |
| `nationality` | `string` | | Nationality |
| `inserted_at` | `utc_datetime` | not null | Created at |
| `updated_at` | `utc_datetime` | not null | Updated at |

#### `schools`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `name` | `string` | not null | School name |
| `country` | `string` | not null | Country |
| `state` | `string` | | State/province |
| `district` | `string` | | District |

#### `courses`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `subject` | `string` | not null | e.g., "AP Biology" |
| `grade` | `string` | not null | Grade level |
| `school_id` | `binary_id` | FK → schools | School association |
| `chapter_structure` | `json` | | Denormalized chapter tree (for fast reads) |

#### `chapters`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `course_id` | `binary_id` | FK → courses, not null | Parent course |
| `parent_id` | `binary_id` | FK → chapters, nullable | For sub-chapters |
| `name` | `string` | not null | Chapter title |
| `order` | `integer` | not null | Display order |

#### `questions`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `content` | `text` | not null | Question text (may include image refs) |
| `answer` | `text` | not null | Correct answer |
| `type` | `string` | not null | `multiple_choice`, `short_answer`, `essay`, `true_false` |
| `chapter_id` | `binary_id` | FK → chapters | Chapter/topic tag |
| `school_id` | `binary_id` | FK → schools, nullable | Per-school tagging |
| `source_url` | `string` | nullable | Where the question came from |
| `source_page` | `integer` | nullable | Page number in source material |
| `is_generated` | `boolean` | default false | AI-generated derivative? |
| `hobby_context` | `string` | nullable | Hobby used for personalization |
| `difficulty` | `integer` | 1-5 | Difficulty level |

#### `question_attempts`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `student_id` | `binary_id` | FK → students, not null | |
| `question_id` | `binary_id` | FK → questions, not null | |
| `correct` | `boolean` | not null | Was the answer correct? |
| `answer_given` | `text` | | Student's actual answer |
| `inserted_at` | `utc_datetime` | not null | When the attempt was made |

#### `uploaded_materials`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `student_id` | `binary_id` | FK → students, not null | Who uploaded it |
| `course_id` | `binary_id` | FK → courses, not null | Associated course |
| `file_path` | `string` | not null | Storage path (local or S3 key) |
| `original_filename` | `string` | not null | Original upload name |
| `content_type` | `string` | not null | MIME type |
| `ocr_status` | `string` | not null, default "pending" | `pending`, `processing`, `completed`, `failed` |

#### `ocr_pages`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `material_id` | `binary_id` | FK → uploaded_materials, not null | Source material |
| `page_number` | `integer` | not null | Page in source document |
| `extracted_text` | `text` | | Raw OCR text output |
| `bounding_boxes` | `json` | | Position metadata for text regions |
| `images` | `json` | | Extracted image references with positions |

#### `test_schedules`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `student_id` | `binary_id` | FK → students, not null | |
| `course_id` | `binary_id` | FK → courses, not null | |
| `test_date` | `date` | not null | When the real test is |
| `scope` | `json` | not null | `{"chapter_ids": [...], "topic_ids": [...]}` |
| `format_template_id` | `binary_id` | FK → test_format_templates, nullable | |

#### `test_format_templates`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `structure` | `json` | not null | `{"sections": [...], "question_types": [...], "counts": {...}, "time_limit": 3600}` |
| `source_material_id` | `binary_id` | FK → uploaded_materials, nullable | Uploaded format sample |

#### `readiness_scores`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `student_id` | `binary_id` | FK → students, not null | |
| `test_schedule_id` | `binary_id` | FK → test_schedules, not null | |
| `chapter_scores` | `json` | not null | `{"ch_id_1": 85, "ch_id_2": 62}` |
| `topic_scores` | `json` | not null | `{"topic_1": 90, "topic_2": 45}` |
| `aggregate_score` | `float` | not null | Weighted overall score (0-100) |
| `updated_at` | `utc_datetime` | not null | Last recalculation |

#### `study_guides`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `student_id` | `binary_id` | FK → students, not null | |
| `test_schedule_id` | `binary_id` | FK → test_schedules, not null | |
| `content` | `json` | not null | Structured guide: weak topics, reference pages, recommendations |
| `generated_at` | `utc_datetime` | not null | |

#### `hobbies`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK | |
| `name` | `string` | not null, unique | e.g., "KPOP", "Basketball" |
| `category` | `string` | not null | e.g., "Music", "Sports" |
| `region_relevance` | `json` | | `{"countries": ["KR", "US"], "age_range": [13, 18]}` |

#### `student_hobbies`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `student_id` | `binary_id` | FK → students, PK | |
| `hobby_id` | `binary_id` | FK → hobbies, PK | |
| `specific_interests` | `json` | | `{"favorite_groups": ["BTS"], "favorite_members": ["JongKuk"]}` |

#### `user_roles`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Internal ID |
| `user_id` | `string` | not null, unique | Interactor Account Server user ID (`external_user_id`) |
| `role` | `string` | not null, enum: `student`, `parent`, `teacher` | User's role in FunSheep. Stored in Interactor `metadata.role` and mirrored locally. |
| `school_id` | `binary_id` | FK → schools, nullable | Associated school (for teachers; optional for parents) |
| `inserted_at` | `utc_datetime` | not null | Created at |
| `updated_at` | `utc_datetime` | not null | Updated at |

#### `student_guardians`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | `binary_id` | PK, auto-generated | Internal ID |
| `guardian_id` | `string` | not null | Interactor user ID of the parent or teacher |
| `student_id` | `binary_id` | FK → students, not null | The student being supervised |
| `relationship_type` | `string` | not null, enum: `parent`, `teacher` | Type of guardian relationship |
| `status` | `string` | not null, default `pending`, enum: `pending`, `active` | Invite status; becomes `active` when student accepts |
| `invited_at` | `utc_datetime` | not null | When the invitation was sent |
| `accepted_at` | `utc_datetime` | nullable | When the student accepted the link |

---

## 6. Authentication Flow

FunSheep uses Interactor Account Server as its identity provider. There are two authentication tiers:

1. **End Users (student, parent, teacher)** -- All use the same OAuth 2.0 Authorization Code flow via Interactor User JWT. A single login page serves all roles. After login, the user's `metadata.role` determines what they see.
2. **Platform Admins** -- Use Interactor Admin JWT tier via a separate admin portal at `/admin`. Admins log in via `/api/v1/admin/login` and receive Admin-tier JWTs with elevated privileges.

Users never create credentials in FunSheep directly. Role is stored in Interactor user `metadata.role` (values: `"student"`, `"parent"`, `"teacher"`). Role enforcement happens at the FunSheep application layer via Phoenix Plugs.

### 6.1 End-User Login Flow (Student / Parent / Teacher)

```
┌──────────┐       ┌──────────────────┐       ┌──────────────────────┐
│  User     │       │  FunSheep      │       │  Interactor Account  │
│  Browser  │       │  Phoenix App     │       │  Server              │
└─────┬─────┘       └────────┬─────────┘       └──────────┬───────────┘
      │                      │                             │
      │  1. Click "Login"    │                             │
      │─────────────────────>│                             │
      │                      │                             │
      │  2. 302 Redirect to Account Server                │
      │<─────────────────────│                             │
      │  Location: https://auth.interactor.com/oauth/     │
      │  authorize?client_id=...&redirect_uri=...&        │
      │  response_type=code&scope=openid profile email    │
      │                      │                             │
      │  3. Follow redirect  │                             │
      │────────────────────────────────────────────────────>│
      │                      │                             │
      │  4. Login page       │                             │
      │<────────────────────────────────────────────────────│
      │                      │                             │
      │  5. Submit credentials (or social login)           │
      │────────────────────────────────────────────────────>│
      │                      │                             │
      │  6. 302 Redirect to callback with auth code        │
      │<────────────────────────────────────────────────────│
      │  Location: https://studysmart.com/auth/callback?   │
      │  code=AUTH_CODE_123                                │
      │                      │                             │
      │  7. Follow redirect  │                             │
      │─────────────────────>│                             │
      │                      │  8. Exchange code for tokens│
      │                      │─────────────────────────────>│
      │                      │  POST /oauth/token           │
      │                      │  {grant_type: authorization_ │
      │                      │   code, code: AUTH_CODE_123,  │
      │                      │   client_id, client_secret,   │
      │                      │   redirect_uri}               │
      │                      │                             │
      │                      │  9. JWT tokens               │
      │                      │<─────────────────────────────│
      │                      │  {access_token, refresh_token,│
      │                      │   id_token, expires_in}       │
      │                      │                             │
      │                      │  10. Verify JWT via JWKS    │
      │                      │─────────────────────────────>│
      │                      │  GET /.well-known/jwks.json  │
      │                      │<─────────────────────────────│
      │                      │                             │
      │                      │  11. Extract user info +     │
      │                      │  metadata.role from JWT,     │
      │                      │  find/create local user      │
      │                      │  record + user_role,         │
      │                      │  create Phoenix session      │
      │                      │                             │
      │  12. Redirect based on role:                       │
      │    student → /dashboard                            │
      │    parent  → /parent/children                      │
      │    teacher → /teacher/classes                      │
      │<─────────────────────│                             │
      │  Set-Cookie: session  │                             │
      │                      │                             │
```

### 6.1.1 Admin Login Flow (Separate Portal)

```
┌──────────┐       ┌──────────────────┐       ┌──────────────────────┐
│  Admin    │       │  FunSheep      │       │  Interactor Account  │
│  Browser  │       │  Admin Portal    │       │  Server              │
└─────┬─────┘       └────────┬─────────┘       └──────────┬───────────┘
      │                      │                             │
      │  1. Visit /admin     │                             │
      │─────────────────────>│                             │
      │                      │                             │
      │  2. Admin login form │                             │
      │<─────────────────────│                             │
      │                      │                             │
      │  3. Submit admin     │                             │
      │  credentials         │                             │
      │─────────────────────>│                             │
      │                      │  4. POST /api/v1/admin/login│
      │                      │─────────────────────────────>│
      │                      │                             │
      │                      │  5. Admin JWT               │
      │                      │<─────────────────────────────│
      │                      │  (Admin-tier token with     │
      │                      │   elevated privileges)       │
      │                      │                             │
      │  6. Redirect to      │                             │
      │  /admin/dashboard    │                             │
      │<─────────────────────│                             │
      │                      │                             │
```

### 6.1.2 Role Enforcement via Phoenix Plugs

```elixir
# RequireRole plug — checks metadata.role on every request
plug FunSheep.Auth.RequireRole, role: :student   # Only students
plug FunSheep.Auth.RequireRole, role: :parent     # Only parents
plug FunSheep.Auth.RequireRole, role: :teacher    # Only teachers
plug FunSheep.Auth.RequireRole, role: [:parent, :teacher]  # Either

# RequireGuardian plug — verifies parent/teacher has active link to student
plug FunSheep.Auth.RequireGuardian, student_param: :student_id
```

Role enforcement rules:
- `metadata.role` is read from the Interactor JWT userinfo and cached in the Phoenix session
- The `RequireRole` plug checks the session role on every request and returns 403 if mismatched
- The `RequireGuardian` plug verifies that the current user has an `active` record in `student_guardians` for the requested student
- Admin routes use a separate pipeline that verifies Admin-tier JWTs (different signing key and claims)

### 6.2 Machine-to-Machine Authentication (App JWT)

For backend API calls to Interactor Core (agents, workflows, credentials), FunSheep uses the OAuth client credentials grant.

```
┌──────────────────┐                    ┌──────────────────────┐
│  FunSheep       │                    │  Interactor Account  │
│  TokenCache       │                    │  Server              │
│  (GenServer)      │                    │                      │
└────────┬─────────┘                    └──────────┬───────────┘
         │                                          │
         │  POST /oauth/token                       │
         │  {grant_type: client_credentials,         │
         │   client_id, client_secret}               │
         │─────────────────────────────────────────>│
         │                                          │
         │  {access_token: "eyJ...", expires_in: 900}│
         │<─────────────────────────────────────────│
         │                                          │
         │  Cache token, schedule refresh           │
         │  at (expires_in - 60) seconds            │
         │                                          │
```

The `TokenCache` GenServer:
- Obtains an App JWT on startup
- Caches the token in process state
- Refreshes proactively 60 seconds before expiry (tokens last 15 minutes)
- All `Interactor.*` modules call `TokenCache.get_token/0` for their API requests

### 6.3 Session Management

| Aspect | Implementation |
|--------|----------------|
| Session storage | Server-side (ETS via Phoenix default, or database-backed) |
| Session content | `%{user_id: uuid, external_user_id: string, role: atom}` |
| Token storage | JWT tokens stored server-side only, never sent to browser |
| Session lifetime | 24 hours |
| CSRF protection | Phoenix built-in CSRF tokens |
| Role caching | `metadata.role` extracted at login and stored in session for fast plug checks |

---

## 7. File Storage Architecture

### 7.1 Storage Abstraction

A behaviour module defines the storage interface, allowing transparent swapping between local and S3 backends.

```
┌─────────────────────────────────────┐
│        FunSheep.Storage           │
│        (behaviour)                   │
│                                      │
│  @callback store(path, binary)       │
│  @callback retrieve(path)            │
│  @callback delete(path)              │
│  @callback url(path)                 │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
┌──────────────┐  ┌──────────────┐
│ LocalStorage │  │  S3Storage   │
│              │  │              │
│ priv/static/ │  │ AWS S3 via   │
│ uploads/     │  │ ExAws        │
│              │  │              │
│ Phase 1      │  │ Phase 2      │
└──────────────┘  └──────────────┘
```

**Configuration:**

```elixir
# config/dev.exs
config :fun_sheep, :storage, adapter: FunSheep.Storage.LocalStorage

# config/prod.exs (Phase 2)
config :fun_sheep, :storage, adapter: FunSheep.Storage.S3Storage
```

### 7.2 File Organization

```
priv/static/uploads/          # Phase 1 local storage root
├── materials/                 # Uploaded course materials
│   └── {student_id}/
│       └── {material_id}/
│           ├── original.*     # Original uploaded file
│           └── pages/         # Extracted page images
│               ├── page_001.png
│               └── page_002.png
└── exports/                   # Generated exports (temporary)
    └── {student_id}/
        └── {guide_id}.pdf
```

---

## 8. OCR Pipeline

### 8.1 Pipeline Flow

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Student     │     │  FunSheep       │     │  Google Cloud    │
│  uploads     │────>│  Content context  │────>│  Vision API      │
│  PDF/image   │     │                   │     │                  │
│              │     │  1. Store file    │     │  2. OCR request  │
│              │     │  2. Set status:   │     │  per page        │
│              │     │     processing    │     │                  │
└──────────────┘     └──────────────────┘     └────────┬─────────┘
                                                        │
                                                        │ 3. Returns:
                                                        │ - extracted text
                                                        │ - bounding boxes
                                                        │ - detected images
                                                        ▼
                     ┌──────────────────┐     ┌──────────────────┐
                     │  Interactor      │     │  FunSheep       │
                     │  Question        │◄────│  Content context  │
                     │  Extraction      │     │                   │
                     │  Agent           │     │  4. Store in      │
                     │                  │     │     ocr_pages     │
                     │  5. Process text │     │  5. Send chunks   │
                     │  chunks,         │     │     to agent      │
                     │  extract Qs      │     │                   │
                     └────────┬─────────┘     └──────────────────┘
                              │
                              │ 6. Tool callbacks
                              │ (store_question,
                              │  classify_question)
                              ▼
                     ┌──────────────────┐
                     │  Questions       │
                     │  context         │
                     │                  │
                     │  7. Store        │
                     │  extracted Qs    │
                     │  with chapter,   │
                     │  source_page,    │
                     │  source_url      │
                     │                  │
                     │  8. Set material │
                     │  status:         │
                     │  completed       │
                     └──────────────────┘
```

### 8.2 OCR Processing Details

| Step | Responsibility | Detail |
|------|---------------|--------|
| Upload | Content context | Accept PDF/image, store via `Storage` behaviour, create `uploaded_material` record |
| Split | Content context | Split multi-page PDFs into individual page images |
| OCR | Oban worker | Async job calls Google Cloud Vision API per page (via `FunSheep.Workers.OcrWorker`) |
| Store | Content context | Save extracted text, bounding boxes, and image references in `ocr_pages` |
| Extract | Interactor Agent | Send text chunks to Question Extraction Agent; receive questions via tool callbacks |
| Notify | PubSub | Broadcast `{:ocr_completed, material_id}` so LiveView updates in real-time |

### 8.3 Token Cost Optimization

The OCR-first approach avoids sending raw PDFs/images to the LLM:

| Approach | Estimated Cost per 100 Pages |
|----------|------|
| Send raw PDF to LLM | ~$5-15 (vision tokens) |
| OCR first, send text only | ~$1.50 (OCR) + ~$0.50 (text tokens) |

---

## 9. Real-Time Architecture

### 9.1 Communication Channels

```
┌──────────────┐         ┌──────────────────┐         ┌──────────────────┐
│   Student    │◄───────>│   FunSheep      │◄───────>│   Interactor     │
│   Browser    │ LiveView│   Phoenix App     │  HTTP/  │   Core           │
│              │WebSocket│                   │  SSE    │                  │
└──────────────┘         └──────────────────┘         └──────────────────┘
```

| Channel | Technology | Use Case |
|---------|-----------|----------|
| Browser ↔ Phoenix | LiveView (WebSocket) | All UI interactions: assessments, dashboards, card swipe |
| Interactor → Phoenix | SSE (Server-Sent Events) | Streaming AI agent responses during assessment/tutoring |
| Interactor → Phoenix | Webhooks (HTTP POST) | Async events: workflow completion, credential status |
| Internal Phoenix | PubSub | Broadcast state changes: OCR done, readiness updated, new questions |

### 9.2 Real-Time Update Flows

**Assessment Answer Processing:**

```
Student submits answer
       │
       ▼ (LiveView handle_event)
Assessments context stores attempt
       │
       ▼ (HTTP POST to Interactor)
Assessment Evaluator Agent evaluates
       │
       ▼ (SSE stream back)
Phoenix receives streamed response
       │
       ├──▶ Readiness context recalculates score
       │         │
       │         ▼ (PubSub broadcast)
       │    ReadinessDashboardLive updates
       │
       └──▶ AssessmentLive shows result + next question
```

**OCR Completion:**

```
OcrWorker finishes page processing
       │
       ▼ (PubSub broadcast: {:ocr_completed, material_id})
CourseDetailLive updates progress bar
       │
       ▼ (When all pages done)
Trigger Question Extraction Agent via Interactor
```

---

## 10. API Design

### 10.1 Phase 1 Surface Area

Phase 1 exposes no public REST API. All student interactions occur through LiveView.

| Endpoint Type | Path Pattern | Purpose |
|---------------|-------------|---------|
| **LiveView routes** | `/*` | All student-facing pages |
| **Tool callbacks** | `POST /api/tools/callback/:tool_name` | Interactor agents invoke FunSheep functions |
| **Webhook receiver** | `POST /api/webhooks/interactor` | Receive Interactor platform events |

### 10.2 Tool Callback Endpoint Design

```elixir
# Router
scope "/api/tools", FunSheepWeb.API do
  pipe_through [:api, :verify_interactor_signature]

  post "/callback/:tool_name", ToolCallbackController, :execute
end
```

The controller dispatches to the appropriate context based on `tool_name`:

| Tool Name | Context Handler | Returns |
|-----------|----------------|---------|
| `parse_ocr_text` | `Content.get_ocr_text/1` | Extracted text for a page range |
| `store_question` | `Questions.create_question/1` | Created question ID |
| `classify_question` | `Questions.update_classification/2` | Updated question |
| `get_student_context` | `Accounts.get_student_context/1` | Demographics + hobbies |
| `evaluate_answer` | `Assessments.evaluate_attempt/2` | Correctness + feedback |
| `get_readiness_data` | `Readiness.get_scores/1` | Current readiness state |
| `get_topic_progress` | `Readiness.get_topic_progress/2` | Per-topic attempt history |
| `find_reference_pages` | `Content.find_pages_for_topic/2` | Page numbers + images |
| `get_source_question` | `Questions.get_for_derivation/1` | Source question for derivation |
| `get_hobby_context` | `Hobbies.get_context_for_student/1` | Hobby details for personalization |
| `validate_answer` | `Questions.validate_generated/1` | Validation result |
| `approve_or_reject` | `Questions.approve_or_reject/2` | Final question status |

### 10.3 Webhook Receiver

```elixir
# Router
scope "/api/webhooks", FunSheepWeb.API do
  pipe_through [:api, :verify_webhook_signature]

  post "/interactor", WebhookController, :handle
end
```

Subscribed event types:

| Event | Handler Action |
|-------|---------------|
| `agent.response_sent` | Forward AI response to student's LiveView via PubSub |
| `workflow.state_changed` | Update workflow progress in UI |
| `workflow.halted` | Notify student that input is needed |
| `workflow.completed` | Mark course/assessment as complete |
| `credential.expired` | Prompt student to re-authorize Google |
| `credential.refresh_failed` | Alert and disable export functionality |

---

## 11. Deployment Architecture (Phase 1)

### 11.1 Target Environment

```
┌──────────────────────────────────────────────────────────────┐
│                      Production Host                          │
│                                                               │
│  ┌───────────────┐  ┌────────────────────────────────────┐   │
│  │   Nginx       │  │   FunSheep (Elixir Release)      │   │
│  │   (reverse    │──│                                    │   │
│  │    proxy,     │  │   Phoenix Endpoint (port 4000)     │   │
│  │    TLS)       │  │   LiveView WebSocket               │   │
│  │              │  │   Oban Workers (OCR, background)   │   │
│  └───────────────┘  └──────────────────┬─────────────────┘   │
│                                         │                     │
│                     ┌───────────────────┘                     │
│                     ▼                                         │
│  ┌────────────────────────────────────┐                      │
│  │   PostgreSQL                       │                      │
│  │   (FunSheep DB + Oban tables)    │                      │
│  └────────────────────────────────────┘                      │
│                                                               │
│  ┌────────────────────────────────────┐                      │
│  │   Local File Storage               │                      │
│  │   /var/studysmart/uploads/          │                      │
│  └────────────────────────────────────┘                      │
└──────────────────────────────────────────────────────────────┘
```

### 11.2 Environment Configuration

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret (64+ hex chars) |
| `PHX_HOST` | Production hostname |
| `PORT` | HTTP port (default 4000) |
| `INTERACTOR_CLIENT_ID` | OAuth client ID for Interactor |
| `INTERACTOR_CLIENT_SECRET` | OAuth client secret |
| `INTERACTOR_ACCOUNT_URL` | `https://auth.interactor.com` |
| `INTERACTOR_CORE_URL` | `https://core.interactor.com` |
| `INTERACTOR_UKB_URL` | Interactor UKB endpoint (port 4005) |
| `INTERACTOR_UDB_URL` | Interactor UDB endpoint (port 4007) |
| `INTERACTOR_REDIRECT_URI` | `https://{PHX_HOST}/auth/callback` |
| `GOOGLE_CLOUD_VISION_KEY` | API key for OCR |
| `STORAGE_ADAPTER` | `local` or `s3` |
| `S3_BUCKET` | AWS S3 bucket (Phase 2) |
| `S3_REGION` | AWS region (Phase 2) |

---

## 12. OTP Supervision Tree

```
FunSheep.Application
├── FunSheep.Repo                          # Ecto repository
├── FunSheepWeb.Endpoint                   # Phoenix HTTP/WS endpoint
├── FunSheep.Interactor.TokenCache         # GenServer: App JWT caching
├── FunSheep.PubSub                        # Phoenix PubSub (pg2 adapter)
├── {Oban, oban_config}                      # Background job processing
│   ├── FunSheep.Workers.OcrWorker         # OCR page processing
│   ├── FunSheep.Workers.AgentCallWorker   # Async agent invocations
│   └── FunSheep.Workers.ReadinessWorker   # Score recalculation
└── FunSheepWeb.Telemetry                  # Metrics and monitoring
```

---

## 13. Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth provider | Interactor Account Server (User JWT for end users, Admin JWT for admins) | SSO across Interactor ecosystem, no custom auth to maintain; role in metadata |
| Role enforcement | Phoenix Plugs (RequireRole, RequireGuardian) | Roles are metadata in Interactor, enforced at application layer for flexibility |
| AI agent platform | Interactor Agents | Centralized agent management, tool callbacks, streaming built-in |
| Workflow engine | Interactor Workflows | State machine support with halting states for human-in-the-loop |
| OCR service | Google Cloud Vision | High accuracy (~98%), image extraction, reasonable cost (~$1.50/1K pages) |
| Frontend framework | Phoenix LiveView | Real-time by default, no JS framework to maintain, server-rendered |
| Background jobs | Oban | PostgreSQL-backed, reliable, built for Elixir, supports retries |
| Primary keys | Binary UUID | Globally unique, no sequential ID exposure |
| File storage | Abstraction with local Phase 1 | Avoid S3 complexity during development, swap via config later |
| No REST API (Phase 1) | LiveView only | Three user roles but all web-based, no third-party integrations yet |
| Question validation | 3-agent pipeline | Ensures 100% answer correctness before showing to students |

---

## 14. Security Considerations

| Concern | Mitigation |
|---------|------------|
| User credentials | Never touch FunSheep; handled entirely by Account Server |
| JWT verification | Validate via JWKS endpoint; verify `iss`, `aud`, `exp` claims |
| Role enforcement | `RequireRole` plug checks `metadata.role` on every request; never trust client-supplied role |
| Guardian access | `RequireGuardian` plug verifies active `student_guardians` record before parent/teacher can view student data |
| Admin separation | Admin portal uses separate JWT tier, separate routes, separate pipeline — no crossover with user auth |
| Tool callback auth | Verify Interactor webhook signatures on all `/api/tools/callback/*` requests |
| Webhook auth | Verify webhook signatures; reject unsigned payloads |
| File uploads | Validate MIME types, enforce size limits, sanitize filenames |
| SQL injection | Ecto parameterized queries (no raw SQL interpolation) |
| XSS | Phoenix HTML escaping by default in LiveView templates |
| CSRF | Phoenix CSRF tokens on all forms and LiveView events |
| Secrets management | All credentials in environment variables, never in code |
| Rate limiting | Apply to webhook/callback endpoints; leverage Interactor's built-in rate limits for API calls |

---

## 15. Future Considerations (Post-Phase 1)

| Area | Enhancement |
|------|-------------|
| Storage | Migrate from local to AWS S3 via config swap |
| Mobile | Consider native apps (React Native / Flutter) consuming a REST API |
| REST API | Expose public API for mobile clients and third-party integrations |
| Caching | Add Redis/ETS caching for readiness scores and course structures |
| Search | Full-text search on questions via PostgreSQL tsvector or Meilisearch |
| Analytics | Student learning analytics dashboard for aggregate insights |
| Multi-tenancy | School/district-level admin portals with teacher management |
| Role expansion | Additional roles (tutor, school admin) via metadata.role extension |
| CDN | CloudFront or similar for static assets and uploaded materials |
