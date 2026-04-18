# Requirements Validator Skill

## Purpose
Automated validation that every requirement from raw input is fully traced through discovery, planning, and implementation phases. Prevents the common failure where 60% of requirements are lost during the planning→implementation transition.

## When to Use
- Before transitioning from Discovery → Planning
- Before transitioning from Planning → Implementation
- Before declaring implementation complete
- Anytime you suspect requirements may have been dropped

## Instructions

When invoked, perform the following validation steps:

### Step 1: Locate Documents

Find and read these files:
- `docs/discovery/requirements.md` — Functional requirements with FR-XXX IDs
- `docs/discovery/user-stories.md` — User stories with US-XXX IDs
- `docs/planning/architecture.md` — Architecture design
- `docs/planning/tasks.md` — Task breakdown with T-XXX IDs

If any file is missing, report it and stop.

### Step 2: Extract All IDs

1. Extract all `FR-XXX` IDs from requirements.md
2. Extract all `US-XXX` IDs from user-stories.md
3. Extract all `T-XXX` IDs from tasks.md
4. Extract all architecture section headers from architecture.md

### Step 3: Validate Requirement → User Story Coverage

For each FR-XXX:
- Search user-stories.md for the FR-XXX ID
- If not found, flag as **MISSING USER STORY**

For each US-XXX:
- Check that it references at least one FR-XXX
- If not, flag as **ORPHANED USER STORY**

### Step 4: Validate Requirement → Task Coverage

For each FR-XXX:
- Search tasks.md for the FR-XXX ID
- If not found, flag as **MISSING TASK**
- If found, check if the requirement is user-facing
  - If user-facing and no UI task exists, flag as **MISSING UI TASK**

### Step 5: Validate Task Granularity

For each T-XXX:
- Check the estimate field
- If estimate is "L" (Large) or > 1 day and no subtasks listed, flag as **TASK TOO LARGE**

### Step 6: Validate Priority Protection

For each FR-XXX:
- Check the Priority field
- If priority is "Should" or "Could", check if the requirement appears in the raw requirements document
- If it does, flag as **PRIORITY DOWNGRADED** — raw requirements should be "Must"

### Step 7: Validate Architecture Coverage

For each major section in architecture.md:
- Search tasks.md for references to that section
- If no task references it, flag as **ORPHANED ARCHITECTURE**

### Step 8: Generate Report

Output the validation report:

```
Requirements Traceability Validation Report
============================================
Date: [current date]
Phase: [Discovery/Planning/Implementation]

SUMMARY
-------
Total Requirements (FR): XX
Total User Stories (US): XX
Total Tasks (T): XX

COVERAGE
--------
Requirements → User Stories: XX/XX (XX%)
Requirements → Tasks: XX/XX (XX%)
User-Facing Requirements → UI Tasks: XX/XX (XX%)
Architecture Sections → Tasks: XX/XX (XX%)

ISSUES FOUND
-------------
🔴 CRITICAL (blocks phase transition):
- FR-XXX: [Title] — MISSING TASK
- FR-XXX: [Title] — MISSING UI TASK
- T-XXX: [Title] — TASK TOO LARGE (needs subtasks)

🟡 WARNING (should fix):
- FR-XXX: [Title] — PRIORITY DOWNGRADED from Must to Should
- US-XXX: [Title] — ORPHANED USER STORY (no FR reference)
- Architecture §X.X — ORPHANED (no tasks reference this section)

🟢 PASSED:
- All "Must" requirements have tasks
- All user-facing requirements have UI tasks
- All tasks are ≤ 1 day or have subtasks

VERDICT: ✅ PASS / ❌ FAIL (XX critical issues must be resolved)
```

### Verdict Rules

- **PASS**: Zero critical issues
- **FAIL**: Any of:
  - A "Must" requirement has no task
  - A user-facing requirement has no UI task
  - A task is > 1 day with no subtasks
  - Total task count < 3x requirement count

## Output

After validation, if the verdict is FAIL:
1. List all critical issues
2. For each issue, suggest the specific fix needed
3. Do NOT proceed to the next phase until all critical issues are resolved

If the verdict is PASS:
1. Confirm all checks passed
2. Display the coverage summary
3. Approve transition to the next phase
