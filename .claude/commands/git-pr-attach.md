## Attach to PR Worktree

Attach the current Claude session to an existing PR's worktree so that all subsequent work happens in the correct branch/directory.

**Usage:**
- `/git-pr-attach <pr-number>` — attach to a specific PR (e.g. `/git-pr-attach 127`).
- `/git-pr-attach` — no arg: list all open PRs in the repo, mark which already have local worktrees, and ask the user to pick one. Then proceed as if that number had been passed.

Bash `cd` does not persist between tool calls in Claude, so "attaching" means: (1) resolve the PR to its branch, (2) resolve the branch to its worktree path, and (3) commit to using that absolute path as the working directory for the remainder of the session.

### 0. No-arg picker (skip if a PR number was provided)
- List open PRs: `gh pr list --state open --json number,headRefName,title,isDraft,author --jq 'sort_by(.number)'`
- List existing worktrees once: `git worktree list --porcelain`. Build a set of branches that have a worktree by parsing `branch refs/heads/<name>` lines.
- Render the candidates as a numbered list. For each PR show:
    - PR number, title, draft marker, author login
    - Branch name
    - **Worktree:** `<absolute-path>` if the branch has one, otherwise `none`
- **Empty case** (no open PRs): stop and tell the user there are no open PRs to attach to; suggest `/git-pr-new` if they want to start one. Do not auto-run it.
- **Single candidate:** still show it and ask for confirmation — do not auto-pick. The whole point of the no-arg form is explicit selection.
- **Multiple candidates:** ask the user which number to attach to. Once they answer, set `<pr-number>` to that PR's number and continue with step 1 below.

### 1. Resolve PR → branch
- Run: `gh pr view <pr-number> --json number,headRefName,state,title,url,isDraft,baseRefName,headRepositoryOwner,headRepository`
- Extract:
    - `headRefName` — the PR branch (required).
    - `state` — `OPEN`, `CLOSED`, or `MERGED`.
    - `title`, `url`, `isDraft`, `baseRefName` — for the summary.
- If `gh pr view` errors (PR not found, wrong repo): stop and report the error. Do not guess.
- **Do not prompt the user yet based on state** — gather worktree state first (step 3), then decide in step 4.

### 2. Resolve branch → worktree
- List worktrees in porcelain format: `git worktree list --porcelain`
- Parse the output to find the entry whose `branch refs/heads/<name>` matches `headRefName`.
- **If a worktree is found:** capture its absolute path. Skip to step 3.
- **If no worktree is found:**
    - Check whether the branch exists locally or on the remote:
        - Local: `git show-ref --verify --quiet refs/heads/<branch>`
        - Remote: `git ls-remote --exit-code --heads origin <branch>`
    - Propose a worktree path as a sibling to the current repo: `../<repo-name>-pr-<pr-number>`. If that path already exists, append `-a`, `-b`, … until free.
    - **Always ask the user to confirm** before creating — this is a filesystem side-effect regardless of PR state. On confirmation:
        - If the branch exists locally: `git worktree add <worktree-path> <branch>`
        - If only on remote: `git fetch origin <branch>` then `git worktree add <worktree-path> <branch>` (Git will set up tracking automatically from `origin/<branch>`).
        - If the branch doesn't exist at all: stop and report — `/git-pr-attach` is for existing PRs, not for creating new ones. Point the user at `/git-pr-new`.
    - Initialize submodules if the repo uses them: if `.gitmodules` exists at the worktree root, run `git -C <worktree-path> submodule update --init --recursive`.

### 3. Verify the worktree state (always run before asking anything else)
Run in parallel from the worktree path:

- `git -C <worktree-path> rev-parse --abbrev-ref HEAD` — confirm the branch matches `headRefName`.
- `git -C <worktree-path> status --short` — surface any uncommitted changes.
- `git -C <worktree-path> log --oneline -5` — recent commits, so the user can sanity-check they're looking at the right work.

If HEAD does not match the PR branch (e.g. someone detached it), stop and report — do not silently switch branches in a worktree that may have in-progress work.

### 4. Decide based on PR state — with the full summary visible
Always present the same summary block first (so the user or you can make an informed call in one glance):

- **PR:** `#<number> — <title>` (`<state>`, `<url>`)
- **Branch:** `<headRefName>` → base `<baseRefName>`
- **Worktree:** `<absolute-worktree-path>`
- **Working tree status:** clean / `<n>` uncommitted files (list them)
- **Recent commits:** the 5-line `git log` output

Then branch on `state`:

- **`OPEN`:** proceed directly to step 5. No confirmation needed — this is the common path.
- **`MERGED`:** proceed to step 5 with a one-line note: *"PR #\<n\> is merged. Attaching to the local worktree for follow-up/cleanup work — note that new commits on this branch will not reopen the PR."* Do not prompt.
- **`CLOSED`** (unmerged): **stop and ask explicitly.** Closed-unmerged is more often a typo or abandoned branch than a deliberate attach target. Use the summary above so the user sees uncommitted work and recent commits before answering. Only proceed to step 5 after the user confirms.

### 5. Commit to the worktree for the rest of the session
Explicitly state to the user and to yourself (Claude):

> Attached to PR #\<n\>. All subsequent file edits, reads, and shell commands in this session must use absolute paths rooted at `<worktree-path>`. For git operations, use `git -C <worktree-path> …` (or absolute `--git-dir` / `--work-tree`) — do **not** rely on `cd`, since Bash state does not persist between tool calls.

### Notes
- Do not modify the worktree's branch, checkout state, or uncommitted changes as a side effect of attaching.
- Do not delete or move the worktree.
- If the user later wants to switch to a different PR, they should run `/git-pr-attach <other-number>` again — this command is idempotent.
