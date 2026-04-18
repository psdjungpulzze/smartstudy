# Requirements Document

## Project Information

| Field | Value |
|-------|-------|
| **Project Name** | [Name] |
| **Document Version** | 1.0 |
| **Last Updated** | [Date] |
| **Author** | [Name] |
| **Status** | Draft / In Review / Approved |

---

## Executive Summary

[Brief overview of the project and its goals - 2-3 paragraphs]

---

## Problem Statement

### Background
[Context and background information]

### Problem
[Clear statement of the problem being solved]

### Impact
[Who is affected and how]

### Success Metrics
| Metric | Current | Target | How Measured |
|--------|---------|--------|--------------|
| [Metric 1] | [Value] | [Value] | [Method] |
| [Metric 2] | [Value] | [Value] | [Method] |

---

## Scope

### In Scope
- [Feature/capability 1]
- [Feature/capability 2]
- [Feature/capability 3]

### Out of Scope
- [Excluded item 1]
- [Excluded item 2]

### Assumptions
- [Assumption 1]
- [Assumption 2]

### Constraints
- [Constraint 1]
- [Constraint 2]

---

## Functional Requirements

### FR-001: [Requirement Name]

**Priority**: Must Have / Should Have / Could Have / Won't Have

**Description**: [Detailed description]

**User Story**: As a [user type], I want [goal] so that [benefit].

**Acceptance Criteria**:
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] [Criterion 3]

**Notes**: [Additional information]

**Traceability (MANDATORY — fill during Planning phase)**:

| Traces To | IDs |
|-----------|-----|
| User Stories | US-XXX, US-XXX |
| Architecture Section | § X.X |
| Tasks | T-XXX, T-XXX, T-XXX |
| Test Cases | TC-XXX |

---

### FR-002: [Requirement Name]

**Priority**: [Priority]

**Description**: [Detailed description]

**User Story**: As a [user type], I want [goal] so that [benefit].

**Acceptance Criteria**:
- [ ] [Criterion 1]
- [ ] [Criterion 2]

**Traceability (MANDATORY — fill during Planning phase)**:

| Traces To | IDs |
|-----------|-----|
| User Stories | US-XXX, US-XXX |
| Architecture Section | § X.X |
| Tasks | T-XXX, T-XXX, T-XXX |
| Test Cases | TC-XXX |

---

## Non-Functional Requirements

### Performance

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-P01 | Page load time | < 2 seconds | High |
| NFR-P02 | API response time | < 200ms (p95) | High |
| NFR-P03 | Concurrent users | 1,000 | Medium |

### Security

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-S01 | Authentication | Multi-factor | High |
| NFR-S02 | Data encryption | At rest and in transit | High |
| NFR-S03 | Compliance | GDPR, SOC2 | High |

### Reliability

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-R01 | Uptime | 99.9% | High |
| NFR-R02 | Recovery time | < 1 hour | Medium |
| NFR-R03 | Data backup | Daily | High |

### Scalability

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-SC01 | Horizontal scaling | Auto-scale to demand | Medium |
| NFR-SC02 | Data growth | Support 10x growth | Medium |

### Usability

| NFR ID | Requirement | Target | Priority |
|--------|-------------|--------|----------|
| NFR-U01 | Accessibility | WCAG 2.1 AA | High |
| NFR-U02 | Mobile support | Responsive design | High |
| NFR-U03 | Browser support | Last 2 versions | Medium |

---

## Dependencies

### Internal Dependencies
| Dependency | Description | Owner | Status |
|------------|-------------|-------|--------|
| [System/Team] | [Description] | [Name] | [Status] |

### External Dependencies
| Dependency | Description | Provider | Risk Level |
|------------|-------------|----------|------------|
| [Service/API] | [Description] | [Provider] | [Low/Med/High] |

---

## Requirements Traceability

| Req ID | Business Goal | Test Case | Status |
|--------|---------------|-----------|--------|
| FR-001 | [Goal] | TC-001 | Not Started |
| FR-002 | [Goal] | TC-002 | Not Started |

---

## Glossary

| Term | Definition |
|------|------------|
| [Term 1] | [Definition] |
| [Term 2] | [Definition] |

---

## Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner | | | |
| Tech Lead | | | |
| Stakeholder | | | |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | [Date] | [Name] | Initial draft |

---

## Requirements Coverage Matrix (MANDATORY)

Before exiting Discovery, fill this matrix. Before exiting Planning, update the Tasks column. Before exiting Implementation, update the Status column.

| Req ID | Title | Priority | User Stories | Arch Section | Tasks | UI Tasks | Test Cases | Status |
|--------|-------|----------|-------------|--------------|-------|----------|-----------|--------|
| FR-001 | | Must/Should/Could | | | | | | |

### Validation Rules
1. **Every row must have values in ALL columns** before proceeding to Implementation
2. **Priority "Must" and "Should" requirements MUST have tasks** — no exceptions
3. **Every requirement with a user-facing component MUST have at least one UI task**
4. **"UI Tasks" column cannot be empty** for any user-facing requirement
5. **Tasks column must have at least 1 task per requirement** — if a requirement maps to 0 tasks, the task breakdown is incomplete
6. If any cell is empty, STOP and fill it before proceeding
