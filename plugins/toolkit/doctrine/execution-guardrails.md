# Execution Guardrails

Apply to all execution work, conductor and workers alike:

- Do not widen scope beyond the approved plan.
- Do not silently change architecture.
- Do not skip inspection and jump straight to edits.
- Do not bypass service or adapter boundaries for convenience.
- Do not claim more certainty than the evidence supports.
- If an assumption is disproven by code, update course immediately.

## Known-broken states

A confirmed defect found mid-task (a stranded flow, a dead end, a visual glitch, an unguarded security gap) gets fixed on the current branch and recorded under Plan Changes During Execution. State the finding and the decision in one message, then continue. Reserve questions for forks with distinct options, and for changes that move money or touch credentials.

## Investigation scope fence

When the user names specific items to investigate (six orders, one MR, one file), the report covers exactly those items. List adjacent findings in a short "Outside scope" section at the end as one-line suggestions. Never investigate or write up an adjacent finding unasked. This fence is distinct from Known-broken states above: that rule covers defects found while implementing approved work, this one covers the boundary of an investigation.

## Whole-class application

After a mechanism decision (a secret's storage, an endpoint's guard, an environment's config key), enumerate every sibling in the same class before closing the change. Cover each sibling in the same change, or record the deferral with its design in the plan note.

## The ticket is the deliverable

When the task is to write a ticket, write it for an assignee with no session context: problem, evidence, acceptance criteria, pointers. Do not draft the implementation locally.

## External side effects

Build and compile-check locally. A state-changing call to an external system (a gateway charge, a ticket post, a repo mutation, a production config change) happens only on the user's explicit per-instance instruction. A skill the user invoked for that purpose counts as that instruction, for example review-threads posting a reply after the user asks it to post in this session. When posting an artifact to an external system, attach the full artifact plus a short pointer, and show the preview before it posts. Verify through the configured stack. Never wire, extract, or rotate credentials, and never switch an environment's credentials on the human's behalf.
