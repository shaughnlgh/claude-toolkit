#!/usr/bin/env bash
# Behavior tests for vault-fs.sh containment. Fully isolated: temporary HOME and
# temporary vault built per run — the real vault and live config are never read
# or written. Asserts behavior (exit codes, filesystem effects, messages), not
# implementation details.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VFS="$HERE/../../vault-fs.sh"
PASS=0; FAIL=0

ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s (%s)\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Scratch world: BASE/home (HOME), BASE/vault/AI (vault root), BASE/outside,
# BASE/vault/AI-other (canonically similar sibling OUTSIDE the root).
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
mkdir -p "$BASE/home/.claude" "$BASE/vault/AI/Projects/demo dir" "$BASE/vault/AI-other" "$BASE/outside"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault" > "$BASE/home/.claude/obsidian-sync.json"
V="$BASE/vault/AI"

run() { HOME="$BASE/home" bash "$VFS" "$@" 2>&1; }

# 1. normal rm of a regular file inside the vault
echo x > "$V/Projects/gone.md"
out="$(run rm 'Projects/gone.md')"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$V/Projects/gone.md" ] && ok "01 rm regular file" || no "01 rm regular file" "rc=$rc $out"

# 2. .tmp -> new final path mv
echo body > "$V/Projects/note.md.tmp"
out="$(run mv 'Projects/note.md.tmp' 'Projects/note.md')"; rc=$?
[ $rc -eq 0 ] && [ -f "$V/Projects/note.md" ] && [ ! -e "$V/Projects/note.md.tmp" ] && ok "02 tmp -> new final mv" || no "02 tmp -> new final mv" "rc=$rc $out"

# 3. atomic replacement of an existing final file stays allowed
echo v2 > "$V/Projects/note.md.tmp"
out="$(run mv 'Projects/note.md.tmp' 'Projects/note.md')"; rc=$?
[ $rc -eq 0 ] && [ "$(cat "$V/Projects/note.md")" = "v2" ] && ok "03 atomic replace existing final" || no "03 atomic replace existing final" "rc=$rc $out"

# 4. absolute input refused
out="$(run rm "$V/Projects/note.md")"; rc=$?
[ $rc -ne 0 ] && case "$out" in *refused*) ok "04 absolute path refused";; *) no "04 absolute path refused" "$out";; esac || no "04 absolute path refused" "rc=0"

# 5. .. input refused
out="$(run rm '../x.md')"; rc=$?
[ $rc -ne 0 ] && case "$out" in *refused*) ok "05 dot-dot refused";; *) no "05 dot-dot refused" "$out";; esac || no "05 dot-dot refused" "rc=0"

# 6. missing source refused
out="$(run rm 'Projects/never-existed.md')"; rc=$?
[ $rc -ne 0 ] && case "$out" in *refused*) ok "06 missing source refused";; *) no "06 missing source refused" "$out";; esac || no "06 missing source refused" "rc=0"

# 7. directory source refused
out="$(run mv 'Projects/demo dir' 'Projects/other.md')"; rc=$?
[ $rc -ne 0 ] && case "$out" in *refused*) ok "07 directory source refused";; *) no "07 directory source refused" "$out";; esac || no "07 directory source refused" "rc=0"

# 8. directory destination refused
echo x > "$V/Projects/src8.md"
out="$(run mv 'Projects/src8.md' 'Projects/demo dir')"; rc=$?
[ $rc -ne 0 ] && [ -f "$V/Projects/src8.md" ] && case "$out" in *refused*) ok "08 directory destination refused";; *) no "08 directory destination refused" "$out";; esac || no "08 directory destination refused" "rc=$rc"

# 9. rm through an outside-pointing symlinked directory refused
ln -s "$BASE/outside" "$V/escape"
echo secret > "$BASE/outside/target.md"
out="$(run rm 'escape/target.md')"; rc=$?
[ $rc -ne 0 ] && [ -f "$BASE/outside/target.md" ] && case "$out" in *refused*) ok "09 rm via outside symlink refused";; *) no "09 rm via outside symlink refused" "$out";; esac || no "09 rm via outside symlink refused" "rc=$rc, file gone?"

# 10. mv source through an outside-pointing symlinked directory refused
out="$(run mv 'escape/target.md' 'Projects/stolen.md')"; rc=$?
[ $rc -ne 0 ] && [ -f "$BASE/outside/target.md" ] && case "$out" in *refused*) ok "10 mv source via outside symlink refused";; *) no "10 mv source via outside symlink refused" "$out";; esac || no "10 mv source via outside symlink refused" "rc=$rc"

# 11. mv destination through an outside-pointing symlinked directory refused
echo x > "$V/Projects/src11.md"
out="$(run mv 'Projects/src11.md' 'escape/leaked.md')"; rc=$?
[ $rc -ne 0 ] && [ -f "$V/Projects/src11.md" ] && [ ! -e "$BASE/outside/leaked.md" ] && case "$out" in *refused*) ok "11 mv dest via outside symlink refused";; *) no "11 mv dest via outside symlink refused" "$out";; esac || no "11 mv dest via outside symlink refused" "rc=$rc"

# 12. symlinked directory resolving INSIDE the vault stays allowed
mkdir -p "$V/Docs"
ln -s "$V/Docs" "$V/docs-link"
echo x > "$V/docs-link/in.md.tmp"
out="$(run mv 'docs-link/in.md.tmp' 'docs-link/in.md')"; rc=$?
[ $rc -eq 0 ] && [ -f "$V/Docs/in.md" ] && ok "12 in-vault symlink allowed" || no "12 in-vault symlink allowed" "rc=$rc $out"

# 13. paths containing spaces work
echo x > "$V/Projects/demo dir/plan - my note.md.tmp"
out="$(run mv 'Projects/demo dir/plan - my note.md.tmp' 'Projects/demo dir/plan - my note.md')"; rc=$?
[ $rc -eq 0 ] && [ -f "$V/Projects/demo dir/plan - my note.md" ] && ok "13 spaces in paths" || no "13 spaces in paths" "rc=$rc $out"

# 14. canonically similar prefix outside the vault refused (defeats string-prefix checks)
ln -s "$BASE/vault/AI-other" "$V/sneaky"
echo x > "$BASE/vault/AI-other/f.md"
out="$(run rm 'sneaky/f.md')"; rc=$?
[ $rc -ne 0 ] && [ -f "$BASE/vault/AI-other/f.md" ] && case "$out" in *refused*) ok "14 similar-prefix sibling refused";; *) no "14 similar-prefix sibling refused" "$out";; esac || no "14 similar-prefix sibling refused" "rc=$rc"

# 15. configured vault path through a legitimate symlink resolves and works
mkdir -p "$BASE/home2/.claude"
ln -s "$BASE/vault" "$BASE/vault-link"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault-link" > "$BASE/home2/.claude/obsidian-sync.json"
echo x > "$V/Projects/via-link.md"
out="$(HOME="$BASE/home2" bash "$VFS" rm 'Projects/via-link.md' 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$V/Projects/via-link.md" ] && ok "15 symlinked configured root works" || no "15 symlinked configured root works" "rc=$rc $out"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
