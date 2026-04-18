# CLAUDE.md - AI-Driven Product Development Guide

This file provides comprehensive guidance to Claude Code for AI-driven product development across all phases of the software development lifecycle.

## Project Overview

- **Project Name**: FunSheep
- **Project Type**: web | mobile
- **Technology Stack**: Elixir, Phoenix Framework, PostgreSQL, LiveView
- **Current Phase**: implementation

## Technology Stack

### Core Technologies
- **Language**: Elixir 1.15+
- **Framework**: Phoenix 1.7+
- **Frontend**: Phoenix LiveView, TailwindCSS
- **Database**: PostgreSQL with Ecto
- **Real-time**: Phoenix Channels, PubSub
- **Background Jobs**: Oban
- **Authentication**: phx.gen.auth or custom

### Key Elixir Concepts
- **OTP**: Supervision trees, GenServers, processes
- **Contexts**: Business logic organization (Phoenix contexts)
- **Changesets**: Data validation and casting
- **Pipelines**: Use `|>` for data transformation
- **Pattern Matching**: Leverage for control flow and destructuring

---

# ⛔ STOP - MANDATORY LAYOUT STRUCTURE

> **Before writing ANY UI code, you MUST implement this layout structure.**

## Default Application Layout (MANDATORY)

**ALL applications built with this template MUST use this 3-panel layout:**

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ APPBAR (Global Navigation Bar) - Fixed Top, h-16, z-50                           │
│ [≡][⊞][Logo]         [✨ What can I do for you?...]          [🔔¹²][?][👤][+]   │
├─────────────────┬────────────────────────────────────────────┬───────────────────┤
│ LEFT DRAWER     │                                            │ RIGHT PANE        │
│ (Sidebar)       │           MAIN CONTENT                     │ (AI Copilot)      │
│ w-64, fixed     │           (scrollable)                     │ w-80, optional    │
│                 │                                            │                   │
│ [+ Create] 🟢   │                                            │ Slides in when    │
│                 │                                            │ user submits AI   │
│ NAVIGATION      │                                            │ query or clicks   │
│ - Dashboard     │                                            │ Quick Create (+)  │
│ - Items...      │                                            │                   │
│                 │                                            │                   │
│ ⚠️ Warnings go  │                                            │                   │
│ BELOW items!    │                                            │                   │
│                 │                                            │                   │
│ ─────────────── │                                            │                   │
│ Feedback        │                                            │                   │
│ 😞 😟 😐 🙂 😊  │                                            │                   │
└─────────────────┴────────────────────────────────────────────┴───────────────────┘
```

### Layout Template Location

**Copy and customize this template:**
```
.claude/templates/ui/phoenix/app_layout.html.heex  →  lib/my_app_web/components/layouts/app.html.heex
```

### 3 MANDATORY Layout Components

| # | Component | Description | Template |
|---|-----------|-------------|----------|
| 1 | **AppBar (GNB)** | Fixed top nav with Logo, AI Input, Notifications, Profile, Quick Create | Included in app_layout.html.heex |
| 2 | **Left Drawer** | Fixed sidebar with Create button, Navigation, Feedback at bottom | Included in app_layout.html.heex |
| 3 | **Main Content** | Scrollable content area that adjusts margins for drawer/pane | Included in app_layout.html.heex |

### Optional: Right Pane (AI Copilot)

The Right Pane slides in from the right when:
- User submits a query in the AI Assistant input
- User clicks the Quick Create (+) button
- Any feature needs a slide-in panel

---

## ⚠️ UI DESIGN SYSTEM - MANDATORY

> **STOP! Before writing ANY UI code, you MUST read this section.**

**All applications built with this template MUST follow the Interactor design system.** This uses a three-tier enforcement system:

### Three-Tier Design Enforcement

| Tier | Location | Purpose | Applied |
|------|----------|---------|---------|
| **1. Universal Standards** | `.claude/rules/i/ui-design.md` | Colors, spacing, border radius, typography | Auto-applied to all UI files |
| **2. Framework Patterns** | `docs/i/ui-design/material-ui/enforcement.md` | Material UI layout, 9 mandatory patterns | Referenced when using Material UI |
| **3. Validation Tool** | `.claude/skills/i/ui-design/` | Validate compliance, generate components | Use before completing UI work |

### Required Reading (In This Order)

| Priority | Document | Purpose |
|----------|----------|---------|
| **1. CRITICAL** | `.claude/rules/i/ui-design.md` | Universal design standards (auto-enforced) |
| **2. CRITICAL** | `docs/i/ui-design/material-ui/enforcement.md` | Material UI patterns (if using 3-panel layout) |
| **3. CRITICAL** | `docs/i/ui-design/material-ui/index.md` | Complete design specification |
| **4. CRITICAL** | `docs/i/ui-design/gnb-components.md` | Navigation patterns |
| 5. High | `docs/i/ui-design/material-ui/checklist.md` | Validation checklist |

### Universal Design Standards (Always Apply)

**Automatically enforced by `.claude/rules/i/ui-design.md`:**
- **Primary Color**: `#4CD964` green for all primary actions/buttons
- **Border Radius**: Buttons and inputs must be pill-shaped (`rounded-full`)
- **Cards**: Must use `rounded-2xl` (16px radius)
- **Spacing**: Follow 8px, 12px, 16px, 24px scale
- **Icons**: Outlined style with `stroke-width="1.5"`
- **Dark Mode**: All components must support dark mode
- **Accessibility**: WCAG AA minimum (4.5:1 contrast ratio)

