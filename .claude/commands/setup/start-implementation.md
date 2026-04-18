# Start Implementation Phase

Initialize the Implementation phase for coding and development.

## Instructions

When this command is invoked, perform the following:

### 1. Verify Phoenix Project Exists

**CRITICAL**: Check if the Phoenix project is initialized before proceeding.

```bash
# Check for mix.exs
ls mix.exs 2>/dev/null
```

#### If No mix.exs Found

**STOP** and guide the user to create the Phoenix project first:

```markdown
## ⚠️ Phoenix Project Not Found

The implementation phase requires an initialized Phoenix project.

### Option 1: Return to Planning Phase
Run `/start-planning` which will guide you through Phoenix project creation.

### Option 2: Create Phoenix Project Now

1. **Derive app name** from your project (snake_case):
   - Example: "Meeting Recording Note Taker" → `meeting_recording_note_taker`

2. **Create the project**:
   ```bash
   mix phx.new . --app <app_name> --database postgres --live
   ```

   Or in a new directory:
   ```bash
   mix phx.new <app_name> --database postgres --live
   ```

3. **Configure port** (edit `config/dev.exs`):
   ```elixir
   http: [ip: {127, 0, 0, 1}, port: 4005]
   ```

4. **Initialize**:
   ```bash
   mix deps.get
   mix ecto.create
   ```

Then run `/start-implementation` again.
```

Do not proceed with implementation until the Phoenix project exists.

### 2. Verify Planning Completion

Check if planning artifacts exist:
- `docs/planning/architecture.md`
- `docs/planning/tasks.md`

If missing, warn that planning phase may be incomplete.

### 3. Set Context

Update the project phase in CLAUDE.md to "implementation".

### 4. Development Environment Check

Verify development setup:
- [ ] Dependencies installed (`npm install` or equivalent)
- [ ] Environment variables configured (`.env`)
- [ ] Development server runs
- [ ] Tests can execute
- [ ] Development port configured (4005 or higher)

### Port Configuration

**Development**: Use port **4005 or higher** to avoid conflicts with other services.
**Production**: Use port **4000** (standard Phoenix default).

#### Dynamic Port Configuration (Recommended)

Update `config/dev.exs` to read from environment variable with fallback:
```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4005")],
  # ... rest of config
```

This allows the startup script to find an available port automatically.

For production (`config/runtime.exs`):
```elixir
port = String.to_integer(System.get_env("PORT") || "4000")
```

### 5. Create Environment Configuration

If `.env` does not exist, create it from `.env.example`:

```bash
cp .env.example .env
```

#### Required Configuration

Ask the user for the following **required** values:

| Variable | Description | Default | Action |
|----------|-------------|---------|--------|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://postgres:postgres@localhost:5432/my_app_dev` | Ask for app name to customize database name |
| `SECRET_KEY_BASE` | Phoenix secret (64+ chars) | *none* | Auto-generate with `mix phx.gen.secret` |
| `LIVE_VIEW_SIGNING_SALT` | LiveView salt (32 chars) | *none* | Auto-generate with `mix phx.gen.secret 32` |

#### Interactive Setup Flow

1. **Ask for Application Name**:
   ```
   What is your application name? (e.g., my_app)
   ```
   - Use this to set database name: `{app_name}_dev`
   - Update `DATABASE_URL` accordingly

2. **Generate Security Keys**:
   ```bash
   # Generate and set SECRET_KEY_BASE
   mix phx.gen.secret

   # Generate and set LIVE_VIEW_SIGNING_SALT
   mix phx.gen.secret 32
   ```

3. **Ask About Optional Services**:
   ```
   Will your application use any of these services? (You can configure later)

   - [ ] Email (SMTP/Mailgun/SendGrid)
   - [ ] Stripe payments
   - [ ] AWS S3 storage
   - [ ] Error tracking (Sentry)
   - [ ] Interactor Authentication (recommended)
   - [ ] Interactor API
   ```

   For any selected, note that configuration is needed in `.env`.

#### Example .env Setup

After gathering information, update `.env` with:

