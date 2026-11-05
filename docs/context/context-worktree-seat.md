---
title: Worktree seat
summary: The constraints that seat-check.sh, the session-start seat line, and the execute flow's seat check must keep when a change touches how a session decides who holds a repo's main checkout.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-05
source_refs:
  - plugins/toolkit/scripts/seat-check.sh
  - plugins/toolkit/scripts/tests/seat-check/run-tests.sh
  - plugins/toolkit/hooks/session-start.sh
  - plugins/toolkit/hooks/tests/session-start-seat-check.sh
  - plugins/toolkit/hooks/tests/run-all.sh
  - plugins/toolkit/skills/execute-flow/SKILL.md
  - plugins/toolkit/workflows/execute-runner.js
  - plugins/toolkit/doctrine/orchestration.md
---
<!-- managed-by: toolkit -->

# Worktree seat

The seat is a repo's main checkout, the directory whose `.git` is a directory. `seat-check.sh` decides which live sessions hold it, and the `session-start.sh` hook and section 2a of the `execute-flow` skill act on its output. The holder rule, the output lines, and the exit codes are in [scripts.md](../scripts.md#seat-checksh). This page lists the constraints a change to the script or its two callers must keep.

## seat-check.sh

- The script parses the session list with `jq -rn 'input | ...'`. Plain `jq` exits 0 on empty stdin, so a missing or failing `claude` binary would read as an empty list and report the seat free. `input` errors on empty stdin, and the script turns that error into exit 2.
- The script joins each row on the 0x1f unit separator and reads it with `IFS=$'\x1f'`. It replaces any tab, newline, carriage return, or 0x1f inside a field with a space. A whitespace `IFS` such as a tab collapses consecutive separators, so a null `status` or `kind` would shift every later column.
- The dirty count runs `git --no-optional-locks status`, so a check from one session never writes the main checkout's `.git/index` while the holder works there.
- The script resolves the main checkout as the parent of the git common dir when that dir is named `.git`. Otherwise it falls back to `git rev-parse --show-toplevel` of the path it was given.
- Every caller must pass its own session id as `--self`. Without it, a caller whose `cwd` is the main checkout lists itself as a holder and the script exits 10.

## The main: line

- The hook and the execute flow both read the `main:` line. A change to its label or its form must change both callers.
- The hook prints the seat line only when the script exits 10 and its `main:` line equals `cd $ROOT && pwd -P`. A linked worktree session's root is the worktree directory, so that equality is the only test that keeps such a session silent. The worktree-silent case in `hooks/tests/session-start-seat-check.sh` pins it.
- Section 1 of the `execute-flow` skill takes `repoName` from the `main:` line. It falls back to the section 3 verifier's `git rev-parse --path-format=absolute --git-common-dir` output only when the seat check exited 2, so a run from a linked worktree recalls and reports under the main checkout's name.

## The worktree answer

