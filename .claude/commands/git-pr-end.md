## Close off PR for review

### Configure for your project
Replace these placeholders when you adopt this command in a new repo (or override in a project `.claude/commands/git-pr-end.md`):

- `<TEST_COMMAND>` — full test command. Same value as `/git-pr-push`.
- `<COVERAGE_EXEMPT_GLOB>` — template-heavy module-name pattern. Same value as `/git-pr-push`.
- `<COVERAGE_CONFIG_HINT>` — where overall coverage threshold is configured. Same value as `/git-pr-push`.

### Worktree preamble
This command operates on the working directory it is invoked from — normally the worktree created by `/git-pr-new` or attached via `/git-pr-attach`. All `git` commands below run against that worktree's branch. Do not `git checkout` a different branch or `cd` out of the worktree (Bash `cd` doesn't persist between tool calls anyway). Use absolute paths or `git -C <worktree-path> …` when needed.

After the PR is marked ready (end of Phase 2), the worktree can stay — it does no harm and may be useful for follow-up review fixes. Once the PR merges, clean up with `git worktree remove <worktree-path>` from the main repo checkout.

### Phase 1: Final Commit & Push (same as /git-pr-push)

#### 1. Identify YOUR changes
- Recall every file you edited, created, or wrote during **this session only**.
- Run `git status` and cross-reference: only consider files that **you touched** in this session.
- Show me two lists:
    - **Files from this session** (will be staged)
    - **Other changed files** (will be left alone for other sessions)
- **Shared files:** If any file appears in both lists (i.e., you touched it AND it has changes from another session), flag it clearly. Run `git diff <file>` and identify whether the diff contains changes beyond what you made. Warn me so I can decide how to handle it.
- Wait for my confirmation before proceeding.

#### 2. Pull & resolve conflicts
- `git stash -- <your files>` to save only your session's uncommitted changes.
- `git pull` to get latest commits from other sessions.
- `git stash pop` to reapply your changes.
- If there are conflicts, resolve them.

#### 3. Test (Coverage Gate)
- Run the full test suite with coverage: `<TEST_COMMAND>`
- **All tests must pass** before proceeding. Fix any failures first.
- Check coverage for **files you changed this session**:
    1. Look up each module you modified in the coverage report.
    2. **Changed-file gate:** Every module you touched must have **≥50% coverage**, except for modules matching `<COVERAGE_EXEMPT_GLOB>` (template/view-heavy files). Any extracted helper/logic functions should still be tested.
    3. If a module you changed is below 50%, write tests for it — prioritize the public functions you added or modified, then happy-path tests, then edge cases.
    4. Re-run `<TEST_COMMAND>` and iterate until your changed modules meet the gate.
- **Overall threshold:** The project's `<COVERAGE_CONFIG_HINT>` threshold is the floor — do not let overall coverage drop below it. If your changes add significant untested code that lowers overall coverage below the threshold, write tests to compensate.
- **Do NOT just create test files — you must run the tests and confirm they pass.**

#### 4. Stage & commit
- **Snapshot check:** Right before staging, re-read each file you plan to commit and verify the contents match what you expect (i.e., only your changes, no partial edits from another session mid-write). If a file has unexpected content, stop and warn me — another session may be actively editing it.
- Stage **only the files from this session** by name — do NOT use `git add -A` or `git add .`
- Check for ignored files: `git ls-files --others --ignored --exclude-standard`
- **Commit with a descriptive message for this session's specific feature.**

#### 5. Push
- **Push to remote.** If push is rejected, run `git pull --rebase && git push` and retry.
- If no PR exists for this branch, create a **draft** PR against `main` with:
    - Title: use the branch name as-is (e.g. `feat: <user_name>-current-working-branch-1`)
    - Body: "Work in progress"
    - `gh pr create --draft --title "<branch-name>" --body "Work in progress"`
- If a PR already exists, confirm it's updated.
- Run `git status` to show remaining uncommitted changes (from other sessions).

### Phase 2: Finalize PR

- **Determine the base for this PR:**
    - Get the merge-base commit: `git merge-base origin/main HEAD`
    - If the merge-base equals `git rev-parse origin/main` (i.e. branch was created from main tip), the base is **main**.
    - Otherwise, find the PR this branch was built on:
      `gh pr list --state all --author @me --json number,headRefName,mergeCommit,state --jq '[.[] | select(.headRefName != "<current-branch>")] | sort_by(.number) | last'`
      Use the highest-numbered PR that is an ancestor of this branch as the base PR.
    - Set the **base label**:
      - If based on main: `base-main`
      - If based on a PR: `base #<number>`
- **Rename the branch and PR to reflect the actual work done:**
    - Review the commits in this batch: `git log origin/main..HEAD --oneline`
    - Create a descriptive name based on the work (e.g. `feat/dark-theme-and-resize-pane`)
    - Rename the branch: `git branch -m <new-descriptive-name>`
    - Push the renamed branch: `git push origin -u <new-descriptive-name>`
    - Delete the old branch from remote: `git push origin --delete <old-branch-name>`
    - Update the PR title using the base label: `gh pr edit --title "feat: <base label>: <descriptive title>"`
      - Examples: `feat: base-main: dark theme and resize pane` or `feat: base #42: agent config improvements`
    - Update the PR body with a summary of all commits/features as bullets
- Check all terminals have committed and pushed their work:
    - `git fetch origin`
    - `git status` — confirm no uncommitted changes in this terminal
    - `git log origin/<branch>..HEAD` — confirm no unpushed commits
- **Ensure clean working tree** (MANDATORY — do not skip):
    - Run `git status` and check for ANY modified, staged, or untracked files (excluding ignored files like `node_modules/` and submodule-only noise).
    - If uncommitted changes exist:
        1. Ask me: "These files have uncommitted changes: [list]. Should I commit them to this PR branch, or discard them?"
        2. If commit: stage, commit with a descriptive message, and push.
        3. If discard: `git checkout -- <files>` for tracked files, `rm <files>` for untracked.
    - **Do NOT proceed until `git status` shows a clean working tree** (only ignored/submodule entries allowed).
    - Run `git status` one final time to confirm.
- Confirm the PR is up to date:
    `gh pr view --web` — open PR in browser to visually confirm all commits are listed
- Mark PR as ready for review:
    `gh pr ready`
- Check CI status immediately after marking ready:
    `gh pr checks <pr-number>` — report each check name and its status (pass/fail/pending).
- End with a status block that clearly distinguishes what is done from what is still needed:

```
PR #<n> marked ready: <url>

CI checks:
  ✅ / ❌ / ⏳  <check-name>  (<link>)
  ...

Next steps:
  ⏳ Wait for CI to pass          (re-run /git-pr-merge once green)
  👀 Awaiting review approval     (if required by branch protection)

Worktree cleanup (after merge):
  git worktree remove <worktree-path>   # run from main repo
```

  - Use ✅ for passing, ❌ for failing, ⏳ for pending/running checks.
  - If all checks are green and no review is required, say so explicitly: "Ready to merge — run /git-pr-merge."
  - Never say "PR is ready" without also showing the CI status.