```bash
# Application Settings
MIX_ENV=dev
PORT=4005
PHX_HOST=localhost

# Database (customize database name)
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/{app_name}_dev
POOL_SIZE=10

# Security (auto-generated)
SECRET_KEY_BASE={generated_64_char_secret}
LIVE_VIEW_SIGNING_SALT={generated_32_char_salt}

# Interactor Authentication (recommended for all apps)
INTERACTOR_URL=https://auth.interactor.com
INTERACTOR_OAUTH_ISSUER=https://interactor.com
# INTERACTOR_API_KEY=your_api_key  # For server-to-server calls

# Optional services - configure as needed
# Uncomment and fill in when ready:
# SMTP_HOST=
# STRIPE_SECRET_KEY=
# AWS_ACCESS_KEY_ID=
# SENTRY_DSN=
```

#### Deferred Configuration Notice

Display to user:
```markdown
## Environment Configuration Created

✅ `.env` file created from `.env.example`
✅ Database URL configured for: {app_name}_dev
✅ Security keys auto-generated

### Configure Later
The following optional services can be configured in `.env` when needed:
- Email settings (SMTP_*, MAILGUN_*, etc.)
- Payment processing (STRIPE_*)
- Cloud storage (AWS_*)
- Error tracking (SENTRY_DSN)
- External APIs (INTERACTOR_API_KEY, GITHUB_TOKEN)

Edit `.env` anytime to add these configurations.

⚠️  Remember: NEVER commit `.env` to version control!
```

#### Validation
- [ ] `.env` file exists
- [ ] `DATABASE_URL` has correct database name
- [ ] `SECRET_KEY_BASE` is set (64+ characters)
- [ ] `LIVE_VIEW_SIGNING_SALT` is set (32 characters)
- [ ] `PORT` is set to 4005 or higher for development

### 6. Interactor Authentication Setup

**IMPORTANT**: Use Interactor server for all authentication needs.

#### Why Use Interactor Authentication?
- Single sign-on across all Interactor ecosystem apps
- JWT tokens with RS256 signing for secure verification
- No need to implement password hashing, session management, etc.
- JWKS endpoint for external token verification

#### Required Environment Variables
```bash
# Add to .env (should already be in .env.example)
INTERACTOR_URL=https://auth.interactor.com
INTERACTOR_OAUTH_ISSUER=https://interactor.com
# INTERACTOR_API_KEY=your_api_key  # For server-to-server calls
```

#### Implementation Checklist
- [ ] Environment variables configured
- [ ] JWT verification using Interactor JWKS endpoint
- [ ] Login redirect to Interactor (or token exchange)
- [ ] Session management with validated JWT claims
- [ ] Protected routes check authentication

#### Quick Start Code (Elixir/Phoenix)
```elixir
# Verify JWT using Interactor's public keys
def verify_interactor_token(token) do
  jwks_url = "#{System.get_env("INTERACTOR_URL")}/oauth/jwks"
  # Fetch JWKS and verify token signature
  # See docs/i/guides/interactor-authentication.md for full implementation
end
```

#### Quick Start Code (Node.js)
```javascript
// Verify JWT using Interactor's public keys
const jwksClient = require('jwks-rsa');
const jwt = require('jsonwebtoken');

const client = jwksClient({
  jwksUri: `${process.env.INTERACTOR_URL}/oauth/jwks`
});

async function verifyInteractorToken(token) {
  // See docs/i/guides/interactor-authentication.md for full implementation
}
```

See: `docs/i/guides/interactor-authentication.md` for complete implementation guide.

### 7. Material UI Design System - MANDATORY

**CRITICAL**: All UI code MUST follow Material UI design patterns. This is enforced by `.claude/rules/material-ui-enforcement.md`.

#### Required Reading Before ANY UI Work

You **MUST** read these files in order before writing any UI code:

1. `.claude/rules/material-ui-enforcement.md` - Auto-applied enforcement rule
2. `.claude/rules/i/ui-design/material-ui/index.md` - Complete design specification
3. `.claude/rules/i/ui-design/gnb-components.md` - Navigation patterns

#### 6 Mandatory UI Patterns (Non-Negotiable)

| # | Pattern | Required Implementation |
|---|---------|------------------------|
| 1 | **Lottie Animated Logo** | Use `InteractorLogo_Light.json` or `_Dark.json` |
| 2 | **GREEN Create Button** | `#4CD964` with hover `#3DBF55` (rounded-full) |
| 3 | **Quick Create (+)** | Green FAB in AppBar opens right panel |
| 4 | **Dual Notification Badge** | Primary count + secondary red error count |
| 5 | **Warnings BELOW Items** | Warning placed immediately BELOW problematic item |
| 6 | **Feedback Section** | 5 emoji faces fixed at drawer bottom |

