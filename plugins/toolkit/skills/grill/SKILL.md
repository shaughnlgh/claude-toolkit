---
name: grill
description: >-
  Use when the user explicitly asks to grill, elicit, or interview requirements for a
  feature or fuzzy task before any plan exists, to run a scoped grill on a wayfinder
  child stub before that child's own planning, or when an expedition's grill gate fires
  it on the user's confirmed yes. Interviews one question at a time with
  a recommended answer for each, settles from the codebase whatever the codebase can
  answer instead of asking, and once the user confirms shared understanding, writes a
  canonical glossary (CONTEXT.md) and Nygard-style ADRs (docs/adr/) into the project
  repo behind a single consent gate, then hands off to plan-workflow. Do not invoke on
  task fuzziness the model detects on its own. Only an explicit grill, elicit, or
  interview request should trigger this.
---

# Grill

This skill runs before planning, only when the user explicitly asks to grill, elicit,
or interview requirements. It is the requirements-elicitation front end that feeds the
existing plan-first workflow: it extracts fuzzy requirements from the user
interactively, pins vague language into canonical terms, and records durable,
repo-owned artifacts before a plan exists. `plan-workflow` is conductor-driven (Claude
reads the code and lists Open Questions at the end of a drafted plan). Grill inverts
that by interviewing the user up front. See Boundary below for what grill does not do.

A skill is markdown instructions the model follows, not deterministic code. The
behaviors below that can be made mechanical (the git precondition, the sentinel
marker, the single end-of-interview consent gate with its one named exception for
deferred out-of-phase items, the explicit-request trigger) are
stated as hard rules. The rest (one question at a time, recommending before deciding,
keeping ADRs rare) are discipline: follow them carefully, but they are not enforced by
tooling.

## Trigger and scope

