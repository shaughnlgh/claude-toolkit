#!/usr/bin/env bash
# Fills a worker type's template, starts the worker session with claude --bg and records it in the lead's scratchpad. Exit codes in docs/scripts.md.
set -uo pipefail

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
fail() { printf 'error: %s\n' "$1" >&2; exit 3; }
finish() { printf '%s\n' "$2"; exit "$1"; }
USAGE="usage: worker-spawn.sh --scratchpad <dir> --type <investigate|plan|execute|ship|chain> --key <key> --plan <planName|-> --note <plan note path|-> --lead-name <name> --model <model> --effort <level> --task-file <path> [--worktree <name>] [--cwd <dir>]"

scratchpad="" type="" key="" plan="" note="" lead_name="" model="" effort="" task_file="" wt="" cwd=.
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "$1 needs a value"
  case $1 in
    --scratchpad) scratchpad=$2 ;;
    --type) type=$2 ;;
    --key) key=$2 ;;
    --plan) plan=$2 ;;
    --note) note=$2 ;;
    --lead-name) lead_name=$2 ;;
    --model) model=$2 ;;
    --effort) effort=$2 ;;
    --task-file) task_file=$2 ;;
    --worktree) wt=$2 ;;
    --cwd) cwd=$2 ;;
    *) die "unknown option: $1" ;;
  esac
  shift 2
done

[ -d "$scratchpad" ] && [ "$(basename "$scratchpad")" = scratchpad ] || die "bad --scratchpad: $scratchpad. $USAGE"
self=$(basename "$(dirname "$scratchpad")")
[[ $self =~ ^[A-Za-z0-9-]{1,64}$ ]] || die "bad --scratchpad: its parent is no session id"
case $type in investigate | plan | execute | ship | chain) ;; *) die "bad --type: $type. $USAGE" ;; esac
[[ $key =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || die "bad --key: $key"
[ "$plan" = - ] || [[ $plan =~ ^[a-z0-9][a-z0-9-]{0,99}$ ]] || die "bad --plan: $plan"
case $type:$plan in execute:- | ship:- | chain:-) die "--type $type takes a plan name in --plan" ;; esac  # its ship trigger names the plan
if [ "$type" = investigate ]; then
  [ "$note" = - ] || die "an investigate worker takes --note -"
else
  [ -f "$note" ] && [[ $(basename "$note") =~ ^plan\ -\ [a-z0-9][a-z0-9-]*\.md$ ]] && ! [[ $note =~ [[:cntrl:]] ]] || die "bad --note: $note"
  note="$(cd "$(dirname "$note")" && pwd)/$(basename "$note")"  # the worker's working directory differs from the lead's
fi
NAME_BAD='["\[:cntrl:]]'  # a backslash inside an ERE bracket is literal
[ "${#lead_name}" -ge 1 ] && [ "${#lead_name}" -le 80 ] && ! [[ $lead_name =~ $NAME_BAD ]] && [[ $lead_name != *'{{'* ]] || die "bad --lead-name: 1 to 80 characters with no double quote, backslash, control character or {{"
MODEL_RE='^[A-Za-z][A-Za-z0-9.:_-]{0,79}(\[1m\])?$'  # the model_ok rule of resolve-models.sh, capped at 80 characters
[ -n "$model" ] || die "missing --model: the worker sessions' model is the user's answer, never a default"
[[ $model =~ $MODEL_RE ]] && [ "$model" != inherit ] && [[ $model != *[Hh][Aa][Ii][Kk][Uu]* ]] || die "bad --model: $model"
[ -n "$effort" ] || die "missing --effort: the worker sessions' effort is the user's answer, never a default"
[[ $effort =~ ^(low|medium|high|xhigh|max)$ ]] || die "bad --effort: $effort"
[ -z "$wt" ] || [[ $wt =~ ^[A-Za-z0-9._-]{1,100}$ ]] || die "bad --worktree: $wt"
cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || die "bad --cwd: not a directory"
[ -f "$task_file" ] && [ -s "$task_file" ] && [ "$(wc -c < "$task_file")" -le 4000 ] && ! grep -qF '{{' "$task_file" || die "bad --task-file: a non-empty file of at most 4000 bytes with no {{"
command -v jq >/dev/null 2>&1 || die "jq not found"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
. "$HERE/lib/agents-list.sh" 2>/dev/null || die "scripts/lib/agents-list.sh not found"
. "$ROOT/hooks/lib/session-scratchpad.sh" 2>/dev/null || die "hooks/lib/session-scratchpad.sh not found"
shopt -u patsub_replacement 2>/dev/null   # bash 5.2 reads & in a ${x//p/r} replacement as the match
tmpl="$ROOT/templates/worker-$type.md"  # --type chain runs a direct-chain note's route in a worker session
[ -s "$tmpl" ] || fail "templates/worker-$type.md not found"
ceiling="" run_opts="" note_text=none
if [ "$note" != - ]; then
  note_text=$note
  fm=$(awk '{ sub(/\r$/, "") } NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f' "$note")
  fmv() {  # strips and unquotes as validate-plan.py's unquote does
    local v; v=$(sed -n "s/^$1:[[:space:]]*//p" <<<"$fm" | head -1); v=${v%"${v##*[![:space:]]}"}
    [[ $v =~ ^\"(.*)\"$ || $v =~ ^\'(.*)\'$ ]] && v=${BASH_REMATCH[1]}
    printf '%s' "$v"
  }
  ceiling=$(fmv ceiling)
  for k in ceiling nits tests e2e tag_merge thread_mode worker_model verifier_model verifier_effort session_model session_effort; do
    v=$(fmv "$k"); [ -n "$v" ] && run_opts+="${run_opts:+, }$k: $v"
  done
fi
case $type in plan | investigate) ceiling=${ceiling:-none} ;; esac
# The ceiling is the user's permission given in advance, so a worker never starts without one.
case $ceiling in none | mr | merge) ;; *) die "the plan note records no ceiling of none, mr or merge" ;; esac
prompt=$(cat "$tmpl")
fill() { prompt=${prompt//"{{$1}}"/$2}; }
fill lead_name "$lead_name"; fill lead_session_id "$self"; fill key "$key"; fill plan_name "$plan"
fill plan_note "$note_text"; fill ceiling "$ceiling"; fill run_options "${run_opts:-ceiling: $ceiling}"
fill plugin_root "$ROOT"; fill task "$(cat "$task_file")"
# No filled value may hold {{, so a placeholder left now is one the template misnames.
left=$(grep -oE '\{\{[a-z_]+\}\}' <<<"$prompt" | grep -vx '{{worker_name}}' | head -1)
[ -z "$left" ] || die "unfilled placeholder $left in templates/worker-$type.md"
# grep reads all of the help text, so claude never takes a SIGPIPE that pipefail would report.
claude --help 2>/dev/null | grep -e '--bg' >/dev/null || finish 12 NOBG
rec="$scratchpad/$WORKER_SPAWN_MODE_FILE"
# The lead writes the task file before each spawn call, so a record older than it came from an earlier spawn.
[ -f "$rec" ] && ! [ "$task_file" -nt "$rec" ] || finish 13 NOMODE
mode=$(sed -n 's/^permission_mode: //p' "$rec")
case $mode in default) mode=manual ;; plan | acceptEdits | auto | dontAsk | bypassPermissions) ;; *) finish 13 NOMODE ;; esac
rows=""
for try in 1 2 3; do   # a single claude agents call can stall past the 3 s cap
  # input errors on empty stdin, so a stalled call that printed nothing counts as a failed read.
  rows=$(agents_json --all | jq -cn 'input | if type == "array" then . else error("not an array") end' 2>/dev/null) && break
  rows=""; [ "$try" -eq 3 ] || sleep 1
