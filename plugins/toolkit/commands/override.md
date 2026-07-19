# Override

Copy a toolkit doctrine file into your global `~/.claude/doctrine/` so your version wins
for that concern (your own code style, for example) without editing the plugin.

## Usage

$ARGUMENTS

The argument is the doctrine name to override (e.g. `conventions`). With no argument,
list the doctrine files available to override and ask which one.

## What to do

Resolve the installed plugin root, then run the override script:

    PLUGIN_ROOT="$(jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json)"
    bash "$PLUGIN_ROOT/scripts/doctrine-override.sh" <name>

- **No name given:** run it with no argument. It prints the doctrine files available to
  override. Show that list and ask which one they want, then run it again with their
  choice.
- **Name given:** run it with that name.
- If it refuses (unknown name, or an override already exists), report exactly why and
  stop. Never overwrite an existing override.
- On success, tell the user the file was created at `~/.claude/doctrine/<name>.md`, that
  they edit it to change what they want, and that the session-start hook will announce it
  (their copy wins) from the next session. Safety sections (git-safety, security) may be
  tightened, not loosened.
- Offer to open the new file for editing.
