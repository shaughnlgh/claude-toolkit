# Git Safety

By default, create the work branch and run no other git change: no `git commit`, `git push`, `git merge`, other branch operation, or PR.
Suggest the commit message; the human handles the rest of git.

The ceiling the human picks widens this default, as the `## Flows` section defines. That section is the single exception to the rules in this file.

## Blocked commands

Do not run any of these commands unless the user explicitly asks, apart from `git switch -c` to create the work branch:

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

You may suggest branch names, commit messages, and PR/MR descriptions. Wherever HEAD is, settle the ticket as the Branch check section below does before you create a branch for work with no recorded ticket, reading only that work's own plan note, so a side fix found on a feature branch also gets the ticket question.

Do not perform commits, pushes, PR mutations, or any branch operation other than creating the work branch without explicit instruction.

## Branch check before any change

Run `git status -sb` in the target repo before the first edit. This applies to vendored module checkouts, which sit at a detached HEAD on the installed tag. If HEAD is `main`, `master`, or a detached tag, create a branch named `<type>/<TICKET>-<slug>` before the first edit. When the plan note holds a `branch` value, use that branch. Otherwise the ticket is the plan note's `ticket` value when the note holds one. With no plan note, it is the `ticket:` value of `<scratchpad>/flow-run-options` when that file's `plan:` line is blank and its `ticket_work:` line equals the `<slug>` of the work at hand, or else the `ticket:` value of `<scratchpad>/side-fix-ticket` when its `ticket_work:` line equals that `<slug>`. Else ask the ticket question in the `plan-guide` skill's Run options section once and record the answer as its Ticket subsection says. The execute and ship flows never ask the ticket question, because they take the branch from the plan note. Only after the user chose to go without a ticket, recorded as `none`, does the branch take the no-ticket form: `<type>/<slug>`, or the no-ticket token the project's rules name in the ticket's place. Determine the base branch with `git symbolic-ref --short refs/remotes/origin/HEAD` (fallback `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, or the glab equivalent), never a guessed list. On a branch other than the base, detect merged work with `git merge-base --is-ancestor HEAD origin/<base>`: exit 0 means the branch tip is already in the base, so stop and ask for a fresh branch. A branch with no commits beyond the base gives the same exit 0. Outside a flow, ask whether it is merged work or a fresh branch, and stop only on merged. The execute flow asks nothing: it stops as merged when the plan note's `mr` key is set and continues as a fresh branch when it is blank. Do not edit until the branch exists or the merged check is settled.

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

Inside a flow whose recorded ceiling is `mr` or `merge`, this section overrides two rules above: the opening rule that the human handles git, and the rule that authorization covers one operation. A flow is a skill whose name ends in `-flow`, driven by a Workflow script under `workflows/`.

Inside a flow, the flow's own skill decides how the work branch is created: the execute flow opens a worktree for it, and where it stops on a default branch it hands the branch command over.

The ceiling is the `ceiling` key on the plan note, or the `ceiling` line of `<scratchpad>/flow-run-options` when the note lacks it and that file's `plan:` line names the same plan. The `## Run options` section of the plan-guide skill (`skills/plan-guide/SKILL.md`) defines the keys, the question set, the reading rule, and the cache. A flow asks only for the keys neither source holds, so one answer holds for the plan and for every flow in the session, and a later session reads the note. A missing, empty, or unrecognised ceiling reads as `none`.

- `none` keeps this doctrine as written.
- `mr` permits commit, branch cut, push, and MR or PR creation. Under `mr` the ship flow may also make bounded fix commits during its pipeline and thread stages, make one fix commit for the findings the execute flow carried to the PR, and reply to and resolve the bot threads it fixed.
- `merge` adds the merge. With `tag_merge: true` on the note it also adds the tag, and the ship flow runs `git fetch origin <default>` before it tags. A ship fix commit merges only when a verifier's read of the commit shows it changed only the plan's paths and no hands-off path. After the merge the ship flow cleans up, each command as its own call with each ref name single-quoted: `git worktree remove` without `--force` on the plan's recorded worktree, `git switch '<default>'` in a clean main checkout only from the plan's branch and only on `seat: free`, `git pull --ff-only origin '<default>'`, `git branch -d '<branch>'` and never `-D`, and `git push origin --delete '<branch>'`. Each delete runs only while the branch sits at the merged head, and the remote delete runs only once the local branch is gone. Asking for the ship flow under `merge` is the request that ExitWorktree with keep requires before the cleanup. On a several-repos note (plan-guide § Repos and modules), the ship flow merges only after every repo's PR or MR was ready, one repo at a time in ship order.

No ceiling permits a deploy. The plan flow runs no git under any ceiling. The execute flow mutates git only as follows.

