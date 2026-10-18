---
title: Workflow script authoring
summary: Constraints on writing and testing the toolkit's Workflow scripts, and the verify.sh conventions a new script or check must follow.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-10-18
source_refs:
  - plugins/toolkit/workflows/
  - plugins/toolkit/workflows/tests/plan-builder/
  - verify.sh
  - plugins/toolkit/hooks/tests/fixtures/session-start/
---
<!-- managed-by: toolkit -->

# Workflow script authoring

The scripts under `plugins/toolkit/workflows/` run through the Workflow tool. What each script does and returns is in [workflows.md](../workflows.md). This page covers how a script must be written so that it parses and tests cleanly, and the `verify.sh` conventions a new script or check must follow.

## Naming a script

- A skill and a workflow script cannot share a name, because both register in the same `toolkit:` namespace and the workflow shadows the skill. The `plan-flow` skill therefore launches the `plan-builder` script.

## Parsing a script

- `node --check` exits 0 on a workflow script that has syntax errors. A file that starts with `export const meta` parses as a module and reports nothing, and the script bodies use top-level `await` and `return`, which no plain parse mode accepts.
- The real check strips `export ` from `export const meta` and compiles the body with the AsyncFunction constructor, `Object.getPrototypeOf(async function () {}).constructor`. `verify.sh` does this in its `WF_PARSE` one-liner for every `workflows/*.js` file.

## Writing prompts

- A prompt is a template literal, so text inside it cannot contain an unescaped backtick. An unescaped backtick ends the string. Shared prompt text such as `RULES` in `plan-builder.js` leaves out code-style markup for that reason.
- If a prompt key names two things, the prompt must name each one separately. In `plan-builder.js`, `relatedTopics` is both a plan section and a top-level list. `RULES` says the section holds one wiki link per line and the list holds plain names. A rule that says only "relatedTopics are a few plain names" leads the planner to return the section as a comma list.

## Runtime behavior a script relies on

- `pipeline()` returns one entry per input item, in input order. A stage that throws turns that item's entry into `null` and keeps its position. `plan-builder.js` relies on `findings[i]` matching `areas[i]`.
- `plan-builder.js` sets `critiqueStale` by comparing the rendered plan text with the text the last returned Invert critique saw, not by object identity. A cold revise that returns identical text therefore leaves `critiqueStale` false.
- `plan-builder.js` checks that case separately. If the cold revise returns text identical to the draft, the script counts it as unapplied, keeps the cold material objections open, and adds a `blocked` reason.
- The exhausted-rounds check in `plan-builder.js` must ignore `revise:cold` when it reads the dead-revise list, because the cold revise is not an Invert round.

## Gating on a script result

- A gate that reads one signal while the script produces several approves results it must reject. A gate on `approveIf.meets` alone can approve a plan that has a `stop` verdict, exhausted rounds, a dead critic, or a stale critique.
- A script whose result feeds an approval gate returns an explicit `blocked` list with one sentence per reason, and the gate requires that list to be empty. The `plan-flow` skill reads `blocked` this way.

## Testing a script

- `workflows/tests/plan-builder/harness.mjs` compiles the script with the same AsyncFunction method and passes in stub `args`, `agent`, `pipeline`, `phase`, and `log`.
- The stub `agent` returns the scripted result for the call's `label`, or `null`, so a case kills a stage by leaving its label out. The stub `pipeline` follows the runtime rule above: a stage that throws leaves `null` in that item's position.

## verify.sh conventions

- The run passes only when `pass + skip` reaches the floor on the last line of `verify.sh`. A check gated on `node` must emit exactly one `skip` for each `ok` it replaces, or a run without `node` falls below the floor.
- `verify.sh` runs the hook fixture suite as one check, so a fixture failure costs one pass, not one per fixture.
- The agent and skill counts are hardcoded in two places: the Structure checks in `verify.sh` and the expected welcome line in `hooks/tests/fixtures/session-start/06-startup-welcome.json`. [agents.md](../agents.md) states the agent count too. Adding or removing an agent or a skill means updating all of them.
- A check that two files carry the same sentence must extract the sentence from both files and compare them, not hardcode it. The git-permission check greps `Do I have permission[^?]*?` from `skills/plan-flow/SKILL.md` and `doctrine/git-safety.md` and requires the two matches to be equal and non-empty.
- Every doctrine index line in `plugins/toolkit/CLAUDE.md` opens with a bold file name followed by an em dash. Any edit to such a line puts that existing em dash on an added line of the diff. A check for "no em dash on added lines" must compare each added line with the line it replaced.

## Related docs

- [workflows.md](../workflows.md) for what `review-mr.js` and `plan-builder.js` take and return.
- [VERIFY.md](../../VERIFY.md) for running `verify.sh` and the suites.
- [context-plan-note-section-checks.md](context-plan-note-section-checks.md) for how the validator and hooks read plan note sections.
