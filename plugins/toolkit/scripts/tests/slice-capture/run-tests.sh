#!/usr/bin/env bash
# Hermetic behavior suite for slice-capture.py. Builds throwaway repos under mktemp -d: one root
# with odd untracked names and a linked worktree, two sibling roots, and a project with module
# repos nested under an ignored and a tracked vendor/. No network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="$HERE/../../slice-capture.py"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(cd "$(mktemp -d -t slice.XXXXXX)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
printf '[user]\n\temail = t@t.invalid\n\tname = t\n[commit]\n\tgpgsign = false\n[init]\n\tdefaultBranch = trunk\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1

repo() { mkdir -p "$1"; git -C "$1" init -q; printf 'one\n' > "$1/${2:-src.txt}"; git -C "$1" add -A; git -C "$1" commit -qm c1 --no-verify; }
run() { OUT="$(python3 "$CAP" "$@" 2>"$T/err")"; RC=$?; }
# field: python expression over the parsed output d.
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$OUT" "$1" 2>/dev/null; }
n=0; scratch() { n=$((n+1)); printf '%s/scratch-%s' "$T" "$n"; }

R="$T/one"; repo "$R"
printf 'two\n' >> "$R/src.txt"
printf 'space\n' > "$R/has space.txt"
printf 'newline-body\n' > "$R/new"$'\n'"line.txt"
printf 'accent\n' > "$R/café.txt"
printf 'slash\n' > "$R/back\\slash.txt"
git -C "$R" worktree add -q -b wt "$R/.claude/worktrees/wt" >/dev/null 2>&1

mkdir -p "$T/legacy"
( cd "$R" && git diff HEAD > "$T/legacy/slice.diff.tmp" \
  && git ls-files --others --exclude-standard -z -- ':(exclude,top).claude/worktrees/' | while IFS= read -r -d '' f; do git diff --no-index -- /dev/null "$f" >> "$T/legacy/slice.diff.tmp"; done )
LEGACY_HASH="$(shasum -a 256 "$T/legacy/slice.diff.tmp" | cut -c1-12)"

run --scratch "$(scratch)" --base HEAD --root "$R"
{ [ "$RC" -eq 0 ] && [ "$(field 'd["hash12"]')" = "$LEGACY_HASH" ] && cmp -s "$(field 'd["diffPath"]')" "$T/legacy/slice.diff.tmp"; } \
  && ok "one root gives the legacy capture's bytes and hash" || no "legacy match (rc=$RC, legacy $LEGACY_HASH): $OUT $(cat "$T/err")"
SINGLE="$OUT"

[ "$(field '"has space.txt" in d["paths"]')" = "True" ] && ok "an untracked name with a space is listed as is" || no "space name: $OUT"

grep -q '^+newline-body$' "$(field 'd["diffPath"]')" && ok "an untracked name with a newline is captured" || no "newline name: $OUT"

[ "$(field '"café.txt" in d["paths"]')" = "True" ] && ok "a non-ASCII name is listed unquoted" || no "non-ASCII name: $OUT"

