#!/usr/bin/env bash
# Hermetic behavior suite for worker-watch.sh. TOOLKIT_AGENTS_FILE answers the agents read, except in the
# read failure cases, where a stub claude first on PATH answers agents --json --all from a per-call output list.
# The cross-lead cases write a real /tmp/claude-<uid>/<slug>/<otherId>/scratchpad/workers that the EXIT trap removes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="$(cd "$HERE/../../.." && pwd -P)"
WATCH="$TOOLKIT/scripts/worker-watch.sh"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(cd "$(mktemp -d -t wwatch.XXXXXX)" && pwd -P)"
UTMP="/tmp/claude-$(id -u)"; MADE=""; [ -d "$UTMP" ] || MADE=1
SLUG="$UTMP/wwatch-test-$$-$RANDOM"
OTHER="wwatch-other-$$-$RANDOM"
trap 'rm -rf "$T" "$SLUG"; [ -z "$MADE" ] || rmdir "$UTMP" 2>/dev/null' EXIT
mkdir -p "$T/bin"
SELF=lead-sid-1
SP="$T/$SELF/scratchpad"; mkdir -p "$SP"
ST="$SP/worker-watch.state"
export TOOLKIT_PROJECTS_DIR="$T/projects"
FIX="$HERE/fixtures/limit-line.json"
LEAD=lead-full-sid-1

