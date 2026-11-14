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
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault" > "$BASE/home/.claude/toolkit-vault.json"
V="$BASE/vault/AI"

run() { HOME="$BASE/home" bash "$VFS" "$@" 2>&1; }

# 1. normal rm of a regular file inside the vault
echo x > "$V/Projects/gone.md"
out="$(run rm 'Projects/gone.md')"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$V/Projects/gone.md" ] && ok "01 rm regular file" || no "01 rm regular file" "rc=$rc $out"

# 2. .tmp -> new final path mv
echo body > "$V/Projects/note.tmp.md"
out="$(run mv 'Projects/note.tmp.md' 'Projects/note.md')"; rc=$?
[ $rc -eq 0 ] && [ -f "$V/Projects/note.md" ] && [ ! -e "$V/Projects/note.tmp.md" ] && ok "02 tmp -> new final mv" || no "02 tmp -> new final mv" "rc=$rc $out"

# 3. atomic replacement of an existing final file stays allowed
echo v2 > "$V/Projects/note.tmp.md"
out="$(run mv 'Projects/note.tmp.md' 'Projects/note.md')"; rc=$?
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
echo x > "$V/docs-link/in.tmp.md"
out="$(run mv 'docs-link/in.tmp.md' 'docs-link/in.md')"; rc=$?
[ $rc -eq 0 ] && [ -f "$V/Docs/in.md" ] && ok "12 in-vault symlink allowed" || no "12 in-vault symlink allowed" "rc=$rc $out"

# 13. paths containing spaces work
echo x > "$V/Projects/demo dir/plan - my note.tmp.md"
out="$(run mv 'Projects/demo dir/plan - my note.tmp.md' 'Projects/demo dir/plan - my note.md')"; rc=$?
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

VREAL="$(cd "$V" && pwd -P)"

# 16. absolute input names the resolved root and expected form
out="$(run rm "$V/Projects/x.md")"; rc=$?
[ $rc -ne 0 ] && case "$out" in *"vault root: $VREAL"*"Projects/<repo>/"*) ok "16 absolute path error names root";; *) no "16 absolute path error names root" "$out";; esac || no "16 absolute path error names root" "rc=0"

# 17. missing source names the resolved root and expected form
out="$(run rm 'Projects/does-not-exist.md')"; rc=$?
[ $rc -ne 0 ] && case "$out" in *"vault root: $VREAL"*"Projects/<repo>/"*) ok "17 missing source error names root";; *) no "17 missing source error names root" "$out";; esac || no "17 missing source error names root" "rc=0"

# 18. destination directory missing names the resolved root and expected form
echo x > "$V/Projects/src18.md"
out="$(run mv 'Projects/src18.md' 'NoSuchDir/dest18.md')"; rc=$?
[ $rc -ne 0 ] && case "$out" in *"vault root: $VREAL"*"Projects/<repo>/"*) ok "18 destination directory missing names root";; *) no "18 destination directory missing names root" "$out";; esac || no "18 destination directory missing names root" "rc=0"

# 19. outside-vault symlink refusal names the resolved root and expected form
out="$(run rm 'escape/target.md')"; rc=$?
[ $rc -ne 0 ] && case "$out" in *"vault root: $VREAL"*"Projects/<repo>/"*) ok "19 outside-vault symlink refusal names root";; *) no "19 outside-vault symlink refusal names root" "$out";; esac || no "19 outside-vault symlink refusal names root" "rc=0"

# 20. sha256 prints the sha256 of a vault note
printf 'plan body\n' > "$V/Projects/plan - a.md"
out="$(run sha256 'Projects/plan - a.md')"; rc=$?
want="$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$V/Projects/plan - a.md")"
[ $rc -eq 0 ] && [ "$out" = "$want" ] && ok "20 sha256 of a vault note" || no "20 sha256 of a vault note" "rc=$rc $out"

# 21. sha256 refuses an absolute path
out="$(run sha256 "$V/Projects/plan - a.md")"; rc=$?
[ $rc -eq 1 ] && case "$out" in refused:*) ok "21 sha256 absolute path refused";; *) no "21 sha256 absolute path refused" "$out";; esac || no "21 sha256 absolute path refused" "rc=$rc"

