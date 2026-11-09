---
name: plan-flow
description: >-
  Plan flow: one run that turns a brief into a validated plan note. Use only when the
  user asks for the plan flow by name ("run the plan flow", "plan flow this brief",
  "run the plan workflow"), including on a pre-scaffolded plan note: status planning,
  ticket frontmatter, a Brief section, or a brief file beside it, and empty or template Implementation Steps
  and Validation Steps. Its Brief section or brief file is the brief, or else its Objective, Current
  Context, and ticket. Never fires from crawl on its own: a typed yes or `run the plan flow` to crawl's offer is the ask by name. Reads the run options from the plan note or the session cache and asks only for the keys neither has,
  runs topic recall, runs a route check that
  recommends wayfinder on a multi-part brief, launches the plan-builder
  workflow (discovery, planner draft, plan-critic pre-mortem with a revise loop, cold
  red team, optional goal judge), writes and validates the plan note in the vault, and
  gates its status on the result. Once the plan is approved, it asks in plain text whether
  to run the execute flow here, open a child session, or stop. Never writes repo files and never runs git. Do NOT
  fire on a plan note whose Implementation Steps are filled (plan-guide owns that) or on
  trivial work that needs no plan.
---

# Plan Flow

Plan-flow is the conductor side of the `plan-builder` workflow, shipped with this plugin at `<plugin-root>/workflows/plan-builder.js`. The script runs discovery, the planner draft, the plan-critic pre-mortem with its revise loop, the cold red team, and the optional goal judge, then returns the plan sections. The conductor reads the run options, runs recall, launches the script, writes and validates the plan note, and gates its status. The script writes no files and runs no git. The conductor writes only the vault note.

## 1. Trigger

Fire only when the user asks for the plan flow by name. Asking for "the plan workflow" counts as asking by name. A `crawl` route never fires this skill on its own. A typed reply to the plan flow offer that ends `crawl` section 4, when it picks the plan flow, such as `yes` or `run the plan flow`, counts as asking by name. A pre-scaffolded plan note is accepted, and section 5 writes into that note in place instead of creating a new plan directory. A note is pre-scaffolded when its status is `planning`, it has `ticket` frontmatter, a Brief section, or a `brief - <plan>.md` file beside it, where `<plan>` is the note's `plan` value, and its Implementation Steps and Validation Steps are empty or still hold template text. Its Current Context and Objective may hold scaffold text. The brief of a pre-scaffolded note is its Brief section when it has one, else that brief file, otherwise its Objective, its Current Context, and its `ticket` frontmatter. Any other plan note, including one whose Implementation Steps are filled, belongs to `plan-guide`, so load `plan-guide` instead. Trivial work needs no plan, so it never fires this skill. Without a pre-scaffolded note, the brief is the user's text for the work, quoted verbatim.

## 2. Run options

Before anything else, read the run options per `plan-guide` § Run options (`<plugin-root>/skills/plan-guide/SKILL.md`): from the pre-scaffolded note, then from `<scratchpad>/flow-run-options` for the keys the note lacks when that file's `plan:` line names this plan, then ask only the questions for the keys still missing. On a pre-scaffolded note, write the cache for this plan at once, because the note names the plan. On a fresh brief, no plan name exists yet, so keep the answers in conversation: section 5 writes the note keys and the cache once section 4 has derived `planName`, and when section 3a moves the work to wayfinder, the answers travel with the wayfinder hand-off. The plan flow runs no git under any ceiling. The `## Flows` section of the git-safety doctrine (`<plugin-root>/doctrine/git-safety.md`) defines what each ceiling permits.

## 3. Recall

Run `python3 <plugin-root>/scripts/topic-recall.py --repo <repoName> --repo-root <repoRoot> "<term one>" "<term two>"`, with each key term from the brief passed as its own quoted argument, because the terms are user text. The plugin root is `../..` from this skill's base directory, resolved to an absolute path. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. `<repoName>` is the basename of `<repoRoot>`. The two sources are the vault topic notes and the repo's `docs/`.

Read the exit code before the output:

