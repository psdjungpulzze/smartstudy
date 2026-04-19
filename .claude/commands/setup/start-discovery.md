# Start Discovery Phase

Initialize the Discovery phase for gathering requirements and understanding the problem space.

## Instructions

When this command is invoked, perform the following:

### 1. Check for Existing Input

First, check if the user has:
- **A rough project idea** - They may share unstructured notes, ideas, or descriptions
- **A filled intake form** - Check for `docs/project-idea-intake.md`
- **Nothing yet** - Guide them to start fresh

If the user provides a rough write-up or idea:
1. Parse and extract key elements (problem, users, features, constraints)
2. Ask clarifying questions about gaps or ambiguities
3. Use extracted information to pre-populate discovery documents
4. Summarize what you understood and confirm with the user

### 2. Set Context

Update the project phase in CLAUDE.md to "discovery" if not already set.

### 3. Create Discovery Workspace

Check if the following exist, create if missing:
- `docs/discovery/` directory
- `docs/discovery/requirements.md` (from template)
- `docs/discovery/stakeholders.md` (from template)
- `docs/discovery/user-stories.md`
- `docs/discovery/research-notes.md`

### 4. Display Discovery Checklist

Present the discovery phase checklist:

```markdown
## Discovery Phase Checklist

### Problem Definition
- [ ] Problem statement clearly articulated
- [ ] Impact and scope defined
- [ ] Success metrics identified
- [ ] Assumptions documented

### Stakeholder Analysis
- [ ] All stakeholders identified
- [ ] Roles and responsibilities defined
- [ ] Communication plan established
- [ ] Sign-off process defined

### Requirements Gathering
- [ ] Functional requirements documented
- [ ] Non-functional requirements defined
- [ ] Constraints identified
- [ ] Dependencies mapped

### User Research
- [ ] User personas created
- [ ] User journeys mapped
- [ ] Pain points identified
- [ ] Jobs-to-be-done documented

### Competitive Analysis
- [ ] Competitors identified
- [ ] Feature comparison completed
- [ ] Differentiation strategy defined

### Technical Feasibility
- [ ] Technical constraints assessed
- [ ] Integration requirements identified
- [ ] Technology options evaluated
```

### 5. Provide Guidance

Offer to help with:
1. Writing the problem statement
2. Creating stakeholder analysis
3. Documenting requirements as user stories
4. Conducting competitive analysis
5. Assessing technical feasibility

### 6. Suggested Prompts

Provide helpful prompts for the discovery phase:

```
"Here's my rough idea for what I want to build: [paste your notes]"
"Help me define the problem statement for [project/feature]"
"Create a stakeholder analysis for this project"
"Convert these requirements into user stories: [requirements]"
"What questions should I ask stakeholders about [topic]?"
"Analyze competitors in the [domain] space"
"What technical considerations should we evaluate for [feature]?"
```

## Handling Rough Ideas

When a user shares an unstructured project idea:

### Extract These Elements
- **Problem/Opportunity**: What pain point or opportunity is mentioned?
- **Users**: Who are the intended users? (explicit or implied)
- **Core Features**: What capabilities are described?
- **Constraints**: Timeline, budget, technical, regulatory?
- **Success Criteria**: How will they know it worked?
- **Integrations**: External systems mentioned?
- **Inspirations**: Similar products or references?

### Ask Clarifying Questions About
- Missing user types or edge cases
- Unclear feature priorities
- Ambiguous technical requirements
- Undefined success metrics
- Potential scope creep areas

### Generate Structured Outputs
After understanding the idea, produce:
1. **Summary**: 2-3 sentence distillation of the idea
2. **User Stories**: Convert features to "As a [user], I want [feature] so that [benefit]"
3. **Open Questions**: List things that need clarification
4. **Suggested Next Steps**: What to explore or decide next

## Output

After initialization, display:

