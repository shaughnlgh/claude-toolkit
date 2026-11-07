---
name: plan-guide
description: >-
  MANDATORY companion for plan work. Invoke BEFORE creating, filling in, updating, or
  closing out any plan note (plan - <name>.md) in the Obsidian vault — including
  pre-scaffolded plan notes — and at the start and end of any planning or
  execution session tied to a plan. Contains the canonical artifact locations, naming
  rules, plan frontmatter and sections, planning steps, status lifecycle, session
  recording, and session closure rules. Do not write or edit
  a plan note without this loaded. A request naming the plan flow or the plan workflow
  goes to the plan-flow skill, which loads this guide for the plan note contract.
---

# Plan Guide

This skill is the single source of truth for the plan-first workflow: where artifacts live, how they are named, what a plan note contains, the planning steps, the status lifecycle, and session closure. The always-loaded invariants (plan-first, approval gate, orchestration rules, git safety) live in the toolkit's CLAUDE.md doctrine and your global config; this file holds the mechanics.

## Workflow: Plan → Execute → Session

For non-trivial development tasks, use a plan-first workflow.

Do not begin implementation until the plan has been written and explicitly approved by the user.

### Canonical artifact location

Workflow artifacts are written directly into the Obsidian vault, at the location the user's `~/.claude/obsidian-sync.json` defines (`vault_path` + `plan_folder_template`):

    <vault_path>/<plan_folder_template>
    e.g. with the default template: <vault_path>/AI/Claude-Code/Projects/{repo_name}/{date}-{plan_name}/

The plan name must be short, lowercase, kebab-case, and derived from the task purpose. The date is the local date (YYYY-MM-DD) when the plan is created. The plan name must match: `^[a-z0-9][a-z0-9-]*$`

### Artifact naming

Every artifact filename embeds the plan name so Obsidian graph nodes are unique and wiki links resolve unambiguously:

    {artifact} - {plan_name}.{ext}

Canonical artifact:

- `plan - <plan-name>.md`

Optional sibling artifacts created by other skills (e.g. `handoff - <plan-name>.md` from the handoff skill) and supporting notes created inside a plan directory follow the same pattern: `{artifact} - <plan-name>.md` (e.g. `security-review - example-sso-login.md`, `flow-diagrams - abc-123-example-feature.md`). The artifact part is short kebab-case.

Never create generically named artifacts (`plan.md`, `handoff.md`, `security-review.md`) in the vault. Generic names collapse into indistinguishable graph nodes and make wiki links ambiguous across plans.

Because filenames derive from the plan name, plan names must be unique across the entire vault, not just within one repo. Check for collisions before creating a plan directory; if a plan name is taken, derive a more specific one.

### Child plans (parent/child directories)

A plan directory MAY contain child plans alongside the parent note — the shape for umbrella work like an incident investigation that spawns many remediation tasks:

- The parent is `plan - <plan-name>.md` where `<plan-name>` matches the directory suffix. Children are additional `plan - <child-slug>.md` notes in the same directory, each with FULL plan frontmatter (own `plan:`, `status`, `branch`, `modules:`, `sessions:`).
- Child slugs follow the same rules as plan names (kebab-case, vault-unique).
- Children carry `parent: <plan-name>` in frontmatter.
- Children never inherit the parent's ticket. Each child links its own ticket or has none.
- Children are full plans in their own right (own approval, stage, branch/MR tracking, reviews, worklogs). Tooling that visualizes plans should group them under their parent.

### Plan name derivation

If the user provides an issue, ticket, Jira key, GitHub issue number, or task ID, include it at the start of the derived plan name.

Normalization:

- Lowercase everything.
- Preserve the ticket prefix when present (e.g. `CR-123` → `cr-123`).
- Replace separators (underscores, spaces, slashes) with hyphens.
- Remove characters that are not `[a-z0-9-]`.
- Output must match: `^[a-z0-9][a-z0-9-]*$`

Examples:

- `CR-123 Runtime error handling` → `cr-123-runtime-error-handling`
- `SHOP-456 credit memo source selection` → `shop-456-creditmemo-source-selection`
- `#789 fix loader bug` → `issue-789-fix-loader-bug`
- `MAG_321 URL rewrite regeneration` → `mag-321-url-rewrite-regeneration`

If no ticket or issue is provided, derive the name from the task only. If the ticket format is ambiguous, ask before writing.

Example (with the default template):

    <root_folder>/Projects/my-repo/2026-05-19-cr-123-runtime-error-handling/

Resolve the vault path and folder template from `~/.claude/obsidian-sync.json`.

### Repo-local plans directory

