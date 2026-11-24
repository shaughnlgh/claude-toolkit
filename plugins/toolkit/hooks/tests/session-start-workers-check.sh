#!/usr/bin/env bash
# Exercises session-start.sh's worker sessions line against a real scratchpad under /tmp/claude-<uid> and a fixture agents list.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters. Run directly, it supplies its own and prints a RESULT line.
# The directories it creates are removed inline at the end, because run-all.sh owns the EXIT trap. The real ~/.claude is never read.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PASS=0; FAIL=0; FAILED_NAMES=()
  SSW_STANDALONE=1
fi

SSW_LINE="Worker sessions this session owns: worker-execute-demo (a1b2c3d4, working)."

# $1 source, $2 session id, $3 agents file, $4 work dir used as cwd and HOME. Prints the hook's additionalContext.
_ssw_hook() {
  (cd "$4" && jq -nc --arg src "$1" --arg s "$2" '{source:$src,session_id:$s}' \
    | env -u TOOLKIT_COMPACT_HANDOFF -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
      HOME="$4" CLAUDE_PLUGIN_ROOT="$(cd "$ROOT/.." && pwd)" TOOLKIT_AGENTS_FILE="$3" bash "$ROOT/session-start.sh" 2>/dev/null) \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# $1 label, $2 1 when the check held.
_ssw_report() {
  if [[ $2 -eq 1 ]]; then
    printf '  PASS  session-start-workers :: %s\n' "$1"
    PASS=$((PASS+1))
  else
    printf '  FAIL  session-start-workers :: %s\n' "$1"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("session-start-workers::$1")
  fi
}

run_session_start_workers_checks() {
  local tmp="/tmp/claude-$(id -u)" made_tmp="" sid="ssw-$$-$RANDOM$RANDOM" gone="ssw-gone-$$-$RANDOM$RANDOM" ok ctx work agents
  if [[ ! -d "$tmp" ]]; then
    mkdir -p "$tmp" && made_tmp=1
  fi
  SSW_BASE="$tmp/session-start-workers-$$"
  work="$SSW_BASE/work"
  agents="$SSW_BASE/agents.json"
  if ! mkdir -p "$work" "$SSW_BASE/$sid/scratchpad" "$SSW_BASE/$gone/scratchpad" \
    || ! printf 'a1b2c3d4\tworker-execute-demo\texecute\tdemo\t1700000000\n' > "$SSW_BASE/$sid/scratchpad/workers" \
    || ! printf 'deadbeef\tworker-plan-old\tplan\told\t1700000000\n' > "$SSW_BASE/$gone/scratchpad/workers" \
    || ! printf '[{"id":"a1b2c3d4","pid":4242,"sessionId":"w-1","name":"worker-execute-demo","kind":"background","status":"busy","state":"working","waitingFor":null}]\n' > "$agents"; then
    _ssw_report "setup" 0
    rm -rf "$SSW_BASE"
    return
  fi

  ctx="$(_ssw_hook resume "$sid" "$agents" "$work")"
  ok=0; [[ "$ctx" == *"$SSW_LINE"* && "$ctx" == *"worker-watch.sh wait --scratchpad $SSW_BASE/$sid/scratchpad "* ]] && ok=1
  _ssw_report "resume lists the owned live worker and the re-arm command" "$ok"
  ok=0; [[ "$ctx" == *"--scratchpad $SSW_BASE/$sid/scratchpad --self $sid with run_in_background."* ]] && ok=1
  _ssw_report "the re-arm command passes the session id as --self" "$ok"

  ctx="$(_ssw_hook compact "$sid" "$agents" "$work")"
  ok=0; [[ "$ctx" == *"$SSW_LINE"* && "$ctx" == *"worker-watch.sh wait --scratchpad $SSW_BASE/$sid/scratchpad --self $sid with run_in_background."* ]] && ok=1
  _ssw_report "compact lists the owned live worker and the full re-arm command" "$ok"

  ctx="$(_ssw_hook startup "$sid" "$agents" "$work")"
  ok=0; [[ -n "$ctx" && "$ctx" != *"Worker sessions this session owns"* ]] && ok=1
  _ssw_report "startup prints no worker sessions line" "$ok"

  ctx="$(_ssw_hook resume "$gone" "$agents" "$work")"
  ok=0; [[ -n "$ctx" && "$ctx" != *"Worker sessions this session owns"* ]] && ok=1
  _ssw_report "a workers file whose rows are all gone prints no line" "$ok"

  printf 'not json\n' > "$SSW_BASE/bad-agents.json"
  ctx="$(_ssw_hook resume "$sid" "$SSW_BASE/bad-agents.json" "$work")"
  ok=0; [[ "$ctx" == *"Worker sessions this session owns could not be listed"* && "$ctx" == *"worker-watch.sh wait --scratchpad $SSW_BASE/$sid/scratchpad --self $sid with run_in_background."* ]] && ok=1
  _ssw_report "a failed agents read still gives the full re-arm command" "$ok"

  rm -rf "$SSW_BASE"
  [[ -n "$made_tmp" ]] && rmdir "$tmp" 2>/dev/null
}

if [[ -n "${SSW_STANDALONE:-}" ]]; then
  run_session_start_workers_checks
  echo
  echo "RESULT: $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]] || exit 1
fi
