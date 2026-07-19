#!/bin/bash
# Copy a plugin doctrine file into ~/.claude/doctrine/ so it overrides the plugin's copy
# for that concern. The session-start hook detects the override and announces it.
# Usage: doctrine-override.sh [<name>]   (no name lists the doctrine files available)
DOCDIR="$(cd "$(dirname "$0")/../doctrine" 2>/dev/null && pwd)"
[ -d "$DOCDIR" ] || { echo "refused: cannot find the plugin doctrine directory" >&2; exit 1; }
avail() { ls "$DOCDIR"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//'; }

name="${1:-}"
if [ -z "$name" ]; then
  echo "doctrine available to override (run: doctrine-override.sh <name>):"
  avail | sed 's/^/  /'
  exit 0
fi

name="${name%.md}"                       # tolerate 'conventions.md'
case "$name" in */*|*..*) echo "refused: name only, not a path" >&2; exit 1 ;; esac
src="$DOCDIR/${name}.md"
[ -f "$src" ] || { echo "refused: no plugin doctrine named '${name}'. Available:" >&2; avail | sed 's/^/  /' >&2; exit 1; }

dst="$HOME/.claude/doctrine/${name}.md"
[ -e "$dst" ] && { echo "refused: an override already exists at $dst (edit it directly)" >&2; exit 1; }
mkdir -p "$HOME/.claude/doctrine"
cp "$src" "$dst"
echo "created override: $dst"
echo "edit it to change the '${name}' concern. The session-start hook announces it next session and your copy wins. Safety sections may be tightened, not loosened."
