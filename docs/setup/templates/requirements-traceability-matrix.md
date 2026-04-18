# Requirements Traceability Matrix

## Purpose
Ensures every requirement flows from raw input → discovery → planning → implementation → testing with nothing lost.

## Instructions
1. Create this matrix during Discovery phase (fill Req ID, Title, Priority, User Stories)
2. Update during Planning phase (fill Architecture, Tasks, UI Tasks)
3. Update during Implementation phase (fill Status, Test Cases)
4. **Every cell must be filled before the phase transition**

## Matrix

| Req ID | Title | Priority | User Stories | Arch § | Tasks | UI Tasks | Tests | Status |
|--------|-------|----------|-------------|--------|-------|----------|-------|--------|
| FR-001 | | Must | US-XXX | §X.X | T-XXX | T-XXX | TC-XXX | Pending |
| FR-002 | | Must | US-XXX | §X.X | T-XXX | T-XXX | TC-XXX | Pending |

## Validation Rules

### During Discovery Exit
- [ ] Req ID, Title, Priority, User Stories columns are complete
- [ ] Every "Must" requirement has at least one user story
- [ ] No empty User Stories cells

### During Planning Exit
- [ ] Arch §, Tasks, UI Tasks columns are complete
- [ ] Every "Must" requirement has at least one task AND one UI task (if user-facing)
- [ ] No task is estimated > 1 day without subtasks
- [ ] Total tasks ≥ 3x total requirements

### During Implementation Exit
- [ ] Status column is complete (Complete/Deferred/Partial)
- [ ] No "Must" requirement has status "Deferred"
- [ ] Tests column has at least one test per requirement
- [ ] All "Complete" requirements have passing tests

## Gap Detection

If any cell is empty, the requirement may be lost. Common failure modes:

| Empty Column | What Failed | Fix |
|---|---|---|
| User Stories | Discovery didn't decompose the requirement | Write missing user stories |
| Tasks | Planning didn't plan implementation | Add tasks to task breakdown |
| UI Tasks | Planning assumed backend-only | Add UI tasks |
| Tests | Implementation skipped testing | Write tests before marking complete |
| Status | Implementation never started | Prioritize and implement |

## Coverage Summary

```
Total Requirements: ___
Fully Traced (all columns filled): ___
Coverage: ___%

Gaps:
- FR-XXX: Missing [column]
- FR-XXX: Missing [column]
```
