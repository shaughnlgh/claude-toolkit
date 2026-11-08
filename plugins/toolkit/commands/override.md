---
description: Copy a toolkit doctrine, rule, agent, or skill into your global ~/.claude so your version overrides the plugin's
argument-hint: [type] [name]
---

# Override

Copy a toolkit component into your global `~/.claude/` so your copy overrides the plugin's for that concern, without editing the plugin. Works for doctrine, rules, agents, and skills.

## Usage

$ARGUMENTS

- No argument: list everything overridable, grouped by type, and ask which.
- A name (e.g. `conventions`, `testing`, `code-reviewer`, `grill`): auto-detect the type and copy it.
- A type and name (e.g. `rules security`): force the type when a name is ambiguous (`security` is both a doctrine and a rule).

## What to do

Run the override script from the plugin root:

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    bash "$PLUGIN_ROOT/scripts/override.sh" [type] [name]

- **No name:** run it with no argument, show the grouped list, ask which one, then run again with the choice.
- **Ambiguous name:** it refuses and names the types — re-run as `<type> <name>`.
- It refuses unknown names and never clobbers an existing override.
- On success, report the created path and how that type takes effect:
  - **doctrine / rules** — the session-start hook picks up your copy from the next session (doctrine is announced as an override; a rule's body is injected in place of the plugin's).
  - **agents / skills** — Claude Code resolves your copy for the bare name; invoke it bare, not `toolkit:<name>`.
- Safety sections (git-safety, security) may be tightened, not loosened.
- Offer to open the new file for editing.
