---
title: Execute flow adjudication
summary: How the execute-flow skill stops, resumes, and settles unreproduced and open panel findings and verified cold-read findings with the user, and the constraints a change to those paths must keep.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-28
source_refs:
  - plugins/toolkit/skills/execute-flow/SKILL.md
  - plugins/toolkit/skills/red-team/SKILL.md
  - plugins/toolkit/workflows/execute-runner.js
  - plugins/toolkit/skills/ship-flow/SKILL.md
  - plugins/toolkit/workflows/ship-runner.js
  - plugins/toolkit/agents/
---
<!-- managed-by: toolkit -->

# Execute flow adjudication

The `execute-flow` skill launches the `execute-runner` workflow and settles with the user what the run cannot settle alone. What the script takes and returns is in [workflows.md](../workflows.md). This page lists the constraints a change to the skill's stop, resume, and fix paths must keep.

## Why the user adjudicates

- A fail-closed gate that no person can open stalls the run instead of making it safer. The execute flow therefore tells every worker the dangerous-commands hook rule, shows the review panel the plan's Assumptions and Risks as settled decisions, and returns each unreproduced panel finding in `review.unverified` and each verified cold-read finding in `coldResidual` for the user to settle instead of blocking the run.

## Stop and resume prefixes

- Section 1 of the skill starts a fresh run on an in-progress plan note only when the last `sessions` summary begins `execute-flow blocked:`, and resumes at section 8 only when it begins `execute-flow adjudicating:`. A new stop path must leave a summary that begins with one of those prefixes, or section 1 refuses the next request to run the flow.
- The ship-flow skill writes summaries that begin `ship-flow stopped:` or `ship-flow finished:`. Section 1 of the ship-flow skill accepts an in-progress plan note only when the last summary begins `execute-flow finished:`, `ship-flow stopped:`, or `ship-flow finished:`. A change to the `execute-flow finished:` prefix must change that list too, or the ship flow refuses every slice the execute flow finished.
- Section 6 writes one `Changed path:` line per path a blocked run left in the tree, taken from `git status` with the section 3 foreign paths removed, and one `Baseline:` line. Section 3 continues a rerun only when every dirty path equals a recorded path. The record comes from the tree and not from the workers' `changedPaths`, because a dead implementer's edits are never collected and a worker can report a foreign path. A blocked stop path that skips the section 6 record forces the user to commit or discard the slice before the rerun, and a WIP commit removes the slice from the `git diff HEAD` capture the panel reviews.
- A continued rerun passes the recorded paths as `priorChangedPaths` and the recorded failing names as `baselineFailing`, an empty list when no clean baseline exists. `prep:baseline` runs over the half-built slice and the validation verifier reads pre-existing status from the baseline failing list it is shown, so dropping `baselineFailing` makes a check the blocked run broke look pre-existing. The doc pass reads `CHANGED PATHS` from the runner's changed list, so dropping `priorChangedPaths` leaves the earlier run's files out of the doc pass.
- `blockersOf` in `execute-runner.js` and `ship-runner.js` stops on any `blockers` entry. The implementer and verifier agent definitions and the runner prompts say `blockers` holds only work the worker could not do. The `execute-runner.js` step prompts route a caveat to `deviations`, and the `ship-runner.js` stage schemas have no `deviations` field, so a ship stage prompt carries no caveat routing. A text filter on `blockers` is not used, because a false pass continues over a denied step and nothing reports it.
- The four leaf agents, `implementer`, `verifier`, `explorer`, and `browser-driver`, name the `Blockers` return heading in their opening sentence and in their return list, and `doctrine/orchestration.md` lists the same heading in the worker return contract. A rename of that heading must change all five files, or a worker reads two names for one field.
- A runner prompt routes a caveat only to a field its schema has. `RETURN_STEP` in `execute-runner.js` sends caveats and follow-ups to `deviations`. The doc pass and remember pass schemas have no `deviations` field, so their blockers sentence says only "one sentence per step you could not do". The verifier definition says a caveat goes in a schema field that holds it or is left out. A new prompt must not name `deviations` unless its schema declares it.
- The runner seeds its changed list from `priorChangedPaths` before any worker runs, and each later path is added only when the list does not already hold it. The recorded paths therefore stay first in `changedPaths` and never repeat. The `baselineFailing` override replaces the failing list only when `prep:baseline` returned a result, so a dead baseline verifier still blocks the run. [workflows.md](../workflows.md) gives the arg contracts.

## Adjudicated findings

- The adjudication list is every `review.unverified` entry, then every `review.open` entry with bucket `confirmed`, then every `coldResidual` entry. Section 6 records each `review.open` entry with its bucket, because a resume at section 8 rebuilds the list from the note. An entry is settled when the plan note records it as fixed, wrong, intentional, or did not matter. Every gate that holds the finished summary, the slice marker, and the commit suggestion reads settled over the whole list, so a gate that reads only `coldResidual`, or a fifth outcome word, leaves the `execute-flow finished:` summary unreachable and the ship flow refusing the slice.
- Section 8 asks one question per entry, panel entries first, with the options Fix now, Wrong, Leave it, and Hold in that order. Fix now is recommended unless the finding maps to an Assumption or Risk, and Leave it is recommended when it does. Leave it records intentional when the finding maps to an Assumption or Risk and did not matter when it maps to none. Wrong also records a `Reviewer prompt (<dimension>):` line for the user to add to `REVIEW.md` by hand. No recorded line starts with `Remember:`, because `remember-guard.sh` keys on that word.
- The cold read gets the keys of the panel's `confirmed`, `nits`, and `preExisting` entries as a no-repeats list, and never the refuted, dropped, or unverified ones, because the cold read is the recovery path for a real defect one verifier refused. Unreproduced nits without a confirmed finding are never fixed in the slice and stay under To settle. A reproduced finding never waits there: it is confirmed at any score, and an open confirmed finding below 0.6 is asked about in section 8 rather than blocking. A refuted doc finding is listed under To settle with the verifier's reason and quoted line, because the cold read is its only automated re-raise. [context-review-scoring.md](context-review-scoring.md) holds the scoring and routing rules.
- The `red-team` skill's post-fix cold read, its section 6, sends a verified residual of fifteen lines or fewer to one scoped implementer fix round. The execute flow asks the user about each entry instead, in its section 8. The two policies differ on purpose.
- The section 8 fix round runs after the doc pass and never reruns it. The skill's report must say whether the fix touched a public surface that the doc pass did not see, because this is the one path in an execute-flow run where the doc pass can miss a change.
- Three files state the adjudication list and its order: this page, [context-review-scoring.md](context-review-scoring.md) under Settled outcomes, and section 8 of the `execute-flow` skill. Section 8 asks its questions in the same order. A change to the list or its order must edit all three.

## Shipping record

- Section 7 of the skill writes the shipping record (the staging list, the commit message, and a hash) after the accepted docs are written, a section 8 fix replaces it, and the ship flow compares a fresh capture against its hash before a commit. The slice marker still keys on `diffHashes.postDoc`, which is taken before any doc lands, so the shipping record hash and the marker hash differ whenever the consent gate accepted a doc.

## Related docs

- [skills.md](../skills.md) for what the `execute-flow` and `red-team` skills do.
- [workflows.md](../workflows.md) for `coldResidual`, `blocked`, and the rest of the `execute-runner` result.
- [context-review-scoring.md](context-review-scoring.md) for how the panel scores, verifies, and routes findings.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the runner's gating rules and the `verify.sh` checks on the skill.
- [context-ship-flow-constraints.md](context-ship-flow-constraints.md) for the ship flow that compares against the shipping record.
