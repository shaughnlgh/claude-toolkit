---
name: pre-compact
description: >-
  Use when the user asks whether it is okay or safe to compact, asks to prepare for a
  compaction, or says pre-compact. Checks that the session's state is recorded,
  finishes what is not, writes a temporary compact handoff into the session
  scratchpad, and answers yes or lists what it did first. Writes no vault note of
  its own; it updates the active plan or work note's session entry and writes notes
  the conversation promised. A handoff or continuation note for a second person or a later session is the
  handoff skill, and this skill never fires on the handoff skill's requests. Never
  compacts the session itself.
---

# Pre-compact

Compaction replaces the conversation with a model-written summary, and that summary often drops the standing rules and the state of the work. After every compaction the session-start hook injects the compact handoff this skill writes, followed by the standing rules. The handoff lives in the session scratchpad and dies with the session. The vault plan or work note stays the durable record.

## Trigger

Fire when the user asks "is it okay to compact", "is it safe to compact", "prepare for a compaction", or says "pre-compact". Do not fire on a request to hand off the session or to write a handoff or continuation note. That request goes to the `handoff` skill. Never run `/compact` or any other compaction yourself. The user compacts.

## Checks

Run every check before writing the handoff. If a check fails, do the missing work first, then run the check again.

1. If an active plan or work note exists, it has a session entry for this session id, and the entry's summary matches the real state of the work. The session id is the UUID directory segment of the scratchpad path. Load `plan-guide` before editing a plan note. If the summary begins with a flow name (`execute-flow`, `ship-flow`, or `plan-flow`), leave it exactly as it is, because the flows resume by those summaries, and put the real state in the handoff only.
2. Every vault note or handoff promised in this conversation is written.
3. Every uncommitted change in the repo is named under `open:` in the handoff as uncommitted, with its paths. This skill never commits. Committing belongs to the ship flow or the human.
4. Every running background task, agent, or shell is named under `open:` in the handoff.

A repo file edit goes to a worker agent, per the orchestration doctrine (`../../doctrine/orchestration.md` from this skill's base directory). The conductor writes vault notes itself, atomically, through `vault-fs.sh mv`.

## Handoff

Write `<scratchpad>/compact-handoff.md`, overwriting any earlier file. The handoff holds state only, with no rules and no prose, and stays under 3,000 bytes. Use this shape:

```
# Compact handoff
repo: <name> (<root>)
branch: <branch>
plan note: <vault path, or none>
git ceiling: <none | mr | merge> for plan <slug, or <unset> when the plan line is missing, blank, or unsafe>, read from the ceiling and plan lines of <scratchpad>/flow-run-options, or unasked
last skill: <toolkit skill the session was inside, or none>
done: <one line>
next: <one line>
open:
- <one bullet per item>
```

Write `git ceiling: unasked` when `<scratchpad>/flow-run-options` does not exist. Write the last skill with its plugin prefix, for example `toolkit:execute-flow`. The `open:` list names every item that checks 3 and 4 require. If the list would push the handoff past its 3,000-byte cap, group the uncommitted paths by directory.

The hook appends the standing rules after the handoff itself: the conductor delegates every project file edit, git mutation runs only under the recorded ceiling, and a flow's SKILL.md is re-read before the flow continues. The handoff never restates them. The hook injects the handoff once and renames it to `compact-handoff.used.md`, so a later compaction needs a fresh run of this skill.

## Answer

If every check passed on the first run, answer "Yes, compact." Otherwise list what you did to make every check pass, one line each, then answer "Yes, compact." Never answer yes before `<scratchpad>/compact-handoff.md` is written.

## Boundary

- Writes only `<scratchpad>/compact-handoff.md`, plus whatever the checks require.
- Writes no vault file of its own. A handoff note in the vault is the `handoff` skill.
- Never compacts the session, and never tells the user the session is safe to compact before the handoff exists.
