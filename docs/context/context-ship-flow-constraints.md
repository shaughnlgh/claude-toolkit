---
title: Ship flow constraints
summary: The invariants the ship-runner workflow, its control-flow suite, and the ship-flow conductor's waits must keep, covering the ceiling and the seat cap, fix commits, pipeline state, the merge guard, the release-only resume, the background wait and relaunch, and the shared git rule text.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-06
source_refs:
  - plugins/toolkit/workflows/ship-runner.js
  - plugins/toolkit/workflows/tests/ship-runner/
  - plugins/toolkit/skills/ship-flow/SKILL.md
---
<!-- managed-by: toolkit -->

# Ship flow constraints

The `ship-flow` skill launches the `ship-runner` workflow to carry a reviewed slice from commit to tag. What the script takes and returns is in [workflows.md](../workflows.md). This page lists the constraints a change to the runner or its suite must keep.

## Ceiling

- `CEILING` in `ship-runner.js` maps the plan note's `ceiling` to a stage rank, and `ceilingRank` is that rank plus one when `ceiling` is `merge` and `tag` is true. The note's `ceiling` key holds `none`, `mr`, or `merge`, and the runner's `stopStage` result names the stage the run stops at, so a change keeps the key vocabulary and the stage vocabulary apart.
- The seat cap lowers a `merge` ceiling to `mr` while the plan note holds a `Validation deferred:` line and no `Seat run passed:` line after the last such line names the HEAD sha that section 3 of the `ship-flow` skill reads. The cap compares the exact sha, so a ship fix commit after a passed seat run brings it back until a seat run passes on the new tip. A capped run compares `stoppedAt` with the uncapped stage, so it records `ship-flow stopped: at mr`.
- The ship flow takes `repoRoot` from the path on the last `Seat: worktree` line on the note when that directory exists, because the plan branch is checked out in that worktree. It calls no EnterWorktree. When that directory is gone, or the note has no such line, `repoRoot` comes from the note's `repo` frontmatter, and no earlier `Seat: worktree` line is tried.
- `TAG_WANTED` holds only when `ceiling` is `merge` and `tag` is true. A `tag` under `ceiling` `none` or `mr` is accepted, ignored, and needs no `tagName`. `RANK` keeps `release` at 5 as the internal name of the tag stage, and `ceilingRank` reaches it only through `TAG_WANTED`.
- The runner never reads the plan note, so the `ship-flow` conductor applies the seat cap by passing `ceiling` as `mr` in the runner args. Because `TAG_WANTED` needs `ceiling` `merge`, a capped run also skips the tag stage, whatever the note's `tag_merge` value.

## Stopping a run

- `halted()` checks a dead agent first, then a denied command, then the worker's blockers. Denial comes before blockers, so a worker that was denied a command ends the run with `handoff` set to the paste-ready command even when it also reported blockers.
- `BLOCKER_RULE` in `ship-runner.js` is a copy of `BLOCKER_RULE` in `execute-runner.js`, and the two lines must stay byte-identical. A change to the rule in one runner must be made in the other in the same slice.
- `RETURN_STOP` asks for `blockers` and `deniedCommand` and has no `deviations` field, so a ship stage prompt carries no sentence that routes a caveat. A ship prompt must not name `deviations` while its schema lacks the field.

## Fix commits

- A fix counts only once it is pushed. `fixCommit()` moves `headSha` and adds to `fixShas` only when the worker returns a new sha with `pushed` true. A fix that committed without a push never becomes `headSha`, because no pipeline runs on an unpushed commit.
- `fixCommit()` records a pushed fix before it checks the worker's blockers, so a fix that pushed and then hit a blocker still reaches the merge stage's fix-commit refusal and the report.
- A thread fix stages only the thread's file with `git add --`. The `changedPaths` check runs after the push, so a stray edit to another file never reaches the remote. It stays uncommitted in the tree, and the check blocks the run.

## Pipeline state

