---
title: Ship flow constraints
summary: The invariants the ship-runner workflow, its control-flow suite, and the ship-flow conductor's waits must keep, covering the ceiling and the seat cap, fix commits, hands-off paths, pipeline state, the merge guard, the release-only resume, the cleanup, the background wait and relaunch, and the shared git rule text.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-08
source_refs:
  - plugins/toolkit/workflows/ship-runner.js
  - plugins/toolkit/workflows/tests/ship-runner/
  - plugins/toolkit/skills/ship-flow/SKILL.md
---
<!-- managed-by: toolkit -->

# Ship flow constraints

The `ship-flow` skill launches the `ship-runner` workflow to carry a reviewed slice from commit to tag and to clean up after the merge. What the script takes and returns is in [workflows.md](../workflows.md). This page lists the constraints a change to the runner or its suite must keep.

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
- `fixCommit()` records a pushed fix before it checks the worker's blockers, so a fix that pushed and then hit a blocker still reaches the `merge:paths` read and the report.
- A pushed fix reaches the merge only when the pipeline is green on its own head, or `noCiConfig` is true and the watch found no pipeline for that head, and the `merge:paths` read shows it changed only `paths` and no hands-off path. The read runs `git -c core.quotePath=false diff --name-only <before> <sha>` for every `fixShas` entry, from the head before that fix, so a second commit inside one fix push is read too. It runs `git -c core.quotePath=false diff-tree --no-commit-id --name-only -r <sha>` for every `priorFixShas` entry, the fix shas earlier ship-flow runs recorded on the note, so a relaunch reads them again, and the merge start's `logShas` check refuses any commit between them that no run recorded. The runner reads the commit itself and never trusts the fixer's own `changedPaths`.
- An empty read refuses the merge, because a commit made without `--allow-empty` changes at least one path and a merge commit prints nothing.
- A thread fix stages only the thread's file with `git add --`. The `changedPaths` check runs after the push, so a stray edit to another file never reaches the remote. It stays uncommitted in the tree, and the check blocks the run.

## Hands-off paths

- `HANDS_OFF` is the CI configuration list (`.github/`, `.gitlab-ci.yml`, `.gitlab/`, `.circleci/`, `Jenkinsfile`) plus `protectedPaths`. It filters the bot threads a thread fix may touch, and the `merge:paths` read applies it to every ship fix, pipeline fixes included.
- The pipeline fixer has no path limit, and its prompt forbids only weakening a test or a check. A pipeline fix that touches a hands-off path still pushes, so at ceiling `mr` the user reads a green head, and at ceiling `merge` the `merge:paths` read refuses the merge.
- The ship-flow conductor fills `protectedPaths` from the section 3 verifier's `ciScripts`, each repo file a CI step runs by path, plus each path on the plan note's `Protected paths:` line, so a plan that names no path still leaves the gate script protected.

## Pipeline state

