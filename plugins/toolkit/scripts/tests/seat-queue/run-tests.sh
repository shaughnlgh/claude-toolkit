#!/usr/bin/env bash
# Hermetic behavior suite for seat-queue.sh. Builds a throwaway repo with two linked worktrees
# under .claude/worktrees/, feeds a per-case agents JSON through TOOLKIT_AGENTS_FILE or a stub
# claude on the PATH with a per-round counter, and uses live background pids and an exited pid.
# No network, no real claude binary.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$HERE/../../seat-queue.sh"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d -t seatq.XXXXXX)"
sleep 120 & LIVE=$!
sleep 120 & L2=$!
sleep 120 & L3=$!
sleep 120 & L4=$!
trap '{ kill "$LIVE" "$L2" "$L3" "$L4"; wait "$LIVE" "$L2" "$L3" "$L4"; } 2>/dev/null; rm -rf "$T"' EXIT
sh -c 'exit 0' & DEAD=$!; wait "$DEAD"

MAIN="$T/main"
git -C "$T" init -q -b trunk main
git -C "$MAIN" config user.email t@t.invalid
git -C "$MAIN" config user.name t
git -C "$MAIN" config commit.gpgsign false
git -C "$MAIN" commit -q --allow-empty -m c1 --no-verify >/dev/null
WT="$MAIN/.claude/worktrees/wt"; WT2="$MAIN/.claude/worktrees/wt2"
git -C "$MAIN" worktree add -q -b wt "$WT" >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b wt2 "$WT2" >/dev/null 2>&1
Q="$MAIN/.git/toolkit-seat-queue"

# The stub answers agents.<round>.json, else agents.last.json, from the dir that STUB names.
S="$T/stub"; mkdir -p "$T/bin" "$S"
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$STUB/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/n"
if [ -f "$STUB/agents.$n.json" ]; then cat "$STUB/agents.$n.json"; else cat "$STUB/agents.last.json"; fi
STUB
chmod +x "$T/bin/claude"

export TOOLKIT_AGENTS_FILE="$T/agents.json"
row() { printf '{"pid":%s,"sessionId":"%s","cwd":"%s","name":"session %s","status":"busy","kind":"interactive"}' "$1" "$2" "$3" "$2"; }
agents() { local IFS=,; printf '[%s]' "$*" > "$TOOLKIT_AGENTS_FILE"; }
stub() { local f=$1 IFS=,; shift; printf '[%s]' "$*" > "$S/$f"; }
enter() { mkdir -p "$Q"; if [ -n "${3:-}" ]; then printf 'seated\n' > "$Q/$1-$2"; else : > "$Q/$1-$2"; fi; }
aged() { perl -e '$t = time - $ARGV[0]; utime $t, $t, $ARGV[1]' "$1" "$2"; }
q() { OUT="$(bash "$SQ" "$@" 2>>"$T/err")"; RC=$?; }
qe() { OUT="$(bash "$SQ" "$@" 2>"$T/e")"; RC=$?; }
qs() { OUT="$(env -u TOOLKIT_AGENTS_FILE STUB="$S" PATH="$T/bin:$PATH" bash "$SQ" "$@" 2>>"$T/err")"; RC=$?; }
reset() { rm -rf "$Q" "$S"; mkdir -p "$S"; }
names() { ls -1 "$Q" 2>/dev/null | grep -E '^[0-9]{10}-[A-Za-z0-9-]+$' | tr '\n' ' '; }
tagged() { printf '%s\n' "$OUT" | grep -E '^(seated|waiter): ' | awk -F'\t' '{ split($1, a, ":"); printf "%s %s;", a[1], $4 }'; }

reset; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self me
{ [ "$RC" -eq 0 ] && [ "$OUT" = TURN ] && [ "$(ls -A "$Q" | grep -cE '^[0-9]{10}-me$')" -eq 1 ]; } && ok "1 join on a free seat prints TURN and creates one entry" || no "1 free join (rc=$RC): $OUT [$(ls -A "$Q")]"

