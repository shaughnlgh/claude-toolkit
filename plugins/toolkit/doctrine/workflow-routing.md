# Workflow Routing

For non-trivial development tasks, use a plan-first workflow: the plan note is written
to the Obsidian vault and explicitly approved by the user before any implementation
begins. Planning always stops for user review. The mechanics live in skills that MUST
be loaded at the right moment — these are blocking requirements, not suggestions.
Every target below ships in this toolkit:

| Moment | Invoke first |
|---|---|
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

The `grill`, `handoff`, `resolving-merge-conflicts`, and `wayfinder` rows are guidance,
not a blocking requirement like the rows above them. Each fires only on an explicit
user request, never on task fuzziness or size the model detects on its own.

Never write or edit a plan note without `plan-workflow` loaded — its frontmatter and
naming rules are a contract that plan-tracking tooling parses, and improvising them
breaks that contract. Keep this discipline for real planned work, not trivial Q&A or
explanation-only sessions.