- A pipeline state is trusted only when its sha is the pushed commit `headSha`. On GitLab, `head_pipeline` can still point at the previous commit right after a push. The fix loop runs only while `pipeline.sha` equals `headSha`, and `settle()` blocks on a state that belongs to another commit, so a stale red never drives a fix round and a stale green never opens the merge.
- The Claude Code harness blocks a foreground `sleep` in an agent's Bash call and kills a foreground call at 600000 milliseconds. The watch prompt therefore waits with one blocking command, `bash <pluginRoot>/scripts/watch-mr.sh <host> <remotePath> <number> pipeline --sha <headSha> --bound 9`, as one Bash call with the timeout parameter set to 600000, and the bound of 9 minutes ends the script before the harness kills it. Under `noCiConfig` the pipeline command adds `--none 2`, which ends the watch with `NONE` only while no check or pipeline has shown for the sha, so the 9-minute bound still covers a check that starts inside the 2 minutes.
- `noPipeline()` holds only when `noCiConfig` is true and the watch returned `none` for `headSha`. `settle()` and the merge gate both read it. A `none` on another sha, a GitLab `skipped` pipeline in a repo with CI configuration, and every pending, red or stale state still block.
- The watch maps the script's exit code to the state: 0 `green`, 10 `red`, 11 or 12 `pending`, 13 `none`, and 14 `pending` with the new head from the `MOVED` line as the sha, so `settle()` blocks on the sha mismatch. Exit 11 maps to `pending` because the ship-flow conductor's longer background watcher detects and reports a stuck pipeline. Exit 2 or 3 is a failure of the script itself and becomes a blocker, never a state.
- The runner's watch can never observe a stuck pipeline, because its bound of 9 minutes ends before the watcher's default stuck window of 10 minutes. The runner therefore has no stuck state, and only the ship-flow conductor's background watcher, run with `--bound 180`, can read `STUCK`.
- The `threads:wait` verifier runs only in round 1, only when `botAuthors` is not empty, and only while `priorFixShas` and `fixShas` are both empty, because a bot that reviews only on request never reviews a fix push. Every other round runs the `threads:settle` verifier, which calls `watch-mr.sh` in `review` mode and maps exit 0 to `landed`, 15 to `quiet`, 12 to `busy`, and 16 to `unreviewed`. A `busy` outcome blocks the run with the in-progress sentence, an `unreviewed` outcome blocks nothing, and a review that lands inside the window is worked in that round.
- The `botLogins` arg carries the host's review bot logins from `~/.claude/toolkit-review-bots.json`. The fetch counts each one as a bot and the settle wait passes each one as a `--bot` flag, but `botLogins` never starts the round-1 `threads:wait`, because a host-wide list does not say that the bot reviews this repo. Only `botAuthors`, the bots the user names, starts that wait. On GitLab a note author carries no bot flag, so the fetch counts only a listed login as a bot.
- The thread rounds run until no open bot thread is fixable or `maxThreadRounds` fix rounds have run. Each round is a review wait, a fetch, the fixes, and a pipeline rewatch, and a loop that runs to its end finishes on a wait and a fetch, so `threads.open` reads the state after the last fix round. A loop that a blocked fix, wait, or pipeline rewatch stops early keeps the last fetch, so the runner drops from `threads.open` each thread it fixed after that fetch and sets `threads.review` from the last review wait, except that a `quiet` wait after a refusal leaves the refusal there. `threads.rounds` counts the rounds that ran fixes. A filter on which bot threads to fix belongs in the `fixableThread` predicate, and the loop stays as it is.
- The `threads:wait` verifier calls the same script in `threads` mode with one double-quoted `--bot` per author, and the args check accepts only host logins, so a login never carries shell syntax into the command. A false `landed` without `unreviewed` true blocks the run before the thread fetch, so `threads` stays null and no merge runs. Exit 16 returns `landed` false with `unreviewed` true, the refusing `login` and its `reason`, which records the refusal and goes on to the fetch. The runner decides on the typed `unreviewed` flag, never on the free-text `reason`, and keeps `login` only when it passes `LOGIN`.
- A refusal from either review wait sets `refusal`, and `threads.review` keeps it over a later `quiet` settle wait, because a thread-fix push moves the head and a settle wait there can read `quiet`. A later `landed` or `busy` settle wait replaces it, and `landed` clears `refusal`, so a review that lands after a refusal is never reported as missing. A refusal pushes no `blocked` sentence, so the fetch and the fix rounds still run, and the merge gate adds no reason for it, the same as for `quiet`. `watch-mr.sh` returns exit 16 `UNREVIEWED` in threads mode at once only when every `botAuthors` login refused, so a refusal never cuts short the wait for another named bot. Both exit-16 prompt sentences come from the one `UNREVIEWED_FIELDS` constant that marks the text after the login as untrusted bot data, and the runner keeps only the first line of `reason`.
- The args check for `botAuthors` and `botLogins` is the one `LOGIN` pattern `^[A-Za-z0-9][A-Za-z0-9._-]*(\[bot\])?$`, run through one check helper for both args. It allows the `[bot]` suffix that GitHub bot logins carry, and an unquoted shell word reads that suffix as a glob bracket expression, so every `--bot` value stays double-quoted in the command.
- Under `nits: skip`, the classification loop sends a thread that `fixableThread` accepts and the fetch marks `nit` to `pushedBackNeeded` with the reason `nits: skip`, the thread stays open, and the merge is refused until the user settles it. Only that reason marks a thread `nits: skip` left open, because a `nit` thread refused for its path, its id, or `fixable` false lands in `pushedBackNeeded` under either value. Under `nits: fix` a fixable `nit` thread is fixed like any other.
- Open item: `headSha`, `remotePath`, and `pluginRoot` reach every stage's shell command with no format check in the runner.

