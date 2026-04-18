# Start Planning Phase

Initialize the Planning phase for architecture design and task breakdown.

## Instructions

When this command is invoked, perform the following:

### 1. Verify Discovery Completion

Check if discovery artifacts exist:
- `docs/discovery/requirements.md`
- `docs/discovery/stakeholders.md`

If missing, warn that discovery phase may be incomplete.

### 2. Set Context

Update the project phase in CLAUDE.md to "planning".

### 3. Create Planning Workspace

Check if the following exist, create if missing:
- `docs/planning/` directory
- `docs/planning/architecture.md` (from template)
- `docs/planning/tasks.md`
- `docs/planning/risks.md`
- `docs/planning/decisions/` directory for ADRs

### 4. Display Planning Checklist

```markdown
## Planning Phase Checklist

### Architecture Design
- [ ] System architecture defined
- [ ] Component diagram created
- [ ] Data model designed
- [ ] API contracts specified
- [ ] Integration points identified

### Technology Selection
- [ ] Technology stack decided
- [ ] Framework choices documented
- [ ] Infrastructure requirements defined
- [ ] Third-party services selected

### Authentication Architecture
- [ ] Use Interactor server for authentication (recommended)
- [ ] Authentication flow designed (JWT tokens via Interactor)
- [ ] Session management approach defined
- [ ] Cross-domain auth requirements identified

### Task Breakdown
- [ ] Features broken into tasks
- [ ] Dependencies identified
- [ ] Priority assigned
- [ ] Effort estimated (optional)

### Risk Assessment
- [ ] Technical risks identified
- [ ] Mitigation strategies defined
- [ ] Contingency plans created

### Documentation
- [ ] Architecture Decision Records (ADRs) created
- [ ] Design document drafted
- [ ] API documentation started
```

### 5. Initialize Phoenix Project

**IMPORTANT**: Check if a Phoenix project exists before proceeding with detailed planning.

#### Check for Existing Project

```bash
# Check if mix.exs exists
ls mix.exs 2>/dev/null
```

#### If No Project Exists

If `mix.exs` is missing, the Phoenix project needs to be created:

1. **Derive app name from project**:
   - Convert project name to snake_case (e.g., "my-project" → "my_project")
   - Use this for the Phoenix app name

2. **Create the Phoenix project**:
   ```bash
   # Standard Phoenix project with LiveView and PostgreSQL
   mix phx.new <app_name> --database postgres --live

   # Or if in existing directory:
   mix phx.new . --app <app_name> --database postgres --live
   ```

3. **After creation, configure dynamic port** (auto-finds available port):

   Update `config/dev.exs` to use PORT env var with 4005 default:
   ```elixir
   config :<app_name>, <AppName>Web.Endpoint,
     http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4005")],
     # ... rest of config
   ```

   This allows `scripts/start.sh` to automatically find an available port if 4005 is in use.

4. **Add recommended dependencies to `mix.exs`**:
   ```elixir
   defp deps do
     [
       # ... existing deps ...
       {:oban, "~> 2.17"},           # Background jobs
       {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
       {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
       {:excoveralls, "~> 0.18", only: :test}
     ]
   end
   ```

5. **Initialize the project**:
   ```bash
   mix deps.get
   mix ecto.create
   mix ecto.migrate
   ```

#### Display After Project Creation

```markdown
## Phoenix Project Initialized

✅ Phoenix project created: <app_name>
✅ Database configured: PostgreSQL
✅ LiveView enabled
✅ Development port: Dynamic (default 4005, auto-finds next if in use)

### Project Structure
lib/
├── <app_name>/           # Business logic (contexts)
└── <app_name>_web/       # Web layer (controllers, LiveView)

### Quick Verification
```bash
./scripts/start.sh    # Auto-finds available port (4005+)
# Or manually:
mix phx.server        # Uses PORT env var or default 4005
mix test              # Should pass
```

Now proceeding with architecture design...
```

### 6. Invoke Architecture Planner

Suggest using the `architecture-planner` skill:

```
I can help design the architecture. Would you like me to:
1. Create a system architecture based on requirements
2. Design the data model
3. Define API contracts
4. Evaluate technology options

Use the architecture-planner skill for detailed guidance.
```

### 6. Interactor Authentication Planning

**IMPORTANT**: All new applications should use Interactor server for authentication.

#### Why Interactor Authentication?
- Single sign-on across all Interactor ecosystem apps
- JWT tokens with RS256 signing for secure verification
- No need to implement password hashing, session management, etc.
- JWKS endpoint for external token verification
- Built-in user management

#### Authentication Architecture Decision
Create an ADR documenting the choice to use Interactor authentication:
- **Context**: Need user authentication for the application
- **Decision**: Use Interactor server as the identity provider
- **Consequences**: Users must have Interactor accounts; app depends on Interactor availability

