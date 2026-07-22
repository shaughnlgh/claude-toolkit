# Skills

The toolkit ships a set of skills — markdown instructions Claude loads at the moment
they apply. Most exist to enforce one discipline: plan before you build, decide testing
up front, review before you ship. This page is the reference for the full set, with
short screencasts of the ones worth seeing in motion.

These GIFs live in the repo (`docs/media/`) but not in the installed plugin. The
marketplace `source` is `./plugins/toolkit`, so only that subtree is pulled into a
user's install — the docs and their media stay in GitHub and never bloat anyone's
plugin cache.

## The set

| Skill | What it does | Fires when |
|---|---|---|
| `crawl` | Front door for new work: ingests a brief or ticket, validates it against the codebase (recall + explorer), then recommends a route — wayfinder, plan-workflow, or no plan — which you confirm before anything is written. | A session opens with a new piece of work and no plan note exists for it yet. |
| `plan-workflow` | Writes a plan note to your Obsidian vault and stops for approval before any implementation. The single source of truth for artifact layout, naming, frontmatter, and the status lifecycle. | Creating, filling in, or closing out a plan note; starting a planning session. |
| `execute-workflow` | Execution mechanics after a plan is approved: delegate to worker agents, report progress in a fixed format, run the doc-update pass, debug with runtime evidence. | Starting execution of an approved plan; debugging a runtime or integration issue. |
| `testing-gate` | Asks once, up front, whether the task needs automated tests or manual verification is enough. | Starting a feature, bugfix, or refactor. |
| `test-first` | The red-green-refactor loop that runs once `testing-gate` has said tests are required. Chains from the gate, never decides the gate itself. | Writing code on a task where tests were required. |
| `grill` | Requirements interview before a plan exists: one question at a time with a recommended answer, self-answers from the code, then writes a `CONTEXT.md` glossary and ADRs into the repo. | You explicitly ask to grill, elicit, or interview requirements. |
| `handoff` | Compresses the session into a continuation note in the vault so a second person, or a later session, can pick the work up cold. | You explicitly ask to hand off or write a continuation note. |
| `resolving-merge-conflicts` | Overview plus side-by-side of every conflict, resolves each hunk by intent, and waits for your confirmation before writing. | You ask for help with a git merge or rebase conflict. |
| `wayfinder` | Turns a large, fuzzy investigation or migration into a mapped set of tickets: aligns with you on outcome and success first, then an issue register, a parent umbrella plan, and one child plan stub per task (each recommended a scoped grill before its own planning). | You ask to map, scope, or break down a big multi-part effort before planning it, or crawl routes here with your confirmation. |
| `gitlab-mr-review` | Multi-dimension MR review: fans out reviewer agents plus MR-specific dimensions and adversarially verifies every finding against the local checkout. | You ask to review a GitLab merge request. |
| `expedition` | The ticket-to-complete pipeline for big, deliberately-committed work: sequences crawl, grill, split decision, planning, execution, and review through recommend-and-confirm gates, with the stage persisted in a vault work note so the effort survives across days. Completion is always your word, never inferred. | You explicitly invoke it, or ask to resume one. Never automatic — committing to the full workflow is your decision. |

All of the request-triggered skills (`grill`, `handoff`, `resolving-merge-conflicts`,
`wayfinder`, `expedition`) fire only on an explicit ask, never on something the model
infers on its own — with two narrow carve-outs: a crawl route you confirmed counts as
the explicit ask for wayfinder, and a confirmed yes at an expedition's grill gate
counts as the explicit ask for grill. `crawl` is the exception in the other
direction: it fires automatically on new work (a brief or ticket with no plan note),
staying near-silent on trivial work.

## Example prompts

How to trigger each skill. Some you invoke directly, some fire automatically inside the
plan-then-build flow.

**Invoke directly:**

- `expedition` — commit a big scope of work to the full guided pipeline:

      Run the expedition on this: <ticket link or brief>.

- `plan-workflow` — plan a non-trivial change:

      Let's plan adding rate limiting to the login endpoint.

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

**Fire automatically inside a flow** (you don't prompt them by name):

- `crawl` — fires first when new work arrives with no plan note, validates the brief
  against the repo, and routes it (near-silently for trivial work). Triggered by, for
  example:

      Here's the ticket: <link>. We need bulk order editing in the admin.

- `testing-gate` — fires when you start any feature, bugfix, or refactor (after crawl
  has routed, when both match), and asks once
  whether tests are required. Triggered by, for example:

      Add a CSV export to the reports page.

- `test-first` — takes over once `testing-gate` decides tests are required, running the
  red-green-refactor loop as the code is written. No separate prompt.

- `execute-workflow` — loads when you start executing an approved plan:

      The plan is approved, go ahead and implement it.

## In action

### test-first

`testing-gate` asks its one question. You say tests are required, and `test-first`
takes over: a failing test first, run red, minimum code to pass, run green, refactor
with the test still green. It uses the repo's existing test setup rather than inventing
one.

![test-first red-green-refactor demo](media/test-first-demo.gif)

### resolving-merge-conflicts

The overview helper runs first to show the shape of the conflict (files, hunks, lines
per side). Then each hunk is resolved by working out what each side intended, and
nothing is written until you confirm. It never runs `git add` or commits — that stays
with you.

![resolving a merge conflict by intent](media/merge-conflict-demo.gif)

### handoff

One explicit ask writes a single continuation note into the vault — into the active
plan's directory if one exists, otherwise a `_handoffs/` bucket — capturing what was
decided, what is done, what remains, and the next concrete step. It never touches the
project repo.

![writing a handoff note to the vault](media/handoff-demo.gif)

### wayfinder

Point it at a large, fuzzy effort (a migration, an incident) and it investigates,
builds an issue register, then emits a parent umbrella plan plus a child plan stub per
task, each ready to flow through `plan-workflow` on its own.

![decomposing a large effort into a plan tree](media/wayfinder-demo.gif)

### grill

An explicit request to grill starts a requirements interview: one question at a time,
each with a recommended answer, self-answering from the code whatever the code can
settle. After a single consent gate it writes a canonical glossary (`CONTEXT.md`) and
any ADRs into the repo, then hands off to `plan-workflow`.

![grilling requirements before a plan](media/grill-demo.gif)
