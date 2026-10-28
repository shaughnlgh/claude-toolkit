---
title: Git tree state capture
summary: How the toolkit's skills and workflow scripts list changed paths, capture a slice diff, and read branch state with read-only git, and the git output quirks those commands must handle.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-28
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
- The `execute-runner.js` capture prompt lists paths with `git -c core.quotePath=false diff HEAD --name-only` and `git -c core.quotePath=false ls-files --others --exclude-standard`, the same `core.quotePath=false` form the `execute-flow` skill's tree check reads. Step 2 of the `red-team` skill runs a plain `git status` and builds no such listing, so its output is not interchangeable with the runner's `paths`.

## Untracked directories

- `git status --porcelain` prints an untracked directory as one `dir/` entry. Add `-uall` so it lists every untracked file, and the entries line up with the per-file lists from `git ls-files`.

## Branch state

- `git merge-base --is-ancestor <branch> origin/<default>` exits 0 for a branch that is already merged and also for a branch cut from the default branch with no commits of its own. The exit code cannot tell the two apart, so the `execute-flow` skill asks the user whether the branch is merged work or a fresh branch for the slice.
- `git symbolic-ref` with one argument reads a ref, and with two arguments it writes one. A read-only command list therefore allows only the one-argument form.
- `git ls-remote origin <name>` matches the pattern against the end of each ref, so `feat/x` also matches `refs/heads/y/feat/x`. Pass the full ref, `refs/heads/<branch>`, as `ship-runner.js` does with `REMOTE_REF` in every ls-remote call.

## Worktrees

- A session in a linked worktree holds no seat. The seat is the main checkout, the directory whose `.git` is a directory, and `seat-check.sh` counts only sessions whose `cwd` is that checkout or a directory under it, outside `<main>/.claude/worktrees/`.
- In a worktree session, the harness guard on the Bash tool reads the command text. It refuses a command that names `git` with `-C`, a `--git-dir`, a `GIT_DIR` variable, or a `cd` into the main checkout, and a command it cannot classify, including one whose script path contains the string `git`. It does not read the script, so a script invoked by a path and arguments with no `git` token runs, and the script's own `git -C <main>` calls run. `seat-check.sh` and the hook's call to it rely on this.
- A main checkout whose `.git/info/exclude` lists `**/.claude/worktrees/` never shows a linked worktree under that path in its `git status`, so the dirty count `seat-check.sh` prints is the main checkout's own. The exclude file is not versioned, so each clone needs the entry.

## Related docs

- [workflows.md](../workflows.md) for the `execute-runner.js` capture commands and the `paths` it returns.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the three diff captures and the hash checks built on them.
- [scripts.md](../scripts.md#seat-checksh) for the `seat-check.sh` holder rule and output.