## Merge guard

- The runner refuses a merge of any head that `seatSha` does not prefix. The seat cap compares only the section 3 HEAD, so without `seatSha` a fix this run pushes after a passed seat run would merge with no seat run on it. The conductor passes `seatSha` only when a `Seat run passed:` line lifted the cap.
- On a run that starts at merge with a `recordedSha`, Prep reads `git log --format=%H <recordedSha>..HEAD`. The merge stage blocks on any printed sha that no `knownShas` entry prefixes and that is not in `fixShas`. `knownShas` holds the shipping record's commit sha, every recorded fix sha, and every sha on a `Seat run reviewed:` line, the commits since the open base that a passing seat run's panel and cold read covered, its own fix commit included. The section 6 preview lists the `Seat run reviewed:` shas under `Commits this run may merge without a panel review`, and the section 9 report lists them under `Fixed beyond the plan:`. A seat-run commit that the push stage pushes is not in `fixShas`, so only `knownShas` lets the merge pass it, and `ship-runner.js` needs no change for it. The guard catches a commit that the run never recorded, such as one a dead fix agent pushed or one the owner pushed by hand after a denial.

## Release-only resume

- A run with `startAt` release needs `mr` and `mergedSha`, and tags `mergedSha`. It skips the pipeline and threads block and Prep's remote-head guard, because the host usually deletes the branch after a merge, so `origin/<branch>` no longer exists to compare with HEAD. It also skips Prep's branch check, because the cleanup deletes the plan branch after a merge, and the tag stage needs only the merge commit.

## Cleanup

- The cleanup stage runs only under `ceiling` `merge`, only when the conductor passes `mainRoot`, never on a release-only start, and only after a merge this run made. `mainRoot` must be an absolute path with no single quote and needs `sessionId`, the conductor's session id in lowercase hex with dashes. `worktree` must sit under `<mainRoot>/.claude/worktrees/`. The conductor passes `mainRoot` only when the session is not inside a worktree, because the cleanup removes that worktree.
- `cleanup:state` reads and `cleanup:run` acts. The script computes the command list in `cleanupCommands()` from the read, so the suite pins the order and every guard.
- The seat read runs at cleanup time, never at launch, because the merge can land after three thread rounds and their pipeline waits. `cleanup:state` runs `seat-check.sh '<mainRoot>' --self <sessionId>` and returns the exit code, the first stdout line as `seatLine`, and each holder as `<name> (<sessionId>)`. The seat is free only when the exit code is 0, `seatLine` is `seat: free`, and no holder came back, and held only when the exit code is 10, `seatLine` is `seat: held`, and a holder came back. Any other mix reads as a check that could not run. Neither a held seat nor a failed check lets the main checkout switch off the plan branch, so one misreported field never frees the seat.
- A clean main checkout already on the default branch fast-forwards under live holders, because a pull moves no holder off its branch. `cleanup.holders` keeps every holder the read returned, so the report names them.
- The occupant read runs at cleanup time as its own `seat-check.sh` call with `--worktree`, so a missing directory cannot turn the seat read into exit 2. The worktree stays, with a skipped sentence, while any occupant is live or the occupant check did not exit 0 or 10.
- Each delete runs only while the branch sits at the merged head `headSha`. The local delete is `git branch -d`, never `-D`, and no cleanup command passes `--force`. The local delete also waits while the branch is checked out in another worktree or in the main checkout.
- `git branch -d` runs before `git push origin --delete`, because after a squash merge `-d` succeeds only while `refs/remotes/origin/<branch>` still matches. The remote branch stays while the local branch stays, so a handed `git branch -d` can still prove the merge.
- A host that deletes the head branch at merge can do so before or after `cleanup:state` reads origin. An empty ls-remote line adds no delete, and a `git push origin --delete` whose output holds `remote ref does not exist` counts as ran. `cleanup.remote` is `cleanup` when the push removed the branch, `host` when origin no longer held it, and `kept` otherwise.
- `settleCleanup()` stops at the first failed command, and every later command lands in `cleanup.notRun`. Command failures go to `cleanup.failed`, never to `blocked`. A permission denial, a reported blocker, or an agent that returns nothing ends the run through `halted()` after the merge has landed, so `merged` stays set, and the commands the implementer reported as run still count as ran.

