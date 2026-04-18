# Stakeholder Analysis

## Project Information

| Field | Value |
|-------|-------|
| **Project Name** | StudySmart |
| **Date** | 2026-04-17 |
| **Author** | Peter Jung |

---

## Stakeholder Register

### Internal Stakeholders

| Name | Role | Interest | Influence | Engagement Level |
|------|------|----------|-----------|------------------|
| Peter Jung | Product Owner / Developer | High | High | Manage Closely |

### External Stakeholders

| Name/Group | Role | Interest | Influence | Engagement Level |
|------------|------|----------|-----------|------------------|
| Students (K-12, Higher Ed) | Primary Users | High | Medium | Manage Closely |
| Parents | End users (parent role), monitor children's progress | High | High | Manage Closely |
| Teachers | End users (teacher role), manage class students | High | High | Manage Closely |
| Interactor Platform Team | Infrastructure provider | Medium | High | Keep Satisfied |

---

## Detailed Stakeholder Profiles

### Students (Primary Users)

| Attribute | Details |
|-----------|---------|
| **Role** | Primary end user |
| **Interest Level** | High |
| **Influence Level** | Medium |
| **Engagement Strategy** | Direct feedback, usage analytics |

**Goals & Interests**:
- Prepare for exams efficiently
- Know exactly what to study
- Quick study sessions on mobile
- Understand weak areas before the test

**Concerns & Risks**:
- Platform must be simple and not add study burden
- Questions must match actual exam content
- Must work on mobile for on-the-go studying
- Privacy concerns (especially for younger students)

**Success Criteria**:
- Improved test scores
- Reduced study time for same results
- Daily engagement with mobile quick tests

**Demographics**:
- Multiple countries, school systems, languages
- Various grade levels (K-12, higher education)
- Diverse nationalities and cultural backgrounds

---

### Parents (End Users — Parent Role)

| Attribute | Details |
|-----------|---------|
| **Role** | End user with parent role |
| **Interest Level** | High |
| **Influence Level** | High |
| **Engagement Strategy** | Progress dashboards, notifications, direct feedback |

**Goals & Interests**:
- Monitor children's test readiness and study progress
- See which subjects/topics their children are struggling with
- Ensure children are consistently using the platform
- Receive alerts when test dates are approaching and readiness is low
- Manage multiple children's accounts from a single parent account

**Concerns & Risks**:
- Dashboard must be clear and non-technical (at-a-glance understanding)
- Privacy: parent should only see their own linked children's data
- Must not create additional pressure — tool should feel supportive, not surveillance-like
- Linking to child accounts must be secure (invite/confirmation mechanism)

**Success Criteria**:
- Can view all linked children's readiness scores in one dashboard
- Receives timely notifications about upcoming tests and readiness gaps
- Can quickly identify which child needs the most attention on which subject

---

### Teachers (End Users — Teacher Role)

| Attribute | Details |
|-----------|---------|
| **Role** | End user with teacher role |
| **Interest Level** | High |
| **Influence Level** | High |
| **Engagement Strategy** | Class management tools, progress analytics, direct feedback |

**Goals & Interests**:
- Add students to their class roster and monitor progress across the class
- View aggregate and per-student readiness scores for their subject
- Assign test scopes and recommend practice activities to students
- Identify students who are falling behind before the exam
- Manage multiple classes and subjects

**Concerns & Risks**:
- Must handle large class sizes efficiently (30+ students per class)
- Class management must be simple — teachers have limited time
- Data isolation: teachers should only see their own linked students' data
- Integration with existing school workflows should be frictionless
- Must not duplicate work teachers already do in other systems

**Success Criteria**:
- Can onboard a full class roster quickly (bulk add or invite codes)
- Can identify struggling students at a glance from class dashboard
- Can assign targeted practice and see improvement over time
- Platform complements rather than replaces existing teaching workflow

---

## Notes

- Phase 1 includes student, parent, and teacher roles as end users
- Platform admin portal is a separate tier with its own authentication (Interactor Admin JWT)
- Parent and teacher features focus on monitoring and managing linked students
- School-level administration (district-wide management) is not in Phase 1 scope
