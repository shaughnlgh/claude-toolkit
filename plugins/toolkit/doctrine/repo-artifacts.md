# Repo Artifacts

The single lookup for where a skill writes durable knowledge into a project repo. Every skill that puts facts, decisions, playbooks, or terminology into a project's `docs/` defers here instead of stating a path inline.

## Authority

This file is self-contained: it is the authority for where the toolkit writes knowledge into a project repo, not a pointer to some other spec. No skill states a repo path inline for these artifact kinds.

## Anchor

Every path in the location contract below is relative to the repo root, never the current working directory. In a monorepo where docs are package-scoped by convention (each package keeps its own `docs/`), do not guess which root applies: ask the user which one this artifact belongs to.

## Location contract

Unconditional, for every repo the toolkit writes into: if a directory below does not exist yet, the writing skill creates it.

| Kind | Path |
|---|---|
| Facts / topic docs | `docs/context/context-<kebab-name>.md` |
| Decisions / ADRs | `docs/decisions/NNNN-kebab-title.md` (four-digit, sequential, no gap-filling) |
| Playbooks / procedures | `docs/playbooks/<kebab-name>.md` |
| Glossary / terminology | `docs/glossary.md` |

## Caution: docs/ may not be knowledge docs at all

Before writing anywhere under `docs/`, check whether it is published site content or build output rather than a knowledge home: an `mkdocs.yml` or Docusaurus config at the repo root, a gitignored `docs/`, or a `docs/` that is clearly generated. Do not write there. Surface what you found and ask the user where knowledge docs actually live in this repo.

## Required frontmatter

Applies to context docs, ADRs, and playbooks. The glossary is exempt: its marker is the grill sentinel (`<!-- managed-by: toolkit/grill -->`) as the literal first line, not YAML frontmatter, per grill's own rules.

- `title`
- `summary`
- `type` — `context` | `decision` | `playbook`
- `status` — see below, never a blanket `active`
- `owner` — `git config user.name` verbatim (a full name or a team name is fine); set on create, never rewritten on a later edit
- `last_reviewed` — set or refreshed only when the file's facts were actually verified against the repo this session; otherwise preserve the existing value, never stamp today on every touch

`status` differs by type. Context docs and playbooks: `active` on create, or whatever lifecycle the writing skill defines. ADRs: mirrors the Nygard body's `Status:` line, never stamped `active` regardless of the body — `Accepted` maps to `active`, `Superseded` maps to `deprecated` plus a `superseded_by` field naming the superseding ADR, `Proposed` maps to `draft`. Update the frontmatter `status` whenever the body's `Status:` line changes.

Context docs carry, immediately after the frontmatter block, a literal `<!-- managed-by: toolkit -->` line, the ownership marker. A skill may only update a context doc that already carries this marker; on one that does not, surface it and ask (rename, add the marker, or skip) rather than restructuring it silently.

Context docs may also carry an optional `source_refs` list (repo-relative paths or doc URLs) as freshness anchors, the same role they play in vault topic notes.

ADRs keep the Nygard body (Context / Decision / Consequences) below the frontmatter, not instead of it.

## Consent is part of the contract

Writing or migrating any artifact this file governs happens only behind a consent gate: list the exact files that will be created, changed, or renamed, get one explicit yes, then hand the settled content to the `implementer` agent to write. No ungated write, ever, regardless of which skill, or plain conversation, triggers it. `doctrine/conventions.md`'s pointer to this file inherits this rule: mentioning a repo doc in conversation never skips the gate.

## Migrating an older layout

Only a layout the toolkit itself owns may ride a writing skill's normal consent gate: a root `CONTEXT.md` carrying the grill sentinel as its first line. Propose renaming it into the location contract as one bullet in that gate's file list.

An existing `docs/adr/` directory is never auto-proposed, even inside grill's own gate. Flag it and ask about it as its own explicit question: state the ADR count, and warn that external links, CI, or ADR tooling may depend on the existing paths. On a yes, migrate in two separate gates, not one: first the renames alone, approved as their own enumerated list; only after that approval, the reference sweep's edit list (every file that mentions an old ADR path), presented as a second enumerated gate before any edit is made. Recommend a clean working tree before starting either phase.

## Vault vs repo boundary

Plans, briefs, sessions, handoffs, and work notes stay in the vault, personal process artifacts. Shared engineering knowledge (facts, decisions, playbooks, glossary) belongs in the repo. A vault topic note becomes a personal hub: a banner pointing at the canonical repo doc, never a second copy of the facts.
