# Workflow Routing

For non-trivial development tasks, use a plan-first workflow: the plan note is written
to the Obsidian vault and explicitly approved by the user before any implementation
begins. Planning always stops for user review. The mechanics live in skills that MUST
be loaded at the right moment — these are blocking requirements, not suggestions.
Every target below ships in this toolkit:

| Moment | Invoke first |
|---|---|
| New work arriving as a brief, ticket reference, or stated task with no plan note yet | `crawl` skill |
| Creating, filling in, updating, or closing out any plan note | `plan-workflow` skill |
| Starting a planning session (incl. pre-scaffolded plan notes) | `plan-workflow` skill |
| Deciding testing level for a feature/bugfix/refactor | `testing-gate` skill |
| Writing or editing code when testing-gate determined tests are required | `test-first` skill |
| Starting execution of an approved plan | `execute-workflow` + `plan-workflow` skills |
| Debugging runtime/integration issues; finishing implementation (doc pass) | `execute-workflow` skill |
| Creating or updating a topic note or stub | `obsidian-topic` command |
| Reviewing a GitLab MR | `gitlab-mr-review` skill |
| (opt-in, not blocking) User asks to grill / elicit requirements for a fuzzy feature, before planning | `grill` skill |
| (opt-in, not blocking) User asks to hand off or write a continuation note | `handoff` skill |
| (opt-in, not blocking) User asks to resolve git merge or rebase conflicts | `resolving-merge-conflicts` skill |
| (opt-in, not blocking) User asks to map, scope, or break down a large multi-part investigation before planning | `wayfinder` skill |
| (opt-in, not blocking) User explicitly invokes the full ticket-to-complete pipeline for a big scope of work, or asks to resume one | `expedition` skill |

The `grill`, `handoff`, `resolving-merge-conflicts`, `wayfinder`, and `expedition` rows are guidance,
not a blocking requirement like the rows above them. Each fires only on an explicit
user request, never on task fuzziness or size the model detects on its own — with two
carve-outs: a `crawl` route the user has confirmed counts as the explicit request for
`wayfinder`, and a confirmed yes at an expedition's grill gate counts as the explicit
request for `grill`. The `crawl` row is the front door for new work: it investigates
the brief and routes to `wayfinder`, `plan-workflow`, or no plan; on routes that
write artifacts the user confirms the route first, while the trivial no-plan route
states its routing in one sentence and proceeds.

Never write or edit a plan note without `plan-workflow` loaded — its frontmatter and
naming rules are a contract that plan-tracking tooling parses, and improvising them
breaks that contract. Keep this discipline for real planned work, not trivial Q&A or
explanation-only sessions.