### 6 Mandatory Material UI Patterns (For 3-Panel Layout Apps)

| # | Pattern | ✅ Correct | ❌ Wrong |
|---|---------|-----------|----------|
| 1 | **Lottie Animated Logo** | `InteractorLogo_Light.json` | Static PNG/SVG |
| 2 | **GREEN Create Button** | `#4CD964` with `#3DBF55` hover | Blue/orange/other colors |
| 3 | **Quick Create (+)** | Green FAB in AppBar → right panel | Missing or wrong action |
| 4 | **Dual Notification Badge** | Primary count + red error count | Single badge only |
| 5 | **Warnings BELOW Items** | Warning below problematic item | Warning at top of page |
| 6 | **Feedback Section** | 5 emoji at drawer bottom | Missing or wrong position |

**📚 See `docs/i/ui-design/material-ui/enforcement.md` for complete Material UI pattern requirements.**

### Validation Before Completing UI Work

Before completing any UI changes, use the `ui-design` skill to validate:

```
Use ui-design skill to validate this component against:
1. Universal design standards
2. Material UI patterns (if applicable)
3. Accessibility requirements
```

The skill will check:
- ✅ Color compliance
- ✅ Border radius standards
- ✅ Spacing consistency
- ✅ Icon style
- ✅ Dark mode support
- ✅ Accessibility standards
- ✅ Framework-specific patterns

### Design Tokens (Use These Exactly)

```
COLORS:
  Primary Green:    #4CD964  (hover: #3DBF55)
  Error Red:        #FF3B30
  Warning Yellow:   #FFCC00
  Background:       #F5F5F5 (light) / #1E1E1E (dark)
  Surface:          #FFFFFF (light) / #2D2D2D (dark)

BORDER RADIUS:
  Buttons:          9999px  (rounded-full - pill shaped)
  Cards/Modals:     16px    (rounded-2xl)
  Inputs:           8px     (rounded-lg)

SIZING:
  AppBar:           64px    (h-16)
  Sidebar:          240px   (w-64) / 56px collapsed
  Right Panel:      320px   (w-80)
```

### TailwindCSS Quick Reference

