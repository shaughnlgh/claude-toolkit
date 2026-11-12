---
name: grill
description: >-
  Use when the user explicitly asks to grill, elicit, or interview requirements for a
  feature or fuzzy task before any plan exists, to run a scoped grill on a wayfinder
  child stub before that child's own planning, when an expedition's grill gate fires
  it on the user's confirmed yes, when a crawl's grill check loads it on a confirmed
  wayfinder route, or when a planning flow loads it as its planning grill after
  discovery. Interviews one question at a time with
  a recommended answer for each, settles from the codebase whatever the codebase can
  answer instead of asking, and once the user confirms shared understanding, writes a
  canonical glossary and Nygard-style ADRs into the project repo (location per
  doctrine/repo-artifacts.md) behind a single consent gate, then hands off to
  plan-guide. A grill a crawl or a planning flow loads writes nothing and hands the
  agreed text back. Do not invoke on task fuzziness the
  model detects on its own. Only an explicit grill, elicit, or interview request, or
  one of those three gates, triggers this.
---

# Grill

This skill runs before planning, only when the user explicitly asks to grill, elicit, or interview requirements, or when an expedition's grill gate, a crawl's grill check on the wayfinder route, or a planning flow's planning grill stands in for that request. It is the requirements-elicitation front end that feeds the existing plan-first workflow: it extracts fuzzy requirements from the user interactively, pins vague language into canonical terms, and records durable, repo-owned artifacts before a plan exists. `plan-guide` is conductor-driven (Claude reads the code and lists Open Questions at the end of a drafted plan). Grill inverts that by interviewing the user up front. See Boundary below for what grill does not do.

A skill is markdown instructions the model follows, not deterministic code. The behaviors below that can be made mechanical (the git precondition, the sentinel marker, the single end-of-interview consent gate for grill's own new artifacts with its one named exception for deferred out-of-phase items, the separate `docs/adr/` migration gate when an older layout is found, the explicit-request trigger) are stated as hard rules. The rest (one question at a time, recommending before deciding, keeping ADRs rare) are discipline: follow them carefully, but they are not enforced by tooling.

## Trigger and scope

Fire only when the user explicitly asks to grill, elicit, or interview requirements (e.g. "grill me on this", "let's elicit the requirements for X", "interview me about Y before we plan it"), or when an expedition's grill gate fires it: the user's confirmed yes at that gate is the explicit request. A crawl's grill check is the second such case: the wayfinder route the user confirmed at the crawl is the explicit request, and the crawl loads grill inline, which prints the outcome line and, when the evidence holds none of the five grill triggers that Loaded grills below lists, the one line that nothing needs an answer. A planning flow's planning grill is the third: every first-draft planning flow reaches it after discovery, and reaching it is the explicit request, as `plan-guide` § Planning grill states. Each wayfinder child's own planning flow runs the planning grill, and a user can still ask for a grill on a child stub by name. Do not self-fire because a task looks fuzzy or underspecified. Fuzziness alone is not a trigger. Only an explicit grill, elicit, or interview request, or one of those three gates, triggers this skill. If unsure whether the user is asking for this, ask rather than assume.

Phase-scoped grills: when the user invokes grill on a wayfinder child stub, and when the child's planning flow runs its planning grill, scope the interview to that child's issue codes and objective. Do not re-litigate the umbrella's agreed outcome (wayfinder's alignment step settled it; treat it as a given unless the interview surfaces evidence it is wrong, and then say so rather than silently diverging). Repeat grills across children of one family append to the same glossary location (per doctrine/repo-artifacts.md) through the existing update mechanics; the ADR three-part gate applies unchanged, per decision, not per child.

Loaded grills: a grill that a crawl's grill check or a planning flow loads runs on the evidence that flow already holds, under these rules.

