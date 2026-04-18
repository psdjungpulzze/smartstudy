# User Stories — FunSheep

## Story Map

```
                              Student Journey
┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│  Setup       │  Course      │  Assessment  │  Practice    │  Quick       │
│  Profile     │  Creation    │  & Readiness │  & Review    │  Study       │
└──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┘
       │              │              │              │              │
       ▼              ▼              ▼              ▼              ▼
  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
  │ US-001  │   │ US-004  │   │ US-007  │   │ US-010  │   │ US-011  │
  │ Profile │   │ Match   │   │ Set Test│   │ Practice│   │ Mobile  │
  │ Setup   │   │ Course  │   │ Scope   │   │ Tests   │   │ Cards   │
  └─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
       │              │              │              │              │
       ▼              ▼              ▼              ▼              ▼
  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
  │ US-002  │   │ US-005  │   │ US-008  │   │ US-012  │   │ US-014  │
  │ Upload  │   │ Content │   │ Adaptive│   │ Study   │   │ Export  │
  │ Material│   │ Discover│   │ Testing │   │ Guide   │   │         │
  └─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
       │              │              │
       ▼              ▼              ▼
  ┌─────────┐   ┌─────────┐   ┌─────────┐
  │ US-003  │   │ US-006  │   │ US-009  │
  │ Hobby   │   │ Question│   │ Test    │
  │ Personl │   │ Extract │   │Readiness│
  └─────────┘   └─────────┘   └─────────┘
```

---

## Epic: Profile & Course Setup

### US-001: Student Profile Setup

**Epic**: Profile & Course Setup | **Priority**: Must Have | **Points**: 5

```
As a new student,
I want to enter my school, subject, and grade information,
So that the platform can find content relevant to my specific course.
```

**Acceptance Criteria**:

**Scenario 1: Complete profile setup**
```
Given I am a new student on the setup page
When I enter my country, school district, subject, grade, gender, and nationality
Then my profile is saved
And I proceed to the hobbies stage
```

**Scenario 2: Partial completion**
```
Given I have completed Stage 1 but not Stage 2
When I return to the app later
Then I resume from Stage 2 (hobbies)
And my Stage 1 data is preserved
```

---

### US-002: Material Upload

**Epic**: Profile & Course Setup | **Priority**: Must Have | **Points**: 3

```
As a student,
I want to upload my textbook PDFs and images,
So that questions can be extracted from my actual course materials.
```

**Acceptance Criteria**:

**Scenario 1: Upload PDF**
```
Given I am on Stage 3 of setup
When I upload a textbook PDF
Then the file is accepted and queued for OCR processing
And I see upload progress and confirmation
```

**Scenario 2: Upload image**
```
Given I am on Stage 3 of setup
When I upload photos of textbook pages
Then the images are accepted and queued for OCR processing
```

---

### US-003: Hobby-Based Question & Explanation Personalization

**Epic**: Profile & Course Setup | **Priority**: Must Have | **Points**: 8

```
As a student,
I want questions and explanations to reference my hobbies and interests,
So that studying feels engaging and relatable to things I care about.
```

**Acceptance Criteria**:

**Scenario 1: Hobby discovery and selection**
```
Given I am on Stage 2 of setup
When the system researches hobbies for my demographics (Korean, female, HS junior, Saratoga CA)
Then I see hobby suggestions like KPOP, K-Drama, Tennis, etc.
And I can select my favorites (e.g., KPOP - BTS, BlackPink)
And my preferences are saved
```

**Scenario 2: Hobby-contextualized question**
```
Given I like KPOP (BTS, BlackPink)
When a math question is generated about percentages
Then it references KPOP context: "Jenny and JongKuk had 100,000 followers..."
Instead of generic: "A store had 100,000 items..."
```

**Scenario 3: Hobby-contextualized explanation**
```
Given I got a question wrong and tapped "I don't know this"
When the explanation is generated
Then it uses my hobby context in the explanation
And I see relatable examples from my interests
```

**Scenario 4: Fallback for unfit topics**
```
Given the topic doesn't naturally fit hobby context (e.g., chemistry formulas)
When a question is generated
Then it uses a generic context without forcing hobby references
```

---

## Epic: Course Creation

### US-004: Match Existing Course

**Epic**: Course Creation | **Priority**: Must Have | **Points**: 5

```
As a student,
I want to see if my course already exists in the system,
So that I can start studying immediately without waiting for content discovery.
```

**Acceptance Criteria**:

