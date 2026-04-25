# Branch Protection — `main`

GitHub branch protection rules live in repo settings, not in code. They must be applied once per repo by someone with admin rights. This doc tells you exactly what to enable and why.

## Why

Claude Code running in `--dangerously-skip-permissions` mode can technically run `git push --force` or merge PRs without review. The `.claude/settings.json` deny list blocks most direct damage, but the last line of defense is **server-side branch protection**: GitHub refuses unsafe operations regardless of what the client attempts. This is especially important for junior engineers who are vibe-coding via Claude and may not notice an unsafe git operation.

## What to enable

**Settings → Branches → Add branch protection rule → Branch name pattern: `main`**

| Setting | Value | Why |
|---|---|---|
| Require a pull request before merging | ✅ | No direct pushes to `main` |
| — Require approvals | **1** minimum | At least one human review |
| — Dismiss stale approvals on new commits | ✅ | Prevent sneak-ins after approval |
| — Require review from Code Owners | ✅ (if `CODEOWNERS` exists) | Route reviews correctly |
| Require status checks to pass | ✅ | CI must be green |
| — Require branches to be up to date | ✅ | No merging against stale base |
| — Status checks: **`gitleaks`** | ✅ required | From `.github/workflows/secret-scan.yml` |
| — Status checks: **`verify`** | ✅ required | From `.github/workflows/claude-settings-check.yml` |
| Require conversation resolution before merging | ✅ | No unresolved review threads |
| Require signed commits | Optional (strong) | Tamper-evident history |
| Require linear history | Optional | Cleaner log |
| Do not allow bypassing the above | ✅ | Applies to admins too |
| Restrict who can push to matching branches | ✅ (empty list) | Nobody pushes directly |
| Allow force pushes | ❌ **off** | The whole point |
| Allow deletions | ❌ **off** | `main` is not deletable |

## Apply via `gh` CLI

Requires `gh auth login` as a repo admin. The `verify` and `gitleaks` job names must match those defined in the workflow files.

```bash
OWNER=<owner>
REPO=<repo>

gh api -X PUT "repos/$OWNER/$REPO/branches/main/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["gitleaks", "verify"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "required_linear_history": false
}
JSON
```

If `require_code_owner_reviews` should be `true`, toggle it in the JSON above.

## What junior engineers should know

If Claude Code asks you to force-push to `main`, or tries to merge a PR without review, **stop**. Branch protection will block the push at GitHub's side, but the fact that Claude is proposing it means something has gone sideways. Share the session transcript with a senior engineer before retrying.

If you accidentally commit a secret:

1. **Rotate the secret first.** Assume it is public the moment it hits GitHub — even if you delete the commit seconds later.
2. Ask for help before rewriting history. `git filter-branch` / `git filter-repo` on a shared branch is how people lose work.
3. Open an issue labeled `security` so the team can audit access logs.
