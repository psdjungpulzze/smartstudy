# Requirements Document

## Project Information

| Field | Value |
|-------|-------|
| **Project Name** | StudySmart |
| **Document Version** | 1.0 |
| **Last Updated** | 2026-04-17 |
| **Author** | Peter Jung |
| **Status** | Draft |

---

## Executive Summary

StudySmart is an AI-powered adaptive study platform that helps students prepare for exams. The platform creates personalized courses by discovering and organizing educational content (textbooks, online resources, videos), extracts and generates practice questions, then uses adaptive testing to identify knowledge gaps and guide students toward test readiness.

The application is built on the Interactor platform, leveraging its AI Agents, Workflows, Credential Management, and Authentication services as core infrastructure rather than building custom equivalents.

---

## Problem Statement

### Background
Students spend significant time studying topics they already know while neglecting weak areas. Current study tools are static and don't adapt to individual knowledge levels, leading to inefficient exam preparation.

### Problem
There is no accessible platform that:
1. Automatically discovers and organizes course content from multiple sources
2. Uses adaptive testing to precisely identify what a student knows vs. doesn't know
3. Provides targeted study guides pointing to exact textbook pages and reference materials
4. Gives a real-time "Test Readiness" score so students know when they're prepared

### Impact
- Students waste hours on unfocused studying
- Poor exam preparation leads to lower grades
- No visibility into knowledge gaps until the actual test
- No way to know "am I ready?" before the exam

### Success Metrics

| Metric | Current | Target | How Measured |
|--------|---------|--------|--------------|
| Time to course setup | Manual (hours) | < 10 minutes | From start to questions available |
| Knowledge gap identification | Not possible | Within 1 session | Assessment completion rate |
| Test Readiness accuracy | N/A | Correlates with actual score within 10% | Compare predicted vs actual scores |
| Daily engagement (mobile) | N/A | 5+ min/day avg | Mobile quick test usage analytics |

---

## Scope

### In Scope (Phase 1)
- Subject/course creation with multi-stage input (demographics, hobbies, material upload)
- Content discovery (online questions, videos, lessons)
- Question extraction from uploaded materials (OCR-first pipeline)
- Question generation (AI-powered, copyright-safe derivatives)
- Adaptive/progressive assessment
- Test Readiness scoring (chapter/topic/aggregate)
- Study guide generation
- Practice tests (focused on weak areas)
- Mobile quick tests (Tinder-style card swipe)
- Export to Google Docs, PDF, etc.
- Multi-language support

### Out of Scope (Phase 1)
- Payment/subscription (beyond Interactor billing integration)
- Social features (study groups, leaderboards)
- Native mobile apps (web-first with mobile-responsive)
- Real-time tutoring/chat with human tutors

### Assumptions
- Students have access to their course textbooks (physical or digital)
- Interactor platform services are available and reliable
- Copyright-safe derivative questions (changed numbers/words) are legally acceptable
- OCR accuracy is sufficient for common textbook formats

### Constraints
- Must use Interactor platform services for AI, auth, workflows, credentials
- Elixir/Phoenix/LiveView stack
- Local file storage initially, AWS S3 later
- AI token costs must be minimized (OCR-first pipeline)

---

## Functional Requirements

### Epic: Subject/Course Setup

#### FR-001: Multi-Stage Student Profile Input

**Priority**: Must Have

**Description**: Students set up their profile through a 3-stage input process covering demographics, hobbies, and material upload.

**User Story**: As a student, I want to set up my profile with my school and subject information, so that the platform can find relevant content for me.

**Acceptance Criteria**:
- [ ] Stage 1 captures: Country/State, District/School, Subject/Class, Grade, Gender, Nationality, **Role selection (student/parent/teacher)**
- [ ] Stage 2: Hobby discovery and personalization (see FR-015)
- [ ] Stage 3 allows uploading textbooks and materials (PDF, images)
- [ ] Profile data is stored via Interactor User Profiles (`external_user_id`)
- [ ] User role stored in Interactor Account Server user `metadata.role`
- [ ] Hobby preferences stored in Interactor User Knowledge Base (UKB) for semantic retrieval
- [ ] Progress is saved between stages