- `0` means the search ran. Read the top hits of both sources and pass the text output as `recallHits`. If the output is empty, pass `none`, because the script rejects a blank `recallHits`.
- `2` means `~/.claude/obsidian-sync.json` is missing or unreadable, or the vault root is not a directory.
- `3` means the run passed its internal deadline.

On `2` or `3`, stop and report the exit code and stderr to the user. Never pass `none` for a failed recall.

## 3a. Route

When this run started from the plan flow offer that ends `crawl` section 4, keep the plan-guide route the user confirmed in crawl, state it in one sentence, and continue to section 4 with no question, because crawl chose that route on explorer evidence that the recall hits do not match.

Apply the route rubric from section 3 of the `crawl` skill (`<plugin-root>/skills/crawl/SKILL.md`) to the evidence available at this point, which is the recall hits. Run no explorer fan-out, because the plan-builder's discovery phase does the deep reading later. A brief that reads as several independent workstreams yields a wayfinder recommendation that the user confirms, never a settled route, because wayfinder investigates before it decomposes. Several workstreams means several subsystems or repos, an issue list rather than one issue, or work that cannot be one branch and one plan. Otherwise the route is this flow.

When the recommendation is wayfinder, ask once through AskUserQuestion: "This brief reads as <N> independent workstreams: <one clause each>. Map it with wayfinder, or plan it as one flow?" with the options in this order:

1. "Wayfinder (Recommended)", with the description "Maps the effort and writes a parent plan plus one child stub per workstream; each child gets its own plan flow later."
2. "One plan flow", with the description "Continues this flow and plans the whole brief as one note."

On "Wayfinder", load the `wayfinder` skill from `<plugin-root>/skills/wayfinder/SKILL.md`, hand it the brief, the recall hits, and the run option answers from section 2, and stop this flow. Hand wayfinder the path of a pre-scaffolded note, which becomes the wayfinder parent note when its name matches its directory's suffix and otherwise the first child stub, as wayfinder section 4 says. The confirmed answer counts as the explicit request that wayfinder's trigger requires. On "One plan flow", continue to section 4.

When there is no wayfinder recommendation, state the route to the user in one sentence and continue to section 4 without a question.

## 4. Launch

Settle the ticket first, per the Ticket subsection of `plan-guide` § Run options. When the brief names no ticket key, issue number, or ticket URL, no expedition work note of the same work records a `ticket`, and either no note exists yet or the note's `ticket` is blank, ask the ticket question in its own AskUserQuestion call. Section 3a has kept the work in this flow by now, so the answer always serves a branch. When the answer is Create a ticket, run the create procedure in that subsection before deriving `planName`. On a pre-scaffolded note, write the answer to its `ticket` key at once with the atomic write, so a rerun neither asks again nor creates a second ticket. On a fresh brief, keep it with section 2's answers for section 5. Derive `planName` per `plan-guide` naming and build the args: `brief`, `repoRoot` as an absolute path, `repoName`, `planName`, `recallHits`, and the optional `knownEvidence` (facts this session already verified, each with its file:line, and the crawl sections the next paragraph names), `approveIf` (one goal sentence the plan must meet, only when the user gave one), and `maxRounds` (revise rounds, default 2), and `models` (the `agents` object the resolver run in the next paragraph prints, left out when the resolver is missing or fails).

Whenever the brief comes from the `brief - <plan>.md` file, on a run started from the plan flow offer that ends `crawl` section 4 or on any by-name run, `knownEvidence` also carries the note's Current Context, Assumptions and Open Questions, which crawl wrote into the note, each under its own heading, after this line: `Crawl checked the brief against the repo. Where these sections correct the brief, the correction holds.` The brief stays the brief file's verbatim text, so the crawl's corrections and open questions reach plan-builder only through `knownEvidence`.

Append one line to `brief` that names the branch shape: `Ticket: <ticket>. The branch is <type>/<ticket>-<slug>.` for a key or `issue-<n>`, and `No ticket. The branch is <type>/<slug>.` for `none`, with the project's no-ticket token in the ticket's place when the project's rules name one.

