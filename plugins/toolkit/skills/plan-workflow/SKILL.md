---
name: plan-workflow
description: >-
  MANDATORY companion for plan work. Invoke BEFORE creating, filling in, updating, or
  closing out any plan note (plan - <name>.md) in the Obsidian vault — including
  pre-scaffolded plan notes — and at the start and end of any planning or
  execution session tied to a plan. Contains the canonical artifact locations, naming
  rules, plan frontmatter and sections, planning steps, status lifecycle, session
  recording, and session closure rules. Do not write or edit
  a plan note without this loaded.
---

# Plan Workflow

This skill is the single source of truth for the plan-first workflow: where artifacts
live, how they are named, what a plan note contains, the planning steps, the status
lifecycle, and session closure. The always-loaded invariants (plan-first, approval
gate, orchestration rules, git safety) live in the toolkit's CLAUDE.md
doctrine and your global config; this file holds the mechanics.

## Workflow: Plan → Execute → Session

For non-trivial development tasks, use a plan-first workflow.

Do not begin implementation until the plan has been written and explicitly approved by the user.

### Canonical artifact location

Workflow artifacts are written directly into the Obsidian vault, at the location the
user's `~/.claude/obsidian-sync.json` defines (`vault_path` + `plan_folder_template`):

    <vault_path>/<plan_folder_template>
    e.g. with the default template: <vault_path>/AI/Claude-Code/Projects/{repo_name}/{date}-{plan_name}/

The plan name must be short, lowercase, kebab-case, and derived from the task purpose.
The date is the local date (YYYY-MM-DD) when the plan is created.
The plan name must match: `^[a-z0-9][a-z0-9-]*$`

### Artifact naming

Every artifact filename embeds the plan name so Obsidian graph nodes are unique
and wiki links resolve unambiguously:

    {artifact} - {plan_name}.{ext}

Canonical artifact:

- `plan - <plan-name>.md`

Optional sibling artifacts created by other skills (e.g. `handoff - <plan-name>.md`
from the handoff skill) and supporting notes created inside a plan directory follow
the same pattern: `{artifact} - <plan-name>.md` (e.g. `security-review - example-sso-login.md`,
`flow-diagrams - abc-123-example-feature.md`). The artifact part is
short kebab-case.

Never create generically named artifacts (`plan.md`, `handoff.md`,
`security-review.md`) in the vault. Generic names collapse into
indistinguishable graph nodes and make wiki links ambiguous across plans.

Because filenames derive from the plan name, plan names must be unique across
the entire vault, not just within one repo. Check for collisions before creating a plan
directory; if a plan name is taken, derive a more specific one.

### Child plans (parent/child directories)

A plan directory MAY contain child plans alongside the parent note — the shape for
umbrella work like an incident investigation that spawns many remediation tasks:

- The parent is `plan - <plan-name>.md` where `<plan-name>` matches the directory
  suffix. Children are additional `plan - <child-slug>.md` notes in the same
  directory, each with FULL plan frontmatter (own `plan:`, `status`, `branch`,
  `modules:`, `sessions:`).
- Child slugs follow the same rules as plan names (kebab-case, vault-unique).
- Children carry `parent: <plan-name>` in frontmatter.
- Children never inherit the parent's ticket. Each child links its own ticket or has
  none.
- Children are full plans in their own right (own approval, stage, branch/MR
  tracking, reviews, worklogs). Tooling that visualizes plans should group them
  under their parent.

### Plan name derivation

If the user provides an issue, ticket, Jira key, GitHub issue number, or task ID,
include it at the start of the derived plan name.

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

If no ticket or issue is provided, derive the name from the task only.
If the ticket format is ambiguous, ask before writing.

Example (with the default template):

    <root_folder>/Projects/my-repo/2026-05-19-cr-123-runtime-error-handling/

Resolve the vault path and folder template from `~/.claude/obsidian-sync.json`.

### Repo-local plans directory

Do not write workflow artifacts to repo-local `.claude/plans/`. The Obsidian vault
is the only artifact location.

### Built-in plan directory

`~/.claude/plans/` is Claude Code's built-in plan mode directory. It is not part
of this workflow.

## Required Artifacts

The one required artifact, written to the Obsidian plan directory:

- `plan - <plan-name>.md` — the single source of truth. A living document: kept current
  during execution (decisions, gaps, deviations) so it records both what was intended
  and what actually happened. Carries its own session history and worklogs in frontmatter.

Other skills may create optional sibling artifacts in the same directory (e.g.
`handoff - <plan-name>.md`); each is linked from the plan's Linked Artifacts section
when — and only when — it is actually created.

