## New PR
Create the next working branch in a **new git worktree** AND draft PR, based on your latest open PR (not main).

### Resolve `{user_name}` (used in branch naming below)
Before anything else, resolve `{user_name}` via the first source that yields a value:
1. `$CLAUDE_USER_NAME` env var, if set.
2. Else: local-part of `git config user.email` (before `@`), lowercased. E.g. `peter@interactor.com` → `peter`.
3. Else: first whitespace-separated token of `git config user.name`, lowercased.

If none yield a value, stop and ask me. Use the resolved value everywhere `{user_name}` appears below.

### Pick the starting point (no checkout needed — worktree model)
- Check for open PRs: `gh pr list --state open --author @me --json number,headRefName,createdAt --jq 'sort_by(.createdAt) | last | .headRefName'`
- If an open PR exists, the start point is `origin/<that-branch>`. Refresh it: `git fetch origin <that-branch>`.
- If no open PRs exist, the start point is `origin/main`. Refresh it: `git fetch origin main`.
- Do **not** `git checkout` the start-point branch in the main repo — if it already has a worktree, that would error; and `git worktree add` can take any ref as its start-point directly.

### Branch naming
- Check existing local and remote branches matching `feat/{user_name}-current-working-branch*` (use `git branch --list` and `git branch -r --list 'origin/feat/{user_name}-current-working-branch*'`).
- If **none exist**: use `feat/{user_name}-current-working-branch` (no number).
- If **any exist**: find the highest number (unnumbered counts as 1) and increment. E.g. if `feat/{user_name}-current-working-branch` exists, next is `feat/{user_name}-current-working-branch-2`.

### Worktree path
- Place the worktree as a sibling to the current repo: `../<repo-name>-cwb-<N>` where `<N>` is the numeric suffix of the branch (unnumbered → `cwb-1`). E.g. for `feat/{user_name}-current-working-branch-3` in a repo called `my-app`, use `../my-app-cwb-3`. (`cwb` = "current working branch"; short suffix keeps paths readable.)
- If the path already exists, append `-a`, `-b`, … until free.

### Create the worktree and branch in one step
- `git worktree add -b <new-branch> <worktree-path> <start-point>`
    - `<start-point>` is either `origin/<latest-open-pr-branch>` or `origin/main` from the step above.
- From now on, **all subsequent commands must run inside the worktree path** (use absolute paths in Bash calls; do not rely on persistent `cd`).

### Initialize submodules in the worktree (if the repo uses them)
- Check for submodules: if `.gitmodules` exists in the worktree, run `git -C <worktree-path> submodule update --init --recursive`.

### Starter commit, push, draft PR (all from the worktree)
- `git -C <worktree-path> commit --allow-empty -m "chore: start working branch"`
- `git -C <worktree-path> push -u origin <new-branch>`
- Create a draft PR (run `gh` with `-R <owner>/<repo>` or inside the worktree):
    ```
    gh pr create --draft --title "feat: <branch-name>" --body "$(cat <<'EOF'
    ## Active Working PR

    This is the current working branch. Previous PRs with descriptive names should be reviewed and merged first.
    EOF
    )"
    ```

### After creation
- Report the worktree path and PR URL to the user.
- Remind the user that subsequent work in this session happens in the worktree path — Claude should use absolute paths rooted at the worktree when editing files or running commands, since Bash `cd` does not persist between tool calls.
- Do not remove the worktree automatically. When the PR is merged/closed, the user can clean it up with `git worktree remove <worktree-path>`.
