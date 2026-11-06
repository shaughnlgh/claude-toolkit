---
title: Git tree state capture
summary: How the toolkit's skills and workflow scripts list changed paths, capture a slice diff, and read branch state with read-only git, and the git output quirks those commands must handle.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-06
source_refs:
  - plugins/toolkit/workflows/execute-runner.js
  - plugins/toolkit/skills/execute-flow/SKILL.md
  - plugins/toolkit/skills/red-team/SKILL.md
  - plugins/toolkit/commands/obsidian-topic.md
  - plugins/toolkit/doctrine/git-safety.md
  - plugins/toolkit/workflows/ship-runner.js
  - plugins/toolkit/scripts/seat-check.sh
  - plugins/toolkit/hooks/session-start.sh
---
<!-- managed-by: toolkit -->

# Git tree state capture

The `red-team` skill, the remember pass in `obsidian-topic.md`, and the execute flow capture a slice as `git diff HEAD` plus one `git diff --no-index` per untracked file. The execute flow also compares path lists that come from different git commands. Those commands print the same path in different forms. This page lists the differences a capture or a path comparison must handle. The runner's capture prompt is described in [workflows.md](../workflows.md), and the read-only git command list is in `plugins/toolkit/doctrine/git-safety.md`, section Flows.

## Diffing untracked files

- `git diff --no-index -- /dev/null "$f"` needs the `--`, or git reads a filename that starts with a dash as an option.
- `git diff --no-index` exits 1 when the two sides differ, which is true for every untracked file. A capture must treat exit 1 as success.
- The untracked list comes from `git ls-files --others --exclude-standard -z` read with a NUL-delimited loop, so a name that holds a space or a newline stays one path.

## Path quoting

- `git diff --name-only`, `git ls-files`, and `git status --porcelain` print a non-ASCII path in quoted octal form unless the command carries `-c core.quotePath=false`.
- `git status --porcelain` wraps a name that contains a space in double quotes. `git ls-files` and `git diff --name-only` print the same name bare. A comparison across these commands removes the surrounding quotes from a quoted porcelain name that holds no backslash.
- All of these commands quote a name that contains a backslash, a double quote, or a control character, and escape those characters, even with `core.quotePath=false`. Compare such a name verbatim on both sides, quotes and escapes included.
- A porcelain rename line holds both paths separated by ` -> `. A name that contains ` -> ` also contains a space, so git always quotes it. Split the line at the ` -> ` that falls outside double quotes. Splitting at the last ` -> ` cuts a quoted new name such as `"p -> q.txt"` in two.
- An agent that returns `git status --porcelain` lines can trim the leading space of a status such as ` M`. `porcelainPaths()` in `ship-runner.js` therefore accepts optional leading whitespace before a status of one or two characters.
- The `execute-runner.js` capture prompt lists paths with `git -c core.quotePath=false diff <base> --name-only` and `git -c core.quotePath=false ls-files --others --exclude-standard` with the own-worktree pathspec, where `<base>` is `HEAD`, or the open base on a seat run, so a seat run's capture holds every commit since that base plus the tree changes. It uses the same `core.quotePath=false` form the `execute-flow` skill's tree check reads. Step 2 of the `red-team` skill runs a plain `git status` and builds no such listing, so its output is not interchangeable with the runner's `paths`.

## Untracked directories

- `git status --porcelain` prints an untracked directory as one `dir/` entry. Add `-uall` so it lists every untracked file, and the entries line up with the per-file lists from `git ls-files`.
- Git lists a linked worktree inside the checkout as one `dir/` entry even under `-uall`, because the directory holds a `.git` entry, and `git ls-files --others` lists it the same way. `git diff --no-index -- /dev/null` on that entry fails with `Could not access` and exits 1, the exit code a capture tolerates, so without the own-worktree pathspec the directory lands in a capture's path list with no diff.

## Branch state

- `git merge-base --is-ancestor <branch> origin/<default>` exits 0 for a branch that is already merged and also for a branch cut from the default branch with no commits of its own. The exit code cannot tell the two apart, so the `execute-flow` skill reads the plan note's `mr` frontmatter instead: it stops as merged when that key is set and continues as a fresh branch when it is blank.
- `git symbolic-ref` with one argument reads a ref, and with two arguments it writes one. A read-only command list therefore allows only the one-argument form.
- `git ls-remote origin <name>` matches the pattern against the end of each ref, so `feat/x` also matches `refs/heads/y/feat/x`. Pass the full ref, `refs/heads/<branch>`, as `ship-runner.js` does with `REMOTE_REF` in every ls-remote call.

## Worktrees

- A session in a linked worktree holds no seat. The seat is the main checkout, the directory whose `.git` is a directory, and `seat-check.sh` counts only sessions whose `cwd` is that checkout or a directory under it, outside `<main>/.claude/worktrees/`.
- In a worktree session, the harness guard on the Bash tool reads the command text. It refuses a command that names `git` with `-C`, a `--git-dir`, a `GIT_DIR` variable, or a `cd` into the main checkout, and a command it cannot classify, including one whose script path contains the string `git`. It does not read the script, so a script invoked by a path and arguments with no `git` token runs, and the script's own `git -C <main>` calls run. `seat-check.sh` and the hook's call to it rely on this.
- `seat-check.sh`, the `execute-runner.js` capture, the `red-team` status read and capture, and the execute flow's status reads pass the pathspec `':(exclude,top).claude/worktrees/'`, so a linked worktree under that path never shows in the dirty count, a capture, or those status reads, and no clone needs an ignore entry for it. The ship flow's section 3 status read and the runner's `prep:baseline` status read carry no pathspec, so in a clone with no ignore entry they list a linked worktree as one untracked directory. Neither read decides a stop on such a path: the ship flow compares only staging-list paths, and the baseline status is reported, not checked. The pathspec over a directory that does not exist drops nothing and exits 0.
- The same guard refuses more forms in a worktree session than the `git` targeting rules above. It refuses a Python heredoc whose text names `git`, even when the script only edits files, a compound command that runs `git diff` alongside `grep`, a pipeline that redirects `verify.sh` output to a file, a compound command that runs several scripts in sequence, and a `sed` edit on a variable path. It allows `cd <worktree> && bash verify.sh </dev/null 2>&1 | tail` and a plain `cd <worktree> && git diff -U0 -- docs`. A worker in a worktree therefore edits docs with the Edit tool, runs each test suite in its own Bash call, and runs a scripted edit only from a script file written with the Write tool and invoked as `python3 <path>`.

## Related docs

- [workflows.md](../workflows.md) for the `execute-runner.js` capture commands and the `paths` it returns.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the three diff captures and the hash checks built on them.
- [scripts.md](../scripts.md#seat-checksh) for the `seat-check.sh` holder rule and output.