# 22. sha256 refuses a directory
out="$(run sha256 'Projects/demo dir')"; rc=$?
[ $rc -eq 1 ] && case "$out" in refused:*) ok "22 sha256 directory refused";; *) no "22 sha256 directory refused" "$out";; esac || no "22 sha256 directory refused" "rc=$rc"

# 23. index prints the plan index, whose sha256 equals the sha256 subcommand's
printf '## Objective\n\nShip it.\n\n## Implementation Steps\n\n1. One.\n2. Two.\n' > "$V/Projects/plan - b.md"
got="$(run index 'Projects/plan - b.md' | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["sha256"], d["sections"][1]["line"], [s["line"] for s in d["implementationSteps"]])')"
[ "$got" = "$(run sha256 'Projects/plan - b.md') 5 [7, 8]" ] && ok "23 index of a vault plan note" || no "23 index of a vault plan note" "$got"

# 24. index refuses a symlink inside the vault that resolves outside it
printf '## Objective\n' > "$BASE/outside/plan - out.md"
ln -s "$BASE/outside/plan - out.md" "$V/Projects/plan - link.md"
out="$(run index 'Projects/plan - link.md')"; rc=$?
[ $rc -eq 1 ] && case "$out" in refused:*) ok "24 index outside symlink refused";; *) no "24 index outside symlink refused" "$out";; esac || no "24 index outside symlink refused" "rc=$rc"

# 25. index of a note that is not UTF-8 exits 1 with a plan-index line
printf '## Objective\n\xff\n' > "$V/Projects/plan - bad.md"
out="$(run index 'Projects/plan - bad.md')"; rc=$?
[ $rc -eq 1 ] && case "$out" in plan-index:*) ok "25 index of a non-UTF-8 note fails";; *) no "25 index of a non-UTF-8 note fails" "$out";; esac || no "25 index of a non-UTF-8 note fails" "rc=$rc"

# cp and attach fixtures: a git checkout at BASE/repo holding a PNG and a JPEG with real magic headers.
R="$BASE/repo"
mkdir -p "$R/.git" "$R/out" "$BASE/norepo"
python3 -c 'import sys; open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + bytes(range(256))); open(sys.argv[2], "wb").write(b"\xff\xd8\xff\xe0" + bytes(range(256)))' "$R/out/s1.png" "$R/out/s2.jpg"

# 26. cp makes a byte-identical .tmp.md copy and keeps the source
printf 'plan body\nline two\n' > "$V/Projects/plan - c.md"
out="$(run cp 'Projects/plan - c.md' 'Projects/plan - c.tmp.md')"; rc=$?
[ $rc -eq 0 ] && cmp -s "$V/Projects/plan - c.md" "$V/Projects/plan - c.tmp.md" && [ -f "$V/Projects/plan - c.md" ] && ok "26 cp makes a byte-identical copy" || no "26 cp makes a byte-identical copy" "rc=$rc $out"

# 27. cp replaces an existing .tmp.md copy
echo stale > "$V/Projects/plan - c.tmp.md"
out="$(run cp 'Projects/plan - c.md' 'Projects/plan - c.tmp.md')"; rc=$?
[ $rc -eq 0 ] && cmp -s "$V/Projects/plan - c.md" "$V/Projects/plan - c.tmp.md" && ok "27 cp replaces an existing copy" || no "27 cp replaces an existing copy" "rc=$rc $out"

# 28. cp refuses an absolute source
out="$(run cp "$V/Projects/plan - c.md" 'Projects/abs.tmp.md')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/abs.tmp.md" ] && case "$out" in "refused: relative vault paths only"*) ok "28 cp absolute source refused";; *) no "28 cp absolute source refused" "$out";; esac || no "28 cp absolute source refused" "rc=$rc"

# 29. cp refuses a directory source
out="$(run cp 'Projects/demo dir' 'Projects/dir.tmp.md')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/dir.tmp.md" ] && case "$out" in "refused: directory operations are not allowed"*) ok "29 cp directory source refused";; *) no "29 cp directory source refused" "$out";; esac || no "29 cp directory source refused" "rc=$rc"

# 30. cp refuses a source symlink inside the vault that resolves outside it
ln -s "$BASE/outside/target.md" "$V/Projects/out-link.md"
out="$(run cp 'Projects/out-link.md' 'Projects/out-link.tmp.md')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/out-link.tmp.md" ] && case "$out" in "refused: path resolves outside the vault"*) ok "30 cp outside symlink source refused";; *) no "30 cp outside symlink source refused" "$out";; esac || no "30 cp outside symlink source refused" "rc=$rc"

