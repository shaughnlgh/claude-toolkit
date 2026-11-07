---
title: Execute flow asks nothing after approval
summary: After it reads the run options, the execute flow asks no question, so every former question is a plan note read or a stop with a report, and a seat run from the main checkout finishes the Validation Steps that a worktree run deferred.
type: decision
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-11-06
---

# 0004. Execute flow asks nothing after approval

Date: 2026-11-06

Status: Accepted

## Context

The execute flow asked questions after the plan was approved: the seat question on a held main checkout, the default branch when `origin/HEAD` was missing, Merged or Fresh over a branch with no commits of its own, Hold or Proceed over foreign dirty paths, one question per adjudication list entry, and the remember pass consent gate. Every one of them stalls an unattended run until a person answers. A worktree run also deferred each Validation Step that needs the running local stack, and nothing ran those steps later, so a slice could ship with its end-to-end checks never run.

## Decision

- The questions become plan note reads or stops with a report. A git step under `none` is a paste-ready handoff followed by a stop. The section 2 run option questions stay, because they ask only for keys the note lacks.
- Asking for the execute flow is the explicit request that EnterWorktree requires. The skill description, the git-safety Flows section, and the doctrine index state it. A held seat, or a main checkout that holds changes, opens a worktree with no question, and an absent, refused, or failed EnterWorktree stops the flow with the plan note untouched.
- A finding the panel's verifier reproduced takes the option the flow recommends: Fix now when it maps to none of the plan's Assumptions or Risks, and Leave it when it maps to one. It gets one fix round, and one the round left unresolved stays held until the user records its outcome on the plan note. An unreproduced panel finding and a cold-read finding that no verifier reproduced are never fixed. The flow records each as unreproduced unless it maps to an Assumption or Risk, and lists it under To settle. An unreproduced panel finding goes into the commit message body for the reviewer of the MR when a commit runs, and a seat run that makes no commit lists it only in its report and on the plan note.
- The consent gate declines every repo doc proposal, and the flow copies each proposal into the plan note's vault folder and links it from the note.
- The seat run, execute-flow section 11, runs the deferred steps against the running local stack from a session started in the main checkout. It passes the worktree run's pre-slice baseline, and its capture, panel, and cold read cover every commit since the open base. It commits its own fixes under `mr` or `merge` and restores the branch the main checkout was on.
- The ship flow caps a `merge`-ceiling run at `mr` until a seat run has passed on the exact HEAD it would merge, and merges over the commits a passing seat run lists on its `Seat run reviewed:` line.

## Consequences

The seat question, the dirty-tree question, and the Wrong adjudication option are gone. The user contests an outcome on the branch before the merge: under `none` the user commits, under `mr` a person merges the MR, and under `merge` the confirmation gate shows the message and the paths but not the diff. A single session that ran inside the worktree leaves it with ExitWorktree keep before the seat run when no other session holds the main checkout, as [0005](0005-approval-offers-the-execute-flow.md) records, and stops naming a session started in the main checkout only when that exit fails. A live session in the plan's worktree stops the seat run before the worktree HEAD is detached, and a commit that lands on the detached worktree during the run stops the reattach and is named in the report. A linked worktree under `.claude/worktrees/` never counts as a change in the main checkout, with or without an ignore entry, because the flows' status reads that decide a stop, the captures, and the dirty count carry the pathspec `':(exclude,top).claude/worktrees/'`. A repo with no origin remote runs on the branch check alone, and a clone with an origin remote but no `origin/HEAD` stops until the user runs the handed `git remote set-head origin --auto`. The local stack keeps any schema, data, or cache change that a seat run applied, unless a lockfile stop or a `Seat run guard:` line in the main checkout's `CLAUDE.md` stops the run before the switch. The `red-team` skill stays interactive, because a person runs it by hand.