#### Design Tokens (Use Exactly)

```
Colors:
  Primary Green:    #4CD964  (hover: #3DBF55)
  Error Red:        #FF3B30
  Warning Yellow:   #FFCC00
  Background:       #F5F5F5  (light) / #1E1E1E (dark)
  Surface:          #FFFFFF  (light) / #2D2D2D (dark)

Border Radius:
  Buttons:          9999px   (pill-shaped, rounded-full)
  Cards/Modals:     16px     (rounded-2xl)
  Inputs:           8px      (rounded-lg)

Sizing:
  AppBar Height:    64px     (h-16)
  Sidebar Width:    240px    (w-64 open) / 56px (collapsed)
  Right Panel:      320px    (w-80)
```

#### TailwindCSS Component Patterns

**Primary Button (Create Actions)**:
```html
<button class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors">
  Create
</button>
```

**AppBar**:
```html
<header class="bg-white shadow-sm h-16 fixed top-0 left-0 right-0 z-50 flex items-center px-4">
  <!-- Logo | Search | Actions -->
</header>
```

**Left Drawer**:
```html
<aside class="w-64 bg-white h-screen fixed left-0 top-16 shadow-lg flex flex-col">
  <!-- Create Button | Navigation | Flex Spacer | Feedback -->
</aside>
```

#### Phoenix/LiveView Pattern

```elixir
# In core_components.ex - Primary button (GREEN for create actions)
attr :variant, :string, default: "primary", values: ~w(primary secondary danger)

def button(assigns) do
  ~H"""
  <button class={[
    "font-medium px-6 py-2 rounded-full shadow-md transition-colors",
    @variant == "primary" && "bg-[#4CD964] hover:bg-[#3DBF55] text-white",
    @variant == "secondary" && "bg-white hover:bg-gray-50 text-gray-700 border border-gray-200",
    @variant == "danger" && "bg-[#FF3B30] hover:bg-red-600 text-white"
  ]}>
    <%= render_slot(@inner_block) %>
  </button>
  """
end
```

#### Brand Assets Setup

Copy from `.claude/assets/i/brand/` to your project's `priv/static/brand/`:
- `lottie/InteractorLogo_Light.json`
- `lottie/InteractorLogo_Dark.json`
- `icons/icon_simple_green_v1.png`

#### UI Validation Checklist

Before ANY UI code is committed:
- [ ] Using Lottie animated logo (not static image)
- [ ] All create buttons use `#4CD964` green
- [ ] AppBar has Quick Create (+) button on right
- [ ] Notifications show dual badge (count + errors)
- [ ] Warnings placed BELOW problematic items
- [ ] Feedback section (5 emoji) at drawer bottom
- [ ] All buttons are pill-shaped (`rounded-full`)
- [ ] Cards use `rounded-2xl` (16px radius)
- [ ] Using correct shadow levels (shadow-sm, shadow-md, shadow-lg)

---

### 8. Display Implementation Guidelines

```markdown
## Implementation Phase Guidelines

### Before Coding
1. Review the task requirements
2. Understand the acceptance criteria
3. Check related architecture decisions
4. Identify test cases first (TDD)
5. **Read Material UI rules if working on UI** (see section 6 above)

### While Coding
1. Follow code style guidelines (`.claude/rules/i/code-style.md`)
2. **Follow Material UI patterns for all UI code** (`.claude/rules/material-ui-enforcement.md`)
3. Write tests alongside code
4. Commit frequently with meaningful messages
5. Keep changes focused and atomic

### Code Review Preparation
1. Self-review before requesting review
2. Ensure tests pass
3. Update documentation if needed
4. Run linter and formatter
5. **Verify Material UI compliance for UI changes**

### AI Collaboration Tips
- Explain context before asking for help
- Review generated code carefully
- Ask for explanations when unclear
- Request tests for generated code
```

### 9. Display Current Tasks

If `docs/planning/tasks.md` exists, show:
- Current sprint/milestone tasks
- Task priorities
- Dependencies

### 10. Suggested Prompts

```
"Help me implement [feature] based on the architecture"
"Write tests for [function/component]"
"Review this code for [concerns]"
"Refactor [code] to improve [aspect]"
"Add error handling to [function]"
"Implement [pattern] for [use case]"
```

### 11. Available Skills

