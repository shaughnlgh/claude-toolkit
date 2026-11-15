---
description: Create or update a topic's canonical knowledge — the canonical spec for topic-note/repo-mode location, structure, and freshness
argument-hint: <topic name> [repo hint]
---

# Topic

Create or update a topic's canonical knowledge: in the vault, or — per Repo mode below — in the project repo when the topic qualifies. This file is the single source of truth for topic notes and repo-mode context docs alike (mode choice, location, frontmatter, structure, content rules, freshness, and the build/update process) — the plan-guide skill and CLAUDE.md point here.

`<plugin-root>` in this file is `${CLAUDE_PLUGIN_ROOT}` when this file runs as `/toolkit:topic`, and the directory above the `commands/` directory that holds this file when a skill or `/toolkit:obsidian-topic` reads it.

## Usage

$ARGUMENTS

Arguments are the topic name, optionally followed by a repo hint.

Examples:

- `/toolkit:topic Stripe Payments`
- `/toolkit:topic 3D Secure my-shop-repo`
- `/toolkit:topic Mobile Safari Tab Suspension`

If no topic name is provided, stop and report:

    error: topic name is required.
    usage: /toolkit:topic <Topic Name> [repo]

## What topic notes are

Topic notes are the vault's distilled knowledge layer: stable concepts (a payment provider, a subsystem, a recurring pattern) that multiple plans can reference. They are what makes pre-planning recall cheaper than re-exploration.

## Repo mode

Some topics are shareable engineering knowledge about the project's systems (a subsystem, an integration, a recurring pattern) that any teammate in the repo would want, not personal workflow (which plans touched it, what still needs checking, reminders to yourself). When the topic is that kind of knowledge, the canonical home is the repo, not the vault.

### Preconditions

- The current working directory must be a git repo the user is actively developing in, not a third-party checkout, a vendor tree, or a read-only reference clone. When in doubt, ask rather than guess.
- Before proposing content at the gate, scrub it per `doctrine/security.md`: no secrets, tokens, credentials, internal hostnames paired with auth details, or personal data may cross from the vault into the repo. Anything questionable is surfaced and asked about, never written silently.
- Before any repo write, run the docs-dir caution and the repo-root/monorepo anchor check from `doctrine/repo-artifacts.md`: confirm `docs/` here is a knowledge home, not published site content or build output, and confirm which repo root the write anchors to.

### Mechanics

- Canonical facts live at `docs/context/context-<kebab-topic>.md`, with the frontmatter `doctrine/repo-artifacts.md` requires (`title`, `summary`, `type: context`, `status: active`, `owner`, `last_reviewed`, optionally `source_refs`), plus the `<!-- managed-by: toolkit -->` marker immediately after the frontmatter block. The directory is created if it does not exist yet.
- An existing `docs/context/context-<kebab-topic>.md` that does NOT carry the `<!-- managed-by: toolkit -->` marker is foreign: surface it and ask how to proceed (rename their file, add the marker themselves, or skip the repo write this round), never restructure it silently.
- Body content follows the same Structure and Content rules as any topic note below, minus the Tasks section — plan links and workflow status are vault-side, never repo-side.
- Before writing, run the same consent gate grill uses for its own repo artifacts: list the exact repo file (created or updated) and the vault note's resulting shape, ask the user to confirm, then hand the settled content to `toolkit:implementer` to write — the conductor never calls Write/Edit on the repo doc itself. The consent gate is the control: declining it keeps the topic vault-only.
- Write order matters: the repo doc is written first, after the gate, via `toolkit:implementer`, read back to confirm it matches, and only then does the vault note collapse to the hub shape. Until the repo doc is committed by the human, it is the sole full copy of the facts.
- The vault note becomes, or remains, the personal hub: right after its frontmatter, a banner naming the canonical repo doc (for example `> Canonical facts: docs/context/context-3d-secure.md in this repo.`). Below the banner, the vault note keeps only vault-side material (Tasks, plan links, personal reminders) and never duplicates facts now owned by the repo doc.
- Once a vault note carries this banner, it is pinned: any new fact for that topic routes to the repo doc the banner names, never back into the vault note. The hub never regrows facts.
- Promoting an existing full vault note into repo mode (the topic was reclassified as shareable) migrates the facts out in the same consent-gated write, in the write order above: the repo doc is created from the vault note's current content first, then the vault note is collapsed to the hub shape. Report the migration explicitly.
- Repo-mode docs never move to `<root_folder>/Docs/` the way a project-local vault note promotes on a second link — that promotion path is for vault-owned notes only. A repo doc that a second repo starts wanting is a cross-repo case; flag it in the report and let the user decide, do not move it yourself.
- A topic spanning multiple repos, or not about any particular repo, is vault-only, always. A topic about the current repo is repo-mode-eligible whether or not a repo hint was passed to the command; the hint only disambiguates which repo when the topic is not about the cwd.
- Vault-only is also the outcome for topics that are personal workflow rather than shareable knowledge, and for any repo-mode consent gate the user declines: proceed with the rest of this file, unchanged.

