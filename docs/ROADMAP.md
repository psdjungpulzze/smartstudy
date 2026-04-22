# FunSheep Feature Roadmap

Future feature ideas and upgrade plans. Items here are not prioritized or committed — they represent the backlog of possibilities.

---

## Referral Program

### Parent Referral
- When a parent introduces another student, the referring parent gets **1 month free subscription**
- Trigger: new student signs up via referral link/code from a parent

### Teacher Referral
- When a teacher introduces a student, the teacher receives **$10 credit**
- Credit can be used to provide a subscription for another student
- Credit expires at the end of the current school year
- Credit has **no monetary value** (cannot be cashed out)

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

### Textbook Upload Bonus
- If someone uploads a textbook for a course that **has no textbook already uploaded**, they receive bonus credit
- Reward details TBD

---

## School Platform Integrations

Integrate with the platforms students, parents, and teachers already use to manage schoolwork, so assignments, schedules, and announcements flow into FunSheep automatically instead of requiring manual upload.

### Google Classroom
- Pull in courses, assignments, due dates, and materials from the student's Google Classroom account
- Auto-create/match FunSheep courses from Google Classroom classes
- Sync assignment deadlines into FunSheep's test/assignment schedule

### ParentSquare
- Ingest announcements, schedules, and teacher communications
- Surface relevant school events and deadlines inside FunSheep for parents

### Student Portals (district / school "kids' portal" systems)
- Integrate with common district portals students use to manage coursework (e.g., PowerSchool, Schoology, Canvas, Infinite Campus — exact list TBD)
- Import grades, assignments, syllabi, and test schedules where the portal's API allows
- Requires per-portal research on available APIs and auth flows
