# Skills

The toolkit ships a set of skills — markdown instructions Claude loads at the moment they apply. Most exist to enforce one discipline: plan before you build, decide testing up front, review before you ship. This page is the reference for the full set, with short screencasts of the ones worth seeing in motion.

These GIFs live in the repo (`docs/media/`) but not in the installed plugin. The marketplace `source` is `./plugins/toolkit`, so only that subtree is pulled into a user's install — the docs and their media stay in GitHub and never bloat anyone's plugin cache.

## The set

| Skill | What it does | Fires when |
|---|---|---|
| `crawl` | Front door for new work: ingests a brief or ticket, validates it against the codebase (recall + explorer), then recommends a route — wayfinder, plan-workflow, or no plan — which you confirm before anything is written. | A session opens with a new piece of work and no plan note exists for it yet. |
| `plan-workflow` | Writes a plan note to your Obsidian vault and stops for approval before any implementation. The single source of truth for artifact layout, naming, frontmatter, and the status lifecycle. | Creating, filling in, or closing out a plan note; starting a planning session. |
| `plan-flow` | One run from brief to plan note: asks the git-permission question unless an earlier flow in the session recorded the answer, runs topic recall, launches the `plan-flow` workflow (explorer discovery, planner draft, plan-critic pre-mortem with a revise loop, cold red team, optional goal judge), then writes and validates the plan note and sets its status from the result. Never writes repo files and never runs git. | You ask for the plan flow by name. Never from crawl, and never on an existing plan note. |
| `execute-workflow` | Execution mechanics after a plan is approved: run topic recall at start (recall reads the vault and the repo's docs), delegate to worker agents, report progress in a fixed format, run the doc-update pass, debug with runtime evidence. | Starting execution of an approved plan; debugging a runtime or integration issue. |
| `testing-gate` | Asks once, up front, whether the task needs automated tests or manual verification is enough. | Starting a feature, bugfix, or refactor. |
| `test-first` | The red-green-refactor loop that runs once `testing-gate` has said tests are required. Chains from the gate, never decides the gate itself. | Writing code on a task where tests were required. |
| `grill` | Requirements interview before a plan exists: one question at a time with a recommended answer, self-answers from the code, then writes a glossary to `docs/glossary.md` and ADRs to `docs/decisions/` in the repo. | You explicitly ask to grill, elicit, or interview requirements. |
| `handoff` | Compresses the session into a continuation note in the vault so a second person, or a later session, can pick the work up cold. | You explicitly ask to hand off or write a continuation note. |
| `resolving-merge-conflicts` | Overview plus side-by-side of every conflict, resolves each hunk by intent, and waits for your confirmation before writing. | You ask for help with a git merge or rebase conflict. |
| `wayfinder` | Turns a large, fuzzy investigation or migration into a mapped set of tickets: aligns with you on outcome and success first, then an issue register, a parent umbrella plan, and one child plan stub per task (each recommended a scoped grill before its own planning). | You ask to map, scope, or break down a big multi-part effort before planning it, or crawl routes here with your confirmation. |
| `gitlab-mr-review` | Multi-dimension MR review: fans out reviewer agents plus MR-specific dimensions and adversarially verifies every finding against the local checkout. | You ask to review a GitLab merge request. |
| `expedition` | The ticket-to-complete pipeline for big, deliberately-committed work: sequences crawl, grill, split decision, planning, execution, and review through recommend-and-confirm gates, with the stage persisted in a vault work note so the effort survives across days. Completion is always your word, never inferred. | You explicitly invoke it, or ask to resume one. Never automatic — committing to the full workflow is your decision. |
| `jira` | Read-only ticket-to-brief adapter: fetches a Jira issue via jira-cli and returns a verbatim brief (metadata, full description, comments, issue links) for crawl or expedition to plan from. | Crawl's ingest step meets a Jira key or ticket URL, or you ask to fetch one directly. |
| `red-team` | Gates an implementation slice's finalization: recommends an adversarial review on a closure signal, runs — on confirmation — the `review-mr` workflow's reviewer/verifier panel over the local uncommitted diff, delegates fixes for confirmed findings with scoped re-checks, runs the doc pass once, runs the remember pass once, which routes facts to repo or vault, and closes with a commit suggestion. | A closure signal ("I'm happy with this", "looks good, let's continue") fires with uncommitted implementation changes present, or you explicitly ask to red team code or a diff. |
| `inversion` | Pre-mortem for a plan, decision, or code fix: up to seven ranked failure causes, a verdict naming the fatal flaw when one exists, a rebuilt plan with walk-away checks, the adversary's view, and one measurable tripwire per failure mode. Never reassures. | You invoke it by name, or ask whether a plan or fix is good, looks right, or is ready to ship. |
| `review-threads` | Works the reviewer threads on a pushed MR or PR (CodeRabbit, Copilot, humans): lists open threads, fixes or pushes back per thread, never comments on threads a fix resolves, reports state, and recommends merge only when every thread is resolved and the pipeline is green. glab for GitLab, gh for GitHub. | You ask to go through or address the review comments on an MR or PR. |
| `incident-investigate` | Root-cause investigation for a production incident: fences scope to the question and items you named, checks that the project's documented evidence sources are reachable before spawning, gathers evidence in parallel with a citation per finding, adjudicates to one verdict with a provenance label, and writes a technical incident note plus a stakeholder summary. Never implements a fix, never mutates production. | You explicitly ask to investigate an incident, or paste a production alert with "find the cause". |

All of the request-triggered skills (`grill`, `handoff`, `resolving-merge-conflicts`, `wayfinder`, `expedition`, `review-threads`, `incident-investigate`, `plan-flow`) fire only on an explicit ask, never on something the model infers on its own — with two narrow carve-outs: a crawl route you confirmed counts as the explicit ask for wayfinder, and a confirmed yes at an expedition's grill gate counts as the explicit ask for grill. `inversion` also fires on an evaluative question about a plan or fix ("is this a good plan", "is this ready to ship"), which counts as the ask. `crawl` is the exception in the other direction: it fires automatically on new work (a brief or ticket with no plan note), staying near-silent on trivial work. `red-team` sits between the two: the recommendation fires automatically on a closure signal, but the run itself still waits on your explicit confirmation — an explicit ask to red team a diff skips that gate and counts as the confirmation on its own.

## Example prompts

How to trigger each skill. Some you invoke directly, some fire automatically inside the plan-then-build pipeline.

**Invoke directly:**

- `expedition` — commit a big scope of work to the full guided pipeline:

      Run the expedition on this: <ticket link or brief>.

- `plan-workflow` — plan a non-trivial change:

      Let's plan adding rate limiting to the login endpoint.

- `plan-flow` builds a complete plan note from a brief in one run, and fires only when you ask for it by name:

      Run the plan flow on this: add CSV export to the reports page.

- `grill` — pin down a fuzzy feature before planning:

      Grill me on the new notifications feature before we plan it.

- `wayfinder` — break a large, fuzzy effort into a plan tree:

      Map out migrating the legacy monolith to a modular service before we plan each piece.

- `resolving-merge-conflicts` — a conflicted merge or rebase:

      Help me resolve these merge conflicts.

- `handoff` — snapshot the session for whoever picks it up next:

      Write a handoff note for this session.

- `gitlab-mr-review` — review a merge request:

      Review this GitLab MR: https://gitlab.example.com/group/repo/-/merge_requests/123

- `inversion` — stress-test a plan or fix before committing to it:

      Is this a good plan? Invert it before we go ahead.

- `review-threads` — work the review comments after a push:

      Go through the CodeRabbit and Copilot threads on this MR.

- `incident-investigate` — find the cause of a production incident:

      Investigate this incident: orders 1001, 1002, and 1003 were captured twice. Find the cause.

**Fire automatically inside a flow** (you don't prompt them by name):

- `crawl` — fires first when new work arrives with no plan note, validates the brief against the repo, and routes it (near-silently for trivial work). Triggered by, for example:

      Here's the ticket: <link>. We need bulk order editing in the admin.

- `jira` — fires when crawl's ingest step meets a Jira key or ticket URL, or you ask to fetch one directly. Triggered by, for example:

      Pull in https://<site>.atlassian.net/browse/PROJ-123, we need to plan this.

- `testing-gate` — fires when you start any feature, bugfix, or refactor (after crawl has routed, when both match), and asks once whether tests are required. Triggered by, for example:

      Add a CSV export to the reports page.

- `test-first` — takes over once `testing-gate` decides tests are required, running the red-green-refactor loop as the code is written. No separate prompt.

- `execute-workflow` — loads when you start executing an approved plan:

      The plan is approved, go ahead and implement it.

- `red-team` — fires when a closure signal arrives with uncommitted implementation changes, or you explicitly ask to red team a diff. Triggered by, for example:

      I'm happy with this, let's continue.

## In action

### test-first

`testing-gate` asks its one question. You say tests are required, and `test-first` takes over: a failing test first, run red, minimum code to pass, run green, refactor with the test still green. It uses the repo's existing test setup rather than inventing one.

![test-first red-green-refactor demo](media/test-first-demo.gif)

### resolving-merge-conflicts

The overview helper runs first to show the shape of the conflict (files, hunks, lines per side). Then each hunk is resolved by working out what each side intended, and nothing is written until you confirm. It never runs `git add` or commits — that stays with you.

![resolving a merge conflict by intent](media/merge-conflict-demo.gif)

### handoff

One explicit ask writes a single continuation note into the vault — into the active plan's directory if one exists, otherwise a `_handoffs/` bucket — capturing what was decided, what is done, what remains, and the next concrete step. It never touches the project repo.

![writing a handoff note to the vault](media/handoff-demo.gif)

### wayfinder

Point it at a large, fuzzy effort (a migration, an incident) and it investigates, builds an issue register, then emits a parent umbrella plan plus a child plan stub per task, each ready to flow through `plan-workflow` on its own.

![decomposing a large effort into a plan tree](media/wayfinder-demo.gif)

### grill

An explicit request to grill starts a requirements interview: one question at a time, each with a recommended answer, self-answering from the code whatever the code can settle. After a single consent gate it writes a canonical glossary (`docs/glossary.md`) and any ADRs (`docs/decisions/`) into the repo, then hands off to `plan-workflow`.

![grilling requirements before a plan](media/grill-demo.gif)
