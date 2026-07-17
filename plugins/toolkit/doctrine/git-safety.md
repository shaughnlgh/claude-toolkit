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

## Branch naming

When suggesting branch names, use lowercase kebab-case with a slash-separated scope prefix.

Examples:
- `runtime/add-healthz-endpoint`
- `docs/update-phase-2-plan`
- `fix/resolver-null-check`

Every planning session must include a suggested branch name.
