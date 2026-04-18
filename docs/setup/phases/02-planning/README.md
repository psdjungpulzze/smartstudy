# Phase 2: Planning

## Overview

The Planning phase translates requirements into a concrete implementation plan, including architecture design, task breakdown, and risk assessment.

## Objectives

- Design system architecture
- Select technologies
- Break down work into tasks
- Identify and mitigate risks
- Document architectural decisions

## Duration

Typical: 1-2 weeks (scale based on project complexity)

---

## Deliverables

### 1. Architecture Design Document
Template: [architecture-template.md](./architecture-template.md)
- System overview
- Component design
- Data model
- API contracts

### 2. Task Breakdown
Template: [task-breakdown.md](./task-breakdown.md)
- Feature decomposition
- Task dependencies
- Priority assignment

### 3. Risk Assessment
Template: [risk-assessment.md](./risk-assessment.md)
- Technical risks
- Mitigation strategies
- Contingency plans

### 4. Architecture Decision Records (ADRs)
Template: [../../templates/adr-template.md](../../templates/adr-template.md)
- Technology choices
- Design patterns
- Trade-off analysis

---

## Process

### Step 1: Architecture Design

1. Review requirements from Discovery
2. Identify system components
3. Design component interactions
4. Define data model
5. Specify API contracts

**Output**: Architecture design document

### Step 2: Technology Selection

1. Evaluate technology options
2. Consider team expertise
3. Assess scalability needs
4. Document decisions in ADRs

**Output**: Technology stack decision with ADRs

### Step 3: Task Breakdown

1. Decompose features into tasks
2. Identify dependencies
3. Estimate effort
4. Assign priorities

**Output**: Task backlog

### Step 4: Risk Assessment

1. Identify technical risks
2. Assess impact and probability
3. Define mitigation strategies
4. Create contingency plans

**Output**: Risk register

### Step 5: Planning Review

1. Review with stakeholders
2. Validate feasibility
3. Adjust based on feedback
4. Get sign-off

**Output**: Approved plan

---

## Checklist

### Architecture Design
- [ ] System architecture defined
- [ ] Component diagram created
- [ ] Data model designed
- [ ] API contracts specified
- [ ] Integration points identified
- [ ] Security considerations addressed

### Technology Selection
- [ ] Technology stack decided
- [ ] Framework choices documented
- [ ] Infrastructure requirements defined
- [ ] Third-party services selected
- [ ] ADRs created for major decisions

### Task Breakdown
- [ ] Features broken into tasks
- [ ] Dependencies identified
- [ ] Priority assigned
- [ ] Effort estimated (if required)
- [ ] Sprint/milestone planning done

### Risk Assessment
- [ ] Technical risks identified
- [ ] Business risks identified
- [ ] Mitigation strategies defined
- [ ] Contingency plans created
- [ ] Risk owners assigned

### Documentation
- [ ] Architecture document complete
- [ ] ADRs written
- [ ] Design decisions recorded
- [ ] API documentation started

---

## Exit Criteria

Before moving to Implementation phase:

1. ✅ Architecture approved by technical leads
2. ✅ Technology decisions documented
3. ✅ Tasks created and prioritized
4. ✅ Risks identified with mitigation plans
5. ✅ Team capacity confirmed
6. ✅ Development environment ready
7. ✅ Every requirement (FR-XXX) has at least one task (T-XXX)
8. ✅ Every user-facing requirement has a dedicated UI task
9. ✅ No task estimated > 1 day without subtasks
10. ✅ Requirements Coverage Matrix has Tasks and UI Tasks columns filled
11. ✅ Coverage report shows 100% for "Must" requirements
12. ✅ No raw requirement downgraded to "Should" or "Could"

---

## AI Collaboration Tips

### Effective Prompts

```
"Design the architecture for [feature/system] with these requirements:
- [Requirement 1]
- [Requirement 2]
Consider: scalability, security, maintainability"
```

```
"Break down [feature] into implementation tasks.
Include: task description, dependencies, estimated complexity"
```

```
"What risks should we consider for [approach/technology]?
Include: technical risks, mitigation strategies"
```

```
"Create an ADR for choosing [option A] over [option B] for [requirement].
Include: context, decision, consequences"
```

```
"Evaluate [technology A] vs [technology B] for [use case].
Consider: performance, team expertise, community support, cost"
```

```
"Define the API contract for [feature].
Include: endpoints, request/response formats, error handling"
```

---

## Templates

- [Architecture Template](./architecture-template.md)
- [Task Breakdown](./task-breakdown.md)
- [Risk Assessment](./risk-assessment.md)
- [ADR Template](../../templates/adr-template.md)

---

## Related Skills

- `architecture-planner` - Design system architecture
- `security-audit` - Security considerations