**Interactor Services**: User Profiles (demographics, preferences), User Knowledge Base (hobby domain knowledge), Account Server (role in user metadata)

---

#### FR-002: Course Matching Against Existing Courses

**Priority**: Must Have

**Description**: Check if similar courses already exist in the system before creating new ones.

**User Story**: As a student, I want to see if my course already exists, so that I don't have to wait for content to be discovered from scratch.

**Acceptance Criteria**:
- [ ] System searches existing courses by subject, school, grade
- [ ] Matches are presented to student for confirmation
- [ ] If confirmed, course structure and questions are shared/cloned
- [ ] Questions are tagged per school for school-specific filtering

---

#### FR-003: New Course Creation — Content Discovery

**Priority**: Must Have

**Description**: When no existing course matches, create a new course by discovering content from multiple sources.

**User Story**: As a student, I want the platform to automatically find my course content online, so that I have study materials ready quickly.

**Acceptance Criteria**:
- [ ] Subject identified and broken into chapters/sections
- [ ] Chapter/section structure stored in DB with page number mappings
- [ ] Online search for practice questions (HTML, PDF, Docs)
- [ ] Online search for video lessons (YouTube transcripts, Khan Academy, etc.)
- [ ] Found questions stored with source attribution (links)
- [ ] All discovery performed by Interactor AI Agent (Content Discovery Agent)

**Interactor Service**: AI Agents (Content Discovery Assistant with search tools)

---

#### FR-004: Question Extraction from Uploaded Materials

**Priority**: Must Have

**Description**: Extract questions from student-uploaded files using OCR-first pipeline.

**User Story**: As a student, I want questions automatically extracted from my textbook PDFs, so that I can practice from my actual course materials.

**Acceptance Criteria**:
- [ ] OCR extracts text + images from uploads before sending to LLM
- [ ] Extracted content preserves page number, bounding box, section mapping
- [ ] Extracted images stored with references back to source page/position
- [ ] AI agent identifies and extracts questions from processed text
- [ ] Extracted question count verified against expected numbers
- [ ] Every question has an associated answer
- [ ] Each question classified by chapter/section
- [ ] OCR supports PDF and image formats

**Interactor Service**: AI Agents (Question Extraction Assistant with OCR tool callbacks)

---

#### FR-005: Question-to-Reference Linking

**Priority**: Must Have

**Description**: Each question is linked to relevant textbook pages and reference materials.

**User Story**: As a student, I want to see which textbook section a question relates to, so that I can review the material when I get it wrong.

**Acceptance Criteria**:
- [ ] Each question tagged with topic
- [ ] Each question linked to specific textbook pages/images
- [ ] Each question categorized per school
- [ ] Student can view the referenced textbook page/image alongside the question

---

### Epic: Test Preparation

#### FR-006: Test Scope Setup

**Priority**: Must Have

**Description**: Student defines the scope of an upcoming test.

**User Story**: As a student, I want to specify which chapters my test covers, so that the platform focuses on relevant material.

**Acceptance Criteria**:
- [ ] Select subject
- [ ] Select chapters + sub-chapters
- [ ] Optionally specify test type/format (if school provided one)
- [ ] Set test date (schedule) for the upcoming exam
- [ ] Scope saved and used for all subsequent assessment/practice

---

#### FR-006b: Test Scheduling

**Priority**: Must Have

**Description**: Students can schedule upcoming tests with dates. The system uses the schedule to plan study activities and trigger test-format practice tests at the right time.

**User Story**: As a student, I want to set my upcoming test dates, so that the platform can plan my study schedule and provide practice tests at the right time.

**Acceptance Criteria**:
- [ ] Student can create/edit/delete scheduled tests with:
  - Test name/subject
  - Test date
  - Test scope (chapters/topics — links to FR-006)
  - Test format (if uploaded — links to FR-006c)
