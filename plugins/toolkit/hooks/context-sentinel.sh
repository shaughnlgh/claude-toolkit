#!/bin/bash
# PostToolUse hook (all tools): context-budget sentinel. Reads the last main-loop
# assistant usage from the session transcript and, when the conversation's context
# crosses a threshold (200k / 400k / 600k tokens), injects a model-visible nudge to
# delegate mechanical work and plan a handoff — plus a user-visible warning from 400k.
# Each threshold fires once per crossing (state in a per-session temp file; re-arms
# when context drops after /compact or /clear). Advisory only: never blocks, always
# exits 0. Disable with TOOLKIT_CTX_SENTINEL=0. TOOLKIT_SENTINEL_STATELESS=1 skips
# the once-per-crossing dedup (used by the fixture tests).

[ "${TOOLKIT_CTX_SENTINEL:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0   # no jq: skip silently, never obstruct work
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SID="${SID//[!A-Za-z0-9_-]/_}"   # state-file path component: never trust it raw
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Last main-loop assistant usage in the recent tail. Sidechain (subagent) entries are
# excluded: their contexts are separate and small. input + cache_read + cache_creation
# is the full context the next request re-sends.
CTX=$(tail -n 200 "$TRANSCRIPT" 2>/dev/null | jq -r '
  select(.isSidechain != true) | .message.usage // empty |
  ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
' 2>/dev/null | tail -n 1)
case "$CTX" in ''|*[!0-9]*) exit 0 ;; esac

TIER=0
[ "$CTX" -ge 200000 ] && TIER=1
[ "$CTX" -ge 400000 ] && TIER=2
[ "$CTX" -ge 600000 ] && TIER=3
CTXK=$((CTX / 1000))

# Once-per-crossing dedup, re-armed when context shrinks (compact/clear).
if [ "${TOOLKIT_SENTINEL_STATELESS:-0}" != "1" ] && [ -n "$SID" ]; then
  STATE="${TMPDIR:-/tmp}/toolkit-ctx-sentinel-${SID}"
  PREV=$(cat "$STATE" 2>/dev/null)
  case "$PREV" in ''|*[!0-9]*) PREV=0 ;; esac
  if [ "$TIER" -le "$PREV" ]; then
    [ "$TIER" -lt "$PREV" ] && printf '%s' "$TIER" > "$STATE" 2>/dev/null
    exit 0
  fi
  printf '%s' "$TIER" > "$STATE" 2>/dev/null
fi
[ "$TIER" -eq 0 ] && exit 0

case "$TIER" in
  1) NUDGE="Context sentinel: this conversation's context is ~${CTXK}k tokens and every request now re-sends all of it. From here, delegate mechanical work (searches, browser loops, log trawls, test runs) to worker agents — they start near-empty — and plan a wrap-up or handoff point. See doctrine/orchestration.md, Context budget." ;;
  2) NUDGE="Context sentinel: context is ~${CTXK}k tokens — each tool step now costs several times a fresh session's. Bring the current task to a stable point, update the plan/work note, and recommend the user continue in a fresh session. Delegate anything mechanical that remains. See doctrine/orchestration.md, Context budget." ;;
  *) NUDGE="Context sentinel: context is ~${CTXK}k tokens, near the window limit — wrap up NOW. Update the plan/work note with current state and next steps, tell the user this session should end, and do not start new work here. See doctrine/orchestration.md, Context budget." ;;
esac

SM=""
[ "$TIER" -ge 2 ] && SM="toolkit: context ~${CTXK}k tokens — each request re-reads all of it; consider wrapping up this session (the plan/work note carries the state)"

jq -n --arg ctx "$NUDGE" --arg sm "$SM" \
  'def base: {hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}};
   if $sm=="" then base else base + {systemMessage:$sm} end'
exit 0