#### Planning Considerations
1. **Same Domain/Subdomain**: Use SharedAuth (cookie-based, automatic)
2. **Different Domain**: Use JWT token exchange via API
3. **API-only Apps**: Use Bearer token authentication

See: `docs/i/guides/interactor-authentication.md` for implementation details.

### 7. Suggested Prompts

```
"Design the architecture for [feature/system]"
"Break down [feature] into implementation tasks"
"What risks should we consider for [approach]?"
"Create an ADR for choosing [technology/approach]"
"Define the API contract for [endpoint]"
"Evaluate [option A] vs [option B] for [requirement]"
"Plan Interactor authentication integration"
```

## Output

```markdown
## Planning Phase Initialized

**Status**: Ready for architecture and planning

### Discovery Summary
[Show summary from discovery phase if available]

### Workspace Created
- docs/planning/architecture.md
- docs/planning/tasks.md
- docs/planning/risks.md
- docs/planning/decisions/

### Next Steps
1. Define system architecture
2. Create component design
3. Break down into tasks
4. Assess risks
5. Document decisions (ADRs)

### Templates Available
- Architecture: `docs/i/phases/02-planning/architecture-template.md`
- Task breakdown: `docs/i/phases/02-planning/task-breakdown.md`
- Risk assessment: `docs/i/phases/02-planning/risk-assessment.md`
- ADR template: `docs/i/templates/adr-template.md`

### Skills Available
- `/architecture-planner` - Design system architecture

What aspect of planning would you like to start with?
```

## Validation Requirements

### Entry Validation
Before starting planning, verify discovery outputs are valid:
```
"Validate discovery documents"
```

If discovery validation fails, address issues before proceeding.

### During Planning Validation
After generating each artifact, validate it:

| Artifact | Validation Command |
|----------|-------------------|
| Architecture design | `mix compile` (if code generated), check Phoenix patterns |
| Database schema | Verify relationships, indexes, types |
| API contracts | Check REST conventions, response formats |
| Task breakdown | Ensure tasks are atomic and testable |

### Exit Gate Validation
Before proceeding to `/start-implementation`:

- [ ] Architecture document reviewed for Phoenix patterns
- [ ] Database schema has proper indexes and constraints
- [ ] API design follows REST conventions
- [ ] All ADRs documented with rationale
- [ ] Tasks are broken down to < 1 day each
- [ ] Risks identified with mitigation strategies

Run the `validator` skill:
```
"Validate the planning documents before implementation"
```

---

## MANDATORY: Requirements Coverage Validation

After generating the task breakdown, run this validation:

### Step 1: Build Coverage Matrix
For each requirement in requirements.md:

| FR-XXX | User Stories | Architecture Section | Tasks | UI Task? | Priority |
|--------|-------------|---------------------|-------|----------|----------|

### Step 2: Validate Coverage
- [ ] Every "Must" requirement has at least one task
- [ ] Every "Should" requirement has at least one task (if from raw requirements)
- [ ] Every user-facing requirement has a UI task
- [ ] No task is larger than 1 day without subtasks
- [ ] Total task count is proportional to requirement count (minimum 3:1 ratio tasks:requirements)

### Step 3: Validate Task Granularity
For each task estimated as "L" (Large) or with no subtasks:
- [ ] Can this be completed in one day?
- [ ] If not, break it into subtasks (T-XXXa, T-XXXb, etc.)

### Step 4: Validate Pipeline Features
For any multi-step pipeline (OCR, AI generation, data import/export):
- [ ] Each step has its own task
- [ ] There is an orchestration task
- [ ] There is an error handling task
- [ ] There is a progress/status UI task
- [ ] There is a background job configuration task

### Step 5: Validate UI Coverage
For every LiveView/page/component planned:
- [ ] There is a dedicated task for building it
- [ ] The task includes acceptance criteria from the user story
- [ ] Loading, error, and empty states are specified

### Step 6: Check for Orphaned Architecture
For each section in architecture.md:
- [ ] There is at least one task referencing this section
- [ ] If an architecture section has no tasks, either add tasks or remove the section

**If ANY requirement has zero tasks, DO NOT proceed to Implementation.**

### Coverage Report Format
Generate this report before proceeding:

```
Requirements Coverage Report
=============================
Total Requirements: XX
  Must:   XX (XX with tasks, XX without)
  Should: XX (XX with tasks, XX without)
  Could:  XX (XX with tasks, XX without)

Total User Stories: XX (XX with tasks, XX without)
Total Tasks: XX
  Backend: XX
  Frontend/UI: XX
  Integration: XX
  Testing: XX

Coverage: XX% (requirements with tasks / total requirements)

GAPS (requirements without tasks):
- FR-XXX: [Title] — MISSING TASKS
- FR-XXX: [Title] — MISSING TASKS

UI GAPS (user-facing requirements without UI tasks):
- FR-XXX: [Title] — MISSING UI TASK
```