```html
<!-- Primary Button (Create Actions) -->
<button class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md">
  Create
</button>

<!-- AppBar -->
<header class="bg-white shadow-sm h-16 fixed top-0 left-0 right-0 z-50">

<!-- Left Drawer -->
<aside class="w-64 bg-white h-screen fixed left-0 top-16 shadow-lg">

<!-- Card -->
<div class="bg-white rounded-2xl shadow-md p-6">
```

### Brand Assets

Copy from `.claude/assets/i/brand/` to `priv/static/brand/`:
- `lottie/InteractorLogo_Light.json`
- `lottie/InteractorLogo_Dark.json`
- `icons/icon_simple_green_v1.png`

### Additional UI Guidelines

| Guideline | Location |
|-----------|----------|
| Logo & Branding | `docs/i/ui-design/logo-branding.md` |
| Forms | `docs/i/ui-design/forms.md` |
| Buttons | `docs/i/ui-design/buttons.md` |
| Colors | `docs/i/ui-design/colors.md` |
| Modals & Dropdowns | `docs/i/ui-design/modals-dropdowns.md` |
| Panels & Toolbar | `docs/i/ui-design/panels-toolbar.md` |

---

## Quick Reference

### Slash Commands

| Command | Description |
|---------|-------------|
| `/start-discovery` | **[SETUP]** Begin requirements gathering phase |
| `/start-planning` | **[SETUP]** Start architecture and planning phase |
| `/start-implementation` | **[SETUP]** Begin development phase |
| `/run-review` | Execute code review workflow |
| `/prepare-release` | Prepare for deployment |
| `/handle-change` | Process requirement/design changes mid-project |

**Note:** Commands marked **[SETUP]** are part of the initial project creation methodology. They are located in `.claude/commands/setup/` and `docs/setup/`.

### Skills

| Skill | Usage |
|-------|-------|
| `code-review` | Comprehensive code quality analysis |
| `security-audit` | OWASP-based security scanning |
| `doc-generator` | Auto-generate documentation |
| `test-generator` | Generate test scaffolds |
| `architecture-planner` | **[SETUP]** Design system architecture |
| `deployment` | Deployment preparation and verification |
| `validator` | **Validate any artifact for correctness** (use after every generation) |
| `requirements-validator` | **Validate requirements traceability and coverage** |

**Note:** Skills marked **[SETUP]** are located in `.claude/skills/setup/`.

### External Documentation

Some documentation is automatically synchronized from external Interactor repositories:

| Document | Description | Manual Sync |
|----------|-------------|-------------|
| `docs/i/guides/interactor-authentication.md` | Interactor auth integration guide (auto-synced daily) | `./scripts/setup/sync-external-docs.sh interactor-auth` |

**Auto-Sync Details:**
- Daily sync at 6am UTC via GitHub Actions
- Manual trigger available in Actions → "Sync External Documentation"
- See `docs/i/guides/README.md` for complete sync system documentation

---

## Development Workflow

### Requirements Traceability (MANDATORY)

Every project MUST maintain a Requirements Traceability Matrix. This matrix is:
- Created during Discovery (requirements → user stories)
- Updated during Planning (user stories → tasks)
- Updated during Implementation (tasks → status)
- Validated at each phase transition

**Template**: `docs/setup/templates/requirements-traceability-matrix.md`
**Checklist**: `docs/setup/checklists/requirements-coverage.md`

### Phase Transition Gates

**Discovery → Planning**: Cannot proceed unless:
- Every raw requirement is in requirements.md
- Every requirement has user stories
- Traceability matrix has Req ID, Title, Priority, User Stories filled

**Planning → Implementation**: Cannot proceed unless:
- Every requirement has tasks
- Every user-facing requirement has UI tasks
- No task > 1 day without subtasks
- Coverage report shows 100% for "Must" requirements

**Implementation → Complete**: Cannot proceed unless:
- Every "Must" requirement has status "Complete"
- All acceptance criteria verified
- UI is functional for all features

---