```markdown
### Skills for Implementation
- `code-review` - Review code for quality and security
- `test-generator` - Generate test scaffolds
- `doc-generator` - Update documentation

### Development Practices Skills (from interactor-workspace)
- `dev-logging` - File-based logging for AI debugging
- `service-launcher` - Multi-service launcher script
- `hot-reload` - Hot code reloading API
- `ci-setup` - GitHub Actions CI pipeline
- `code-quality` - Code quality enforcement
- `deployment-infra` - Deployment infrastructure setup
```

### 12. Create Development Start Script

Create `./scripts/start.sh` - a comprehensive development startup script that:

1. **Checks all dependencies**:
   - Elixir/Erlang versions (via asdf or system)
   - Node.js (if assets pipeline needed)
   - PostgreSQL running and accessible
   - Required CLI tools (mix, npm/yarn)

2. **Validates environment setup**:
   - `.env` file exists with required variables
   - Database configured and accessible
   - Required environment variables set

3. **Auto-setup if environment not ready**:
   - Prompt user to install missing dependencies
   - Offer to create `.env` from `.env.example`
   - Run `mix deps.get` if deps missing
   - Run `mix ecto.setup` if database not initialized
   - Run `npm install` if node_modules missing (for assets)

4. **Finds an available port**:
   - Start from port 4005
   - Check if port is in use, increment if needed
   - Export PORT environment variable for Phoenix

5. **Starts the development server**:
   - Run migrations if pending
   - Start Phoenix server with IEx shell on available port
   - Display helpful startup information

```bash
#!/usr/bin/env bash
# ./scripts/start.sh - Development environment startup script
#
# Usage: ./scripts/start.sh [options]
# Options:
#   --check-only    Only check dependencies, don't start server
#   --setup         Run full setup (deps, db, assets)
#   --skip-checks   Skip dependency checks and start immediately
#   --port PORT     Use specific port (default: auto-find from 4005)
```

**Port Finding Logic** (must be included in start.sh):
```bash
# Find available port starting from 4005
find_available_port() {
    local port=${1:-4005}
    local max_port=$((port + 100))

    while [ $port -lt $max_port ]; do
        if ! lsof -i :$port > /dev/null 2>&1; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done

    echo "Error: No available port found between $1 and $max_port" >&2
    return 1
}

# Use specified port or find available one
if [ -n "$SPECIFIED_PORT" ]; then
    PORT=$SPECIFIED_PORT
else
    PORT=$(find_available_port 4005)
    if [ $? -ne 0 ]; then
        exit 1
    fi
fi

export PORT
echo "Starting Phoenix on port $PORT..."
```

**Required behavior**:
- Exit with clear error messages if critical dependencies missing
- Offer interactive prompts for fixable issues
- Support `--help` flag for usage information
- Be idempotent (safe to run multiple times)
- Work on macOS and Linux
- **Automatically find available port if default is in use**

## Output

```markdown
## Implementation Phase Initialized

**Status**: Ready for development

### Architecture Summary
[Show key points from architecture doc if available]

### Current Tasks
[List tasks from planning if available]

### Development Checklist
- [ ] Environment configured
- [ ] Dependencies installed
- [ ] Tests running
- [ ] Linter configured

### Guidelines Reference
- Code style: `.claude/rules/i/code-style.md`
- Testing: `.claude/rules/i/testing.md`
- Security: `.claude/rules/i/security.md`
- Git workflow: `.claude/rules/i/git-workflow.md`

### Skills Available
- `code-review` - Code quality analysis
- `test-generator` - Create test scaffolds
- `doc-generator` - Update documentation

### Development Practices (interactor-workspace)
- `dev-logging` - File-based logging for AI debugging
- `service-launcher` - Multi-service launcher script
- `hot-reload` - Hot code reloading API
- `ci-setup` - GitHub Actions CI pipeline
- `code-quality` - Code quality enforcement
- `deployment-infra` - Deployment infrastructure

### Quick Commands
```bash
mix phx.server   # Start development server (port 4005+)
mix test         # Run tests
mix format       # Format code
mix credo        # Static analysis
```

> **Note**: Development runs on port 4005+ (localhost:4005). Production uses port 4000.

What would you like to implement first?
```

## Validation Requirements

### Entry Validation
Before starting implementation, verify planning outputs:
```
"Validate planning documents"
```

### During Implementation - Validate Every Change

After generating ANY code, run these validation commands:

```bash
# Required after every code generation
mix compile --warnings-as-errors    # Must pass
mix format --check-formatted        # Must pass
mix credo --strict                  # Should pass

# After writing tests
mix test                            # Must pass
```

