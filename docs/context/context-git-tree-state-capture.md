---
title: Git tree state capture
summary: How the toolkit's skills and workflow scripts list changed paths, capture a slice diff, and read branch state with read-only git, and the git output quirks those commands must handle.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-19
source_refs:
  - plugins/toolkit/workflows/execute-runner.js
  - plugins/toolkit/skills/execute-flow/SKILL.md
  - plugins/toolkit/skills/red-team/SKILL.md
  - plugins/toolkit/commands/obsidian-topic.md
  - plugins/toolkit/doctrine/git-safety.md
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

## Untracked directories

- `git status --porcelain` prints an untracked directory as one `dir/` entry. Add `-uall` so it lists every untracked file, and the entries line up with the per-file lists from `git ls-files`.

## Branch state

- `git merge-base --is-ancestor <branch> origin/<default>` exits 0 for a branch that is already merged and also for a branch cut from the default branch with no commits of its own. The exit code cannot tell the two apart, so the `execute-flow` skill asks the user whether the branch is merged work or a fresh branch for the slice.
- `git symbolic-ref` with one argument reads a ref, and with two arguments it writes one. A read-only command list therefore allows only the one-argument form.

## Related docs

- [workflows.md](../workflows.md) for the `execute-runner.js` capture commands and the `paths` it returns.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the three diff captures and the hash checks built on them.