### Phase 1: Discovery **[SETUP PHASE]**

**Objective**: Understand the problem space and gather requirements.

When working on discovery tasks:
1. Use `/start-discovery` to initialize the phase
2. Reference `docs/setup/phases/01-discovery/` for templates
3. Create stakeholder analysis using provided template
4. Document requirements in user story format
5. Validate requirements against business goals

**Key deliverables**:
- Problem statement document
- Stakeholder analysis
- Requirements document with user stories
- Research summary

**Exit criteria**: Requirements prioritized and approved by stakeholders.

**Note:** This phase is part of initial project setup. Files are in `docs/setup/phases/01-discovery/`.

---

### Phase 2: Planning **[SETUP PHASE]**

**Objective**: Design architecture and create implementation plan.

When working on planning tasks:
1. Use `/start-planning` to initialize the phase
2. Create architecture using `docs/setup/templates/design-doc-template.md`
3. Break down work using `docs/setup/phases/02-planning/task-breakdown.md`
4. Document decisions using ADR template at `docs/setup/templates/adr-template.md`
5. Identify and assess risks

**Key deliverables**:
- Architecture design document
- Task breakdown with estimates
- Architecture Decision Records (ADRs)
- Risk assessment

**Exit criteria**: Architecture approved, tasks estimated, risks mitigated.

**Note:** This phase is part of initial project setup. Files are in `docs/setup/phases/02-planning/` and `docs/setup/templates/`.

---

### Phase 3: Implementation

**Objective**: Write code following established standards.

When writing code:
1. Use `/start-implementation` to setup the phase **[SETUP command]**
2. Follow `.claude/rules/i/code-style.md` for formatting
3. Apply TDD - write tests first when possible
4. Use meaningful commit messages per `.claude/rules/i/git-workflow.md`
5. Reference `docs/setup/phases/03-implementation/ai-collaboration-guide.md` for initial setup collaboration **[SETUP]**
6. Reference `docs/i/phases/03-implementation/` for ongoing development standards

**Best practices**:
- Commit frequently with atomic changes
- Write self-documenting code
- Handle errors appropriately
- Never hardcode secrets or credentials

**Exit criteria**: Feature complete, tests passing, code reviewed.

---

### Phase 4: Testing

**Objective**: Ensure quality through comprehensive testing.

When testing:
1. Follow `.claude/rules/testing.md` for requirements
2. Achieve minimum coverage thresholds
3. Include unit, integration, and e2e tests
4. Use `test-generator` skill for scaffolding
5. Document test scenarios

**Coverage requirements**:
- Minimum overall: 80%
- Critical paths: 100%
- New code: Must include tests

**Exit criteria**: All tests passing, coverage met, quality gates passed.

---

### Phase 5: Review

**Objective**: Validate code quality, security, and performance.

When reviewing:
1. Use `/run-review` to execute review workflow
2. Use `code-review` skill for automated analysis
3. Complete security checklist from `security-audit` skill
4. Check performance benchmarks
5. Verify accessibility requirements

**Review checklist**:
- [ ] Code quality and maintainability
- [ ] Security vulnerabilities
- [ ] Performance issues
- [ ] Test coverage
- [ ] Documentation completeness

**Exit criteria**: All review items addressed, approvals obtained.

---

### Phase 6: Deployment

**Objective**: Release to production safely.

When deploying:
1. Use `/prepare-release` to run deployment checklist
2. Use `deployment` skill for verification
3. Complete release checklist
4. Verify CI/CD pipeline
5. Set up monitoring and alerts

**Pre-deployment checklist**:
- [ ] All tests passing
- [ ] Security audit complete
- [ ] Documentation updated
- [ ] Rollback plan documented
- [ ] Monitoring configured

**Exit criteria**: Successful production deployment, monitoring active.

---

## Iterative Changes & Rework

Real projects rarely follow a linear path. Requirements change, designs evolve, and issues surface late. Here's how to handle changes at any phase.