[ "$(cat "$Q"/*-me)" = seated ] && ok "2 a TURN join marks its entry seated" || no "2 seated mark: '$(cat "$Q"/*-me)'"

reset; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 1 0" ]; } && ok "3 an unqueued main-checkout holder gives WAIT 0 1 1 0" || no "3 unqueued holder (rc=$RC): $OUT"

reset; enter 1000000000 s2; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 1 0 0 0" ]; } && ok "4 an older waiting entry gives WAIT 1 0 0 0" || no "4 waiter ahead (rc=$RC): $OUT"

reset; enter 1000000000 s2 seated; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 0 0" ]; } && ok "5 a seated entry in a worktree holds the seat" || no "5 seated elsewhere (rc=$RC): $OUT"

reset; enter 9999999999 s2 seated; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 0 0" ]; } && ok "6 a seated entry that sorts after the joiner holds the seat" || no "6 seated later (rc=$RC): $OUT"

reset; enter 1000000000 s1; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 1 1 0 0" ]; } && ok "7 a main-checkout holder with an entry is not unqueued" || no "7 queued holder (rc=$RC): $OUT"

reset; enter 1000000000 me; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
[ "$(names)" = "1000000000-me " ] && ok "8 a second join keeps one entry under its first name" || no "8 rejoin entries: $(names)"

reset; enter 1000000000 s2; touch "$Q/.miss-s2"; aged 60 "$Q/.miss-s2"
agents "$(row "$LIVE" me "$WT")" "$(row "$DEAD" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$OUT" = TURN ] && [ ! -e "$Q/1000000000-s2" ]; } && ok "9 a second miss removes a dead waiter and the join gets TURN" || no "9 dead waiter (rc=$RC): $OUT [$(names)]"

reset; enter 1000000000 s2 seated; agents "$(row "$LIVE" me "$WT")" "$(row "$DEAD" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 0 0" ]; } && ok "10 one missed read keeps a dead seated entry" || no "10 first miss (rc=$RC): $OUT"

aged 60 "$Q/.miss-s2"; q join "$MAIN" --self me
[ "$OUT" = TURN ] && ok "11 a second miss a minute later removes the seated entry" || no "11 second miss (rc=$RC): $OUT"

reset; enter 1000000000 s2; touch "$Q/.miss-s2"; aged 700 "$Q/.miss-s2"
agents "$(row "$LIVE" me "$WT")" "$(row "$DEAD" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 1 0 0 0" ]; } && ok "12 a miss marker older than 10 minutes restarts the count" || no "12 old marker (rc=$RC): $OUT"

reset; enter 1000000000 s2; touch "$Q/.miss-s2"; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s2 "$WT2")"; q join "$MAIN" --self me
[ ! -e "$Q/.miss-s2" ] && ok "13 a live read removes the miss marker" || no "13 marker kept (rc=$RC): $OUT"

reset; agents "$(row null me "$WT")"; q join "$MAIN" --self me
{ [ "$RC" -eq 2 ] && [ -z "$(names)" ]; } && ok "14 a null-pid self row exits 2 and keeps no entry" || no "14 null pid (rc=$RC): $OUT [$(names)]"

reset; enter 1000000000 s2; agents "$(row "$LIVE" me "$MAIN")" "$(row "$L2" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 0 ] && [ "$OUT" = TURN ]; } && ok "15 a main-checkout session gets TURN ahead of an older worktree waiter" || no "15 main ignores order (rc=$RC): $OUT"

reset; enter 1000000000 s1; agents "$(row "$LIVE" me "$MAIN")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
{ [ "$RC" -eq 11 ] && [ "$OUT" = "DEADLOCK s1" ]; } && ok "16 a waiting holder beside a main-checkout session gives DEADLOCK" || no "16 deadlock (rc=$RC): $OUT"

reset; enter 1000000000 s1 seated; agents "$(row "$LIVE" me "$MAIN")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 0 0" ]; } && ok "17 a seated holder beside a main-checkout session gives WAIT" || no "17 seated holder (rc=$RC): $OUT"