## Conductor waits and relaunches

- The runner ends at its watch bound with one named `blocked` sentence, and the `ship-flow` conductor owns any longer wait. The conductor waits only when `blocked` holds exactly the pending sentence, the no-review sentence, or the in-progress sentence, `handoff` is null, and `incomplete` is empty. The watcher for the in-progress sentence runs `watch-mr.sh` in `review` mode, and its `QUIET` exit 15 and any watcher's `UNREVIEWED` exit 16 relaunch as `LANDED` does.
- The watcher is the one host-reading command the conductor runs. The skill's description and its Boundary both state this carve-out from the rule that the conductor never runs a host command, so a change to the carve-out must change both.
- The watcher runs as a Bash call with `run_in_background: true`. The harness wakes the conductor when the command exits, and the conductor spends no tokens while it waits. The conductor never polls, never spawns an agent to wait, and runs one watcher at a time.
- The `/setup` allow rule for the watcher matches only an invocation written as `bash <plugin-root>/scripts/watch-mr.sh ...`, so the skill must call the watcher in that literal form or the background start prompts.
- The watcher runs from the repo's working directory, because `glab` reads the GitLab host from the git remote there.
- A relaunch after a wait runs only when the derived `startAt` is `merge` and the branch, the MR url and number, and the launch's ceiling are unchanged. The ship flow asks no question before a launch or a relaunch. Any other `startAt` means the tree or the host changed during the wait, so the conductor reports and stops. One ship-flow ask starts at most three watchers.
- A relaunch passes `maxFixRounds` as the first launch's value minus the sum of `pipeline.rounds` across the ask's runs, never below zero. The count uses `pipeline.rounds`, not `fixShas`, so review thread fixes do not drain the pipeline fix budget.
- A relaunch passes `maxThreadRounds` as 3 minus the sum of `threads.rounds` across the ask's runs, never below zero, so one ask runs at most three thread fix rounds. A constant in the runner would restart at every relaunch, and one ask runs at most four launches. A new ask, a parent dispatch included, starts a fresh budget.
- A relaunch after a thread-fix push reads a fix head that carries no refusal, so the last result alone can drop one. The conductor holds every result of the ask, so a refusal any run of the ask returned keeps the present-tense caveat and the ask-again step. Section 8 also records a `Review refused: <login> on <sha>, bot text: "<reason>"` line on the note, and a later ask reports that line only as `an earlier ship run recorded that <login> did not review <sha>`, with no next step, because the owner may have asked again and the bot may have reviewed that sha since. No runner arg carries a refusal.
- Fix shas cross waits, relaunches, and sessions through the plan note, which feeds `knownShas` and `priorFixShas`. The section 6 preview lists them under `Commits this run may merge without a panel review`, the section 9 report lists every one under `Fixed beyond the plan:`, and the section 8 summary compares `stoppedAt` with the ceiling section 5 mapped from the note.