Do not write workflow artifacts (plan, handoff, and session notes) to repo-local `.claude/plans/`. The Obsidian vault is the only location for these workflow artifacts; it does not govern repo-owned knowledge artifacts (facts, decisions, playbooks, glossary), which follow `doctrine/repo-artifacts.md` instead.

### Built-in plan directory

`~/.claude/plans/` is Claude Code's built-in plan mode directory. It is not part of this workflow.

## Required Artifacts

The one required artifact, written to the Obsidian plan directory:

- `plan - <plan-name>.md` — the single source of truth. A living document: kept current during execution (decisions, gaps, deviations) so it records both what was intended and what actually happened. Carries its own session history and worklogs in frontmatter.

Other skills may create optional sibling artifacts in the same directory (e.g. `handoff - <plan-name>.md`); each is linked from the plan's Linked Artifacts section when — and only when — it is actually created.

The plan note plus git (the branch diff and, after a squash-merge, the squashed commit) plus the session ids recorded on the plan are the complete record of what was done. Execution details belong in the plan note under "Plan Changes During Execution". Topic notes (the cross-plan knowledge layer) are maintained during planning and execution, not written at finalization.

Write every vault file atomically: Write the content to a `.tmp.md` file beside the destination, then move it into place with the toolkit's `scripts/vault-fs.sh mv`. The vault path contains spaces and sits inside iCloud Drive. The `.tmp.md` suffix keeps the markdown hooks firing on the temporary write. `vault-fs.sh` takes paths relative to `vault_path` plus `root_folder` from `~/.claude/obsidian-sync.json`, so a plan note path starts at `Projects/<repo>/...`. Worked example with the default template:

    Write tool target: <vault_path>/<root_folder>/Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md
    bash <plugin-root>/scripts/vault-fs.sh mv "Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md" "Projects/my-repo/<date>-example-feature/plan - example-feature.md"

## Plan Sync

After creating or refining the plan note, it is written directly to the Obsidian plan directory. There is no separate sync step for new plans.

If the plan note cannot be written to Obsidian (vault missing, path error, iCloud issue), stop and report the failure. Do not write repo-local workflow artifacts.

### Do not write if