# 31. attach copies a PNG byte-identical into Projects/
out="$(run attach "$R" 'out/s1.png' 'Projects/evidence-s1.png')"; rc=$?
[ $rc -eq 0 ] && cmp -s "$R/out/s1.png" "$V/Projects/evidence-s1.png" && ok "31 attach copies a PNG" || no "31 attach copies a PNG" "rc=$rc $out"

# 32. attach copies a JPEG to a .jpg destination
out="$(run attach "$R" 'out/s2.jpg' 'Projects/evidence-s2.jpg')"; rc=$?
[ $rc -eq 0 ] && cmp -s "$R/out/s2.jpg" "$V/Projects/evidence-s2.jpg" && ok "32 attach copies a JPEG" || no "32 attach copies a JPEG" "rc=$rc $out"

# 33. attach refuses an existing destination and leaves its bytes unchanged
echo keep > "$V/Projects/taken.png"
out="$(run attach "$R" 'out/s1.png' 'Projects/taken.png')"; rc=$?
[ $rc -eq 1 ] && [ "$(cat "$V/Projects/taken.png")" = "keep" ] && case "$out" in "refused: attachment destination exists"*) ok "33 attach existing destination refused";; *) no "33 attach existing destination refused" "$out";; esac || no "33 attach existing destination refused" "rc=$rc"

# 34. attach refuses a text file named .png
echo 'not an image' > "$R/out/fake.png"
out="$(run attach "$R" 'out/fake.png' 'Projects/fake.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/fake.png" ] && case "$out" in "refused: source is not a PNG or JPEG"*) ok "34 attach text file named png refused";; *) no "34 attach text file named png refused" "$out";; esac || no "34 attach text file named png refused" "rc=$rc"

# 35. attach refuses a source symlink that resolves outside the checkout
cp "$R/out/s1.png" "$BASE/outside/s1.png"
ln -s "$BASE/outside/s1.png" "$R/out/link.png"
out="$(run attach "$R" 'out/link.png' 'Projects/link.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/link.png" ] && case "$out" in "refused: source resolves outside the checkout"*) ok "35 attach outside symlink source refused";; *) no "35 attach outside symlink source refused" "$out";; esac || no "35 attach outside symlink source refused" "rc=$rc"

# 36. attach refuses a .. source
out="$(run attach "$R" 'out/../out/s1.png' 'Projects/dotdot.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/dotdot.png" ] && case "$out" in "refused: source must be relative to the checkout, no '..'"*) ok "36 attach dot-dot source refused";; *) no "36 attach dot-dot source refused" "$out";; esac || no "36 attach dot-dot source refused" "rc=$rc"

# 37. attach refuses a root with no .git
cp "$R/out/s1.png" "$BASE/norepo/s1.png"
out="$(run attach "$BASE/norepo" 's1.png' 'Projects/norepo.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/norepo.png" ] && case "$out" in "refused: not a git checkout root"*) ok "37 attach root without .git refused";; *) no "37 attach root without .git refused" "$out";; esac || no "37 attach root without .git refused" "rc=$rc"

# 38. attach refuses a .jpg destination for a PNG
out="$(run attach "$R" 'out/s1.png' 'Projects/wrong.jpg')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/wrong.jpg" ] && case "$out" in "refused: destination extension does not match"*) ok "38 attach jpg destination for a PNG refused";; *) no "38 attach jpg destination for a PNG refused" "$out";; esac || no "38 attach jpg destination for a PNG refused" "rc=$rc"

# 39. attach refuses a sparse PNG over 10 MiB
printf '\x89PNG\r\n\x1a\n' > "$R/out/big.png"
truncate -s 10485761 "$R/out/big.png"
out="$(run attach "$R" 'out/big.png' 'Projects/big.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/big.png" ] && case "$out" in "refused: source is over 10 MiB"*) ok "39 attach PNG over 10 MiB refused";; *) no "39 attach PNG over 10 MiB refused" "$out";; esac || no "39 attach PNG over 10 MiB refused" "rc=$rc"

