#!/usr/bin/env bash
# Hermetic behavior suite for git-ro.sh. Builds a throwaway repo whose config wires
# every execute-on-read vector (pager, fsmonitor, external diff, textconv) to a
# marker-writing script, then proves git-ro neutralizes each: the marker never
# appears, write options can't write, and ordinary status/diff/log/show still work.
# No network. Everything lives under mktemp dirs cleaned on exit.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITRO="$HERE/../../git-ro.sh"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d -t gitro-repo)"; M="$(mktemp -d -t gitro-markers)"
trap 'rm -rf "$T" "$M"' EXIT

git -C "$T" init -q
git -C "$T" config user.email t@t.invalid
git -C "$T" config user.name t
git -C "$T" config commit.gpgsign false

# marker-writing drivers (each records that it executed, then behaves benignly)
mk() { printf '#!/bin/sh\n: > "%s/%s"\nexec cat\n' "$M" "$1" > "$T/evil-$1.sh"; chmod +x "$T/evil-$1.sh"; }
mk PAGER; mk FSMON; mk EXTDIFF; mk TEXTCONV
git -C "$T" config core.pager     "$T/evil-PAGER.sh"
git -C "$T" config core.fsmonitor "$T/evil-FSMON.sh"
git -C "$T" config diff.external  "$T/evil-EXTDIFF.sh"
git -C "$T" config diff.ev.textconv "$T/evil-TEXTCONV.sh"
printf '*.bin diff=ev\n' > "$T/.gitattributes"

printf 'hello\n' > "$T/a.txt"
printf '\000\001binary\n' > "$T/data.bin"
git -C "$T" add -A >/dev/null; git -C "$T" commit -qm c1 >/dev/null
printf 'changed\n' >> "$T/a.txt"   # an unstaged change so diff has content

# Clear any markers created by the RAW setup git calls above (which run without
# git-ro's neutralization and legitimately trigger fsmonitor). Only git-ro-triggered
# executions past this point count.
rm -f "$M"/* 2>/dev/null

# exercise the read operations through git-ro
bash "$GITRO" "$T" status  >/dev/null 2>&1
bash "$GITRO" "$T" diff    >/dev/null 2>&1
bash "$GITRO" "$T" log -p  >/dev/null 2>&1
bash "$GITRO" "$T" show HEAD >/dev/null 2>&1

for mk in PAGER FSMON EXTDIFF TEXTCONV; do
  [ -e "$M/$mk" ] && no "$mk driver EXECUTED via git-ro" || ok "$mk driver neutralized"
done

# caller-supplied --textconv must be refused, and must not execute the driver
rm -f "$M/TEXTCONV"
bash "$GITRO" "$T" show HEAD --textconv >/dev/null 2>&1; rc=$?
{ [ "$rc" -ne 0 ] && [ ! -e "$M/TEXTCONV" ]; } && ok "caller --textconv refused (cannot override --no-textconv)" || no "caller --textconv not refused (rc=$rc, marker=$([ -e "$M/TEXTCONV" ] && echo yes || echo no))"

# write options cannot write a file
bash "$GITRO" "$T" log "--output=$T/OUT.txt" >/dev/null 2>&1
[ -e "$T/OUT.txt" ] && no "--output wrote a file" || ok "--output refused, nothing written"
bash "$GITRO" "$T" diff -o "$T/OUT2.txt" >/dev/null 2>&1
[ -e "$T/OUT2.txt" ] && no "-o wrote a file" || ok "-o refused, nothing written"

# ordinary reads still work
bash "$GITRO" "$T" status >/dev/null 2>&1 && ok "status works" || no "status broken"
bash "$GITRO" "$T" diff   >/dev/null 2>&1 && ok "diff works"   || no "diff broken"
[ -n "$(bash "$GITRO" "$T" log -1 --format=%s 2>/dev/null)" ] && ok "log works" || no "log broken"
bash "$GITRO" "$T" show HEAD >/dev/null 2>&1 && ok "show works" || no "show broken"
# log -c (combined-diff read flag) must NOT be mistaken for a write option
bash "$GITRO" "$T" log -c -1 >/dev/null 2>&1 && ok "log -c allowed (read flag)" || no "log -c wrongly refused"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