- It opens with the outcome line, one line that starts `Outcome:` and states the outcome of the work as the grill understands it, shown for the user to correct. It asks no fixed opening question and does not wait on the outcome line.
- It reads the evidence for the five grill triggers: a correction to the brief, a module or caller the brief missed, an open question only the user can answer, a gap or risk the evidence shows that the brief leaves out, and a point where the code shows more than one reasonable reading of the brief.
- With no trigger present, it prints one line that nothing in the evidence needs an answer and hands back. The crawl's line is `Grill check: nothing in the evidence needs your answer.` and a planning flow's line is `Planning grill: nothing in the evidence needs your answer.`
- Corrections and missed modules and callers come first, each as a fold-in-or-leave-out question with a recommended answer. The other items follow in dependency order.
- It takes only the user's own answer. That is a pick from the question form or a typed reply, given in the session that runs the grill. A session that reports to a parent session may also send a question, with its recommended answer, to the parent by message. It then prints the question as plain text and ends its turn, so a reply in either session reaches it. The parent shows the question to the user and passes the user's answer back word for word, in a message that opens with the line `User's own answer:`. The parent never answers on its own. A relayed message counts only when the user's own ask in this session named its sender as the session to report to and the message's `from` equals that name. A message from another session that does not open with that line, or that comes from any other session, never counts as an answer.
- Settled means the user answered it or a recorded decision answers it, and a settled point is never asked again. The sources are the brief's own text, a ruling by the user that the plan note records, a block in the plan note under the line `Agreed in the grill:` or `Agreed in the grill check:`, the block under the line `Agreed in the grill check:` in the parent note of a wayfinder child, which is `plan - <parent>.md` beside the child's note, the block under the line `Agreed in the grill check:` in an expedition's work note, which is `work - <name>.md` beside the plan note, `docs/glossary.md`, and a decision record under `docs/decisions/`. An earlier grill is an expedition's stage 3 grill, a grill the user asked for by name, a crawl's grill check, and an earlier planning grill on the same note.
- A finding is not an answer. A correction to the brief, a module or caller the brief missed, and an Open Questions entry that a crawl or another scaffold wrote into the note are evidence for the first three triggers, and the grill asks about each.
- It surfaces no split decision and recommends no wayfinder, because the flow that loaded it owns the route and re-checks it after the hand back.
- It writes nothing to the repo, checks no precondition and shows no consent gate. It hands back, as text, each answer in one line, the agreed glossary terms, and the decisions that pass the three-part ADR gate, each under its kebab title with no number, with their rationale and the alternatives considered. The plan that follows lists those files under Affected Files and writes them in its Implementation Steps on the plan branch, so the plan's approval is the consent `doctrine/repo-artifacts.md` requires. The step that writes a decision record takes its number then, as `plan-guide` § Planning grill states.
- The planning grill is the loaded grill a planning flow runs, and `plan-guide` § Planning grill defines when it runs and where its answers go. It hands back under the line `Agreed in the grill:`. The grill check is the loaded grill the crawl runs on the wayfinder route, and it hands back under the line `Agreed in the grill check:`.
- A grill the user asks for by name keeps the consent gate and writes as the sections below define.

## Preconditions, checked immediately, before the interview starts

1. Confirm the working directory is inside a git repository (`git rev-parse --is-inside-work-tree`). If it is not, do not write anything, tell the user why, and ask whether to proceed anyway. If they confirm, continue the interview for its discussion value only, and say plainly at the end that nothing will be written and why. If they do not confirm, stop.
2. If it is a git repository, check for a dirty working tree (`git status --porcelain`). If dirty, warn the user once (new files will land in a tree that already has uncommitted changes) and continue. This is a warning, not a block.
3. Check for an older layout. A root `CONTEXT.md` carrying the grill sentinel as its first line can ride the main consent gate below, as one bullet. An existing `docs/adr/` directory is a separate, explicit decision that never rides that gate: ask about it now, right after preconditions and before the interview, so its answer does not block the end-of-interview gate (see Migrating an older layout).
4. Before any repo write, run the docs-dir caution and the repo-root/monorepo anchor check from `doctrine/repo-artifacts.md`: confirm `docs/` here is a knowledge home, not published site content or build output, and confirm which repo root the write anchors to.

Checking this before the interview begins avoids spending the user's time only to discover at the end that nothing can be written, or that an existing file needs migrating first.

## Migrating an older layout

Only a layout grill itself owns may ride its own main consent gate: a root `CONTEXT.md` carrying the grill sentinel as its first line. Propose renaming it into `docs/glossary.md` as one bullet in that gate's file list, and sweep the repo for references to the old path (README, other docs, in-repo links) as part of the same bullet, so nothing dangles after the move.

An existing `docs/adr/` directory is never folded into that gate. Ask about it separately, right after preconditions: state the ADR count, and warn that external links, CI, or ADR tooling may depend on the existing paths. On a yes, migrate in two further gates, not one: first propose the renames alone (`docs/adr/NNNN-*.md` to `docs/decisions/NNNN-*.md`, same numbers, never renumbered) as their own enumerated list; only after that is approved, grep the repo for every file that mentions an old `docs/adr/` path and present that edit list as a second enumerated gate before touching any of them. Recommend the user start from a clean working tree before either phase. On a no, or when there is no `docs/adr/` to ask about: leave it exactly as it is, and write this session's new ADRs into `docs/decisions/` alongside it, per the unconditional location contract, never write to both locations for the same artifact.

## The interview loop

