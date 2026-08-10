#!/bin/bash
# Copy a toolkit component into ~/.claude/ so your copy overrides the plugin's for that
# concern. doctrine, rules, and agents are single .md files; a skill is a directory.
# Usage:
#   override.sh                  list everything overridable
#   override.sh <name>           auto-detect the type and copy (refuses if ambiguous)
#   override.sh <type> <name>    force the type (doctrine | rules | agents | skills)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"    # plugin root: plugins/toolkit
HOMEC="$HOME/.claude"
TYPES="doctrine rules agents skills"

names_of() {  # $1 = type
  case "$1" in
    skills) ls -d "$ROOT/skills"/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null ;;
    *)      ls "$ROOT/$1"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//' ;;
  esac
}
has() {  # $1=type $2=name -> 0 if it exists in the plugin
  case "$1" in
    skills) [ -d "$ROOT/skills/$2" ] ;;
    *)      [ -f "$ROOT/$1/$2.md" ] ;;
  esac
}

# No args: list everything overridable. frontend/design are excluded from the rules
# listing (and guards below refuse them) since they're reference-only, never injected.
if [ $# -eq 0 ]; then
  echo "overridable toolkit components (run: override.sh <name>  or  override.sh <type> <name>):"
  for t in $TYPES; do
    echo "  $t:"
    if [ "$t" = rules ]; then
      names_of "$t" | grep -v -x -e frontend -e design | sed 's/^/    /'
      echo "    (frontend, design: reference-only, not overridable)"
    else
      names_of "$t" | sed 's/^/    /'
    fi
  done
  exit 0
fi

# Every remaining form needs a non-empty component name (else the skills dir-check below
# would treat "" as a match and copy the whole skills/ tree).
if [ $# -ge 2 ]; then _n="$2"; else _n="$1"; fi
[ -n "${_n%.md}" ] || { echo "refused: a component name is required (run with no argument to list)" >&2; exit 1; }

# Resolve type + name.
if [ $# -ge 2 ]; then
  typ="$1"; name="${2%.md}"
  case " $TYPES " in *" $typ "*) : ;; *) echo "refused: unknown type '$typ' (use one of: $TYPES)" >&2; exit 1 ;; esac
else
  name="${1%.md}"; typ=""; n=0; all=""
  for t in $TYPES; do if has "$t" "$name"; then n=$((n+1)); typ="$t"; all="$all $t"; fi; done
  if [ "$n" -eq 0 ]; then echo "refused: no toolkit component named '$name'. Run with no argument to list." >&2; exit 1; fi
  if [ "$n" -gt 1 ]; then echo "refused: '$name' is ambiguous (${all# }). Specify: override.sh <type> $name" >&2; exit 1; fi
fi
case "$name" in */*|*..*) echo "refused: a name, not a path" >&2; exit 1 ;; esac
has "$typ" "$name" || { echo "refused: no $typ named '$name'" >&2; exit 1; }
# The frontend rule is reference-only (never injected); its content lives in the agent.
if [ "$typ" = rules ] && [ "$name" = frontend ]; then
  echo "refused: the 'frontend' rule is reference-only and is not injected. Its content lives in the frontend-designer agent — override that instead:  override.sh agents frontend-designer" >&2
  exit 1
fi
# The design rule is reference-only (never injected); it's just an index over rules/design/.
if [ "$typ" = rules ] && [ "$name" = design ]; then
  echo "refused: the 'design' rule is reference-only and is not injected. It's an index over the rules/design/ catalog, with no equivalent component to override." >&2
  exit 1
fi

# Source + destination.
if [ "$typ" = skills ]; then src="$ROOT/skills/$name"; dst="$HOMEC/skills/$name"
else src="$ROOT/$typ/$name.md"; dst="$HOMEC/$typ/$name.md"; fi
[ -e "$dst" ] && { echo "refused: an override already exists at $dst (edit it directly)" >&2; exit 1; }
mkdir -p "$(dirname "$dst")"
if [ "$typ" = skills ]; then cp -R "$src" "$dst"; else cp "$src" "$dst"; fi

echo "created override ($typ): $dst"
case "$typ" in
  doctrine) echo "edit it; the session-start hook announces it and your copy wins for the '$name' concern." ;;
  rules)    echo "edit it (keep its frontmatter); the session-start hook injects your version instead of the plugin's '$name' rule." ;;
  agents|skills) echo "edit it; Claude Code resolves your '$name' over the plugin's for the bare name (invoke bare, not toolkit:$name)." ;;
esac
echo "Safety concerns may be tightened, not loosened."