The plan note plus git (the branch diff and, after
a squash-merge, the squashed commit) plus the session ids recorded on the plan are the
complete record of what was done. Execution details belong in the plan note under
"Plan Changes During Execution". Topic notes (the cross-plan knowledge layer) are
maintained during planning and execution, not written at finalization.

Use atomic writes (write to temp file, then the toolkit's scripts/vault-fs.sh mv) for all files written into
the Obsidian vault. The vault path contains spaces and is inside iCloud Drive.

## Plan Sync

After creating or refining the plan note, it is written directly to the Obsidian
plan directory. There is no separate sync step for new plans.

If the plan note cannot be written to Obsidian (vault missing, path error, iCloud
issue), stop and report the failure. Do not write repo-local workflow artifacts.

### Do not write if

- The active plan directory is ambiguous.
- The plan note does not exist or has not been created yet.
- The Obsidian config is missing.
- Sensitive data may be present in the artifacts.
- The user explicitly says not to write.

If writing is skipped, state exactly why.

## Plan note (`plan - <plan-name>.md`)

The plan must be written before implementation begins.

Writing style for the plan note follows the vault rules (same as topic notes): plain
sentences. Never use em dashes or semicolons to split text. Use separate sentences,
commas, or parentheses instead.

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

### Required plan sections

- Objective
- Current Context
- Assumptions
- Affected Files
- Implementation Steps
- Validation Steps
- Risks
- Rollback Notes
- Open Questions
- Plan Changes During Execution — initially empty; updated during execution if reality diverges from the plan (changed assumptions, changed affected files, deviations, validation changes)
- Related Topics — use `[[wiki links]]` here
- Linked Artifacts — the heading is present from creation but starts with no links.
  It lists the sibling artifacts actually created for this plan (e.g.
  `[[handoff - <plan-name>]]` when the handoff skill writes one). Link an artifact
  only once it exists — never speculatively.

### Implementation Steps must show the code, not just describe it

A plan a reader cannot see the code off is not finished. In Implementation Steps, include
the concrete artifacts that make the change buildable and reviewable:

- Representative code snippets for the load-bearing or novel changes — the key function,
  the signature, the tricky bit — not whole files.
- A directory-tree layout for any new files, modules, or moved structure.
- Signatures, schemas, or an example input to output for new contracts and APIs.
- The exact commands, config keys, migrations, or env vars the change adds or changes.

Show enough that plan-critic and the human can judge the approach from the plan, and the
implementer builds from it without re-deriving the design. Prose alone is not enough for
non-trivial work.

### Reuse check (minimalism)

Before the plan proposes new code, apply the reuse ladder from the toolkit's minimalism
doctrine (`../../doctrine/minimalism.md` from this skill's base directory): does it need
to exist, does the codebase or the standard library or an already-installed dependency
already do it. Record the result in a line or two (in Current Context or Implementation
Steps) so a reviewer can see why each new file, abstraction, or dependency earns its
place. Reach for the shortest change that satisfies the objective, not the most elaborate.

Stop after writing the plan and wait for explicit approval before changing implementation files.

### The plan note as a living document

During execution, if implementation reality diverges from the plan, Claude must
update the plan note rather than deferring deviations to a separate artifact. Record
changes in the "Plan Changes During Execution" section. This keeps the plan as
the single source of truth for what was intended and what actually happened.

## Topic links

Related Topics sections use `[[wiki links]]` to topic notes. Every topic linked
from a plan note must resolve: if the topic note does not exist anywhere in the
vault, create a stub during planning. The full topic note spec (location, frontmatter,
structure, content rules, freshness validation, build process) lives in
the toolkit's obsidian-topic command (`../../commands/obsidian-topic.md` from this
skill's base directory) — Read it before creating or updating topic notes or stubs. Prefer fewer, better topic links over many noisy ones. Do not rely on
Obsidian-only plugins for basic readability.

Use plain strings in the plan frontmatter `related_topics`, and Obsidian `[[wiki links]]`
in the body Related Topics section. In the plan's Linked Artifacts section, link only
sibling artifacts that actually exist. Never link bare generic names like `[[plan]]`.

## Planning Workflow

For non-trivial tasks, follow these steps before writing the plan note:

1. Topic recall: derive candidate topics from the task, search the vault for
   matching topic notes and prior plan folders, and read the hits. Validate
   topic notes before relying on them (see the toolkit's obsidian-topic command,
   `../../commands/obsidian-topic.md` from this skill's base directory, § Freshness and validation). Split the result into known facts vs gaps — only
   the gaps need exploration. The conductor does this directly; it is a few
   searches, not a delegated task.
2. Read relevant code, config, docs, and existing patterns (see Docs-First Discipline
   in the toolkit's CLAUDE.md doctrine).
3. Invoke the `/testing-gate` skill to determine the required testing level.
4. AFTER topic recall, use the planner agent (the toolkit's `planner`, not
   `explorer`) for repo/doc scan or evidence gathering, scoped to the gaps from
   step 1 so it does not re-derive what recall already found. Skip only when the
   task is obviously too small for delegation, and say why.
5. Write the plan note (`plan - <plan-name>.md`) to the Obsidian plan directory.
   Create the plan directory per the canonical layout, or fill in a pre-scaffolded
   note where one exists.
   Create stubs for Related Topics links that do not resolve.
6. Include a suggested branch name.
7. Note project-specific high-risk areas from the project's `01-project-core.md`.
8. No implementation code changes in this mode.
9. Stop and wait for explicit user approval before execution.

On non-trivial plans, after drafting the plan note and before stopping for approval, run the `plan-critic` subagent (model: opus) to adversarially red-team the draft. Fold its material objections into the plan's Risks / Assumptions / Open Questions, then present for approval. This step is conductor-gated: skip it for trivial plans. It augments, and does not replace, the human approval gate or the ad-hoc `advisor` tool.

### Pre-scaffolded plans

When a planning prompt points you at an **already-scaffolded** plan note (a pre-created
`plan - <plan-name>.md` with `status: planning` and ticket frontmatter), do not create
a new plan directory. Fill in the
existing note in place. Treat its path as the single source of truth for the plan.

### Plan status lifecycle

Drive the plan note's frontmatter `status` through its lifecycle so plan-tracking
tooling can surface state:

- `planning` — actively being planned (scaffold/start state).
- `review` — planning is complete and the plan is awaiting human review. **When you
  finish a planning session and stop for approval, set `status: review`** (this is
  the signal plan-tracking tooling watches for). Do this whether or not the plan was
  scaffolded.
- `approved` — the human approved the plan; ready to execute. Approval also stamps
  the frontmatter `approved:` date. Approval sets both fields (`status: approved` +
  `approved: <date>`); tooling may automate this and attach the plan note to the ticket. Only an `approved` plan should be
  worked: while a plan is in `review`, the only actions are approve and time tracking.
- `in-progress` → `completed` (or `blocked` / `abandoned`) as execution proceeds.

### Record the session on the plan

Record the session id UP FRONT, not at the end. The list holds at most one entry per
session id: create your entry once at session start, then only ever update that same
entry — never add a second entry for the same session.

At session start:
- If your current session id is already on the list (a resumed conversation that kept
  its id), update that entry — do not append.
- Otherwise append one new entry (date, a short "in progress" summary, your session
  id). If the plan note does not exist yet (no scaffold), derive the plan name and
  create the note skeleton (frontmatter with that `sessions:` entry, empty sections)
  as one of the FIRST actions of the session, before deep exploration, then fill the
  body in as planning proceeds.
- If resumption minted a genuinely new session id (a new transcript), that is a new
  session: append a new entry for it.
- If no session id is available, leave `id:` blank — never invent a placeholder value.

During the session and before stopping, update that same entry's summary to the real
one-line outcome. For a blank-id entry, update the entry you created this session; if
it cannot be identified unambiguously (say, two blank-id entries on the same date),
stop and report the ambiguity rather than guessing or adding a probable duplicate.
Record the id yourself — do not rely on tooling to backfill it.

## Session Closure

The record of the work is the plan note (kept current during execution), git (the
branch diff, and the squashed commit after merge), and the session ids on the plan.

### What Claude must do as a session ends

1. Make sure the plan note is current: decisions, gaps, and deviations recorded in
   "Plan Changes During Execution"; Validation, Risks, and Open Questions up to date.
2. Make sure touched topic notes reflect any durable facts surfaced (see the toolkit's
   obsidian-topic command).
3. Update this session's `sessions:` entry with the real one-line outcome (append one
   only if it is somehow missing — never a second entry for the same session id).
4. Report that execution is complete.

### Finalize

Mark a plan done once the MRs are merged: post a comment to the ticket, transition
the ticket status, and set the plan frontmatter to `completed`. Tooling may automate
these steps.

### Do not mark a plan complete if

- There is no plan for this session, or the plan is ambiguous.
- The Obsidian config or vault is missing.
- The MRs are not actually merged.

If completion is skipped, state exactly why.

### Guardrails

- The Obsidian plan note is the source of truth for the work.
- Do not invent a plan name. If the active plan is ambiguous, ask before writing.
- Keep this discipline only for real planned work, not trivial Q&A or
  explanation-only sessions.