run --scratch "$(scratch)" --base HEAD --root "$T" --repo "$R"
[ "$(field '"\"one/back\\\\slash.txt\"" in d["paths"]')" = "True" ] && ok "a quoted name with a backslash takes the prefix after its opening quote" || no "backslash name: $OUT"

OUT="$SINGLE"
[ "$(field 'any(p.startswith(".claude/") for p in d["paths"])')" = "False" ] && ok "a linked worktree under .claude/worktrees/ is left out" || no "own worktree listed: $OUT"

P="$T/projects"; repo "$P/app"; repo "$P/web"
printf 'app-change\n' >> "$P/app/src.txt"; printf 'web-change\n' >> "$P/web/src.txt"
run --scratch "$(scratch)" --base HEAD --root "$P" --repo "$P/app" --repo "$P/web"
D="$(field 'd["diffPath"]')"
{ [ "$(field 'd["paths"]')" = "['app/src.txt', 'web/src.txt']" ] && grep -q '^diff --git a/app/src.txt b/app/src.txt$' "$D" && grep -q '^+++ b/web/src.txt$' "$D"; } \
  && ok "two sibling roots take their prefixes in paths and in the diff" || no "sibling prefixes: $OUT"
WEB_PART="$(field 'd["parts"][1]["hash12"]')"

git -C "$P/app" commit -qam c2 --no-verify
run --scratch "$(scratch)" --base HEAD --root "$P" --repo "$P/app" --repo "$P/web"
[ "$(field 'd["parts"][1]["hash12"]')" = "$WEB_PART" ] && ok "a commit in one root leaves the other root's part hash unchanged" || no "web part moved from $WEB_PART: $OUT"

[ "$(field 'd["parts"][0]["empty"]')" = "True" ] && ok "the committed root's part is empty" || no "app part not empty: $OUT"

printf 'web-new\n' > "$P/web/new.txt"
run --scratch "$(scratch)" --base HEAD --root "$P" --repo "$P/app" --repo "$P/web"
grep -q '^diff --git a/web/new.txt b/web/new.txt$' "$(field 'd["diffPath"]')" && ok "an untracked file in a sibling root takes the root prefix in its diff header" || no "untracked sibling header: $OUT"

J="$T/shop"; repo "$J" .gitignore; printf 'vendor/\n' > "$J/.gitignore"; git -C "$J" commit -qam ignore --no-verify
repo "$J/vendor/acme/mod" m.txt; printf 'mod-change\n' >> "$J/vendor/acme/mod/m.txt"
printf 'shop-new\n' > "$J/new.txt"
run --scratch "$(scratch)" --base HEAD --root "$J" --repo "$J" --repo "$J/vendor/acme/mod"
[ "$(field 'd["paths"]')" = "['new.txt', 'vendor/acme/mod/m.txt']" ] && ok "a module repo under an ignored vendor/ is captured once by its own repo" || no "ignored vendor module: $OUT $(cat "$T/err")"

K="$T/store"; repo "$K" vendor-keep.txt; mkdir -p "$K/vendor"; printf 'keep\n' > "$K/vendor/keep.txt"; git -C "$K" add -A; git -C "$K" commit -qm vendor --no-verify
repo "$K/vendor/acme/mod" m.txt; printf 'mod-change\n' >> "$K/vendor/acme/mod/m.txt"
run --scratch "$(scratch)" --base HEAD --root "$K" --repo "$K" --repo "$K/vendor/acme/mod"
{ [ "$RC" -eq 0 ] && [ "$(field 'd["paths"]')" = "['vendor/acme/mod/m.txt']" ]; } && ok "a module repo under a tracked vendor/ is captured once by its own repo" || no "tracked vendor module (rc=$RC): $OUT $(cat "$T/err")"

C="$T/clean"; repo "$C"
run --scratch "$(scratch)" --base HEAD --root "$C"
{ [ "$(field 'd["empty"]')" = "True" ] && [ ! -s "$(field 'd["diffPath"]')" ]; } && ok "a clean tree gives empty true and a zero-byte file" || no "clean tree: $OUT"

FIRST="$(git -C "$C" rev-parse HEAD)"; printf 'later\n' >> "$C/src.txt"; git -C "$C" commit -qam c2 --no-verify
run --scratch "$(scratch)" --base "$FIRST" --root "$C"
grep -q '^+later$' "$(field 'd["diffPath"]')" && ok "a sha base captures the commits after it" || no "sha base: $OUT"

run --scratch "$(scratch)" --base HEAD --root "$P" --repo "$R"
{ [ "$RC" -eq 2 ] && grep -q '^slice-capture: ' "$T/err"; } && ok "a --repo outside --root exits 2" || no "outside repo (rc=$RC): $(cat "$T/err")"

run --scratch "$(scratch)" --base HEAD --root "$P" --repo "$P/app" --repo "$P/app/"
{ [ "$RC" -eq 2 ] && grep -q '^slice-capture: ' "$T/err"; } && ok "a duplicate --repo exits 2" || no "duplicate repo (rc=$RC): $(cat "$T/err")"

run --scratch "$(scratch)" --base 'HEAD~1' --root "$C"
{ [ "$RC" -eq 2 ] && grep -q '^slice-capture: ' "$T/err"; } && ok "a bad --base exits 2" || no "bad base (rc=$RC): $(cat "$T/err")"

OUT="$SINGLE"
[ "$(field '"parts" in d')" = "False" ] && ok "a run with no --repo prints no parts key" || no "parts key present: $OUT"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