**Scenario 1: Course exists**
```
Given similar courses exist for my school and subject
When I view the matches
And I confirm one matches my course
Then I am enrolled in that course with its existing questions and structure
```

**Scenario 2: No match**
```
Given no similar courses exist
When I see "no matches found"
Then the system begins creating a new course via content discovery
```

---

### US-005: Automatic Content Discovery

**Epic**: Course Creation | **Priority**: Must Have | **Points**: 8

```
As a student,
I want the platform to automatically find practice questions and video lessons online,
So that I have comprehensive study materials without manual searching.
```

**Acceptance Criteria**:

**Scenario 1: Online question discovery**
```
Given a new course is being created
When the content discovery agent runs
Then it searches HTML, PDF, and Docs sources for practice questions
And stores all found questions with source links
And classifies each question by chapter/section
```

**Scenario 2: Video lesson discovery**
```
Given a new course is being created
When the content discovery agent runs
Then it searches YouTube transcripts and Khan Academy for relevant lessons
And ranks results by relevance and quality
```

---

### US-006: Question Extraction from Uploads

**Epic**: Course Creation | **Priority**: Must Have | **Points**: 8

```
As a student,
I want questions automatically extracted from my uploaded textbook,
So that I can practice from my actual course materials.
```

**Acceptance Criteria**:

**Scenario 1: Successful extraction**
```
Given I uploaded a textbook PDF
When OCR processing completes
Then questions are extracted with page numbers and section mappings
And each question has an associated answer
And extraction count is verified against expected numbers
```

**Scenario 2: Reference linking**
```
Given questions have been extracted
When I view a question during assessment
Then I can see which textbook page/section it relates to
And I can view the actual textbook page image
```

---

## Epic: Assessment & Readiness

### US-007: Define Test Scope & Schedule

**Epic**: Assessment & Readiness | **Priority**: Must Have | **Points**: 5

```
As a student preparing for a test,
I want to specify which chapters my test covers and set the test date,
So that the platform focuses on relevant material and plans my study timeline.
```

**Acceptance Criteria**:

**Scenario 1: Set test scope and date**
```
Given I have an upcoming exam
When I create a new test schedule
Then I can select the subject, chapters, and sub-chapters
And I can set the test date
And I can optionally upload a test format/sample
```

**Scenario 2: Dashboard with countdown**
```
Given I have scheduled tests
When I view my dashboard
Then I see upcoming tests sorted by date
And each shows days remaining and my current readiness score
```

---

### US-016: Test Format Replication

**Epic**: Assessment & Readiness | **Priority**: Must Have | **Points**: 8

```
As a student,
I want to practice with tests that look exactly like my real exam,
So that I'm fully prepared for the actual test format and timing.
```

**Acceptance Criteria**:

**Scenario 1: Upload test format**
```
Given I have a sample test from my school
When I upload the test format (PDF or image)
Then the system analyzes it to identify question types, count, sections, point distribution, and time limits
And confirms the format structure with me
```

**Scenario 2: Generate format-matched practice test**
```
Given a test format has been analyzed
When I request a practice test
Then it matches the exact format: same number of questions, same types, same section order
And questions are drawn from my test scope topics
And all questions have validated correct answers (multi-agent pipeline)
```

**Scenario 3: Timed practice mode**
```
Given the test format includes a time limit
When I start a format-matched practice test
Then a timer counts down matching the real exam duration
And I see time remaining throughout the test
```

**Scenario 4: Pre-test recommendation**
```
Given my test is scheduled for 5 days from now
When I open the app
Then the platform recommends taking a format-matched practice test
And shows my readiness score: "3 days left, readiness: 72%"
```

---

### US-008: Adaptive Assessment

**Epic**: Assessment & Readiness | **Priority**: Must Have | **Points**: 13

```
As a student,
I want the platform to adaptively test me starting from easy questions,
So that it can efficiently identify exactly what I know and don't know.
```

**Acceptance Criteria**:

**Scenario 1: Progressive difficulty**
```
Given I am taking an assessment
When I answer easy questions correctly
Then the difficulty increases
And I am tested on deeper knowledge
```

**Scenario 2: Knowledge gap verification**
```
Given I answered a question incorrectly
When the adaptive system detects a potential gap
Then it tests me on at least 2 more questions on that topic
To verify the gap is real
```

**Scenario 3: Free-response evaluation**
```
Given a question requires a written answer
When I submit my response
Then the AI agent evaluates my answer
And provides corrections and model answers
```

