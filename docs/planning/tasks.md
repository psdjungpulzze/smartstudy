# StudySmart Phase 1 - Task Breakdown

> AI-powered adaptive study platform. Elixir/Phoenix/LiveView with Interactor platform integration, Google Cloud Vision OCR, PostgreSQL.

---

## Milestone 1: Foundation & Infrastructure

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-101 | Phoenix project scaffolding | Run `mix phx.new study_smart`, configure deps (ecto, jason, finch, oban, floki), set up `.formatter.exs`, and confirm `mix compile` succeeds. | None | S | Must |
| T-102 | Core database schema and migrations | Create migrations for `students`, `schools`, `districts`, `countries`, `courses`, `chapters`, `sections`, `questions`, `question_attempts`, `study_materials`. Use binary_id primary keys and UTC timestamps throughout. | T-101 | L | Must |
| T-103 | Ecto schemas and changesets | Define Ecto schemas with validations, associations, and enums for all tables created in T-102. | T-102 | L | Must |
| T-104 | Storage behaviour and LocalStorage adapter | Define a `StudySmart.Storage` behaviour with `put/3`, `get/2`, `delete/2`, `url/2` callbacks. Implement `StudySmart.Storage.Local` writing to `priv/uploads/` with content-hash filenames. | T-101 | M | Must |
| T-105 | Interactor OAuth 2.0 client credentials setup | Create `StudySmart.Interactor.Auth` module that exchanges `client_id`/`client_secret` for an `access_token` via Interactor's token endpoint, caches the token, and refreshes before the 15-min expiry. | T-101 | M | Must |
| T-106 | Account Server OAuth 2.0 Authorization Code flow | Implement the student-facing OAuth login: redirect to Account Server `/oauth/authorize`, handle callback with code exchange, store tokens in session. Uses Account Server OAuth/OIDC endpoints. | T-105 | L | Must |
| T-107 | JWT verification via JWKS | Create `StudySmart.Auth.Token` module that fetches the Account Server JWKS endpoint, caches public keys, and verifies RS256 JWT access tokens (issuer, audience, expiry claims). | T-106 | M | Must |
| T-108 | Session management and auth plugs | Build `StudySmart.Auth.Pipeline` plug that extracts JWT from session/cookie, verifies via T-107, assigns `current_user` and `current_role` to conn. Add `require_authenticated` and `require_guest` plugs. | T-107 | M | Must |
| T-109 | App layout shell (3-panel) | Implement the mandatory 3-panel layout in `app.html.heex`: fixed AppBar (h-16), left drawer (w-64), scrollable main content area. Follow CLAUDE.md design system tokens (green primary, pill buttons, rounded-2xl cards). | T-101 | L | Must |
| T-110 | Login/logout LiveView pages | Build login page that initiates OAuth flow (T-106), callback handler, and logout that clears session and revokes token. Single login for all end-user roles; post-login redirect based on `metadata.role`. | T-108, T-109 | M | Must |
| T-111 | Dev seeds and test helpers | Create `priv/repo/seeds.exs` with sample schools, courses, student/parent/teacher data, and guardian relationships. Add `StudySmart.DataCase` and `StudySmart.ConnCase` test helpers with factory functions. | T-103 | M | Should |
| T-112 | Role-based Phoenix Plugs (RequireRole, RequireGuardian) | Build `RequireRole` plug that checks `metadata.role` from session and returns 403 on mismatch. Build `RequireGuardian` plug that verifies active `student_guardians` record before allowing parent/teacher access to student data. | T-108 | M | Must |
| T-113 | Admin portal layout and auth | Build separate admin layout at `/admin` with Interactor Admin JWT login (`/api/v1/admin/login`). Separate pipeline, separate session, separate UI shell. | T-107, T-109 | L | Must |
| T-114 | Role selection during registration flow | Add role selection step (student/parent/teacher) during first login/registration. Store role in Interactor user `metadata.role` via API call and mirror to local `user_roles` table. | T-106, T-103 | M | Must |

---