- The active plan directory is ambiguous.
- The plan note does not exist or has not been created yet. (Exception: an expedition's `work - <name>.md` and `brief - <name>.md`, and an incident investigation's `incident - <name>.md`, precede the plan note by design. Each derives the plan name at ingestion per this skill's naming rules, so the artifact carries the eventual plan name and lands in the eventual plan directory.)
- The Obsidian config is missing.
- Sensitive data may be present in the artifacts.
- The user explicitly says not to write.

If writing is skipped, state exactly why.

### Validate the plan note

The toolkit's `scripts/validate-plan.py` (same directory as vault-fs.sh; resolve the plugin root the same way) mechanically checks a plan note against this contract: filename and slug, required frontmatter keys, status lifecycle values, parent/child directory shape, session-entry structure and id uniqueness, required headings, and no retired-artifact links. Read-only, zero dependencies beyond python3:

    python3 <plugin-root>/scripts/validate-plan.py "<plan note path>"

Run it and require exit 0:

- after creating or changing a plan note, before treating the write as successful;
- before presenting a completed plan for approval (setting `status: review`);
- before beginning execution of an approved plan;
- before declaring session closure complete.

A failure is corrected or reported to the user — never silently ignored. The validator proves the mechanical contract only; whether the content is a good plan remains human and model judgment.

## Plan note (`plan - <plan-name>.md`)

The plan must be written before implementation begins.

Writing style for the plan note follows the vault rules (same as topic notes): plain sentences. Never use em dashes or semicolons to split text. Use separate sentences or commas instead. Never hard-wrap prose: write each paragraph as one continuous line and let the editor soft-wrap. This applies to every markdown file, not just plan notes.

### Required plan frontmatter

```yaml
---
type: plan
date:
created:
updated:
project:
repo:
plan:
status:
approved:
tool: Claude Code
branch:
ticket:
mr:
modules:
repos:
sessions:
tags:
related_topics:
---
```

- `ticket`: the issue/ticket key if one was provided (e.g. `CR-123`). Leave blank if none.
- `approved`: the date (YYYY-MM-DD) the plan was approved. Leave blank until then; it is stamped (by you or tooling) when status moves to `approved`.
- `mr`: the merge/pull request URL once one is opened for the plan's branch. Leave blank until then; record it when the draft MR is created.
- `modules`: for plans that also change owned vendor modules (each its own git repo) **nested under the project repo**, the list of modules touched. Leave blank for single-repo plans (the common case). Each entry has `name` (composer package), `path` (e.g. `vendor/acme/module-foo`), `branch`, and `mr`. Track each module's branch/MR alongside the project's. Example:

```yaml
modules:
  - name: acme/module-payments
    path: vendor/acme/module-payments
    branch: fix/payment-timeout
    mr:
```

- `repos`: for plans that span multiple **sibling top-level repos** (each its own `~/projects/<repo>`, not nested under another), the list of code repos touched. Use this when `repo` is a grouping rather than a single code repo (e.g. a storefront umbrella covering a backend repo plus a PWA repo). Each entry has `repo` (the `~/projects` dir name), `branch`, and `mr`. Each is its own work component with its own branch/MR. Leave `branch` blank at plan level in this case (the per-repo branches live here). Use `modules` for nested vendor modules and `repos` for sibling repos; a plan can use either, both, or neither. Example:

```yaml
repos:
  - repo: shop-backend
    branch: feature/content-types
    mr:
  - repo: shop-pwa
    branch: feature/content-type-renderer
    mr:
```

- `sessions`: the Claude Code work session(s) tied to this plan, oldest first — at most one entry per session id. A plan can span many sessions; most have just one for now. Each entry has `date`, a one-line `summary`, and optionally `id` (the session id / transcript file). The entry is created when a work session starts (planning and execution alike) and its summary is updated to the real outcome as the session ends (see Record the session on the plan), so the plan carries its full session history. The `id` is the reference point back into the actual transcript if the blow-by-blow is ever needed. Example:

```yaml
sessions:
  - date: 2026-06-14
    summary: Initial plan + first implementation pass
    id:
```

- `related_topics`: plain strings, not wiki links. Use wiki links only in the body.
- Do not invent ticket values. Do not invent tags or topics — use obvious project/task topics only.

### Required plan sections (each as a `##` heading)

- Objective
- Plain Language Summary — immediately after Objective, first sentence exactly "This section is for non-technical readers. The technical detail below it can be skipped.", then one to three short jargon-free paragraphs a non-technical stakeholder can read
- Current Context
- Assumptions
- Affected Files, which may hold one `Protected paths: <path>, <path>` line of repo-relative paths, which the ship flow adds to the paths no fix commit may change before an unattended merge
- Implementation Steps
- Validation Steps
- Risks
- Rollback Notes
- Open Questions
- Plan Changes During Execution — initially empty; updated during execution if reality diverges from the plan (changed assumptions, changed affected files, deviations, validation changes)
- Related Topics — use `[[wiki links]]` here
- Linked Artifacts — the heading is present from creation but starts with no links. It lists the sibling artifacts actually created for this plan (e.g. `[[handoff - <plan-name>]]` when the handoff skill writes one) and the repo doc paths promoted from it under Finalize. Link an artifact only once it exists — never speculatively.

### Implementation Steps must show the code, not just describe it

A plan a reader cannot see the code off is not finished. In Implementation Steps, include the concrete artifacts that make the change buildable and reviewable:

- Representative code snippets for the load-bearing or novel changes — the key function, the signature, the tricky bit — not whole files.
- A directory-tree layout for any new files, modules, or moved structure.
- Signatures, schemas, or an example input to output for new contracts and APIs.
- The exact commands, config keys, migrations, or env vars the change adds or changes.

Show enough that plan-critic and the human can judge the approach from the plan, and the implementer builds from it without re-deriving the design. Prose alone is not enough for non-trivial work.

### Validation Steps

- Number the steps 1, 2, 3, so the execute runner reads each as its own step.
- A step is a unit step unless `[e2e]` follows its number on the step's own first line, as in `3. [e2e] Run npx playwright test checkout.spec.ts against the local site`. An intro paragraph before the list does not hide that marker.
- An end-to-end step needs the running local stack: the site's URL, a browser, or the repo's own end-to-end command. Mark every step that needs the stack, because an unmarked one can read as pre-existing on the seat.
- The toolkit installs no end-to-end tool. The repo supplies the command a step names.
- If a step needs a cache flush, a rebuild, or a sync wait first, the step names that command.
- An end-to-end step writes no file into the repo unless an ignore rule covers that file.

### Reuse check (minimalism)

Before the plan proposes new code, apply the reuse ladder from the toolkit's minimalism doctrine (`../../doctrine/minimalism.md` from this skill's base directory): does it need to exist, does the codebase or the standard library or an already-installed dependency already do it. Record the result in a line or two (in Current Context or Implementation Steps) so a reviewer can see why each new file, abstraction, or dependency earns its place. Reach for the shortest change that satisfies the objective, not the most elaborate.