```markdown
## Discovery Phase Initialized

**Status**: Ready to begin discovery

### Workspace Created
- docs/discovery/requirements.md
- docs/discovery/stakeholders.md
- docs/discovery/user-stories.md
- docs/discovery/research-notes.md

### Next Steps
1. Define the problem statement
2. Identify stakeholders
3. Gather requirements
4. Conduct user research

### Templates Available
- **Project idea intake**: `docs/project-idea-intake.md` (start here with rough ideas)
- Requirements template: `docs/i/phases/01-discovery/requirements-template.md`
- Stakeholder template: `docs/i/phases/01-discovery/stakeholder-analysis.md`
- User story template: `docs/i/phases/01-discovery/user-story-template.md`

### Ready to Help With
- Problem definition
- Stakeholder analysis
- Requirements documentation
- User research planning
- Competitive analysis

What would you like to start with?
```

## Validation Before Proceeding

Before transitioning to the Planning phase, validate discovery outputs:

### Discovery Validation Checklist
- [ ] Problem statement is clear and specific
- [ ] All user types/personas identified
- [ ] Requirements have acceptance criteria
- [ ] No ambiguous language ("should", "might" → "must", "will")
- [ ] Success metrics are measurable
- [ ] Scope boundaries defined (what's NOT included)
- [ ] Stakeholders identified and roles clear

### Exit Gate
Run the `validator` skill on all discovery artifacts before proceeding to planning:
```
"Validate the discovery documents before we move to planning"
```

Only proceed to `/start-planning` when validation passes.

---

## Exit Gate: Discovery → Planning

Before transitioning to Planning, validate ALL of the following:

### Interactor Capability Overlap Check (MANDATORY)

Review every requirement against the Interactor Capability Map in `.claude/rules/i/interactor-integration.md`. For each requirement, determine:

- [ ] **Auth/User Management**: Does any requirement involve login, signup, user roles, MFA, or session management? → Tag with `[INTERACTOR:AUTH]`
- [ ] **Credential Storage**: Does any requirement involve storing OAuth tokens, API keys, or third-party credentials? → Tag with `[INTERACTOR:CREDENTIALS]`
- [ ] **AI/Chat**: Does any requirement involve chatbots, AI assistants, LLM integration, or conversational interfaces? → Tag with `[INTERACTOR:AGENTS]`
- [ ] **Workflows**: Does any requirement involve multi-step processes, approval flows, or pipeline orchestration? → Tag with `[INTERACTOR:WORKFLOWS]`
- [ ] **Events/Streaming**: Does any requirement involve real-time events, webhooks, or server-sent events? → Tag with `[INTERACTOR:WEBHOOKS]`
- [ ] **Org/Tenant Management**: Does any requirement involve organizations, multi-tenancy, or role hierarchies? → Tag with `[INTERACTOR:AUTH]`

**Add an "Interactor Overlap" column to the requirements document.** For each tagged requirement, note: "Use Interactor [SERVICE]" or "Custom needed — [reason]". Requirements marked "Custom needed" MUST have the reason documented and will require an ADR in the Planning phase.

### Requirements Completeness
- [ ] Every requirement has a unique ID (FR-XXX)
- [ ] Every requirement has acceptance criteria
- [ ] Every requirement has a priority (Must/Should/Could)
- [ ] Raw requirements document has been fully decomposed — no requirement left unaddressed

### User Story Coverage
- [ ] Every requirement (FR-XXX) maps to at least one user story (US-XXX)
- [ ] Every user story references its parent requirement(s)
- [ ] User stories cover ALL user roles mentioned in requirements
- [ ] No orphaned user stories

### Traceability Matrix
- [ ] Requirements Coverage Matrix exists with Req ID, Title, Priority, and User Stories columns filled
- [ ] No empty cells in the User Stories column

### Cross-Check Procedure
1. List all FR-XXX IDs from requirements.md
2. For each FR-XXX, grep user-stories.md for the ID
3. If any FR-XXX has zero matches, a user story is missing
4. List all US-XXX IDs from user-stories.md
5. For each US-XXX, verify it references at least one FR-XXX
6. Report any gaps

**DO NOT proceed to Planning if any check fails.**
