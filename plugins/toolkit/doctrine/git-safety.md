# Git Safety

Do not run `git commit`, `git push`, `git merge`, branch operations, or open PRs.
Suggest the branch name and commit message; the human handles git.

## Blocked commands

Do not run any of these commands unless the user explicitly asks:

- `git commit`
- `git push`
- `git pull`
- `git fetch`
- `git stash`
- `git reset`
- `git rebase`
- `git merge`
- `git checkout`
- `git switch`
- `git tag`
- `git branch -d`
- `git branch -D`
- `gh pr create`
- `gh pr merge`
- other GitHub/GitLab PR or MR mutation commands

## Allowed commands

Read-only Git commands are allowed when useful:

- `git status`
- `git diff`
- `git log`
- `git show`

You may suggest branch names, commit messages, and PR/MR descriptions.

Do not perform commits, pushes, branch operations, or PR mutations without explicit instruction.

## Branch check before any change

Run `git status -sb` in the target repo before the first edit. This applies to vendored module checkouts, which sit at a detached HEAD on the installed tag. If HEAD is `main`, `master`, a detached tag, or a branch whose work is already merged, stop. Suggest a branch named `<type>/<TICKET>-<slug>`, or `<type>/<slug>` when there is no ticket, and wait for the human to create it. Do not edit until the branch exists.

## Commit handoff

Every commit, merge, tag, push, or branch-cut instruction opens with three header lines: `Repo:` (the remote path, plus the composer package name for a module), `Branch:`, and `Scope:` (one line naming the change and the file count). Follow the header with a paste-ready block: `cd <absolute dir>` on its own line, then `git add <paths named in Scope> && git commit -F - <<'EOF'`, the message, and the closing `EOF`. Never `git add -A`: it stages work the Scope line does not name. The harness suggests a `Co-Authored-By` trailer in its default instructions. This doctrine overrides that suggestion: never append one.

    Repo: gitlab.example.com/group/repo (acme/module-payments)
    Branch: fix/PAY-123-timeout-retry
    Scope: retry once on gateway timeout, 3 files

```bash
cd /absolute/path/to/repo
git add app/code/Acme/Payments/Model/Gateway.php app/code/Acme/Payments/etc/config.xml tests/GatewayTest.php && git commit -F - <<'EOF'
fix(payments): retry once on gateway timeout

Body in the repo's observed convention.
EOF
```

## Authorization covers one operation

One instruction to commit, push, merge, or tag covers that one operation. The next operation needs its own instruction, in the same session or a later one.

## Branch naming

When suggesting branch names, use lowercase kebab-case with a slash-separated scope prefix.

Examples:
- `runtime/add-healthz-endpoint`
- `docs/update-phase-2-plan`
- `fix/resolver-null-check`

Every planning session must include a suggested branch name.