- A pipeline state is trusted only when its sha is the pushed commit `headSha`. On GitLab, `head_pipeline` can still point at the previous commit right after a push. The fix loop runs only while `pipeline.sha` equals `headSha`, and `settle()` blocks on a state that belongs to another commit, so a stale red never drives a fix round and a stale green never opens the merge.
- The Claude Code harness blocks a foreground `sleep` in an agent's Bash call and kills a foreground call at 600000 milliseconds. The watch prompt therefore waits with one blocking command, `bash <pluginRoot>/scripts/watch-mr.sh <host> <remotePath> <number> pipeline --sha <headSha> --bound 9`, as one Bash call with the timeout parameter set to 600000, and the bound of 9 minutes ends the script before the harness kills it.
- The watch maps the script's exit code to the state: 0 `green`, 10 `red`, 11 or 12 `pending`, 13 `none`, and 14 `pending` with the new head from the `MOVED` line as the sha, so `settle()` blocks on the sha mismatch. Exit 11 maps to `pending` because the ship-flow conductor's longer background watcher detects and reports a stuck pipeline. Exit 2 or 3 is a failure of the script itself and becomes a blocker, never a state.
- The runner's watch can never observe a stuck pipeline, because its bound of 9 minutes ends before the watcher's default stuck window of 10 minutes. The runner therefore has no stuck state, and only the ship-flow conductor's background watcher, run with `--bound 180`, can read `STUCK`.
- The `threads:wait` verifier runs only when `botAuthors` is not empty. It calls the same script in `threads` mode with one double-quoted `--bot` per author, and the args check accepts only host logins, so a login never carries shell syntax into the command. A false `landed` blocks the run before the thread fetch, so `threads` stays null and no merge runs.
- The args check for `botAuthors` is the pattern `^[A-Za-z0-9][A-Za-z0-9._-]*(\[bot\])?$`. It allows the `[bot]` suffix that GitHub bot logins carry, and an unquoted shell word reads that suffix as a glob bracket expression, so every `--bot` value stays double-quoted in the command.
- Open item: `headSha`, `remotePath`, and `pluginRoot` reach every stage's shell command with no format check in the runner.

## Merge guard

- On a run that starts at merge with a `recordedSha`, Prep reads `git log --format=%H <recordedSha>..HEAD`. The merge stage blocks on any printed sha that no `knownShas` entry prefixes and that is not in `fixShas`. `knownShas` holds the shipping record's commit sha, every recorded fix sha, and every sha on a `Seat run reviewed:` line, the commits since the open base that a passing seat run's panel and cold read covered, its own fix commit included. The confirmation gate lists the `Seat run reviewed:` shas under `Fix commits to read before Go`. A seat-run commit that the push stage pushes is not in `fixShas`, so only `knownShas` lets the merge pass it, and `ship-runner.js` needs no change for it. The guard catches a commit that the run never recorded, such as one a dead fix agent pushed or one the owner pushed by hand after a denial.

## Release-only resume

- A run with `startAt` release needs `mr` and `mergedSha`, and tags `mergedSha`. It skips the pipeline and threads block and Prep's remote-head guard, because the host usually deletes the branch after a merge, so `origin/<branch>` no longer exists to compare with HEAD.

## Conductor waits and relaunches

