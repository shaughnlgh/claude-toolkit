---
title: Execute flow adjudication
summary: How the execute-flow skill stops, resumes, and settles unreproduced panel findings and verified cold-read findings with the user, and the constraints a change to those paths must keep.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-19
source_refs:
  - plugins/toolkit/skills/execute-flow/SKILL.md
  - plugins/toolkit/skills/red-team/SKILL.md
  - plugins/toolkit/workflows/execute-runner.js
  - plugins/toolkit/skills/ship-flow/SKILL.md
---
<!-- managed-by: toolkit -->

# Execute flow adjudication

The `execute-flow` skill launches the `execute-runner` workflow and settles with the user what the run cannot settle alone. What the script takes and returns is in [workflows.md](../workflows.md). This page lists the constraints a change to the skill's stop, resume, and fix paths must keep.

## Why the user adjudicates

- A fail-closed gate that no person can open stalls the run instead of making it safer. The execute flow therefore tells every worker the dangerous-commands hook rule, shows the review panel the plan's Assumptions and Risks as settled decisions, and returns each unreproduced panel finding in `review.unverified` and each verified cold-read finding in `coldResidual` for the user to settle instead of blocking the run.

## Stop and resume prefixes

- Section 1 of the skill starts a fresh run on an in-progress plan note only when the last `sessions` summary begins `execute-flow blocked:`, and resumes at section 8 only when it begins `execute-flow adjudicating:`. A new stop path must leave a summary that begins with one of those prefixes, or section 1 refuses the next request to run the flow.
- The ship-flow skill writes summaries that begin `ship-flow stopped:` or `ship-flow finished:`. Section 1 of the ship-flow skill accepts an in-progress plan note only when the last summary begins `execute-flow finished:`, `ship-flow stopped:`, or `ship-flow finished:`. A change to the `execute-flow finished:` prefix must change that list too, or the ship flow refuses every slice the execute flow finished.

## Adjudicated findings

- The adjudication list is every `review.unverified` entry followed by every `coldResidual` entry. An entry is settled when the plan note records it as fixed, wrong, intentional, or did not matter. Every gate that holds the finished summary, the slice marker, and the commit suggestion reads settled over the whole list, so a gate that reads only `coldResidual`, or a fifth outcome word, leaves the `execute-flow finished:` summary unreachable and the ship flow refusing the slice.
- Section 8 asks one question per entry, panel entries first, with the options Fix now, Wrong, Leave it, and Hold in that order. Fix now is recommended when the entry's score (`finalScore` for a panel entry, `score` for a cold entry) is 0.6 or above and the finding maps to no Assumption or Risk, and Leave it is recommended otherwise. Leave it records intentional when the finding maps to an Assumption or Risk and did not matter when it maps to none. Wrong also records a `Reviewer prompt (<dimension>):` line for the user to add to `REVIEW.md` by hand. No recorded line starts with `Remember:`, because `remember-guard.sh` keys on that word.
- The cold read gets the keys of the panel's `confirmed`, `nits`, and `preExisting` entries as a no-repeats list, and never the refuted, dropped, or unverified ones, because the cold read is the recovery path for a real defect one verifier refused. Nits without a confirmed finding are never fixed in the slice and stay under To settle. [context-review-scoring.md](context-review-scoring.md) holds the scoring and routing rules.
- The `red-team` skill's post-fix cold read, its section 6, sends a verified residual of fifteen lines or fewer to one scoped implementer fix round. The execute flow asks the user about each entry instead, in its section 8. The two policies differ on purpose.
- The section 8 fix round runs after the doc pass and never reruns it. The skill's report must say whether the fix touched a public surface that the doc pass did not see, because this is the one path in an execute-flow run where the doc pass can miss a change.

## Shipping record

- Section 7 of the skill writes the shipping record (the staging list, the commit message, and a hash) after the accepted docs are written, a section 8 fix replaces it, and the ship flow compares a fresh capture against its hash before a commit. The slice marker still keys on `diffHashes.postDoc`, which is taken before any doc lands, so the shipping record hash and the marker hash differ whenever the consent gate accepted a doc.

## Related docs

- [skills.md](../skills.md) for what the `execute-flow` and `red-team` skills do.
- [workflows.md](../workflows.md) for `coldResidual`, `blocked`, and the rest of the `execute-runner` result.
- [context-review-scoring.md](context-review-scoring.md) for how the panel scores, verifies, and routes findings.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the runner's gating rules and the `verify.sh` checks on the skill.
- [context-ship-flow-constraints.md](context-ship-flow-constraints.md) for the ship flow that compares against the shipping record.
