#!/usr/bin/env bash
# Exercises session-start.sh's compact handoff lookup against a real scratchpad under /tmp/claude-<uid>.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters. Run directly, it supplies its own and prints a RESULT line.
# Every directory it creates is removed, also when a check fails or the run is interrupted. The real ~/.claude is never read.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PASS=0; FAIL=0; FAILED_NAMES=()
  SH_STANDALONE=1
fi

SH_HOOK="$ROOT/session-start.sh"
SH_TMP="/tmp/claude-$(id -u)"
SH_STALE="This handoff could not be marked as used, so it may be stale: trust the transcript over it."
SH_DIRS=()
SH_MADE_TMP=""
SH_WORK=""

_sh_pass() {
  printf '  PASS  session-start-handoff :: %s\n' "$1"
  PASS=$((PASS+1))
}

_sh_fail() {
  printf '  FAIL  session-start-handoff :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("session-start-handoff::$1")
}

# Removes every recorded directory, restoring write permission first so a read-only scratchpad goes too.
_sh_cleanup() {
  local d
  for d in "${SH_DIRS[@]+"${SH_DIRS[@]}"}"; do
    [[ -n "$d" && -e "$d" ]] || continue
    chmod -R u+w "$d" 2>/dev/null
    rm -rf "$d"
  done
  SH_DIRS=()
  SH_WORK=""
  [[ -n "$SH_MADE_TMP" ]] && rmdir "$SH_TMP" 2>/dev/null
  return 0
}

# Sets SH_NAME to a fresh name under SH_TMP and records it for cleanup.
_sh_new() {
  if [[ ! -d "$SH_TMP" ]]; then
    mkdir -p "$SH_TMP" || return 1
    SH_MADE_TMP=1
  fi
  SH_NAME="toolkit-hooktest-$$-$RANDOM$RANDOM"
  SH_DIRS+=("$SH_TMP/$SH_NAME")
}

# Sets SH_WORK to a fresh temp dir used as the hook's cwd and HOME, outside any git repo.
_sh_work() {
  SH_WORK="$(mktemp -d)" || return 1
  SH_DIRS+=("$SH_WORK")
}

# $1 scratchpad dir, $2 handoff marker (empty for no handoff), $3 flow-git-permission content.
_sh_layout() {
  mkdir -p "$1" || return 1
  if [[ -n "$2" ]]; then
    printf '# Compact handoff\nnext: %s\n' "$2" > "$1/compact-handoff.md" || return 1
  fi
  printf '%s\n' "$3" > "$1/flow-git-permission"
}

# $1 session id. Runs the hook on a compact payload. Sets SH_CTX and SH_ERR.
_sh_hook() {
  local out
  out="$(cd "$SH_WORK" && jq -nc --arg s "$1" '{source:"compact",session_id:$s}' \
    | env -u CLAUDE_PLUGIN_ROOT -u TOOLKIT_COMPACT_HANDOFF -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
      HOME="$SH_WORK" bash "$SH_HOOK" 2>"$SH_WORK/stderr")"
  SH_CTX="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  SH_ERR="$(cat "$SH_WORK/stderr" 2>/dev/null)"
}

# $1 label, $2 "twice" to run the hook a second time. One slug, one session, a handoff and a push answer.
# Sets SH_PAD to the scratchpad, SH_CTX1 and SH_CTX to the first and last run's context.
_sh_session() {
  local sid="hooktest-sid-$$-$RANDOM$RANDOM"
  if ! _sh_work || ! _sh_new; then _sh_fail "$1 :: setup failed"; return 1; fi
  SH_PAD="$SH_TMP/$SH_NAME/$sid/scratchpad"
  _sh_layout "$SH_PAD" "HANDOFF-ONE" "push" || { _sh_fail "$1 :: layout failed"; return 1; }
  _sh_hook "$sid"
  SH_CTX1="$SH_CTX"
  [[ "${2:-}" == "twice" ]] && _sh_hook "$sid"
  return 0
}

check_sh_first_run_injects() {
  local label="first-run-injects"
  _sh_session "$label" || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX1" != *"next: HANDOFF-ONE"* ]]; then
    _sh_fail "$label :: the scratchpad handoff was not injected"; return
  fi
  _sh_pass "$label :: the first compaction injects the scratchpad's compact handoff"
}

check_sh_first_run_skips_inference() {
  local label="first-run-skips-inference"
  _sh_session "$label" || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX1" == *"git permission push"* ]]; then
    _sh_fail "$label :: the handoff run also printed the inferred state line"; return
  fi
  _sh_pass "$label :: the handoff run prints no inferred git permission"
}