reset; enter 1000000000 me seated; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
{ [ -e "$Q/1000000000-me" ] && [ ! -s "$Q/1000000000-me" ]; } && ok "18 a WAIT verdict empties the own seated mark" || no "18 mark kept (rc=$RC): $OUT"

: > "$MAIN/dirty.txt"
reset; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 1 1" ]; } && ok "19 a dirty held main checkout gives WAIT 0 1 1 1" || no "19 dirty held (rc=$RC): $OUT"

reset; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self me
{ [ "$RC" -eq 14 ] && [ "$OUT" = "DIRTY 1" ] && [ "$(cat "$Q"/*-me)" = seated ]; } && ok "20 a dirty free main checkout gives DIRTY 1 and marks the entry seated" || no "20 dirty free (rc=$RC): $OUT [$(cat "$Q"/*-me)]"
rm -f "$MAIN/dirty.txt"

reset; mkdir -p "$Q"; : > "$Q/1000000000-s9.bak"; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self me
{ [ "$OUT" = TURN ] && [ -e "$Q/1000000000-s9.bak" ]; } && ok "21 a file outside the entry pattern is neither counted nor removed" || no "21 stray file (rc=$RC): $OUT"

reset; mkdir -p "$Q/.grant"; touch -t 202001010000 "$Q/.grant"; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self me
{ [ "$OUT" = TURN ] && [ ! -e "$Q/.grant" ]; } && ok "22 a stale grant lock is removed and the join gets TURN" || no "22 stale lock (rc=$RC): $OUT"

reset; mkdir -p "$Q/.grant"; agents "$(row "$LIVE" me "$WT")"
bash "$SQ" join "$MAIN" --self me > "$T/bg.out" 2>>"$T/err" & BG=$!
sleep 2; HELD="$(cat "$T/bg.out")"; rmdir "$Q/.grant"; wait "$BG"
{ [ -z "$HELD" ] && [ "$(cat "$T/bg.out")" = TURN ]; } && ok "23 a join waits for a fresh grant lock, then gets TURN" || no "23 fresh lock: held '$HELD', after '$(cat "$T/bg.out")'"

# A stub ls holds a2 between its last listing and its seated write, and a stub date gives both
# joins one epoch, so a1 sorts first and lists while a2 holds a turn it has not marked yet.
R="$T/rbin"; mkdir -p "$R"
printf '#!/usr/bin/env bash\n%s "$@"; rc=$?\nif [ -n "${HOLD:-}" ]; then n=$(( $(cat "$HOLD" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$HOLD"; [ "$n" -ne 3 ] || { : > "$HOLD.held"; sleep 2; }; fi\nexit $rc\n' "$(command -v ls)" > "$R/ls"
printf '#!/usr/bin/env bash\n[ "$*" = +%%s ] && { echo 1000000000; exit 0; }\nexec %s "$@"\n' "$(command -v date)" > "$R/date"
chmod +x "$R/ls" "$R/date"
reset; agents "$(row "$LIVE" a1 "$WT")" "$(row "$L2" a2 "$WT2")"
PATH="$R:$PATH" HOLD="$T/hold" bash "$SQ" join "$MAIN" --self a2 > "$T/c2.out" 2>>"$T/err" & P2=$!
for i in $(seq 50); do [ -e "$T/hold.held" ] && break; sleep 0.1; done
PATH="$R:$PATH" bash "$SQ" join "$MAIN" --self a1 > "$T/c1.out" 2>>"$T/err" & P1=$!
wait "$P1" "$P2"
{ [ -e "$T/hold.held" ] && [ "$(cat "$T/c1.out" "$T/c2.out" | grep -cx TURN)" -eq 1 ] && [ "$(cat "$Q"/1000000000-a1 "$Q"/1000000000-a2 | grep -cx seated)" -eq 1 ]; } && ok "24 a join that lists while another join holds an unmarked turn gets no TURN" || no "24 concurrent: a1 '$(cat "$T/c1.out")' a2 '$(cat "$T/c2.out")'"

