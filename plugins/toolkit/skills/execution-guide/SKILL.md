---
name: execution-guide
description: >-
  MANDATORY companion for execution work. Invoke when starting to execute an approved
  plan, and when debugging runtime/integration issues or finishing implementation work.
  Contains the execution workflow steps, progress report format, the doc update pass
  (run before declaring any task done), and the runtime-evidence debugging method.
  Also invoke plan-guide at execution start for the plan note spec, status
  lifecycle, and session recording rules. A request naming the execute flow or the
  execute workflow goes to the execute-flow skill, whose runner reads this guide's Doc
  Update Pass. Also invoke when crawl hands off a direct route, or a session opens a
  plan note whose route is direct-drive or direct-chain: the Direct route section holds
  its steps, its step lines, its drive and chain modes and its closing record.
---

# Execution Guide

This skill holds the execution-time mechanics. The always-loaded invariants (orchestration rules, execution guardrails, git safety, validation honesty) live in the toolkit's CLAUDE.md doctrine and your global config. The plan note spec, status lifecycle, session recording, and session closure live in the `plan-guide` skill — invoke that too at execution start.

## Execution Workflow

After plan approval and explicit user instruction to execute:

1. Read the approved plan from the vault plan directory.
2. Recall vault topics and repo docs: run `python3 <plugin-root>/scripts/topic-recall.py --repo <repo basename> --repo-root <repo root> <plan name and Objective key terms>`. `<plugin-root>` is `../..` from this skill's base directory, the directory that holds this SKILL.md, resolved to an absolute path, so a `--plugin-dir` session runs the loaded copy's scripts. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/toolkit:override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. Recall reads the vault topics and the repo's own `docs/` together. Read the top hits of both sources, and validate each before relying on it (topic command, § Freshness and validation). Carry the recalled facts into every worker brief as Known evidence. Keep every worker's Topic note material return for the remember pass.
3. Re-read the relevant docs and project rules.
4. Main chat acts as supervisor only. Delegate all implementation and verification to worker agents. Do not edit implementation files or run implementation commands directly.
5. Prefer the `implementer` subagent for execution work and the `verifier` for completion checks.
6. Break work into bounded delegated tasks that map back to the plan.
7. Inspect worker results against the plan.
8. Check for knock-on impact in the project's high-risk areas.
9. Have workers run relevant verification.
10. If the actual worker model differs from the requested model and that is visible, report it.
11. Report progress and residual risk.
12. When execution surfaces an idea, requirement, or risk that belongs to a different phase of a multi-part effort, write it into the child plan stub that owns it (Open Questions or Current Context) at the moment it surfaces, and say so. Deferred ideas that live only in conversation get lost. Stub edits go through plan-guide's mechanics: atomic vault write, then validate-plan.py on the edited stub.

### Build minimal

The plan says what to build; build the least that satisfies it. The subagent-rules hook injects the write-time rules at spawn, but doctrine itself still does not travel on its own, so pass task-relevant doctrine sections down in every implementation delegation, following the handoff template in `<plugin-root>/doctrine/orchestration.md`: shortest working diff, no unrequested abstractions, reuse before adding, and trace and grep the callers before changing a shared function. Prefer deleting code to adding it. Mark any deliberate shortcut with a greppable `TODO(author):` comment naming the ceiling and the upgrade path. See `<plugin-root>/doctrine/minimalism.md`.

### Progress format

```
### Current step
`<step number and purpose>`

### Files inspected
- `<path>`

### Files changed
- `<path>` — `<what changed>`

### Checks performed
- `<what was verified>`

### Notes
- `<risk, follow-up, or constraint>`
```

## Slice Finalization

When the user signals a completed implementation slice, the `red-team` skill (`<plugin-root>/skills/red-team/SKILL.md`) owns finalization: it recommends the adversarial review, runs it on confirmation, and ends with a commit suggestion. It invokes this skill's Doc Update Pass once, after its fixes, and runs the remember pass once after the doc pass. On a direct route note the Direct route section below owns that order, and red-team ends after its cold read.

## Doc Update Pass

Treat docs as part of the change, not an afterthought. When implementation changes architecture, conventions, contracts, workflow, OR the set of files / modules / commands / options that a doc enumerates, update the affected docs in the same changeset.