- Section 2a of the `execute-flow` skill names the worktree after the plan note's `branch` frontmatter value, or after `planName` when that value is blank.
- When `git worktree list` already shows `<main>/.claude/worktrees/<name>`, section 2a calls EnterWorktree with `path`, so a rerun enters the worktree that an earlier run opened.
- EnterWorktree with `name` always creates a new branch from the `worktree.baseRef` setting and never checks out an existing branch. When the plan's branch exists locally or on origin, section 2a obtains the worktree with `git worktree add` under the flow's git permission, as a paste-ready command for the user under `none`, then calls EnterWorktree with `path`. Git refuses that add while another worktree has the branch checked out, so section 2a skips the add and asks the fallback question with only Take the seat and Hold.
- Section 2a calls EnterWorktree with `name` only when the plan's branch does not exist. Section 3 then skips its merged check. After any worktree entry, section 5 writes the worktree's branch from section 3 into the plan note's `branch` frontmatter when the two differ, so the commit handoff and the ship flow name the branch the worktree carries.
- After the switch, `repoRoot` is the worktree path in every later section. `repoName` does not change, because section 1 resolves it from the main checkout.
- The switch lasts only for the live session. Section 5 records `Seat: worktree <path>` under Plan Changes During Execution, and section 1 re-enters that path with EnterWorktree `path` before anything else in a later session. A session that already runs in that path counts as entered, so section 2a asks no seat question.
- A fresh worktree holds only tracked files, so section 2a runs the repo's install step after the switch. A line in the main checkout's `CLAUDE.md` that begins `Worktree install: ` overrides the default for a repo the default does not fit, and a `<worktree>` token in it expands to `.claude/worktrees/<name>`, the worktree path relative to the main checkout.
- Without that line, the default needs nothing declared. When the main checkout's `.env` has a line that begins `WARDEN_ENV_NAME=` and `composer.lock` exists, the composer part is `warden env exec -T php-fpm composer install -d /var/www/html/.claude/worktrees/<name> --no-interaction --no-scripts`, because Composer runs in the `php-fpm` container, which mounts the main checkout at `/var/www/html`. `--no-scripts` keeps a Composer script in the container from reaching the running stack, which serves the main checkout. Without Warden, the composer part is `composer install --no-interaction`. When `package-lock.json` exists, the npm part is `npm ci` on the host. The install is the composer part, the npm part, or both joined with `&&`, composer first. With neither lockfile, no install runs.
- The Warden command runs with the worktree as its working directory like any other install, and `warden` finds the environment by walking up from there.
- The install runs after every section 2a entry and never after a section 1 re-entry, because the earlier run installed there. An implementer runs it with the worktree as its working directory, because the harness blocks a worktree session's commands whose working directory is the main checkout.
- A failed install stops the flow with the plan note untouched. The worktree stays, so a rerun enters it through the existing-worktree case and runs the install again.
- No worker or conductor builds a worktree's environment by hand: no symlink or copy from the main checkout into the worktree, no partial install, and no ignore-file edit to hide one. A worktree whose tests cannot run after the install step is a stop, not a repair.
- A run in a worktree, entered by section 1 or section 2a, passes `inWorktree: true` to the runner. The running local stack serves the main checkout, so the validation verifier does not run a Validation Step that needs it, such as the site's URL, a browser check, or a request to the local stack. It returns that step as deferred with `needs the seat` as evidence and runs every other step. A deferred step does not block.
- The plan note records each deferred step under Plan Changes During Execution as `Validation deferred: <step> (needs the seat)`, and the report lists them first under a line that reads "Deferred to the seat". Nothing is created outside the worktree for such a step: no container, no database clone, no media mount, and no hostname.
- The `deferred` status exists in the validation schema only under `inWorktree`, and a runner result without the `deferred` list reads as an empty list.
- When EnterWorktree or a worktree command fails, the seat question comes back with only Take the seat and Hold, and the first of the two carries the Recommended marker under the busy rule.
- The `seat-check.sh` holder rule already exempts a `cwd` under `<main>/.claude/worktrees/`, the directory where EnterWorktree creates worktrees, so the worktree session holds no seat and the script needs no change. If either path moves, the holder rule must move with it.
- The [parent and child session shape](../../plugins/toolkit/doctrine/orchestration.md#parent-and-child-sessions) puts each child in such a worktree.

## Seat line size

- The hook re-sends the seat line on every request, so its size is a budget. The fixed text is 241 bytes, and a change to the wording must recount it.
- The hook keeps at most three holders. It cuts each holder name to 24 and each status to 8 with awk `substr`, and the branch to 40 with `cut -c`. That keeps a line with three ASCII holders and an ASCII branch under 400 bytes, and the line-cap and three-holders cases in the hook test pin it.
- The macOS system awk counts bytes in `substr`, and `cut -c` counts characters under a UTF-8 locale. A branch name with multibyte characters can therefore push the line past 400 bytes.

## Tests

- The seat-check suite creates its linked worktree at `<main>/.claude/worktrees/wt` and adds `.claude/worktrees/` to the scratch repo's `.git/info/exclude`, so the worktree does not count in the dirty total. [context-git-tree-state-capture.md](context-git-tree-state-capture.md) covers why each clone needs that exclude entry.
- The hook test makes a holder live by writing the test shell's own `$$` as its `pid`, so `kill -0` succeeds without starting a process. It supplies the session list through `TOOLKIT_AGENTS_FILE`, which the hook passes to the script through its environment.
- `session-start-seat-check.sh` reuses `_sr_make_repo` from `session-start-recall-check.sh`, so `run-all.sh` must source it after that file.
- A suite file that cleans up with a recursive force `rm` on a variable must be written with the Write or Edit tool. [context-watch-mr.md](context-watch-mr.md) gives the hook rule behind this.

## Related docs

- [scripts.md](../scripts.md#seat-checksh) for the holder rule, the output, and the exit codes.
- [hooks.md](../hooks.md) for the `session-start.sh` seat line.
- [skills.md](../skills.md) for what the `execute-flow` skill asks when the seat is held.
- [context-git-tree-state-capture.md](context-git-tree-state-capture.md) for the worktree rules of the harness Bash guard.
- [context-macos-script-portability.md](context-macos-script-portability.md) for the 3 second bound on the `claude agents --json` call.
