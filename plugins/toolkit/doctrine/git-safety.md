# Git Safety

Do not run `git commit`, `git push`, `git merge`, branch operations, or open PRs.
Suggest the branch name and commit message; the human handles git.

The `## Flows` section is the single exception to the rules in this file.

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

Run `git status -sb` in the target repo before the first edit. This applies to vendored module checkouts, which sit at a detached HEAD on the installed tag. If HEAD is `main`, `master`, or a detached tag, stop, suggest a branch named `<type>/<TICKET>-<slug>`, or `<type>/<slug>` when there is no ticket, and wait for the human to create it. Determine the base branch with `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, or the glab equivalent), never a guessed list. On a branch other than the base, detect merged work with `git merge-base --is-ancestor HEAD origin/<base>`: exit 0 means the branch tip is already in the base, so stop and ask for a fresh branch. A branch with no commits beyond the base gives the same exit 0, so when the branch was just cut the toolkit asks whether it is merged work or a fresh branch, and stops only on merged. Do not edit until the branch exists or the merge question is resolved.

## Commit handoff

Every commit, merge, tag, push, or branch-cut instruction opens with three header lines: `Repo:` (the remote path, plus the composer package name for a module), `Branch:`, and `Scope:` (one line naming the change and the file count).

A commit handoff follows the header with a paste-ready block: `cd "<absolute dir>"` on its own line, then `git add -- "<path one>" "<path two>" && git commit -F - <<'EOF'`, the message, and the closing `EOF`. Double-quote each path and put `--` before the pathspec. Never `git add -A`: it stages work the Scope line does not name. The harness suggests a `Co-Authored-By` trailer in its default instructions. This doctrine overrides that suggestion: never append one.

    Repo: gitlab.example.com/group/repo (acme/module-example)
    Branch: fix/PROJ-123-timeout-retry
    Scope: retry once on request timeout, 3 files

```bash
cd "/absolute/path/to/repo"
git add -- "app/code/Acme/Example/Model/Client.php" "app/code/Acme/Example/etc/config.xml" "tests/ClientTest.php" && git commit -F - <<'EOF'
fix(example): retry once on request timeout

Body in the repo's observed convention.
EOF
```

A push, tag, switch, or merge handoff follows the same header with its own paste-ready block: `cd "<absolute dir>"` on its own line, then the single command (`git push`, `git tag`, `git switch -c <branch>`, or `git merge <branch>`).

## Authorization covers one operation

One instruction to commit, push, merge, or tag covers that one operation. The next operation needs its own instruction, in the same session or a later one.

## Flows

Inside a flow with a recorded `push` or `release` answer, this section overrides three rules above: the opening rule that the human handles git, the branch check rule to stop and wait for the human to create the branch, and the rule that authorization covers one operation. A flow is a skill whose name ends in `-flow`, driven by a Workflow script under `workflows/`.

The first flow that runs in a session asks one question through AskUserQuestion before anything else runs: "Do I have permission to run git commands on your behalf for every flow in this session?" The flow records the answer at `<scratchpad>/flow-git-permission` as `none`, `push`, or `release`, and the answer holds for every flow run in that session. A later flow in the same session reads the file and never re-asks, so a `push` or `release` answer given to the plan flow also covers a later flow in that session that runs git. A missing, empty, or unrecognised file reads as `none`.

- `none` keeps this doctrine as written.
- `push` permits commit, branch cut, push, and MR or PR creation. Under `push` the ship flow may also make bounded fix commits during its pipeline and thread stages, and reply to and resolve the bot threads it fixed.
- `release` adds merge and tag. Under `release` the ship flow runs `git fetch origin <default>` before it tags.

No answer permits a deploy, and `release` never means deploy. The plan flow runs no git under any answer. The execute flow never mutates git state under any answer, and its agents run only read-only git in the repo: `git status`, `git diff`, `git log`, `git ls-files`, `git branch --show-current`, `git remote get-url`, `git symbolic-ref` with one ref argument, and `git merge-base --is-ancestor`. A `-c core.quotePath=false` prefix on one of these commands keeps it read-only. The ship flow is the only flow that mutates git, and only under `push` or `release`. The hooks apply under every answer, including the `block-dangerous-commands` hook and its protected-branch guard, and a flow never bypasses them. Outside a flow, and in every ad-hoc session, this doctrine applies unchanged and the human runs git. A resumed session keeps its scratchpad and so keeps its answer. A new session asks again.

## Branch naming

When suggesting branch names, use lowercase kebab-case with a slash-separated scope prefix.

Examples:
- `runtime/add-healthz-endpoint`
- `docs/update-phase-2-plan`
- `fix/resolver-null-check`

Every planning session must include a suggested branch name.
