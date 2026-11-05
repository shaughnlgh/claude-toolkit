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

Inside a flow whose recorded ceiling is `mr` or `merge`, this section overrides three rules above: the opening rule that the human handles git, the branch check rule to stop and wait for the human to create the branch, and the rule that authorization covers one operation. A flow is a skill whose name ends in `-flow`, driven by a Workflow script under `workflows/`.

The ceiling is the `ceiling` key on the plan note, or the `ceiling` line of `<scratchpad>/flow-run-options` when the note lacks it and that file's `plan:` line names the same plan. The `## Run options` section of the plan-guide skill (`skills/plan-guide/SKILL.md`) defines the keys, the question set, the reading rule, and the cache. A flow asks only for the keys neither source holds, so one answer holds for the plan and for every flow in the session, and a later session reads the note. A missing, empty, or unrecognised ceiling reads as `none`.

- `none` keeps this doctrine as written.
- `mr` permits commit, branch cut, push, and MR or PR creation. Under `mr` the ship flow may also make bounded fix commits during its pipeline and thread stages, and reply to and resolve the bot threads it fixed.
- `merge` adds the merge. With `tag_merge: true` on the note it also adds the tag, and the ship flow runs `git fetch origin <default>` before it tags.

No ceiling permits a deploy. The plan flow runs no git under any ceiling. The execute flow never mutates git state under any ceiling apart from opening a worktree at the user's seat answer, through EnterWorktree under any ceiling, or through `git fetch` and `git worktree add` for an existing branch only under `mr` or `merge` and as paste-ready commands under `none`. Apart from those two commands, its agents run only read-only git in the repo: `git status`, `git diff`, `git log`, `git ls-files`, `git branch --show-current`, `git branch --list`, `git worktree list`, `git ls-remote --heads`, `git remote get-url`, `git symbolic-ref` with one ref argument, `git merge-base --is-ancestor`, `git rev-parse` in the `--path-format=absolute --git-common-dir` form, and `git show` with one `<ref>:<path>` argument. A `-c core.quotePath=false` prefix on one of these commands keeps it read-only. Apart from that worktree, the ship flow is the only flow that mutates git, and only under `mr` or `merge`. The hooks apply under every ceiling, including the `block-dangerous-commands` hook and its protected-branch guard, and a flow never bypasses them. Outside a flow, and in every ad-hoc session, this doctrine applies unchanged and the human runs git. A resumed session keeps its scratchpad and so keeps the cache. A new session reads the plan note.

## Command shape under the permission classifier

Auto mode routes every command no allow rule matches through a classifier. The classifier reads the user's typed messages, the tool calls, and CLAUDE.md. It never reads a tool result, so an AskUserQuestion answer is invisible to it, and it never reads the plan note, the run options cache, or auto-memory. A recorded `mr` or `merge` ceiling therefore authorises the flow, not the classifier. These rules keep each mutation legible to it and to the allow rules.

- Each commit, push, branch cut, and MR or PR creation runs as its own Bash call. The call text begins with the git, glab, or gh command, after at most a `cd "<absolute dir>" &&` prefix, so a prefix allow rule such as `Bash(git push:*)` can match it. A repo flag (`-C`, `-R`) follows the subcommand.
- An MR or PR opens with `glab mr create` or `gh pr create`, with the title and body passed through quoted heredocs or a body file. Never open one through a raw API call (`glab api -X POST`, `gh api -X POST`), and never wrap the command in an interpreter heredoc (`python3 - <<'EOF'`, `jq ... | glab api`): the classifier reads that shape as a generic external write.
- A classifier denial arrives as a tool result that names a reason category in brackets. The report states that category on its own line before the handoff block, and when the category points at an external system or an untrusted remote, says that the global autoMode environment may not name this repo's remote.

## Branch naming

When suggesting branch names, use lowercase kebab-case with a slash-separated scope prefix.

Examples:
- `runtime/add-healthz-endpoint`
- `docs/update-phase-2-plan`
- `fix/resolver-null-check`

Every planning session must include a suggested branch name.
