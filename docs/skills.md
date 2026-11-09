# Skills

The toolkit ships a set of skills — markdown instructions Claude loads at the moment they apply. Most exist to enforce one discipline: plan before you build, decide testing up front, review before you ship. This page is the reference for the full set, with short screencasts of the ones worth seeing in motion.

These GIFs live in the repo (`docs/media/`) but not in the installed plugin. The marketplace `source` is `./plugins/toolkit`, so only that subtree is pulled into a user's install — the docs and their media stay in GitHub and never bloat anyone's plugin cache.

## The set

A skill whose name ends in `-flow` runs the work for you. A skill whose name ends in `-guide` is the manual a session follows by hand.

| Skill | What it does | Fires when |
|---|---|---|
| `crawl` | Front door for new work: ingests a brief or ticket, validates it against the codebase (recall + explorer), then recommends a route, wayfinder, plan-guide, or no plan, which you confirm before anything is written. The brief shape is `docs/brief-template.md`. On the plan-guide route, when the brief names no ticket, the run options carry the ticket question, and a ticket it creates exists before the plan name is derived. On the plan-guide route it scaffolds the plan note and ends with one plain-text question that offers the plan flow on it, with a `/rename parent-<planName>` line when the session has no parent name. | A session opens with a new piece of work and no plan note exists for it yet. |
| `plan-guide` | Writes a plan note to your Obsidian vault and stops for approval before any implementation. The single source of truth for artifact layout, naming, frontmatter, and the status lifecycle. After approval it asks in plain text whether to run the execute flow here, open a child session for it, or stop: in the child form, which recommends the child and puts `yes` on it, when this session's name starts with `parent-` or the context-sentinel hook has injected its ~200k token nudge, and in the run-here form otherwise. It hands over the child's launch command, which names the child `child-<planName>`. | Creating, filling in, or closing out a plan note; starting a planning session. |
| `plan-flow` | One run from brief to plan note: reads the run options from the plan note or the session cache, asking only for the keys neither has, runs topic recall, then a route check that recommends wayfinder when the recall hits and the brief show several independent workstreams, then, when the brief names no ticket and the work stays in this flow, asks the ticket question in its own call and creates a ticket only on your yes to a shown draft, launches the `plan-builder` workflow (explorer discovery, planner draft, plan-critic pre-mortem with a revise loop, cold red team, optional goal judge), then writes and validates the plan note, in place on a pre-scaffolded note, and sets its status from the result, then prints the note's plain language summary and asks for your approval only when the status is not already approved, and once the plan is approved asks in plain text whether to run the execute flow here, open a child session, or stop. Never writes repo files and never runs git. | You ask for the plan flow by name, with a brief or on a pre-scaffolded plan note: status `planning`, ticket frontmatter, a Brief section, or a brief file beside it, and empty or template Implementation Steps and Validation Steps. Its Brief section is the brief, else that brief file, or else its Objective, Current Context, and ticket. From crawl only when you type `yes` or `run the plan flow` to its plan flow offer, and never on a plan note whose Implementation Steps are filled. |
| `execution-guide` | Execution mechanics after a plan is approved: run topic recall at start (recall reads the vault and the repo's docs), delegate to worker agents, report progress in a fixed format, run the doc-update pass, debug with runtime evidence. | Starting execution of an approved plan; debugging a runtime or integration issue. |
| `execute-flow` | One run that executes an approved plan note end to end: reads the run options from the plan note or the session cache, asking only for the keys neither has, then asks nothing. Runs `seat-check.sh` and, when another live session holds the main checkout, the main checkout holds changes, or a run from an approved note or from Mission Control's start-work finds the main checkout on `main`, `master`, its default branch, or a detached HEAD, opens a worktree with no question, named after the plan name, and runs the repo's install step there. It also opens one when the note names a branch and the main checkout sits on another. Under mr or merge, a plan branch that exists nowhere is cut under the name the note records with `git worktree add -b`, and under none EnterWorktree creates `worktree-<planName>`. The install step is: by default the lockfiles' install commands, with Composer run in the Warden `php-fpm` container when the main checkout's `.env` names a Warden environment and `npm ci` on the host, or the `Worktree install:` line of the main checkout's CLAUDE.md as an override. A rerun after a failed install enters the worktree that run left behind. A session already inside a worktree the plan note does not record adopts it when it is on the plan's branch. When EnterWorktree is absent or refused, or the install fails, it stops with a report. A rerun, or a run whose seat check could not run, stops on `main`, `master`, the repo's default branch, or a detached HEAD and hands you the branch command to run, runs on the branch check alone in a repo with no origin remote, and hands you `git remote set-head origin --auto` when `origin/HEAD` is missing. It stops when the tree holds changes that are not the slice, and a rerun of a blocked run continues over the paths that run recorded from the tree. It runs topic recall, moves the note to in-progress, and launches the `execute-runner` workflow (one implementer per Implementation Step, the plan's Validation Steps with one fix round, deferring a step that needs the running local stack, or carries `[e2e]`, to the seat when the run sits in a worktree, a `review-mr` panel chosen by the changed paths that returns scored findings and at most five unreproduced nits, fix rounds over every reproduced finding, a cold read, and the Doc Update Pass and the remember pass when nothing blocked). It records the result on the note, runs the consent gate with every repo doc proposal declined and saves each proposal beside the plan note, settles each reproduced finding by its recommended option (fix now, or leave it when the finding maps to an Assumption or Risk), records each unreproduced finding for review, and closes with a report. Only a run with nothing blocked, no held finding, and no held Validation Step gets a commit suggestion. A blocked run's report opens with the blocked reasons and the note stays in-progress for a rerun. On a note whose deferred Validation Steps wait for the seat, a session in the main checkout runs the seat run, and a session inside the plan's worktree first leaves it with ExitWorktree keep when no other session holds the main checkout: it checks the plan branch out in a free, clean main checkout, runs the steps against the running local stack with the worktree run's baseline, reviews every commit since the last passing seat run, commits its own fixes under mr or merge, and restores the branch the main checkout was on. A lockfile change, or a path under a `Seat run guard:` line in the main checkout's CLAUDE.md, stops the seat run before the switch, and a repo lists there any other dependency file or a migration directory. A run that stays in the main checkout stops when its branch differs from the note's. When the ask names a parent session, it reports there by message after every stop and at the close, then leaves its worktree with ExitWorktree keep, and a child with no step deferred to the seat waits for the parent's dispatch. A message from that parent whose first line reads `<planName>: run the execute flow` or `<planName>: run the ship flow` starts that flow on the same note, because the user's launch prompt grants it, within the note's ceiling only. Mutates git only as the git-safety Flows section lists: the worktree, and the seat run's switches, fix commit, and restore, all paste-ready under none. Otherwise it runs read-only git only through its agents. | You ask for the execute flow by name on an approved plan note, on an in-progress note that Mission Control's start-work moved there, while its last session entry still begins `start-work:`, on an in-progress note it left blocked, mid-run, or adjudicating its findings, or on a note whose deferred Validation Steps wait for the seat run. Replying `run the execute flow here`, or `yes` to the run-here form of the question after a plan approval, counts as asking, and so does a dispatch from the parent session your launch prompt named. Never from crawl. |
| `ship-flow` | One run that carries a reviewed slice toward production: reads the run options from the plan note or the session cache, asking only for the keys neither has, runs in the plan's worktree when the note records one that still exists, reads the host, the tree, and where to resume through one verifier, plus a capture verifier before a commit, prints every external side effect and asks nothing, then launches the `ship-runner` workflow (commit, push, MR or PR, a pipeline watch pinned to the pushed commit with a bounded fix loop, bot review threads worked in at most three rounds per ask after any bot review in progress ends, a merge of that exact commit, a tag, and the cleanup). When a run stops only on a slow pipeline or a bot review that has not landed or is still in progress, it waits in the background and relaunches itself. It stops at the ceiling the note records, and at mr while deferred Validation Steps wait for a seat run that passed on the exact commit it would merge. A command the permission system denies ends the run with a paste-ready handoff. It merges over its own fix commits and over the commits a passing seat run reviewed, but only when a read of each fix commit shows it changed nothing outside the plan's paths and no CI configuration, CI script, or protected path. It refuses a merge over a commit the shipping record and the seat run never saw, an open thread, a stale pipeline that did not run on the commit being merged, a head past the one a seat run passed on, or a requested-changes review. Under merge it then removes the plan's worktree, returns the main checkout to the default branch and fast-forwards it, and deletes the merged branch locally and on origin, each only when its reads at cleanup time prove it safe, and leaves the main checkout on the plan branch while another live session holds it. It closes with a report that names the MR, every commit fixed beyond the plan, and the caveats, and reports to a named parent session by message. The conductor runs no git, and every mutation runs in the runner's agents. | You ask for the ship flow by name after an execute-flow report, or on an in-progress plan note whose branch exists, or the parent session your launch prompt named sends `<planName>: run the ship flow`. Never from crawl. |
| `testing-gate` | Reads `tests` from the plan note or the session cache, and asks once, up front, only when neither has it. | Starting a feature, bugfix, or refactor. |
| `test-first` | The red-green-refactor loop that runs once `testing-gate` has said tests are required. Chains from the gate, never decides the gate itself. | Writing code on a task where tests were required. |
| `grill` | Requirements interview before a plan exists: one question at a time with a recommended answer, self-answers from the code, then writes a glossary to `docs/glossary.md` and ADRs to `docs/decisions/` in the repo. | You explicitly ask to grill, elicit, or interview requirements. |
| `handoff` | Compresses the session into a continuation note in the vault so a second person, or a later session, can pick the work up cold. | You explicitly ask to hand off or write a continuation note. |
| `pre-compact` | Readies a session for compaction: checks that the plan or work note, every promised note, uncommitted changes, and running background tasks are recorded, finishes what is not, writes a state-only compact handoff under 3,000 bytes to the session scratchpad, and answers yes. The session-start hook injects that handoff once after the compaction, followed by the standing rules. Names uncommitted changes in the handoff and never commits them, because committing belongs to the ship flow or you. Never writes a vault file of its own and never compacts the session itself. | You ask whether it is okay or safe to compact, ask to prepare for a compaction, or say pre-compact. Never on a request to hand off, which goes to `handoff`. |
| `resolving-merge-conflicts` | Overview plus side-by-side of every conflict, resolves each hunk by intent, and waits for your confirmation before writing. | You ask for help with a git merge or rebase conflict. |
| `wayfinder` | Turns a large, fuzzy investigation or migration into a mapped set of tickets: aligns with you on outcome and success first, then an issue register, a parent umbrella plan, and one child plan stub per task (each recommended a scoped grill before its own planning). | You ask to map, scope, or break down a big multi-part effort before planning it, or crawl or the plan flow's route check routes here with your confirmation. |
| `gitlab-mr-review` | Multi-dimension MR review: fans out reviewer agents plus MR-specific dimensions whose findings carry a tag, a self-score, and a file:line citation, verifies each dimension's findings with one batched verifier against the local checkout, and reports the confirmed findings by tag and final score with the counts of nits, pre-existing, and dropped findings. | You ask to review a GitLab merge request. |
| `expedition` | The ticket-to-complete pipeline for big, deliberately-committed work: sequences crawl, grill, split decision, planning, execution, and review through recommend-and-confirm gates, with the stage persisted in a vault work note so the effort survives across days. Completion is always your word, never inferred. | You explicitly invoke it, or ask to resume one. Never automatic — committing to the full workflow is your decision. |
| `jira` | Jira ticket-to-brief adapter: fetches a Jira issue via jira-cli and returns a verbatim brief (metadata, full description, comments, issue links) for crawl or expedition to plan from. It creates a ticket only on your yes to a draft it showed, and never edits, transitions, or comments on one. | Crawl's ingest step meets a Jira key or ticket URL, you ask to fetch one directly, or the ticket question's create answer reaches your yes on a Jira draft. |
| `red-team` | Gates an implementation slice's finalization: recommends an adversarial review on a closure signal, runs — on confirmation — the `review-mr` workflow's reviewer/verifier panel over the local uncommitted diff, which splits scored findings into confirmed, nits, pre-existing, refuted, unverified, and dropped, delegates one fix round for the confirmed findings with scoped re-checks, where the nits follow the plan note's `nits` value (under `fix` they ride the round or make their own, under `skip` the report lists them), records each finding's outcome with its scores, runs the doc pass once, runs the remember pass once, which routes facts to repo or vault, and closes with a commit suggestion. | A closure signal ("I'm happy with this", "looks good, let's continue") fires with uncommitted implementation changes present, or you explicitly ask to red team code or a diff. |
| `inversion` | Pre-mortem for a plan, decision, or code fix: up to seven ranked failure causes, a verdict naming the fatal flaw when one exists, a rebuilt plan with walk-away checks, the adversary's view, and one measurable tripwire per failure mode. Never reassures. | You invoke it by name, or ask whether a plan or fix is good, looks right, or is ready to ship. |
| `review-threads` | Works the reviewer threads on a pushed MR or PR (CodeRabbit, Copilot, humans): lists open threads, fixes or pushes back per thread, never comments on threads a fix resolves, reports state, and recommends merge only when every thread is resolved and the pipeline is green. glab for GitLab, gh for GitHub. | You ask to go through or address the review comments on an MR or PR. |
| `incident-investigate` | Root-cause investigation for a production incident: fences scope to the question and items you named, checks that the project's documented evidence sources are reachable before spawning, gathers evidence in parallel with a citation per finding, adjudicates to one verdict with a provenance label, and writes a technical incident note plus a stakeholder summary. Never implements a fix, never mutates production. | You explicitly ask to investigate an incident, or paste a production alert with "find the cause". |

