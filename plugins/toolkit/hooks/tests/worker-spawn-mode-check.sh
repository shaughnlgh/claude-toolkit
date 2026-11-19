#!/usr/bin/env bash
# Exercises worker-spawn-mode.sh against real scratchpads under /tmp/claude-<uid>, which JSON fixtures cannot create or read back.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters. Run directly, it supplies its own and prints a RESULT line.
# The directories it creates are removed inline at the end, because run-all.sh owns the EXIT trap.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PASS=0; FAIL=0; FAILED_NAMES=()
  WSM_STANDALONE=1
fi

# $1 session id, $2 permission mode, $3 command, $4 scratchpad_dir (empty for none). Prints the hook's stdout.
_wsm_hook() {
  jq -nc --arg s "$1" --arg m "$2" --arg c "$3" --arg d "$4" \
    '{session_id:$s,permission_mode:$m,tool_name:"Bash",tool_input:{command:$c}} + (if $d == "" then {} else {scratchpad_dir:$d} end)' \
    | bash "$ROOT/worker-spawn-mode.sh" 2>/dev/null
}

# $1 label, $2 1 when the check held.
_wsm_report() {
  if [[ $2 -eq 1 ]]; then
    printf '  PASS  worker-spawn-mode :: %s\n' "$1"
    PASS=$((PASS+1))
  else
    printf '  FAIL  worker-spawn-mode :: %s\n' "$1"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("worker-spawn-mode::$1")
  fi
}

run_worker_spawn_mode_checks() {
  local tmp="/tmp/claude-$(id -u)" made_tmp="" sid="wsm-$$-$RANDOM$RANDOM" ok out pad
  local spawn="bash /opt/toolkit/scripts/worker-spawn.sh --type execute --key demo"
  if [[ ! -d "$tmp" ]]; then
    mkdir -p "$tmp" && made_tmp=1
  fi
  WSM_BASE="$tmp/worker-spawn-mode-$$"

  ok=1
  pad="$WSM_BASE/direct/scratchpad"
  if mkdir -p "$pad"; then
    out="$(_wsm_hook "$sid-a" auto "$spawn" "$pad")"
    [[ -z "$out" && "$(cat "$pad/worker-spawn-mode" 2>/dev/null)" == 'permission_mode: auto' && ! -e "$pad/worker-spawn-mode.tmp" ]] || ok=0
  else
    ok=0
  fi
  _wsm_report "a spawn command writes the one permission_mode line, no effort line, and prints nothing" "$ok"

  ok=1
  pad="$WSM_BASE/unrelated/scratchpad"
  if mkdir -p "$pad"; then
    out="$(_wsm_hook "$sid-b" auto "ls -la" "$pad")"
    [[ -z "$out" && -z "$(ls -A "$pad")" ]] || ok=0
  else
    ok=0
  fi
  _wsm_report "an unrelated command writes nothing and prints nothing" "$ok"

  ok=1
  pad="$WSM_BASE/unknown/scratchpad"
  if mkdir -p "$pad"; then
    out="$(_wsm_hook "$sid-c" someNewMode "$spawn" "$pad")"
    [[ -z "$out" && -z "$(ls -A "$pad")" ]] || ok=0
  else
    ok=0
  fi
  _wsm_report "an unknown permission mode writes nothing and prints nothing" "$ok"

  ok=1
  pad="$WSM_BASE/$sid-d/scratchpad"
  if mkdir -p "$pad"; then
    out="$(_wsm_hook "$sid-d" default "$spawn" "")"
    [[ -z "$out" && "$(cat "$pad/worker-spawn-mode" 2>/dev/null)" == 'permission_mode: default' ]] || ok=0
  else
    ok=0
  fi
  _wsm_report "a missing scratchpad_dir falls back to the scratchpad found by session_id and prints nothing" "$ok"

  rm -rf "$WSM_BASE"
  [[ -n "$made_tmp" ]] && rmdir "$tmp" 2>/dev/null
}

if [[ -n "${WSM_STANDALONE:-}" ]]; then
  run_worker_spawn_mode_checks
  echo
  echo "RESULT: $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]] || exit 1
fi
