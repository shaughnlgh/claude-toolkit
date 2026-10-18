<!-- managed-by: toolkit/grill -->
# Context

## Glossary

### Brief

The verbatim planning input: the user's words plus any ticket content, captured exactly and never paraphrased. Every piece of new work enters the planning workflow as a brief, whatever its source.

### Ticket Adapter

A skill that turns an external ticket reference into a brief. Read-only by default: fetching and recording is the adapter's job, judging or changing the ticket is not.

### Topic recall

The lookup `scripts/topic-recall.py` runs over the vault's topic notes and, when given `--repo-root`, the repo's `docs/` folder. It ranks hits by the query words found in each title and summary. The session-start hook injects the top hits for the current repo. `plan-workflow`, `execute-workflow`, and `crawl` run it with the task words before they read code.

### Remember pass

The once-per-slice step that routes the durable facts a slice surfaced. One `implementer` stages shareable facts about the repo as proposed `docs/context/` content behind the conductor's consent gate, and folds every other fact into vault topic notes. `red-team` step 7b runs it after the doc pass, or `plan-workflow` Session Closure runs it if red-team has not. A `Remember:` line records that it ran. The Doc Update Pass keeps existing docs accurate about what changed. The remember pass records what the slice learned.

### Remember guard

The `remember-guard.sh` Stop hook. It warns the user when a reply has a line that begins `Suggested commit` while the session's in-progress plan note has no `Remember:` line under Plan Changes During Execution. It only warns and never blocks. `validate-plan.py` enforces the line at completion: it rejects a plan at status completed, created on or after 2026-10-18, that has no `Remember:` line there.
