#!/bin/bash
set -euo pipefail
# Vault file ops (rm|mv|cp), image attachments from a git checkout (attach), reads (sha256|index) with containment guardrails, and the topic index write (topic-index).
# - Vault inputs are vault-relative only; absolute paths and any `..` are refused lexically.
# - Every effective source/destination is then canonically resolved (symlinks and
#   all) and must remain inside the canonical vault root — a symlinked directory
#   pointing outside the vault is refused even though the input path looks relative.
# - mv REPLACES an existing destination file by design: write to a `.tmp.md` file
#   beside the destination then mv is the toolkit's atomic-write mechanism.
# - cp replaces an existing destination like mv. attach copies one PNG or JPEG of at most 10 MiB from inside a git checkout and never replaces a destination.
# - Regular files only. No directory ops, no locking, no content validation.
# Vault root resolves from the user's vault config (see toolkit-vault.json.template)
. "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/vault-config.sh"
CFG=$(vault_config_file) || { echo "vault-fs: no vault config, expected ~/.claude/toolkit-vault.json" >&2; exit 1; }
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

cmd="${1:?usage: vault-fs.sh rm|mv|cp|sha256|index <relpath> [dst], attach <checkout> <src-relpath> <dst-relpath>, or topic-index}"

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
  sha256)
    t="$(resolve "${2:?path required}")"
    canon "$t" file
    python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$t" ;;
  index)
    t="$(resolve "${2:?path required}")"
    canon "$t" file
    python3 "$(dirname "${BASH_SOURCE[0]}")/plan-index.py" "$t" ;;
  topic-index)
    python3 "$(dirname "${BASH_SOURCE[0]}")/vault-index.py" "$ROOT" ;;
  cp)
    s="$(resolve "${2:?src required}")"; d="$(resolve "${3:?dst required}")"
    canon "$s" file
    canon "$d" dest
    cp "$s" "$d"; echo "copied: $s -> $d" ;;
  attach)
    d="$(resolve "${4:?dst required}")"
    if [ -e "$d" ] || [ -L "$d" ]; then echo "refused: attachment destination exists: $4 $HINT" >&2; exit 1; fi
    canon "$d" dest
    s="$(python3 - "${2:?checkout required}" "${3:?src required}" "$d" <<'PY'
import os, sys
root_in, rel, dst = sys.argv[1], sys.argv[2], sys.argv[3]
def refuse(msg):
    sys.stderr.write("refused: %s (checkout: %s)\n" % (msg, root_in))
    sys.exit(1)
root = os.path.realpath(root_in)
if not os.path.exists(os.path.join(root, ".git")):
    refuse("not a git checkout root")
# A dotfiles repo at the home directory would let the allow rule copy any image under it.
if os.path.commonpath([root, os.path.realpath(os.path.expanduser("~"))]) == root:
    refuse("the checkout holds the home directory")
if rel.startswith("/") or ".." in rel:
    refuse("source must be relative to the checkout, no '..': %s" % rel)
real = os.path.realpath(os.path.join(root, rel))
if os.path.commonpath([root, real]) != root:
    refuse("source resolves outside the checkout: %s" % rel)
if not os.path.isfile(real):
    refuse("source is not a regular file: %s" % rel)
if os.path.getsize(real) > 10 * 1024 * 1024:
    refuse("source is over 10 MiB: %s" % rel)
head = open(real, "rb").read(8)
kind = "png" if head == b"\x89PNG\r\n\x1a\n" else "jpeg" if head[:3] == b"\xff\xd8\xff" else ""
if not kind:
    refuse("source is not a PNG or JPEG image: %s" % rel)
if os.path.splitext(dst)[1].lower() not in ((".png",) if kind == "png" else (".jpg", ".jpeg")):
    refuse("destination extension does not match the %s source" % kind)
print(real)
PY
)"
    cp "$s" "$d"; echo "attached: $s -> $d" ;;
  *) echo "refused: unknown command: $cmd" >&2; exit 1 ;;
esac