- [ ] Dashboard shows upcoming tests sorted by date
- [ ] System triggers test-format practice tests a configurable number of days before the test (e.g., 3-5 days prior)
- [ ] Notifications/reminders as test date approaches
- [ ] Test Readiness score displayed in context of scheduled test date ("3 days left, readiness: 72%")

---

#### FR-006c: Test Format Replication

**Priority**: Must Have

**Description**: When a student uploads a test format/sample from their school, the system generates practice tests that exactly replicate that format — same structure, question types, number of questions, timing, and layout.

**User Story**: As a student, I want to practice with tests that look exactly like my real exam, so that I'm fully prepared for the actual test experience.

**Acceptance Criteria**:
- [ ] Student can upload a test format/sample (PDF, image, or describe the format)
- [ ] System analyzes the format via OCR + AI Agent to identify:
  - Number of questions
  - Question types (multiple choice, short answer, essay, etc.)
  - Point distribution
  - Section structure
  - Time limits (if specified)
- [ ] AI generates practice tests matching the exact format:
  - Same number of questions per section
  - Same question types in same order
  - Same point distribution
  - Questions drawn from the test scope (FR-006) topics
  - Questions use multi-agent validation (FR-012) for answer correctness
- [ ] Practice tests in this format are recommended/surfaced starting a few days before the scheduled test date (FR-006b)
- [ ] Student can generate multiple practice tests in the same format
- [ ] Student can take the practice test in a timed mode matching the real exam duration

**Interactor Services**: AI Agents (Format Analysis Agent as supporting assistant), Workflows (timed test session)

---

#### FR-007: Adaptive Assessment

**Priority**: Must Have

**Description**: Adaptive/progressive testing that identifies knowledge gaps.

**User Story**: As a student, I want the platform to test me adaptively, so that it can quickly identify exactly what I know and don't know.

**Acceptance Criteria**:
- [ ] Tests at least 3 questions per topic
- [ ] If any wrong, adaptively tests again to verify the gap
- [ ] Starts easy, progressively increases difficulty
- [ ] Uses stored questions first; generates new only after exhausting stored pool
- [ ] Generated questions are copyright-safe derivatives (changed numbers/words)
- [ ] All generated questions stored in DB for future reuse
- [ ] Full question history tracked (correct/incorrect per attempt)
- [ ] Can filter to show only correct or incorrect answered questions
- [ ] For free-response questions, AI agent evaluates and provides corrections
- [ ] Assessment modeled as Interactor Workflow (state machine)

**Interactor Services**: Workflows (assessment state machine), AI Agents (Assessment Evaluator)

---

#### FR-008: Test Readiness Dashboard

**Priority**: Must Have

**Description**: Shows the student's readiness for their upcoming test.

**User Story**: As a student, I want to see my estimated test score, so that I know if I'm ready or need to study more.

**Acceptance Criteria**:
- [ ] Shows test scope coverage
- [ ] Per-chapter score
- [ ] Per-topic score
- [ ] Aggregate estimated total test score
- [ ] Scores update in real-time as assessments are completed

---

#### FR-009: Study Guide Generation

**Priority**: Must Have

**Description**: AI-generated study guide based on weakness analysis.

**User Story**: As a student, I want a personalized study guide, so that I know exactly what to review and where to find it.

**Acceptance Criteria**:
- [ ] Identifies topics needing more study
- [ ] Shows specific textbook pages for each weak topic
- [ ] Links to relevant video lessons and online resources
- [ ] Generated by Interactor AI Agent (Study Guide Generator)

**Interactor Service**: AI Agents (Study Guide Generator Assistant)

---

#### FR-010: Practice Tests

**Priority**: Must Have

**Description**: Targeted practice focusing on lower-scoring areas.

**User Story**: As a student, I want to practice questions I'm scoring lower on, so that I can improve my weak areas.

**Acceptance Criteria**:
- [ ] Focuses on questions the student scored lower on
- [ ] UX similar to assessment phase
- [ ] Repetitive cycle: test -> results -> learning materials -> re-test
- [ ] Tracks improvement over repeated practice