Concrete triggers — if you do any of these, find and update the doc that describes it (this list is illustrative, not exhaustive):

- Add, remove, or rename a file, module, class, or function that appears in a documented file tree, module inventory, or API list.
- Change a command, flag, config key, env var, or default that a doc records.
- Change a public contract, schema, route, event, or naming convention a doc describes.

Catch drift reliably — before declaring a task done:

- Grep the `docs/` tree (and `README`, plus repo-local `CLAUDE.md` / `AGENTS.md` / `.claude/rules/` where present) for the names of the files, symbols, commands, or options you added, removed, or renamed. If a doc references the area you touched, update it in the same changeset.
- If the invalidated doc lives in a distributed rules slice (a config plugin) rather than in this repo, it cannot ride this changeset: raise the change against the config repo in the same working session, and say so in your report — never let a distributed doc drift silently.
- Identify affected docs explicitly; do not assume "code-only" until you have checked.
- If a doc update is genuinely deferred, state the debt explicitly rather than leaving it silent.
- Do not let docs drift behind implementation.

Each project defines its commonly impacted docs and any project-specific doc-update triggers in its `01-project-core.md` / `01-project-details.md` or equivalent. Honor those in addition to the triggers above.

## Direct route

A direct route builds work that the user chose at `crawl`'s route question to build without a plan first. The plan note is its one record. Its `route` frontmatter value is `direct-drive` or `direct-chain` (`plan-guide` § Required plan frontmatter), the route answer is the user's go-ahead for the build, and the note needs no filled Implementation Steps and no approval. The lead runs `direct-drive`, and a `chain` worker session runs `direct-chain`. `crawl` section 4 hands off here for `direct-drive`, and so does every session that opens a `direct-drive` note. A `chain` worker session comes here on its own `direct-chain` note. A lead that opens a `direct-chain` note follows Resume below and runs no step. Load `plan-guide` for every note write, write by its atomic write rule, and run `validate-plan.py` after each write, requiring exit 0. The session that runs the steps runs every step through agents and the review workflow. It edits no file itself and starts no worker session for the steps.

### Steps

The steps run in this order. Each runs the pass that already exists, never a shortened version of it.

1. `build`: first, one `toolkit:verifier` runs `git -c core.quotePath=false status --porcelain -uall -- ':(exclude,top).claude/worktrees/'` and returns the output verbatim. When it lists any path, name each path and stop in both modes until the user commits it or sets it aside, because the closing record stages every changed path in the tree. Then run the git-safety branch check, which creates the work branch before the first edit when HEAD is the base or a detached tag. When HEAD is on any other branch, name that branch and ask in one plain-text question whether to build on it or on a fresh branch from the base, which chain mode stops for too, because the ship flow ships the whole branch. Record the branch the build runs on as the note's `branch`. When `pwd -P` sits under `<main>/.claude/worktrees/`, also record `Seat: worktree <path>` under Plan Changes During Execution, so the ship flow runs there. The direct route opens no worktree itself. Then delegate the change to one `toolkit:implementer` with the brief, the crawl's evidence from the note, and the Build minimal rules above. Under `tests: required` the brief tells it to follow the `test-first` skill (`<plugin-root>/skills/test-first/SKILL.md`). Under `tests: manual` it adds no test.
2. `tests`: one `toolkit:verifier` runs the test command that the repo's rules or README name, with stdin from `/dev/null`, and returns the command, its exit code and each failing name. When the repo names no test command, record `Step done: tests: the repo names no test command`.
3. `red team`: load the `red-team` skill (`<plugin-root>/skills/red-team/SKILL.md`) and run its steps 2 to 6: the review, its one fix round and the cold read. The user's yes to this step's offer in drive mode, or the chain mode route answer, is the confirmation that its step 1 requires. Its steps 7, 7b and 8 do not run inside this step. Print in plain text what its step 8 report would carry: each `dead` dimension, the `preExisting` entries, the `dropped` count and reasons, the nits that `nits: skip` leaves, and the residual-risk line. A non-empty `dead` fails the step, because a dimension whose reviewer died did not review the slice.
4. `check`: under `e2e: required`, one `toolkit:browser-driver` checks the change against the running local stack and returns what it saw. Under `e2e: skip` the check is the user's own: say in two or three lines what to look at, and take the user's typed result.
5. `docs`: the Doc Update Pass above, once, through one `toolkit:implementer`, as `red-team` step 7 runs it.
6. `remember`: the remember pass as `red-team` step 7b runs it, once, with the cumulative diff recaptured by that skill's step 2 method and its `Remember:` line recorded under Plan Changes During Execution.

