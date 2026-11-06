#!/usr/bin/env bash
# Hermetic behavior suite for seat-check.sh. Builds a throwaway repo with one linked worktree
# under .claude/worktrees/, feeds a per-case agents JSON through TOOLKIT_AGENTS_FILE, and uses a
# live background pid and an exited pid. No network, no claude binary.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAT="$HERE/../../seat-check.sh"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d -t seat.XXXXXX)"; O="$(mktemp -d -t seat-other.XXXXXX)"
sleep 60 & LIVE=$!
trap 'kill "$LIVE" 2>/dev/null; rm -rf "$T" "$O"' EXIT
sh -c 'exit 0' & DEAD=$!; wait "$DEAD"

MAIN="$T/main"; mkdir -p "$MAIN/sub" "$T/plain"
git -C "$MAIN" init -q -b trunk
git -C "$MAIN" config user.email t@t.invalid
git -C "$MAIN" config user.name t
git -C "$MAIN" config commit.gpgsign false
: > "$MAIN/sub/.keep"
git -C "$MAIN" add -A >/dev/null; git -C "$MAIN" commit -qm c1 --no-verify >/dev/null
git -C "$MAIN" worktree add -q -b wt "$MAIN/.claude/worktrees/wt" >/dev/null 2>&1
git -C "$O" init -q
ln -s "$MAIN" "$T/link"
MAIN_P="$(cd "$MAIN" && pwd -P)"

export TOOLKIT_AGENTS_FILE="$T/agents.json"
agents() { printf '%s' "$1" > "$TOOLKIT_AGENTS_FILE"; }
entry() { printf '[{"pid":%s,"sessionId":"%s","cwd":"%s","name":"build session","status":"busy","kind":"interactive"}]' "$1" "$2" "$3"; }
run() { OUT="$(bash "$SEAT" "$@" 2>&1)"; RC=$?; }
holder_count() { printf '%s\n' "$OUT" | grep -c '^holder: '; }

agents '[]'; run "$MAIN" --self me
{ [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | head -1)" = "seat: free" ]; } && ok "empty list: seat free, exit 0" || no "empty list (rc=$RC): $OUT"

agents "$(entry "$LIVE" s1 "$MAIN")"; run "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$(printf '%s\n' "$OUT" | head -1)" = "seat: held" ] && [ "$(holder_count)" -eq 1 ] \
  && printf '%s\n' "$OUT" | grep -q $'^holder: build session\tbusy\t'; } && ok "live pid at main holds the seat, exit 10" || no "live pid at main (rc=$RC): $OUT"

agents "$(entry "$DEAD" s1 "$MAIN")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 0 ] && ok "dead pid is not a holder" || no "dead pid held: $OUT"

agents "$(entry "$LIVE" me "$MAIN")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 0 ] && ok "own session is not a holder" || no "own session held: $OUT"

agents "$(entry null s1 "$MAIN")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 0 ] && ok "null pid is not a holder" || no "null pid held: $OUT"

agents "$(entry "$LIVE" s1 "$MAIN/.claude/worktrees/wt")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 0 ] && ok "linked worktree session is not a holder" || no "worktree session held: $OUT"

agents "$(entry "$LIVE" s1 "$MAIN/sub")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 1 ] && ok "subdirectory of main is a holder" || no "subdirectory not held: $OUT"

agents "$(entry "$LIVE" s1 "$O")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 0 ] && ok "another repo is not a holder" || no "another repo held: $OUT"

agents "$(entry "$LIVE" s1 "$T/link")"; run "$MAIN" --self me
[ "$(holder_count)" -eq 1 ] && ok "symlink to main is a holder" || no "symlink not held: $OUT"

agents '[]'; run "$MAIN/.claude/worktrees/wt"
printf '%s\n' "$OUT" | grep -qFx "main: $MAIN_P" && ok "worktree argument reports the main checkout" || no "worktree main line: $OUT"

agents "$(entry "$LIVE" s2 "$MAIN/.claude/worktrees/wt")"; run "$MAIN" --self me --worktree "$MAIN/.claude/worktrees/wt"
printf '%s\n' "$OUT" | grep -q $'^occupant: build session\tbusy\t' && ok "a live session in the --worktree path is an occupant" || no "occupant missing: $OUT"

agents "$(entry "$DEAD" s2 "$MAIN/.claude/worktrees/wt")"; run "$MAIN" --self me --worktree "$MAIN/.claude/worktrees/wt"
! printf '%s\n' "$OUT" | grep -q '^occupant: ' && ok "a dead pid in the --worktree path is not an occupant" || no "dead pid listed as occupant: $OUT"

agents "$(entry "$LIVE" s1 "$MAIN")"; run "$MAIN" --self me --worktree "$MAIN/.claude/worktrees/wt"
{ [ "$(holder_count)" -eq 1 ] && ! printf '%s\n' "$OUT" | grep -q '^occupant: '; } && ok "a main checkout session is a holder, not an occupant" || no "main session listed as occupant: $OUT"

agents '[]'; run "$MAIN"
printf '%s\n' "$OUT" | grep -qx 'dirty: 0' && ok "a linked worktree under .claude/worktrees/ is not dirty" || no "worktree counted as dirty: $OUT"

: > "$MAIN/untracked.txt"; agents '[]'; run "$MAIN"
{ printf '%s\n' "$OUT" | grep -qx 'branch: trunk' && printf '%s\n' "$OUT" | grep -qx 'dirty: 1'; } && ok "branch and dirty count read the main checkout" || no "branch/dirty: $OUT"

run "$T/plain"
{ [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q '^error: '; } && ok "non-repo path exits 2 with an error line" || no "non-repo (rc=$RC): $OUT"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
