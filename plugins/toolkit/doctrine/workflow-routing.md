# Workflow Routing

For non-trivial development tasks, use a plan-first workflow: the plan note is written to the vault and explicitly approved by the user before any implementation begins. Planning always stops for user review. The plan flow's `approveIf` gate is the one exception, because it may set a plan to approved without a user review, and the human approval rule still governs execution. The mechanics live in skills that MUST be loaded at the right moment — these are blocking requirements, not suggestions. Every target below ships in this toolkit:

| Moment | Invoke first |
|---|---|
| New work arriving as a brief, ticket reference, or stated task with no plan note yet | `crawl` skill |
| Creating, filling in, updating, or closing out any plan note | `plan-guide` skill |
| Starting a planning session, including on a pre-scaffolded plan note the user plans by hand rather than through the plan flow by name | `plan-guide` skill |
| Deciding testing level for a feature/bugfix/refactor | `testing-gate` skill |
| Writing or editing code when testing-gate determined tests are required | `test-first` skill |
| Starting execution of an approved plan | `execution-guide` + `plan-guide` skills |
| Debugging runtime/integration issues; finishing implementation (doc pass) | `execution-guide` skill |
| User signals a completed implementation slice (recommend red team, run only on confirmation) | `red-team` skill |
| Creating or updating a topic note or stub | `topic` command |
| Reviewing a GitLab MR | `gitlab-mr-review` skill |
| (opt-in, not blocking) User asks to grill / elicit requirements for a fuzzy feature, before planning, a crawl's grill check loads it on a confirmed wayfinder route, or a planning flow loads it for its planning grill | `grill` skill |
| (opt-in, not blocking) User asks to hand off or write a continuation note | `handoff` skill |
| (opt-in, not blocking) User asks whether it is okay to compact, or asks to prepare for a compaction | `pre-compact` skill |
| (opt-in, not blocking) User asks to resolve git merge or rebase conflicts | `resolving-merge-conflicts` skill |
| (opt-in, not blocking) User asks to map, scope, or break down a large multi-part investigation before planning | `wayfinder` skill |
| (opt-in, not blocking) User explicitly invokes the full ticket-to-complete pipeline for a big scope of work, or asks to resume one | `expedition` skill |
| (opt-in, not blocking) User asks whether a plan, decision, or fix is good, or invokes a pre-mortem by name | `inversion` skill |
| (opt-in, not blocking) User asks to work through review threads on a pushed MR or PR | `review-threads` skill |
| (opt-in, not blocking) User asks to investigate a production incident or pastes an alert with "find the cause" | `incident-investigate` skill |
| (opt-in, not blocking) User asks for the plan flow or the plan workflow by name, with a brief or on a pre-scaffolded plan note | `plan-flow` skill |
| (opt-in, not blocking) User asks for the execute flow or the execute workflow by name on an approved plan note | `execute-flow` skill |
| (opt-in, not blocking) User asks for the ship flow by name after an execute-flow report, or on an in-progress plan note with a built branch, or on a parent dispatch | `ship-flow` skill |

The `grill`, `handoff`, `pre-compact`, `resolving-merge-conflicts`, `wayfinder`, `expedition`, `inversion`, `review-threads`, `incident-investigate`, `plan-flow`, `execute-flow`, and `ship-flow` rows are guidance, not a blocking requirement like the rows above them. Each fires only on an explicit user request, never on task fuzziness or size the model detects on its own. Seven carve-outs apply: a `crawl` route or a `plan-flow` route check the user has confirmed counts as the explicit request for `wayfinder`, a confirmed yes at an expedition's grill gate counts as the explicit request for `grill`, a confirmed `crawl` wayfinder route counts as the explicit request for `grill`, which the crawl's grill check then runs inline, a planning flow that reaches its planning grill step, in `plan-flow` section 4 or the `plan-guide` Planning Workflow, counts as the explicit request for `grill`, which the flow then runs inline, a typed reply to the plan flow offer that ends `crawl` section 4 that picks the plan flow, `run the plan flow` or a bare `yes`, counts as the explicit request for `plan-flow`, and a typed reply to the post-approval question in `plan-guide` § After approval that picks running here, `run the execute flow here` or a bare `yes` in the run-here form of that question, counts as the explicit request for `execute-flow`, and a message that the execute-flow section 1 parent dispatch rule accepts counts as the explicit request for `execute-flow` or `ship-flow`. The plan flow, the execute flow, and the ship flow run only on an explicit ask, and a `crawl` route never fires one on its own. An evaluative question about a plan or fix ("is this a good plan", "is this ready to ship") counts as the explicit request for `inversion`. When uncommitted implementation changes are present, a closure-shaped utterance routes to `red-team`, not `inversion`. The `crawl` row is the front door for new work: it investigates the brief and routes to `wayfinder`, `plan-guide`, or no plan; on routes that write artifacts the user confirms the route first, while the trivial no-plan route states its routing in one sentence and proceeds.

The `red-team` row is blocking for the recommendation only, not the run — at a closure signal, saying so in one line is mandatory, while the review itself runs only on the user's explicit confirmation; an explicit red-team request invokes the skill directly at any time, bypassing the recommendation. At slice closure, `red-team` owns finalization and invokes `execution-guide`'s doc pass exactly once after its own fixes, then the `topic` command's remember pass once after it; the finishing-implementation row above continues to cover doc-pass mechanics outside a red-teamed closure.

Never write or edit a plan note without `plan-guide` loaded — its frontmatter and naming rules are a contract that plan-tracking tooling parses, and improvising them breaks that contract. Keep this discipline for real planned work, not trivial Q&A or explanation-only sessions.
