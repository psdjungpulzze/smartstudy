# Research Notes — StudySmart

## Interactor Platform Service Mapping

### Services Available (from interactor-workspace)

| Service | Docs | Relevance to StudySmart |
|---------|------|------------------------|
| **Account Server** | `docs/i/account-server-docs/integration-guide/` | Authentication: User JWT (OAuth/OIDC) for students/parents/teachers, Admin JWT for platform admins. User `metadata.role` stores role (student/parent/teacher). Role enforcement at app layer. |
| **AI Agents** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md` | Core of the product — question extraction, content discovery, answer evaluation, study guide generation |
| **Workflows** | `docs/i/interactor-docs/integration-guide/05-workflows.md` | Adaptive assessment state machine, course creation pipeline |
| **Credential Management** | `docs/i/interactor-docs/integration-guide/03-credential-management.md` | Google Docs export, YouTube API access |
| **Webhooks & SSE** | `docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md` | Real-time AI agent responses during assessment |
| **Data Sources** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md#data-sources` | Connect PostgreSQL so agents can query question bank |
| **User Profiles** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md#user-profiles` | Store student preferences, grade, school, learning context |
| **User Knowledge Base (UKB)** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md#user-knowledge-base` | Store hobby domain knowledge AND curriculum/subject knowledge for semantic retrieval by AI agents |
| **User Database (UDB)** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md#user-database` | Agent-queryable data layer for student progress data. Dynamic tables with per-user isolation. Parents/teachers query linked students' progress via agents. |
| **Supporting Assistants** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md#supporting-assistants` | Orchestrator pattern for specialized agents |
| **Service Knowledge Base** | `docs/i/interactor-docs/integration-guide/04-ai-agents.md#service-knowledge-base-search` | Discover connectable external services |
| **Billing Server** | Referenced in overview | Per-student usage tracking via allocations |

### Key Interactor Patterns to Use

1. **external_user_id**: Map to student ID for data isolation
2. **Config Code Sync**: Define assistants, tools, workflows as code (recommended over API)
3. **Tool Callbacks**: StudySmart backend exposes tool endpoints that agents can invoke (e.g., search DB, run OCR)
4. **Callback Signature Verification**: HMAC-SHA256 on all tool callbacks
5. **SSE for real-time**: Stream agent responses to frontend during assessment/chat
6. **Workflow halting states**: Model "waiting for student answer" as halting states

### Authentication & Role Architecture

| Concern | Approach |
|---------|----------|
| **End users (student/parent/teacher)** | Interactor User JWT via OAuth/OIDC. Role stored in Account Server user `metadata.role`. |
| **Platform admins** | Interactor Admin JWT. Separate admin portal with its own login flow. |
| **Role enforcement** | At StudySmart application layer, NOT at auth layer. Middleware reads `metadata.role` from JWT/user record and enforces permissions per route/action. |
| **UKB usage** | Hobby domain knowledge (what KPOP is, BTS members, etc.) + curriculum/subject knowledge (chapter outlines, topic taxonomies). Semantic retrieval enables agents to find contextually relevant content. |
| **UDB usage** | Agent-queryable data layer for student progress data. Dynamic tables with per-user isolation. When a parent/teacher queries progress, agents access linked students' UDB data. |

---

## Open Research Topics

### 1. Adaptive Testing Algorithm
- **Question**: What's the best adaptive testing methodology?
- **Current approach**: Min 3 questions/topic, progressive difficulty, re-test on errors
- **To research**: Item Response Theory (IRT), Computerized Adaptive Testing (CAT), Bayesian knowledge tracing
- **Key constraint**: Must work with limited question pools initially

### 2. Copyright-Safe Question Derivation
- **Question**: How much modification makes a derivative question legally safe?
- **Current approach**: Change numbers and words slightly
- **To research**: Fair use doctrine, educational use exceptions, how existing platforms handle this
- **Risk**: Medium — needs legal review before launch

### 3. OCR Pipeline Selection (RESOLVED)
- **Decision**: Google Cloud Vision OCR
- **Why**: ~98% accuracy vs ~85-95% for Tesseract. Critical for textbooks with small text, multi-column layouts, formulas, and diagrams. Bad OCR = garbage questions in DB.
- **Cost**: ~$1.50 per 1,000 pages (~$1 per 500-page textbook). Negligible compared to AI token costs.
- **Integration**: Google Cloud Vision API; credentials managed via Interactor Credential Management

### 4. Hobby-Based Question & Explanation Personalization (RESOLVED)
- **Decision**: Hobbies are used to contextualize both questions AND explanations
- **Process**:
  1. Research hobbies based on student demographics (region, gender, age, nationality)
  2. Store hobby domain knowledge in Interactor UKB (names, terms, scenarios related to the hobby)
  3. Student selects hobby preferences → stored in Interactor User Profiles
  4. When generating questions/explanations, agents retrieve hobby context from UKB + User Profiles
  5. Contextualize with relatable references from the student's interests
