---
name: plan-guide
description: >-
  MANDATORY companion for plan work. Invoke BEFORE creating, filling in, updating, or
  closing out any plan note (plan - <name>.md) in the vault — including
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

Workflow artifacts are written directly into the vault, at the location the vault config defines, `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent, (`vault_path` + `plan_folder_template`):

    <vault_path>/<plan_folder_template>
    e.g. with the default template: <vault_path>/AI/Claude-Code/Projects/{repo_name}/{date}-{plan_name}/

The plan name must be short, lowercase, kebab-case, and derived from the task purpose. The date is the local date (YYYY-MM-DD) when the plan is created. The plan name must match: `^[a-z0-9][a-z0-9-]*$`

### Artifact naming

Every artifact filename embeds the plan name so note names are unique across the vault and wiki links resolve unambiguously:

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

Resolve the vault path and folder template from the vault config: `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent.

### Repo-local plans directory

Do not write workflow artifacts (plan, handoff, and session notes) to repo-local `.claude/plans/`. The vault is the only location for these workflow artifacts; it does not govern repo-owned knowledge artifacts (facts, decisions, playbooks, glossary), which follow `doctrine/repo-artifacts.md` instead.

### Built-in plan directory

`~/.claude/plans/` is Claude Code's built-in plan mode directory. It is not part of this workflow.

## Required Artifacts

The one required artifact, written to the vault plan directory:

- `plan - <plan-name>.md` — the single source of truth. A living document: kept current during execution (decisions, gaps, deviations) so it records both what was intended and what actually happened. Carries its own session history and worklogs in frontmatter.

Other skills may create optional sibling artifacts in the same directory (e.g. `handoff - <plan-name>.md`); each is linked from the plan's Linked Artifacts section when — and only when — it is actually created.

The plan note plus git (the branch diff and, after a squash-merge, the squashed commit) plus the session ids recorded on the plan are the complete record of what was done. Execution details belong in the plan note under "Plan Changes During Execution". Topic notes (the cross-plan knowledge layer) are maintained during planning and execution, not written at finalization.

Write every vault file atomically. To create a file, Write the content to a `.tmp.md` file beside the destination, then move it into place with the toolkit's `scripts/vault-fs.sh mv`. To change an existing plan note or evidence note, send only the changed lines: copy the note to its `.tmp.md` sibling with `vault-fs.sh cp`, Read the copy with `offset` and `limit` around each change, Edit the copy, then `vault-fs.sh mv` it over the note. Every skill that changes an existing plan note takes this changed-lines path, with one exception: a fill of most of a note's sections, such as `plan-flow`'s fill of a pre-scaffolded note, Writes the whole filled note to the `.tmp.md` file, because its new lines are most of the note. Topic notes keep the whole Write that `commands/topic.md` and the execute runner's remember pass define. `vault-fs.sh index` prints a plan note's section heading lines, and the frontmatter ends before the first section. Read the copy in ranges, because a whole-file Read of a long note costs context and the Read tool refuses a file over its size cap. Each Edit anchor must be unique in the copy. If the Edit tool or the Write tool refuses the copy, remove the copy with `vault-fs.sh rm`, Write the whole content to the same `.tmp.md` path as a new file, then `vault-fs.sh mv` it over the note, because the Write tool refuses an existing file that the session has not read. The Read of the copy needs Read permission on the vault, and `/toolkit:setup` check 6 offers a vault Read rule. The vault path can contain spaces. The `.tmp.md` suffix keeps the markdown hooks firing on the temporary write. `vault-fs.sh` takes paths relative to `vault_path` plus `root_folder` from the vault config, `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent, so a plan note path starts at `Projects/<repo>/...`. `<plugin-root>` is `../..` from this skill's base directory, the directory that holds this SKILL.md, resolved to an absolute path, so a `--plugin-dir` session runs the loaded copy's scripts. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/toolkit:override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. Worked example with the default template:

    Write tool target: <vault_path>/<root_folder>/Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md
    bash <plugin-root>/scripts/vault-fs.sh mv "Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md" "Projects/my-repo/<date>-example-feature/plan - example-feature.md"
    Change: bash <plugin-root>/scripts/vault-fs.sh cp "Projects/my-repo/<date>-example-feature/plan - example-feature.md" "Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md"
    Read with offset and limit, then Edit: <vault_path>/<root_folder>/Projects/my-repo/<date>-example-feature/plan - example-feature.tmp.md
    Then the mv line above.

## Plan Sync

After creating or refining the plan note, it is written directly to the vault plan directory. There is no separate sync step for new plans.

If the plan note cannot be written to the vault (vault missing, path error, sync issue), stop and report the failure. Do not write repo-local workflow artifacts.

### Do not write if

