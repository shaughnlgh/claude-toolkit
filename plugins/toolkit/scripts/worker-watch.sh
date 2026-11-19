#!/usr/bin/env bash
# The lead's bounded watch over the worker sessions its scratchpad's workers file records. Exit codes in docs/scripts.md.
set -uo pipefail

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
fail() { printf 'error: %s\n' "$1" >&2; exit 3; }
finish() { printf '%s\n' "$2"; exit "$1"; }
USAGE="usage: worker-watch.sh wait --scratchpad <dir> [--bound <n>] [--interval <seconds>] [--push-after <seconds>] [--start-grace <seconds>] [--hold <id>]... | list --scratchpad <dir> | name <sessionId>"
# Minutes by default, seconds with a trailing s, as in watch-mr.sh.
to_secs() {
  [[ $2 =~ ^([0-9]+)(s?)$ ]] || die "bad duration: $2"
  local n=$((10#${BASH_REMATCH[1]}))
  [ -n "${BASH_REMATCH[2]}" ] || n=$((n * 60))
  printf -v "$1" '%s' "$n"
}
age() {  # seconds since the mtime of $1, GNU stat first and BSD stat second
  local m; m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
  echo $(($(date +%s) - m))
}
secs() { [[ $2 =~ ^[0-9]+$ ]] || die "bad $1: $2"; printf '%s' "$((10#$2))"; }

[ $# -ge 1 ] || die "$USAGE"
sub=$1; shift
case $sub in wait | list | name) ;; *) die "unknown subcommand: $sub. $USAGE" ;; esac
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$HERE/lib/agents-list.sh" 2>/dev/null || fail "scripts/lib/agents-list.sh not found"
. "$HERE/../hooks/lib/session-scratchpad.sh" 2>/dev/null || fail "hooks/lib/session-scratchpad.sh not found"

# input errors on empty stdin, so a stalled call that printed nothing counts as a failed read.
read_rows() { agents_json --all | jq -cn 'input | if type == "array" then . else error("not an array") end' 2>/dev/null; }
CLEAN='def clean: tostring | gsub("[\t\r\n]"; " ") | .[0:64];
def dash: if . == null or . == "" then "-" else clean end;'
# The first workers line of an id wins.
OWNED='def owned: $ws | split("\n") | map(split("\t") | select(length >= 2 and (.[0] | test("^[0-9a-f]{8}$")))
  | {id: .[0], name: (.[1] | clean), type: (.[2] | dash), plan: (.[3] | dash), epoch: (.[4] // "")})
  | reduce .[] as $w ([]; if any(.[]; .id == $w.id) then . else . + [$w] end);'
STORED='def stored: $st | split("\n") | map(split("\t") | select(length == 4 and .[0] != "unowned")
  | {key: .[0], value: {sig: .[1], since: (.[2] | tonumber? // $now), pushed: (.[3] | tonumber? // 0)}}) | from_entries;
def stored_unowned: [$st | split("\n")[] | split("\t") | select(.[0] == "unowned") | .[1] // ""] | first // "";'
# A row with no pid keeps its state after Claude Code ends an unattached worker, so state is read, never kill -0.
SIG='def sig($id): (map(objects | select(.id == $id)) | first) as $r
  | if $r == null then "gone"
    elif $r.waitingFor == "permission prompt" or $r.waitingFor == "sandbox request" then "permission"
    elif ($r.waitingFor // "") != "" or $r.status == "waiting" or $r.state == "blocked" then "input"
    elif $r.state == "failed" or $r.state == "stopped" then "gone"
    elif $r.state == "working" and $r.status != "idle" then "busy"
    else "idle:" + ($r.state // "-" | clean) end;'

if [ "$sub" = name ]; then
  [ $# -eq 1 ] && [[ $1 =~ ^[A-Za-z0-9-]{1,64}$ ]] || die "bad session id. $USAGE"
  command -v jq >/dev/null 2>&1 || fail "jq not found"
  rows=$(read_rows) || fail "agents source gave no JSON array"
  # The full name, uncut, because a worker sends to it.
  n=$(jq -r --arg s "$1" 'first(.[] | objects | select(.sessionId == $s and .pid != null) | .name // empty | tostring | gsub("[\t\r\n]"; " "))' <<<"$rows")
  [ -n "$n" ] || finish 11 NONE
  finish 0 "name: $n"
fi

scratchpad="" bound=60 interval=15 push_after=120 grace=300 holds=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "$1 needs a value"
  case $sub:$1 in
    *:--scratchpad) scratchpad=$2 ;;
    wait:--bound) bound=$2 ;;
    wait:--interval) interval=$(secs --interval "$2") || exit 2 ;;
    wait:--push-after) push_after=$(secs --push-after "$2") || exit 2 ;;
    wait:--start-grace) grace=$(secs --start-grace "$2") || exit 2 ;;
    wait:--hold) [[ $2 =~ ^[0-9a-f]{8}$ ]] || die "bad --hold: $2"; holds+=" $2" ;;
    *) die "unknown option: $1. $USAGE" ;;
  esac
  shift 2
done
[ -d "$scratchpad" ] && [ "$(basename "$scratchpad")" = scratchpad ] || die "bad or missing --scratchpad: $scratchpad. $USAGE"
self=$(basename "$(dirname "$scratchpad")")
[[ $self =~ ^[A-Za-z0-9-]{1,64}$ ]] || die "bad --scratchpad: its parent is no session id"
to_secs bound_s "$bound"
[ "$interval" -ge 1 ] || interval=1
command -v jq >/dev/null 2>&1 || fail "jq not found"
W="$scratchpad/$WORKERS_FILE"
read_workers() { [ -e "$W" ] || return 0; cat "$W" 2>/dev/null; }

if [ "$sub" = list ]; then
  ws=$(read_workers) || fail "cannot read $W"
  rows=$(read_rows) || fail "agents source gave no JSON array"
  jq -r --arg ws "$ws" "$CLEAN$OWNED"' . as $rows | owned[] | . as $w | ($rows | map(objects | select(.id == $w.id)) | first) as $r
    | select($r != null and ($r.pid != null or $r.state == "working" or $r.state == "blocked"))
    | "worker: \($w.name)\t\($w.id)\t\($w.type)\t\($w.plan)\t\($r.status | dash)\t\($r.state | dash)\t\($r.waitingFor | dash)"' <<<"$rows" || fail "cannot read the agents rows"
  exit 0
fi

L="$scratchpad/worker-watch.lock"
if ! mkdir "$L" 2>/dev/null; then
  a=$(age "$L/pid" || age "$L") || a=0
  [ "$a" -ge $((3 * interval)) ] || finish 12 RUNNING
  rm -f "$L/pid"; rmdir "$L" 2>/dev/null
  mkdir "$L" 2>/dev/null || finish 12 RUNNING
fi
trap 'rm -f "$L/pid"; rmdir "$L" 2>/dev/null' EXIT
trap 'exit 130' INT TERM HUP
echo $$ > "$L/pid" || fail "cannot write $L/pid"

S="$scratchpad/worker-watch.state"
start=$(date +%s)
old=$(cat "$S" 2>/dev/null)
held=$(jq -cn --arg st "$old" --arg h "$holds" --argjson now "$start" "$STORED"' stored as $o
  | [$h | split(" ")[] | select(length > 0) | {(.): ($o[.].sig // "")}] | add // {}') || fail "cannot read $S"

# Event order within one exit: NEEDS permission 0, NEEDS input 1, PUSH 2, IDLE 3, NOSTART 4, GONE 5, UNOWNED 6.
ROUND="$CLEAN$OWNED$STORED$SIG"'
def ev($r; $i; $line): .ev += [{r: $r, i: $i, line: $line}];
def needs($n; $w; $i): ev(if $n == "permission" then 0 else 1 end; $i; "NEEDS \($w.name) \($w.id) \($n)");
. as $rows | stored as $old
| ([$listed | split("\n")[] | select(length > 0) | {(.): true}] | add // {}) as $lst
| reduce (owned | to_entries[]) as $e ({state: {}, ev: [], held: $held, open: false};
    # A gone worker is read again each round, because one read can miss a live row and a stopped worker can restart.
    $e.key as $i | $e.value as $w | $old[$w.id] as $s
      | ($rows | sig($w.id)) as $n
      | (if $s == null then
          if $n == "busy" or $n == "permission" or $n == "input" then
            .state[$w.id] = {sig: $n, since: $now, pushed: 0} | if $n == "busy" then . else needs($n; $w; $i) end
          elif $now - (($w.epoch | tonumber?) // $start) >= $grace then
            .state[$w.id] = {sig: $n, since: $now, pushed: 0} | ev(4; $i; "NOSTART \($w.name) \($w.id)")
          else . end
        elif $s.sig != $n then
          .state[$w.id] = {sig: $n, since: $now, pushed: 0}
          | if $n == "permission" or $n == "input" then needs($n; $w; $i)
            elif $n | startswith("idle:") then ev(3; $i; "IDLE \($w.name) \($w.id) \($n[5:])")
            elif $n == "gone" and ($s.sig | startswith("idle:") | not) then ev(5; $i; "GONE \($w.name) \($w.id)")
            else . end
        elif ($n == "permission" or $n == "input") and $s.pushed == 0 and $now - $s.since >= $pa then
          .state[$w.id] = ($s | .pushed = 1) | ev(2; $i; "PUSH \($w.name) \($w.id) \($n) \(($now - $s.since) / 60 | floor)m")
        else .state[$w.id] = $s end)
      | .state[$w.id].sig as $k
      | (if $k == "gone" or ($k != null and ($k | startswith("idle:")) and $k == $n) then . else .open = true end)
      | if .held | has($w.id) then (if .held[$w.id] == $n then .open = true else del(.held[$w.id]) end) else . end)
| ($rows | map(objects | select(.kind == "background" and .pid != null and .sessionId != $self
    and ($lst[(.id // "") | tostring] | not))) | sort_by(.id | tostring)) as $u
| ($u | map(.id | clean) | join(",")) as $uids
| if $uids != stored_unowned and ($u | length) > 0
  then ev(6; 0; "UNOWNED \($u | length): \($u | map("\(.name | dash) (\(.id | clean))") | join(", "))") else . end
| {events: (.ev | sort_by([.r, .i]) | map(.line)), held, open,
   text: ([owned[] as $w | .state[$w.id] // empty | "\($w.id)\t\(.sig)\t\(.since)\t\(.pushed)"]
     + (if $uids == "" then [] else ["unowned\t\($uids)"] end) | join("\n"))}'

MAX_BAD_ROUNDS=3   # one stalled claude agents call must not end a 60 minute watch
bad=0
pause() { [ $(($(date +%s) - start)) -lt "$bound_s" ] || finish 10 BOUND; sleep "$interval"; }
while :; do
  touch "$L/pid"
  ws=$(read_workers) || fail "cannot read $W"
  rows=$(read_rows) || {
    bad=$((bad + 1)); [ "$bad" -lt "$MAX_BAD_ROUNDS" ] || fail "agents source gave no JSON array in $MAX_BAD_ROUNDS rounds in a row"
    pause; continue
  }
  bad=0
  # Every live session's workers file marks its ids as owned, so another lead's workers never read as unowned.
  listed=$(cut -f1 <<<"$ws")
  while IFS= read -r sid; do
    f=$(session_workers_file "$sid")
    [ -z "$f" ] || listed+=$'\n'"$(cut -f1 "$f" 2>/dev/null)"
  done < <(jq -r '.[] | objects | select(.pid != null) | .sessionId | strings | select(test("^[A-Za-z0-9_-]+$"))' <<<"$rows")
  res=$(jq -c --arg ws "$ws" --arg st "$old" --arg listed "$listed" --arg self "$self" --argjson held "$held" \
    --argjson now "$(date +%s)" --argjson start "$start" --argjson grace "$grace" --argjson pa "$push_after" "$ROUND" <<<"$rows") \
    || fail "the watch round could not read the agents rows"
  text=$(jq -r .text <<<"$res"); held=$(jq -c .held <<<"$res")
  if [ "$text" != "$old" ]; then
    tmp=$(mktemp "$scratchpad/.worker-watch.state.XXXXXX") && printf '%s\n' "$text" > "$tmp" && mv "$tmp" "$S" || fail "cannot write $S"
    old=$text
  fi
  out=$(jq -r '.events[]' <<<"$res")
  [ -z "$out" ] || finish 0 "$out"
  [ "$(jq -r .open <<<"$res")" = true ] || finish 11 NONE
  pause
done
