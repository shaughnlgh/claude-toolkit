---
title: Ship flow merges unattended
summary: The ship flow asks nothing after it reads the run options, works bot review threads in bounded rounds, merges over its own fix commits once a verifier's read shows they changed only the plan's paths, cleans up the branch and worktree under merge, and starts on a dispatch from the parent session the user's launch prompt names.
type: decision
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-11-07
---

# 0006. Ship flow merges unattended

Date: 2026-11-07

Status: Accepted

## Context

The ship flow asked Go, Edit, or Stop at a confirmation gate after the run options, although the note's `ceiling` already records how far the run may go. The runner refused any merge over a fix commit its own launch pushed, and the conductor capped every relaunch after a fix at `mr`, so a run that fixed anything never merged without a person. The pipeline fixer could edit any file, CI scripts included, and nothing compared its changes with the plan's paths. After a merge the plan's worktree, its local and remote branch, and a stale main checkout stayed for the user to clean by hand. The runner waited for a bot review only when the user named the bot, and then fetched, fixed, and refetched the threads once. A child session ignored every message from its parent, because a message from another session is not the user's ask.

## Decision

- The ship flow asks no question after it reads the run options. Section 6 prints the preview, and the recorded `ceiling` is the answer the gate used to ask for, as [0004](0004-execute-flow-asks-nothing-after-approval.md) already does for the execute flow.
- The runner merges over its own fix commits once the pipeline is green on that exact head. It never merges a head that the `seatSha` of a passing seat run does not prefix.
- Before a merge over any fix commit, a `merge:paths` verifier reads the files each fix commit changed, from this run and from earlier runs through `priorFixShas`, with `git diff` from the head before each fix this run pushed and `git diff-tree` for an earlier run's fix. The merge goes ahead only when every file sits inside the plan's paths and off every hands-off path, and an empty read refuses. The section 3 verifier returns `ciScripts`, the repo files a CI step runs by path, and the conductor passes them in `protectedPaths`. The pipeline fix prompt forbids weakening a test or a check.
- The thread stage waits for a bot review in progress to end. `watch-mr.sh` review mode is busy while a bot comment carries CodeRabbit's `review in progress by coderabbit.ai` marker, and ends `LANDED` on a bot review on the head or `QUIET` after a settle window, default 2 minutes, with neither. Round 1 waits for a named bot's review only when the ask names one in `botAuthors` and no run has pushed a fix. Every other wait is the settle wait.
- The runner works bot threads in rounds of review wait, fetch, fixes, and pipeline rewatch until no open bot thread is fixable. One ask runs at most three fix rounds across every relaunch, through the `maxThreadRounds` budget the conductor passes.
- Under `ceiling: merge`, a cleanup stage runs after the merge and the tag. It removes the plan's worktree, switches the main checkout to the default branch and fast-forwards it, and deletes the branch with `git branch -d` and then `git push origin --delete`. Each delete runs only while the branch sits at the merged head, and nothing passes `--force` or `-D`. The worktree remove runs only when an occupant read taken at cleanup time ran and names no live session.
- The cleanup reads the seat with `seat-check.sh --self` at cleanup time. It switches the main checkout off the plan branch only when the exit code, the seat line, and the holder lines agree on `seat: free`, which matches the seat run's rule. A clean main checkout already on the default branch fast-forwards under live holders, because a pull moves no holder off its branch, and the report names the holders.
- The user's child launch prompt grants that the named parent may start the child's execute or ship flow on the same plan note by message. The dispatch counts only when its `from` is that parent, its first line reads `<planName>: run the execute flow` or `<planName>: run the ship flow`, and the note records an `approved` date and a valid `ceiling`. It carries no permission beyond the ceiling. This replaces the [0005](0005-approval-offers-the-execute-flow.md) bullet "The parent starts no flow on a message".
- Under `mr` or `merge`, the execute flow cuts a plan branch that exists nowhere under the name the note records, with `git worktree add -b`, and a run that stays in the main checkout stops when its branch differs from the note's.

## Consequences

A fix commit merges with no human read. Its gates are the pipeline pinned to its head, the `merge:paths` read of the fix itself, and the repo's required checks. A pipeline fix that changes a CI script, CI configuration, or a file outside the plan's paths hands the merge to the user, and every later run refuses it again through `priorFixShas`. A pipeline fix that edits a test inside the plan's paths that no CI step names merges when green, so a plan that wants a test file protected names it on the note's `Protected paths:` line. The report lists every fix commit under `Fixed beyond the plan:`. Each thread round costs at least the settle window, and a bot that starts after that window misses the merge, which the report states as a `QUIET` outcome. A branch someone pushed to after the merge stays, and so does a worktree that holds changes, because git refuses the command and the report names the leftover. A held seat leaves the plan branch checked out in the main checkout, and the report hands the remaining commands. On a host that deletes the head branch at merge, a `git push origin --delete` that meets an absent ref counts as ran, and the note records that the host removed the branch. A permission denial during the cleanup ends the run with the paste-ready handoff after the merge has landed, and the report still shows the merge. A dispatch rests on the receiving model honoring the launch prompt's grant over the label that a message is not from the user, and session names are not unique, so the dispatch only starts the flow the launch prompt already named. This decision replaces the [0004](0004-execute-flow-asks-nothing-after-approval.md) sentence that under `merge` the confirmation gate shows the message and the paths but not the diff.