## Git rule text

- Every stage's `SHIP GIT RULE` ends with the shared `FORBIDDEN` sentence, so `FORBIDDEN` must never name a command that any stage runs, such as `gh pr merge`, `git push`, or the cleanup's `git switch`. Its clause "never run a command this rule does not name" still bans `git switch` in every other stage.
- `gitRule(allowed, dir)` names the directory the stage runs in: `repoRoot` by default, and `mainRoot` for the two cleanup stages.
- `FORBIDDEN` forbids the bare `--auto` flag, not every flag that starts with `--auto`, because the GitLab merge command runs `glab mr merge` with `--auto-merge=false`. Its clause "run each named command with exactly the flags shown" lets a named command keep its own flags, such as `-f` on `gh api`.

## Testing the runner

- `tests/ship-runner/harness.mjs` reads `FORBIDDEN` from the runner source with a regex on the `const FORBIDDEN = '...'` line, so that line must stay a one-line single-quoted string literal.
- The harness keeps its own copies of `GH_THREADS_QUERY` and the `gh api graphql` reply and resolve mutation text. A change to either text in `ship-runner.js` must be made in `harness.mjs` too.
- The harness's two exit-16 prompt cases assert the `UNREVIEWED_FIELDS` text by exact substring, so a change to that constant must be made in `harness.mjs` too.
- Before the harness checks a prompt for another stage's mutating command or a banned flag, it removes the `FORBIDDEN` sentence from the prompt, because that sentence names banned strings in every prompt.
- The harness rewrites `export const meta` to `const meta` and asserts nothing on `meta.description`, so the description prose can change without breaking the suite.
- `SHIP_RUNNER_SCRIPT=<copy> bash run-tests.sh` runs the suite against another copy of the script, for a mutant run. Run each mutant copy as its own plain command. A loop of `sed` mutants inside a bash function can be refused by the command checks even though it deletes nothing.
- The generic `STAGES` cases in `harness.mjs` take per-row run args through an `args` field, merged over `ARGS` or `GL_ARGS`. A row for a stage that spawns only when an arg is set, such as `threads:wait` with `botAuthors` or `cleanup:state` with `mainRoot`, sets that field.
- Thread round labels carry the round number from round 2 on: `threads:settle`, then `threads:settle:2`, and `pipeline:watch:threads`, then `pipeline:watch:threads:2`. `threads:fetch:<k>` always carries it, and `threads:fix:<i>` counts fixes across every round. A stub for a later round must use the suffixed label.
- `merge:paths` runs only when `fixShas` or `priorFixShas` is not empty, after the last thread fetch and before `merge:mr`. Its stub returns one `{sha, paths}` per fix sha, so a case that adds a fix sha must add its entry or the merge is refused.
- A case that proves the run skips a stage asserts that the stage's label is absent from `prompts`, as the `recordedSha at HEAD` and `origin already at HEAD` cases do for `commit:paths` and `push:branch`. A full label list ties the case to how far the default stubs and the default ceiling carry the run.

## Related docs

- [workflows.md](../workflows.md) for the `ship-runner` args, stages, result, and `blocked` sentences.
- [skills.md](../skills.md) for what the `ship-flow` skill does.
- [context-execute-flow-adjudication.md](context-execute-flow-adjudication.md) for the shipping record the ship flow compares against and the summary prefixes it accepts.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the rules every workflow script and its suite follow.
- [context-git-tree-state-capture.md](context-git-tree-state-capture.md) for the git output quirks the Prep stage handles.
- [context-watch-mr.md](context-watch-mr.md) for the host API behavior and the head and pipeline rules `watch-mr.sh` keeps.
- [context-worktree-seat.md](context-worktree-seat.md) for the seat rule the cleanup's seat read matches.
- [0006-ship-flow-merges-unattended.md](../decisions/0006-ship-flow-merges-unattended.md) for why the ship flow merges over its own fixes and cleans up.