check_sh_first_run_renames() {
  local label="first-run-renames" renamed=0
  _sh_session "$label" || { _sh_cleanup; return; }
  [[ -f "$SH_PAD/compact-handoff.used.md" && ! -e "$SH_PAD/compact-handoff.md" ]] && renamed=1
  _sh_cleanup
  if [[ $renamed -ne 1 ]]; then
    _sh_fail "$label :: compact-handoff.md was not renamed to compact-handoff.used.md"; return
  fi
  _sh_pass "$label :: the injected handoff is renamed to compact-handoff.used.md"
}

check_sh_second_run_infers_permission() {
  local label="second-run-infers-permission"
  _sh_session "$label" twice || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"git permission push"* ]]; then
    _sh_fail "$label :: the second compaction did not report the recorded push answer"; return
  fi
  _sh_pass "$label :: the second compaction infers state and reports git permission push"
}

check_sh_second_run_no_reinject() {
  local label="second-run-no-reinject"
  _sh_session "$label" twice || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" == *"next: HANDOFF-ONE"* ]]; then
    _sh_fail "$label :: the consumed handoff was injected again"; return
  fi
  _sh_pass "$label :: the second compaction does not inject the consumed handoff"
}

check_sh_second_run_names_consumed() {
  local label="second-run-names-consumed"
  _sh_session "$label" twice || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"An earlier handoff was consumed at a previous compaction."* ]]; then
    _sh_fail "$label :: the inferred line does not say an earlier handoff was consumed"; return
  fi
  _sh_pass "$label :: the second compaction says an earlier handoff was consumed"
}

# $1 label, $2 "dotdot" or "slash". Lays out a scratchpad that a traversing session_id would reach.
# Sets SH_CTX and SH_SAME (1 when the laid-out tree is unchanged after the run).
_sh_traversal() {
  local before after root sid a b
  if ! _sh_work || ! _sh_new; then _sh_fail "$1 :: setup failed"; return 1; fi
  root="$SH_TMP/$SH_NAME"
  if [[ "$2" == "dotdot" ]]; then
    sid="../$SH_NAME"
    _sh_layout "$root/scratchpad" "HANDOFF-TRAVERSAL" "push" || { _sh_fail "$1 :: layout failed"; return 1; }
  else
    a="hooktest-a$RANDOM"; b="hooktest-b$RANDOM"
    sid="$a/$b"
    _sh_layout "$root/$a/$b/scratchpad" "HANDOFF-TRAVERSAL" "push" || { _sh_fail "$1 :: layout failed"; return 1; }
  fi
  before="$(find "$root" | sort)"
  _sh_hook "$sid"
  after="$(find "$root" | sort)"
  SH_SAME=0
  [[ "$before" == "$after" ]] && SH_SAME=1
  return 0
}

check_sh_dotdot_no_handoff() {
  local label="dotdot-no-handoff"
  _sh_traversal "$label" dotdot || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" == *"HANDOFF-TRAVERSAL"* ]]; then
    _sh_fail "$label :: a session_id of ../<dir> injected a handoff"; return
  fi
  _sh_pass "$label :: a session_id of ../<dir> injects no handoff"
}

check_sh_dotdot_no_permission() {
  local label="dotdot-no-permission"
  _sh_traversal "$label" dotdot || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"git permission unasked"* ]]; then
    _sh_fail "$label :: a session_id of ../<dir> read a git permission"; return
  fi
  _sh_pass "$label :: a session_id of ../<dir> reports git permission unasked"
}

check_sh_dotdot_creates_nothing() {
  local label="dotdot-creates-nothing"
  _sh_traversal "$label" dotdot || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ $SH_SAME -ne 1 ]]; then
    _sh_fail "$label :: a session_id of ../<dir> changed the scratchpad tree"; return
  fi
  _sh_pass "$label :: a session_id of ../<dir> leaves the scratchpad tree unchanged"
}

check_sh_slash_no_handoff() {
  local label="slash-no-handoff"
  _sh_traversal "$label" slash || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" == *"HANDOFF-TRAVERSAL"* ]]; then
    _sh_fail "$label :: a session_id of a/b injected a handoff"; return
  fi
  _sh_pass "$label :: a session_id of a/b injects no handoff"
}

check_sh_slash_no_permission() {
  local label="slash-no-permission"
  _sh_traversal "$label" slash || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"git permission unasked"* ]]; then
    _sh_fail "$label :: a session_id of a/b read a git permission"; return
  fi
  _sh_pass "$label :: a session_id of a/b reports git permission unasked"
}

check_sh_slash_creates_nothing() {
  local label="slash-creates-nothing"
  _sh_traversal "$label" slash || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ $SH_SAME -ne 1 ]]; then
    _sh_fail "$label :: a session_id of a/b changed the scratchpad tree"; return
  fi
  _sh_pass "$label :: a session_id of a/b leaves the scratchpad tree unchanged"
}