## Milestone 2: Student Profile & Course Setup

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-201 | Multi-stage profile setup LiveView (Stage 1: Demographics) | Build a step-wizard LiveView. Stage 1 collects name, grade, school (searchable dropdown), district, and country. Validate and persist to `students` table. | T-103, T-109, T-108 | L | Must |
| T-202 | Multi-stage profile setup LiveView (Stage 2: Hobbies) | Stage 2 presents hobby categories and lets students pick interests. Store selections as a JSONB array on the student record. | T-201 | M | Must |
| T-203 | Multi-stage profile setup LiveView (Stage 3: Material upload) | Stage 3 allows uploading textbook PDFs/images. Use `allow_upload` in LiveView, persist via Storage behaviour (T-104), and create `study_materials` records. | T-202, T-104 | L | Must |
| T-204 | School/district/country seed data | Create a data loader that imports school, district, and country reference data from a CSV or JSON seed file. Provide initial dataset for at least one country. | T-102 | M | Must |
| T-205 | Interactor User Profiles integration | Create `StudySmart.Interactor.UserProfiles` module that syncs student preferences (grade, hobbies, learning style) to Interactor user profiles via the platform API, using the cached access token from T-105. | T-105, T-201 | M | Should |
| T-206 | Hobby Discovery Agent setup | Create an Interactor AI Assistant named `hobby_discovery_agent` with a system prompt that suggests related hobbies and learning connections. Register via `POST /api/v1/agents/assistants`. | T-105 | M | Should |
| T-207 | Hobby Discovery Agent room and chat integration | Create a room for each student session with the Hobby Discovery Agent. Send student hobby selections as messages and display agent suggestions in the profile wizard via SSE streaming. | T-206, T-202 | L | Should |
| T-208 | Interactor UKB integration for hobby knowledge | Store and retrieve hobby domain knowledge from Interactor's Universal Knowledge Base. Create data source entries so agents can query hobby-related context. | T-105, T-206 | M | Could |
| T-211 | Student-guardian relationship management | Build invite/accept flow: parent or teacher enters student email to send link request. Student sees pending invitations in `GuardianInviteLive` and can accept or reject. Accepted links create `active` records in `student_guardians`. Include revocation. | T-114, T-103 | L | Must |
| T-212 | Parent dashboard: children list with readiness overview | Build `ParentDashboardLive` showing all linked children with their names, schools, upcoming tests, and aggregate readiness scores. Each child links to a detail view. | T-211, T-109 | L | Must |
| T-213 | Teacher dashboard: class student list with aggregate readiness | Build `TeacherDashboardLive` showing all linked students grouped by course/class, with per-student readiness scores and aggregate class metrics. | T-211, T-109 | L | Must |
| T-209 | Google Cloud Vision OCR API client module | Create `StudySmart.OCR.GoogleVision` module wrapping the Cloud Vision `TEXT_DETECTION` and `DOCUMENT_TEXT_DETECTION` APIs. Handle auth via service account JSON key, request batching, and error handling. | T-101 | L | Must |
| T-210 | OCR pipeline: upload to structured text | Build `StudySmart.OCR.Pipeline` GenServer that takes an uploaded file, sends pages to Vision API (T-209), stores extracted text per page, maps text blocks to page numbers and bounding boxes, and saves metadata to `study_materials` and a new `ocr_pages` table. | T-209, T-203 | L | Must |

---