### Change Triggers

| Trigger | Impact | Action |
|---------|--------|--------|
| New requirement discovered | May affect architecture | Assess scope, update docs, possibly re-plan |
| Bug found in production | Code + possibly design | Fix, add tests, update if pattern issue |
| Performance issue | Implementation | Profile, fix, document learnings |
| User feedback | Requirements + UI/UX | Update requirements, prioritize changes |
| Security vulnerability | Immediate | Hotfix, then root cause analysis |
| Scope change from stakeholder | All phases | Re-assess, update ADRs, re-plan affected areas |

### Handling Changes by Current Phase

**During Implementation (most common):**
```
Change Request
     │
     ▼
┌─────────────────────────────────────────┐
│  1. Assess Impact                       │
│     • Does this change the architecture?│
│     • Does this invalidate existing code│
│     • What tests need updating?         │
└─────────────────────────────────────────┘
     │
     ├─── Small (same architecture) ───▶ Update code + tests, continue
     │
     └─── Large (architecture change) ──▶ Go back to Planning
                                              │
                                              ▼
                                         Update ADR
                                         Revise design doc
                                         Re-estimate tasks
                                         Resume implementation
```

**After Deployment:**
```
Issue/Change Request
     │
     ▼
┌─────────────────────────────────────────┐
│  Severity Assessment                    │
│  • P0: Production down → Hotfix NOW     │
│  • P1: Major bug → Fix this sprint      │
│  • P2: Minor issue → Backlog            │
│  • Feature request → New discovery      │
└─────────────────────────────────────────┘
     │
     ├─── Hotfix ──▶ Fix → Test → Deploy → Post-mortem → Update docs
     │
     └─── Feature ──▶ Mini-discovery → Planning → Implementation → ...
```

### When to Loop Back

| Situation | Go Back To | What to Update |
|-----------|------------|----------------|
| "We need a completely different approach" | Planning | ADR, design doc, task breakdown |
| "New stakeholder requirements" | Discovery | Requirements doc, user stories |
| "This feature is more complex than expected" | Planning | Task breakdown, estimates, possibly ADR |
| "Tests revealed design flaw" | Planning | Design doc, ADR if architectural |
| "Performance won't meet SLA" | Planning | ADR for optimization approach |
| "Security audit failed" | Implementation | Fix code, update security checklist |

### Change Documentation

When making significant changes, document them:

```markdown
## Change Record

**Date**: YYYY-MM-DD
**Type**: Requirement / Architecture / Implementation / Hotfix
**Triggered by**: [What caused this change]

### Original Approach
[What was planned/built]

### New Approach
[What changed and why]

### Impact
- [ ] Requirements doc updated
- [ ] ADR created/updated
- [ ] Design doc updated
- [ ] Affected code refactored
- [ ] Tests updated
- [ ] Documentation updated

### Lessons Learned
[What to do differently next time]
```

### Mini-Cycles for Changes

For changes that don't require full phase restarts:

```
┌──────────────────────────────────────────────────────────┐
│                    Mini-Cycle                            │
│                                                          │
│   Assess → Plan (brief) → Implement → Test → Review     │
│     │                                            │       │
│     └────────────── Validate ◄───────────────────┘       │
└──────────────────────────────────────────────────────────┘
```

1. **Assess**: What's the scope? Does it change architecture?
2. **Plan**: Quick task list, update ADR if needed
3. **Implement**: Make changes following existing patterns
4. **Test**: Run full validation suite
5. **Review**: Code review, check for regressions

---

## AI Collaboration Guidelines

### DO

- Ask clarifying questions before major implementations
- Propose architecture before coding complex features
- Write tests alongside implementation
- Document decisions and rationale
- Reference existing patterns in codebase
- Use provided skills and commands for workflows
- Break down large tasks into smaller steps

### DON'T

