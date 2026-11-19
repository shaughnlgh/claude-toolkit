---
title: Seat queue in the git common dir
summary: A seat run that finds the main checkout taken waits in a queue kept in the git common dir and ordered by join second, then session id, behind a mkdir lock, with an entry removed only after two missed agents reads and a run whose parent holds the main checkout stopped at once only when the parent is the only live session with its name.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-10
---

# 0009. Seat queue in the git common dir

Date: 2026-11-10

Status: Accepted

Amended by [0015](0015-lead-and-worker-sessions.md), which replaces the bullets that open "When the run's parent" and "A child leaves its worktree", so the queue prints `LEAD` when the run's lead holds the main checkout, and the lead ends a worker session with `claude stop` once its work is pushed or merged.

## Context

`seat-check.sh` derives the seat from the live session list on every call and keeps no state. A seat run that found the main checkout held or dirty stopped, and the user had to end every other session there and ask again. Order between waiting runs needs state that every linked worktree of the clone sees, and the scratchpad is per session. A live row that one `claude agents --json` read leaves out, for example while the CLI rewrites the session registry file, looks the same as a dead session.

## Decision

- The queue is `<git common dir>/toolkit-seat-queue/`, kept by `scripts/seat-queue.sh`, with one entry per joined session named `<join epoch seconds>-<sessionId>`. The entry is empty while the session waits and holds `seated` from its turn until the release, so a listing never misses an entry while its state changes.
- A `mkdir` of `.grant` in the queue directory serializes each grant step and each leave. A lock older than 10 seconds belongs to a killed process and is removed.
- A verdict lists the entries before its seat read and removes only listed entries. It removes another session's entry only on a second miss 5 seconds to 10 minutes after the first, which `.miss-<sessionId>` records.
- Liveness comes from `seat-check.sh --live`, so the liveness rule stays in one script. A session with `pid: null` cannot join.
- A seated entry counts as a holder for every other session, whatever `cwd` the agents list reports for it.
- A session outside the main checkout gets its turn when no waiting entry is ahead of it and no other session holds the seat. A session in the main checkout ignores order and waits only for the other holders.
- The seat run waits through `seat-queue.sh wait`, started as a background Bash command, as the ship flow waits on `watch-mr.sh`. At the wait start it names each session in the main checkout with no entry, to the user and to its parent.
- When the run's parent, matched by the session id of the one live row with the parent's name, sits in the main checkout with no entry, the queue prints `PARENT`, and the run starts no watcher and stops. A name that matches no live row or more than one falls back to the wait.
- A child leaves its worktree after a report only when the report tells the user to end it, and otherwise stays in its worktree.
- The release after the restore returns the session to the worktree it left and removes the entry. It keeps the entry seated while the plan note has an open restore point or the return fails.

## Consequences

This is the toolkit's first shared state and its first lock. The queue lives inside `.git`, git never reads it, and it goes away with the clone. The queue holds the seat for a run that left a worktree without relying on the agents-list `cwd`, but the session-start seat line and another run's section 2a still read `cwd` alone. A dead session's entry goes one round later than a single read would allow. A session in the main checkout with no entry, such as a planning child, holds every waiter until it ends or moves, while a run whose parent is such a session, and the only live session with the parent's name, stops at once instead of waiting. A background session cannot join, so its seat run stops. A session that never joins can take a free seat first. A reused pid keeps a dead session live, a weakness the queue inherits from the seat-check liveness rule. A sandbox that refuses the write fails the join, so the seat run stops and quotes the error. This decision changes two points of [0005](0005-approval-offers-the-execute-flow.md): the seat run waits for its turn instead of stopping on a held main checkout, and a child leaves its worktree after a report only when the report tells the user to end it.