# The stub answers agents.<n> before agents for the n-th agents call.
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
[ "$1" = agents ] || exit 1
n=$(( $(cat "$CASE/.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CASE/.n"
if [ -e "$CASE/agents.$n" ]; then cat "$CASE/agents.$n"; else cat "$CASE/agents"; fi
STUB
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH"

A=a1a1a1a1 B=b2b2b2b2 C=c3c3c3c3 D=d4d4d4d4
N=0
case_() {
  N=$((N + 1)); export CASE="$T/case.$N"; mkdir -p "$CASE"
  rm -f "$SP/workers" "$ST" "$SP/worker-watch-self" "$SP/worker-watch.lock/pid"; rmdir "$SP/worker-watch.lock" 2>/dev/null
  rm -rf "$T/projects"
  export TOOLKIT_AGENTS_FILE="$CASE/agents"; echo '[]' > "$CASE/agents"
}
worker() { printf '%s\tworker-execute-%s\texecute\tp-%s\t%s\n' "$1" "$1" "$1" "${2:-$(date +%s)}" >> "$SP/workers"; }
stored() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-$(date +%s)}" "${4:-0}" >> "$ST"; }
# $1 id, $2 status, $3 state, $4 waitingFor or "", $5 pid or null, $6 kind, $7 sessionId
row() {
  jq -cn --arg id "$1" --arg st "$2" --arg s "$3" --arg w "${4:-}" --arg p "${5:-4242}" --arg k "${6:-background}" --arg sid "${7:-sess-$1}" \
    '{id: $id, name: ("worker-execute-" + $id), sessionId: $sid, kind: $k, pid: (if $p == "null" then null else ($p | tonumber) end),
      status: $st, state: $s, waitingFor: (if $w == "" then null else $w end)}'
}
agents() { local IFS=,; printf '[%s]\n' "$*" > "${AGF:-$CASE/agents}"; }
run() { OUT="$(bash "$WATCH" "$@" 2>"$CASE/err")"; RC=$?; ERR="$(cat "$CASE/err")"; }
watch() { run wait --scratchpad "$SP" --interval 1 --bound "${BOUND:-3s}" "$@"; }
ago() { local e=$(( $(date +%s) - $1 )); date -r "$e" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$e" +%Y%m%d%H%M.%S; }
sig_of() { awk -F'\t' -v id="$1" '$1 == id { print $2 }' "$ST" 2>/dev/null; }
# $1 sessionId, $2 seconds since the reset (negative for a future reset), $3 line uuid, $4 project folder. Sets LAT to the reset.
limit() {
  LAT=$(( $(date +%s) - $2 )); mkdir -p "$T/projects/${4:--repo-a}"
  jq -c --argjson at "$LAT" --arg u "${3:-u-1}" --arg s "$1" \
    '.quotaLimits.resetsAt = $at | .apiErrorParams.rate_limit_info.resetsAt = $at | .uuid = $u | .sessionId = $s' "$FIX" >> "$T/projects/${4:--repo-a}/$1.jsonl"
}
said() { printf '{"type":"assistant","uuid":"r-1","message":{"model":"claude-opus-5-5"}}\n' >> "$T/projects/-repo-a/$1.jsonl"; }
BUSY() { row "$1" busy working; }
IDLE_DONE() { row "$1" idle done; }

case_; worker "$A"; worker "$B"; stored "$A" busy; stored "$B" busy
agents "$(row "$A" waiting blocked 'input needed')" "$(row "$B" waiting blocked 'permission prompt')"; watch
[ "$RC" -eq 0 ] && [ "$OUT" = "NEEDS worker-execute-$B $B permission"$'\n'"NEEDS worker-execute-$A $A input" ] \
  && ok "permission and input NEEDS in one round print permission first" || no "needs order (rc=$RC): $OUT $ERR"
[ "$(sig_of "$A")" = input ] && [ "$(sig_of "$B")" = permission ] && ok "the state file stores the new signatures" || no "state: $(cat "$ST")"
[ ! -e "$SP/worker-watch.lock" ] && ok "the lock is removed at exit" || no "lock left behind"

case_; worker "$A"; stored "$A" busy; agents "$(row "$A" waiting blocked 'sandbox request')"; watch
[ "$OUT" = "NEEDS worker-execute-$A $A permission" ] && ok "a sandbox request reads permission" || no "sandbox (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(BUSY "$A")"; watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a busy worker that stays busy reaches BOUND exit 10" || no "busy (rc=$RC): $OUT $ERR"

case_; worker "$A"; stored "$A" busy; agents "$(row "$A" idle working)"; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "IDLE worker-execute-$A $A working" ]; } && ok "status idle with state working gives IDLE ... working" || no "idle mid-task (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(row "$A" waiting blocked 'input needed')"; watch; watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a second run on the same input row prints nothing and reaches BOUND" || no "re-arm repeat (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" idle:done; agents "$(IDLE_DONE "$A")"; watch
{ [ "$RC" -eq 11 ] && [ "$OUT" = NONE ]; } && ok "an unchanged idle:done worker gives NONE exit 11" || no "settled (rc=$RC): $OUT"
watch --hold "$A"
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "the same run with --hold gives BOUND exit 10" || no "hold (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" idle:done; agents "$(BUSY "$A")"; watch --hold "$A"
{ [ "$RC" -eq 10 ] && [ "$(sig_of "$A")" = busy ]; } && ok "a held idle:done worker that reads busy is stored as busy" || no "held busy (rc=$RC): $OUT $(cat "$ST")"
agents "$(IDLE_DONE "$A")"; watch
[ "$OUT" = "IDLE worker-execute-$A $A done" ] && ok "a next run without --hold on idle:done gives IDLE" || no "after hold (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" permission "$(( $(date +%s) - 200 ))"; agents "$(row "$A" waiting blocked 'permission prompt')"; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "PUSH worker-execute-$A $A permission 3m" ]; } && ok "a permission wait past --push-after gives PUSH" || no "push (rc=$RC): $OUT"
watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "the next run gives no second PUSH" || no "second push (rc=$RC): $OUT"

case_; worker "$A"; agents "$(IDLE_DONE "$A")"; watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ] && [ -z "$(sig_of "$A")" ]; } && ok "a new worker that reads idle stays pending and reaches BOUND" || no "pending idle (rc=$RC): $OUT"

case_; worker "$A"; watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a new worker with no row stays pending and reaches BOUND" || no "pending no row (rc=$RC): $OUT"