All of the request-triggered skills (`grill`, `handoff`, `pre-compact`, `resolving-merge-conflicts`, `wayfinder`, `expedition`, `review-threads`, `incident-investigate`, `plan-flow`, `execute-flow`, `ship-flow`) fire only on an explicit ask, never on something the model infers on its own, with five narrow carve-outs: a crawl route or a plan-flow route check you confirmed counts as the explicit ask for wayfinder, a confirmed yes at an expedition's grill gate counts as the explicit ask for grill, a typed `yes` or `run the plan flow` to crawl's plan flow offer counts as the explicit ask for plan-flow, a typed `run the execute flow here` or a bare `yes` in the run-here form of the post-approval question counts as the explicit ask for execute-flow, and a message that execute-flow's parent dispatch rule accepts counts as the explicit ask for execute-flow or ship-flow. `inversion` also fires on an evaluative question about a plan or fix ("is this a good plan", "is this ready to ship"), which counts as the ask. `crawl` is the exception in the other direction: it fires automatically on new work (a brief or ticket with no plan note), staying near-silent on trivial work. `red-team` sits between the two: the recommendation fires automatically on a closure signal, but the run itself still waits on your explicit confirmation. An explicit ask to red team a diff skips that gate and counts as the confirmation on its own.

## Example prompts

