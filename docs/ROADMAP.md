# FunSheep Feature Roadmap

Future feature ideas and upgrade plans. Items here are not prioritized or committed — they represent the backlog of possibilities.

---

## Plans Index

Full implementation documents live in `docs/ROADMAP/`. Each file is a self-contained prompt for a Claude Code session.

Plans are ordered by impact for a high school student preparing for finals.

| # | Feature | Category | Document | Status |
|---|---------|----------|----------|--------|
| 1 | Readiness by Topic — three UX states + teacher/parent views | Learning Engine | [ROADMAP/funsheep-readiness-by-topic.md](ROADMAP/funsheep-readiness-by-topic.md) | Planning |
| 2 | Custom Fixed-Question Tests | Learning Engine | [ROADMAP/funsheep-custom-fixed-question-tests.md](ROADMAP/funsheep-custom-fixed-question-tests.md) | Planning |
| 3 | Confidence-Based Scoring (Don't Know / Not Sure / I Know) | Learning Engine | [ROADMAP/confidence-based-scoring.md](ROADMAP/confidence-based-scoring.md) | Research & Proposal |
| 4 | Study References — inline practice references + Readiness Study Hub | Learning Engine | [ROADMAP/funsheep-study-references.md](ROADMAP/funsheep-study-references.md) | Planning |
| 5 | AI-Scored Freeform Grading — 0–10 rubric scoring with explanation for short-answer/free-response | Learning Engine | [ROADMAP/funsheep-scored-freeform-grading.md](ROADMAP/funsheep-scored-freeform-grading.md) | Planning |
| 6 | Essay Tests — exam-specific rubric grading, auto-save, model responses (AP, GRE, LSAT, Bar, ACT) | Learning Engine | [ROADMAP/funsheep-essay-tests.md](ROADMAP/funsheep-essay-tests.md) | Planning |
| 7 | Memory Span — personal forgetting-curve insight | Learning Engine | [ROADMAP/funsheep-memory-span.md](ROADMAP/funsheep-memory-span.md) | Planning |
| 8 | Question Bank — hierarchical browse + role-scoped management (admin, teacher, student, parent) | Platform & Content | [ROADMAP/funsheep-question-bank.md](ROADMAP/funsheep-question-bank.md) | Planning |
| 9 | OCR Throughput Strategy (Tier 1–4 infra + UX) | Platform & Content | [ROADMAP/funsheep-ocr-throughput-strategy.md](ROADMAP/funsheep-ocr-throughput-strategy.md) | Draft — Tier 1 actionable now |
| 10 | Questions with Images & Graphs — end-to-end figure support (OCR extraction, web scrape, AI gen) | Platform & Content | [ROADMAP/funsheep-questions-with-images-and-graphs.md](ROADMAP/funsheep-questions-with-images-and-graphs.md) | Planning |
| 11 | Student Onboarding — Parent & Teacher Flows | Platform & Content | [ROADMAP/funsheep-student-onboarding.md](ROADMAP/funsheep-student-onboarding.md) | Planning |
| 12 | School Course Catalog & One-Click Enrollment | Platform & Content | [ROADMAP/funsheep-school-course-catalog.md](ROADMAP/funsheep-school-course-catalog.md) | Planning |
| 13 | Auto-Populate Courses from External LMS (Google Classroom, Canvas) | Platform & Content | [ROADMAP/funsheep-auto-populate-courses.md](ROADMAP/funsheep-auto-populate-courses.md) | Planning |
| 14 | Community Content Validation (scoring, reputation, moderation) | Platform & Content | [ROADMAP/community-content-validation.md](ROADMAP/community-content-validation.md) | Draft |
| 15 | Fun Animations — sheep reactions, celebrations, per-page motion | Platform & Content | [ROADMAP/funsheep-fun-animations.md](ROADMAP/funsheep-fun-animations.md) | Planning |
| 16 | Sound Effects | Platform & Content | [ROADMAP/funsheep-sound-effects.md](ROADMAP/funsheep-sound-effects.md) | Planned |
| 17 | Peer Sharing — student↔student and parent↔parent | Social & Growth | [ROADMAP/funsheep-peer-sharing.md](ROADMAP/funsheep-peer-sharing.md) | Planning |
| 18 | Flock Shout Outs + Teacher Credit economy (Wool Credits) | Social & Growth | [ROADMAP/flock-shout-outs-and-credits.md](ROADMAP/flock-shout-outs-and-credits.md) | Planning |
| 19 | Teacher Credit System — canonical implementation spec | Social & Growth | [ROADMAP/funsheep-teacher-credit-system.md](ROADMAP/funsheep-teacher-credit-system.md) | Planning |
| 22 | Social Friends & Followers — follow graph, school directory, peer invites, course sharing, viral loops | Social & Growth | [ROADMAP/funsheep-social-friends-strategy.md](ROADMAP/funsheep-social-friends-strategy.md) | Planning |
| 20 | Subscription Purchase Flows (Flow A student-ask, B parent-initiated, C teacher-initiated) | Monetization | [ROADMAP/funsheep-subscription-flows.md](ROADMAP/funsheep-subscription-flows.md) | Planning |
| 21 | Premium Courses & Standardized Test Prep (SAT, ACT, AP, IB, LSAT, Bar, GMAT, MCAT) | Monetization | [ROADMAP/funsheep-premium-courses-and-tests.md](ROADMAP/funsheep-premium-courses-and-tests.md) | Planning |

### Quality Assessments

These are diagnostic documents, not feature plans.

| Assessment | Document |
|------------|----------|
| AP Biology Question Quality Audit | [ROADMAP/funsheep-ap-biology-question-quality-assessment.md](ROADMAP/funsheep-ap-biology-question-quality-assessment.md) |
| Platform Quality Assessment (AP Bio teacher perspective) | [ROADMAP/funsheep-platform-quality-assessment.md](ROADMAP/funsheep-platform-quality-assessment.md) |

### Archived Plans

Superseded or parked documents live in `docs/ROADMAP/Archives/`.

| Plan | Notes |
|------|-------|
| [Admin Section Build-Out](ROADMAP/Archives/funsheep-admin-section-plan.md) | Archived |
| [Parent Experience](ROADMAP/Archives/funsheep-parent-experience.md) | Archived |
| [Teacher Experience](ROADMAP/Archives/funsheep-teacher-experience.md) | Archived |

---

## Referral Program

### Parent Referral
- When a parent introduces another student, the referring parent gets **1 month free subscription**
- Trigger: new student signs up via referral link/code from a parent
- *See also*: `docs/ROADMAP/funsheep-peer-sharing.md` §6 for full referral attribution + reward structure

### Teacher Referral
- When a teacher introduces a student, the teacher receives **$10 credit**
- Credit can be used to provide a subscription for another student
- Credit expires at the end of the current school year
- Credit has **no monetary value** (cannot be cashed out)
- *See also*: `docs/ROADMAP/funsheep-teacher-credit-system.md` — Wool Credits is the more developed version of this idea; the "$10 credit" framing may be superseded by Wool Credits

---

## Community Contribution Rewards

### Test Schedule Upload Bonus
- A student, parent, or teacher can upload a course's test schedule
- Bonus: **1 month free subscription** (TBD — confirm reward)
- The uploaded schedule must be **confirmed by at least 5 students or parents** before the bonus is granted
- Requires a **schedule confirmation workflow**:
  - Uploader submits schedule
  - Other users in the same course can confirm or dispute it
  - Once 5 confirmations are reached, schedule is marked as verified and bonus is awarded
- *See also*: `docs/ROADMAP/community-content-validation.md` — references this confirmation workflow as a related open question

### Textbook Upload Bonus
- If someone uploads a textbook for a course that **has no textbook already uploaded**, they receive bonus credit
- Reward details TBD
- *See also*: `docs/ROADMAP/funsheep-teacher-credit-system.md` — material uploads already earn Wool Credits for teachers (2 uploads = 1 credit)

---

## School Platform Integrations

Integrate with the platforms students, parents, and teachers already use to manage schoolwork, so assignments, schedules, and announcements flow into FunSheep automatically instead of requiring manual upload.

### Google Classroom
- Pull in courses, assignments, due dates, and materials from the student's Google Classroom account
- Auto-create/match FunSheep courses from Google Classroom classes
- Sync assignment deadlines into FunSheep's test/assignment schedule
- *Full plan*: `docs/ROADMAP/funsheep-auto-populate-courses.md`

### Canvas LMS
- Pull courses and assignments via Canvas API
- Multi-tenant (each school has its own host)
- *Full plan*: `docs/ROADMAP/funsheep-auto-populate-courses.md`

### ParentSquare
- Ingest announcements, schedules, and teacher communications
- Surface relevant school events and deadlines inside FunSheep for parents
- *Status*: stub in `docs/ROADMAP/funsheep-auto-populate-courses.md`; no open API — full integration TBD

### Student Portals (district / school "kids' portal" systems)
- Integrate with common district portals students use to manage coursework (e.g., PowerSchool, Schoology, Canvas, Infinite Campus — exact list TBD)
- Import grades, assignments, syllabi, and test schedules where the portal's API allows
- Requires per-portal research on available APIs and auth flows
- *No full plan yet*