## Milestone 3: Course Creation & Content Discovery

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-301 | Course matching and search | Implement `StudySmart.Courses.search/1` that finds existing courses by school, subject, grade, and textbook. Build a LiveView search component with results list and "use this course" action. | T-103, T-109 | M | Must |
| T-302 | Course creation flow | LiveView form for creating a new course: subject, grade, textbook reference, and school association. On save, insert into `courses` and redirect to chapter management. | T-301 | M | Must |
| T-303 | Chapter and section management | Build LiveView CRUD for chapters and sections within a course. Support ordering (position field), renaming, and deletion. Chapters have many sections. | T-302 | M | Must |
| T-304 | Content Discovery Agent setup | Create an Interactor AI Assistant named `content_discovery_agent` with web search tools attached. System prompt instructs it to find supplementary educational content for given topics. | T-105 | M | Must |
| T-305 | Question Extraction Agent setup | Create an Interactor AI Assistant named `question_extraction_agent`. System prompt instructs it to identify questions, exercises, and problems from OCR text. Register tool callbacks for receiving OCR text. | T-105, T-210 | M | Must |
| T-306 | Tool callback endpoints for agents | Create Phoenix controller endpoints at `/api/webhooks/agent-tools` that agents can invoke. Implement tool handlers for: `get_ocr_text`, `search_questions`, `store_question`. Verify Interactor webhook signatures. | T-305, T-304 | L | Must |
| T-307 | Question extraction from OCR text | Build `StudySmart.Questions.Extractor` that sends OCR page text to the Question Extraction Agent, parses structured question output (question text, options, answer, page ref), and persists to `questions` table. | T-305, T-306, T-210 | L | Must |
| T-308 | Question-to-reference linking | Link each extracted question back to its source: page number, section, bounding box coordinates, and associated image. Store as `question_references` join table. | T-307 | M | Must |
| T-309 | Per-school question tagging | Add a `question_tags` table with school-scoped tags (topic, difficulty, bloom's level). Build tagging UI in the question management LiveView. | T-307 | M | Should |
| T-310 | Online question search via Content Discovery Agent | Invoke the Content Discovery Agent to search for additional questions on a given topic. Parse results, create question records with source attribution, and flag as "external". | T-304 | L | Should |
| T-311 | Video and lesson discovery | Use the Content Discovery Agent with region-aware prompting to find YouTube videos, Khan Academy lessons, and local platform content. Store results in a `resources` table with URL, type, transcript excerpt, and source. | T-304 | L | Should |
| T-312 | Source attribution storage | Create `source_attributions` table linking questions and resources to their origin (textbook page, URL, API). Display attribution in question detail views. | T-307, T-311 | M | Should |

---

## Milestone 4: Assessment Engine

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-401 | Test scope setup LiveView | Build a LiveView where students select chapters/sections to include in an assessment. Store scope as a `test_scopes` record with JSONB chapter/section IDs. | T-303, T-109 | M | Must |
| T-402 | Test scheduling | CRUD for upcoming tests: name, date, associated course, and scope. Calendar-style display of scheduled tests on the dashboard. | T-401 | M | Must |
| T-403 | Adaptive Assessment workflow definition | Define an Interactor Workflow (`adaptive_assessment`) with states: `select_topic` -> `present_question` -> `evaluate_answer` -> `check_mastery` -> `next_topic_or_complete`. Use halting states for student input. | T-105 | L | Must |
| T-404 | Adaptive testing logic | Implement the core algorithm: minimum 3 questions per topic, increase difficulty on correct answers, decrease on incorrect. Track per-topic mastery in `topic_mastery` table. Move to next topic when mastery threshold met or max questions reached. | T-403 | L | Must |
| T-405 | Question selection algorithm | Build `StudySmart.Assessment.QuestionSelector` that picks questions from stored pool first (prioritizing unseen, then previously incorrect), sorted by target difficulty. Return `{:generate, topic, difficulty}` when pool exhausted. | T-307, T-404 | M | Must |
| T-406 | Question Creator Agent setup | Create Interactor AI Assistant `question_creator_agent` with system prompt for generating curriculum-aligned questions at a specified difficulty. Takes topic, difficulty, hobby context, and existing questions (to avoid duplicates). | T-105 | M | Must |
| T-407 | Answer Creator Agent setup | Create Interactor AI Assistant `answer_creator_agent` that generates detailed answer explanations and distractor rationale for questions produced by the Question Creator. | T-105 | M | Must |
| T-408 | Question Validator Agent setup | Create Interactor AI Assistant `question_validator_agent` that checks generated questions for accuracy, clarity, appropriate difficulty, and curriculum alignment. Returns pass/fail with revision suggestions. | T-105 | M | Must |
| T-409 | Multi-agent question generation pipeline | Orchestrate T-406 -> T-407 -> T-408 in sequence: create question, generate answer, validate. If validation fails, loop back to creator with feedback. Max 2 retries before discarding. Persist validated questions. | T-406, T-407, T-408 | L | Must |
| T-410 | Hobby-contextualized question generation | Extend the Question Creator Agent prompt to incorporate student hobbies from their profile, generating word problems and scenarios using hobby-related contexts (e.g., sports stats for math). | T-409, T-202 | M | Should |
| T-411 | Assessment Evaluator Agent for free-response | Create Interactor AI Assistant `assessment_evaluator_agent` that scores free-text student answers against reference answers. Returns score (0-100), feedback, and partial credit rationale. | T-105 | M | Must |
| T-412 | Assessment LiveView (question presentation and answering) | Build the student-facing test-taking LiveView: display question, collect answer (MCQ or free-text), show immediate feedback, track time per question. Communicates with adaptive workflow instance. | T-404, T-405, T-411 | L | Must |
| T-413 | Question attempt history tracking | Record every answer attempt in `question_attempts` table: student, question, answer given, correct/incorrect, time taken, difficulty at time of attempt. | T-412 | M | Must |
| T-414 | SSE streaming for real-time agent responses | Implement SSE endpoint and LiveView hook that streams agent responses (question generation, evaluation) to the student in real-time using Interactor's streaming API (`Accept: text/event-stream`). | T-412 | M | Must |

---

## Milestone 5: Test Readiness & Study Guides

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-501 | Readiness score calculation | Build `StudySmart.Readiness.Calculator` that computes mastery scores per topic, per chapter, and aggregate from `question_attempts` and `topic_mastery` data. Weight recent attempts more heavily. | T-413 | L | Must |
| T-502 | Test Readiness Dashboard LiveView | Dashboard showing per-test readiness: progress bars per chapter/topic, aggregate score, color-coded status (red/yellow/green). Include sparkline trend of score over time. | T-501, T-402 | L | Must |
| T-503 | Schedule-aware readiness display | Enhance dashboard to show readiness in context of upcoming test dates: "3 days left, readiness: 72%", projected readiness at test date based on current study velocity. | T-502 | M | Must |
| T-504 | Study Guide Generator Agent setup | Create Interactor AI Assistant `study_guide_generator_agent` that produces structured study guides from weak topics, including explanations, key formulas, worked examples, and textbook page references. | T-105 | M | Must |
| T-505 | Study guide generation and storage | Invoke Study Guide Generator Agent with student's weak topics and question attempt data. Parse output into structured sections, store in `study_guides` table with chapter/topic associations. | T-504, T-501 | L | Must |
| T-506 | Study guide display LiveView | Render generated study guides with formatted content, linked textbook page references (deep-link to OCR page view), and associated practice questions. | T-505 | M | Must |

---

## Milestone 6: Practice & Mobile Quick Tests

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-601 | Practice test engine | Build a practice mode that auto-selects questions from weak areas (below mastery threshold), runs in a continuous loop, and updates readiness scores after each answer. | T-405, T-501 | L | Must |
| T-602 | Mobile quick test LiveView (card UI) | Create a mobile-optimized LiveView with swipeable card-based question display. Cards show question on front, answer on back. Touch/swipe interactions via JS hooks. | T-601, T-109 | L | Must |
| T-603 | Card interaction handlers | Implement "I know this" (mark correct, advance), "I don't know this" (show explanation, mark incorrect), "Answer" (flip to show answer), and "Skip" (defer, re-queue). Each action updates attempt history. | T-602 | M | Must |
| T-604 | Short explanation generation | When student taps "I don't know this", invoke a lightweight agent call to generate a 2-3 sentence explanation of the concept. Cache explanations for reuse. | T-603, T-105 | M | Should |
| T-605 | In-product browser for external resources | Build a slide-in panel or modal that loads external lesson URLs (YouTube, Khan Academy) within the app using an iframe with sandbox restrictions. Track which resources were viewed. | T-311, T-109 | M | Should |
| T-606 | Practice response tracking integration | Ensure all practice/quick-test responses flow into `question_attempts` and trigger readiness score recalculation in real-time via PubSub broadcast. | T-601, T-603, T-501 | M | Must |

---

## Milestone 7: Test Format Replication

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-701 | Test format upload and AI analysis | Allow teachers/students to upload sample test papers. Send to an Interactor AI Agent that analyzes structure: number of sections, question types, point distribution, time limits. | T-105, T-209 | L | Must |
| T-702 | Test format template storage | Store analyzed formats in `test_format_templates` table: name, structure JSON (sections, question counts per type, point weights, time limit), and source school. | T-701 | M | Must |
| T-703 | Format-matched practice test generation | Generate practice tests matching a stored format template: correct number of MCQ/short-answer/essay questions per section, matching difficulty distribution. Use the multi-agent pipeline (T-409). | T-702, T-409 | L | Must |
| T-704 | Timed test mode | Add countdown timer to the assessment LiveView (T-412) matching the real exam duration from the format template. Show warnings at 50%, 25%, and 5% remaining. Auto-submit when time expires. | T-703, T-412 | M | Must |
| T-705 | Pre-test format recommendations | Before a scheduled test date, surface format-matched practice tests on the dashboard. Notify students that format tests are available for upcoming exams. | T-703, T-502 | M | Should |

---

## Milestone 8: Export & Polish

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-801 | PDF export module | Build `StudySmart.Export.PDF` using a PDF generation library (e.g., ChromicPDF or Puppeteer) to export study guides, practice tests, and readiness reports as formatted PDFs. | T-505, T-703 | L | Must |
| T-802 | Google Docs export via Interactor Credentials | Use Interactor Credential Management to store student Google OAuth tokens. Export study guides to Google Docs via the Docs API, using credentials retrieved from `GET /api/v1/credentials`. | T-105, T-505 | L | Should |
| T-803 | Interactor Billing integration | Integrate Interactor billing APIs to track per-student usage: agent calls, OCR pages processed, questions generated. Enforce usage limits based on subscription tier. | T-105 | L | Must |
| T-804 | Multi-language i18n setup | Configure Gettext for i18n. Extract all user-facing strings, create initial `.po` files for English and one additional language. Set up locale switching in the AppBar. | T-109 | M | Should |
| T-805 | Notifications and test reminders | Use Oban scheduled jobs to send test reminders at 7 days, 3 days, and 1 day before scheduled tests. Display in-app notification badge (dual badge per design system) and optional email via Interactor. | T-402 | L | Should |
| T-806 | UI polish and mobile responsiveness | Audit all LiveViews for mobile breakpoints, touch targets, dark mode support, and design system compliance. Fix spacing, color, and border-radius deviations from design tokens. | T-109 | L | Must |
| T-807 | Error handling and fallback UI | Add global error boundary, friendly 404/500 pages, offline detection banner, and graceful degradation when Interactor services are unavailable. | T-101 | M | Must |
| T-808 | End-to-end smoke tests | Write Wallaby or Playwright E2E tests covering: login -> profile setup -> course creation -> take assessment -> view readiness -> export PDF. | T-412, T-501, T-801 | L | Should |

---

## Milestone 9: Interactor Data Integration & Multi-Role Notifications

| Task ID | Title | Description | Dependencies | Effort | Priority |
|---------|-------|-------------|--------------|--------|----------|
| T-901 | Interactor UDB integration: register PostgreSQL as Data Source | Create `StudySmart.Interactor.UserDatabase` module. Register StudySmart's PostgreSQL as a Data Source in Interactor UDB (port 4007). Map key tables (students, readiness_scores, question_attempts, test_schedules) so AI agents can query student data via natural language. Configure per-user data isolation so agents only access data for the relevant student. | T-105, T-103 | L | Must |
| T-902 | Interactor UKB integration: store/search curriculum and hobby knowledge | Extend `StudySmart.Interactor.KnowledgeBase` to store curriculum/subject knowledge (syllabi, topic taxonomies, reference summaries) in addition to hobby domain knowledge in Interactor UKB (port 4005). Implement semantic search for agents to retrieve relevant domain context during question generation and study guide creation. | T-105, T-208 | L | Must |
| T-903 | Parent/teacher notification on student assessment completion | Send in-app and optional email notification to linked parents and teachers when a student completes an assessment session. Include summary: topics covered, aggregate score, readiness change. Use Oban job to query `student_guardians` and dispatch notifications. | T-211, T-413, T-805 | M | Should |

---

## Dependency Graph (Critical Path)

```
T-101 ─┬─ T-102 ── T-103 ── T-201 ── T-202 ── T-203 ── T-210 ── T-307 ── T-405 ── T-404 ── T-412 ── T-413 ── T-501 ── T-502
       │                                                                                  ↑                         │
       ├─ T-104 ──────────────────────────────────────────┘                               │                         ├── T-505 ── T-801
       │                                                                                   │                         └── T-601 ── T-602
       ├─ T-105 ── T-106 ── T-107 ── T-108 ── T-110                                      │
       │     │                                                                             │
       │     ├── T-304 ── T-310, T-311                                                    │
       │     ├── T-305 ── T-306 ────────────────────────────────────────────┘              │
       │     ├── T-406, T-407, T-408 ── T-409 ──────────────────────────────── T-703      │
       │     └── T-403 ────────────────────────────────────────────────────────┘           │
       │                                                                                   │
       └─ T-109 ──────────────────────────────────────────────────────────── T-502 ── T-503
```

**Critical path**: T-101 -> T-102 -> T-103 -> T-201 -> T-203 -> T-210 -> T-307 -> T-405 -> T-404 -> T-412 -> T-413 -> T-501 -> T-502

---

## Summary

| Milestone | Tasks | Must | Should | Could | Total Effort |
|-----------|-------|------|--------|-------|--------------|
| 1. Foundation & Infrastructure | 14 | 13 | 1 | 0 | ~10 days |
| 2. Student Profile & Course Setup | 13 | 9 | 3 | 1 | ~10 days |
| 3. Course Creation & Content Discovery | 12 | 7 | 5 | 0 | ~8 days |
| 4. Assessment Engine | 14 | 12 | 1 | 0 | ~10 days |
| 5. Test Readiness & Study Guides | 6 | 6 | 0 | 0 | ~5 days |
| 6. Practice & Mobile Quick Tests | 6 | 4 | 2 | 0 | ~5 days |
| 7. Test Format Replication | 5 | 4 | 1 | 0 | ~4 days |
| 8. Export & Polish | 8 | 4 | 4 | 0 | ~6 days |
| 9. Interactor Data Integration & Notifications | 3 | 2 | 1 | 0 | ~3 days |
| **Total** | **81** | **61** | **18** | **1** | **~61 days** |