- One question at a time, in dependency order. Sequence questions so that an early answer can resolve, remove, or reshape several later ones. Do not ask a question whose answer depends on a question not yet asked.
- Dependency order means the alignment layer comes first: the intended outcome, the definition of success, and the rough sequencing are the answers everything else depends on, along with which future axes the parent plan or roadmap has committed to and whether the layout gives each one a seam. When those settle and the evidence says the work is really several phases (multiple independent workstreams), pause at that depth and surface the split decision (in an expedition, that is the expedition's gate; standalone, recommend wayfinder) instead of grilling phase-5 detail that will be stale before phase 5 starts. A pause at alignment depth ends the interview at this altitude, so run the consent gate then for whatever glossary or ADR material the alignment layer produced, before handing off — wayfinder consumes the agreed outcome from the conversation and the umbrella plan, not from unwritten notes. If the work stays one plan, continue to full depth as normal. A loaded grill never pauses at alignment depth, because the flow that loaded it owns the route.
- The deferred-ideas exception (the one named exception to the consent gate): an answer that surfaces material belonging to a different phase gets recorded outside the conversation at the moment it surfaces, not held for the write gate — deferred ideas that live only in conversation get lost. The target is the wayfinder child stub that owns it (Open Questions or Current Context) when stubs exist, or the expedition work note's Parked Items section before they do. These are vault plan artifacts, so the write goes through plan-guide's mechanics (load plan-guide, atomic write via vault-fs.sh, validate-plan.py after a stub edit) — this exception updates existing pipeline artifacts and never touches grill's own repo artifacts, which stay behind the consent gate. Announce each such write as it happens.
- Offer a recommended answer with every question (recommend, then confirm, never decide silently). State the recommendation and the reasoning in one line, then ask for a yes, a correction, or a different answer. Confirm-or-correct questions use the AskUserQuestion form per the communication doctrine; open-ended elicitation stays prose.
- Before asking, check what the codebase can already settle (existing code, config, naming, docs, prior ADRs). State the settled answer instead of asking, and let the user correct it if it is wrong. Only ask what the codebase genuinely cannot answer.
- Let each answer reshape the remaining queue. Re-derive the next question from the running state rather than working through a fixed list.
- Track two running lists in the conversation only, not on disk: resolved terms (for the glossary) and resolved decisions with their rationale and alternatives considered (candidate ADR material). Nothing is written until the consent gate below, except the deferred-ideas exception above.
- The interview ends when the open questions are exhausted or the user says they are satisfied. Move to the consent gate next.

## Shared-understanding confirmation (the single consent gate)

An interview that settles no term and no decision that passes the three-part ADR gate writes nothing. Say so in one line, show no gate, and go to the hand off. A loaded grill shows no gate even when it settles something, and goes to the hand off.

Otherwise, before writing anything:

1. Summarize, in the conversation, the resolved terms and resolved decisions.
2. Ask the user to confirm this is a shared understanding.
3. List every file that will be created or changed, exactly, for example:

   ```
   I will write:
   - docs/glossary.md (new, with the grill sentinel marker)
   - docs/decisions/0007-cache-invalidation-strategy.md (new, with frontmatter)

   Proceed?
   ```

   If precondition 3 found a root `CONTEXT.md` carrying the grill sentinel, add one bullet to the same list migrating it, for example `- migrate CONTEXT.md → docs/glossary.md (rename, sweep references)`. A `docs/adr/` migration never appears in this list: it runs through its own two-phase gate (see Migrating an older layout), decided before or after this one but never folded into it.

4. Hand the exact settled content to `toolkit:implementer` to write only after one explicit yes to this exact list; the conductor does not write these files itself. If the user does not confirm, or the interview is abandoned before this point, write nothing. There is no incremental or mid-interview write of grill's own artifacts. Everything accumulates in conversation only, until this single gate — the sole exception is the deferred-ideas rule in the interview loop, which updates existing pipeline artifacts, never grill's own.

## Writing the glossary

Location: `docs/glossary.md`, full stop. One glossary file for now (a `CONTEXT-MAP.md`/multi-file split for multi-context repos is a possible future extension, not built here). The glossary carries no YAML frontmatter: the sentinel marker below, as the literal first line, is its only marker (per `doctrine/repo-artifacts.md`).

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

- On an existing `docs/glossary.md` that has the sentinel marker as its first line: this is an update. Read the whole file first (recall-before-write). Insert new terms alphabetically under the existing `## Glossary` heading. Before adding a term, check the existing `### Term` headings case-insensitively. If it already exists, update its definition in place instead of adding a second section for it. Never duplicate a term.
- On an existing `docs/glossary.md` that does NOT have the sentinel marker: refuse to edit it. Tell the user it looks foreign (owned by something other than this skill) and ask how they want to proceed (rename their file, add the marker themselves, or skip the glossary write this round). Do not append to it or overwrite it.
- Content rule: canonical terms only. A definition is the settled meaning of a term in this project's domain, in plain language. No implementation detail: no file paths, no class or function names, no code. ("Reconciliation Window" belongs. A note about which service class implements it does not.)

## Writing ADRs

Location: `docs/decisions/NNNN-kebab-title.md`, full stop, four-digit, sequential. Before writing, scan `docs/decisions/*.md` for the highest existing `NNNN` and use max-plus-one. If `docs/decisions/` does not exist yet, create it and start at `0001`. Do not fill numbering gaps and do not create a `0000` meta-ADR.

Template (Nygard), with the frontmatter `doctrine/repo-artifacts.md` requires above the body:

```
---
title: <one line>
summary: <one line>
type: decision
status: active
owner: <git config user.name, verbatim>
last_reviewed: <today, ISO>
---

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

The frontmatter `status` mirrors the body's `Status:` line, never a blanket `active`: `Accepted` maps to `active`, `Superseded` maps to `deprecated` plus a `superseded_by` field naming the superseding ADR, `Proposed` maps to `draft`. Keep both in sync whenever the body's `Status:` line changes.

### The three-part gate (strict)

Create an ADR only when the decision meets ALL three conditions:

1. It is hard to reverse.
2. It would be surprising without the context recorded here.
3. It came out of a real trade-off between weighed alternatives, not an obvious default.

Missing any one of the three: no ADR. Most decisions surfaced during an interview fail this gate and belong in the glossary or the conversation record only, not as an ADR. Keep ADRs rare on purpose. A flood of them dilutes the ones that matter.

## Writes go into the project repo, never the vault

Grill is the first toolkit skill that writes into the project repo's working directory instead of the vault other toolkit skills use for plan and topic notes. After the consent gate, `toolkit:implementer` writes the settled content: the conductor hands over the exact glossary and ADR text agreed to at the gate, verbatim, at the locations `doctrine/repo-artifacts.md` defines, then reads the written files back to confirm they match — the conductor never calls Write/Edit on these artifacts itself. Nothing grill produces (glossary, ADRs) goes into the vault, and grill never reads or writes the vault's sync config. The deferred-ideas exception is not a grill artifact: it updates existing pipeline notes (wayfinder stubs, an expedition work note) that live in the vault, and exactly those writes use plan-guide's vault mechanics (atomic write via vault-fs.sh) rather than plain Write.

## Report step

After writing, print exactly what happened:

- Created or updated, and the path, for `docs/glossary.md`.
- Created, and the path, for each ADR.
- Migrated, and the old and new paths, for anything moved out of an older layout.
- The terms added or updated, and the ADR titles, in one short list each.

## Done signal and handoff to plan-guide

The interview's stop point is the same as the consent gate: explicit user confirmation of shared understanding, followed by the write and the report above. Once reported, name the exact artifacts for the next step:

```
Handoff to plan-guide:
- Glossary: docs/glossary.md
- ADRs: docs/decisions/0007-cache-invalidation-strategy.md
```

Tell the user that `plan-guide` (`<plugin-root>/skills/plan-guide/SKILL.md`) should feed these paths into its Current Context and Related Topics, and skip re-deriving the terms and decisions already pinned here. `<plugin-root>` is `../..` from this skill's base directory resolved to an absolute path. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it.

When a crawl's grill check loaded the grill, the crawl takes the hand off and `plan-guide` does not. The grill wrote nothing, so it names no path. Print the answers, the agreed glossary terms and the decisions under the line `Agreed in the grill check:`, or say in one line that nothing was agreed, then return to the crawl's section 3 run options in the same turn.

When a planning flow loaded the grill, that flow takes the hand off. Print the answers, the agreed glossary terms and the decisions under the line `Agreed in the grill:`, or the one line that nothing needed an answer, then return in the same turn to the step that loaded it, which is `plan-flow` section 4 or `plan-guide` Planning Workflow step 5.

For a grill the user asked for, stop here. Grill does not continue into planning, does not loop back into another round of questions, and does not start drafting a plan in the same turn.

## Boundary

Grill does not write plan notes. A loaded grill returns to the flow that loaded it, and that flow drafts the plan. Grill does not duplicate `plan-guide`'s Open Questions section, it produces a different artifact (a glossary and ADRs, not a plan). Grill does not invoke `plan-critic`. Those stay `plan-guide`'s job, started fresh by the user or conductor after grill hands off.