---

#### FR-011: Mobile Quick Tests

**Priority**: Must Have

**Description**: Tinder-style card-based quick review for mobile.

**User Story**: As a student on the go, I want to quickly flip through study cards, so that I can study in short bursts.

**Acceptance Criteria**:
- [ ] Card-based question UI (swipeable)
- [ ] "I know this" — mark as known and skip
- [ ] "I don't know this" — show short explanation, then links to video/lessons
- [ ] "Answer" — provide answer interface (like assessment)
- [ ] "Skip" — move to next without marking
- [ ] All responses tracked and feed into Test Readiness score
- [ ] In-product browser for external lesson links if needed

---

### Epic: Cross-Cutting

#### FR-012: Dynamic Question Generation (Multi-Agent Validation)

**Priority**: Must Have

**Description**: AI generates copyright-safe derivative questions when none exist for a topic. Uses a multi-agent pipeline to ensure answer correctness.

**User Story**: As a student, I want new practice questions generated when I've exhausted the stored ones, so that I always have fresh material to study.

**Acceptance Criteria**:
- [ ] If no stored questions exist for a topic, generate using AI agents
- [ ] Derivative questions use simple word and number changes from source material
- [ ] Multi-agent validation pipeline ensures 100% answer correctness:
  - Agent 1 (Question Creator): Creates the derivative question with modified numbers/words
  - Agent 2 (Answer Creator): Independently solves the new question to produce the answer
  - Agent 3 (Validator): Cross-checks that the question, answer from Agent 2, and original source are all consistent
- [ ] Only questions that pass all 3 agents are stored in DB
- [ ] Failed validations are logged for review but never shown to students
- [ ] Generated questions stored in DB for future reuse
- [ ] Modeled as Interactor Supporting Assistants (orchestrator delegates to 3 specialized agents)

**Interactor Service**: AI Agents (3 Supporting Assistants: Question Creator, Answer Creator, Validator)

---

#### FR-013: Export / Print

**Priority**: Should Have

**Description**: Export study materials to various formats.

**Acceptance Criteria**:
- [ ] Export weak areas and study guides to Google Docs
- [ ] Export to PDF
- [ ] Export to Word Docs
- [ ] Uses Interactor Credential Management for Google OAuth

**Interactor Service**: Credential Management (Google OAuth tokens)

---

#### FR-014: Multi-Language Support

**Priority**: Should Have

**Description**: Platform supports multiple languages.

**Acceptance Criteria**:
- [ ] UI supports multiple languages
- [ ] Content discovery works across languages
- [ ] Implementation follows interactor-website patterns

---

#### FR-015: Hobby-Based Question & Explanation Personalization

**Priority**: Must Have

**Description**: The platform researches hobbies relevant to the student's demographics, stores the student's hobby preferences, and uses them to contextualize questions and explanations with relatable references.

**User Story**: As a student, I want math problems and explanations to reference things I care about (like KPOP, sports, gaming), so that studying feels more engaging and relatable.

**Example**: A high school junior, female, Korean, living in Saratoga, CA, who likes KPOP (BTS, BlackPink):
> "Let's say Jenny and JongKuk had 100,000 followers. If Jenny got in a scandal and lost 50,000 followers, she would be left with 50,000 followers. What percentage of her original followers did she lose?"

**Acceptance Criteria**:
- [ ] Hobby discovery process:
  1. Research common hobbies based on student demographics (region, gender, age, nationality)
  2. Store discovered hobby knowledge in Interactor User Knowledge Base (UKB) for semantic retrieval
  3. Present hobby options to student for selection/confirmation
  4. Store student's hobby preferences in Interactor User Profiles
- [ ] Hobby-contextualized content generation:
  1. When generating derivative questions (FR-012), contextualize with student's hobby interests
  2. When generating explanations ("I don't know this" flow), use hobby references in examples
  3. Hobby context retrieved from UKB and User Profiles at generation time
