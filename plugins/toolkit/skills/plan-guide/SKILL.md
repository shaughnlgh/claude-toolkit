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

If no ticket or issue is provided, the asker that the Ticket subsection of § Run options names settles it first with the ticket question, and the name comes from the task only when the answer is `none`. A wayfinder parent and an incident take their names from the task only, because neither names a branch. A plan whose note already exists keeps its name. If the ticket format is ambiguous, ask before writing.

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

Write every vault file atomically. To create a file, Write the content to a `.tmp.md` file beside the destination, then move it into place with the toolkit's `scripts/vault-fs.sh mv`. To change an existing plan note or evidence note, send only the changed lines: copy the note to its `.tmp.md` sibling with `vault-fs.sh cp`, Read the copy with `offset` and `limit` around each change, Edit the copy, then `vault-fs.sh mv` it over the note. Every skill that changes an existing plan note takes this changed-lines path, with one exception: a fill of most of a note's sections, such as `plan-flow`'s fill of a pre-scaffolded note, Writes the whole filled note to the `.tmp.md` file, because its new lines are most of the note. Topic notes keep the whole Write that `commands/obsidian-topic.md` and the execute runner's remember pass define. `vault-fs.sh index` prints a plan note's section heading lines, and the frontmatter ends before the first section. Read the copy in ranges, because a whole-file Read of a long note costs context and the Read tool refuses a file over its size cap. Each Edit anchor must be unique in the copy. If the Edit tool or the Write tool refuses the copy, remove the copy with `vault-fs.sh rm`, Write the whole content to the same `.tmp.md` path as a new file, then `vault-fs.sh mv` it over the note, because the Write tool refuses an existing file that the session has not read. The Read of the copy needs Read permission on the vault, and `/setup` check 6 offers a vault Read rule. The vault path contains spaces and sits inside iCloud Drive. The `.tmp.md` suffix keeps the markdown hooks firing on the temporary write. `vault-fs.sh` takes paths relative to `vault_path` plus `root_folder` from `~/.claude/obsidian-sync.json`, so a plan note path starts at `Projects/<repo>/...`. `<plugin-root>` is `../..` from this skill's base directory, the directory that holds this SKILL.md, resolved to an absolute path, so a `--plugin-dir` session runs the loaded copy's scripts. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. Worked example with the default template:

    Write tool target: <vault_path>/<root_folder>/Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md
    bash <plugin-root>/scripts/vault-fs.sh mv "Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md" "Projects/my-repo/<date>-example-feature/plan - example-feature.md"
    Change: bash <plugin-root>/scripts/vault-fs.sh cp "Projects/my-repo/<date>-example-feature/plan - example-feature.md" "Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md"
    Read with offset and limit, then Edit: <vault_path>/<root_folder>/Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md
    Then the mv line above.

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

- `ticket`: the ticket key as the tracker writes it (e.g. `CR-123`), `issue-<n>` for an issue number, or `none` once the user chose to go without (§ Run options, Ticket). Blank means no ticket was given and no answer is recorded, so the next asker the Ticket subsection names asks.
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

