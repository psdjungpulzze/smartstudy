## Commit & Push (Session-Scoped)

### Configure for your project
Replace these placeholders when you adopt this command in a new repo (edit this file or override in a project `.claude/commands/git-pr-push.md`):

- `<TEST_COMMAND>` — full test command run in step 3. Examples:
    - Elixir/Phoenix: `asdf exec mix test --cover`
    - Node/TS (Jest): `npm test -- --coverage`
    - Python (pytest): `pytest --cov`
    - Go: `go test -cover ./...`
- `<COVERAGE_EXEMPT_GLOB>` — module-name pattern that is exempt from the per-file coverage gate because it is template/view-heavy. Examples:
    - Phoenix LiveView: `*Live`, `*Panel`, `*Sidebar`
    - React components: `*Page.tsx`, `*Layout.tsx`
    - Leave blank if nothing is exempt.
- `<COVERAGE_CONFIG_HINT>` — where the overall coverage threshold is configured (e.g. `mix.exs test_coverage`, `jest.config.js coverageThreshold`, `pyproject.toml [tool.coverage]`). Only used in the narrative.

### Worktree preamble
This command operates on the working directory it is invoked from. If the session is attached to a PR worktree (via `/git-pr-attach` or `/git-pr-new`), all `git` commands below run against that worktree's branch. Bash `cd` does not persist between tool calls, so use absolute paths and `git -C <worktree-path> …` when needed. Do not `git checkout` a different branch — that would swap the worktree's HEAD.

### 1. Identify YOUR changes
- Recall every file you edited, created, or wrote during **this session only**.
- Run `git status` and cross-reference: only consider files that **you touched** in this session.
- Show me two lists:
    - **Files from this session** (will be staged)
    - **Other changed files** (will be left alone for other sessions)
- **Shared files:** If any file appears in both lists (i.e., you touched it AND it has changes from another session), flag it clearly. Run `git diff <file>` and identify whether the diff contains changes beyond what you made. Warn me so I can decide how to handle it.
- Wait for my confirmation before proceeding.

### 2. Pull & resolve conflicts
- `git stash -- <your files>` to save only your session's uncommitted changes.
- `git pull` to get latest commits from other sessions.
- `git stash pop` to reapply your changes.
- If there are conflicts, resolve them.

### 3. Test (Coverage Gate)
- Run the full test suite with coverage: `<TEST_COMMAND>`
- **All tests must pass** before proceeding. Fix any failures first.
- Check coverage for **files you changed this session**:
    1. Look up each module you modified in the coverage report.
    2. **Changed-file gate:** Every module you touched must have **≥50% coverage**, except for modules matching `<COVERAGE_EXEMPT_GLOB>` (template/view-heavy files). Any extracted helper/logic functions should still be tested.
    3. If a module you changed is below 50%, write tests for it — prioritize the public functions you added or modified, then happy-path tests, then edge cases.
    4. Re-run `<TEST_COMMAND>` and iterate until your changed modules meet the gate.
- **Overall threshold:** The project's `<COVERAGE_CONFIG_HINT>` threshold is the floor — do not let overall coverage drop below it. If your changes add significant untested code that lowers overall coverage below the threshold, write tests to compensate.
- **Do NOT just create test files — you must run the tests and confirm they pass.**

### 4. Stage & commit
- **Snapshot check:** Right before staging, re-read each file you plan to commit and verify the contents match what you expect (i.e., only your changes, no partial edits from another session mid-write). If a file has unexpected content, stop and warn me — another session may be actively editing it.
- Stage **only the files from this session** by name — do NOT use `git add -A` or `git add .`
- Check for ignored files: `git ls-files --others --ignored --exclude-standard`
- **Commit with a descriptive message for this session's specific feature.**

### 5. Push
- **Push to remote.** If push is rejected, run `git pull --rebase && git push` and retry.
- If no PR exists for this branch, create a **draft** PR against `main` with:
    - Title: use the branch name as-is (e.g. `feat: <user_name>-current-working-branch-1`)
    - Body: "Work in progress"
    - `gh pr create --draft --title "<branch-name>" --body "Work in progress"`
- If a PR already exists, confirm it's updated.
- Run `git status` to show remaining uncommitted changes (from other sessions).