How to trigger each skill. Some you invoke directly, some fire automatically inside the plan-then-build pipeline.

**Invoke directly:**

- `expedition` — commit a big scope of work to the full guided pipeline:

      Run the expedition on this: <ticket link or brief>.

- `plan-guide` — plan a non-trivial change:

      Let's plan adding rate limiting to the login endpoint.

- `plan-flow` builds a complete plan note from a brief in one run, and fires only when you ask for it by name:

      Run the plan flow on this: add CSV export to the reports page.

- `execute-flow` executes an approved plan note in one run and asks nothing after it reads the run options. When nothing blocked and every entry on the adjudication list is settled, it closes with a commit suggestion that you run yourself. When the run sat in a worktree and deferred steps that need the running local stack, ask for it again from a session started in the main checkout, after the slice is committed, and it runs the seat run. It fires only when you ask for it by name:

      Run the execute flow on the add-csv-export plan.

- `ship-flow` commits, pushes, opens the MR or PR, watches the pipeline, waits in the background on a slow pipeline or a pending bot review, works the bot review threads, merges, tags, and cleans up a slice the execute flow reviewed, stopping at the ceiling the plan note records with no question. It fires only when you ask for it by name, or on its parent session's dispatch:

      Run the ship flow on the add-csv-export plan.