- The runner ends at its watch bound with one named `blocked` sentence, and the `ship-flow` conductor owns any longer wait. The conductor waits only when `blocked` holds exactly the pending sentence or the no-review sentence, `handoff` is null, and `incomplete` is empty.
- The watcher is the one host-reading command the conductor runs. The skill's description and its Boundary both state this carve-out from the rule that the conductor never runs a host command, so a change to the carve-out must change both.
- The watcher runs as a Bash call with `run_in_background: true`. The harness wakes the conductor when the command exits, and the conductor spends no tokens while it waits. The conductor never polls, never spawns an agent to wait, and runs one watcher at a time.
- The `/setup` allow rule for the watcher matches only an invocation written as `bash <plugin-root>/scripts/watch-mr.sh ...`, so the skill must call the watcher in that literal form or the background start prompts.
- The watcher runs from the repo's working directory, because `glab` reads the GitLab host from the git remote there.
- A relaunch after a wait skips the Go gate only when the derived `startAt` is `merge` and the branch, the MR url and number, and the gate's ceiling are unchanged. Any other `startAt` means the tree or the host changed during the wait, so the conductor reports and stops. One ship-flow ask starts at most three watchers.
- After any run in the ask returned a non-empty `fixShas`, a relaunch passes `ceiling` as `mr`. `knownShas` exempts every recorded fix sha from the merge guard, and the runner's `fixShas` refusal covers only the fix commits its own launch pushed. Only the conductor sees every fix in the ask, so the conductor decides whether the ask may merge.
- A relaunch passes `maxFixRounds` as the gate's value minus the sum of `pipeline.rounds` across the ask's runs, never below zero. The count uses `pipeline.rounds`, not `fixShas`, so review thread fixes do not drain the pipeline fix budget.
- Fix shas awaiting review cross waits, relaunches, and sessions through the plan note. The section 6 gate lists them under `Fix commits to read before Go`, the section 9 report names them when any run in the ask returned a non-empty `fixShas` and nothing merged, and the section 8 summary compares `stoppedAt` with the ceiling the gate approved, so a relaunch capped at `mr` records `ship-flow stopped: at mr`.

## Git rule text

- Every stage's `SHIP GIT RULE` ends with the shared `FORBIDDEN` sentence, so `FORBIDDEN` must never name a command that any stage runs, such as `gh pr merge` or `git push`.
- `FORBIDDEN` forbids the bare `--auto` flag, not every flag that starts with `--auto`, because the GitLab merge command runs `glab mr merge` with `--auto-merge=false`. Its clause "run each named command with exactly the flags shown" lets a named command keep its own flags, such as `-f` on `gh api`.

## Testing the runner

- `tests/ship-runner/harness.mjs` reads `FORBIDDEN` from the runner source with a regex on the `const FORBIDDEN = '...'` line, so that line must stay a one-line single-quoted string literal.
- The harness keeps its own copies of `GH_THREADS_QUERY` and the `gh api graphql` reply and resolve mutation text. A change to either text in `ship-runner.js` must be made in `harness.mjs` too.
- Before the harness checks a prompt for another stage's mutating command or a banned flag, it removes the `FORBIDDEN` sentence from the prompt, because that sentence names banned strings in every prompt.
- The harness rewrites `export const meta` to `const meta` and asserts nothing on `meta.description`, so the description prose can change without breaking the suite.
- `SHIP_RUNNER_SCRIPT=<copy> bash run-tests.sh` runs the suite against another copy of the script, for a mutant run. Run each mutant copy as its own plain command. A loop of `sed` mutants inside a bash function can be refused by the command checks even though it deletes nothing.
- The generic `STAGES` cases in `harness.mjs` take per-row run args through an `args` field, merged over `ARGS` or `GL_ARGS`. A row for a stage that spawns only when an arg is set, such as `threads:wait` with `botAuthors`, sets that field.
- A case that proves the run skips a stage asserts that the stage's label is absent from `prompts`, as the `recordedSha at HEAD` and `origin already at HEAD` cases do for `commit:paths` and `push:branch`. A full label list ties the case to how far the default stubs and the default ceiling carry the run.

## Related docs

- [workflows.md](../workflows.md) for the `ship-runner` args, stages, result, and `blocked` sentences.
- [skills.md](../skills.md) for what the `ship-flow` skill does.
- [context-execute-flow-adjudication.md](context-execute-flow-adjudication.md) for the shipping record the ship flow compares against and the summary prefixes it accepts.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the rules every workflow script and its suite follow.
- [context-git-tree-state-capture.md](context-git-tree-state-capture.md) for the git output quirks the Prep stage handles.
- [context-watch-mr.md](context-watch-mr.md) for the host API behavior and the head and pipeline rules `watch-mr.sh` keeps.