When the section 2 options carry `e2e: required`, append this line to `brief`: `End-to-end tests are required: mark each Validation Step that needs the running local stack with [e2e] directly after its number.`

Run `scripts/resolve-models.sh` as `plan-guide` § Run options defines, from the `worker_model`, `verifier_model` and `verifier_effort` values this flow read or asked there, and pass the printed `agents` object as `models`. On a fresh brief the values are the answers section 2 keeps in conversation, because section 5 writes the note keys and the cache only after the launch.

When `repoRoot` contains `plugins/toolkit/workflows/plan-builder.js`, launch `{scriptPath: "<repoRoot>/plugins/toolkit/workflows/plan-builder.js"}`, otherwise `{name: "toolkit:plan-builder"}` with the `scriptPath` fallback `red-team` uses. That fallback is `{scriptPath: "<plugin-root>/workflows/plan-builder.js"}`, used if name resolution fails. The script is named `plan-builder` because a workflow and a skill cannot share a name in the plugin registry. Persist the `runId` and script path to `<scratchpad>/plan-flow-<planName>.runid` at once, before reading the result. A dead run resumes with `resumeFromRunId`. Completed agents return cached, so never relaunch a fresh run when a resume is possible.

The result is `{plan, branch, relatedTopics, discovery, rounds, tripwires, walkAway, coldObjections, coldVerdict, finalVerdict, openObjections, critiqueStale, blocked, approveIf, incomplete}`:

- `discovery.uncovered` lists the discovery areas that no explorer covered.
- `finalVerdict` is `proceed`, `revise`, `stop`, or `incomplete`.
- `coldVerdict` is the cold red team's verdict string, or null.
- `openObjections` lists the objections left unapplied, each with `section`, `claim`, `evidence`, `fix`, and `material`.
- `critiqueStale` is true when the returned plan differs from the draft that the last returned Invert critique saw.
- `blocked` lists plain-sentence reasons that the plan must not be auto-approved, and is empty when nothing blocks.

## 5. Write the plan note

Load `plan-guide`. Create the directory and note per its naming and atomic write rules: Write the note to a `.tmp.md` file beside the destination, then move it into place with `vault-fs.sh mv`.

For a pre-scaffolded note, create no directory and no new note. Write the whole filled note to the `.tmp.md` file beside it, then move it into place with `vault-fs.sh mv`. This is the fill exception of `plan-guide`'s atomic write rule, because the sections are most of the note. Keep the frontmatter values that are already set, such as `ticket`, `repo`, `created`, and `branch`, and fill the empty ones. A `branch` value that the scaffold already set wins over the result's `branch`, so the shape check below applies only when the scaffold left `branch` empty, and the ticket insertion after it applies to either branch.

Map each section to its heading:

| `plan` key | Heading |
|---|---|
| `objective` | Objective |
| `plainLanguageSummary` | Plain Language Summary |
| `currentContext` | Current Context |
| `assumptions` | Assumptions |
| `affectedFiles` | Affected Files |
| `implementationSteps` | Implementation Steps |
| `validationSteps` | Validation Steps |
| `risks` | Risks |
| `rollbackNotes` | Rollback Notes |
| `openQuestions` | Open Questions |
| `relatedTopics` | Related Topics |

Add Plan Changes During Execution and Linked Artifacts, both empty at creation as `plan-guide` requires. Write the full frontmatter per `plan-guide`, with `status: planning` until the gate. Write the run option keys from section 2 into the frontmatter, each with its value, and a toolkit-default model or effort answer as a bare key. Write the ticket the brief names, else the expedition work note's `ticket` inside an expedition, else section 4's ticket answer, to `ticket`. On a fresh brief, once the note is in place, write `<scratchpad>/flow-run-options` for `planName` with the same keys, per `plan-guide` § Run options. Before writing the frontmatter, check `branch` against the git-safety branch shape: `<type>/<TICKET>-<slug>` or `<type>/<slug>`, lowercase kebab-case apart from the ticket key. If `branch` does not match, write `feat/<planName>` and tell the user. Then, when `ticket` holds a key or `issue-<n>` and the part of `branch` after the type prefix does not start with `<ticket>-` in any letter case, insert `<ticket>-` after the type prefix and tell the user, so `feat/example-change` with `issue-48` becomes `feat/issue-48-example-change`. When it starts with the ticket in another letter case, write the ticket as `ticket` records it. When `ticket` is `none` and the project's rules name a no-ticket token, the same insertion applies with that token. When the scaffold set `branch` and that branch already exists, locally per `git branch --list '<branch>'` or on origin per `git ls-remote --heads origin 'refs/heads/<branch>'`, skip the insertion and leave `branch` as it is. Check that each `relatedTopics` entry is a plain name with no brackets and no slashes. If an entry carries brackets or a slash, write it without the brackets and with only its last path segment, and tell the user. Write `branch` to `branch` and `relatedTopics` to `related_topics` as plain strings.

