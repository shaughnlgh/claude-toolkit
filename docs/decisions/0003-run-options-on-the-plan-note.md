---
title: Run options on the plan note
summary: The flows read their run options, the git ceiling first, from eight optional frontmatter keys on the plan note, asked once and cached per session for that plan.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-05
---

# 0003. Run options on the plan note

Date: 2026-11-05

Status: Accepted

Amended by [0007](0007-ticket-question-and-creation-on-yes.md), which replaces the sentence that a flow asks at most two AskUserQuestion calls carrying up to five questions in all.

## Context

Each flow asked a git-permission question at the start of a session and recorded the answer in a scratchpad file, the ship flow asked a second question for the stage to stop at, and the testing gate asked its own question. Nothing on the plan note recorded any answer, so a plan executed across two sessions, or by a second person, was asked again, and an unattended run had no record to read. The toolkit is moving to one run from a brief to a merged MR with human input only between planning and execution, which needs every option a flow acts on to live where the flows, Mission Control, and the user can all read and edit it.

## Decision

The run options live on the plan note as flat, unprefixed frontmatter keys: `ceiling`, `worker_model`, `verifier_model`, `verifier_effort`, `nits`, `tests`, `e2e`, and `tag_merge`. `ceiling` takes `none`, `mr`, or `merge`, the ship ladder's own stage names, so the ceiling is the stage the ship run stops at and the ship flow's separate stop question retires. Stopping at commit or push is no longer offered. `nits` takes `fix` or `skip`, `tests` takes `required` or `manual`, `e2e` takes `required` or `skip`, and `tag_merge` takes `true` or `false`. `worker_model` governs the implementer role, and `verifier_model` with `verifier_effort` govern the verifier role. A model key is blank, a Claude Code alias, or a full model id with an optional `[1m]` suffix, and the effort key is blank or one of `low`, `medium`, `high`, `xhigh`, `max`, `inherit`. Blank means the models file decides. `haiku` is a validator violation on any role. The word `release` leaves the user-facing side with no compatibility code, because no plan note ever carried it. The ship runner keeps `release` as the internal name of its tag stage, switched on by `tag_merge: true` under `ceiling: merge`. The keys are optional on every note and stay out of the required frontmatter, so skeletons, older notes, and Mission Control scaffolds still validate. The validator reads a blank key as absent and checks a value only when one is present. A flow reads the keys one by one and asks only for the enum keys the note lacks. The plan-guide skill defines the keys, the question set, the reading rule, and the session cache `<scratchpad>/flow-run-options` in one section that every flow references. The cache opens with the slug of the plan it serves, and a flow reads it only for that plan. This decision records the keys and their validation. Giving the model and effort keys effect in the runners is a separate change.

## Consequences

A flow asks at most two AskUserQuestion calls, carrying up to five questions in all, once per plan, and a later session or another person reads the note instead of being asked. The user changes an option by editing the note. Mission Control needs no change, because its parser reads the frontmatter as YAML and its scalar editor matches a key by name. The ship flow loses the option to stop at commit or push, which a user who wants a commit and no MR gets from `ceiling: none` and the paste-ready commit block. A session cache that disagrees with the note loses, because the note is read first, and a cache for another plan is never read. The validator rejects a note that carries a misspelt value, so a hand edit is caught at the next flow's validation gate. One section in plan-guide replaces three copies of a question, and three verify.sh checks replace five drift checks.