done
[ -n "$rows" ] || fail "agents source gave no JSON array in 3 reads"
base="worker-$type-$key" name=$base n=1
# A stopped worker keeps its row and name until claude rm, and a reply in agent view restarts it.
while jq -e --arg n "$name" 'any(.[]; .name == $n)' <<<"$rows" >/dev/null; do
  n=$((n + 1)); [ "$n" -le 9 ] || fail "no free name after $base-9"; name="$base-$n"
done
fill worker_name "$name"
args=(--bg -n "$name" --permission-mode "$mode" --model "$model" --effort "$effort")
# Claude Code opens an existing worktree of this name, so a rerun lands in the plan's worktree.
[ -n "$wt" ] && args+=(-w "$wt")
cache=$(cd "$HOME/.claude/plugins/cache" 2>/dev/null && pwd -P)
# A lead that loaded this plugin by path gets a worker on the same copy.
[ -n "$cache" ] && [[ $ROOT/ == "$cache"/* ]] || args+=(--plugin-dir "$ROOT")
out=$(cd "$cwd" && claude "${args[@]}" "$prompt" 2>&1) || fail "claude --bg exited non-zero: $(grep -v '^Starting background service' <<<"$out" | head -1)"
# The start line reads "backgrounded · <id> · <name>".
id=$(tr -s ' \t' '\n\n' <<<"$out" | grep -m1 -xE '[0-9a-f]{8}')
# claude --bg exited 0, so the worker runs even when it cannot be recorded, and a failed spawn would invite a second run.
unrecorded() { printf 'error: %s\n' "$1" >&2; finish 14 "UNRECORDED $name"; }
[ -n "$id" ] || unrecorded "claude --bg printed no 8-hex id"
printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$type" "$plan" "$(date +%s)" >> "$scratchpad/$WORKERS_FILE" || unrecorded "cannot write $scratchpad/$WORKERS_FILE"
finish 0 "STARTED $id $name"
