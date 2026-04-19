---
paths: [
  "**/*.heex",
  "**/*.html",
  "**/*.css",
  "**/live/**/*.ex",
  "**/components/**/*.ex",
  "**/templates/**/*.ex",
  "assets/js/**/*.js"
]
excludePaths: [
  "**/*_test.exs",
  "**/test/**"
]
alwaysApply: true
---

# Mandatory Visual Testing Rule

**STOP** — Before marking any UI/UX task as complete, you **MUST** run Playwright visual verification.

## When This Applies

This rule applies whenever you create or modify any UI-related file:
- LiveView modules (`**/live/**/*.ex`)
- HEEx templates (`**/*.heex`)
- Layout or component modules (`**/components/**/*.ex`)
- CSS/JS assets (`assets/**`)

## Required Steps

1. **Launch the `visual-tester` agent** to capture screenshots of all affected pages
2. The agent will:
   - Navigate to each affected page via `/dev/login` → target page
   - Capture screenshots at mobile (375px), tablet (768px), and desktop (1440px)
   - Check dark mode rendering
   - Verify no horizontal overflow, touch targets ≥44px, text contrast
3. **Review the agent's report** — if it reports FAIL, fix the issues before completing
4. **Report results to the user** — include pass/fail status and any issues found

## How to Run

Use the built-in `visual-tester` subagent:

```
Agent(subagent_type: "visual-tester", prompt: "...")
```

Or if the Phoenix server is not running, note that visual testing was skipped and why.

## Non-Compliance

Do **NOT**:
- Skip visual testing because "the code compiles"
- Claim a UI feature is done without screenshots
- Assume responsive behavior is correct without checking

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
