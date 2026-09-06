#!/bin/bash
set -euo pipefail
# Vault file ops (rm|mv) with containment guardrails.
# - Inputs are vault-relative only; absolute paths and any `..` are refused lexically.
# - Every effective source/destination is then canonically resolved (symlinks and
#   all) and must remain inside the canonical vault root — a symlinked directory
#   pointing outside the vault is refused even though the input path looks relative.
# - mv REPLACES an existing destination file by design: write to a `.tmp.md` file
#   beside the destination then mv is the toolkit's atomic-write mechanism.
# - Regular files only. No directory ops, no locking, no content validation.
# Vault root resolves from the user's obsidian-sync.json (see obsidian-sync.json.template)
CFG="$HOME/.claude/obsidian-sync.json"
ROOT="$(python3 - "$CFG" <<'PY' 2>/dev/null || true
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
    p = os.path.join(d["vault_path"].rstrip("/"), d["root_folder"])
except Exception:
    sys.exit(1)
rp = os.path.realpath(p)
if not os.path.isdir(rp):
    sys.exit(1)
print(rp)
PY
)"
[ -n "$ROOT" ] || { echo "vault-fs: cannot resolve vault root from $CFG" >&2; exit 1; }

# Single source for the hint every path refusal appends (not the unknown-command one).
HINT="(vault root: $ROOT, expected form: Projects/<repo>/...)"

cmd="${1:?usage: vault-fs.sh rm|mv <relpath> [dst]}"

# Cheap lexical guard first; canonical containment (canon) below catches what
# this cannot: escape through a symlinked directory inside the vault.
resolve() {
  case "$1" in
    /*|*..*) echo "refused: relative vault paths only $HINT" >&2; exit 1 ;;
  esac
  printf '%s/%s' "$ROOT" "$1"
}

# canon <abs-path> <file|dest>: validates canonical containment and file-kind.
# Prints a "refused: ..." reason (with the shared HINT appended) to stderr and
# fails when the path (or, for a not-yet-existing destination, its existing
# parent) resolves outside the vault root, or is not a regular file. Paths are
# passed as arguments, never interpolated into the Python source.
canon() {
  python3 - "$ROOT" "$1" "$2" "$HINT" <<'PY'
import os, sys
root, cand, mode, hint = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def refuse(msg):
    sys.stderr.write("refused: %s %s\n" % (msg, hint))
    sys.exit(1)

def contained(p):
    # Path-aware comparison: /vault-other is NOT inside /vault.
    try:
        return os.path.commonpath([root, p]) == root
    except ValueError:
        return False

if mode == "file":
    if not os.path.lexists(cand):
        refuse("missing source: %s" % cand)
    real = os.path.realpath(cand)
    if os.path.isdir(real):
        refuse("directory operations are not allowed: %s" % cand)
    if not os.path.isfile(real):
        refuse("not a regular file: %s" % cand)
    if not contained(real):
        refuse("path resolves outside the vault: %s" % cand)
else:  # dest — may not exist yet
    if os.path.lexists(cand):
        real = os.path.realpath(cand)
        if not os.path.exists(real):
            refuse("dangling symlink destination: %s" % cand)
        if os.path.isdir(real):
            refuse("directory destination is not allowed: %s" % cand)
        if not os.path.isfile(real):
            refuse("destination is not a regular file: %s" % cand)
        if not contained(real):
            refuse("path resolves outside the vault: %s" % cand)
    else:
        parent = os.path.realpath(os.path.dirname(cand))
        if not os.path.isdir(parent):
            refuse("destination directory does not exist: %s" % cand)
        if not contained(os.path.join(parent, os.path.basename(cand))):
            refuse("path resolves outside the vault: %s" % cand)
PY
}

case "$cmd" in
  rm)
    t="$(resolve "${2:?path required}")"
    canon "$t" file
    rm "$t"; echo "removed: $t" ;;
  mv)
    s="$(resolve "${2:?src required}")"; d="$(resolve "${3:?dst required}")"
    canon "$s" file
    canon "$d" dest
    mv "$s" "$d"; echo "moved: $s -> $d" ;;
  *) echo "refused: unknown command: $cmd" >&2; exit 1 ;;
esac