Stop after writing the plan and wait for explicit approval before changing implementation files.

### Feasibility gate

Every planned signal, detector, integration, or data source gets a check against real data (a query, an API call, a sample file) before design proceeds. When the signal or mechanism depends on something outside the repo (a credential, an API, a connector, a remote system), it also gets a named external dependency that the user confirms is available. A local input (a repository file, compiler or test output, an in-process metric) records "external dependency: none" and passes the gate on its real-data check alone. A known caveat is a blocker now, never a "revisit later" note. Record each check and its result in Current Context.

### Review readiness

A plan enters `status: review` only when Open Questions and Assumptions are settled. Each section reads "None" or names an external unknown the team cannot resolve (a vendor answer) together with its owner. An unresolved external dependency keeps the plan in planning until the user confirms access or the design drops the dependency. Answer internal questions during planning. Never carry one into review.

### Spec, not journal

The plan body describes the current design as if it had always been so. After a rename or a reversal, rewrite the affected sections in place. History lives only under Plan Changes During Execution. Banned in the body: "renamed from", "was originally", "the earlier X design", "rescoped", "now confirmed", "revised on", and any date used as narration. When the change touches a versioned artifact, state the kind of change it needs (patch, minor, or major), never a version number.

### The plan note as a living document

During execution, if implementation reality diverges from the plan, Claude must update the plan note rather than deferring deviations to a separate artifact. Record changes in the "Plan Changes During Execution" section. This keeps the plan as the single source of truth for what was intended and what actually happened.

## Run options

Eight frontmatter keys record how the flows run a plan: `ceiling`, `worker_model`, `verifier_model`, `verifier_effort`, `nits`, `tests`, `e2e`, and `tag_merge`. They are optional on every note and are not part of the Required plan frontmatter block, so a skeleton, an older note, and a Mission Control scaffold still validate. A key is written only with a value, except that the three model and effort keys may be written blank, meaning the models file decides. `validate-plan.py` reads a blank key as absent and checks a value only when one is present. This section is the only definition of the keys, the reading rule, and the session cache. The `testing-gate` skill owns a separate tests-only question for work with no plan note. Every other run option question lives only in this section, and a flow references this section by name and carries no copy of the question set.

### Values