Fire only when the user explicitly asks to grill, elicit, or interview requirements
(e.g. "grill me on this", "let's elicit the requirements for X", "interview me about Y
before we plan it") — or when an expedition's grill gate fires it: the user's confirmed
yes at that gate is the explicit request. A wayfinder handoff only recommends per-child
grills; the user still invokes each one. Do not self-fire because a task looks fuzzy or underspecified.
Fuzziness alone is not a trigger. Only an explicit grill, elicit, or interview request
should trigger this skill. If unsure whether the user is asking for this, ask rather
than assume.

Phase-scoped grills: when the user invokes grill on a wayfinder child stub, scope the interview to that child's issue codes and objective — do not re-litigate the umbrella's agreed outcome (wayfinder's alignment step settled it; treat it as a given unless the interview surfaces evidence it is wrong, and then say so rather than silently diverging). Repeat grills across children of one family append to the same `CONTEXT.md` through the existing update mechanics; the ADR three-part gate applies unchanged, per decision, not per child.

## Preconditions, checked immediately, before the interview starts

1. Confirm the working directory is inside a git repository (`git rev-parse
   --is-inside-work-tree`). If it is not, do not write anything, tell the user why, and
   ask whether to proceed anyway. If they confirm, continue the interview for its
   discussion value only, and say plainly at the end that nothing will be written and
   why. If they do not confirm, stop.
2. If it is a git repository, check for a dirty working tree (`git status
   --porcelain`). If dirty, warn the user once (new files will land in a tree that
   already has uncommitted changes) and continue. This is a warning, not a block.

Checking this before the interview begins avoids spending the user's time only to
discover at the end that nothing can be written.

## The interview loop

- One question at a time, in dependency order. Sequence questions so that an early
  answer can resolve, remove, or reshape several later ones. Do not ask a question
  whose answer depends on a question not yet asked.
- Dependency order means the alignment layer comes first: the intended outcome, the definition of success, and the rough sequencing are the answers everything else depends on. When those settle and the evidence says the work is really several phases (multiple independent workstreams), pause at that depth and surface the split decision (in an expedition, that is the expedition's gate; standalone, recommend wayfinder) instead of grilling phase-5 detail that will be stale before phase 5 starts. A pause at alignment depth ends the interview at this altitude, so run the consent gate then for whatever glossary or ADR material the alignment layer produced, before handing off — wayfinder consumes the agreed outcome from the conversation and the umbrella plan, not from unwritten notes. If the work stays one plan, continue to full depth as normal.
- The deferred-ideas exception (the one named exception to the consent gate): an answer that surfaces material belonging to a different phase gets recorded outside the conversation at the moment it surfaces, not held for the write gate — deferred ideas that live only in conversation get lost. The target is the wayfinder child stub that owns it (Open Questions or Current Context) when stubs exist, or the expedition work note's Parked Items section before they do. These are vault plan artifacts, so the write goes through plan-workflow's mechanics (load plan-workflow, atomic write via vault-fs.sh, validate-plan.py after a stub edit) — this exception updates existing pipeline artifacts and never touches grill's own repo artifacts, which stay behind the consent gate. Announce each such write as it happens.
- Offer a recommended answer with every question (recommend, then confirm, never
  decide silently). State the recommendation and the reasoning in one line, then ask
  for a yes, a correction, or a different answer. Confirm-or-correct questions use the
  AskUserQuestion form per the communication doctrine; open-ended elicitation stays prose.
- Before asking, check what the codebase can already settle (existing code, config,
  naming, docs, prior ADRs). State the settled answer instead of asking, and let the
  user correct it if it is wrong. Only ask what the codebase genuinely cannot answer.
- Let each answer reshape the remaining queue. Re-derive the next question from the
  running state rather than working through a fixed list.
- Track two running lists in the conversation only, not on disk: resolved terms (for
  the glossary) and resolved decisions with their rationale and alternatives
  considered (candidate ADR material). Nothing is written until the consent gate below,
  except the deferred-ideas exception above.
- The interview ends when the open questions are exhausted or the user says they are
  satisfied. Move to the consent gate next.

## Shared-understanding confirmation (the single consent gate)

Before writing anything:

1. Summarize, in the conversation, the resolved terms and resolved decisions.
2. Ask the user to confirm this is a shared understanding.
3. List every file that will be created or changed, exactly, for example:

   ```
   I will write:
   - CONTEXT.md (new, with the grill sentinel marker)
   - docs/adr/0007-cache-invalidation-strategy.md (new)

   Proceed?
   ```

4. Hand the exact settled content to `toolkit:implementer` to write only after one explicit yes to this exact list; the conductor does not write these files itself. If the user does not confirm, or the interview is abandoned before this point, write nothing. There is no incremental or mid-interview write of grill's own artifacts. Everything accumulates in conversation only, until this single gate — the sole exception is the deferred-ideas rule in the interview loop, which updates existing pipeline artifacts, never grill's own.

## Writing the glossary (CONTEXT.md)

Location: `CONTEXT.md` at the repo root. One root file for now (a `CONTEXT-MAP.md` for
multi-context repos is a possible future extension, not built here).

- On create, write the sentinel marker as the literal first line, then the glossary:

  ```
  <!-- managed-by: toolkit/grill -->
  # Context

  ## Glossary

  ### <Term>

  <one to three plain sentences: the canonical definition>

  ### <Next Term>

  ...
  ```

  Terms are sorted alphabetically under the single `## Glossary` heading.

- On an existing `CONTEXT.md` that has the sentinel marker as its first line: this is
  an update. Read the whole file first (recall-before-write). Insert new terms
  alphabetically under the existing `## Glossary` heading. Before adding a term, check
  the existing `### Term` headings case-insensitively. If it already exists, update
  its definition in place instead of adding a second section for it. Never duplicate a
  term.
- On an existing `CONTEXT.md` that does NOT have the sentinel marker: refuse to edit
  it. Tell the user it looks foreign (owned by something other than this skill) and
  ask how they want to proceed (rename their file, add the marker themselves, or skip
  the glossary write this round). Do not append to it or overwrite it.
- Content rule: canonical terms only. A definition is the settled meaning of a term in
  this project's domain, in plain language. No implementation detail: no file paths,
  no class or function names, no code. ("Reconciliation Window" belongs. A note about
  which service class implements it does not.)

## Writing ADRs (docs/adr/)

Location: `docs/adr/NNNN-kebab-title.md`, four-digit, sequential. Before writing, scan
`docs/adr/*.md` for the highest existing `NNNN` and use max-plus-one. If `docs/adr/`
does not exist yet, create it and start at `0001`. Do not fill numbering gaps and do
not create a `0000` meta-ADR.

Template (Nygard):

```
# NNNN. Title

Date: YYYY-MM-DD

Status: Accepted

## Context

<what forces are at play, what problem this addresses>

## Decision

<what was decided>

## Consequences

<what becomes easier or harder as a result, including tradeoffs accepted>
```

### The three-part gate (strict)

Create an ADR only when the decision meets ALL three conditions:

1. It is hard to reverse.
2. It would be surprising without the context recorded here.
3. It came out of a real trade-off between weighed alternatives, not an obvious
   default.

Missing any one of the three: no ADR. Most decisions surfaced during an interview fail
this gate and belong in the glossary or the conversation record only, not as an ADR.
Keep ADRs rare on purpose. A flood of them dilutes the ones that matter.

## Writes go into the project repo, never the vault

Grill is the first toolkit skill that writes into the project repo's working directory instead of the vault other toolkit skills use for plan and topic notes. After the consent gate, `toolkit:implementer` writes the settled content: the conductor hands over the exact CONTEXT.md and ADR text agreed to at the gate, verbatim, then reads the written files back to confirm they match — the conductor never calls Write/Edit on these artifacts itself. Nothing grill produces (glossary, ADRs) goes into the vault, and grill never reads or writes the vault's sync config. The deferred-ideas exception is not a grill artifact: it updates existing pipeline notes (wayfinder stubs, an expedition work note) that live in the vault, and exactly those writes use plan-workflow's vault mechanics (atomic write via vault-fs.sh) rather than plain Write.

## Report step

After writing, print exactly what happened:

- Created or updated, and the path, for `CONTEXT.md`.
- Created, and the path, for each ADR.
- The terms added or updated, and the ADR titles, in one short list each.

## Done signal and handoff to plan-workflow

The interview's stop point is the same as the consent gate: explicit user confirmation
of shared understanding, followed by the write and the report above. Once reported,
name the exact artifacts for the next step:

```
Handoff to plan-workflow:
- Glossary: CONTEXT.md
- ADRs: docs/adr/0007-cache-invalidation-strategy.md
```

Tell the user that `plan-workflow` (`../plan-workflow/SKILL.md` from this skill's base
directory) should feed these paths into its Current Context and Related Topics, and
skip re-deriving the terms and decisions already pinned here.

Then stop. Grill does not continue into planning, does not loop back into another
round of questions, and does not start drafting a plan in the same turn.

## Boundary

Grill does not write plan notes. Grill does not duplicate `plan-workflow`'s Open
Questions section, it produces a different artifact (a glossary and ADRs, not a plan).
Grill does not invoke `plan-critic`. Those stay `plan-workflow`'s job, started fresh by
the user or conductor after grill hands off.
