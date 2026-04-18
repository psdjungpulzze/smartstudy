# Project Requirements — Raw Instructions

Original requirements as provided by the project owner. This document preserves the instructions verbatim for reference. See `project-idea-intake.md` for the structured version.

---

## Development Phase 1

### Subject/Course Creation (과목 만들기)

1. 과목을 설정
    1. Input stage 1:
        1. 나라/주
        2. District/학교
        3. 과목/수업
        4. 학년
        5. 성별
        6. 국적
    2. Input stage 2: 취미
        1. 지역/성별/나이/국적에 따른 취미 discovery먼저 하고
        2. 그것을 DB에 넣은 다음
        3. 추천
    3. Input stage 3: 자료 upload
2. 수업 만들기 : 수업 관련 내용 Discovery
    1. 기존에 만들어진 비슷한 과목이 있는지 보고 학생에게 확인.
        1. 학생이 있다고 확인하면 그것을 바탕으로 수업이 만들어 짐
    2. 없으면 새로 만듬 (Search)
        1. 과목 identify와 Chapter/section 분류
            1. define해서 DB에 넣음
            2. 페이지와 이미지/pdf페이지도 중요함. 질문 할 때 학생에게 특정 교과나 supplement material 이미지/pdf를 보여 주며 알려 줄 수 있게
        2. Online에서 유출 문제들 서치. HTML, PDF, Docs, etc다 서치.
        3. 온라인에서 수업들 서치
            1. For example
                1. YouTube : Transcript 보고 가장 좋은 것
                2. Khan academy등등
        4. 질문 만들기
            1. Extract the questions from the uploaded file - intelligent identification of pages and sections
            2. 새로 만들 경우 서치 한 것들을 바탕으로 질문 만들기.
                1. 일단 찾은 것들을 모두 넣기. 질문 Source도 같이 저장 (link)
            3. 질문 마다 chapter/section 분류 생성. 나중에 질문 할때 학생들에게 교과서 어떤 부분 관련된 질문인지 보여 주기 위해.
            4. For example
                1. Question extraction
                    1. Extract the questions from the Test Prep Series AP Biology
                    2. Extract the questions from Chapter Review for each chapter
                    3. Check the number of questions extracted against the question numbers, so that the number of questions equal to the extracted
                    4. Make sure the questions all have answer associated with it.
                2. If PDF or image, perform OCR.
    3. 질문 마다 교과서 및 참고 자료 링크
        1. 질문 마다 topic을 설정

---

### Test Preparation (실제 시험 준비)

1. 시험 범위 설정
    1. 과목
    2. Chapter + sub-chapter
    3. 시험 유형 (학교에서 준 것 있으면)
    4. 시험 날짜 스케줄 설정 (upcoming test scheduling)
    5. 시험 형식 업로드 시 → 동일 형식의 모의고사 생성 (test format replication)

2. Assessment단계 (adaptive/progressive testing)
    1. Goal is to identify what student knows and don't know.
    2. Research the best ways to do this.
        1. For example, make sure the student is tested on at least three questions on a topic
        2. If the student gets any of the three wrong, test again adaptively to verify
        3. Start easy and make it progressively harder to test the student's depth of knowledge
        4. Because of copyright, we can not use the exact questions from the source (text, supplement, etc). Change the numbers or words slightly to make it slightly different.
            1. When you create a new question, store it in the DB, so that it can be used in the future
        5. Always use the stored questions before creating new. Only after the student have finished the questions, create new.
        6. Keep history of the question.
            1. If answered correct or incorrect
            2. Make it possible to extract only the correct or incorrect answered questions
        7. For questions that require answer, use AI agent to provide correction (answer). Also, associated answers.
    3. Provide where the weakness are.
        1. Test Readiness
            - Test scope
            - Each chapter score
            - Each topic score
            - Aggregate to total estimate test score.
    4. Provide study guide
        1. What topics the student needs to study more.
        2. Show the pages.

3. Practice tests
    1. Goal is to practice the questions that the student is scoring lower in
    2. The user experience can be similar to assessment
    3. It's a repetition of testing and giving learning materials to know what the student is getting wrong.