### Step lines

The state of each step is one line under Plan Changes During Execution, written as soon as the state is known:

    Step done: <step>: <evidence>
    Step skipped: <step>: "<the user's words>"
    Step later: <step>: "<the user's words>"

After each step whose agents change the tree, write each path they returned as its own `Changed path: <path>` line under Plan Changes During Execution.

`<step>` is `build`, `tests`, `red team`, `check`, `docs` or `remember`. `<evidence>` is one line: the changed file count for `build`, the command and its exit code for `tests`, the panel, the diff hash and the count of fixed findings for `red team`, the user's words or the browser result for `check`, the docs changed or `no doc needed` for `docs`, and the `Remember:` line for `remember`. A step with no line is owed. The last line for a step is its state. Only the user's typed words skip a step or move it to later, and the line quotes them. The lead never skips, drops or reorders a step on its own judgment. A step that fails gets no line and stays owed. A skipped step is never offered or raised again. A later step is raised once more before the ship question, as Closing record below states. When the user skips `remember`, also record `Remember: skipped by the user: "<the user's words>"`, because the ship flow and `validate-plan.py` complete a merged note only with a `Remember:` line. A `remember` step left for later records no `Remember:` line, so the note stays open, as it does under a `Remember pass owed:` line.

### Drive mode

Under `route: direct-drive`, after every step, print these two lines and one question in plain text, and end the turn. After a step that failed, print `Failed: <step>: <reason>` above them, so the offer never reads as a first offer:

    Done: <each done step, and each skipped step as "<step> (skipped)", or none>
    Owed: <each owed step in order, and each later step as "<step> (later)", or none>
    Run <the next owed step> next?

Never ask it through AskUserQuestion, because the step lines quote the user's typed words. A typed yes runs the step. Words that skip the step, or that go on without it, record `Step skipped:`. Words that leave it for later record `Step later:`. When the reply does not say which of the two it means, ask which in one line. After a skipped or later line, the next reply offers the step after it. Any other reply is an ordinary message, and the same offer follows the answer to it.

### Chain mode

Under `route: direct-chain`, run the same steps in the same order with no offer between them. Stop only when a step fails or needs a decision that is the user's: a failing test or check, changes in the tree that are not this session's work, a red team unverified entry or open question, the user's own check under `e2e: skip`, or the consent gate of the remember pass. In the `red team` step every confirmed finding takes the fix round with no question, as the red-team skill's Adjudicate and fix section states for a `direct-chain` note. On a stop, print `Stopped at <step>: <reason>`, the `Done:` and `Owed:` lines, and the one question the user must answer, then go on from that step once the user answers. With no stop, end with the `Done:` and `Owed:` lines and the ship question. The `chain` worker session asks the user's own check under `e2e: skip` and the consent gate of the remember pass through AskUserQuestion, because those answers must be the user's own. It sends every other stop, and the closing `Done:` and `Owed:` lines with the ship question, to the lead by message, and goes on from the stopped step once the lead answers with the user's words.

### Out of order

The user may ask for any step or skill by name at any time, such as the red team, a commit or the ship flow, and nothing in this section stops that. When the user asks for a later step, a commit or the ship flow while a step is owed or carries a `Step later:` line, ask one plain-text question first that names each of those steps: run them first, or go on without them. A `Step later:` step counts as owed for this question. Record the reply as one `Step skipped:` or `Step later:` line per named step, with the user's words, then do what the user asked. An ask for the ship flow is the exception: the ship flow runs only when every step is done or carries a `Step skipped:` line in the user's words, so a reply that leaves a step for later starts no ship flow. A step the user ran by hand records its `Step done:` line. On an ask for a commit, write the shipping record by the capture rules of Closing record below before the commit handoff, while the tree still holds the slice, so a later ship flow goes on from the push. The `direct-route finished:` summary still waits until every step is done or skipped.

### Resume

A session that opens a `direct-drive` note, and the same session after a compaction, reads the step lines before anything else. It opens with the `Done:` and `Owed:` lines and the next offer: the next owed step, the question about the later steps when only later steps remain, and the ship question when every step is done or skipped and the last summary does not begin `ship-flow finished:`.