- [ ] Hobby data structure includes:
  - Hobby category (music, sports, gaming, etc.)
  - Specific interests (BTS, BlackPink, etc.)
  - Relevant names, terms, and scenarios that can be used in word problems
- [ ] Questions contextualized with hobbies are the preferred format when possible
- [ ] Fallback to generic questions when hobby context doesn't fit the topic

**Interactor Services**:
- User Knowledge Base (UKB): Store hobby domain knowledge (what KPOP is, who BTS members are, relevant terms/scenarios) for semantic retrieval by agents
- User Profiles: Store student's selected hobby preferences
- AI Agents: Hobby Discovery Agent researches hobbies; Question Creator Agent uses hobby context when generating

---

#### FR-016: Region-Based Educational Platform Discovery

**Priority**: Should Have

**Description**: The platforms used for lesson and content discovery vary by region, school district, and country. The system must discover and use appropriate educational platforms based on the student's location.

**User Story**: As a student, I want the platform to find lessons from sources relevant to my region, so that the content matches my curriculum and educational standards.

**Acceptance Criteria**:
- [ ] Educational platform discovery varies by:
  - Country (e.g., YouTube global, but local platforms for specific countries)
  - School district (district-specific resources)
  - Region (state/province-level educational resources)
- [ ] System maintains a registry of educational platforms per region
- [ ] Content discovery agent selects appropriate platforms based on student profile
- [ ] Supports adding new platform sources as they're discovered

---

### Epic: Multi-Role & Relationships

#### FR-017: User Role Management

**Priority**: Must Have

**Description**: The platform supports three end-user roles (student, parent, teacher) with role-based permissions. Platform admins are a separate tier with their own admin portal. Roles are stored in Interactor Account Server user `metadata.role` and enforced at the StudySmart application layer, not the auth layer.

**User Story**: As a user, I want to select my role (student, parent, or teacher) during profile setup, so that the platform shows me features relevant to my role.

**Acceptance Criteria**:
- [ ] Three end-user roles: student, parent, teacher
- [ ] Role selected during profile setup (FR-001 Stage 1) and stored in Account Server user `metadata.role`
- [ ] Role-based UI: students see study features; parents see child readiness dashboards; teachers see class management
- [ ] Role enforcement happens at the StudySmart application layer (not at Interactor auth layer)
- [ ] All end users authenticate via Interactor User JWT (OAuth/OIDC)
- [ ] Platform admins authenticate via Interactor Admin JWT (separate admin portal, see FR-019)
- [ ] Users cannot change their own role after initial setup (admin action required)

**Interactor Services**: Account Server (OAuth/OIDC for end users, Admin JWT for admins, user `metadata.role`)

---

#### FR-018: Parent-Student & Teacher-Student Relationships

**Priority**: Must Have

**Description**: Parents and teachers can link to multiple student accounts to view their readiness, manage their courses, and monitor progress. Relationships are stored in StudySmart's application database.

**User Story**: As a parent, I want to link my account to my children's student accounts, so that I can monitor their test readiness and study progress.

**Acceptance Criteria**:
- [ ] Parents can add/link multiple students to their account
- [ ] Teachers can add/link multiple students (class roster) to their account
- [ ] Linking requires student confirmation or invite code mechanism
- [ ] Parents can view each linked student's Test Readiness dashboard, scores, and study activity
- [ ] Teachers can view each linked student's progress and readiness scores
- [ ] Teachers can manage courses for their linked students (assign test scopes, recommend practice)
- [ ] Relationship data stored in StudySmart application DB (not Interactor)
- [ ] Student data isolation preserved — parents/teachers only see data for their linked students
- [ ] Student progress data queryable by agents via Interactor UDB (User Database) with per-user isolation

**Interactor Services**: UDB (agent-queryable student progress data with per-user isolation)

---

#### FR-019: Admin Portal

**Priority**: Must Have

**Description**: A separate admin portal for platform management, accessible only via Interactor Admin JWT authentication. This is distinct from end-user authentication.

