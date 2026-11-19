---
title: Approval offers the execute flow
summary: After a plan is approved the session asks once in plain text whether to run the execute flow here, open a child session for it, or stop, and the execute flow opens the plan's worktree on a default branch, names it after the plan, and leaves it with keep for the seat run.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-07
---

# 0005. Approval offers the execute flow

Date: 2026-11-07

Status: Accepted

Amended by [0006](0006-ship-flow-merges-unattended.md), which replaces the bullet "The parent starts no flow on a message".

Amended by [0008](0008-crawl-session-is-the-parent.md), which replaces the bullet "A child session starts from one command the parent hands the user" and limits the bare `yes` in the bullet that opens "After a session sets `status: approved`" to the run-here form of the question.

Amended by [0009](0009-seat-queue-in-the-git-common-dir.md), which replaces the clause "and only when no other live session holds the main checkout" in the bullet that opens "A session inside the plan's worktree", so the seat run waits for its turn instead of stopping, and the sentence "After its report the child leaves its worktree with ExitWorktree keep" in the bullet that opens "The child reports to the parent", so a child leaves its worktree after a report only when the report tells the user to end it.

Amended by [0015](0015-lead-and-worker-sessions.md), which replaces the bullets that open "A child session starts" and "The child reports to the parent" and the Consequences sentence that rejects `claude --bg`, so a lead starts a worker session with `claude --bg` on the user's typed yes and the worker session reports to the lead.

## Context

Plan approval ended the turn, so the user opened a new session, named it, and pasted an ask before any execute run started. A run from approved in a free, clean main checkout on its default branch stopped at the branch check until the user created the plan's branch by hand. The orchestration doctrine described parent and child sessions with no brief, report, name, or terminal. A message from another Claude Code session never counts as the user's consent, so a parent cannot start a child's flow by message. The auto-mode permission classifier reads the user's typed messages and never an AskUserQuestion answer. The execute flow named its worktree after the plan branch with each `/` turned into `-`, so two branches could share a directory, and its re-entry guard counted commits against whatever the main checkout had checked out. A session that ran inside the plan's worktree could not run the seat run.

## Decision

- After a session sets `status: approved`, by the user or the `approveIf` gate, it ends its reply with one plain-text question that plan-guide defines: run the execute flow here, open a child session, or stop. A typed `yes` or `run the execute flow here` is the user's ask for the execute flow by name. The question is plain text, not AskUserQuestion, so the reply that starts the run is a typed message the classifier reads. When a classifier denial stops a run that started on a bare `yes`, the report quotes `run the execute flow here` as the reply to type.
- A run from approved or start-work on a free, clean main checkout that sits on `main`, `master`, the origin default branch, or a detached HEAD takes the plan's worktree instead of stopping at the branch check. A plan branch that does not exist yet takes the branch `worktree-<planName>` that EnterWorktree creates, as on a held seat.
- A child session starts from one command the parent hands the user: `claude -n <planName>` in the main checkout, with the user's ask for the execute flow and the parent's name as its first prompt. The plan note is the brief, because it carries the run options.
- The child reports to the parent by cross-session message, in the five-line shape that execute-flow section 10 defines. The parent starts no flow on a message. After its report the child leaves its worktree with ExitWorktree keep, so its session ends with no exit prompt, and it ends before the parent runs the ship flow or the seat run.
- The worktree is named after the plan name, which is unique across the vault. A worktree the note does not record belongs to the plan only when it is on the plan's branch, or named after the plan and on `worktree-<planName>`.
- A session inside the plan's worktree leaves it with ExitWorktree keep before the seat run, and only when no other live session holds the main checkout. Asking for the execute flow is the request that ExitWorktree requires, as it is for EnterWorktree.

## Consequences

The user approves and types one reply to start a run in the same session, whatever the seat state. A session alone in a clean main checkout on its default branch builds in the plan's worktree, runs the install step there, and leaves the Validation Steps that need the running local stack to a seat run, which the same session reaches through ExitWorktree keep. A plan branch created that way carries the `worktree-<planName>` name into the MR. A rerun on a default branch still stops at the branch check. A bare `yes` reaches the classifier without the question it answers, so a denial there costs one typed `run the execute flow here`, which the stop report quotes. A child costs one pasted command, and a keep answer only when its ExitWorktree call fails, and the parent's user still asks for the ship flow and the seat run. The seat run needs the main checkout to itself, so a coordinating session that sits there stops it, and a session inside the plan's worktree stops before it leaves while another session holds the main checkout. A held or refused cross-session message leaves the parent unaware until the user tells it, and the plan note still holds the outcome. A worktree left under a branch-derived name by an older run is not found by name. A worktree that ExitWorktree refuses to leave keeps the stop that names a session in the main checkout. Starting a child with `claude --bg` was rejected, because its first prompt would be the parent's words rather than the user's ask.