case_; worker "$A"; agents "$(row "$A" waiting blocked 'input needed')"; watch
[ "$OUT" = "NEEDS worker-execute-$A $A input" ] && ok "a new worker that reads input gives NEEDS" || no "new input (rc=$RC): $OUT"

case_; worker "$A" "$(( $(date +%s) - 400 ))"; agents "$(IDLE_DONE "$A")"; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "NOSTART worker-execute-$A $A" ]; } && ok "a new worker idle past the start grace gives NOSTART" || no "nostart (rc=$RC): $OUT"
watch
{ [ "$RC" -eq 11 ] && [ "$OUT" = NONE ]; } && ok "a next run on the same row gives NONE" || no "after nostart (rc=$RC): $OUT"

case_; worker "$A" not-a-number; agents "$(IDLE_DONE "$A")"; watch --start-grace 0
[ "$OUT" = "NOSTART worker-execute-$A $A" ] && ok "a spawn epoch that is not a number counts as the run start" || no "bad epoch (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; watch
[ "$OUT" = "GONE worker-execute-$A $A" ] && ok "a missing row after busy gives GONE" || no "gone (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" idle:done; watch
{ [ "$RC" -eq 11 ] && [ "$OUT" = NONE ] && [ "$(sig_of "$A")" = gone ]; } && ok "a missing row after idle:done prints nothing and settles" || no "finished then gone (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(row "$A" idle done '' null)"; watch
[ "$OUT" = "IDLE worker-execute-$A $A done" ] && ok "a pid-null done row reads its state" || no "pid null done (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(row "$A" idle blocked '' null)"; watch
[ "$OUT" = "NEEDS worker-execute-$A $A input" ] && ok "a pid-null blocked row gives NEEDS input" || no "pid null blocked (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(row "$A" idle stopped '' null)"; watch
[ "$OUT" = "GONE worker-execute-$A $A" ] && ok "a stopped row after busy gives GONE" || no "stopped (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" gone; agents "$(row "$A" waiting blocked 'permission prompt')"; watch
[ "$OUT" = "NEEDS worker-execute-$A $A permission" ] && ok "a gone worker whose row returns waiting gives NEEDS" || no "gone returns (rc=$RC): $OUT"

case_; worker "$A"; worker "$B"; stored "$A" gone; stored "$B" idle:done; agents "$(IDLE_DONE "$B")"; watch
{ [ "$RC" -eq 11 ] && [ "$OUT" = NONE ]; } && ok "every worker gone or settled gives NONE exit 11" || no "all settled (rc=$RC): $OUT"

mkdir -p "$SLUG/$OTHER/scratchpad"; printf '%s\tworker-plan-x\tplan\tx\t1\n' "$D" > "$SLUG/$OTHER/scratchpad/workers"
case_; worker "$A"; stored "$A" busy
agents "$(BUSY "$A")" "$(BUSY "$C")" "$(row f6f6f6f6 busy working '' 77 background "$SELF")" "$(row "$OTHER" idle done '' 88 interactive "$OTHER")" \
  "$(BUSY "$D")" "$(row e5e5e5e5 idle done '' 99 interactive)" "$(row 99999999 idle done '' null background)"; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "UNOWNED 1: worker-execute-$C ($C)" ]; } && ok "the unowned line names a background row no workers file lists" || no "unowned (rc=$RC): $OUT"
[[ $OUT != *f6f6f6f6* ]] && ok "the unowned line leaves out self" || no "unowned self: $OUT"
[[ $OUT != *"$D"* ]] && ok "the unowned line leaves out a row another live lead's workers file lists" || no "unowned other lead: $OUT"
[[ $OUT != *e5e5e5e5* ]] && ok "the unowned line leaves out interactive rows" || no "unowned interactive: $OUT"
[[ $OUT != *99999999* ]] && ok "the unowned line leaves out background rows with no pid" || no "unowned pid null: $OUT"
grep -qxF "unowned"$'\t'"$C" "$ST" && ok "the state file stores the unowned ids" || no "unowned state: $(cat "$ST")"
watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "an unchanged unowned set does not repeat" || no "unowned repeat (rc=$RC): $OUT"