- Skip testing or security considerations
- Make breaking changes without discussion
- Hard-code secrets, credentials, or environment-specific values
- Bypass pre-commit hooks or quality gates
- Assume requirements - ask when unclear
- Over-engineer simple solutions

---

## Validation Requirements

**Every generated artifact must be validated before moving forward.**

### Automatic Validation

After generating any output, run the `validator` skill to ensure correctness:

| Artifact | Validation |
|----------|------------|
| Requirements/User Stories | Completeness, clarity, no ambiguity |
| Architecture/Design | Technical correctness, Phoenix patterns |
| Code (Elixir) | Compiles, formatted, passes credo |
| Migrations | Reversible, safe, correct types |
| Tests | Pass, adequate coverage, no flaky tests |

### Validation Commands

```bash
# Always run after code generation
mix compile --warnings-as-errors  # Must pass
mix format --check-formatted      # Must pass
mix credo --strict                # Should pass
mix test                          # Must pass

# Before commits
mix test --cover                  # Check coverage
mix sobelow                       # Security check
```

### Phase Gate Validation

Before transitioning between phases, validate:

| Transition | Required Validations |
|------------|---------------------|
| Discovery → Planning | Requirements complete, stakeholders identified |
| Planning → Implementation | Architecture reviewed, tasks broken down |
| Implementation → Testing | Code compiles, basic tests pass |
| Testing → Review | All tests pass, coverage met |
| Review → Deployment | Security audit, performance checked |

### Validation Report Format

After validation, report results as:

```
✓ PASS: [Check name]
✗ FAIL: [Check name] - [Issue and fix]
⚠ WARN: [Check name] - [Recommendation]
```

---

## Project Structure

<!-- Phoenix Application Structure -->

```
lib/
├── my_app/                    # Core business logic
│   ├── accounts/              # Accounts context (users, auth)
│   │   ├── user.ex           # User schema
│   │   └── accounts.ex       # Context functions
│   ├── catalog/               # Example business context
│   │   ├── product.ex        # Product schema
│   │   └── catalog.ex        # Context functions
│   └── application.ex         # OTP Application
│
├── my_app_web/                # Web layer
│   ├── components/            # Phoenix components
│   │   └── core_components.ex
│   ├── controllers/           # Traditional controllers
│   ├── live/                  # LiveView modules
│   │   ├── page_live.ex
│   │   └── user_live/
│   ├── router.ex              # Routes
│   ├── endpoint.ex            # HTTP endpoint
│   └── telemetry.ex           # Metrics
│
├── priv/
│   ├── repo/migrations/       # Ecto migrations
│   └── static/                # Static assets
│
└── test/
    ├── my_app/                # Context tests
    ├── my_app_web/            # Web layer tests
    └── support/               # Test helpers
```

---

## Common Commands

```bash
# Development
mix phx.server                 # Start Phoenix server (localhost:4000)
iex -S mix phx.server          # Start with interactive shell
mix deps.get                   # Install dependencies
mix deps.compile               # Compile dependencies

# Database
mix ecto.create                # Create database
mix ecto.migrate               # Run migrations
mix ecto.rollback              # Rollback last migration
mix ecto.reset                 # Drop, create, migrate, seed
mix ecto.gen.migration <name>  # Generate migration

# Code Generation
mix phx.gen.live <Context> <Schema> <table> [fields]    # LiveView CRUD
mix phx.gen.html <Context> <Schema> <table> [fields]    # HTML CRUD
mix phx.gen.context <Context> <Schema> <table> [fields] # Context only
mix phx.gen.schema <Schema> <table> [fields]            # Schema only
mix phx.gen.auth Accounts User users                    # Auth scaffolding

# Testing
mix test                       # Run all tests
mix test --cover               # Run with coverage
mix test test/path/to_test.exs # Run specific file
mix test test/path:42          # Run specific test at line

# Code Quality
mix format                     # Format code (auto-fixes)
mix format --check-formatted   # Check formatting
mix credo                      # Static analysis
mix dialyzer                   # Type checking
mix sobelow                    # Security analysis
```

