## Merge PR & Clean Up

Merge a reviewed-and-approved PR into its base branch and clean up the worktree. Run this **after** `/git-pr-end` has marked the PR ready and review/CI have signed off — this command does not run tests or rename branches.

### Worktree preamble
This command operates on the worktree it is invoked from. If invoked from the main repo checkout (not a worktree), stop and tell the user to `/git-pr-attach <pr-number>` first — the cleanup steps need a known worktree path to remove.

Capture the worktree path, branch name, and main-repo path up front:
- `<worktree-path>` — current working directory (verify via `git rev-parse --show-toplevel`).
- `<branch>` — `git rev-parse --abbrev-ref HEAD`.
- `<main-repo-path>` — `git worktree list --porcelain` and find the entry whose branch is `main` (or the repo's default). The cleanup commands run from there because you can't remove the worktree you're standing in.

### Phase 1: Preflight (all checks must pass)
Run in parallel:

- `gh pr view --json number,title,state,isDraft,mergeable,mergeStateStatus,baseRefName,url,reviewDecision` — capture PR metadata.
- `git -C <worktree-path> status --short` — must be empty (no uncommitted/untracked files).
- `git -C <worktree-path> log origin/<branch>..HEAD --oneline` — must be empty (no unpushed commits).

Then validate:

- **PR exists** for the current branch. If not, stop.
- **PR is OPEN** and **not draft**. If draft, stop and remind the user to run `/git-pr-end` first.
- **`mergeable` is `MERGEABLE`** and **`mergeStateStatus` is `CLEAN`**. If `BLOCKED`, `BEHIND`, `DIRTY`, or `UNSTABLE`, stop and report the reason — typical fixes are pulling base, resolving conflicts, or waiting on CI.
- **`reviewDecision`** — if branch protection requires review and this is `REVIEW_REQUIRED` or `CHANGES_REQUESTED`, stop. `APPROVED` or empty (no required reviewers) is fine.
- **Working tree clean** and **no unpushed commits** (from the parallel checks above).

If any check fails, present the failing items as a list and stop. Do not offer to bypass.

### Phase 2: Confirm & merge
Show the user a summary block and ask explicitly before merging:

- **PR:** `#<n> — <title>` (`<url>`)
- **Branch:** `<branch>` → `<baseRefName>`
- **Worktree:** `<worktree-path>` (will be removed)
- **Merge method:** `--merge --delete-branch` (creates a merge commit; deletes the remote branch)

Wait for explicit confirmation. Then:

- `gh pr merge <pr-number> --merge --delete-branch`
- If the merge fails (e.g. someone pushed to base in the meantime), stop and report — do not retry blindly. The user may need to pull base into the branch and re-run.

### Phase 3: Cleanup
Run from the main repo checkout (use `git -C <main-repo-path>` — do not `cd`):

- `git -C <main-repo-path> worktree remove <worktree-path>` — removes the worktree directory and its admin entry.
    - If this fails because of leftover untracked files, list them and ask before using `--force`.
- `git -C <main-repo-path> fetch --prune origin` — drops the now-deleted remote-tracking ref.
- `git -C <main-repo-path> branch -d <branch>` — deletes the local branch (safe delete; will refuse if unmerged, which shouldn't happen post-merge but is a useful safety net).
- `git -C <main-repo-path> checkout main && git -C <main-repo-path> pull origin main` — bring main up to date so the next `/git-pr-new` branches off the merged commit.

### Phase 4: Detach the session
Tell the user (and yourself) explicitly:

> PR #\<n\> merged. Worktree `<worktree-path>` removed. This session is no longer attached to a worktree — subsequent work should start with `/git-pr-new` or `/git-pr-attach`.

Do not silently keep operating against the deleted worktree path.