case_; mkdir "$SP/worker-watch.lock"; echo 1 > "$SP/worker-watch.lock/pid"; watch
{ [ "$RC" -eq 12 ] && [ "$OUT" = RUNNING ] && [ -e "$SP/worker-watch.lock/pid" ]; } && ok "a live lock gives RUNNING exit 12 and stays" || no "live lock (rc=$RC): $OUT"
touch -t "$(ago 60)" "$SP/worker-watch.lock/pid"; watch
{ [ "$RC" -eq 11 ] && [ ! -e "$SP/worker-watch.lock" ]; } && ok "a stale lock is taken over" || no "stale lock (rc=$RC): $OUT $ERR"

case_; worker "$A"; worker "$B"; worker "$C"; agents "$(row "$A" waiting blocked 'input needed')" "$(row "$B" idle done '' null)" "$(row "$C" busy working '' null)"
run list --scratchpad "$SP"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "worker: worker-execute-$A"$'\t'"$A"$'\texecute\t'"p-$A"$'\twaiting\tblocked\tinput needed'$'\n'"worker: worker-execute-$C"$'\t'"$C"$'\texecute\t'"p-$C"$'\tbusy\tworking\t-' ]; } \
  && ok "list prints the owned rows with a pid or a working state" || no "list (rc=$RC): $OUT $ERR"
[ ! -e "$ST" ] && ok "list writes no state" || no "list wrote $ST"

case_; agents "$(row "$A" idle done '' 5 interactive lead-x)" "$(row "$B" idle done '' null background lead-y)"; run name lead-x
{ [ "$RC" -eq 0 ] && [ "$OUT" = "name: worker-execute-$A" ]; } && ok "name prints the live row's name" || no "name (rc=$RC): $OUT"
run name lead-y
{ [ "$RC" -eq 11 ] && [ "$OUT" = NONE ]; } && ok "name on a row with no pid or an unknown id gives NONE exit 11" || no "name none (rc=$RC): $OUT"

LONG="lead-$(printf 'x%.0s' {1..80})"
case_; agents "$(row "$A" idle done '' 5 interactive lead-z | jq -c --arg n "$LONG" '.name = $n')"; run name lead-z
{ [ "$RC" -eq 0 ] && [ "$OUT" = "name: $LONG" ]; } && ok "name prints a name longer than 64 characters in full" || no "long name (rc=$RC): $OUT"

case_; unset TOOLKIT_AGENTS_FILE; worker "$A"; stored "$A" busy; echo 'not json' > "$CASE/agents.1"
agents "$(row "$A" waiting blocked 'input needed')"; BOUND=6s watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "NEEDS worker-execute-$A $A input" ]; } && ok "an event follows one failed agents read" || no "one bad read (rc=$RC): $OUT $ERR"

case_; unset TOOLKIT_AGENTS_FILE; worker "$A"; stored "$A" busy; echo 'not json' > "$CASE/agents.1"; : > "$CASE/agents.2"
agents "$(row "$A" waiting blocked 'input needed')"; BOUND=6s watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "NEEDS worker-execute-$A $A input" ]; } && ok "an event follows two failed agents reads" || no "two bad reads (rc=$RC): $OUT $ERR"

case_; unset TOOLKIT_AGENTS_FILE; worker "$A"; stored "$A" busy
echo 'not json' > "$CASE/agents.1"; AGF="$CASE/agents.2" agents "$(BUSY "$A")"; echo 'not json' > "$CASE/agents.3"; echo 'not json' > "$CASE/agents.4"
agents "$(row "$A" waiting blocked 'input needed')"; BOUND=8s watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "NEEDS worker-execute-$A $A input" ]; } && ok "a good read resets the failed read count" || no "bad read reset (rc=$RC): $OUT $ERR"