---

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `MIX_ENV` | Environment (dev/test/prod) | Yes |
| `DATABASE_URL` | PostgreSQL connection string | Yes |
| `SECRET_KEY_BASE` | Phoenix secret key (generate with `mix phx.gen.secret`) | Yes (prod) |
| `PHX_HOST` | Host for production (e.g., example.com) | Yes (prod) |
| `PORT` | HTTP port (default: 4000) | No |
| `POOL_SIZE` | Database connection pool size | No |

See `.env.example` for all available variables.

---

## Key Resources

### Setup Documentation (Initial Project Creation)

**These files contain proprietary project creation methodology:**
- `docs/setup/phases/` - Initial discovery, planning, and setup phases
  - `01-discovery/` - Requirements gathering templates
  - `02-planning/` - Architecture and task planning
  - `03-implementation/` - AI collaboration guide for setup
- `docs/setup/templates/` - Setup document templates (PRD, ADR, Design Doc)
- `docs/setup/checklists/` - Project kickoff checklist
- `.claude/commands/setup/` - Setup phase commands (`/start-discovery`, `/start-planning`, `/start-implementation`)
- `.claude/skills/setup/` - Setup skills (`architecture-planner`)

### Ongoing Development Documentation

**These files are for continuous improvement and can be shared:**
- `docs/i/phases/` - Ongoing phase documentation
  - `03-implementation/` - Coding standards and best practices
  - `04-testing/` - Testing requirements and templates
  - `05-review/` - Code review and security checklists
  - `06-deployment/` - Deployment procedures
- `docs/i/templates/` - Ongoing templates (change requests, template feedback)
- `docs/i/checklists/` - Ongoing checklists (code-complete, release-ready, validation)
- `docs/i/guides/` - Integration guides (some auto-synced from external repos)
- `docs/i/ui-design/` - Complete UI/UX design system

### Configuration

- `.claude/commands/i/` - Ongoing workflow commands (review, release, change handling)
- `.claude/skills/i/` - Development skills (code-review, security-audit, testing, etc.)
- `.claude/rules/i/` - Development rules (code-style, security, testing, git-workflow)
- `.claude/templates/ui/` - UI component templates
- `.claude/assets/i/brand/` - Brand assets (logos, icons, favicons)
- `.claude/settings.json` - Team settings and permissions

### Platform-Specific

- `config/web/` - Web project configuration
- `config/mobile/` - Mobile project configuration
- `config/backend/` - Backend project configuration
- `config/cli/` - CLI project configuration

---

## Getting Started

### For New Projects (Using Setup Methodology)

1. Run `./scripts/setup/init-project.sh <project-name> <type>` to initialize
2. Update this CLAUDE.md with your project specifics
3. Configure `.claude/settings.json` for your team
4. Set up environment variables from `.env.example`
5. Use `/start-discovery` to begin the development process (located in `.claude/commands/setup/`)
6. Follow the setup phases in sequence:
   - Discovery → Planning → Implementation → Testing → Review → Deployment

**Note:** The setup commands and documentation in `docs/setup/` and `.claude/*/setup/` contain proprietary project creation methodology. These files should be excluded when sharing projects with external engineers. They are now located OUTSIDE the `/i/` convention to ensure they are never accidentally synced.

### For Ongoing Development (Shared with External Engineers)

External engineers working on improvements should:
1. Use ongoing commands: `/run-review`, `/prepare-release`, `/handle-change`
2. Reference `docs/i/phases/` for development standards
3. Follow `.claude/rules/i/` for code style, security, testing, and git workflow
4. Use `.claude/skills/i/` for specialized tasks (code-review, security-audit, etc.)

The setup methodology files will not be available to external engineers.

## Interactor Workspace

@interactor-workspace/CONSUMER_CLAUDE.md
