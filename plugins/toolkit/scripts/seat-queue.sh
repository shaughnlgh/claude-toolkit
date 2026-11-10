#!/usr/bin/env bash
# Keeps the seat queue of a repo's main checkout in its git common dir. Exit codes per subcommand in docs/scripts.md.
set -fuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SEAT="$HERE/seat-check.sh"
QUEUE=toolkit-seat-queue  # every linked worktree resolves the same git common dir
ENTRY='^[0-9]{10}-[A-Za-z0-9-]{1,64}$'  # <join epoch seconds>-<sessionId>
STALE=10  # seconds: a verdict holds the grant lock for milliseconds, so an older lock belongs to a killed process
SETTLE=5  # seconds a registry rewrite can hide a live row: the sweep's second-miss floor and the first join's re-read delay
MISS_MAX=600  # seconds: a second miss counts only inside this window after the first

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
finish() { printf '%s\n' "$2"; exit "$1"; }
to_secs() {  # minutes by default, seconds with a trailing s, as watch-mr.sh reads --bound
  [[ $2 =~ ^([0-9]+)(s?)$ ]] || die "bad duration: $2"
  local n=$((10#${BASH_REMATCH[1]}))
  [ -n "${BASH_REMATCH[2]}" ] || n=$((n * 60))
  printf -v "$1" '%s' "$n"
}
age() {  # seconds since the mtime of $1, GNU stat first and BSD stat second
  local m; m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
  echo $(($(date +%s) - m))
}

sub=${1:-}; [ $# -gt 0 ] && shift
repo="" self="" parent="" bound=180 interval=30
while [ $# -gt 0 ]; do
  case $1 in
    --self) [ $# -ge 2 ] || die "--self needs a session id"; self=$2; shift 2 ;;
    --parent) [ $# -ge 2 ] || die "--parent needs a session id"; parent=$2; shift 2 ;;
    --bound) [ $# -ge 2 ] || die "--bound needs a value"; bound=$2; shift 2 ;;
    --interval) [ $# -ge 2 ] || die "--interval needs a value"; interval=$2; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$repo" ] || die "one repo path only"; repo=$1; shift ;;
  esac
done
case $sub in join | leave | list | wait) ;; *) die "usage: seat-queue.sh <join|leave|list|wait> <repo path> [--self <sessionId>] [--parent <sessionId>] [--bound <n> (minutes, default 180)] [--interval <seconds>]" ;; esac
[ -n "$repo" ] || die "missing repo path"
[ "$sub" = list ] || [[ $self =~ ^[A-Za-z0-9-]{1,64}$ ]] || die "bad or missing --self: $self"
[ -z "$parent" ] || [[ $parent =~ ^[A-Za-z0-9-]{1,64}$ ]] || die "bad --parent: $parent"
common=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null) || die "not a git repo: $repo"
common=$(cd "$repo" && cd "$common" 2>/dev/null && pwd -P) || die "cannot resolve the git common dir"
Q="$common/$QUEUE"
LOCK="$Q/.grant"

entries() { LC_ALL=C ls -1 "$Q" 2>/dev/null | grep -E "$ENTRY"; }
mine() { entries | grep -E "^[0-9]{10}-$self\$"; }
drop_mine() { local f; for f in $(mine); do rm -f "$Q/$f"; done; rm -f "$Q/.miss-$self"; }
# No --self: the session's own holder line tells it that it sits in the main checkout.
seat() { SEAT_OUT=$(bash "$SEAT" "$repo" --live); case $? in 0 | 10) ;; *) return 1 ;; esac; }  # a killed or missing seat check prints no rows, which would read as every session gone
sids() { printf '%s\n' "$SEAT_OUT" | sed -n "s/^$1: //p" | awk -F'\t' '{ print $4 }'; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
lock() {  # mkdir is atomic, so one verdict at a time reads the entry states and writes a mark
  local tries=0 a
  until mkdir "$LOCK" 2>/dev/null; do
    if a=$(age "$LOCK") && [ "$a" -ge "$STALE" ] && mkdir "$LOCK.break" 2>/dev/null; then  # one breaker re-reads the age, so no contender removes a fresh lock
      a=$(age "$LOCK") && [ "$a" -ge "$STALE" ] && rmdir "$LOCK" 2>/dev/null && { rmdir "$LOCK.break"; continue; }
      rmdir "$LOCK.break"  # a lock rmdir cannot remove counts as a try, so the 15-try cap still ends the loop
    fi
    a=$(age "$LOCK.break") && [ "$a" -ge "$STALE" ] && rmdir "$LOCK.break" 2>/dev/null
    tries=$((tries + 1)); [ "$tries" -lt 15 ] || return 1
    sleep 1
  done
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT
  trap 'exit 130' INT TERM HUP
}
unlock() { rmdir "$LOCK" 2>/dev/null; trap - EXIT INT TERM HUP; }
sweep() {  # $1 the listing taken before the seat read, $2 the live session ids
  local f s a
  for f in $1; do
    s=${f#*-}
    if has "$2" "$s"; then rm -f "$Q/.miss-$s"; continue; fi
    a=$(age "$Q/.miss-$s") || a=""
    if [ -n "$a" ] && [ "$a" -ge "$SETTLE" ] && [ "$a" -lt "$MISS_MAX" ]; then rm -f "$Q/$f" "$Q/.miss-$s"
    elif [ -z "$a" ] || [ "$a" -ge "$MISS_MAX" ]; then touch "$Q/.miss-$s"
    fi
  done
}

verdict() {  # prints one status line, returns 0 TURN, 10 WAIT, 11 DEADLOCK, 13 LEFT, 14 DIRTY, 15 PARENT, 2 a failed write (die), 3 seat check failed, 4 lock stayed taken
  local snap live main_sids hold dirty f st s own_entry="" own_state="" seen="" dl="" queued="" ahead=0 others unq=0 par=""
  snap=$(entries)  # listed before the seat read, so a join that lands during the read is never removed
  seat || return 3
  live=$(sids live); main_sids=$(sids holder); hold=$main_sids
  dirty=$(printf '%s\n' "$SEAT_OUT" | sed -n 's/^dirty: //p')
  lock || return 4
  if [ "$sub" = join ] && [ -n "${new:-}" ] && ! has "$live" "$self"; then drop_mine; unlock; echo LEFT; return 13; fi
  sweep "$snap" "$live"
  while read -r f; do
    [ -n "$f" ] || continue
    s=${f#*-}; st=waiting; [ -s "$Q/$f" ] && st=seated
    if [ "$s" = "$self" ]; then [ -n "$own_entry" ] || { own_entry=$f; own_state=$st; }; seen=1; continue; fi
    queued+="$s"$'\n'
    if [ "$st" = seated ]; then hold+=$'\n'"$s"  # a seated entry holds the seat whatever cwd the agents list reports
    elif has "$main_sids" "$s"; then dl=$s
    fi
    [ "$st" = waiting ] && [ -z "$seen" ] && ahead=$((ahead + 1))
  done <<< "$(entries)"
  if [ -z "$own_entry" ]; then unlock; echo LEFT; return 13; fi
  others=$(printf '%s\n' $hold | grep -vxF -- "$self" | sort -u | grep -c .)
  for s in $main_sids; do
    [ "$s" = "$self" ] || has "$queued" "$s" || { unq=$((unq + 1)); [ "$s" != "$parent" ] || par=$s; }
  done
  if [ -n "$par" ]; then drop_mine; unlock; echo "PARENT $par"; return 15; fi  # a parent stays until its user ends it, so a wait on it would run to the bound
  if has "$main_sids" "$self"; then  # sits in the main checkout and holds the seat by its cwd, so order does not apply
    if [ -n "$dl" ]; then unlock; echo "DEADLOCK $dl"; return 11; fi
    ahead=0
  fi
  if [ "$ahead" -eq 0 ] && [ "$others" -eq 0 ] && has "$live" "$self"; then  # a self row that one read missed waits a round
    [ "$own_state" = seated ] || printf 'seated\n' > "$Q/$own_entry" || { unlock; die "cannot mark $Q/$own_entry seated"; }
    unlock
    [ "$dirty" = 0 ] && { echo TURN; return 0; }
    echo "DIRTY $dirty"; return 14
  fi
  [ "$own_state" = waiting ] || : > "$Q/$own_entry"
  unlock
  echo "WAIT $ahead $others $unq $dirty"; return 10
}

case $sub in
  leave) [ -d "$Q" ] || exit 0; lock || die "the queue lock $LOCK stayed taken"; drop_mine; unlock; exit 0 ;;
  list)
    seat || die "the seat check could not run"
    queued=""
    for f in $(entries); do
      s=${f#*-}; tag=waiter; [ -s "$Q/$f" ] && tag=seated; queued+="$s"$'\n'
      printf '%s\n' "$SEAT_OUT" | sed -n 's/^live: //p' | awk -F'\t' -v s="$s" -v t="$tag" '$4 == s { print t ": " $0 }'
    done
    printf '%s\n' "$SEAT_OUT" | sed -n 's/^holder: //p' | while IFS= read -r l; do
      has "$queued" "$(printf '%s\n' "$l" | awk -F'\t' '{ print $4 }')" || printf 'unqueued: %s\n' "$l"
    done
    exit 0 ;;
  join)
    mkdir -p "$Q" || die "cannot create $Q"
    new=""
    if [ -z "$(mine)" ]; then ent="$(date +%s)-$self"; : > "$Q/$ent" || die "cannot write to $Q"; new=1; fi
    line=$(verdict); rc=$?
    if [ "$rc" = 13 ] && [ -n "$new" ]; then  # one read can miss a live row, so a first join reads twice before it gives up
      sleep "$SETTLE"; : > "$Q/$ent" || die "cannot write to $Q"
      line=$(verdict); rc=$?
    fi
    case $rc in
      3 | 4) [ -z "$new" ] || drop_mine
        [ "$rc" = 3 ] && die "the seat check could not run"
        die "the queue lock $LOCK stayed taken" ;;
      2) exit 2 ;;
      13) [ -n "$new" ] || die "the queue entry for session $self was removed before the verdict read it, by a leave or by a sweep after two reads missed its live row"
        die "session $self has no live row in the agents list on two reads: only an interactive session lists a pid, or this shell cannot signal other sessions' pids (a sandboxed shell), so seat-check sees none live" ;;
    esac
    finish "$rc" "$line" ;;
  wait)
    to_secs bound_s "$bound"
    [[ $interval =~ ^[0-9]+$ ]] || die "bad interval: $interval"
    interval=$((10#$interval)); [ "$interval" -ge 1 ] || interval=1
    [ -d "$Q" ] || finish 13 LEFT
    fails=0 last="unknown unknown unknown unknown"
    while :; do
      line=$(verdict); rc=$?
      case $rc in
        0 | 11 | 13 | 14 | 15) finish "$rc" "$line" ;;
        2) exit 2 ;;
        3 | 4) fails=$((fails + 1)); [ "$fails" -lt 5 ] || { [ "$rc" = 3 ] && what="seat check" || what="queue lock"; echo "error: the $what failed five rounds in a row" >&2; exit 3; } ;;
        *) fails=0; last=${line#WAIT } ;;
      esac
      [ "$SECONDS" -lt "$bound_s" ] || finish 12 "BOUND $((SECONDS / 60)) $last"
      sleep "$interval"
    done ;;
esac