case_; unset TOOLKIT_AGENTS_FILE; worker "$A"; stored "$A" busy; before=$(cat "$ST")
for i in 1 2 3; do echo 'not json' > "$CASE/agents.$i"; done
agents "$(row "$A" waiting blocked 'input needed')"; BOUND=6s watch
{ [ "$RC" -eq 3 ] && [[ $ERR == error:* ]]; } && ok "three failed reads in a row exit 3 with an error line" || no "three bad reads (rc=$RC): $OUT $ERR"
[ "$(cat "$ST")" = "$before" ] && ok "three failed reads leave the state file unchanged" || no "state changed: $(cat "$ST")"

WAITING() { row "$1" waiting blocked 'input needed'; }
case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "sess-$A" -600; watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ] && [ "$(sig_of "$A")" = limit ]; } && ok "a future reset holds a waiting worker with no NEEDS until the bound" || no "limit hold (rc=$RC): $OUT $ERR"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "sess-$A" 120; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "LIMIT worker-execute-$A $A $LAT sess-$A" ]; } && ok "a reset more than 60 seconds past gives one LIMIT with the session id" || no "limit (rc=$RC): $OUT $ERR"
watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a second watch on the same limit line and waiting row gives no LIMIT" || no "limit repeat (rc=$RC): $OUT"
agents "$(IDLE_DONE "$A")"; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "IDLE worker-execute-$A $A done" ]; } && ok "a worker idle after LIMIT with the same stale line ends by the idle rules" || no "limit then idle (rc=$RC): $OUT"
agents "$(WAITING "$A")"; limit "sess-$A" 120 u-2; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "LIMIT worker-execute-$A $A $LAT sess-$A" ]; } && ok "a new limit line after an announced one gives one new LIMIT" || no "second limit (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "sess-$A" 30; watch
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a reset 30 seconds past stays held inside the margin" || no "limit margin (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A" | jq -c '.cwd = "/repo/a/.claude/worktrees/x"')"; limit "sess-$A" 120 u-1 -elsewhere; watch
[ "$OUT" = "LIMIT worker-execute-$A $A $LAT sess-$A" ] && ok "a transcript in a project folder that differs from the row cwd is found" || no "limit moved (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "sess-$A" 120; said "sess-$A"; watch
[ "$OUT" = "NEEDS worker-execute-$A $A input" ] && ok "a newest assistant line that is no error keeps the old events" || no "limit superseded (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "sess-$A" 120; echo '{"type":"assistant",' >> "$T/projects/-repo-a/sess-$A.jsonl"; watch
[ "$OUT" = "LIMIT worker-execute-$A $A $LAT sess-$A" ] && ok "a malformed transcript line is skipped" || no "limit malformed (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; mkdir -p "$T/projects/-repo-a"
jq -c 'del(.quotaLimits.resetsAt, .apiErrorParams.rate_limit_info.resetsAt) | .sessionId = "x"' "$FIX" > "$T/projects/-repo-a/sess-$A.jsonl"; watch
[ "$OUT" = "LIMIT worker-execute-$A $A 0 sess-$A" ] && ok "a limit line with no resetsAt gives LIMIT at once with 0" || no "limit no reset (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; mkdir -p "$T/projects/-repo-a"
printf '{"type":"user","pad":"%s"}\n' "$(head -c 70000 /dev/zero | tr '\0' x)" > "$T/projects/-repo-a/sess-$A.jsonl"; limit "sess-$A" 120; watch
[ "$OUT" = "LIMIT worker-execute-$A $A $LAT sess-$A" ] && ok "a tail that starts mid-line still finds the limit line" || no "limit partial tail (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" input; agents "$(WAITING "$A")"; watch
{ [ "$RC" -eq 10 ] && [ "$(awk -F'\t' '{ print NF }' "$ST")" = 5 ]; } && ok "a four-field state file from the old watch loads and is written with five fields" || no "old state (rc=$RC): $OUT $(cat "$ST")"

# A fake clock whose every date +%s reads one day later than the one before, so any default bound passes within one round.
mkdir -p "$T/clock"
cat > "$T/clock/date" <<'CLOCK'
#!/usr/bin/env bash
[ "$1" = +%s ] || exec /bin/date "$@"
n=$(( $(cat "$CASE/.clock" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CASE/.clock"
echo $(( $(/bin/date +%s) + n * 86400 ))
CLOCK
chmod +x "$T/clock/date"
case_; worker "$A"; stored "$A" busy; agents "$(BUSY "$A")"
OUT="$(PATH="$T/clock:$PATH" bash "$WATCH" wait --scratchpad "$SP" --interval 1 --bound 60 2>&1)"; RC=$?
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "under the fake clock a watch with --bound 60 ends BOUND" || no "fake clock bound (rc=$RC): $OUT"
case_; worker "$A"; stored "$A" busy; agents "$(BUSY "$A")"
PATH="$T/clock:$PATH" bash "$WATCH" wait --scratchpad "$SP" --interval 1 >/dev/null 2>&1 & WPID=$!
sleep 4; kill -0 "$WPID" 2>/dev/null && ok "under the fake clock a watch with no --bound over a busy row still runs after days" || no "no bound watch ended"
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "sess-$A" 120; limit "$LEAD" -600; watch --self "$LEAD"
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a held lead limit keeps a passed worker LIMIT back" || no "lead held (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(WAITING "$A")"; limit "$LEAD" 120; limit "sess-$A" 120; watch --self "$LEAD"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "LIMIT self - $LAT $LEAD"$'\n'"LIMIT worker-execute-$A $A $LAT sess-$A" ]; } && ok "passed lead and worker limits give LIMIT self and then the worker LIMIT" || no "both limits (rc=$RC): $OUT"
watch --self "$LEAD"
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a second watch after both limits were reported gives no LIMIT" || no "both limits repeat (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(BUSY "$A")"; limit "$SELF" 120; watch
{ [ "$RC" -eq 0 ] && [ "$OUT" = "LIMIT self - $LAT $SELF" ]; } && ok "with no --self the watch reads the lead's limit by the scratchpad's session id" || no "default self (rc=$RC): $OUT $ERR"

case_; worker "$A"; stored "$A" busy; agents "$(BUSY "$A")"; limit "$LEAD" 120; watch --self "$LEAD"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "LIMIT self - $LAT $LEAD" ]; } && ok "a passed lead limit with no worker limit gives LIMIT self" || no "lead limit (rc=$RC): $OUT $ERR"
watch --self "$LEAD"
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ]; } && ok "a second watch on the same lead limit line gives no LIMIT self" || no "lead repeat (rc=$RC): $OUT"

case_; worker "$A"; stored "$A" busy; agents "$(IDLE_DONE "$A")"; limit "$LEAD" 50; watch --self "$LEAD"
{ [ "$RC" -eq 10 ] && [ "$OUT" = BOUND ] && [ "$(sig_of "$A")" = busy ]; } && ok "a worker gone idle while the lead limit holds gives no IDLE and no state change" || no "lead hold idle (rc=$RC): $OUT"
BOUND=20s watch --self "$LEAD"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "IDLE worker-execute-$A $A done"$'\n'"LIMIT self - $LAT $LEAD" ]; } && ok "the held IDLE fires once the lead hold ends" || no "lead hold ends (rc=$RC): $OUT"

case_; watch --self 'bad id'
[ "$RC" -eq 2 ] && ok "a bad --self id exits 2" || no "bad self (rc=$RC): $ERR"
case_; watch --hold A1A1A1A1
{ [ "$RC" -eq 2 ]; } && ok "a bad --hold id exits 2" || no "bad hold (rc=$RC): $ERR"
case_; run wait --interval 1
[ "$RC" -eq 2 ] && ok "a missing --scratchpad exits 2" || no "missing scratchpad (rc=$RC): $ERR"
case_; run name 'bad id'
[ "$RC" -eq 2 ] && ok "a bad name session id exits 2" || no "bad name id (rc=$RC): $ERR"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