### Code Generation Validation Checklist

After generating each type of code:

| Generated Code | Validation |
|---------------|------------|
| Schema/Migration | `mix ecto.migrate`, check rollback works |
| Context functions | `mix compile`, verify pattern matching |
| LiveView | Check mount/handle_params/handle_event pattern |
| Controller | Verify action_fallback, proper responses |
| Tests | `mix test`, verify meaningful assertions |

### Continuous Validation

Run after each significant change:
```elixir
# In IEx during development
recompile()  # Check for compilation errors
```

### Exit Gate Validation
Before proceeding to `/run-review`:

- [ ] All code compiles without warnings
- [ ] All tests pass
- [ ] Code is formatted (`mix format`)
- [ ] Credo passes (`mix credo --strict`)
- [ ] Coverage meets minimum threshold
- [ ] No TODO comments left in code

Run the `validator` skill:
```
"Validate the implementation before code review"
```

---

## Requirement-Aware Implementation

### Before Starting Each Milestone
1. List the tasks in this milestone
2. For each task, identify the requirement(s) it implements
3. Before coding, read the requirement's acceptance criteria
4. After coding, verify acceptance criteria are met

### Before Marking a Milestone Complete
- [ ] All tasks in the milestone are complete
- [ ] All acceptance criteria for linked requirements are met
- [ ] UI for all user-facing features in this milestone is functional
- [ ] Update Requirements Coverage Matrix status column

### Implementation Completion Gate
Before declaring implementation complete:
- [ ] Every requirement in the Coverage Matrix has status "Complete" or "Deferred" (with justification)
- [ ] No "Must" requirement has status "Deferred"
- [ ] Every LiveView/page is functional with real data
- [ ] Every pipeline (OCR, AI, export) works end-to-end
- [ ] Every user role can complete their core workflows

### 13. Update Team Settings

After the application has been built, update `.claude/settings.json` to reflect the project's technology stack:

#### For Elixir/Phoenix Projects

Update the settings to include Elixir-specific permissions and hooks:

```json
{
  "permissions": {
    "allow": [
      "Bash(git diff:*)",
      "Bash(git status:*)",
      "Bash(git log:*)",
      "Bash(git branch:*)",
      "Bash(mix test:*)",
      "Bash(mix format:*)",
      "Bash(mix credo:*)",
      "Bash(mix compile:*)",
      "Bash(mix deps.get:*)",
      "Bash(mix ecto.migrate:*)",
      "Bash(mix phx.routes:*)",
      "Bash(iex:*)",
      "Read(**/*)",
      "Glob(**/*)",
      "Grep(**/*)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(git commit:*)",
      "Bash(git checkout:*)",
      "Bash(git merge:*)",
      "Bash(mix ecto.drop:*)",
      "Bash(mix ecto.reset:*)",
      "Bash(mix ecto.rollback:*)",
      "Bash(mix deps.update:*)",
      "Bash(rm:*)",
      "Bash(curl:*)",
      "Bash(wget:*)",
      "Write(.env*)",
      "Write(**/secrets/**)",
      "Edit(mix.exs)",
      "Edit(mix.lock)"
    ],
    "deny": [
      "Write(.env)",
      "Write(.env.local)",
      "Write(.env.production)",
      "Write(**/credentials*)",
      "Write(**/secrets/**)",
      "Read(.env)",
      "Read(.env.local)",
      "Read(.env.production)",
      "Bash(rm -rf /)",
      "Bash(rm -rf ~)",
      "Bash(sudo:*)",
      "Bash(mix ecto.drop --force:*)"
    ],
    "additionalDirectories": []
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write(*.ex)",
        "hooks": [
          {
            "type": "command",
            "command": "mix format \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      },
      {
        "matcher": "Write(*.exs)",
        "hooks": [
          {
            "type": "command",
            "command": "mix format \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      },
      {
        "matcher": "Write(*.heex)",
        "hooks": [
          {
            "type": "command",
            "command": "mix format \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      },
      {
        "matcher": "Write(*.js)",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      },
      {
        "matcher": "Write(*.json)",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      },
      {
        "matcher": "Write(*.md)",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write(.env*)",
        "hooks": [
          {
            "type": "command",
            "command": "echo '⚠️  WARNING: Modifying environment file. Ensure no secrets are being committed.'"
          }
        ]
      },
      {
        "matcher": "Write(**/production/**)",
        "hooks": [
          {
            "type": "command",
            "command": "echo '⚠️  WARNING: Modifying production configuration file.'"
          }
        ]
      },
      {
        "matcher": "Edit(config/runtime.exs)",
        "hooks": [
          {
            "type": "command",
            "command": "echo '⚠️  WARNING: Modifying runtime configuration. Verify environment variables.'"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'PROJECT_ROOT='$(pwd) >> $CLAUDE_ENV_FILE 2>/dev/null || true"
          }
        ]
      }
    ]
  },
  "env": {
    "MIX_ENV": "dev",
    "EDITOR": "code"
  },
  "attribution": {
    "commit": "Generated with AI assistance\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
    "pr": "Generated with AI assistance"
  }
}
```