reset; enter 1000000000 me seated; enter 1000000001 s2; q leave "$MAIN" --self me
{ [ "$RC" -eq 0 ] && [ "$(names)" = "1000000001-s2 " ]; } && ok "25 leave removes the own entry and keeps the others" || no "25 leave (rc=$RC): $(names)"

reset; enter 1000000000 s1 seated; enter 1000000001 s2; enter 1000000002 s3
agents "$(row "$LIVE" s1 "$WT")" "$(row "$L2" s2 "$WT2")" "$(row "$DEAD" s3 "$WT2")"; q list "$MAIN"
[ "$(tagged)" = "seated s1;waiter s2;" ] && ok "26 list prints live entries in join order with their tags" || no "26 list (rc=$RC): $OUT"

reset; enter 1000000000 s1; agents "$(row "$LIVE" s1 "$MAIN")" "$(row "$L2" s2 "$MAIN")"; q list "$MAIN"
[ "$(printf '%s\n' "$OUT" | grep '^unqueued: ' | cut -f4 | tr '\n' ' ')" = "s2 " ] && ok "27 list prints unqueued only for a holder with no entry" || no "27 unqueued (rc=$RC): $OUT"

reset; enter 1000000000 me; agents "$(row "$LIVE" me "$WT")"; q wait "$MAIN" --self me --interval 1 --bound 5s
{ [ "$RC" -eq 0 ] && [ "$OUT" = TURN ]; } && ok "28 wait prints TURN on the first round" || no "28 wait turn (rc=$RC): $OUT"

reset; enter 1000000000 me; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q wait "$MAIN" --self me --interval 1 --bound 2s
{ [ "$RC" -eq 12 ] && [ "$OUT" = "BOUND 0 0 1 1 0" ]; } && ok "29 wait prints BOUND with the counts of its last WAIT and exits 12 on a held seat" || no "29 bound (rc=$RC): $OUT"

reset; mkdir -p "$Q"; agents "$(row "$LIVE" me "$WT")"; q wait "$MAIN" --self me --interval 1 --bound 5s
{ [ "$RC" -eq 13 ] && [ "$OUT" = LEFT ]; } && ok "30 wait with no own entry prints LEFT" || no "30 no entry (rc=$RC): $OUT"

reset; enter 1000000000 me; agents "$(row "$DEAD" me "$WT")"; q wait "$MAIN" --self me --interval 6 --bound 30s
{ [ "$RC" -eq 13 ] && [ "$OUT" = LEFT ]; } && ok "31 wait with a dead own row across two rounds prints LEFT" || no "31 dead self (rc=$RC): $OUT"

reset; enter 1000000000 me
stub agents.1.json "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; stub agents.last.json "$(row "$LIVE" me "$WT")"
qs wait "$MAIN" --self me --interval 1 --bound 30s
{ [ "$RC" -eq 0 ] && [ "$OUT" = TURN ]; } && ok "32 wait prints TURN after the holder ends between rounds" || no "32 holder ends (rc=$RC): $OUT"

reset; enter 1000000000 me; printf '{}' > "$TOOLKIT_AGENTS_FILE"; qe wait "$MAIN" --self me --interval 1 --bound 30s
{ [ "$RC" -eq 3 ] && [ "$(tail -1 "$T/e")" = "error: the seat check failed five rounds in a row" ]; } && ok "33 wait exits 3 after five failed rounds and ends stderr with its own error line" || no "33 failed rounds (rc=$RC): $OUT [$(tail -1 "$T/e")]"

q bogus "$MAIN" --self me
[ "$RC" -eq 2 ] && ok "34 an unknown subcommand exits 2" || no "34 bogus (rc=$RC): $OUT"

reset; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self 'a/b'
{ [ "$RC" -eq 2 ] && [ -z "$(ls -A "$Q" 2>/dev/null)" ]; } && ok "35 a --self value with a slash exits 2 and writes nothing" || no "35 bad self (rc=$RC): $(ls -A "$Q" 2>/dev/null)"