check_sh_two_slugs_one_injected() {
  local label="two-slugs-one-injected" count=0 sid="hooktest-sid-$$-$RANDOM$RANDOM" first second
  if ! _sh_work || ! _sh_new; then _sh_fail "$label :: setup failed"; _sh_cleanup; return; fi
  first="$SH_TMP/$SH_NAME/$sid/scratchpad"
  _sh_new || { _sh_fail "$label :: setup failed"; _sh_cleanup; return; }
  second="$SH_TMP/$SH_NAME/$sid/scratchpad"
  if ! _sh_layout "$first" "HANDOFF-FIRST" "push" || ! _sh_layout "$second" "HANDOFF-SECOND" "push"; then
    _sh_fail "$label :: layout failed"; _sh_cleanup; return
  fi
  _sh_hook "$sid"
  _sh_cleanup
  [[ "$SH_CTX" == *"HANDOFF-FIRST"* ]] && count=$((count+1))
  [[ "$SH_CTX" == *"HANDOFF-SECOND"* ]] && count=$((count+1))
  if [[ $count -ne 1 ]]; then
    _sh_fail "$label :: $count of the two slug directories' handoffs were injected, want exactly 1"; return
  fi
  _sh_pass "$label :: two slug directories for one session_id inject exactly one handoff"
}

# $1 label. A handoff in a read-only (555) scratchpad. Sets SH_CTX and SH_ERR.
_sh_readonly() {
  local sid="hooktest-sid-$$-$RANDOM$RANDOM" pad
  if ! _sh_work || ! _sh_new; then _sh_fail "$1 :: setup failed"; return 1; fi
  pad="$SH_TMP/$SH_NAME/$sid/scratchpad"
  if ! _sh_layout "$pad" "HANDOFF-READONLY" "push" || ! chmod 555 "$pad"; then
    _sh_fail "$1 :: layout failed"; return 1
  fi
  _sh_hook "$sid"
}

check_sh_readonly_warns() {
  local label="readonly-warns"
  _sh_readonly "$label" || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"$SH_STALE"* ]]; then
    _sh_fail "$label :: a handoff that could not be renamed carries no stale warning"; return
  fi
  _sh_pass "$label :: a handoff in a read-only scratchpad carries the stale warning"
}

check_sh_readonly_logs() {
  local label="readonly-logs"
  _sh_readonly "$label" || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_ERR" != *"could not rename"* ]]; then
    _sh_fail "$label :: a failed rename logged nothing to stderr"; return
  fi
  _sh_pass "$label :: a failed rename logs one line to stderr"
}

# $1 label, $2 flow-git-permission content. No handoff, so the hook takes the inferred path. Sets SH_CTX.
_sh_permission() {
  local sid="hooktest-sid-$$-$RANDOM$RANDOM"
  if ! _sh_work || ! _sh_new; then _sh_fail "$1 :: setup failed"; return 1; fi
  _sh_layout "$SH_TMP/$SH_NAME/$sid/scratchpad" "" "$2" || { _sh_fail "$1 :: layout failed"; return 1; }
  _sh_hook "$sid"
}

check_sh_permission_padded() {
  local label="permission-padded"
  _sh_permission "$label" "  push  " || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"git permission push."* ]]; then
    _sh_fail "$label :: a push answer with surrounding spaces did not read as push"; return
  fi
  _sh_pass "$label :: a push answer with surrounding spaces reads as push"
}

check_sh_permission_inner_space() {
  local label="permission-inner-space"
  _sh_permission "$label" "pu sh" || { _sh_cleanup; return; }
  _sh_cleanup
  if [[ "$SH_CTX" != *"git permission none."* ]]; then
    _sh_fail "$label :: an answer of 'pu sh' did not read as none"; return
  fi
  _sh_pass "$label :: an answer with an inner space reads as none"
}

run_session_start_handoff_checks() {
  check_sh_first_run_injects
  check_sh_first_run_skips_inference
  check_sh_first_run_renames
  check_sh_second_run_infers_permission
  check_sh_second_run_no_reinject
  check_sh_second_run_names_consumed
  check_sh_dotdot_no_handoff
  check_sh_dotdot_no_permission
  check_sh_dotdot_creates_nothing
  check_sh_slash_no_handoff
  check_sh_slash_no_permission
  check_sh_slash_creates_nothing
  check_sh_two_slugs_one_injected
  check_sh_readonly_warns
  check_sh_readonly_logs
  check_sh_permission_padded
  check_sh_permission_inner_space
}

if [[ -n "${SH_STANDALONE:-}" ]]; then
  trap _sh_cleanup EXIT
  run_session_start_handoff_checks
  echo
  echo "RESULT: $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]]
  exit
fi