## Location and naming

Resolve `vault_path` and `root_folder` from the vault config: `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent. Every vault path below is relative to `<root_folder>` unless stated otherwise.

- Human-readable Title Case basenames (e.g. `Stripe Payments.md`). No plan-name suffix — topics are shared across plans by design.
- Claude creates new topic notes in the current project directory: `Projects/{repo_name}/<Topic>.md`.
- Cross-project topics live in `<root_folder>/Docs/`. When a second project starts linking a project-local topic, promote it: move the note to `Docs/` with the toolkit's scripts/vault-fs.sh mv — wiki links resolve by basename, so moves are safe.
- Topic-like notes may also exist in `General/` at the vault root (user-curated). Link to them freely, but Claude does not write outside `<root_folder>/`, except the repo-mode canonical doc (`docs/context/context-<kebab-topic>.md`) in the current repo, per Repo mode above.
- Basenames must be unique across the vault. Search before creating.

## Required topic frontmatter

```yaml
---
type: topic
created:
updated:
verified:
repos:
source_refs:
tags:
---
```

Freshness fields, exact semantics:

- `created`: the original creation date. Immutable.
- `updated`: the last content edit of any kind (fact added or removed, Tasks row, reformat, migration). Bumped on every write. Makes no claim about truth.
- `verified`: the last date the note's claims were checked against `source_refs` (spot-check at minimum, deep-dive at best). Blank means no recorded verification. Blank is honest, never an error to paper over.

`updated` later than `verified` means the note changed after its last recorded verification. Equal date-only values do not prove which happened first. These fields support triage; they never remove the spot-check-before-relying rule for consequential claims.

- `repos`: the repos this topic applies to.
- `source_refs`: repo-relative module/system roots (e.g. `vendor/acme/module-payments/`) or doc URLs the facts were derived from. No repo prefix — the same module is installed in multiple repos, and the relative path locates it inside whichever project a task is scoped to. These are the freshness anchors — required, not optional. File-level paths belong in plan notes and Tasks entries, not here.

## Structure

Topic notes are written for humans as well as Claude — a teammate reading one should understand what the thing is, where it lives, how it behaves, what has been done to it, and how to test it. For module/system topics use these sections (omit any that do not apply):

- Overview — what it is and what features it offers (one short paragraph)
- Where it lives — composer package / git repo or registry, the repos it is installed in, module root path, key classes or entry points. No versions: package manifests and repo configuration are the authority for version pins.
- Depends on / associates with — related modules and why they are coupled
- Flows — how the important paths actually behave
- Tasks — historical work context only: task (wiki-link the plan note), repo, what changed or is planned, and the flow impact or durable outcome. No status column. Plan frontmatter is authoritative for workflow status and the ticket for external state, so the linked plan note is where status lives.
- Gotchas — known issues, surprises, and hard-won lessons
- Testing — test mode config, test cards/accounts, how to exercise the flows
- Related Topics — `[[wiki links]]` to related topic notes

For narrower concept topics (a browser quirk, a recurring pattern), a short fact list is enough — do not pad to fill the structure.

## Content rules

- Writing style: plain sentences. Never use em dashes or semicolons to split text. Use separate sentences, commas, or parentheses instead. This applies to all vault notes Claude writes (topic and plan notes).
- Distilled facts and pointers, not knowledge dumps. Never dump code or duplicate documentation that lives in the repo.
- Never record version pins or other fast-changing values (e.g. `my-shop-repo: 4.0.3`). Package manifests and repo configuration (composer.json, package.json, lock files) are the authority. Topic notes may describe where a module is installed and why, never which version.
- Never mirror mutable workflow state. Plan frontmatter is authoritative for plan status, and Jira/GitLab/GitHub for ticket and MR state. Topic notes link to plans; they do not carry a current status for them.
- Update in place; do not append forever. Remove facts that are no longer true.
- Do not invent facts (especially test data such as test cards). A stub with frontmatter and 2-3 known facts is better than a padded page.
- When work lands, update the durable facts: the Tasks row's what-changed and flow impact, plus any affected Flows or Gotchas.

## Freshness and validation

A topic note is a claim about the world at its `verified` time. A blank `verified` means unverified. `updated` records edit recency only and is never a truth timestamp. Before relying on a topic note during planning:

- Spot-check at least one `source_refs` entry: the file still exists and still matches the claim. Code and source evidence always outrank the note.
- A clean check (facts hold, nothing to correct) is recordable: set `verified` to today. That is the whole point of the field.
- If reality disagrees, trust the code, correct the note from the checked evidence, and set both `updated` and `verified` to today.
- An edit that did not re-check the rest of the note (new fact folded in, a Tasks row, a mechanical change) bumps `updated` only.
- A topic note that fails validation must be corrected or flagged in the plan, never silently trusted.

## When topics are created and updated

- During planning: topic recall runs first, and every topic linked from the plan's Related Topics either resolves to an existing note or gets a stub created.
- During execution: workers return durable facts as Topic note material, and the remember pass routes them once per slice (§ Remember pass).
- Ad hoc: `/toolkit:topic <Topic Name>` creates or updates a single topic note using the full process below.
- Topic notes are the cross-plan knowledge layer. Reviewing and maintaining them across plans is part of the work; tooling may assist.
- Keep the bar for new topics at stable recurring concepts. One-off details belong in the plan note, not a topic.

## Remember pass

Runs once per implementation slice, from red-team step 7b, the execute flow's `execute-runner` workflow, or plan-guide Session Closure, whichever comes first. A `Remember:` line under the plan note's Plan Changes During Execution is the signal that the pass already ran for the slice. For a slice with no plan note, the line goes in the red-team report only, and that report is the signal. The remember pass is distinct from execution-guide's Doc Update Pass: the doc pass keeps existing docs accurate about what changed, the remember pass records what the slice learned.

### Inputs

The conductor gathers these before delegating:

- The cumulative slice diff. Capture it by red-team step 2's method: `git diff HEAD` into a scratchpad file, plus `git diff --no-index -- /dev/null <file>` appended for each untracked file. Red-team step 7b captures it fresh after the doc pass. Session Closure captures it the same way when red-team has not run.
- The files the slice touched.
- Every Topic note material return from this slice.
- The recall hits from `python3 <plugin-root>/scripts/topic-recall.py --repo <repo> --repo-root <repo root> <touched module and plan terms>`.

### Brief

The conductor delegates one `implementer` worker with this brief, verbatim apart from the bracketed values.

> Objective: route the durable facts this slice surfaced. Fold the vault-bound facts into vault topic notes, and stage the repo-bound facts as proposed doc content for the conductor's consent gate.
>
> Scope: write only under the vault root folder [vault path]/[root folder] and the scratchpad [scratchpad path]. You must not write any repo file.
>
> Known evidence: the cumulative diff at [diff path], the touched files [list], the Topic note material returns from this slice [pasted], and the recall hits [pasted].
>
> Task-specific constraints. The plugin root is [plugin root]. Before your first write, read these files under that root: `commands/topic.md`, `doctrine/security.md`, `doctrine/repo-artifacts.md`, and the usage header of `scripts/vault-fs.sh`.
>
> Routing: before any write, classify each durable fact. Class (a) is shareable engineering knowledge about this repo. Class (b) is cross-repo, not about any repo, or personal workflow. A class (a) fact routes only to a `docs/context/` doc that carries the `<!-- managed-by: toolkit -->` marker: an existing one that covers the subject, else a new `docs/context/context-<kebab>.md`. Never route a fact into a hand-written repo doc. If a hand-written repo doc covers the subject, name it as the related doc on the proposal. A class (b) fact routes to the vault topic note. If a vault note carries the repo-mode banner, route its new facts to the doc the banner names, never into the note.
>
> Class (a) content: for each proposed repo doc, write the full proposed content to `[scratchpad path]/remember-<kebab-path>.md`, where `<kebab-path>` is the repo-relative path in kebab case. Scrub the content per `doctrine/security.md` first. For a new file, write the whole doc with the frontmatter `doctrine/repo-artifacts.md` requires and the `<!-- managed-by: toolkit -->` marker on the line after the frontmatter. For an existing managed file, write only the exact section to add and name the heading it goes under. Do not write class (a) facts into any vault note.
>
> Class (b) writes: for each candidate topic, fold facts under the section they belong to (Flows, Gotchas, Tasks, Related Topics). Never rewrite Overview or any prose that carries no new fact. Bump `updated`. Spot-check one `source_refs` entry against the repo, and set `verified` to today only on a clean check. Create a stub only for a concept that the plan's Related Topics or the collected material names and no existing note covers. Search by basename before creating. Write every vault file atomically: Write to `<name>.tmp.md` beside the target, then run `bash <plugin root>/scripts/vault-fs.sh mv`.
>
> Required checks: read back every vault file you wrote and confirm it holds the folded facts. Run no git command.
>
> Expected return format: the standard worker fields plus `Proposed repo doc changes`. Write one line per repo file as `<repo-relative path>, created or updated, <scratch file path>, facts from <[[Note]], ...> or none`, where the notes are the vault notes whose facts move into that doc. If a hand-written doc covers the subject, append `, related <repo-relative path>`. If there is no proposal, write `none`. End with exactly one draft line in one of these forms: `Remember: repo docs <paths>; topics updated [[A]], [[B]]`, `Remember: repo docs <paths>`, `Remember: topics updated [[A]]`, `Remember: no change (<reason>)`.

### Gate and record

1. If `Proposed repo doc changes` reads `none`, skip to step 6 and record the worker's `Remember:` line as it stands.
2. Run the Repo mode preconditions for each proposal: confirm the repo is one the user actively develops, not a third-party checkout, a vendor tree, or a read-only reference clone, then run the docs-dir caution and the repo-root anchor check.
3. Show the consent gate once. For each proposal, list the repo path, created or updated, the scratch file, the related hand-written doc when there is one, and the resulting shape of each vault note whose facts move. That shape is the hub (banner plus vault-side material only) when every fact moves, else the note without the moved facts.
4. Delegate one `implementer` to write each accepted scratch file to its repo path: the whole file for a new doc, the section under its named heading for an existing managed doc. In that same delegation, the implementer folds each declined proposal's facts into the vault topic by the class (b) rules.
5. Read each written repo doc back and confirm it matches its scratch file. Only then delegate the hub collapse. A vault note collapses to a hub only when every fact it holds moved to an accepted doc. A note that also holds class (b) facts does not collapse: the implementer removes only the moved facts from it and keeps the rest.
6. If a vault topic note was created, updated, moved or removed in this pass, run `bash <plugin-root>/scripts/vault-fs.sh topic-index`. Record one `Remember:` line in one of the four forms. It lists only the repo paths accepted at the gate. It lists every vault topic touched: the ones the worker updated, the ones that received declined facts, and the ones collapsed to hubs or trimmed of moved facts. Record it under the plan note's Plan Changes During Execution, and repeat it in the red-team report and the commit suggestion. For a slice with no plan note, record it in the red-team report only.

## Instructions

### 1. Choose the mode

Decide repo mode or vault-only per Repo mode above, before resolving anything else — it changes where step 5's write lands and what step 2's search is even for.

- A topic spanning multiple repos, or not about any particular repo, is vault-only, always, whether or not a repo hint was passed.
- A topic about the current repo is repo-mode-eligible whether or not a repo hint was passed; judge whether it is shareable engineering knowledge rather than personal workflow: shareable knowledge heads for repo mode, subject to the consent gate in step 5; personal workflow is vault-only.
- State the chosen mode and why in one line before continuing.

### 2. Resolve the topic

Search the vault for an existing note with that basename: project dirs under `<root_folder>/Projects/`, `<root_folder>/Docs/`, and `General/` at the vault root. Also grep for `[[<Topic Name>]]` links to see which notes reference it and from which projects. In repo mode, also check the repo for an existing `docs/context/context-<kebab-topic>.md`.

- If a note exists: this is an update. Read it and validate it per the Freshness and validation rules before changing anything.
- If no note exists: this is a create. Decide location per the Location rules: the relevant project dir if one project links it, `<root_folder>/Docs/` if more than one does.
- If an existing project-local note is now linked from a second project, promote it to `Docs/` with the toolkit's scripts/vault-fs.sh mv before updating.
- If an existing full vault note now qualifies for repo mode (per step 1), this is a promotion: migrate its facts into the repo doc per Repo mode above instead of updating it as a standalone dossier.
- If an existing vault note already carries the canonical-source banner, it is already a hub, not a promotion candidate: route any new facts to the repo doc it names, per Repo mode above, never back into the note.

### 3. Determine the topic class

- Module/system topic (a payment gateway, a subsystem, an integration): build the full dossier structure.
- Concept topic (a browser quirk, a recurring pattern): a short fact list is enough. Do not pad.

### 4. Gather evidence

1. Recall first. Search the vault for the existing note (per step 2) and for prior plan notes that mention the topic. Update, never duplicate.
2. For module/system dossiers, delegate a read-only deep dive to the `explorer` subagent (model sonnet). Have it inventory: config and entry points (routes, crons, observers), the capability surface (declared vs actually implemented), services, owned database tables, admin configuration, and anything surprising. Require the worker handoff contract return including `Topic note material`.
3. Verify before recording. Spot-check the highest-impact agent claims directly in code before they become facts, especially anything destined for Gotchas. Note the verification date on consequential claims.
4. Validate facts against current code, not plan-era descriptions. Plans are historical records and code moves on (services get renamed, flows change).
5. External facts (test cards, API behavior, response codes) come from official documentation via web search/fetch. Cite the URL inline and add it to `source_refs`. Never invent them. If they cannot be fetched, leave an honest stub line.
6. Flag unresolved questions in the note instead of guessing (e.g. "declared and consumed but not found where it is defined").

### 5. Write the note

- In repo mode, follow Repo mode's Preconditions and Mechanics above: scrub the content per `doctrine/security.md`, confirm the target `docs/context/context-<kebab-topic>.md` either does not exist or already carries the `<!-- managed-by: toolkit -->` marker, run the consent gate (list the exact repo file and the vault note's resulting hub shape, one explicit yes), hand the settled content to `toolkit:implementer` with the frontmatter and marker the doctrine requires, then read the written file back to confirm it matches. Only after that write exists on disk does the vault note collapse to the hub: the banner plus vault-side material only, via the same atomic-write mechanics below.
- Follow the Structure, Content rules, and writing style above (plain sentences, no em dashes or semicolons as splitters, no version pins, distilled facts).
- `source_refs`: repo-relative module roots and doc URLs only.
- On create, set `created`, `updated`, and `verified` to the creation date (the evidence-gathering process above is a verification). On update, bump `updated` always; set `verified` only when the note's facts were actually checked this session (see Freshness and validation).
- Use atomic writes: Write to a `.tmp.md` file beside the destination, then `bash <plugin-root>/scripts/vault-fs.sh mv`.
- After a topic note is created, updated, moved or removed in the vault, run `bash <plugin-root>/scripts/vault-fs.sh topic-index`.

### 6. Maintain the link graph

- Wiki-link related topic notes from the Related Topics section.
- Prune Related Topics while there. Remove links that fail the topic bar (not a stable recurring concept, duplicates framework docs, or is a single constant). Prune both the body list and the frontmatter, and fix the same link in other notes so it does not dangle elsewhere.
- If the Tasks section references plan notes, wiki-link them with their full artifact names (e.g. `[[plan - <plan-name>]]`).

### 7. Report

Print:
- Mode chosen (repo or vault-only) and why
- Created or updated, and the note path (and, in repo mode, the repo doc path, and whether it was a create, an update, or a promotion from an existing vault note)
- Facts verified in code (and what was checked)
- External sources fetched
- Links pruned or promoted
- Unresolved questions flagged in the note
- Agent usage (agent name and requested model)

### 8. Rules

- Do not modify project source code or Git state, except the repo-mode canonical doc write in step 5, behind its own consent gate — no other repo file changes.
- Do not write outside `<root_folder>/`, except that same repo-mode canonical doc (`docs/context/context-<kebab-topic>.md`) in the current repo.
- Do not invent facts, ticket references, or test data.
- One topic per invocation. If the deep dive surfaces sibling topic candidates, list them in the report instead of creating them.
- These rules bind the ad hoc command. The remember pass follows the Scope in § Remember pass instead, which allows its scratchpad files, and it may touch several topics in one run.