reset; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" p "$MAIN")"; q join "$MAIN" --self me --parent p
{ [ "$RC" -eq 15 ] && [ "$OUT" = "PARENT p" ] && [ -z "$(names)" ]; } && ok "36 an unqueued parent in the main checkout gives PARENT and no entry" || no "36 parent (rc=$RC): $OUT [$(names)]"

reset; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s1 "$MAIN")"; q join "$MAIN" --self me --parent x
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 1 0" ]; } && ok "37 a --parent id that holds nothing falls back to the wait" || no "37 unknown parent (rc=$RC): $OUT"

reset; enter 1000000000 p seated; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" p "$MAIN")"; q join "$MAIN" --self me --parent p
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 1 0 0" ]; } && ok "38 a parent with a seated entry is waited for" || no "38 seated parent (rc=$RC): $OUT"

reset; enter 1000000000 me
stub agents.1.json "$(row "$LIVE" me "$WT")" "$(row "$L2" p "$WT2")" "$(row "$L3" s1 "$MAIN")"
stub agents.last.json "$(row "$LIVE" me "$WT")" "$(row "$L2" p "$MAIN")" "$(row "$L3" s1 "$MAIN")"
qs wait "$MAIN" --self me --parent p --interval 1 --bound 30s
{ [ "$RC" -eq 15 ] && [ "$OUT" = "PARENT p" ] && [ -z "$(names)" ]; } && ok "39 wait prints PARENT when the parent moves into the main checkout" || no "39 parent moves (rc=$RC): $OUT [$(names)]"

reset; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self me --parent 'a/b'
{ [ "$RC" -eq 2 ] && [ -z "$(ls -A "$Q" 2>/dev/null)" ]; } && ok "40 a --parent value with a slash exits 2 and writes nothing" || no "40 bad parent (rc=$RC): $(ls -A "$Q" 2>/dev/null)"

reset; enter 1000000000 me seated; agents "$(row "$L2" s1 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 10 ] && [ "$OUT" = "WAIT 0 0 0 0" ] && [ -e "$Q/1000000000-me" ]; } && ok "41 a rejoin whose read misses its own row keeps its entry and waits" || no "41 rejoin miss (rc=$RC): $OUT [$(names)]"

reset; enter 1000000000 s2 seated; touch "$Q/.miss-s2"; agents "$(row "$LIVE" me "$WT")" "$(row "$DEAD" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$OUT" = "WAIT 0 1 0 0" ] && [ -e "$Q/1000000000-s2" ]; } && ok "42 a second miss under 5 seconds after the first keeps the seated entry" || no "42 miss floor (rc=$RC): $OUT [$(names)]"

reset; enter 1000000000 s2 seated; touch "$Q/.miss-s2"; aged 60 "$Q/.miss-s2"; agents "$(row "$L3" s3 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 2 ] && [ -e "$Q/1000000000-s2" ]; } && ok "43 a join whose read misses its own row removes no other entry" || no "43 self miss before sweep (rc=$RC): $OUT [$(names)]"

reset; q leave "$MAIN" --self me
[ "$RC" -eq 0 ] && ok "44 leave with no queue directory exits 0 at once" || no "44 leave no queue (rc=$RC): $OUT"

reset; stub agents.1.json; stub agents.last.json "$(row "$LIVE" me "$WT")"; qs join "$MAIN" --self me
{ [ "$RC" -eq 0 ] && [ "$OUT" = TURN ] && [ "$(cat "$S/n")" -eq 2 ] && [ -n "$(names)" ]; } && ok "45 a first join whose first read misses its own row reads again and gets TURN" || no "45 first-join miss (rc=$RC): $OUT [$(names)] reads $(cat "$S/n")"

reset; stub agents.last.json "$(row "$L2" s1 "$WT2")"; qs join "$MAIN" --self me
{ [ "$RC" -eq 2 ] && [ "$(cat "$S/n")" -eq 2 ] && [ -z "$(names)" ]; } && ok "46 a first join whose two reads miss its own row exits 2 and keeps no entry" || no "46 first-join two misses (rc=$RC): $OUT [$(names)] reads $(cat "$S/n")"