- **Example**: Korean female HS junior in Saratoga, CA who likes KPOP (BTS, BlackPink):
  > "Jenny and JongKuk had 100,000 followers. If Jenny got in a scandal and lost 50,000 followers, she would be left with 50,000 followers. What percentage did she lose?"
- **Interactor services used**:
  - **User Knowledge Base (UKB)**: Stores hobby domain knowledge — what KPOP is, BTS/BlackPink member names, relevant terms/scenarios. Enables semantic retrieval so agents can find contextually appropriate references.
  - **User Profiles**: Stores the student's selected hobby preferences (memory.facts)
  - **AI Agents**: Hobby Discovery Agent researches hobbies; Question Creator uses hobby context
- **Fallback**: Generic questions when hobby context doesn't naturally fit the topic

### 4b. Multi-Agent Question Validation (RESOLVED)
- **Decision**: Use 3-agent pipeline for derivative question generation to ensure 100% answer correctness
- **Process**:
  1. **Agent 1 (Question Creator)**: Creates derivative question with simple word/number changes + hobby context
  2. **Agent 2 (Answer Creator)**: Independently solves the new question (doesn't see Agent 1's answer)
  3. **Agent 3 (Validator)**: Compares Agent 1's question, Agent 2's answer, and original source for consistency
- **Only questions passing all 3 agents are stored**; failures are logged but never shown
- **Modeled as**: Interactor Supporting Assistants under an orchestrator

### 4c. Region-Based Lesson Platform Discovery (RESOLVED)
- **Decision**: Platforms for lesson discovery depend on region, school district, and country
- **Approach**: System discovers appropriate educational platforms based on student's location profile
- **Examples**: YouTube (global), Khan Academy (global), but also local/regional platforms per country
- **Implementation**: Content Discovery Agent selects platforms based on student profile demographics

### 5. Multi-Language Implementation
- **Reference**: interactor-website patterns
- **To research**: How interactor-website handles i18n
- **Considerations**: Content discovery across languages, question translation, UI localization

---

## Competitive Analysis

| Platform | Strengths | Weaknesses | StudySmart Differentiator |
|----------|-----------|------------|--------------------------|
| **Khan Academy** | Free, video lessons, exercises | Not adaptive, generic (not per-school) | Per-school content, adaptive testing, textbook-linked |
| **Quizlet** | Card-based review, user-generated | No adaptive testing, no content discovery | AI-powered content discovery, adaptive assessment |
| **Chegg** | Step-by-step solutions | Subscription cost, no adaptive testing | Test readiness scoring, targeted practice |
| **Anki** | Spaced repetition, customizable | Manual card creation, steep learning curve | Auto-generated cards, AI extraction from textbooks |
| **AP Classroom** | Official AP content | Only AP, limited practice | Multi-subject, adaptive, mobile-first |

### Key Differentiators
1. **Automatic content discovery** — no manual content creation needed
2. **Per-school question tagging** — relevance to specific school's curriculum
3. **Adaptive assessment with readiness scoring** — "am I ready for the test?"
4. **Textbook-linked questions** — see exactly where to review
5. **Tinder-style mobile quick tests** — engaging daily study habit

---

## Technical Research Notes

### OCR-First Pipeline Architecture
```
Upload (PDF/Image)
       │
       ▼
┌──────────────┐
│ OCR Engine   │ → Text + images with position metadata
│ (Tesseract/  │   (page, bounding box, section)
│  Cloud OCR)  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Metadata     │ → Store extracted content with mappings
│ Storage      │   back to source pages/images
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ LLM Agent    │ → Send relevant text chunks (not full PDF)
│ (via         │   for question extraction, classification
│ Interactor)  │   Token cost: ~10-50x reduction vs raw PDF
└──────────────┘
```

### File Storage Strategy
- **Phase 1 (Development)**: Local storage in `priv/static/uploads/`
- **Phase 2 (Production)**: AWS S3 via storage abstraction layer
- **Implementation**: Build behind a behaviour/interface module so swap is config-only

### Interactor Agent Architecture (Planned)

| Agent | Type | Tools | Purpose |
|-------|------|-------|---------|
| StudySmart Orchestrator | Primary | delegate_to_assistant | Routes tasks to specialized agents |
| Hobby Discovery Agent | Supporting | web_search, ukb_store | Research hobbies by demographics, store in UKB |
| Content Discovery Agent | Supporting | web_search, scrape_content | Find online questions, videos, lessons (region-aware) |
| Question Extraction Agent | Supporting | ocr_process, extract_questions | Extract Q&A from processed OCR text |
| Assessment Evaluator Agent | Supporting | query_question_db, evaluate_answer | Evaluate free-response answers |
| Study Guide Generator Agent | Supporting | query_weakness_data, format_guide | Generate personalized study guides |
| Question Creator Agent | Supporting | query_topic_data, get_hobby_context | Create derivative questions with hobby context |
| Answer Creator Agent | Supporting | solve_question | Independently solve generated questions |
| Question Validator Agent | Supporting | compare_answers | Validate question+answer consistency |
