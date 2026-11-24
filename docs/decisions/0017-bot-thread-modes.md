---
title: Bot thread modes
summary: The ship flow handles third-party review bot threads in one of two modes picked per plan by the thread_mode run option, manual by default, where manual reports a verdict per thread and posts nothing and automatic fixes the real threads and posts and resolves a pushback on a false one only behind a citation guard.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-24
---

# 0017. Bot thread modes

Date: 2026-11-24

Status: Accepted

Amends [0006](0006-ship-flow-merges-unattended.md): the bullet that has the runner work bot threads in rounds now runs those rounds only under `thread_mode: automatic`.

## Context

The ship runner's thread stage fixed every fixable bot thread and had no way to report without acting, so a run either worked every thread or skipped the stage. Some repos forbid replies on review threads. With an all-or-nothing stage, the only way to keep a run from replying was to patch the stage out, which left every bot thread unread.

## Decision

- The `thread_mode` run option, `manual` or `automatic`, records per plan how the ship flow handles third-party review bot threads. Crawl and the plan flow ask it with the other run options. A note without the key reads as `manual`.
- In both modes a verifier reads each open bot thread against the code at the pushed head and returns a verdict of `real`, `false` or `unsettled`, with evidence and a recommendation.
- Manual mode reports each verdict and recommendation, posts nothing, and stops at the open MR or PR while a bot thread is open.
- Automatic mode fixes the real threads, and on a false thread posts a pushback and resolves the thread. A thread the verifier cannot settle stays open and is reported, never pushed back.
- The citation guard. A `false` verdict stands only when its evidence cites `<file>:<line>`, where the file is a path with a separator or a file extension, is the thread's own file or one of the plan's paths, and the line is 1 or later. Any other `false` verdict becomes `unsettled`. The pushback implementer posts nothing when `git cat-file -e <head>:<file>` fails for the cited file.
- A repo or project rule that forbids replies on review threads turns the run into manual mode, and the ship flow's preview names the rule.

Alternatives weighed and rejected: a report-only variant of `maxThreadRounds: 0`, because it still waits and judges from thread text alone; automatic as the default, because an older note would start posting replies the user never chose; and asking at ship time, because the question stops an unattended run.

## Consequences

A note with no `thread_mode` stops at the open MR or PR when a bot thread is open, and posts nothing, so a `ceiling: merge` note sets `thread_mode: automatic` to keep merging unattended. This includes every note written before the key existed. Automatic mode posts public replies that cannot be unsent. The guard proves that the cited file exists at the head and belongs to the change, not that the verifier read that line correctly, so a wrong reading of a real line can still post a wrong pushback, which the thread's author can reopen. Automatic mode resolves a thread it pushes back on, which the hand-run `review-threads` skill does not do. An older `validate-plan.py` ignores the `thread_mode` key.