- The active plan directory is ambiguous.
- The plan note does not exist or has not been created yet. (Exception: an expedition's `work - <name>.md` and `brief - <name>.md`, and an incident investigation's `incident - <name>.md`, precede the plan note by design. Each derives the plan name at ingestion per this skill's naming rules, so the artifact carries the eventual plan name and lands in the eventual plan directory.)
- The vault config is missing.
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
- `modules`: for plans that also change owned vendor modules (each its own git repo) **nested under the project repo**, the list of modules touched. Leave blank for single-repo plans (the common case). Each entry has `name` (composer package), `path` (§ Repos and modules), `branch`, and `mr`. Track each module's branch/MR alongside the project's. Example:

```yaml
modules:
  - name: acme/module-payments
    path: vendor/acme/module-payments
    branch: fix/payment-timeout
    mr:
```

- `repos`: for plans that span multiple **sibling top-level repos** (each its own `<projects root>/<repo>`, not nested under another), the list of code repos touched. Use this when `repo` is a grouping rather than a single code repo (e.g. a storefront umbrella covering a backend repo plus a PWA repo). Each entry has `repo` (the directory name under the projects root), `branch`, and `mr`. Each is its own work component with its own branch/MR. Use `modules` for nested vendor modules and `repos` for sibling repos; a plan can use either, both, or neither. § Repos and modules defines the repo set, the branch default and the ship order. Example:

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
    name: "worker-execute-csv-export"
```

- `related_topics`: plain strings, not wiki links. Use wiki links only in the body.
- Do not invent ticket values. Do not invent tags or topics — use obvious project/task topics only.

### Repos and modules

This subsection is the one definition of the repo set, the module path, the branch default and the ship order. The execute flow (execute-flow section 2b) and the ship flow (ship-flow section 3b) read them from here.

- Repo set: the `repos:` entries, or the note's `repo` when `repos:` is empty, plus each `modules:` entry, nested under the note's `repo`. With `repos:` set, the note's `repo` is a grouping name unless an entry names it. A note whose repo set holds two or more members is a several-repos note. The flows run a several-repos note from a session started in the projects root, the directory that holds each repo as `<projects root>/<repo>`.
- Module path: a module's `path` is where Composer installs the package in the project, and it ends with `vendor/<name>`, such as `vendor/acme/module-pay` or `src/vendor/acme/module-pay`. The path keeps that form even when the project keeps the module's working checkout elsewhere through execute-flow section 2b's `Module checkout path:` line.
- Branch default: an entry's `branch` wins, and a blank entry `branch` takes the plan-level `branch`.
- Ship order: the `repos:` entries in list order, with each repo's modules, in `modules:` order, directly before the repo they nest under. On a note with no `repos:` list, the order is the modules in list order and then the note's `repo`. List the repos in the order they must merge, such as a back end before the app that calls it. The ship flow opens every repo's PR or MR before it merges any, then merges in this order.
- The ship flow records each repo's PR or MR in its entry's `mr` field. In a several-repos plan, each Implementation Step names the repo it changes.

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
- A vault may sync to a cloud service and the evidence note is meant for sharing, so a `[shots]` step runs against anonymised or fixture data. If the local stack holds unmasked customer data, the plan names that data under Risks as needing the user's explicit acceptance, and the user's approval of the plan with that Risk in it is the acceptance.
- An end-to-end step runs against the running local stack. No flow runs one against staging, and a staging run happens only when the user asks for it after the MR opens.
- A step that needs a fixture plan note builds it in a scratch vault: a `mktemp -d` directory, a temporary `HOME` whose `.claude/toolkit-vault.json` points `vault_path` at that directory, and an `EXIT` trap that removes it, as `scripts/tests/vault-fs/run-tests.sh` does. The remember guard and any other tool that reads plan notes read the real vault config, and they count an open plan note there as work in flight.
- A manual check that needs a live Claude Code session reads the real config, so its notes go in the real vault under `Projects/<repo>-scratch/`. A flow files its notes under the basename of the repo's main checkout, so a check that launches a flow runs it in a scratch repo whose directory is named `<repo>-scratch`. Each fixture plan note the plan writes there carries `status: completed`, which the remember guard does not count as open. The plan's last Validation Step is a manual check that removes every entry that is not a folder under `Projects/<repo>-scratch/` with `vault-fs.sh rm`, then the emptied folders with `rmdir`, and fails unless the folder is gone, as below.

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

During execution, if implementation reality diverges from the plan, Claude must update the plan note rather than deferring deviations to a separate artifact. Record changes in the "Plan Changes During Execution" section. This keeps the plan as the single source of truth for what was intended and what actually happened. An amendment that adds new scope follows the changed-plan rule in § Planning grill.

## Run options

Ten frontmatter keys record how the flows run a plan: `ceiling`, `worker_model`, `verifier_model`, `verifier_effort`, `session_model`, `session_effort`, `nits`, `tests`, `e2e`, and `tag_merge`. They are optional on every note and are not part of the Required plan frontmatter block, so a skeleton, an older note, and a note from another tool that writes plan notes still validate. A key is written only with a value, except that `worker_model`, `verifier_model` and `verifier_effort` may be written blank, meaning the models file decides. `validate-plan.py` reads a blank key as absent and checks a value only when one is present. This section is the only definition of the keys, the reading rule, and the session cache. The `testing-gate` skill owns a separate tests-only question for work with no plan note. Every other run option question lives only in this section, and a flow references this section by name and carries no copy of the question set. It also defines the ticket question, which writes the required `ticket` key and is not a run option key.

### Values

- `ceiling`: `none`, `mr`, or `merge`. The stage the ship flow stops at, and the limit on what any flow may do in git. `none` suggests git commands and runs none. `mr` commits, pushes, opens the MR or PR, watches the pipeline, and works the bot threads. `merge` adds the merge. The `## Flows` section of the git-safety doctrine (`<plugin-root>/doctrine/git-safety.md`) defines what each value permits.
- `tag_merge`: `true` or `false`. Under `ceiling: merge`, `true` tags the merge commit and pushes the tag. Under any other ceiling the key has no effect.
- `worker_model`: blank, a Claude Code alias (`sonnet`, `opus`, `fable`, `inherit`), or a full model id, with an optional `[1m]` suffix. The implementer role's model. Blank or absent means the models file decides. `inherit` clears the models file's value, so a workflow call runs on the session model and an Agent-tool spawn uses a configured default subagent model, then the session model.
- `verifier_model`: the same vocabulary as `worker_model`. The verifier role's model.
- `verifier_effort`: blank, or `low`, `medium`, `high`, `xhigh`, `max`, or `inherit`. The verifier role's effort. Blank or absent means the models file decides.
- `session_model`: `opus`, `sonnet`, `fable`, or a full model id, with an optional `[1m]` suffix, and never `inherit` or haiku. The model of every worker session the lead starts for this task, plan, execute, ship and investigate alike.
- `session_effort`: `low`, `medium`, `high`, `xhigh` or `max`. The effort of those worker sessions.
- `nits`: `fix` or `skip`. Whether the review loops fix unreproduced nits and small findings. Under `fix`, the execute runner's fix round takes the panel's unreproduced nits and runs for them when no confirmed finding starts it, except on a seat run, where they ride only a round that a confirmed finding starts. The ship runner fixes a fixable bot thread that asks only for a cosmetic change, and the `red-team` skill sends the nits to its round. Under `skip`, none of them fixes a nit, and each lists the nits for the user. A reproduced finding is fixed under either value.
- `tests`: `required` or `manual`. Whether the slice needs automated tests, or manual verification is enough.
- `e2e`: `required` or `skip`. `required` means the plan marks at least one end-to-end step, and those steps run against the running local stack before the slice ships. `skip` means the runner reports each marked step as a manual check and never runs it. The Validation Steps subsection above defines the marker.

`haiku` is not accepted on any model key.

`session_model` and `session_effort` never reach `scripts/resolve-models.sh`, and `worker_model`, `verifier_model` and `verifier_effort` keep their meaning for the agents inside a flow.

`worker_model`, `verifier_model`, and `verifier_effort` reach `scripts/resolve-models.sh` (`<plugin-root>/scripts/resolve-models.sh`). The `agent-model.sh` hook reads them from the session cache for an Agent-tool spawn. Before a flow launches a workflow, it runs the resolver with `bash` and one flag for each of these values it read or asked that is not blank, `--worker-model '<value>'`, `--verifier-model '<value>'` and `--verifier-effort '<value>'`, and with no flags when it holds none. Each value must be single-quoted, because zsh reads an unquoted `[1m]` suffix as a glob and aborts the command with `no matches found`. The flow passes the printed `agents` object as the runner's `models` arg. When `repoRoot` contains `plugins/toolkit/scripts/resolve-models.sh`, the flow runs that copy instead, so the resolver comes from the same tree as the runner it launches. If the resolver exits 0 and prints anything on stderr, the flow reports that output to the user before the launch. If the resolver is missing or exits non-zero, the flow reports its stderr and launches without `models`, so every call inherits the session model and effort.

### Reading rule

A flow reads the run options per key. The five enum keys are `ceiling`, `nits`, `tests`, `e2e`, and `tag_merge`. A bare enum key, one with no value, counts as absent. The note holds the keys when all five enum keys are present with valid values. Then the flow asks nothing and writes the session cache from the note. The ticket question follows the Ticket subsection, not this rule.

When the note lacks one or more enum keys, the flow fills each missing key from the session cache, but only when the cache's `plan:` line equals the note's `plan:` value. A cache for another plan, or one with a blank `plan:` line, is never read by a plan flow. For each key still missing, the flow asks the matching question from the question set below, so a note with some keys gets one question set that covers only the gaps. A missing or blank model or effort key never triggers a question on its own, because blank means the models file decides. The exception is `session_model` and `session_effort`: when either is missing or blank, the asker asks the worker session question, always of the user, and a lead never answers it for the user, because the worker sessions would otherwise run on whatever model the lead or the machine default names. Whenever a flow asks any run option question, it also asks the question for every model or effort key the note lacks, and a `worker_model`, `verifier_model` or `verifier_effort` key written blank counts as answered. The flow records every filled or answered key on the note at its next write of the note, and rewrites the cache for this plan.

A wayfinder child stub copies the parent's run option keys only when the parent carries values, so a child of a parent with recorded options never re-asks. The user changes an option by editing the note.

### Question set

At most two AskUserQuestion calls carry the run option questions, up to six of them, recommended answer first, per the communication doctrine. When crawl asks the ticket question, it rides in those calls, so they carry up to seven questions in all. Every other asker puts the ticket question in its own AskUserQuestion call, as the Ticket subsection says, and the create procedure asks its own questions only after a Create a ticket answer. Neither counts against the two calls. A flow asks only the questions whose keys are missing under the reading rule, and a question writes only the keys that were missing. A free-text answer that names a valid value counts as that value.

Call one carries up to four questions:

1. "Where does the ship flow stop?", asked when `ceiling` or `tag_merge` is missing, with the options "No git, suggest only (Recommended for a work repo)", which writes `ceiling: none` and `tag_merge: false`, "Commit, push and open the MR or PR", which writes `ceiling: mr` and `tag_merge: false`, "Through merge", which writes `ceiling: merge` and `tag_merge: false`, and "Through merge, then tag the merge commit", which writes `ceiling: merge` and `tag_merge: true`. When the note already holds a valid `ceiling` and lacks only `tag_merge`, the answer writes only `tag_merge`, `true` for the last option and `false` for any other, and the held `ceiling` stays as it is.
2. "What testing does this slice need?", asked when both `tests` and `e2e` are missing, with the options "Unit tests, no end-to-end (Recommended)", which writes `tests: required` and `e2e: skip`, "Unit and end-to-end tests", which writes `tests: required` and `e2e: required`, and "Manual verification", which writes `tests: manual` and `e2e: skip`. When only `tests` is missing, ask "Does this slice need unit tests?" instead, with the options "Unit tests (Recommended)", which writes `tests: required`, and "Manual verification", which writes `tests: manual`. When only `e2e` is missing, ask "Does this slice need end-to-end tests?" instead, with the options "No end-to-end (Recommended)", which writes `e2e: skip`, and "End-to-end tests", which writes `e2e: required`.
3. "Fix the nits the reviewers raise?", asked when `nits` is missing, with the options "Fix (Recommended)", which writes `nits: fix`, and "Skip", which writes `nits: skip`.
4. "Which model implements?", which joins the set when the note has no `worker_model` key, with the options "Toolkit default (Recommended)", which writes a blank `worker_model`, then "opus", "sonnet", and "fable", each of which writes that alias.

Call two carries the verifier question, then the worker session question, then the ticket question when crawl asks it. While call one carries fewer than four questions, each joins call one, the verifier question first, then the worker session question, and the asker makes one call when both fit.

1. "Which model and effort verifies?" with the options "Toolkit default (Recommended)", which writes a blank `verifier_model` and a blank `verifier_effort`, then "opus at xhigh", "opus at high", and "sonnet at high", each of which writes that alias and that effort.
2. "Which model and effort run the worker sessions?", asked when `session_model` or `session_effort` is missing, with the options "opus at high (Recommended)", "opus at xhigh", "sonnet at high" and "fable at high", each of which writes that alias as `session_model` and that effort as `session_effort`. One answer covers the plan, execute, ship and investigate workers of the task. A user who names another model or effort for one phase when the lead proposes that worker gets it for that worker only, and the note keeps its answer.
3. "Which ticket covers this work?", with the options the Ticket subsection lists for the repo's tracker. It is the same question every other asker puts in its own call.

### Ticket

The ticket question settles the ticket for work that has none, before any branch or plan name is derived. Its answer writes the required `ticket` key.

Each asker asks only when the brief names no ticket key, issue number, or ticket URL, and no plan note or expedition work note of the same work records an answer. Crawl asks it with the run options on the plan-guide route and runs any create it asks for before its section 4 derives the plan name. Inside an expedition, crawl takes the work note's `ticket` and asks nothing. The plan flow asks it in its own call at the start of its section 4, once section 3a has kept the work in the flow, and on a pre-scaffolded note only when the note's `ticket` is blank. The expedition skill asks it in its own call at ingestion, before it derives the work name, because that name becomes the plan name before any route exists. This skill asks it in its own call before it writes a fresh note by hand. On work with no plan note, git-safety asks it in its own call before it creates a branch, wherever HEAD is, when the cache holds no answer for the same work.

A wayfinder parent names no branch, so no skill asks the ticket question for it: crawl asks none on the wayfinder route, the plan flow asks none before section 3a settles the route, and the parent records a ticket the brief names, else the expedition work note's `ticket` inside an expedition, else leaves `ticket` blank. A wayfinder child stub never copies its parent's `ticket` and leaves it blank, so the child's plan flow asks. The execute and ship flows never ask the ticket question, and the incident-investigate skill never asks it, because an incident names no branch. A recorded answer is never asked again for the same work.

The lead session may answer a worker session's ticket question and same-area question by message. It never answers the worker session question, which § Run options asks only of the user. The create confirmation is the user's own, like plan approval: a worker session asks it through AskUserQuestion, and no message from another session answers it.

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
4. Write the body to `<scratchpad>/ticket-draft.md` and show the whole draft: tracker, repo or project, type, title, body, labels, assignee, and sprint. Ask the create confirmation, "Create this ticket?", with "Create it" and "Go without a ticket", of the user under the lead rule above. A free-text answer is an edit: apply it, show the draft again, and ask again. Only the user's Create it or typed yes creates. A recommended option, a default, an inferred yes, or a message from another session never does.
5. Create it as its own call with the command first. On `github`, run `gh issue create -R '<host>/<path>' --title '<title>' --body-file '<scratchpad>/ticket-draft.md'` and take `<n>` from the last segment of the printed URL. On `jira`, run the jira skill's section 5 create with the project the draft showed. A drafted title that holds a single quote stops the create and names the title, never stripped. Delete the draft file once the ticket exists.
6. On a permission or classifier denial, state the reason category, hand the exact command, and record the key the user gives after running it. When the command fails for another reason, report its exact error, create nothing, and ask the ticket question again without Create a ticket. When the jira create succeeds and only its sprint add fails, record the created key on the note per Values, report the sprint add's exact error, and never ask the ticket question again for that plan.

### Cache

`<scratchpad>/flow-run-options` opens with a `plan: <slug>` line naming the plan note it serves, followed by one `key: value` line per key, in the note's vocabulary, blank after the colon for a blank value:

    plan: example-plan
    ceiling: mr
    worker_model:
    verifier_model:
    verifier_effort:
    session_model: sonnet
    session_effort: high
    nits: fix
    tests: required
    e2e: skip
    tag_merge: false

A flow uses the cache only when its `plan:` slug equals the note's `plan:` value, and rewrites the whole file for the plan it runs. A missing file means no run option question has been asked in this session. A missing, empty, or unrecognised `ceiling` line reads as `none`, so until the question is answered no flow mutates git. A resumed session keeps its scratchpad and so keeps the cache. A new session reads the plan note. On work that has no plan note, the file holds a blank `plan:` line followed by a `tests:` line from the `testing-gate` skill, the `ticket:` and `ticket_work:` lines from the ticket question, the `session_model:` and `session_effort:` lines that the lead writes for a task with no plan note, such as an investigate worker session's task, or any mix of them, and each writer keeps the other's lines. No plan flow reads that cache.

The session-start agent model list predates a cache written later in the session. After a flow writes or rewrites the cache, it runs `bash <plugin-root>/scripts/resolve-models.sh --list --options '<scratchpad>/flow-run-options'` and passes the `model` and `effort` that list prints on each later Agent-tool spawn of a `toolkit:` agent. If that run fails, the flow passes neither field and the `agent-model.sh` hook adds them.

    plan:
    tests: required
    ticket: none
    ticket_work: example-fix

## Topic links

Related Topics sections use `[[wiki links]]` to topic notes. Every topic linked from a plan note must resolve: if the topic note does not exist anywhere in the vault, create a stub during planning. The full topic note spec (location, frontmatter, structure, content rules, freshness validation, build process) lives in the toolkit's topic command (`<plugin-root>/commands/topic.md`) — Read it before creating or updating topic notes or stubs. Prefer fewer, better topic links over many noisy ones. Do not rely on note-app plugins for basic readability.

Stubs created during planning stay vault-side; promoting a topic's canonical facts into the project repo happens only through the `topic` command's own consent gate (Repo mode), never as a side effect of planning.

Use plain strings in the plan frontmatter `related_topics`, and `[[wiki links]]` in the body Related Topics section. Linked Artifacts follows its rule under Required plan sections (existing sibling artifacts only); never link bare generic names like `[[plan]]`.

## Planning Workflow

For non-trivial tasks, follow these steps before writing the plan note:

1. Topic recall: derive candidate topics from the task, run the toolkit's `scripts/topic-recall.py` with `--repo <repo>`, `--repo-root <repo root>`, and the task words, which reads the vault topics and the repo's `docs/` together, read the top hits, and search prior plan folders. Validate topic notes before relying on them (see the toolkit's topic command, `<plugin-root>/commands/topic.md`, § Freshness and validation). Split the result into known facts and gaps. Only the gaps need exploration. The conductor does this directly. It is one script run plus the reads, not a delegated task.
2. Read relevant code, config, docs, and existing patterns (see Docs-First Discipline in the toolkit's CLAUDE.md doctrine).
3. Invoke the `/toolkit:testing-gate` skill to determine the required testing level.
4. AFTER topic recall, delegate discovery and investigation, scoped to the gaps from step 1. Discovery and investigation (repo/doc scan, mapping how existing code works, answering factual questions from the codebase) goes to the `explorer` agent. Skip it when recall and your step-2 reads closed every gap, and say so. Escalate the explorer's model per invocation for genuinely hard tracing (orchestration model policy); evidence that needs commands run (a failing test, a repro) goes to the `verifier` agent instead, since explorer is read-only.
5. Run the planning grill on the evidence from steps 1 to 4, per § Planning grill below.
6. Drafting the reviewable plan itself (proposed steps, risks, verification approach) goes to the `planner` agent, fed with the recall facts, the explorer findings and the grill block so it does not re-derive them, except when the main challenge is choosing architecture, which the conductor keeps per orchestration doctrine. Skip delegation in steps 4 and 6 only when the task is obviously too small, and say why.
7. Write the plan note (`plan - <plan-name>.md`) to the vault plan directory. Create the plan directory per the canonical layout, or fill in a pre-scaffolded note where one exists. Create stubs for Related Topics links that do not resolve.
8. Include a suggested branch name.
9. Note project-specific high-risk areas from the project's `01-project-core.md`.
10. No implementation code changes in this mode.
11. Stop and wait for explicit user approval before execution.

On non-trivial plans, after drafting the plan note and before stopping for approval, run the `plan-critic` subagent to adversarially red-team the draft. Plan-critic applies the inversion pre-mortem structure and returns tripwires and walk-away checks. Fold its material objections into the plan's Risks / Assumptions / Open Questions. Copy its Tripwires block into Validation Steps, one line per failure mode, and its Walk-away checks block into Risks, one line per check, so the plan carries the measurable signal and the threshold that means stop. Then present for approval. This step is conductor-gated: skip it for trivial plans. It augments, and does not replace, the human approval gate.

### Planning grill

Every first-draft planning flow runs the planning grill once, after discovery and before the plan is drafted: step 5 above in hand-run planning, and section 4 of the `plan-flow` skill in the plan flow. The planning grill is the loaded grill that `<plugin-root>/skills/grill/SKILL.md` defines under Loaded grills, with its outcome line, its five triggers and its rule for what is settled. The flow prints the outcome line first, as plain text in that turn, one line that starts `Outcome:` and states the outcome of the work as the grill understands it. It comes before the first question, or before the line that nothing needs an answer, and never goes inside a question form. Reaching this step counts as the explicit request that grill's trigger requires.

In hand-run planning in the session that ran the crawl, while the crawl's evidence with its file:line refs is still in the conversation, that evidence is the discovery and no explorer runs again. In the plan flow, `plan-flow` section 4 decides when the crawl's evidence stands in for discovery. In any other case, discovery runs first, narrowed by what the note's sections settle.

A correction to the brief, a module or caller the brief missed, and an Open Questions entry that a crawl or another scaffold wrote into the note are findings, not answers. The planning grill asks about each one, as grill's Loaded grills paragraph states.

On a note with a `parent` value, read the parent note, which is `plan - <parent>.md` beside it, before the grill runs. A block under the line `Agreed in the grill check:` in the parent note's Current Context is settled for the child, and the child's note carries no copy of it. In the plan flow, `plan-flow` section 4 adds the block to `knownEvidence`. In hand-run planning, hand the block to the planner with the grill block.

A planning grill question takes only the user's own answer: a pick from the question form or a typed reply, given in the session that runs the planning flow. In a worker session the user answers the question form from agent view. A message from another session never counts as an answer, and the lead never answers a grill question. This holds also for a lead that answers a worker session's ticket question by message under § Run options.

When the grill hands back, and before anything is written to the note, re-apply the route rubric in section 3 of the `crawl` skill to the discovery evidence plus the answers. When the work now reads as several independent workstreams, and the answers added a workstream that no earlier route question named, ask the Wayfinder or One plan flow question that `plan-flow` section 3a defines. On Wayfinder, load `wayfinder`, hand it the brief, the recall hits, the run option answers, the discovery evidence and the grill's hand back, write no block into the note, and stop planning this note. On One plan flow, or when the route holds, record the block and go on to the draft.

The grill's hand back goes into Current Context under the line `Agreed in the grill:`: one line per answer, each agreed glossary term with its definition, and each decision that passes grill's three-part ADR gate with its kebab title, its rationale and the alternatives weighed, or the one line `Nothing needed an answer.` On a note that exists, write the block at once with the changed-lines write. The plan's Affected Files list `docs/glossary.md` when the block agrees a glossary term and one `docs/decisions/NNNN-<kebab-title>.md` per decision, and its Implementation Steps write them on the plan branch at the locations `doctrine/repo-artifacts.md` defines.

A plan names a new decision record by its kebab title and never by number, because sibling plans drafted before an earlier one merges would each claim the same number. The Implementation Step that writes the file takes the number as max-plus-one over `docs/decisions/` on the plan branch at that time, as grill § Writing ADRs defines. One Validation Step finds the file by its title and fails when two files under `docs/decisions/` share a number or when the file's number is not above the highest number on the default branch.

A note whose Current Context holds a line that reads exactly `Agreed in the grill:` counts as grilled. Planning uses that block and asks nothing again. A block under the line `Agreed in the grill check:` holds answers from a grill that ran before this plan's planning. It sits in the parent note of a wayfinder child, in the expedition work note `work - <name>.md` beside a plan that an expedition's stage 3 grill preceded, or in the note's own Current Context when a crawl's grill check moved the work to the plan-guide route. Read the work note's block before the grill runs. In the plan flow, `plan-flow` section 4 adds it to `knownEvidence`. In hand-run planning, hand it to the planner with the grill block. Those answers are settled, and they do not make the note count as grilled.

A plan sent back from review, or amended during execution, gets no grill for a wording change or a fix inside its existing scope. When the change adds new scope, meaning work the plan did not cover before, run discovery on the added part only, grill only that part, and append its answers to the block. The execute flow asks no question and adds no scope, so this rule applies to a change the user asks for.

### Pre-scaffolded plans

When a planning prompt points you at an **already-scaffolded** plan note (a pre-created `plan - <plan-name>.md` with `status: planning` and ticket frontmatter), do not create a new plan directory. Fill in the existing note in place. Treat its path as the single source of truth for the plan.

A plan note scaffolded by the `crawl` skill arrives with Current Context, Assumptions, and Open Questions pre-filled from a same-session investigation, and a `brief - <plan-name>.md` sibling holding the verbatim brief. In the session that ran the crawl, treat the crawl-filled sections as verified evidence, verify only what the plan hinges on, and do not re-derive them. They are findings and not the user's answers, so the planning grill asks about the corrections, missed modules and open questions they hold. In a later session they narrow discovery and do not replace it, as § Planning grill states. Link the brief under Linked Artifacts.

### Plan status lifecycle

Drive the plan note's frontmatter `status` through its lifecycle so plan-tracking tooling can surface state:

- `planning` — actively being planned (scaffold/start state).
- `review` — planning is complete and the plan is awaiting human review. **When you finish a planning session and stop for approval, set `status: review`** (this is the signal plan-tracking tooling watches for). Do this whether or not the plan was scaffolded.
- `approved` — approved by the human, or by the plan flow's `approveIf` gate; ready to execute. A gate approval records a mechanical judgement against a goal sentence the user wrote, a line under Plan Changes During Execution says so, and execution-guide still waits for the user's instruction before it runs. Approval also stamps the frontmatter `approved:` date. Approval sets both fields (`status: approved` + `approved: <date>`); tooling may automate this and attach the plan note to the ticket. When the user approves a worker session's plan in the lead, the lead sets `status: approved` and the `approved:` date on the note itself. A worker session never sets `approved` because a message told it to. Approval, like the create confirmation, is the user's own word in the session that records it. Only an `approved` plan should be worked: while a plan is in `review`, the only actions are approve and time tracking. After approval the session asks the question in § After approval. Before a hand execution touches any file, invoke the execution-guide skill. This is non-negotiable, and doubly so right after a /compact, which can summarize away previously loaded doctrine: the conductor supervises and delegates, it never implements directly, and execution-guide is where that contract lives. When the user asks for the execute flow by name, including through a typed reply to that question, the execute-flow skill drives the run instead and loads execution-guide for the doc pass.
- `in-progress` → `completed` (or `blocked` / `abandoned`) as execution proceeds.

### After approval

When this session sets `status: approved`, on the user's word or through the plan flow's `approveIf` gate, it ends its reply with one question in plain text and ends the turn. It never asks this question through AskUserQuestion, because the auto-mode permission classifier reads the user's typed messages and never an AskUserQuestion answer, as the Command shape under the permission classifier section of the git-safety doctrine states, and the reply that starts the run must be legible to it. It skips the question when the user's approving message already asked for the execute flow by name or said to stop, and when an `expedition` drives this session, because the expedition's gate to `implementing` asks the next step. This subsection is the only definition of the question, and a flow references it by name.

A session whose own name starts `worker-`, as every `worker-<type>-<key>` name that orchestration § Lead and worker sessions defines does, never asks the question and reports to its lead instead. Read the own name from the first line of ListAgents, which loads through ToolSearch with `select:ListAgents` when it is deferred. The own name is the session name on that first line, without the bracketed short id after it.

The question takes one of two forms, verbatim. It takes the worker form when the read prints an own-name line. It takes the run-here form when ListAgents is absent or prints no own-name line, because a worker session could not report to this session, and the reply says in one line before the question that this session cannot read its own name. In each form `yes` sits on the line marked (recommended), so a bare `yes` takes the recommendation.

The worker form:

    The plan is approved. Start worker-execute-<key> to build it?
    - `start the worker` or `yes`: starts worker-execute-<key> in the background, in its own worktree, to run the execute flow, and then the ship flow up to the note's ceiling `<ceiling>` when I tell it to continue (recommended). The ceiling you picked is your permission, so it does not ask you again. I tell you here when it needs you, finishes, or stops.
    - `run the execute flow here`: builds the plan in this session now. The build runs in its own worktree when another session is using the main checkout, when the main checkout holds changes, or when it sits on its default branch.
    - `stop` or `no`: nothing runs. Ask for a worker or for the execute flow by name when you are ready.

The run-here form:

    The plan is approved. Run the execute flow here now?
    - `run the execute flow here` or `yes`: builds the plan in this session now (recommended). The build runs in its own worktree when another session is using the main checkout, when the main checkout holds changes, or when it sits on its default branch.
    - `stop` or `no`: nothing runs. Ask for the execute flow by name when you are ready.

`<key>` is the note's `ticket` in lowercase when it holds a tracker key or `issue-<n>`, else the plan name, and on a note with a `parent` value whose plan name holds a `-t<n>-` segment a ticket key gets `-t<n>` appended. `<ceiling>` is the note's `ceiling`.

The user's next typed message answers the question:

- `start the worker`, or a bare `yes` in the worker form, starts the worker session as Starting the worker below defines.
- `run the execute flow here`, or a bare `yes` in the run-here form, is the user asking for the execute flow by name. After a gate approval it is also the user's instruction that the human approval rule requires. Load the `execute-flow` skill (`<plugin-root>/skills/execute-flow/SKILL.md`) and follow it from its section 1 on this plan note.
- `stop` or `no` ends the turn. The next step waits on the user.
- Any other reply starts nothing. The session handles it as an ordinary message and starts no flow.

A later ask for a worker session on an approved note gets the same proposal and needs its own yes.

Starting the worker. When the note or the cache for this plan lacks `session_model` or `session_effort`, ask the worker session question of § Run options first. Write the one-line task `Build the approved plan in the plan note.` to `<scratchpad>/worker-task.md` with the Write tool, then run, as its own call with the command first:

    bash <plugin-root>/scripts/worker-spawn.sh --scratchpad '<scratchpad>' --type execute --key '<key>' --plan '<planName>' --note '<plan note path>' --lead-name '<own name>' --model '<session_model>' --effort '<session_effort>' --cwd '<main>' --worktree '<planName>' --task-file '<scratchpad>/worker-task.md'

`<main>` is the main checkout of the repo that the note's `repo` names. On a several-repos note (§ Repos and modules), pass `--cwd '<projects root>'`, the directory that holds this session's main checkout, and no `--worktree`. When `<main>/.claude/worktrees/<planName>` already exists, as on a rerun after a stopped worker session, Claude Code opens it for `-w <planName>`, and execute-flow section 1 re-enters it when the note records it, or adopts it by the unrecorded worktree rule. `<session_model>` and `<session_effort>` are the recorded answer, or the model and effort the user named for this worker session. They are never this session's own model or effort. When `<main>`, the scratchpad path, the plan note path or the own name holds a single quote, start no worker session and give the run-here form. On `STARTED`, say in one line which worker session started and that this session will tell the user when it needs them, then start the watch per orchestration § Lead and worker sessions. On `NOBG`, `NOMODE`, or exit 2 or 3, say why in one line, quoting the `error:` line on exit 2 or 3, and offer `run the execute flow here`. On `UNRECORDED <name>`, handle it as orchestration § Lead and worker sessions defines, and offer no run here, because that worker session runs the execute flow. On a classifier denial of the spawn, state the reason category per git-safety and end with the line: Type `start the worker` to ask again.

The seat while an execute worker session runs:

- When this session runs in the main checkout, it holds the seat, so the worker session's execute flow adopts the plan's worktree with no question. This session has no queue entry, so a worker session's seat run that finds it in the main checkout starts no watcher and stops at once with `LEAD`, because a wait on this session would last until its user ends it. The worker session knows this session by the session id its first prompt carries, never by name, and waits for it as for any other holder, up to the seat queue's wait bound, only when that id is missing or not valid. This session then runs the seat run itself once the worker session is stopped with `claude stop`, as the report names, or moves into a linked worktree and dispatches the seat run to the worker session again.
- When this session runs in a linked worktree, it does not hold the seat, so the worker session's execute flow decides by its section 2a table from the worktree it starts in. Git checks a branch out in one worktree only, so this session's own worktree must not sit on the plan's branch, or the worker session's run stops.
- This session runs no flow on the plan while the worker session runs it, and edits nothing in a checkout the worker session is writing.
- A worker session stays in its worktree after a report and waits for this session's message, because the ship flow and a rerun of the execute flow both run from the recorded worktree. This session's seat run waits in the seat queue until the worker session is stopped.
- The seat run also needs the main checkout to itself. It waits in the seat queue while any other live session sits in `<main>`, a coordinating session above this one and a worker session that is still planning included. Such a session has no queue entry, so the wait ends only when it ends or moves into a linked worktree, or stops when the watcher's bound runs out, and the wait start names each such session.

Reports. When a report's `Next:` line is `send <own name> the message "<planName>: run the ship flow"` and the report holds no blocked reason, the lead sends that message with `notify_when_idle: true`, starts the watch with `--hold <id>` unless a watcher runs, lists the continue in its decisions-made list, and tells the user in one line. When a ship report's `MR:` line holds a URL or its `Merged:` line holds a sha and the report holds no blocked reason, the lead runs `claude stop <id>` with the id from `<scratchpad>/workers`, lists the stop in its decisions-made list, and names it in the same line as the report. When a ship report's blocked reason is an auto mode refusal of a step the ceiling allows, or the continue message cannot be sent, the lead runs the ship flow itself on that plan note up to the recorded ceiling, per the Grant rule of orchestration § Lead and worker sessions, and names the refusal as a template defect in its final summary. After any other report the lead leaves the worker session idle and asks nothing about stopping it.

### Record the session on the plan

Record the session id UP FRONT, not at the end. Your session id is the UUID directory segment of this session's scratchpad path (shown in your system prompt) — derive it from there; do not wait to be told it. The list holds at most one entry per session id: create your entry once at session start, then only ever update that same entry — never add a second entry for the same session.

At session start:
- If your current session id is already on the list (a resumed conversation that kept its id), update that entry — do not append.
- Otherwise append one new entry (date, a short "in progress" summary, your session id, and `name` per the Session name paragraph below). If the plan note does not exist yet (no scaffold), derive the plan name and create the note skeleton (the full 18-key frontmatter, blank values except `type: plan` and `status: planning`, which the validator requires non-blank, carrying that `sessions:` entry, and all 13 required `##` headings present but empty, so it passes the validation gate) as one of the FIRST actions of the session, before deep exploration, then fill the body in as planning proceeds.
- If resumption minted a genuinely new session id (a new transcript), that is a new session: append a new entry for it.
- Every live session has an id — the scratchpad path is always in your context, so derivation always succeeds. Never leave `id:` blank on an entry you create, and never invent a placeholder value: if you truly cannot locate the scratchpad path, that is an error to surface to the human, not a reason to skip the id. A blank id only ever appears on a manually pre-scaffolded entry.

Session name: each time this session creates, claims, or updates its entry, read its own name from the first line of ListAgents, which loads through ToolSearch with `select:ListAgents` when it is deferred, and write it as the entry's `name` when it differs. The own name is the session name on that line, without the bracketed short id after it. Always write the value as a double-quoted YAML scalar, such as `name: "PROJ-12 Fix checkout: totals"`, because a session name can hold spaces and a colon, and a plain scalar such as `123` or `true` reads as a number or a boolean. Plan-tracking tooling reads it: a name that starts `worker-` marks a worker session, and any other name marks a lead, including the optional `lead-<name>` that crawl suggests. An older `parent-` name reads as a lead and an older `child-` name as a worker session. When ListAgents is absent, prints no own-name line, or prints a name that holds a double quote, a backslash, or a control character such as a tab or a newline, write no new `name` and leave the entry's existing `name` as it is. Never escape a character inside the quotes, and never write a blank or guessed name.

During the session and before stopping, update that same entry's summary to the real one-line outcome. If the note carries a pre-scaffolded blank-id entry that is clearly this session's work, claim it: fill in your id and `name` rather than appending a duplicate; if ownership is ambiguous (say, two blank-id entries on the same date), stop and report the ambiguity rather than guessing. Record the id yourself. Do not rely on tooling to backfill it.

## Session Closure

The record of the work is the plan note (kept current during execution), git (the branch diff, and the squashed commit after merge), and the session ids on the plan.

### What Claude must do as a session ends

1. Make sure the plan note is current: decisions, gaps, and deviations recorded in "Plan Changes During Execution"; Validation, Risks, and Open Questions up to date.
2. If Plan Changes During Execution holds no `Remember:` line for this slice, the remember pass has not run. Run it now (topic command, § Remember pass) and record its `Remember:` line there. Capture the slice diff for its brief as red-team step 2 does: `git diff HEAD` plus each untracked file. A `Remember pass owed: <path>` line with no `Remember:` line after it means the execute flow left the pass owed, whatever earlier `Remember:` line the section holds. The session that recorded that line does not run this step for the slice, because its own pass already tried once. A later session runs the owed pass the standard way (topic command, § Remember pass), with the lines of the file that line names, the `remember-material - <planName>.md` copy beside the plan note, as the brief's Topic note material returns. `git diff HEAD` is empty once the slice is committed, so capture the diff of an owed pass by the state the note records. With no commit sha recorded, capture `git diff HEAD` plus each untracked file, and when that capture is empty because the user committed the slice from a suggested commit, capture `bash <plugin-root>/scripts/git-ro.sh <repo> diff <default>...<branch>`. With a commit sha and no merge sha recorded, capture `bash <plugin-root>/scripts/git-ro.sh <repo> diff <default>...<branch>`. With a merge sha that equals the recorded commit sha or a recorded fix sha, which a fast-forward merge records, capture `bash <plugin-root>/scripts/git-ro.sh <repo> diff <commit sha>^1 <merge sha>`, because a fast-forward may carry several commits. With any other merge sha, capture `bash <plugin-root>/scripts/git-ro.sh <repo> diff <merge sha>^1 <merge sha>`, because `git show` prints no diff for a merge commit. Record the `Remember:` line after the owed line, which stays as history.
3. Update this session's `sessions:` entry with the real one-line outcome (append one only if it is somehow missing — never a second entry for the same session id).
4. Report that execution is complete.

### Finalize

Mark a plan done once the MRs are merged: post a comment to the ticket, transition the ticket status, and set the plan frontmatter to `completed`. Tooling may automate these steps. validate-plan.py rejects a completed plan whose Plan Changes During Execution has no Remember: line, or holds a Remember pass owed: line with no Remember: line after it, so run the remember pass first. Plans created before 2026-10-18 are exempt. Before the final MR merges, promote what outlives the plan as the handoff skill's "Promote what outlives the plan" item describes, so Linked Artifacts names each promoted path, or reads "Nothing to promote", before the plan is set to `completed`.

### Do not mark a plan complete if

- There is no plan for this session, or the plan is ambiguous.
- The vault config or vault is missing.
- The MRs are not actually merged.
- Plan Changes During Execution has no Remember: line, or holds a Remember pass owed: line with no Remember: line after it, for a plan created on or after 2026-10-18.

If completion is skipped, state exactly why.

### Guardrails

- The plan note in the vault is the source of truth for the work.
- Do not invent a plan name. If the active plan is ambiguous, ask before writing.
- Keep this discipline only for real planned work, not trivial Q&A or explanation-only sessions.