**Scenario 4: Question sourcing**
```
Given I am being tested
When stored questions exist for the topic
Then stored questions are used first
And new questions are generated only after stored ones are exhausted
And generated questions are copyright-safe derivatives
```

---

### US-009: View Test Readiness

**Epic**: Assessment & Readiness | **Priority**: Must Have | **Points**: 5

```
As a student,
I want to see my estimated test score broken down by chapter and topic,
So that I know exactly where I stand and what to focus on.
```

**Acceptance Criteria**:

**Scenario 1: Dashboard view**
```
Given I have completed at least one assessment
When I view the Test Readiness dashboard
Then I see per-chapter scores, per-topic scores, and aggregate estimated score
And the scores reflect my most recent performance
```

---

## Epic: Practice & Review

### US-010: Targeted Practice Tests

**Epic**: Practice & Review | **Priority**: Must Have | **Points**: 5

```
As a student,
I want to practice questions I'm scoring lower on,
So that I can improve my weak areas before the test.
```

---

### US-011: Mobile Quick Tests (Tinder-Style)

**Epic**: Practice & Review | **Priority**: Must Have | **Points**: 8

```
As a student on the go,
I want to swipe through study cards quickly on my phone,
So that I can study in short bursts during commutes or breaks.
```

**Acceptance Criteria**:

**Scenario 1: Card interactions**
```
Given I am on the mobile quick test screen
When a question card appears
Then I can choose: "I know this", "I don't know this", "Answer", or "Skip"
```

**Scenario 2: "I don't know this" flow**
```
Given I tap "I don't know this"
When the explanation appears
Then I see a short explanation first
And links to video lessons and other resources
And an in-product browser opens for external links
```

---

### US-012: AI-Generated Study Guide

**Epic**: Practice & Review | **Priority**: Must Have | **Points**: 5

```
As a student,
I want a personalized study guide based on my assessment results,
So that I know exactly what to review and where to find the material.
```

---

## Epic: Export & Utility

### US-013: Export Study Materials

**Epic**: Export & Utility | **Priority**: Should Have | **Points**: 3

```
As a student,
I want to export my study guide and weak areas to PDF or Google Docs,
So that I can review them offline or print them out.
```

---

### US-014: Multi-Language Support

**Epic**: Export & Utility | **Priority**: Should Have | **Points**: 5

```
As a student who speaks a different language,
I want to use the platform in my native language,
So that I can understand the interface without language barriers.
```

---

### US-015: Multi-Agent Question Generation with Validation

**Epic**: Cross-Cutting | **Priority**: Must Have | **Points**: 8

```
As the platform,
I want to generate derivative questions using a 3-agent pipeline,
So that every generated question has a verified correct answer.
```

**Acceptance Criteria**:

**Scenario 1: Successful 3-agent validation**
```
Given a derivative question needs to be created for a topic
When Agent 1 creates the question with changed numbers/words (+ hobby context if applicable)
And Agent 2 independently solves the question to produce an answer
And Agent 3 validates that the question, answer, and original source are consistent
Then the question is stored in DB for future use
```

**Scenario 2: Validation failure**
```
Given Agent 3 finds inconsistency between the question and answer
When the validation fails
Then the question is logged for review but NOT stored for student use
And the system retries with a new derivative
```

---

## Epic: Multi-Role & Relationships

### US-017: Parent Views Student Readiness

**Epic**: Multi-Role & Relationships | **Priority**: Must Have | **Points**: 5

```
As a parent,
I want to see my child's test readiness scores and study progress,
So that I know if they are prepared for their upcoming exams and where they need help.
```

**Acceptance Criteria**:

**Scenario 1: Parent dashboard**
```
Given I am logged in as a parent with linked student accounts
When I view my dashboard
Then I see each linked child's name, subjects, and current readiness scores
And upcoming test dates with countdown and readiness percentage
```

**Scenario 2: Drill into child's progress**
```
Given I see my child's readiness score is 65% for Math
When I click on that subject
Then I see per-chapter and per-topic breakdowns
And I see which topics my child is weakest in
```

**Scenario 3: Multiple children**
```
Given I have 3 children linked to my account
When I view my parent dashboard
Then I see all 3 children's readiness at a glance
And I can switch between children easily
```

---

### US-018: Teacher Manages Class Students

**Epic**: Multi-Role & Relationships | **Priority**: Must Have | **Points**: 8

