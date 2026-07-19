# Obsidian Topic

Create or update a single topic note in the Obsidian vault. This file is the single
source of truth for topic notes (location, frontmatter, structure, content rules,
freshness, and the build/update process) — the plan-workflow skill and CLAUDE.md
point here.

## Usage

$ARGUMENTS

Arguments are the topic name, optionally followed by a repo hint.

Examples:

- `/obsidian-topic Stripe Payments`
- `/obsidian-topic 3D Secure my-shop-repo`
- `/obsidian-topic Mobile Safari Tab Suspension`

If no topic name is provided, stop and report:

    error: topic name is required.
    usage: /obsidian-topic <Topic Name> [repo]

## What topic notes are

Topic notes are the vault's distilled knowledge layer: stable concepts (a payment
provider, a subsystem, a recurring pattern) that multiple plans can reference.
They are what makes pre-planning recall cheaper than re-exploration.

## Location and naming

Resolve `vault_path` and `root_folder` from `~/.claude/obsidian-sync.json`. Every
vault path below is relative to `<root_folder>` unless stated otherwise.

- Human-readable Title Case basenames (e.g. `Stripe Payments.md`). No plan-name
  suffix — topics are shared across plans by design.
- Claude creates new topic notes in the current project directory:
  `Projects/{repo_name}/<Topic>.md`.
- Cross-project topics live in `<root_folder>/Docs/`. When a second project
  starts linking a project-local topic, promote it: move the note to `Docs/`
  with the toolkit's scripts/vault-fs.sh mv — wiki links resolve by basename, so moves are safe.
- Topic-like notes may also exist in `General/` at the vault root (user-curated).
  Link to them freely, but Claude does not write outside `<root_folder>/`.
- Basenames must be unique across the vault. Search before creating.

## Required topic frontmatter

```yaml
---
type: topic
created:
updated:
repos:
source_refs:
tags:
---
```

- `repos`: the repos this topic applies to.
- `source_refs`: repo-relative module/system roots (e.g.
  `vendor/acme/module-payments/`) or doc URLs the facts were derived
  from. No repo prefix — the same module is installed in multiple repos, and the
  relative path locates it inside whichever project a task is scoped to. These
  are the freshness anchors — required, not optional. File-level paths belong in
  plan notes and Tasks entries, not here.

## Structure

Topic notes are written for humans as well as Claude — a teammate reading one
should understand what the thing is, where it lives, how it behaves, what has
been done to it, and how to test it. For module/system topics use these
sections (omit any that do not apply):

- Overview — what it is and what features it offers (one short paragraph)
- Where it lives — composer package / git repo or registry, the repos it is
  installed in, module root path, key classes or entry points. No versions:
  package manifests and repo configuration are the authority for version pins.
- Depends on / associates with — related modules and why they are coupled
- Flows — how the important paths actually behave
- Tasks — historical work context only: task (wiki-link the plan note), repo,
  what changed or is planned, and the flow impact or durable outcome. No status
  column. Plan frontmatter is authoritative for workflow status and the ticket
  for external state, so the linked plan note is where status lives.
- Gotchas — known issues, surprises, and hard-won lessons
- Testing — test mode config, test cards/accounts, how to exercise the flows
- Related Topics — `[[wiki links]]` to related topic notes

For narrower concept topics (a browser quirk, a recurring pattern), a short
fact list is enough — do not pad to fill the structure.

## Content rules

- Writing style: plain sentences. Never use em dashes or semicolons to split
  text. Use separate sentences, commas, or parentheses instead. This applies to
  all vault notes Claude writes (topic and plan notes).
- Distilled facts and pointers, not knowledge dumps. Never dump code or
  duplicate documentation that lives in the repo.
- Never record version pins or other fast-changing values (e.g.
  `my-shop-repo: 4.0.3`). Package manifests and repo configuration
  (composer.json, package.json, lock files) are the authority. Topic notes may
  describe where a module is installed and why, never which version.
- Never mirror mutable workflow state. Plan frontmatter is authoritative for
  plan status, and Jira/GitLab/GitHub for ticket and MR state. Topic notes link
  to plans; they do not carry a current status for them.
- Update in place; do not append forever. Remove facts that are no longer true.
- Do not invent facts (especially test data such as test cards). A stub with
  frontmatter and 2-3 known facts is better than a padded page.
- When work lands, update the durable facts: the Tasks row's what-changed and
  flow impact, plus any affected Flows or Gotchas.

## Freshness and validation