- `ceiling`: `none`, `mr`, or `merge`. The stage the ship flow stops at, and the limit on what any flow may do in git. `none` suggests git commands and runs none. `mr` commits, pushes, opens the MR or PR, watches the pipeline, and works the bot threads. `merge` adds the merge. The `## Flows` section of the git-safety doctrine (`../../doctrine/git-safety.md` from this skill's base directory) defines what each value permits.
- `tag_merge`: `true` or `false`. Under `ceiling: merge`, `true` tags the merge commit and pushes the tag. Under any other ceiling the key has no effect.
- `worker_model`: blank, a Claude Code alias (`sonnet`, `opus`, `fable`, `inherit`), or a full model id, with an optional `[1m]` suffix. The implementer role's model. Blank or absent means the models file decides. `inherit` clears the models file's value, so a workflow call runs on the session model and an Agent-tool spawn uses a configured default subagent model, then the session model.
- `verifier_model`: the same vocabulary as `worker_model`. The verifier role's model.
- `verifier_effort`: blank, or `low`, `medium`, `high`, `xhigh`, `max`, or `inherit`. The verifier role's effort. Blank or absent means the models file decides.
- `nits`: `fix` or `skip`. Whether the review loops fix unreproduced nits and small findings.
- `tests`: `required` or `manual`. Whether the slice needs automated tests, or manual verification is enough.
- `e2e`: `required` or `skip`. `required` means the plan marks at least one end-to-end step, and those steps run against the running local stack before the slice ships. `skip` means the runner reports each marked step as a manual check and never runs it. The Validation Steps subsection above defines the marker.

`haiku` is not accepted on any model key.

`worker_model`, `verifier_model`, and `verifier_effort` reach `scripts/resolve-models.sh` (`../../scripts/resolve-models.sh` from this skill's base directory). The `agent-model.sh` hook reads them from the session cache for an Agent-tool spawn. Before a flow launches a workflow, it runs the resolver with `bash` and one flag for each of these values it read or asked that is not blank, `--worker-model '<value>'`, `--verifier-model '<value>'` and `--verifier-effort '<value>'`, and with no flags when it holds none. Each value must be single-quoted, because zsh reads an unquoted `[1m]` suffix as a glob and aborts the command with `no matches found`. The flow passes the printed `agents` object as the runner's `models` arg. When `repoRoot` contains `plugins/toolkit/scripts/resolve-models.sh`, the flow runs that copy instead, so the resolver comes from the same tree as the runner it launches. If the resolver exits 0 and prints anything on stderr, the flow reports that output to the user before the launch. If the resolver is missing or exits non-zero, the flow reports its stderr and launches without `models`, so every call inherits the session model and effort. Open item: no runner, hook, or skill reads `nits`. The flows ask and record it only, so the execute runner fixes nits whatever `nits` says.

### Reading rule

A flow reads the run options per key. The five enum keys are `ceiling`, `nits`, `tests`, `e2e`, and `tag_merge`. A bare enum key, one with no value, counts as absent. The note holds the keys when all five enum keys are present with valid values. Then the flow asks nothing and writes the session cache from the note.

When the note lacks one or more enum keys, the flow fills each missing key from the session cache, but only when the cache's `plan:` line equals the note's `plan:` value. A cache for another plan, or one with a blank `plan:` line, is never read by a plan flow. For each key still missing, the flow asks the matching question from the question set below, so a note with some keys gets one question set that covers only the gaps. A missing or blank model or effort key never triggers a question on its own, because blank means the models file decides. Whenever a flow asks any run option question, it also asks the question for every model or effort key the note lacks, and a key written blank counts as answered. The flow records every filled or answered key on the note at its next write of the note, and rewrites the cache for this plan.

A wayfinder child stub copies the parent's run option keys only when the parent carries values, so a child of a parent with recorded options never re-asks. The user changes an option by editing the note.

### Question set

At most two AskUserQuestion calls, carrying up to five questions in all, recommended answer first, per the communication doctrine. A flow asks only the questions whose keys are missing under the reading rule, and a question writes only the keys that were missing. A free-text answer that names a valid value counts as that value.

Call one carries up to four questions:

1. "Where does the ship flow stop?", asked when `ceiling` or `tag_merge` is missing, with the options "No git, suggest only (Recommended for a work repo)", which writes `ceiling: none` and `tag_merge: false`, "Commit, push and open the MR or PR", which writes `ceiling: mr` and `tag_merge: false`, "Through merge", which writes `ceiling: merge` and `tag_merge: false`, and "Through merge, then tag the merge commit", which writes `ceiling: merge` and `tag_merge: true`. When the note already holds a valid `ceiling` and lacks only `tag_merge`, the answer writes only `tag_merge`, `true` for the last option and `false` for any other, and the held `ceiling` stays as it is.
2. "What testing does this slice need?", asked when both `tests` and `e2e` are missing, with the options "Unit tests, no end-to-end (Recommended)", which writes `tests: required` and `e2e: skip`, "Unit and end-to-end tests", which writes `tests: required` and `e2e: required`, and "Manual verification", which writes `tests: manual` and `e2e: skip`. When only `tests` is missing, ask "Does this slice need unit tests?" instead, with the options "Unit tests (Recommended)", which writes `tests: required`, and "Manual verification", which writes `tests: manual`. When only `e2e` is missing, ask "Does this slice need end-to-end tests?" instead, with the options "No end-to-end (Recommended)", which writes `e2e: skip`, and "End-to-end tests", which writes `e2e: required`.
3. "Fix the nits the reviewers raise?", asked when `nits` is missing, with the options "Fix (Recommended)", which writes `nits: fix`, and "Skip", which writes `nits: skip`.
4. "Which model implements?", which joins the set when the note has no `worker_model` key, with the options "Toolkit default (Recommended)", which writes a blank `worker_model`, then "opus", "sonnet", and "fable", each of which writes that alias.

Call two carries the verifier question, which joins the set when the note has no `verifier_model` or no `verifier_effort` key. When call one carries fewer than four questions, the verifier question joins call one instead and the flow makes one call.

1. "Which model and effort verifies?" with the options "Toolkit default (Recommended)", which writes a blank `verifier_model` and a blank `verifier_effort`, then "opus at xhigh", "opus at high", and "sonnet at high", each of which writes that alias and that effort.

### Cache

`<scratchpad>/flow-run-options` opens with a `plan: <slug>` line naming the plan note it serves, followed by one `key: value` line per key, in the note's vocabulary, blank after the colon for a blank value:

    plan: example-plan
    ceiling: mr
    worker_model:
    verifier_model:
    verifier_effort:
    nits: fix
    tests: required
    e2e: skip
    tag_merge: false

A flow uses the cache only when its `plan:` slug equals the note's `plan:` value, and rewrites the whole file for the plan it runs. A missing file means no run option question has been asked in this session. A missing, empty, or unrecognised `ceiling` line reads as `none`, so until the question is answered no flow mutates git. A resumed session keeps its scratchpad and so keeps the cache. A new session reads the plan note. On work that has no plan note, the `testing-gate` skill writes the file as a blank `plan:` line followed by `tests: <value>`, so no plan flow ever reads that cache.

## Topic links

Related Topics sections use `[[wiki links]]` to topic notes. Every topic linked from a plan note must resolve: if the topic note does not exist anywhere in the vault, create a stub during planning. The full topic note spec (location, frontmatter, structure, content rules, freshness validation, build process) lives in the toolkit's obsidian-topic command (`../../commands/obsidian-topic.md` from this skill's base directory) — Read it before creating or updating topic notes or stubs. Prefer fewer, better topic links over many noisy ones. Do not rely on Obsidian-only plugins for basic readability.

Stubs created during planning stay vault-side; promoting a topic's canonical facts into the project repo happens only through `obsidian-topic`'s own consent gate (Repo mode), never as a side effect of planning.

Use plain strings in the plan frontmatter `related_topics`, and Obsidian `[[wiki links]]` in the body Related Topics section. Linked Artifacts follows its rule under Required plan sections (existing sibling artifacts only); never link bare generic names like `[[plan]]`.

## Planning Workflow

For non-trivial tasks, follow these steps before writing the plan note:

1. Topic recall: derive candidate topics from the task, run the toolkit's `scripts/topic-recall.py` with `--repo <repo>`, `--repo-root <repo root>`, and the task words, which reads the vault topics and the repo's `docs/` together, read the top hits, and search prior plan folders. Validate topic notes before relying on them (see the toolkit's obsidian-topic command, `../../commands/obsidian-topic.md` from this skill's base directory, § Freshness and validation). Split the result into known facts and gaps. Only the gaps need exploration. The conductor does this directly. It is one script run plus the reads, not a delegated task.
2. Read relevant code, config, docs, and existing patterns (see Docs-First Discipline in the toolkit's CLAUDE.md doctrine).
3. Invoke the `/testing-gate` skill to determine the required testing level.
4. AFTER topic recall, delegate the planning-time work by shape, scoped to the gaps from step 1. Discovery and investigation (repo/doc scan, mapping how existing code works, answering factual questions from the codebase) goes to the `explorer` agent — skip it when recall and your step-2 reads closed every gap, and say so. Escalate the explorer's model per invocation for genuinely hard tracing (orchestration model policy); evidence that needs commands run (a failing test, a repro) goes to the `verifier` agent instead, since explorer is read-only. Drafting the reviewable plan itself (proposed steps, risks, verification approach) goes to the `planner` agent, fed with the recall facts and explorer findings so it does not re-derive them — except when the main challenge is choosing architecture, which the conductor keeps per orchestration doctrine. Skip delegation entirely only when the task is obviously too small, and say why.
5. Write the plan note (`plan - <plan-name>.md`) to the Obsidian plan directory. Create the plan directory per the canonical layout, or fill in a pre-scaffolded note where one exists. Create stubs for Related Topics links that do not resolve.
6. Include a suggested branch name.
7. Note project-specific high-risk areas from the project's `01-project-core.md`.
8. No implementation code changes in this mode.
9. Stop and wait for explicit user approval before execution.

On non-trivial plans, after drafting the plan note and before stopping for approval, run the `plan-critic` subagent (model: opus) to adversarially red-team the draft. Plan-critic applies the inversion pre-mortem structure and returns tripwires and walk-away checks. Fold its material objections into the plan's Risks / Assumptions / Open Questions. Copy its Tripwires block into Validation Steps, one line per failure mode, and its Walk-away checks block into Risks, one line per check, so the plan carries the measurable signal and the threshold that means stop. Then present for approval. This step is conductor-gated: skip it for trivial plans. It augments, and does not replace, the human approval gate.

### Pre-scaffolded plans

When a planning prompt points you at an **already-scaffolded** plan note (a pre-created `plan - <plan-name>.md` with `status: planning` and ticket frontmatter), do not create a new plan directory. Fill in the existing note in place. Treat its path as the single source of truth for the plan.

A plan note scaffolded by the `crawl` skill arrives with Current Context, Assumptions, and Open Questions pre-filled from a same-session investigation, and a `brief - <plan-name>.md` sibling holding the verbatim brief. Treat the crawl-filled sections as this session's ground truth — verify only what the plan hinges on, do not re-derive them — and link the brief under Linked Artifacts.

### Plan status lifecycle

Drive the plan note's frontmatter `status` through its lifecycle so plan-tracking tooling can surface state:

- `planning` — actively being planned (scaffold/start state).
- `review` — planning is complete and the plan is awaiting human review. **When you finish a planning session and stop for approval, set `status: review`** (this is the signal plan-tracking tooling watches for). Do this whether or not the plan was scaffolded.
- `approved` — approved by the human, or by the plan flow's `approveIf` gate; ready to execute. A gate approval records a mechanical judgement against a goal sentence the user wrote, a line under Plan Changes During Execution says so, and execution-guide still waits for the user's instruction before it runs. Approval also stamps the frontmatter `approved:` date. Approval sets both fields (`status: approved` + `approved: <date>`); tooling may automate this and attach the plan note to the ticket. Only an `approved` plan should be worked: while a plan is in `review`, the only actions are approve and time tracking. After approval the session asks the question in § After approval. Before a hand execution touches any file, invoke the execution-guide skill. This is non-negotiable, and doubly so right after a /compact, which can summarize away previously loaded doctrine: the conductor supervises and delegates, it never implements directly, and execution-guide is where that contract lives. When the user asks for the execute flow by name, including through a typed reply to that question, the execute-flow skill drives the run instead and loads execution-guide for the doc pass.
- `in-progress` → `completed` (or `blocked` / `abandoned`) as execution proceeds.

### After approval

When this session sets `status: approved`, on the user's word or through the plan flow's `approveIf` gate, it ends its reply with one question in plain text and ends the turn. It never asks this question through AskUserQuestion, because the auto-mode permission classifier reads the user's typed messages and never an AskUserQuestion answer, as the Command shape under the permission classifier section of the git-safety doctrine states, and the reply that starts the run must be legible to it. It skips the question when the user's approving message already asked for the execute flow by name or said to stop, and when an `expedition` drives this session, because the expedition's gate to `implementing` asks the next step. This subsection is the only definition of the question, and a flow references it by name.

The question, verbatim:

    The plan is approved. Run the execute flow here now?
    - `run the execute flow here` or `yes`: builds the plan in this session now (recommended). The build runs in its own worktree when another session is using the main checkout, when the main checkout holds changes, or when it sits on its default branch.
    - `open a child session`: gives you one command to paste in a new terminal. The child builds the plan and messages this session when it finishes or stops.
    - `stop` or `no`: nothing runs. Ask for the execute flow by name when you are ready.

The `run the execute flow here` line comes first in every form of the question, because it is the reply that names the flow. When the context-sentinel hook has injected its ~200k token nudge in this session, "(recommended)" moves to the `open a child session` line, per the Context budget section of the orchestration doctrine, and the order stays.

The user's next typed message answers the question:

- `yes`, or a reply that asks to run the execute flow here, such as `run the execute flow here`, is the user asking for the execute flow by name. After a gate approval it is also the user's instruction that the human approval rule requires. Load the `execute-flow` skill (`../execute-flow/SKILL.md` from this skill's base directory) and follow it from its section 1 on this plan note.
- A reply that asks for a child session, such as `open a child session`, hands the user the child launch command below and ends the turn. A later ask for a child session on an approved plan note hands the same command.
- `stop` or `no` ends the turn. The next step waits on the user.
- Any other reply answers nothing. The session handles it as an ordinary message and starts no flow.

Child launch command. Read this session's own name from the first line of ListAgents, and the names of the other live sessions from the lines after it. ListAgents loads through ToolSearch with `select:ListAgents` when it is deferred. `<main>` is the main checkout of the repo that the note's `repo` names, `<repo>` is the basename of `<main>`, and `<parent name>` is this session's name. Hand no command, and say why in one sentence, in each of these cases:

- ListAgents is absent or prints no own-name line, or another live session answers to this session's name. Tell the user to run `/rename <repo>-parent`, or to pick any name that no other live session uses and that differs from `<planName>`, and then to ask for the child again.
- This session's own name is `<planName>`, the name the child takes. Give the same `/rename` advice.
- A live session other than this one answers to `<planName>`. Name it, and say that it must end, with keep answered at any worktree exit prompt, before a new child starts.
- `<main>`, the plan note path, or `<parent name>` holds a single quote, or the path or `<parent name>` holds a double quote.

Otherwise hand the user this command for a new terminal window or tab:

    cd '<main>' && claude -n '<planName>' 'Run the execute flow on the plan note "<plan note path>". When it finishes or stops, report to the session "<parent name>" by message. Run the execute flow or the ship flow on this plan note when "<parent name>" asks for it by message, and report again when that flow finishes or stops.'

The command's prompt is the user's own ask for the execute flow, the user's grant for the parent dispatch that execute-flow section 1 defines, within the note's ceiling, and the child's whole brief, because the plan note carries the run options and the prompt names the parent. Then tell the user each of these:

- When this session runs in the main checkout, it holds the seat, so the child's execute flow opens the plan's worktree with no question.
- When this session runs in a linked worktree, it does not hold the seat, so the child's execute flow opens the plan's worktree when the main checkout holds changes, sits on a default branch, or sits on a branch other than the plan's, so the user does not switch it first. Otherwise the child runs in the main checkout on the branch it holds. No collision results, because this session is not in the main checkout.
- The child messages this session when its run finishes or stops.
- When the child's report names no seat run, the child waits for this session's dispatch. This session sends it as a message whose first line is the one the report's `Next:` line names, such as `<planName>: run the ship flow`, and the child runs that flow within the note's ceiling.
- The child leaves its worktree with ExitWorktree keep after its report. It ends after its report only when the report names a seat run, and before this session runs the seat run the user makes sure it has ended.
- When the child says it could not leave, the user answers keep at the worktree exit prompt, because the seat run stops while a live session sits in the worktree and remove deletes the worktree and its branch.
- The seat run also needs the main checkout to itself, so every other live session started in `<main>`, a coordinating session above this one included, ends before this session asks for it.

### Record the session on the plan

Record the session id UP FRONT, not at the end. Your session id is the UUID directory segment of this session's scratchpad path (shown in your system prompt) — derive it from there; do not wait to be told it. The list holds at most one entry per session id: create your entry once at session start, then only ever update that same entry — never add a second entry for the same session.

At session start:
- If your current session id is already on the list (a resumed conversation that kept its id), update that entry — do not append.
- Otherwise append one new entry (date, a short "in progress" summary, your session id). If the plan note does not exist yet (no scaffold), derive the plan name and create the note skeleton (the full 18-key frontmatter — blank values except `type: plan` and `status: planning`, which the validator requires non-blank — carrying that `sessions:` entry, and all 13 required `##` headings present but empty, so it passes the validation gate) as one of the FIRST actions of the session, before deep exploration, then fill the body in as planning proceeds.
- If resumption minted a genuinely new session id (a new transcript), that is a new session: append a new entry for it.
- Every live session has an id — the scratchpad path is always in your context, so derivation always succeeds. Never leave `id:` blank on an entry you create, and never invent a placeholder value: if you truly cannot locate the scratchpad path, that is an error to surface to the human, not a reason to skip the id. A blank id only ever appears on a manually pre-scaffolded entry.

During the session and before stopping, update that same entry's summary to the real one-line outcome. If the note carries a pre-scaffolded blank-id entry that is clearly this session's work, claim it — fill in your id rather than appending a duplicate; if ownership is ambiguous (say, two blank-id entries on the same date), stop and report the ambiguity rather than guessing. Record the id yourself — do not rely on tooling to backfill it.

## Session Closure

The record of the work is the plan note (kept current during execution), git (the branch diff, and the squashed commit after merge), and the session ids on the plan.

### What Claude must do as a session ends

1. Make sure the plan note is current: decisions, gaps, and deviations recorded in "Plan Changes During Execution"; Validation, Risks, and Open Questions up to date.
2. If Plan Changes During Execution holds no `Remember:` line for this slice, the remember pass has not run. Run it now (obsidian-topic command, § Remember pass) and record its `Remember:` line there. Capture the slice diff for its brief as red-team step 2 does: `git diff HEAD` plus each untracked file.
3. Update this session's `sessions:` entry with the real one-line outcome (append one only if it is somehow missing — never a second entry for the same session id).
4. Report that execution is complete.

### Finalize

Mark a plan done once the MRs are merged: post a comment to the ticket, transition the ticket status, and set the plan frontmatter to `completed`. Tooling may automate these steps. validate-plan.py rejects a completed plan whose Plan Changes During Execution has no Remember: line, so run the remember pass first. Plans created before 2026-10-18 are exempt. Before the final MR merges, promote what outlives the plan as the handoff skill's "Promote what outlives the plan" item describes, so Linked Artifacts names each promoted path, or reads "Nothing to promote", before the plan is set to `completed`.

### Do not mark a plan complete if

- There is no plan for this session, or the plan is ambiguous.
- The Obsidian config or vault is missing.
- The MRs are not actually merged.
- Plan Changes During Execution has no Remember: line, for a plan created on or after 2026-10-18.

If completion is skipped, state exactly why.

### Guardrails

- The Obsidian plan note is the source of truth for the work.
- Do not invent a plan name. If the active plan is ambiguous, ask before writing.
- Keep this discipline only for real planned work, not trivial Q&A or explanation-only sessions.