```
As a teacher,
I want to add students to my class and monitor their progress,
So that I can identify struggling students and provide targeted support before exams.
```

**Acceptance Criteria**:

**Scenario 1: Add students to class**
```
Given I am logged in as a teacher
When I create a class and add students (via invite code or direct add)
Then the students appear in my class roster
And I can see their readiness scores for my subject
```

**Scenario 2: Class progress overview**
```
Given I have a class of 30 students
When I view the class dashboard
Then I see aggregate class readiness and per-student scores
And students below a threshold are highlighted for attention
```

**Scenario 3: Assign practice**
```
Given I see a student struggling with Chapter 5
When I assign a targeted practice test for Chapter 5
Then the student receives a notification to complete the practice
And I can track whether they completed it and their score
```

---

### US-019: Admin Platform Management

**Epic**: Multi-Role & Relationships | **Priority**: Must Have | **Points**: 8

```
As a platform admin,
I want a separate admin portal to manage users, courses, and platform settings,
So that I can maintain the system securely without mixing with end-user features.
```

**Acceptance Criteria**:

**Scenario 1: Separate admin login**
```
Given I am a platform admin
When I navigate to the admin portal URL
Then I see a separate login page
And I authenticate via Interactor Admin JWT (not User JWT)
```

**Scenario 2: User management**
```
Given I am logged into the admin portal
When I view the users section
Then I can see all users with their roles (student/parent/teacher)
And I can edit roles, deactivate accounts, and view activity
```

**Scenario 3: Platform analytics**
```
Given I am logged into the admin portal
When I view the analytics dashboard
Then I see platform-wide stats: total users, courses, questions, usage trends
And I can filter by role, school, or date range
```

---

### US-020: Parent/Teacher Adds Student

**Epic**: Multi-Role & Relationships | **Priority**: Must Have | **Points**: 5

```
As a parent,
I want to link my account to my child's student account,
So that I can monitor their study progress and test readiness.
```

**Acceptance Criteria**:

**Scenario 1: Link via invite code**
```
Given my child has a FunSheep student account
When I enter their invite code on my parent dashboard
Then the link request is sent to my child for confirmation
And once confirmed, their data appears on my dashboard
```

**Scenario 2: Teacher links students**
```
Given I am a teacher creating a new class
When I generate a class invite code and share it with students
Then students who enter the code are linked to my class
And I can see their progress immediately after linking
```

**Scenario 3: Remove linked student**
```
Given I have a student linked to my account
When I remove the link
Then I no longer see that student's data
And the student's account is unaffected
```

---

## Backlog Summary

| ID | Title | Epic | Priority | Points | Status |
|----|-------|------|----------|--------|--------|
| US-001 | Student Profile Setup | Setup | Must Have | 5 | Backlog |
| US-002 | Material Upload | Setup | Must Have | 3 | Backlog |
| US-003 | Hobby Personalization | Setup | Must Have | 8 | Backlog |
| US-004 | Match Existing Course | Course Creation | Must Have | 5 | Backlog |
| US-005 | Content Discovery | Course Creation | Must Have | 8 | Backlog |
| US-006 | Question Extraction | Course Creation | Must Have | 8 | Backlog |
| US-007 | Define Test Scope & Schedule | Assessment | Must Have | 5 | Backlog |
| US-008 | Adaptive Assessment | Assessment | Must Have | 13 | Backlog |
| US-009 | Test Readiness Dashboard | Assessment | Must Have | 5 | Backlog |
| US-010 | Practice Tests | Practice | Must Have | 5 | Backlog |
| US-011 | Mobile Quick Tests | Practice | Must Have | 8 | Backlog |
| US-012 | Study Guide Generation | Practice | Must Have | 5 | Backlog |
| US-013 | Export Study Materials | Export | Should Have | 3 | Backlog |
| US-014 | Multi-Language Support | Export | Should Have | 5 | Backlog |
| US-015 | Multi-Agent Question Validation | Cross-Cutting | Must Have | 8 | Backlog |
| US-016 | Test Format Replication | Assessment | Must Have | 8 | Backlog |
| US-017 | Parent Views Student Readiness | Multi-Role | Must Have | 5 | Backlog |
| US-018 | Teacher Manages Class Students | Multi-Role | Must Have | 8 | Backlog |
| US-019 | Admin Platform Management | Multi-Role | Must Have | 8 | Backlog |
| US-020 | Parent/Teacher Adds Student | Multi-Role | Must Have | 5 | Backlog |
| | | | **Total** | **128** | |