reset; agents "$(row "$LIVE" me "$WT")"; START=$SECONDS; q wait "$MAIN" --self me --interval 1 --bound 30s
{ [ "$RC" -eq 13 ] && [ "$OUT" = LEFT ] && [ $((SECONDS - START)) -lt 5 ]; } && ok "47 wait with no queue directory prints LEFT at once" || no "47 wait no queue (rc=$RC, $((SECONDS - START))s): $OUT"

reset; printf '{}' > "$TOOLKIT_AGENTS_FILE"; qe join "$MAIN" --self me
{ [ "$RC" -eq 2 ] && [ "$(sed -n 1p "$T/e")" = "error: agents source is not a JSON array" ] && [ "$(tail -1 "$T/e")" = "error: the seat check could not run" ]; } && ok "48 a join whose seat check fails exits 2 with the seat-check line, then its own line last" || no "48 join seat failure (rc=$RC): $(tr '\n' '|' < "$T/e")"

reset; printf '{}' > "$TOOLKIT_AGENTS_FILE"; q list "$MAIN"
[ "$RC" -eq 2 ] && ok "49 list on a failed seat check exits 2" || no "49 list seat failure (rc=$RC): $OUT"

mkdir -p "$T/alt"; cp "$SQ" "$T/alt/seat-queue.sh"; printf '#!/usr/bin/env bash\nexit 137\n' > "$T/alt/seat-check.sh"
reset; enter 1000000000 me; enter 1000000001 s1 seated; touch "$Q/.miss-s1"; aged 60 "$Q/.miss-s1"
OUT="$(bash "$T/alt/seat-queue.sh" join "$MAIN" --self me 2>>"$T/err")"; RC=$?
{ [ "$RC" -eq 2 ] && [ -e "$Q/1000000001-s1" ]; } && ok "50 a seat check killed with 137 fails the join and removes no live entry" || no "50 killed seat check (rc=$RC): $OUT [$(names)]"

reset; enter 1000000000 me; enter 1000000001 s2; agents "$(row "$LIVE" me "$WT")" "$(row "$L2" s2 "$WT2")"; q join "$MAIN" --self me
{ [ "$RC" -eq 0 ] && [ "$OUT" = TURN ]; } && ok "51 a waiting entry that sorts after the joiner is not ahead of it" || no "51 later waiter (rc=$RC): $OUT"

reset; mkdir -p "$Q/.grant" "$Q/.grant.break"; touch -t 202001010000 "$Q/.grant" "$Q/.grant.break"; agents "$(row "$LIVE" me "$WT")"; q join "$MAIN" --self me
{ [ "$OUT" = TURN ] && [ ! -e "$Q/.grant.break" ]; } && ok "52 an orphaned stale break lock is removed and the join gets TURN" || no "52 stale break (rc=$RC): $OUT"

# A stub ls removes the entry that DROP names on its second call, the verdict's first listing, as another run's leave would.
D="$T/dbin"; mkdir -p "$D"
printf '#!/usr/bin/env bash\nn=$(( $(cat "$DROP.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$DROP.n"\n[ "$n" -ne 2 ] || rm -f "$DROP"\nexec %s "$@"\n' "$(command -v ls)" > "$D/ls"; chmod +x "$D/ls"
reset; enter 1000000000 me; agents "$(row "$LIVE" me "$WT")"
OUT="$(PATH="$D:$PATH" DROP="$Q/1000000000-me" bash "$SQ" join "$MAIN" --self me 2>"$T/e")"; RC=$?
{ [ "$RC" -eq 2 ] && [ "$(tail -1 "$T/e")" = "error: the queue entry for session me was removed before the verdict read it, by a leave or by a sweep after two reads missed its live row" ]; } && ok "53 a rejoin whose entry goes before its verdict lists exits 2 and says the entry was removed" || no "53 rejoin removed (rc=$RC): $(tr '\n' '|' < "$T/e")"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