A topic note is a claim about the world at its `updated` time. Before relying
on one during planning:

- Spot-check at least one `source_refs` entry: the file still exists and still
  matches the claim.
- If reality disagrees, trust the code, correct the topic note, and bump
  `updated`.
- A topic note that fails validation must be corrected or flagged in the plan,
  never silently trusted.

## When topics are created and updated

- During planning: topic recall runs first, and every topic linked from the plan's
  Related Topics either resolves to an existing note or gets a stub created.
- During execution: as work surfaces durable facts (gotchas, flow changes, new
  surface area), fold them into the touched topic notes and bump `updated`, the same
  way planning does. Keeping topics current is part of the work, not a finalize step.
- Ad hoc: `/obsidian-topic <Topic Name>` creates or updates a single topic
  note using the full process below.
- Topic notes are the cross-plan knowledge layer. Reviewing and maintaining them
  across plans is part of the work; tooling may assist.
- Keep the bar for new topics at stable recurring concepts. One-off details
  belong in the plan note, not a topic.

## Instructions

### 1. Resolve the topic

Search the vault for an existing note with that basename: project dirs under
`<root_folder>/Projects/`, `<root_folder>/Docs/`, and `General/` at the vault
root. Also grep for `[[<Topic Name>]]` links to see which notes reference it
and from which projects.

- If a note exists: this is an update. Read it and validate it per the
  Freshness and validation rules before changing anything.
- If no note exists: this is a create. Decide location per the Location rules:
  the relevant project dir if one project links it, `<root_folder>/Docs/` if
  more than one does.
- If an existing project-local note is now linked from a second project,
  promote it to `Docs/` with the toolkit's scripts/vault-fs.sh mv before updating.

### 2. Determine the topic class

- Module/system topic (a payment gateway, a subsystem, an integration): build
  the full dossier structure.
- Concept topic (a browser quirk, a recurring pattern): a short fact list is
  enough. Do not pad.

### 3. Gather evidence

1. Recall first. Search the vault for the existing note (per step 1) and for
   prior plan notes that mention the topic. Update, never duplicate.
2. For module/system dossiers, delegate a read-only deep dive to the
   `explorer` subagent (model sonnet). Have it inventory: config and entry
   points (routes, crons, observers), the capability surface (declared vs
   actually implemented), services, owned database tables, admin
   configuration, and anything surprising. Require the worker handoff
   contract return including `Topic note material`.
3. Verify before recording. Spot-check the highest-impact agent claims
   directly in code before they become facts, especially anything destined
   for Gotchas. Note the verification date on consequential claims.
4. Validate facts against current code, not plan-era descriptions. Plans are
   historical records and code moves on (services get renamed, flows change).
5. External facts (test cards, API behavior, response codes) come from
   official documentation via web search/fetch. Cite the URL inline and add
   it to `source_refs`. Never invent them. If they cannot be fetched, leave
   an honest stub line.
6. Flag unresolved questions in the note instead of guessing (e.g. "declared
   and consumed but not found where it is defined").

### 4. Write the note

- Follow the Structure, Content rules, and writing style above (plain sentences,
  no em dashes or semicolons as splitters, no version pins, distilled facts).
- `source_refs`: repo-relative module roots and doc URLs only.
- Set `created` on create, bump `updated` always.
- Use atomic writes: Write to a `.tmp` file in the target directory, then
  the toolkit's `vault-fs.sh mv`, in the `scripts/` directory at the plugin root (locate the plugin root via the installed cache path shown by /toolkit-setup, or ../scripts relative to this commands/ directory).

### 5. Maintain the link graph

- Wiki-link related topic notes from the Related Topics section.
- Prune Related Topics while there. Remove links that fail the topic bar
  (not a stable recurring concept, duplicates framework docs, or is a single
  constant). Prune both the body list and the frontmatter, and fix the same
  link in other notes so it does not dangle elsewhere.
- If the Tasks section references plan notes, wiki-link them with their full
  artifact names (e.g. `[[plan - <plan-name>]]`).

### 6. Report

Print:
- Created or updated, and the note path
- Facts verified in code (and what was checked)
- External sources fetched
- Links pruned or promoted
- Unresolved questions flagged in the note
- Agent usage (agent name and requested model)

### 7. Rules

- Do not modify project source code or Git state.
- Do not write outside `<root_folder>/`.
- Do not invent facts, ticket references, or test data.
- One topic per invocation. If the deep dive surfaces sibling topic
  candidates, list them in the report instead of creating them.
