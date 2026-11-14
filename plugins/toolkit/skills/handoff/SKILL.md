---
name: handoff
description: >-
  Use only when the user explicitly asks to hand off the session, or to write a
  handoff or continuation note, so a second person or a later session can pick the
  work up cold. Writes a single continuation note into the vault: into the
  active plan's directory if one exists, otherwise into a vault-root _handoffs/
  bucket. Never fires automatically at session end or because a task looks unfinished.
  Only an explicit handoff/continuation-note request should trigger this.
---

# Handoff

This skill writes a session continuation note into the vault: a compressed, plain-language snapshot of the current work so someone else, or a later session, can pick it up cold without re-reading the whole transcript. It is not automatic. It fires only when the user explicitly asks to hand off, or to write a handoff or continuation note.

It does not duplicate `plan-guide`'s frontmatter session history (the `sessions:` list on the plan note). That stays, and this complements it: the `sessions:` entry is a one-line record that a session happened, this note is the fuller narrative of what to do next. Handoff does not mark a plan complete or change its `status`. Handoff never writes to the project repo. See Boundary below.

## Trigger and scope

Fire only on an explicit request (e.g. "write a handoff note", "hand this off", "write a continuation note for whoever picks this up next"). Do not self-fire at the end of a session, when context is running low, or because the task looks incomplete. If unsure whether the user is asking for this, ask rather than assume.

## Placement rules

Decide placement before writing. Check whether an active plan note exists for the current work in the vault (per `plan-guide`'s canonical layout).

1. **Active plan exists.** Write the note as `handoff - <plan-name>.md` into that plan's directory (the same directory as `plan - <plan-name>.md`). Then edit the plan note's Linked Artifacts section to add a link to the new note (`[[handoff - <plan-name>]]`). Read the plan note first (recall-before-write) before editing it.
2. **No active plan.** Write into a `_handoffs/` bucket at the vault root, resolved from the vault config, `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent, as `vault_path` + `root_folder` (`<vault_path>/<root_folder>/_handoffs/`). Filename: `handoff - <short-kebab-topic>-<YYYY-MM-DD>.md`. The topic is a short kebab-case description of the work, derived the same way `plan-guide` derives plan names.

If it is ambiguous whether an active plan exists (more than one candidate, or the plan directory cannot be found), ask the user rather than guessing.

## Writing mechanics

Use atomic writes, the same as `plan-guide`: write the note to a `.tmp.md` file beside the destination first, then move it into place with `bash <plugin-root>/scripts/vault-fs.sh mv`, where `<plugin-root>` is `../..` from this skill's base directory resolved to an absolute path. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. The vault path contains spaces and lives in iCloud Drive, so writing directly (instead of write-then-move) risks a partial file if iCloud syncs mid-write. Never write directly to the final path in the vault. The Linked Artifacts edit of the plan note takes `plan-guide`'s changed-lines path: `vault-fs.sh cp` to the plan note's `.tmp.md` copy, an Edit on the copy, then `vault-fs.sh mv`.

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
- `session`: the current session id — the UUID directory segment of this session's scratchpad path (shown in your system prompt). Always present in a live session; never leave blank or invent a value.
- `repo`: the repo the work belongs to.
- `plan`: the plan name, if an active plan exists (case 1 above). Leave blank in the `_handoffs/` case.

Body, in plain sentences, covering:

- What the work is (one or two sentences of framing, not the whole plan restated).
- What was decided (key choices made this session and why, briefly).
- What is done (concretely, so it is not redone).
- What remains (concretely, so nothing is missed).
- Where the code lives: repo, branch, and the key files and paths touched.
- Open questions (anything unresolved that the next person needs to decide or ask about).
- The single next concrete step. One step, not a list, so the next person knows exactly where to start.
- Promote what outlives the plan. Name each finding a future contributor would need without this note: a behavior, a gotcha, a decision. The code MR carries each finding into the repo doc that `doctrine/repo-artifacts.md` names for its kind, or into the module's README, behind that file's consent gate. Handoff never writes that doc itself (see Boundary), so record each finding's target path here and whether the MR has written it yet. Once the doc exists, link its path from the plan's Linked Artifacts. If no active plan exists, list the path in this note instead. If nothing outlives the plan, write "Nothing to promote" so the omission is deliberate. If the project treats the repo as legacy, never promote into it. Leave that knowledge in the vault topic note.

Writing style for the note: plain sentences. Never use em dashes or semicolons to split text. Use separate sentences or commas instead. This matches the vault's writing rules for plan and topic notes.

## Boundary

Handoff complements `plan-guide`'s session closure, it does not replace it. It does not fire in place of recording a `sessions:` entry on the plan note, that still happens per `plan-guide`'s Session Closure rules. Handoff writes only to the vault, never to the project repo. Handoff never changes a plan note's `status` and never marks a plan complete, it only adds links to the plan's Linked Artifacts section when case 1 applies.
