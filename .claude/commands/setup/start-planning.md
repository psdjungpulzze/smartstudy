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

### 4. Determine Deployment Mode (MANDATORY — Ask Before Proceeding)

**You MUST ask the developer this question before continuing with any other planning step.** Do not skip or assume.

Present the following to the developer:

```markdown
## ⚠️ Deployment Mode Decision Required

Before we design the architecture, I need to understand how this application will be deployed.
This determines how authentication, billing, and user flows are implemented.

**Option A: Interactor Mode** (`*.interactor.com`)
- App will run on an Interactor subdomain (e.g., `app.interactor.com`)
- Users authenticate via Interactor auth (`auth.interactor.com`)
- Billing handled by Interactor billing UI
- Good for: internal tools, Interactor ecosystem apps

**Option B: Customer Mode** (white-label / customer's own domain)
- App will run on the customer's own domain (e.g., `app.customer.com`)
- Users NEVER leave the customer's domain — no redirects to `*.interactor.com`
- App must have its own login, registration, billing (payment, history, credit cards), and user management UI
- Interactor APIs can be used server-to-server on the backend, but the UI is fully self-contained
- Good for: SaaS products, white-label apps, customer-facing products

**Which mode is this application? (A or B)**
```

**Wait for the developer's answer.** Then:

1. Record the decision as an ADR in `docs/planning/decisions/001-deployment-mode.md`
2. Update `CLAUDE.md` Project Overview to include `- **Deployment Mode**: interactor | customer`
3. Adjust all subsequent planning steps based on the chosen mode:
   - **Customer Mode**: Add tasks for login UI, registration UI, password reset UI, billing UI (payment forms, history, credit card management), user profile/settings UI
   - **Interactor Mode**: Plan Interactor auth integration, SharedAuth or JWT token exchange

### 5. Interactor Capability Review (MANDATORY — Before Architecture)

**Before designing the architecture**, review requirements tagged with `[INTERACTOR:*]` from Discovery and validate that Interactor services will be used wherever applicable.

#### Step 1: Review Tagged Requirements

Read `docs/discovery/requirements.md` and identify all requirements with Interactor overlap tags. For each:

| Requirement | Interactor Service | Decision | ADR Needed? |
|---|---|---|---|
| FR-XXX: [title] | Account Server / Credentials / Agents / Workflows / Webhooks | Use Interactor / Custom (with reason) | Yes if Custom |

#### Step 2: Read Interactor Documentation for Each Service

For each Interactor service that will be used, read the full integration guide:
- Account Server → `docs/i/account-server-docs/integration-guide.md`
- Credentials → `docs/i/interactor-docs/integration-guide/03-credential-management.md`
- AI Agents → `docs/i/interactor-docs/integration-guide/04-ai-agents.md`
- Workflows → `docs/i/interactor-docs/integration-guide/05-workflows.md`
- Webhooks → `docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md`

#### Step 3: Create ADRs for Any Custom Implementations

If any requirement that overlaps with an Interactor capability will NOT use Interactor, create an ADR documenting:
- What Interactor service was available
- Why it cannot be used (compliance, offline, separate user base, etc.)
- What custom approach will be used instead

#### Step 4: Record in Architecture Document

In `docs/planning/architecture.md`, add an **"Interactor Platform Integration"** section listing:
- Which Interactor services will be used and for what
- API integration approach (server-to-server vs. client-side)
- Any custom implementations with ADR references

**DO NOT proceed to architecture design until this review is complete.**

### 6. Display Planning Checklist

```markdown
## Planning Phase Checklist

### Interactor Capability Review
- [ ] All `[INTERACTOR:*]` tagged requirements reviewed
- [ ] Interactor docs read for each service to be used
- [ ] ADRs created for any custom implementations that override Interactor
- [ ] Architecture document has "Interactor Platform Integration" section

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

### Deployment Mode
- [ ] Deployment mode decided (Interactor or Customer) — **ADR recorded**
- [ ] Auth strategy matches deployment mode
- [ ] Billing strategy matches deployment mode
- [ ] No `*.interactor.com` redirects if Customer Mode

### Authentication Architecture
- [ ] **If Interactor Mode**: Use Interactor server for authentication (SharedAuth or JWT)
- [ ] **If Customer Mode**: Design self-contained login/registration/password-reset UI
- [ ] Authentication flow designed
- [ ] Session management approach defined

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

### 6. Initialize Phoenix Project

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

### 7. Invoke Architecture Planner

Suggest using the `architecture-planner` skill:

```
I can help design the architecture. Would you like me to:
1. Create a system architecture based on requirements
2. Design the data model
3. Define API contracts
4. Evaluate technology options

Use the architecture-planner skill for detailed guidance.
```

### 8. Authentication & Billing Planning (Based on Deployment Mode)

**The approach here depends entirely on the Deployment Mode chosen in Step 4.**

#### If Interactor Mode (`*.interactor.com`):

Use Interactor server for authentication:
- Single sign-on across all Interactor ecosystem apps
- JWT tokens with RS256 signing via JWKS endpoint
- No need to implement password hashing, session management, etc.
- Built-in user management and billing

**Planning Considerations:**
1. **Same Domain/Subdomain**: Use SharedAuth (cookie-based, automatic)
2. **Different Domain**: Use JWT token exchange via API
3. **API-only Apps**: Use Bearer token authentication

Create an ADR documenting the choice to use Interactor authentication.

See: `docs/i/guides/interactor-authentication.md` for implementation details.

#### If Customer Mode (customer's own domain):

**The app MUST provide its own complete user-facing flows. Users must NEVER be redirected to `*.interactor.com`.**

Plan and create tasks for:
- **Login page** — email/password form, error handling, "forgot password" link
- **Registration page** — sign-up form with validation
- **Password reset** — request flow + reset flow
- **User profile / settings** — name, email, password change
- **Billing UI** — payment method management (credit card add/remove/update), billing history, invoices, plan selection
- **Session management** — cookie-based sessions, remember me, logout

Interactor APIs may be used **server-to-server** on the backend (e.g., for token verification, user provisioning), but all UI must be self-contained within the app.

Create an ADR documenting the choice to use self-contained auth/billing with the rationale that users must not leave the customer's domain.

### 9. Suggested Prompts

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

- [ ] **Interactor capability review complete** — all `[INTERACTOR:*]` requirements addressed
- [ ] **No Interactor feature being reimplemented without an ADR** justifying the custom approach
- [ ] **Architecture doc has "Interactor Platform Integration" section** listing services to use
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