- `grill` — pin down a fuzzy feature before planning:

      Grill me on the new notifications feature before we plan it.

- `wayfinder` — break a large, fuzzy effort into a plan tree:

      Map out migrating the legacy monolith to a modular service before we plan each piece.

- `resolving-merge-conflicts` — a conflicted merge or rebase:

      Help me resolve these merge conflicts.

- `handoff` — snapshot the session for whoever picks it up next:

      Write a handoff note for this session.

- `pre-compact` records the session's state and writes the compact handoff before you compact:

      Is it safe to compact?

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

- `jira` — fires when crawl's ingest step meets a Jira key or ticket URL, when you ask to fetch one directly, or when the ticket question's create answer reaches your yes on a Jira draft. Triggered by, for example:

      Pull in https://<site>.atlassian.net/browse/PROJ-123, we need to plan this.

- `testing-gate` — fires when you start any feature, bugfix, or refactor (after crawl has routed, when both match), and asks once whether tests are required. Triggered by, for example:

      Add a CSV export to the reports page.

- `test-first` — takes over once `testing-gate` decides tests are required, running the red-green-refactor loop as the code is written. No separate prompt.

- `execution-guide` — loads when you start executing an approved plan:

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

Point it at a large, fuzzy effort (a migration, an incident) and it investigates, builds an issue register, then emits a parent umbrella plan plus a child plan stub per task, each ready to flow through `plan-guide` on its own.

![decomposing a large effort into a plan tree](media/wayfinder-demo.gif)

### grill

An explicit request to grill starts a requirements interview: one question at a time, each with a recommended answer, self-answering from the code whatever the code can settle. After a single consent gate it writes a canonical glossary (`docs/glossary.md`) and any ADRs (`docs/decisions/`) into the repo, then hands off to `plan-guide`.

![grilling requirements before a plan](media/grill-demo.gif)
