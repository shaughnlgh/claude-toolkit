---
title: Ship flow constraints
summary: The invariants the ship-runner workflow and its control-flow suite must keep, covering the cap and ceiling, fix commits, pipeline state, the merge guard, the release-only resume, and the shared git rule text.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-10-19
source_refs:
  - plugins/toolkit/workflows/ship-runner.js
  - plugins/toolkit/workflows/tests/ship-runner/
  - plugins/toolkit/skills/ship-flow/SKILL.md
---
<!-- managed-by: toolkit -->

# Ship flow constraints

The `ship-flow` skill launches the `ship-runner` workflow to carry a reviewed slice from commit to tag. What the script takes and returns is in [workflows.md](../workflows.md). This page lists the constraints a change to the runner or its suite must keep.

## Cap and ceiling

- `CAP` in `ship-runner.js` maps the session git permission to a stage rank, and the ceiling is `min(RANK[stopAt], CAP[permission])`. "Cap" names the permission's limit and "ceiling" names the effective stop. The skill and the docs keep the two words apart, so a change must not use one for the other.

## Stopping a run

- `halted()` checks a dead agent first, then a denied command, then the worker's blockers. Denial comes before blockers, so a worker that was denied a command ends the run with `handoff` set to the paste-ready command even when it also reported blockers.

## Fix commits

- A fix counts only once it is pushed. `fixCommit()` moves `headSha` and adds to `fixShas` only when the worker returns a new sha with `pushed` true. A fix that committed without a push never becomes `headSha`, because no pipeline runs on an unpushed commit.
- `fixCommit()` records a pushed fix before it checks the worker's blockers, so a fix that pushed and then hit a blocker still reaches the merge stage's fix-commit refusal and the report.
- A thread fix stages only the thread's file with `git add --`. The `changedPaths` check runs after the push, so a stray edit to another file never reaches the remote. It stays uncommitted in the tree, and the check blocks the run.

## Pipeline state

- A pipeline state is trusted only when its sha is the pushed commit `headSha`. On GitLab, `head_pipeline` can still point at the previous commit right after a push. The fix loop runs only while `pipeline.sha` equals `headSha`, and `settle()` blocks on a state that belongs to another commit, so a stale red never drives a fix round and a stale green never opens the merge.
- The Claude Code harness blocks a foreground `sleep` in an agent's Bash call. The watch prompt therefore waits with one blocking command, `gh run watch --exit-status` or `glab ci status --live`, as one Bash call with the timeout parameter set to 600000.

## Merge guard

- On a run that starts at merge with a `recordedSha`, Prep reads `git log --format=%H <recordedSha>..HEAD`. The merge stage blocks on any printed sha that no `knownShas` entry prefixes and that is not in `fixShas`. `knownShas` holds the shipping record's commit sha and every recorded fix sha. The guard catches a commit that the run never recorded, such as one a dead fix agent pushed or one the owner pushed by hand after a denial.

## Release-only resume

- A run with `startAt` release needs `mr` and `mergedSha`, and tags `mergedSha`. It skips the pipeline and threads block and Prep's remote-head guard, because the host usually deletes the branch after a merge, so `origin/<branch>` no longer exists to compare with HEAD.

## Git rule text

- Every stage's `SHIP GIT RULE` ends with the shared `FORBIDDEN` sentence, so `FORBIDDEN` must never name a command that any stage runs, such as `gh pr merge` or `git push`.
- `FORBIDDEN` forbids the bare `--auto` flag, not every flag that starts with `--auto`, because the GitLab merge command runs `glab mr merge` with `--auto-merge=false`. Its clause "run each named command with exactly the flags shown" lets a named command keep its own flags, such as `-f` on `gh api`.

## Testing the runner

- `tests/ship-runner/harness.mjs` reads `FORBIDDEN` from the runner source with a regex on the `const FORBIDDEN = '...'` line, so that line must stay a one-line single-quoted string literal.
- The harness keeps its own copies of `GH_THREADS_QUERY` and the `gh api graphql` reply and resolve mutation text. A change to either text in `ship-runner.js` must be made in `harness.mjs` too.
- Before the harness checks a prompt for another stage's mutating command or a banned flag, it removes the `FORBIDDEN` sentence from the prompt, because that sentence names banned strings in every prompt.
- The harness rewrites `export const meta` to `const meta` and asserts nothing on `meta.description`, so the description prose can change without breaking the suite.
- `SHIP_RUNNER_SCRIPT=<copy> bash run-tests.sh` runs the suite against another copy of the script, for a mutant run. Run each mutant copy as its own plain command. A loop of `sed` mutants inside a bash function can be refused by the command checks even though it deletes nothing.

## Related docs

- [workflows.md](../workflows.md) for the `ship-runner` args, stages, result, and `blocked` sentences.
- [skills.md](../skills.md) for what the `ship-flow` skill does.
- [context-execute-flow-adjudication.md](context-execute-flow-adjudication.md) for the shipping record the ship flow compares against and the summary prefixes it accepts.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the rules every workflow script and its suite follow.
- [context-git-tree-state-capture.md](context-git-tree-state-capture.md) for the git output quirks the Prep stage handles.