#### Settings Customization Checklist

When updating settings for your project:

1. **Permissions - Allow**: Add commands your team runs frequently
   - Build commands (`mix compile`, `mix deps.get`)
   - Test commands (`mix test`, `mix coveralls`)
   - Format/lint commands (`mix format`, `mix credo`)

2. **Permissions - Ask**: Add potentially destructive commands
   - Database operations (`mix ecto.drop`, `mix ecto.reset`)
   - Dependency changes (`mix deps.update`)
   - Git operations that modify history

3. **Permissions - Deny**: Add commands that should never run
   - Production database operations
   - Credential file access
   - Destructive system commands

4. **Hooks - PostToolUse**: Auto-format files after writing
   - `.ex`, `.exs`, `.heex` → `mix format`
   - `.js`, `.json`, `.md` → `prettier`

5. **Environment Variables**: Set project-specific defaults
   - `MIX_ENV`: Default environment
   - `DATABASE_URL`: If using external database
   - Custom project variables

#### Validation
After updating settings:
- [ ] Settings file is valid JSON
- [ ] All file patterns use correct glob syntax
- [ ] Hooks reference available formatters
- [ ] No sensitive data in env section

### 14. Update Project README

After the application has been built, update the project documentation:

#### Step 1: Rename Existing README
Rename the template setup README to preserve it for reference:

```bash
mv README.md README_SETUP.md
```

#### Step 2: Create Application README
Create a new `README.md` tailored to the built application with the following structure:

```markdown
# [Application Name]

[Brief description of what the application does]

## Features

- [Feature 1]
- [Feature 2]
- [Feature 3]

## Tech Stack

- **Backend**: Elixir/Phoenix
- **Database**: PostgreSQL
- **Frontend**: Phoenix LiveView, TailwindCSS
- [Other technologies used]

## Getting Started

### Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- PostgreSQL 14+
- Node.js 18+ (for assets)

### Installation

1. Clone the repository:
   ```bash
   git clone [repository-url]
   cd [project-directory]
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Set up the database:
   ```bash
   mix ecto.setup
   ```

4. Install frontend dependencies:
   ```bash
   cd assets && npm install && cd ..
   ```

5. Start the development server:
   ```bash
   ./scripts/start.sh
   # Or manually: mix phx.server
   ```

6. Visit [`localhost:4005`](http://localhost:4005) in your browser.

## Development

### Running Tests
```bash
mix test
```

### Code Quality
```bash
mix format      # Format code
mix credo       # Static analysis
mix dialyzer    # Type checking
```

### Database Migrations
```bash
mix ecto.migrate    # Run migrations
mix ecto.rollback   # Rollback last migration
```

## Project Structure

```
lib/
├── [app_name]/           # Core business logic (contexts)
├── [app_name]_web/       # Web layer (controllers, views, templates)
test/                     # Test files
priv/repo/migrations/     # Database migrations
```

## Configuration

See `.env.example` for required environment variables.

## Documentation

- [Architecture](docs/planning/architecture.md)
- [API Documentation](docs/api/) (if applicable)

## Contributing

[Contributing guidelines if applicable]

## License

[License information]
```

#### Customization Requirements

When creating the new README, ensure:
1. **Application name** matches the actual project name
2. **Features** reflect what was actually implemented
3. **Tech stack** lists all technologies used
4. **Port number** matches the configured development port (default: 4005)
5. **Project structure** reflects the actual directory layout
6. **Environment variables** reference the actual `.env.example` file

#### Validation
After creating the new README:
- [ ] README.md exists with application-specific content
- [ ] README_SETUP.md exists (preserved template documentation)
- [ ] All links in README are valid
- [ ] Installation instructions work when followed
