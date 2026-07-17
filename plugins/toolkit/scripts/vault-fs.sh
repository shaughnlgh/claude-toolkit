#!/bin/bash
set -euo pipefail
# Vault root resolves from the user's obsidian-sync.json (see obsidian-sync.json.template)
CFG="$HOME/.claude/obsidian-sync.json"
ROOT="$(python3 -c "import json;d=json.load(open('$CFG'));print(d['vault_path'].rstrip('/')+'/'+d['root_folder'])" 2>/dev/null || true)"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "vault-fs: cannot resolve vault root from $CFG" >&2; exit 1; }
cmd="${1:?usage: vault-fs.sh rm|mv <relpath> [dst]}"
resolve() {
  case "$1" in
    /*|*..*) echo "refused: relative vault paths only" >&2; exit 1 ;;
  esac
  printf '%s/%s' "$ROOT" "$1"
}
case "$cmd" in
  rm)
    t="$(resolve "${2:?path required}")"
    [ -f "$t" ] || { echo "refused: not a regular file: $t" >&2; exit 1; }
    rm "$t"; echo "removed: $t" ;;
  mv)
    s="$(resolve "${2:?src required}")"; d="$(resolve "${3:?dst required}")"
    [ -e "$s" ] || { echo "refused: missing src: $s" >&2; exit 1; }
    mv "$s" "$d"; echo "moved: $s -> $d" ;;
  *) echo "refused: unknown command: $cmd" >&2; exit 1 ;;
esac