Only a `chain` worker session resumes chain mode, unless no worker session can start. The `chain` worker session, and the same worker session after a compaction, reads the step lines and goes on from the first owed step. A lead that opens a `direct-chain` note runs no step while a `chain` worker session can start. When the `crawl` section 4 spawn prints `NOBG` or exits 2 or 3, the lead offers to run the chain in its own session as that section does, and on the user's yes it reads the step lines and goes on from the first owed step. It runs `bash <plugin-root>/scripts/worker-watch.sh list --scratchpad '<scratchpad>'` and reads its own `<scratchpad>/workers` record for a `chain` worker session of that plan. When one is live, the lead reports its state and the note's `Done:` and `Owed:` lines, and forwards the user's words to it with SendMessage. When none is live, the lead offers in one question to start one with the `crawl` section 4 spawn command, and starts nothing before the user's yes. When every step is done or skipped and the last summary does not begin `ship-flow finished:`, the lead asks the ship question below.

### Closing record and the ship question

The ship flow runs only when every step is done or carries a `Step skipped:` line in the user's words. A `Step later:` step counts as owed here: when no other step is owed, name each later step and ask in one plain-text question whether to run it now or skip it, and write no closing record and ask no ship question while a step is later. A reply that leaves a step for later again ends the turn with no ship question.

When every step is done or skipped, write the closing record, then ask the ship question. The closing record is what execute-flow section 7 writes for an unblocked run (`<plugin-root>/skills/execute-flow/SKILL.md`): the commit message in the repo's observed convention, and the shipping record under Plan Changes During Execution, which holds the staging list, that commit message and a hash. Take the staging list and the hash from one `toolkit:verifier` briefed with the `CAPTURE_PROMPT` text of `<plugin-root>/workflows/execute-runner.js`, substituted as ship-flow section 4 substitutes it, so the ship flow's own capture compares equal. The staging list is the capture's `paths` and the hash is its `hash12`. Brief that verifier to also return the capture command's exit code. When it is not 0, say so with its output, write nothing, and stop, because a failed capture reads as an empty one. When the capture's `paths` hold a path that no `Changed path:` line names, write nothing, name each such path, and stop in both modes: the user takes it out of the tree, or answers that it is this work, which records its `Changed path:` line, and the capture runs again. When the capture is empty and the note holds no shipping record, say that the tree holds no slice, write no closing record, and ask no ship question. When the capture is empty and the note already holds a shipping record, keep that record unchanged, because the user committed the slice after it was written. In the same write, set this session's entry summary to begin `direct-route finished:`, followed by the steps done and skipped. The note holds one shipping record. When a capture that is not empty finds the note already holding one, replace that record in place with the new capture, as an execute-flow section 8 fix replaces it.

The ship question is plain text and ends the turn:

    Done: <as in drive mode>
    Owed: none
    Go into the ship flow now, up to the ceiling <ceiling>?
    - `run the ship flow` or `yes`: ships the slice up to that ceiling (recommended).
    - `no`: nothing ships. Ask for the ship flow by name when you are ready.

A typed `run the ship flow` or bare `yes` is the user asking for the ship flow by name: load `ship-flow` (`<plugin-root>/skills/ship-flow/SKILL.md`) and follow it from its section 1 on this note. On a `direct-chain` note the lead asks the ship question that the `chain` worker session reports, in plain text and never through AskUserQuestion, and on that typed reply it messages the worker session `<planName>: run the ship flow` in place of loading `ship-flow` itself. The lead never commits, pushes, or opens an MR or PR itself on a direct route.

## Runtime-Evidence Debugging

When debugging runtime, integration, adapter, or boundary issues, use runtime evidence before fixing.

1. Write 3-5 concrete hypotheses first.
2. Instrument minimally (2-6 logs at decision points).
3. Gather one clean reproduction where possible.
4. Classify hypotheses as confirmed, rejected, or inconclusive.
5. Fix only what the evidence supports, at the root cause rather than per-caller symptom (see the toolkit's minimalism doctrine).
6. Verify the fix with runtime evidence.
7. Remove temporary instrumentation after confirmation.

Do not log secrets or private data. Prefer narrow evidence over speculative defensive code.