**User Story**: As a platform admin, I want a separate admin portal with its own login, so that I can manage users, courses, and platform settings securely.

**Acceptance Criteria**:
- [ ] Separate admin login page/portal (not the main student/parent/teacher app)
- [ ] Admin authentication via Interactor Admin JWT (not User JWT)
- [ ] Admins can manage users (view, edit roles, deactivate)
- [ ] Admins can view platform-wide analytics (usage, course stats, question counts)
- [ ] Admins can manage courses and question pools
- [ ] Admins can review flagged content (failed question validations, reported issues)
- [ ] Admin portal has its own route namespace and layout

**Interactor Services**: Account Server (Admin JWT authentication)

---

## Non-Functional Requirements

### Performance

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-P01 | Page load time | < 2 seconds | High |
| NFR-P02 | Question card transition | < 200ms | High |
| NFR-P03 | OCR processing (per page) | < 5 seconds | Medium |
| NFR-P04 | Assessment question delivery | < 1 second | High |

### Security

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-S01 | Authentication | Interactor Account Server (OAuth/OIDC) | High |
| NFR-S02 | Data encryption | At rest and in transit | High |
| NFR-S03 | Student data privacy | COPPA/FERPA awareness | High |
| NFR-S04 | API security | All via Interactor JWT tokens | High |

### Reliability

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-R01 | Uptime | 99.9% | High |
| NFR-R02 | Data backup | Daily | High |
| NFR-R03 | Graceful degradation | App works if AI services temporarily unavailable | Medium |

### Usability

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-U01 | Mobile responsive | Full mobile support | High |
| NFR-U02 | Accessibility | WCAG 2.1 AA | High |
| NFR-U03 | Card swipe UX | Native-feeling touch interactions | High |

---

## Dependencies

### External Dependencies

| Dependency | Description | Provider | Risk Level |
|------------|-------------|----------|------------|
| Interactor Platform | AI Agents, Workflows, Credentials, Webhooks | Interactor (internal) | Low |
| Account Server | Authentication (User JWT + Admin JWT), user management, role metadata | Interactor (internal) | Low |
| Interactor UKB | User Knowledge Base for hobby + curriculum/subject domain knowledge (semantic retrieval for AI agents) | Interactor (internal) | Low |
| Interactor UDB | User Database as agent-queryable data layer for student progress data (dynamic tables with per-user isolation) | Interactor (internal) | Low |
| Billing Server | Usage tracking, per-student quotas | Interactor (internal) | Low |
| YouTube API | Video lesson discovery | Google | Medium |
| Google Docs API | Export functionality | Google | Low |
| Google Cloud Vision OCR | Text/image extraction (~98% accuracy) | Google Cloud | Low |

---

## Glossary

| Term | Definition |
|------|------------|
| Test Readiness | Aggregate score predicting student's exam performance |
| Adaptive Assessment | Testing that adjusts difficulty based on student's responses |
| OCR-first pipeline | Extract text/images via OCR before sending to LLM to reduce token costs |
| Derivative question | Modified version of a copyrighted question (changed numbers/words) |
| external_user_id | Interactor's user isolation mechanism, maps to student ID |
| UKB (User Knowledge Base) | Interactor service for storing domain knowledge (hobbies, curriculum) with semantic retrieval for AI agents |
| UDB (User Database) | Interactor service providing agent-queryable dynamic tables with per-user data isolation |
| User JWT | Interactor OAuth/OIDC token for end users (students, parents, teachers) |
| Admin JWT | Interactor admin token for platform administrators (separate auth flow) |
| metadata.role | Field in Interactor Account Server user metadata storing the user's role (student/parent/teacher) |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-17 | Peter Jung | Initial draft from project requirements |
| 1.1 | 2026-04-17 | Peter Jung | Added multi-role support (FR-017), parent/teacher relationships (FR-018), admin portal (FR-019); updated FR-001 with role selection; added UKB/UDB dependencies; updated glossary |