- Asking for the execute flow is the explicit request that Claude Code's EnterWorktree tool requires, and the request that ExitWorktree requires, which the flow calls only with keep: on the seat route only on a free seat, and after a lead report. When EnterWorktree is absent or refused, the flow stops with a report.
- On a held or dirty seat, and on a free, clean seat whose main checkout sits on a default branch on a run from approved or start-work, as execute-flow section 2a defines, the flow opens a worktree with no question. It does so through EnterWorktree under any ceiling, or through `git fetch` and `git worktree add` for an existing branch under `mr` or `merge`, or through `git worktree add -b` for the note's branch when it does not exist yet.
- The seat run runs under `mr` or `merge`, on a clean tree, with each command as its own call and each ref name single-quoted. It runs `git switch --detach` in the plan's worktree, then `git switch <branch>` in the main checkout, then `git add --` and `git commit` there for its own fixes. Then it runs `git switch <restore point>` in the main checkout, or `git switch --detach <sha>` for a detached restore point, and `git switch <branch>` in the worktree when the worktree HEAD has not moved.
- On a several-repos note (execute-flow section 2b), the flow opens each top-level repo's worktree, and each external module checkout's worktree, through `git fetch` and `git worktree add`, never EnterWorktree. It readies each nested module checkout with Composer's `reinstall --prefer-source`, and moves it to the module's branch with `git fetch origin '<ref>'` and `git switch`. Each of these commands runs as its own call under `mr` or `merge`, and is paste-ready under `none`.
- Under `none`, every one of these commands is a paste-ready handoff and the run stops.

Apart from those commands, the execute flow's agents run only read-only git in the repo: `git status`, `git diff`, `git log`, `git ls-files`, `git branch --show-current`, `git branch --list`, `git worktree list`, `git ls-remote --heads`, `git remote get-url`, `git symbolic-ref` with one ref argument, `git merge-base --is-ancestor`, `git rev-parse` with one ref argument or in the `--path-format=absolute --git-common-dir` form, `git check-ref-format --branch`, and `git show` with one `<ref>:<path>` argument. A `-c core.quotePath=false` prefix on one of these commands keeps it read-only. Apart from those commands, the ship flow is the only flow that mutates git, and only under `mr` or `merge`. The hooks apply under every ceiling, including the `block-dangerous-commands` hook and its protected-branch guard, and a flow never bypasses them. Outside a flow, and in every ad-hoc session, this doctrine applies unchanged. A resumed session keeps its scratchpad and so keeps the cache. A new session reads the plan note.

## Command shape under the permission classifier

Auto mode routes every command no allow rule matches through a classifier. The classifier reads the user's typed messages, the tool calls, and CLAUDE.md. It never reads a tool result, so an AskUserQuestion answer is invisible to it, and it never reads the plan note, the run options cache, or auto-memory. A recorded `mr` or `merge` ceiling therefore authorises the flow, not the classifier. These rules keep each mutation legible to it and to the allow rules.

- Each commit, push, branch cut, and MR or PR creation runs as its own Bash call. The call text begins with the git, glab, or gh command, after at most a `cd "<absolute dir>" &&` prefix, so a prefix allow rule such as `Bash(git push:*)` can match it. A repo flag (`-C`, `-R`) follows the subcommand.
- An MR or PR opens with `glab mr create` or `gh pr create`, with the title and body passed through quoted heredocs or a body file. Never open one through a raw API call (`glab api -X POST`, `gh api -X POST`), and never wrap the command in an interpreter heredoc (`python3 - <<'EOF'`, `jq ... | glab api`): the classifier reads that shape as a generic external write.
- A long-running local process runs through the Bash tool's `run_in_background` and stops through Claude Code's own stop for that task. When that does not fit, it starts in one Bash call as `bash -c 'set -m; <launch command> > <scratchpad>/<name>.log 2>&1 & echo $! > <scratchpad>/<name>.pid'`, because a background child that keeps the tool's output open holds the call until its timeout, and `set -m` makes the recorded PID lead a process group that holds every process the launch forks. It stops with `kill -- -"$(cat <scratchpad>/<name>.pid)"`, the shape the built-in Session-Created Job Cleanup exception covers, and it counts as stopped only when `kill -0 -- -"$(cat <scratchpad>/<name>.pid)"` then fails, because a signal to the leader alone leaves a wrapper's or a `cd ... &&` list's children running. It never stops by pkill, killall, a port, or a PID list read from ps output, because the classifier sees commands and never their output, and a pattern or a port can match a sibling session's run.
- A classifier denial arrives as a tool result that names a reason category in brackets. The report states that category on its own line before the handoff block, and when the category points at an external system or an untrusted remote, says that the global autoMode environment may not name this repo's remote. Merge Without Review clears through the Own PR Merge or Own MR Merge entry that `/toolkit:setup` check 6 offers. Interfere With Workloads clears through the stop shape above while `autoMode.allow` keeps `$defaults`. Self-Modification clears for a `.claude/settings.json`, `.claude/settings.local.json` or `CLAUDE.md` change only when the user's typed message asks for it, so a worker brief never carries such a change the user did not ask for, and under auto mode `/toolkit:setup` writes a settings or CLAUDE.md entry only on the typed line `yes <name>` that names it, with `/permissions` as the route when the classifier refuses an autoMode entry after that line.

## Branch naming

When naming a branch, use lowercase kebab-case with a slash-separated scope prefix.

Examples:
- `runtime/add-healthz-endpoint`
- `docs/update-phase-2-plan`
- `fix/resolver-null-check`

Every planning session must include a suggested branch name.