4. Mobile quick tests
    1. Quick card-based question.
    2. Like Tinder for studying. The student quickly goes through questions with:
        1. Options:
            1. I know this: Mark as "I know this" and skip
            2. I don't know this: Provide short explanation first. Then links to video and other lessons for more detail (install in-product-browser if needed)
            3. Answer: Provide a way to answer (similar to assessment and practice test)
            4. Skip
        2. Keep record to provide readiness score

---

### Cross-Cutting Requirements

- Question dynamic generation
    - 질문 없으면 생성
    - 생성된 질문은 저장.
- Output/Print
    - 공부가 필요한 부분들을 Google Docs, Docs, PDF등으로 뽑아 줌
    - 여기 저기 export할 수 있게 함
- Test Readiness
    - Test scope
    - Each chapter score
    - Each topic score
    - Aggregate to total estimate test score.
- Multi-language support (refer to interactor-website)

---

### Additional Requirements (Added Later)

- Make sure the questions are tagged or categorized per school.
- To reduce AI token cost, use OCR to extract text and images from uploaded files first, instead of sending entire files to LLM. Mark extracted text and images properly so they can be mapped back to the actual textbook page/image.
- Image storage: save locally for now, move to AWS S3 later.
- **This application MUST make full use of Interactor platform services** (interactor-workspace). Use Interactor for: authentication (Account Server), AI agents, workflows, credential management, webhooks/streaming, data sources, user profiles, billing. Do NOT build custom equivalents for services that Interactor already provides.

**Multi-role support (added 2026-04-17):**
- Three end-user roles: **student**, **parent**, **teacher** (+ platform admin as separate tier)
- Role selected during profile setup (Stage 1) and stored in Interactor Account Server user `metadata.role`
- Parents and teachers can have multiple students under their guidance (parent-student and teacher-student relationships)
- Parents can view linked children's test readiness scores, progress, and study activity
- Teachers can add students to their class, monitor progress, and assign practice activities
- Separate admin portal for platform management — admins authenticate via **Interactor Admin JWT** (not User JWT)
- All end users (student/parent/teacher) authenticate via **Interactor User JWT** (OAuth/OIDC)
- Role enforcement at StudySmart application layer, NOT at Interactor auth layer
- Use **Interactor UKB** (User Knowledge Base) for hobby domain knowledge AND curriculum/subject knowledge (semantic retrieval for AI agents)
- Use **Interactor UDB** (User Database) as agent-queryable data layer for student progress data (dynamic tables with per-user isolation)

### Clarifications (Added 2026-04-17)

**Hobby personalization (clarified):**
- Research hobbies based on demographics → store hobby domain knowledge in Interactor UKB → student selects preferences → use to contextualize questions AND explanations
- Example: Korean female HS junior in Saratoga, CA, KPOP fan → "Jenny and JongKuk had 100,000 followers. If Jenny lost 50,000, what percentage did she lose?"
- Use Interactor User Knowledge Base (UKB) for hobby domain knowledge, User Profiles for preferences

**Copyright-safe question derivation (clarified):**
- Simple word and number changes from source questions
- Must be 100% sure the new answer is correct
- Use multi-agent validation: Agent 1 creates question, Agent 2 creates answer independently, Agent 3 validates consistency
- Only pass all 3 → stored. Failures logged, never shown.

**OCR tool (decided):**
- Google Cloud Vision OCR (~98% accuracy, ~$1.50/1K pages). Worth the cost for textbook quality.

**Lesson platform discovery (clarified):**
- Platforms vary by region, school district, and country
- System must discover appropriate platforms based on student's location

**Test scheduling & format replication (added 2026-04-17):**
- Student can schedule upcoming test dates
- Dashboard shows countdown + readiness score per scheduled test
- If student uploads a test format/sample, system generates practice tests in the exact same format (same question types, count, sections, point distribution, timing)
- Format-matched practice tests are recommended a few days before the test date
- Timed mode available to simulate real exam conditions
