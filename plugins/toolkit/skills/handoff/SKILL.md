---
name: handoff
description: >-
  Use only when the user explicitly asks to hand off the session, or to write a
  handoff or continuation note, so a second person or a later session can pick the
  work up cold. Writes a single continuation note into the Obsidian vault: into the
  active plan's directory if one exists, otherwise into a vault-root _handoffs/
  bucket. Never fires automatically at session end or because a task looks unfinished.
  Only an explicit handoff/continuation-note request should trigger this.
---

# Handoff

This skill writes a session continuation note into the Obsidian vault: a compressed,
plain-language snapshot of the current work so someone else, or a later session, can
pick it up cold without re-reading the whole transcript. It is not automatic. It fires
only when the user explicitly asks to hand off, or to write a handoff or continuation
note.

It does not duplicate `plan-workflow`'s frontmatter session history (the
`sessions:` list on the plan note). That stays, and this complements it: the
`sessions:` entry is a one-line record that a session happened, this note is the
fuller narrative of what to do next. Handoff does not mark a plan complete or change
its `status`. Handoff never writes to the project repo. See Boundary below.

## Trigger and scope

Fire only on an explicit request (e.g. "write a handoff note", "hand this off",
"write a continuation note for whoever picks this up next"). Do not self-fire at the
end of a session, when context is running low, or because the task looks incomplete.
If unsure whether the user is asking for this, ask rather than assume.

## Placement rules

Decide placement before writing. Check whether an active plan note exists for the
current work in the vault (per `plan-workflow`'s canonical layout).

1. **Active plan exists.** Write the note as `handoff - <plan-name>.md` into that
   plan's directory (the same directory as `plan - <plan-name>.md`). Then edit the
   plan note's Linked Artifacts section to add a link to the new note
   (`[[handoff - <plan-name>]]`). Read the plan note first (recall-before-write)
   before editing it.
2. **No active plan.** Write into a `_handoffs/` bucket at the vault root, resolved
   from `~/.claude/obsidian-sync.json` as `vault_path` + `root_folder`
   (`<vault_path>/<root_folder>/_handoffs/`). Filename:
   `handoff - <short-kebab-topic>-<YYYY-MM-DD>.md`. The topic is a short kebab-case
   description of the work, derived the same way `plan-workflow` derives plan names.

If it is ambiguous whether an active plan exists (more than one candidate, or the
plan directory cannot be found), ask the user rather than guessing.

## Writing mechanics

Use atomic writes, the same as `plan-workflow`: write the note to a `.tmp` file
first, then move it into place with the toolkit's `scripts/vault-fs.sh mv`. The
vault path contains spaces and lives in iCloud Drive, so writing directly (instead of
write-then-move) risks a partial file if iCloud syncs mid-write. Never write directly
to the final path in the vault.

## Content of the note

Keep a light frontmatter block, consistent with other vault notes:

```yaml
---
type: handoff
date:
session:
repo:
plan:
---
```

- `date`: the local date (YYYY-MM-DD) the note is written.
- `session`: the current session id — the UUID directory segment of this session's
  scratchpad path (shown in your system prompt). Always present in a live session;
  never leave blank or invent a value.
- `repo`: the repo the work belongs to.
- `plan`: the plan name, if an active plan exists (case 1 above). Leave blank in the
  `_handoffs/` case.

Body, in plain sentences, covering:

- What the work is (one or two sentences of framing, not the whole plan restated).
- What was decided (key choices made this session and why, briefly).
- What is done (concretely, so it is not redone).
- What remains (concretely, so nothing is missed).
- Where the code lives: repo, branch, and the key files and paths touched.
- Open questions (anything unresolved that the next person needs to decide or ask
  about).
- The single next concrete step. One step, not a list, so the next person knows
  exactly where to start.

Writing style for the note: plain sentences. Never use em dashes or semicolons to
split text. Use separate sentences, commas, or parentheses instead. This matches the
vault's writing rules for plan and topic notes.

## Boundary

Handoff complements `plan-workflow`'s session closure, it does not replace it. It
does not fire in place of recording a `sessions:` entry on the plan note, that
still happens per `plan-workflow`'s Session Closure rules. Handoff writes only to
the vault, never to the project repo. Handoff never changes a plan note's `status`
and never marks a plan complete, it only adds a link from the plan's Linked
Artifacts section when case 1 applies.