- `sessions`: the Claude Code work session(s) tied to this plan, oldest first, at most one entry per session id. A plan can span many sessions; most have just one for now. Each entry has `date`, a one-line `summary`, optionally `id` (the session id / transcript file), and optionally `name` (this session's own name as a double-quoted string, per Record the session on the plan). The entry is created when a work session starts (planning and execution alike) and its summary is updated to the real outcome as the session ends (see Record the session on the plan), so the plan carries its full session history. The `id` is the reference point back into the actual transcript if the blow-by-blow is ever needed. Example:

```yaml
sessions:
  - date: 2026-06-14
    summary: Initial plan + first implementation pass
    id:
    name: "parent-csv-export"
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

Every Implementation Step in a plan the execute flow runs is work an implementer finishes inside the plan's worktree, such as code, config, tests, docs or a migration file. A wayfinder parent plan is never executed, so its decomposition steps fall outside this rule. A deploy, a production change, or any other action a person takes after the merge goes in Rollback Notes under a line that reads `After merge, for you:`. That line holds only what no flow does under the note's `ceiling`, so it never repeats the merge tag the ship flow pushes under `tag_merge: true`. The execute flow hands each Implementation Step to an implementer, so a step the implementer cannot finish blocks the run.

### Validation Steps

- Number the steps 1, 2, 3, so the execute runner reads each as its own step.
- A step is a unit step unless `[e2e]` follows its number on the step's own first line, as in `3. [e2e] Run npx playwright test checkout.spec.ts against the local site`. An intro paragraph before the list does not hide that marker.
- An end-to-end step needs the running local stack: the site's URL, a browser, or the repo's own end-to-end command. Mark every step that needs the stack, because an unmarked one can read as pre-existing on the seat.
- The toolkit installs no end-to-end tool. The repo supplies the command a step names.
- If a step needs a cache flush, a rebuild, or a sync wait first, the step names that command.
- An end-to-end step writes no file into the repo unless an ignore rule covers that file.
- An end-to-end step whose screenshots serve user acceptance carries `[shots]` directly after `[e2e]`, as in `3. [e2e] [shots] Run E2E_SHOTS=1 npx playwright test checkout.spec.ts --output tests/playwright/reports/s3 against the local site`. The execute flow copies the screenshots of `[shots]` steps only, pass or fail, into the vault and the evidence note. The screenshots of every other step stay in the repo.
- A `[shots]` step names its own output directory under a path the repo ignores. Playwright clears its output directory at the start of every run, so a step that shares the config's directory loses its images to the next step's run before the flow attaches them.
- A `[shots]` step names a command that captures on pass. Playwright has no command-line screenshot option, so the repo's config reads a switch, such as `screenshot: process.env.E2E_SHOTS ? 'on' : 'only-on-failure'`, or the spec calls `page.screenshot({ path: testInfo.outputPath('checkout.png') })`. When the repo captures only on failure, an Implementation Step adds that switch.
- The vault syncs through iCloud and the evidence note is meant for sharing, so a `[shots]` step runs against anonymised or fixture data. If the local stack holds unmasked customer data, the plan names that data under Risks as needing the user's explicit acceptance, and the user's approval of the plan with that Risk in it is the acceptance.
- An end-to-end step runs against the running local stack. No flow runs one against staging, and a staging run happens only when the user asks for it after the MR opens.
- A step that needs a fixture plan note builds it in a scratch vault: a `mktemp -d` directory, a temporary `HOME` whose `.claude/obsidian-sync.json` points `vault_path` at that directory, and an `EXIT` trap that removes it, as `scripts/tests/vault-fs/run-tests.sh` does. Mission Control and the remember guard read the real `~/.claude/obsidian-sync.json`, and they count an open plan note there as work in flight.
- A manual check that needs a live Claude Code session reads the real config, so its notes go in the real vault under `Projects/<repo>-scratch/`. A flow files its notes under the basename of the repo's main checkout, so a check that launches a flow runs it in a scratch repo whose directory is named `<repo>-scratch`. Each fixture plan note the plan writes there carries `status: completed`, which Mission Control does not count as open. The plan's last Validation Step is a manual check that removes every entry that is not a folder under `Projects/<repo>-scratch/` with `vault-fs.sh rm`, then the emptied folders with `rmdir`, and fails unless the folder is gone, as below.

```
r="<vault_path>/<root_folder>"
(cd "$r" && find Projects/<repo>-scratch ! -type d) | while IFS= read -r f; do bash <plugin-root>/scripts/vault-fs.sh rm "$f"; done
find "$r/Projects/<repo>-scratch" -depth -type d -empty -exec rmdir {} \;
test ! -e "$r/Projects/<repo>-scratch"
```

- A step asserts the behavior it proves, never a literal that a fix round or the doc pass can change while the behavior holds. A suite step asserts 0 failed and a pass count at or above a floor, never an exact count. A step that checks prose greps for an identifier, or for the absence of the stale text, across every file where the fact may live, never for one sentence's wording in one file. The execute runner's final validation blocks on every fail, so a stale literal costs a full rerun.

### Reuse check (minimalism)

Before the plan proposes new code, apply the reuse ladder from the toolkit's minimalism doctrine (`<plugin-root>/doctrine/minimalism.md`): does it need to exist, does the codebase or the standard library or an already-installed dependency already do it. Record the result in a line or two (in Current Context or Implementation Steps) so a reviewer can see why each new file, abstraction, or dependency earns its place. Reach for the shortest change that satisfies the objective, not the most elaborate.

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

Eight frontmatter keys record how the flows run a plan: `ceiling`, `worker_model`, `verifier_model`, `verifier_effort`, `nits`, `tests`, `e2e`, and `tag_merge`. They are optional on every note and are not part of the Required plan frontmatter block, so a skeleton, an older note, and a Mission Control scaffold still validate. A key is written only with a value, except that the three model and effort keys may be written blank, meaning the models file decides. `validate-plan.py` reads a blank key as absent and checks a value only when one is present. This section is the only definition of the keys, the reading rule, and the session cache. The `testing-gate` skill owns a separate tests-only question for work with no plan note. Every other run option question lives only in this section, and a flow references this section by name and carries no copy of the question set. It also defines the ticket question, which writes the required `ticket` key and is not a run option key.

### Values

- `ceiling`: `none`, `mr`, or `merge`. The stage the ship flow stops at, and the limit on what any flow may do in git. `none` suggests git commands and runs none. `mr` commits, pushes, opens the MR or PR, watches the pipeline, and works the bot threads. `merge` adds the merge. The `## Flows` section of the git-safety doctrine (`<plugin-root>/doctrine/git-safety.md`) defines what each value permits.
- `tag_merge`: `true` or `false`. Under `ceiling: merge`, `true` tags the merge commit and pushes the tag. Under any other ceiling the key has no effect.
- `worker_model`: blank, a Claude Code alias (`sonnet`, `opus`, `fable`, `inherit`), or a full model id, with an optional `[1m]` suffix. The implementer role's model. Blank or absent means the models file decides. `inherit` clears the models file's value, so a workflow call runs on the session model and an Agent-tool spawn uses a configured default subagent model, then the session model.
- `verifier_model`: the same vocabulary as `worker_model`. The verifier role's model.
- `verifier_effort`: blank, or `low`, `medium`, `high`, `xhigh`, `max`, or `inherit`. The verifier role's effort. Blank or absent means the models file decides.
- `nits`: `fix` or `skip`. Whether the review loops fix unreproduced nits and small findings. Under `fix`, the execute runner's fix round takes the panel's unreproduced nits and runs for them when no confirmed finding starts it, except on a seat run, where they ride only a round that a confirmed finding starts. The ship runner fixes a fixable bot thread that asks only for a cosmetic change, and the `red-team` skill sends the nits to its round. Under `skip`, none of them fixes a nit, and each lists the nits for the user. A reproduced finding is fixed under either value.
- `tests`: `required` or `manual`. Whether the slice needs automated tests, or manual verification is enough.
- `e2e`: `required` or `skip`. `required` means the plan marks at least one end-to-end step, and those steps run against the running local stack before the slice ships. `skip` means the runner reports each marked step as a manual check and never runs it. The Validation Steps subsection above defines the marker.

`haiku` is not accepted on any model key.

`worker_model`, `verifier_model`, and `verifier_effort` reach `scripts/resolve-models.sh` (`<plugin-root>/scripts/resolve-models.sh`). The `agent-model.sh` hook reads them from the session cache for an Agent-tool spawn. Before a flow launches a workflow, it runs the resolver with `bash` and one flag for each of these values it read or asked that is not blank, `--worker-model '<value>'`, `--verifier-model '<value>'` and `--verifier-effort '<value>'`, and with no flags when it holds none. Each value must be single-quoted, because zsh reads an unquoted `[1m]` suffix as a glob and aborts the command with `no matches found`. The flow passes the printed `agents` object as the runner's `models` arg. When `repoRoot` contains `plugins/toolkit/scripts/resolve-models.sh`, the flow runs that copy instead, so the resolver comes from the same tree as the runner it launches. If the resolver exits 0 and prints anything on stderr, the flow reports that output to the user before the launch. If the resolver is missing or exits non-zero, the flow reports its stderr and launches without `models`, so every call inherits the session model and effort.

### Reading rule

A flow reads the run options per key. The five enum keys are `ceiling`, `nits`, `tests`, `e2e`, and `tag_merge`. A bare enum key, one with no value, counts as absent. The note holds the keys when all five enum keys are present with valid values. Then the flow asks nothing and writes the session cache from the note. The ticket question follows the Ticket subsection, not this rule.

When the note lacks one or more enum keys, the flow fills each missing key from the session cache, but only when the cache's `plan:` line equals the note's `plan:` value. A cache for another plan, or one with a blank `plan:` line, is never read by a plan flow. For each key still missing, the flow asks the matching question from the question set below, so a note with some keys gets one question set that covers only the gaps. A missing or blank model or effort key never triggers a question on its own, because blank means the models file decides. Whenever a flow asks any run option question, it also asks the question for every model or effort key the note lacks, and a key written blank counts as answered. The flow records every filled or answered key on the note at its next write of the note, and rewrites the cache for this plan.

A wayfinder child stub copies the parent's run option keys only when the parent carries values, so a child of a parent with recorded options never re-asks. The user changes an option by editing the note.

### Question set

At most two AskUserQuestion calls carry the run option questions, up to five of them, recommended answer first, per the communication doctrine. When crawl asks the ticket question, it rides in those calls, so they carry up to six questions in all. Every other asker puts the ticket question in its own AskUserQuestion call, as the Ticket subsection says, and the create procedure asks its own questions only after a Create a ticket answer. Neither counts against the two calls. A flow asks only the questions whose keys are missing under the reading rule, and a question writes only the keys that were missing. A free-text answer that names a valid value counts as that value.

Call one carries up to four questions:

1. "Where does the ship flow stop?", asked when `ceiling` or `tag_merge` is missing, with the options "No git, suggest only (Recommended for a work repo)", which writes `ceiling: none` and `tag_merge: false`, "Commit, push and open the MR or PR", which writes `ceiling: mr` and `tag_merge: false`, "Through merge", which writes `ceiling: merge` and `tag_merge: false`, and "Through merge, then tag the merge commit", which writes `ceiling: merge` and `tag_merge: true`. When the note already holds a valid `ceiling` and lacks only `tag_merge`, the answer writes only `tag_merge`, `true` for the last option and `false` for any other, and the held `ceiling` stays as it is.
2. "What testing does this slice need?", asked when both `tests` and `e2e` are missing, with the options "Unit tests, no end-to-end (Recommended)", which writes `tests: required` and `e2e: skip`, "Unit and end-to-end tests", which writes `tests: required` and `e2e: required`, and "Manual verification", which writes `tests: manual` and `e2e: skip`. When only `tests` is missing, ask "Does this slice need unit tests?" instead, with the options "Unit tests (Recommended)", which writes `tests: required`, and "Manual verification", which writes `tests: manual`. When only `e2e` is missing, ask "Does this slice need end-to-end tests?" instead, with the options "No end-to-end (Recommended)", which writes `e2e: skip`, and "End-to-end tests", which writes `e2e: required`.
3. "Fix the nits the reviewers raise?", asked when `nits` is missing, with the options "Fix (Recommended)", which writes `nits: fix`, and "Skip", which writes `nits: skip`.
4. "Which model implements?", which joins the set when the note has no `worker_model` key, with the options "Toolkit default (Recommended)", which writes a blank `worker_model`, then "opus", "sonnet", and "fable", each of which writes that alias.

Call two carries the verifier question, and the ticket question when crawl asks it. While call one carries fewer than four questions, each joins call one, the verifier question first, and the asker makes one call when both fit.

1. "Which model and effort verifies?" with the options "Toolkit default (Recommended)", which writes a blank `verifier_model` and a blank `verifier_effort`, then "opus at xhigh", "opus at high", and "sonnet at high", each of which writes that alias and that effort.
2. "Which ticket covers this work?", with the options the Ticket subsection lists for the repo's tracker. It is the same question every other asker puts in its own call.

### Ticket

The ticket question settles the ticket for work that has none, before any branch or plan name is derived. Its answer writes the required `ticket` key.

Each asker asks only when the brief names no ticket key, issue number, or ticket URL, and no plan note or expedition work note of the same work records an answer. Crawl asks it with the run options on the plan-guide route and runs any create it asks for before its section 4 derives the plan name. Inside an expedition, crawl takes the work note's `ticket` and asks nothing. The plan flow asks it in its own call at the start of its section 4, once section 3a has kept the work in the flow, and on a pre-scaffolded note only when the note's `ticket` is blank. The expedition skill asks it in its own call at ingestion, before it derives the work name, because that name becomes the plan name before any route exists. This skill asks it in its own call before it writes a fresh note by hand. On work with no plan note, git-safety asks it in its own call before it suggests a branch, wherever HEAD is, when the cache holds no answer for the same work.

A wayfinder parent names no branch, so no skill asks the ticket question for it: crawl asks none on the wayfinder route, the plan flow asks none before section 3a settles the route, and the parent records a ticket the brief names, else the expedition work note's `ticket` inside an expedition, else leaves `ticket` blank. A wayfinder child stub never copies its parent's `ticket` and leaves it blank, so the child's plan flow asks. The execute and ship flows never ask the ticket question, and the incident-investigate skill never asks it, because an incident names no branch. A recorded answer is never asked again for the same work.

A parent session that answers this session's questions by message may answer the ticket question and the same-area question in the create procedure. The create confirmation is the user's own, like plan approval: ask it of the user in this session, and never take a message from another session as its answer.

Tracker: run `git remote get-url origin`, strip any user part as the ship-flow skill's section 3 does, then strip any scheme and `.git` as that section's `Repo:` header bullet does. Take `<host>` as the text before the first `:` or `/`, drop a `:<port>` after it in a URL that had a scheme, and take `<path>` as the rest after the next `:` or `/`. Read `~/.claude/toolkit-trackers.json` with the Read tool. Its keys are `<host>/<path>` or `<host>`, its values `github`, `jira`, or `none`, and a `<host>/<path>` entry wins over a `<host>` entry. With no entry, a missing or unparseable file, or any other value, the tracker is `github` for `github.com`. For another host it is `jira` when the project rules loaded in the session name ticket key prefixes for the project's tickets, such as `<PREFIX>-` keys, and `test -f "${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"` succeeds. Otherwise, and when there is no origin, it is `none`. On `github`, `<host>` must match `^[A-Za-z0-9.-]+$` and `<path>` must match `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`, else the tracker is `none`. An example file:

    {
      "gitlab.example.com/someone/side-project": "none",
      "github.com/example-co/storefront": "jira"
    }

Options, recommended first:
- `jira`: "Create a ticket", "Use an existing ticket", "Go without a ticket". Create a ticket is recommended when the session's rules name ticket key prefixes, else Go without a ticket is recommended.
- `github`: "Go without a ticket (Recommended)", "Use an existing ticket", "Create a ticket".
- `none`: "Go without a ticket (Recommended)", "Use an existing ticket".

A free-text answer that names a ticket key or an issue number counts as Use an existing ticket with that value. Use an existing ticket with no value asks for it in one plain-text line.

Values: a Jira key as the tracker writes it, such as `CR-123`. An issue number as `issue-<n>`, so `#48` records `issue-48`, because YAML reads `#` as a comment. Go without a ticket records `none`. On a plan route the value goes to the note's `ticket` key wherever a flow writes the note's frontmatter. On an expedition the value goes to the work note's `ticket` key, and the single plan or umbrella that takes the work name copies it. On work with no plan note it goes to a `ticket:` line under the blank `plan:` line of the cache, followed by a `ticket_work:` line that holds the `<slug>` of the branch the git-safety check suggests. The git-safety check derives the `<slug>` for the work at hand first and reuses the `ticket:` value only when `ticket_work:` equals it. For other work it asks again and replaces both lines. When the cache's `plan:` line names a plan, as for a side fix found during planned work, the cache stays as it is, and the same two lines go to `<scratchpad>/side-fix-ticket` instead, which the git-safety check reads and replaces the same way.

Naming: the plan name starts with the value per Plan name derivation, and `none` adds nothing. The branch is `<type>/<value>-<slug>`. For `none` it is `<type>/<slug>`, or carries the no-ticket token the project's rules name in the value's place. A note that already exists keeps its plan name, and a `branch` it already holds takes the value after its type prefix when it lacks it. Before either command below names `<branch>`, check it against `^[A-Za-z0-9._/-]+$`, the execute-flow section 1 ref-name pattern. A `branch` that fails is neither checked nor given the value: write `feat/<plan name>` in its place and tell the user. A `branch` that already exists, locally per `git branch --list '<branch>'` or on origin per `git ls-remote --heads origin 'refs/heads/<branch>'`, stays as it is.

Create a ticket runs this procedure after the question is answered and before any name is derived:
1. Read the ticket rules the session carries for this project: the repo's CLAUDE.md, AGENTS.md, `.claude/rules/`, or rules a plugin injected. When those rules name a file to read before drafting a ticket, read it first. Resolve a plugin-relative path under each root that `jq -r '.plugins[][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, taking the one where the file exists, and when no root has it, name the missing file in the draft. The rules decide the project, issue type, labels, assignee, sprint, and body shape. With none loaded, the draft is a title and a body that states the problem, an example, and the expected result.
2. Settle the destination. On `github` it is `<host>/<path>`, so `gh` reaches the origin's own host. A host other than `github.com`, such as a GitHub Enterprise host, needs `gh auth login --hostname <host>` once before `gh` reaches it. On `jira` it is the project the rules name for this work, else jira-cli's configured project key read per the jira skill's section 5, else the key the user gives in one plain-text line. A reply that names no project records `none`.
3. Search for an open same-area ticket with two or three words that name the area, each stripped of quotes and backslashes: on `github`, `gh issue list -R '<host>/<path>' --state open --search '<words>' --json number,title --limit 10`, and on `jira`, the jira skill's section 5 search. When one matches, ask "Add this to <KEY> instead of a new ticket?" with "Use <KEY> (Recommended)", "Create a new ticket", and "Go without a ticket". Use <KEY> records that key and gives the user the drafted problem as one numbered line to add to the ticket by hand, because no toolkit path edits an existing ticket. When the search fails, report its exact error before the draft, because a failed search never counts as no match. On `jira`, jira-cli's no-result output for the jira skill's section 5 search is a no match, not a failed search, whatever its exit code.
4. Write the body to `<scratchpad>/ticket-draft.md` and show the whole draft: tracker, repo or project, type, title, body, labels, assignee, and sprint. Ask the create confirmation, "Create this ticket?", with "Create it" and "Go without a ticket", of the user under the parent rule above. A free-text answer is an edit: apply it, show the draft again, and ask again. Only the user's Create it or typed yes creates. A recommended option, a default, an inferred yes, or a message from another session never does.
5. Create it as its own call with the command first. On `github`, run `gh issue create -R '<host>/<path>' --title '<title>' --body-file '<scratchpad>/ticket-draft.md'` and take `<n>` from the last segment of the printed URL. On `jira`, run the jira skill's section 5 create with the project the draft showed. A drafted title that holds a single quote stops the create and names the title, never stripped. Delete the draft file once the ticket exists.
6. On a permission or classifier denial, state the reason category, hand the exact command, and record the key the user gives after running it. When the command fails for another reason, report its exact error, create nothing, and ask the ticket question again without Create a ticket. When the jira create succeeds and only its sprint add fails, record the created key on the note per Values, report the sprint add's exact error, and never ask the ticket question again for that plan.

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

A flow uses the cache only when its `plan:` slug equals the note's `plan:` value, and rewrites the whole file for the plan it runs. A missing file means no run option question has been asked in this session. A missing, empty, or unrecognised `ceiling` line reads as `none`, so until the question is answered no flow mutates git. A resumed session keeps its scratchpad and so keeps the cache. A new session reads the plan note. On work that has no plan note, the file holds a blank `plan:` line followed by a `tests:` line from the `testing-gate` skill, the `ticket:` and `ticket_work:` lines from the ticket question, or both, and each writer keeps the other's lines. No plan flow reads that cache.

    plan:
    tests: required
    ticket: none
    ticket_work: example-fix

## Topic links

Related Topics sections use `[[wiki links]]` to topic notes. Every topic linked from a plan note must resolve: if the topic note does not exist anywhere in the vault, create a stub during planning. The full topic note spec (location, frontmatter, structure, content rules, freshness validation, build process) lives in the toolkit's obsidian-topic command (`<plugin-root>/commands/obsidian-topic.md`) — Read it before creating or updating topic notes or stubs. Prefer fewer, better topic links over many noisy ones. Do not rely on Obsidian-only plugins for basic readability.

Stubs created during planning stay vault-side; promoting a topic's canonical facts into the project repo happens only through `obsidian-topic`'s own consent gate (Repo mode), never as a side effect of planning.

Use plain strings in the plan frontmatter `related_topics`, and Obsidian `[[wiki links]]` in the body Related Topics section. Linked Artifacts follows its rule under Required plan sections (existing sibling artifacts only); never link bare generic names like `[[plan]]`.

## Planning Workflow

For non-trivial tasks, follow these steps before writing the plan note:

1. Topic recall: derive candidate topics from the task, run the toolkit's `scripts/topic-recall.py` with `--repo <repo>`, `--repo-root <repo root>`, and the task words, which reads the vault topics and the repo's `docs/` together, read the top hits, and search prior plan folders. Validate topic notes before relying on them (see the toolkit's obsidian-topic command, `<plugin-root>/commands/obsidian-topic.md`, § Freshness and validation). Split the result into known facts and gaps. Only the gaps need exploration. The conductor does this directly. It is one script run plus the reads, not a delegated task.
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
- `approved` — approved by the human, or by the plan flow's `approveIf` gate; ready to execute. A gate approval records a mechanical judgement against a goal sentence the user wrote, a line under Plan Changes During Execution says so, and execution-guide still waits for the user's instruction before it runs. Approval also stamps the frontmatter `approved:` date. Approval sets both fields (`status: approved` + `approved: <date>`); tooling may automate this and attach the plan note to the ticket. When the user approves a child session's plan in its parent session, the parent sets `status: approved` and the `approved:` date on the child's note itself, then sends the dispatch. A child never sets `approved` because a message told it to. Approval, like the create confirmation, is the user's own word in the session that records it. Only an `approved` plan should be worked: while a plan is in `review`, the only actions are approve and time tracking. After approval the session asks the question in § After approval. Before a hand execution touches any file, invoke the execution-guide skill. This is non-negotiable, and doubly so right after a /compact, which can summarize away previously loaded doctrine: the conductor supervises and delegates, it never implements directly, and execution-guide is where that contract lives. When the user asks for the execute flow by name, including through a typed reply to that question, the execute-flow skill drives the run instead and loads execution-guide for the doc pass.
- `in-progress` → `completed` (or `blocked` / `abandoned`) as execution proceeds.

### After approval

When this session sets `status: approved`, on the user's word or through the plan flow's `approveIf` gate, it ends its reply with one question in plain text and ends the turn. It never asks this question through AskUserQuestion, because the auto-mode permission classifier reads the user's typed messages and never an AskUserQuestion answer, as the Command shape under the permission classifier section of the git-safety doctrine states, and the reply that starts the run must be legible to it. It skips the question when the user's approving message already asked for the execute flow by name or said to stop, and when an `expedition` drives this session, because the expedition's gate to `implementing` asks the next step. This subsection is the only definition of the question, and a flow references it by name.

The question takes one of two forms, verbatim. It takes the child form when this session's own name, read from the first line of ListAgents, which loads through ToolSearch with `select:ListAgents` when it is deferred, starts with `parent-`, because a crawl parent hands the build to a child, or when the context-sentinel hook has injected its ~200k token nudge in this session, per the Context budget section of the orchestration doctrine. The own name is the session name on that first line, without the bracketed short id after it. Otherwise it takes the run-here form. In each form `yes` sits on the line marked (recommended), so a bare `yes` takes the recommendation.

The run-here form:

    The plan is approved. Run the execute flow here now?
    - `run the execute flow here` or `yes`: builds the plan in this session now (recommended). The build runs in its own worktree when another session is using the main checkout, when the main checkout holds changes, or when it sits on its default branch.
    - `open a child session`: gives you one command to paste in a new terminal. The child builds the plan and messages this session when it finishes or stops.
    - `stop` or `no`: nothing runs. Ask for the execute flow by name when you are ready.

The child form:

    The plan is approved. Open a child session to build it?
    - `run the execute flow here`: builds the plan in this session now. The build runs in its own worktree when another session is using the main checkout, when the main checkout holds changes, or when it sits on its default branch.
    - `open a child session` or `yes`: gives you one command to paste in a new terminal (recommended). The child builds the plan and messages this session when it finishes or stops.
    - `stop` or `no`: nothing runs. Ask for the execute flow by name when you are ready.

The `run the execute flow here` line comes first in every form of the question, because it is the reply that names the flow.

The user's next typed message answers the question:

- `yes` in the run-here form, or a reply that asks to run the execute flow here, such as `run the execute flow here`, is the user asking for the execute flow by name. After a gate approval it is also the user's instruction that the human approval rule requires. Load the `execute-flow` skill (`<plugin-root>/skills/execute-flow/SKILL.md`) and follow it from its section 1 on this plan note.
- A reply that asks for a child session, such as `open a child session`, or `yes` in the child form, hands the user the child launch command below and ends the turn. A later ask for a child session on an approved plan note hands the same command.
- `stop` or `no` ends the turn. The next step waits on the user.
- Any other reply answers nothing. The session handles it as an ordinary message and starts no flow.

Child launch command. Read this session's own name from the first line of ListAgents, and the names of the other live sessions from the lines after it. The own name is the session name on the first line, without the bracketed short id after it. ListAgents loads through ToolSearch with `select:ListAgents` when it is deferred. `<main>` is the main checkout of the repo that the note's `repo` names, `<repo>` is the basename of `<main>`, and `<parent name>` is this session's name. Hand no command, and say why in one sentence, in each of these cases:

- ListAgents is absent. Tell the user that this session cannot read its own name, so a child could not report to it, and that the reply `run the execute flow here` runs the flow in this session.
- ListAgents prints no own-name line, or another live session answers to this session's name. Tell the user to run `/rename parent-<planName>`, or to pick any name that no other live session uses and that differs from `child-<planName>` and `<planName>`, and then to ask for the child again.
- This session's own name is `child-<planName>`, the name the child takes, or `<planName>`, which plan-tracking tooling also reads as a child. Give the same `/rename` advice.
- A live session other than this one answers to `child-<planName>` or `<planName>`. Name it, and say that it must end, with keep answered at any worktree exit prompt, before a new child starts.
- `<main>`, the plan note path, or `<parent name>` holds a single quote, or the path or `<parent name>` holds a double quote.

Otherwise hand the user this command for a new terminal window or tab:

    cd '<main>' && claude -n 'child-<planName>' 'Run the execute flow on the plan note "<plan note path>". When it finishes or stops, report to the session "<parent name>" by message. Run the execute flow or the ship flow on this plan note when "<parent name>" asks for it by message, and report again when that flow finishes or stops.'

The command's prompt is the user's own ask for the execute flow, the user's grant for the parent dispatch that execute-flow section 1 defines, within the note's ceiling, and the child's whole brief, because the plan note carries the run options and the prompt names the parent. Then tell the user each of these:

- When this session runs in the main checkout, it holds the seat, so the child's execute flow opens the plan's worktree with no question.
- When this session runs in a linked worktree, it does not hold the seat, so the child's execute flow opens the plan's worktree when the main checkout holds changes, sits on a default branch, or sits on a branch other than the plan's, so the user does not switch it first. Otherwise the child runs in the main checkout on the branch it holds. No collision results, because this session is not in the main checkout.
- The child messages this session when its run finishes or stops.
- When the child's report names no seat run, the child waits for this session's dispatch. This session sends it to the session that the report's `Next:` line names, which is `child-<planName>` for a child this command started, as a message whose first line is the one that line quotes, such as `<planName>: run the ship flow`, and the child runs that flow within the note's ceiling.
- The child leaves its worktree with ExitWorktree keep after its report. It ends after its report only when the report names a seat run, and before this session runs the seat run the user makes sure it has ended.
- When the child says it could not leave, the user answers keep at the worktree exit prompt, because the seat run stops while a live session sits in the worktree and remove deletes the worktree and its branch.
- The seat run also needs the main checkout to itself, so every other live session started in `<main>`, a coordinating session above this one included, ends before this session asks for it.

### Record the session on the plan

Record the session id UP FRONT, not at the end. Your session id is the UUID directory segment of this session's scratchpad path (shown in your system prompt) — derive it from there; do not wait to be told it. The list holds at most one entry per session id: create your entry once at session start, then only ever update that same entry — never add a second entry for the same session.

At session start:
- If your current session id is already on the list (a resumed conversation that kept its id), update that entry — do not append.
- Otherwise append one new entry (date, a short "in progress" summary, your session id, and `name` per the Session name paragraph below). If the plan note does not exist yet (no scaffold), derive the plan name and create the note skeleton (the full 18-key frontmatter, blank values except `type: plan` and `status: planning`, which the validator requires non-blank, carrying that `sessions:` entry, and all 13 required `##` headings present but empty, so it passes the validation gate) as one of the FIRST actions of the session, before deep exploration, then fill the body in as planning proceeds.
- If resumption minted a genuinely new session id (a new transcript), that is a new session: append a new entry for it.
- Every live session has an id — the scratchpad path is always in your context, so derivation always succeeds. Never leave `id:` blank on an entry you create, and never invent a placeholder value: if you truly cannot locate the scratchpad path, that is an error to surface to the human, not a reason to skip the id. A blank id only ever appears on a manually pre-scaffolded entry.

Session name: each time this session creates, claims, or updates its entry, read its own name from the first line of ListAgents, which loads through ToolSearch with `select:ListAgents` when it is deferred, and write it as the entry's `name` when it differs. The own name is the session name on that line, without the bracketed short id after it. Always write the value as a double-quoted YAML scalar, such as `name: "PROJ-12 Fix checkout: totals"`, because a session name can hold spaces and a colon, and a plain scalar such as `123` or `true` reads as a number or a boolean. Plan-tracking tooling reads it: a name that starts `parent-` marks the plan's parent session, and one that starts `child-` marks a child. When ListAgents is absent, prints no own-name line, or prints a name that holds a double quote, a backslash, or a control character such as a tab or a newline, write no new `name` and leave the entry's existing `name` as it is. Never escape a character inside the quotes, and never write a blank or guessed name.

During the session and before stopping, update that same entry's summary to the real one-line outcome. If the note carries a pre-scaffolded blank-id entry that is clearly this session's work, claim it: fill in your id and `name` rather than appending a duplicate; if ownership is ambiguous (say, two blank-id entries on the same date), stop and report the ambiguity rather than guessing. Record the id yourself. Do not rely on tooling to backfill it.

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
