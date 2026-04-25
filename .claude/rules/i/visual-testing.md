---
paths: [
  "**/*.heex",
  "**/*.html",
  "**/*.css",
  "**/live/**/*.ex",
  "**/components/**/*.ex",
  "**/templates/**/*.ex",
  "assets/js/**/*.js",
  "config/*.exs",
  "mix.exs",
  "mix.lock",
  "**/application.ex",
  "**/endpoint.ex",
  ".env.credentials",
  ".env.prod"
]
excludePaths: [
  "**/*_test.exs",
  "**/test/**"
]
alwaysApply: true
---

# Mandatory Visual Testing Rule

**STOP** — Before marking any task as complete, you **MUST** run Playwright visual verification if the change touches UI files OR requires a server restart.

## When This Applies

### UI/UX changes — verify affected pages render correctly:
- LiveView modules (`**/live/**/*.ex`)
- HEEx templates (`**/*.heex`)
- Layout or component modules (`**/components/**/*.ex`)
- CSS/JS assets (`assets/**`)

### Server-touching changes — verify the app boots and the home page loads:
- Config files (`config/*.exs`, including `dev.exs`, `runtime.exs`, `config.exs`)
- Dependencies (`mix.exs`, `mix.lock`)
- OTP application or endpoint (`**/application.ex`, `**/endpoint.ex`)
- Environment files (`.env.credentials`, `.env.prod`)

## Required Steps

### For UI/UX changes:
1. **Launch the `visual-tester` agent** to capture screenshots of all affected pages
2. The agent will:
   - Navigate to each affected page via `/dev/login` → target page
   - Capture screenshots at mobile (375px), tablet (768px), and desktop (1440px)
   - Check dark mode rendering
   - Verify no horizontal overflow, touch targets ≥44px, text contrast
3. **Review the agent's report** — if it reports FAIL, fix the issues before completing
4. **Report results to the user** — include pass/fail status and any issues found

### For server-touching changes (config, deps, env, application boot):
1. **Restart the dev server** — the user's server at port 4040 must be restarted to pick up the change; remind them if they need to do it themselves
2. **Start an isolated test server** via `scripts/i/visual-test.sh start` (uses port 4041–4099, never 4040)
3. **Use Playwright** to navigate to `http://localhost:$PORT/` and verify the page loads without errors (no crash page, no boot error, HTTP 200)
4. **Navigate to `/dev/login`** and log in as a test user to confirm authentication works
5. **Navigate to the affected feature page** if the change was targeted (e.g., config for a specific service)
6. **Report boot success or failure** — if the server fails to start, diagnose and fix before declaring done

## How to Run

Use the built-in `visual-tester` subagent:

```
Agent(subagent_type: "visual-tester", prompt: "...")
```

For server restart verification, pass a prompt like:
```
"Start an isolated server via scripts/i/visual-test.sh, navigate to http://localhost:$PORT/ and /dev/login, confirm the app boots and the login page loads without errors. Take a screenshot."
```

If the Phoenix server is not running and cannot be started, note that visual testing was skipped and why.

## Non-Compliance

Do **NOT**:
- Skip visual testing because "the code compiles"
- Claim a UI feature is done without screenshots
- Claim a config/env/dep change is safe without verifying the server still boots
- Assume the app boots correctly after touching config or dependencies

If visual testing cannot be run (e.g., no database, server won't start), explicitly tell the user:
> "Visual testing was skipped because [reason]. Run `mix phx.server` and I can verify."

## Checklist

Before completing UI work:
- [ ] `visual-tester` agent ran on all affected pages
- [ ] No horizontal overflow at any viewport
- [ ] Dark mode renders correctly
- [ ] Touch targets ≥44px on mobile
- [ ] Typography and spacing match design system
- [ ] Screenshots reviewed and issues fixed

Before completing server-touching changes:
- [ ] Isolated test server started via `scripts/i/visual-test.sh`
- [ ] Root page (`/`) returns HTTP 200 (no crash/boot error)
- [ ] `/dev/login` page loads and login works
- [ ] Affected feature page verified if change was targeted
- [ ] Test server stopped via `scripts/i/visual-test.sh stop`
