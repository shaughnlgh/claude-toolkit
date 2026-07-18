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
| `plan-workflow` | Writes a plan note to your Obsidian vault and stops for approval before any implementation. The single source of truth for artifact layout, naming, frontmatter, and the status lifecycle. | Creating, filling in, or closing out a plan note; starting a planning session. |
| `execute-workflow` | Execution mechanics after a plan is approved: delegate to worker agents, report progress in a fixed format, run the doc-update pass, debug with runtime evidence. | Starting execution of an approved plan; debugging a runtime or integration issue. |
| `testing-gate` | Asks once, up front, whether the task needs automated tests or manual verification is enough. | Starting a feature, bugfix, or refactor. |
| `test-first` | The red-green-refactor loop that runs once `testing-gate` has said tests are required. Chains from the gate, never decides the gate itself. | Writing code on a task where tests were required. |
| `grill` | Requirements interview before a plan exists: one question at a time with a recommended answer, self-answers from the code, then writes a `CONTEXT.md` glossary and ADRs into the repo. | You explicitly ask to grill, elicit, or interview requirements. |
| `handoff` | Compresses the session into a continuation note in the vault so a second person, or a later session, can pick the work up cold. | You explicitly ask to hand off or write a continuation note. |
| `resolving-merge-conflicts` | Overview plus side-by-side of every conflict, resolves each hunk by intent, and waits for your confirmation before writing. | You ask for help with a git merge or rebase conflict. |
| `wayfinder` | Turns a large, fuzzy investigation or migration into a mapped set of tickets: an issue register, a parent umbrella plan, and one child plan stub per task. | You ask to map, scope, or break down a big multi-part effort before planning it. |
| `gitlab-mr-review` | Multi-dimension MR review: fans out reviewer agents plus MR-specific dimensions and adversarially verifies every finding against the local checkout. | You ask to review a GitLab merge request. |

All of the request-triggered skills (`grill`, `handoff`, `resolving-merge-conflicts`,
`wayfinder`) fire only on an explicit ask, never on something the model infers on its
own.

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

<!-- demo: drop the recording at docs/media/wayfinder-demo.gif and swap the line below for:
![decomposing a large effort into a plan tree](media/wayfinder-demo.gif) -->

_Demo coming soon._

## Not a skill: the design doctrine

The same batch added `doctrine/design.md` — structural design judgment (deep modules,
clean seams, abstractions that earn their keep). It is not a skill and has no demo,
because it is always-on write-time law rather than a moment-triggered step. It sits
beside `doctrine/conventions.md`: conventions is how code should look, design is how it
should be shaped.