Append the tripwires to Validation Steps and the walk-away checks to Risks, one line each. If `critiqueStale` is true, end each of those tripwire and walk-away lines with the sentence "Written against an earlier draft, re-check against the final plan." List every `openObjections` entry under Risks as an open objection, one line each with its section, claim, and fix. List every `coldObjections` entry that the final plan does not resolve under Risks, one line each with its section and claim.

Record the session entry per `plan-guide`, with the id taken from the scratchpad path. When the gate in section 6 sets `status: approved`, the session summary must say that the approval came from the `approveIf` judge and quote the goal sentence, so a reader knows that a model judged the plan against a goal the user wrote and that no human read the note first. Create stubs for unresolved Related Topics per the obsidian-topic command (`<plugin-root>/commands/obsidian-topic.md`).

Then run `python3 <plugin-root>/scripts/validate-plan.py "<plan note path>"` and require exit 0. A failure is reported with the validator output, never patched silently.

## 6. Gate

Set `status: approved` and `approved: <today>` only when `approveIf.meets` is true and `blocked`, `incomplete`, and `discovery.uncovered` are all empty. In every other case, set `status: review` and stop. A run without `approveIf` returns `approveIf: null`, which lands in `review`. If the status is approved, write the session summary that section 5 requires in the same change, and add the line `Approved by the approveIf judge against "<goal>"` under Plan Changes During Execution, because a later flow in this session rewrites the same session entry. Write the status change by `plan-guide`'s changed-lines path, `vault-fs.sh cp` to the `.tmp.md` copy, an Edit on the copy, then `vault-fs.sh mv`, with the session summary and the approval line in the same copy when the gate approves, and run `validate-plan.py` again, requiring exit 0.

Whatever the gate result, state to the user the `finalVerdict`, the `coldVerdict`, every `blocked` reason, every `incomplete` marker, and every `discovery.uncovered` area. State a null `coldVerdict` and each empty list as "none". When `approveIf.meets` is false, also state its `reasons` and `unmetGoals`. If the status is approved, say so.

Then print the note's Plain Language Summary verbatim under the heading `Plain language summary`. If the gate left the status at `review` or `planning`, follow the summary with the approval ask: "Approve this plan as written, or tell me what to change?" The user approves from that summary. The approval follows the `plan-guide` lifecycle, so an approval here sets `status: approved` and `approved: <today>` with the same changed-lines write and validation as the gate. Once the status is `approved`, by the gate or by the user, end the reply with the post-approval question that `plan-guide` § After approval defines (`<plugin-root>/skills/plan-guide/SKILL.md`), and act on the user's typed answer as that subsection says.

## Boundary

The flow never writes repo files and never runs git. Prose rules bind the note. Not for a plan note whose sections are filled (`plan-guide` owns that) and not for a standalone review of a written plan (`plan-critic` owns that). An approved status never starts execution on its own. The next step waits on the user's typed answer to the post-approval question or on the user's own ask. On a reply that picks running the execute flow here, this flow ends and the `execute-flow` skill takes over under its own boundary. An approved status set by the gate records a mechanical judgement against the user's own `approveIf` sentence, not a human reading of the note. The human approval rule in `plan-guide` still governs execution, and the user can revert the status to `review`.
