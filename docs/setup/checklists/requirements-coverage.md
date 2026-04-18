# Requirements Coverage Checklist

Run this checklist at each phase transition to prevent requirement loss.

## Discovery → Planning Transition

### Requirements Quality
- [ ] Every requirement has a unique ID (FR-XXX)
- [ ] Every requirement has clear acceptance criteria (testable, not vague)
- [ ] Every requirement has a priority that matches the raw requirements
- [ ] No raw requirement was downgraded from "Must" to "Should/Could"
- [ ] Raw requirements document has been reviewed line-by-line against requirements.md

### User Story Coverage
- [ ] Every FR-XXX appears in at least one US-XXX
- [ ] Every US-XXX references its parent FR-XXX(s)
- [ ] Stories exist for ALL user roles (student, parent, teacher, admin)
- [ ] Stories cover happy path AND error cases

### Raw Requirements Audit
- [ ] Open the raw requirements document side-by-side with requirements.md
- [ ] Go through EVERY line of the raw requirements
- [ ] For each line, verify it appears as a requirement or is part of one
- [ ] Flag any raw requirement line not covered
- [ ] Resolve all flags before proceeding

## Planning → Implementation Transition

### Task Coverage
- [ ] Every FR-XXX has at least one task (T-XXX)
- [ ] Every US-XXX has implementation tasks
- [ ] No task is > 1 day without subtasks
- [ ] Architecture sections all map to tasks

### UI Coverage
- [ ] Every user-facing feature has a UI task
- [ ] UI tasks specify: component, states (loading/error/empty), mobile
- [ ] No feature relies on "UI polish" task at the end

### Pipeline Coverage
For each multi-step pipeline:
- [ ] Each step has its own task
- [ ] Orchestration task exists
- [ ] Error handling task exists
- [ ] Progress UI task exists
- [ ] Background job task exists

### Priority Audit
- [ ] No raw requirement is classified below "Must" without written justification
- [ ] All "Must" items have tasks with clear owners
- [ ] "Should" items from raw requirements are reclassified to "Must"

## Implementation → Completion

### Feature Completion
- [ ] Every requirement with status "Complete" has:
  - Working code
  - Functional UI (if user-facing)
  - At least one test
  - Acceptance criteria verified
- [ ] No "Must" requirement has status "Deferred" or "Partial"
- [ ] End-to-end workflows work for all user roles

### UI Completion
- [ ] Every planned LiveView/page renders correctly
- [ ] Every form submits and saves data
- [ ] Every list view shows real data
- [ ] Every detail view shows complete information
- [ ] Error states are handled (not blank pages or crashes)
- [ ] Loading states exist for async operations
- [ ] Mobile responsive (if required)