# 40. cp refuses a destination through an outside-pointing symlinked directory
out="$(run cp 'Projects/plan - c.md' 'escape/leak.tmp.md')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$BASE/outside/leak.tmp.md" ] && case "$out" in "refused: path resolves outside the vault"*) ok "40 cp dest via outside symlink refused";; *) no "40 cp dest via outside symlink refused" "$out";; esac || no "40 cp dest via outside symlink refused" "rc=$rc"

# 41. attach refuses a destination through an outside-pointing symlinked directory
out="$(run attach "$R" 'out/s1.png' 'escape/leak.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$BASE/outside/leak.png" ] && case "$out" in "refused: path resolves outside the vault"*) ok "41 attach dest via outside symlink refused";; *) no "41 attach dest via outside symlink refused" "$out";; esac || no "41 attach dest via outside symlink refused" "rc=$rc"

# 42. attach refuses a checkout that holds the home directory
mkdir -p "$BASE/home/.git" "$BASE/home/Desktop" && cp "$R/out/s1.png" "$BASE/home/Desktop/s1.png"
out="$(run attach "$BASE/home" 'Desktop/s1.png' 'Projects/home.png')"; rc=$?
[ $rc -eq 1 ] && [ ! -e "$V/Projects/home.png" ] && case "$out" in "refused: the checkout holds the home directory"*) ok "42 attach checkout holding the home directory refused";; *) no "42 attach checkout holding the home directory refused" "$out";; esac || no "42 attach checkout holding the home directory refused" "rc=$rc"

# Config name cases: a second vault at BASE/vault-b and one HOME per case.
mkdir -p "$BASE/vault-b/AI/Projects" "$BASE/h-legacy/.claude" "$BASE/h-new/.claude" "$BASE/h-both/.claude" "$BASE/h-bad/.claude"
VB="$BASE/vault-b/AI"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault" > "$BASE/h-legacy/.claude/obsidian-sync.json"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault" > "$BASE/h-new/.claude/toolkit-vault.json"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault-b" > "$BASE/h-both/.claude/toolkit-vault.json"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault" > "$BASE/h-both/.claude/obsidian-sync.json"
printf '{"vault_path": ' > "$BASE/h-bad/.claude/toolkit-vault.json"
printf '{"vault_path": "%s", "root_folder": "AI"}\n' "$BASE/vault" > "$BASE/h-bad/.claude/obsidian-sync.json"

# 43. only the legacy obsidian-sync.json resolves the vault
echo x > "$V/Projects/legacy43.md"
out="$(HOME="$BASE/h-legacy" bash "$VFS" rm 'Projects/legacy43.md' 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$V/Projects/legacy43.md" ] && ok "43 legacy config alone resolves" || no "43 legacy config alone resolves" "rc=$rc $out"

# 44. only toolkit-vault.json resolves the vault
echo x > "$V/Projects/new44.md"
out="$(HOME="$BASE/h-new" bash "$VFS" rm 'Projects/new44.md' 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$V/Projects/new44.md" ] && ok "44 new config alone resolves" || no "44 new config alone resolves" "rc=$rc $out"

# 45. with both files, the rm lands in the toolkit-vault.json vault
echo x > "$V/Projects/both45.md"; echo x > "$VB/Projects/both45.md"
out="$(HOME="$BASE/h-both" bash "$VFS" rm 'Projects/both45.md' 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$VB/Projects/both45.md" ] && [ -f "$V/Projects/both45.md" ] && ok "45 new config wins over legacy" || no "45 new config wins over legacy" "rc=$rc $out"

# 46. an invalid toolkit-vault.json is an error, with no fallback to a valid legacy file
echo x > "$V/Projects/bad46.md"
out="$(HOME="$BASE/h-bad" bash "$VFS" rm 'Projects/bad46.md' 2>&1)"; rc=$?
[ $rc -eq 1 ] && [ -f "$V/Projects/bad46.md" ] && ok "46 invalid new config does not fall back" || no "46 invalid new config does not fall back" "rc=$rc $out"

# 47. topic-index writes INDEX.md inside the resolved vault root
printf -- '---\ntype: topic\nsummary: Topic index case.\n---\n' > "$VB/Projects/Index Case.md"
out="$(HOME="$BASE/h-both" bash "$VFS" topic-index 2>&1)"; rc=$?
[ $rc -eq 0 ] && grep -q 'Index Case' "$VB/INDEX.md" && ok "47 topic-index writes the vault root INDEX.md" || no "47 topic-index writes the vault root INDEX.md" "rc=$rc $out"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
