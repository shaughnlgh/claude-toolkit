#!/bin/bash
# PreToolUse hook (Bash): records the session's permission mode for scripts/worker-spawn.sh, which starts a worker session in the lead's mode.
# Prints nothing and never changes the call, because a change after the auto mode check gets the call refused once.
INPUT=$(cat 2>/dev/null)
case "$INPUT" in *worker-spawn.sh*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
case "$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" in *scripts/worker-spawn.sh*) ;; *) exit 0 ;; esac
mode=$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)
case $mode in default | plan | acceptEdits | auto | dontAsk | bypassPermissions) ;; *) exit 0 ;; esac
. "$(dirname "${BASH_SOURCE[0]}")/lib/session-scratchpad.sh" 2>/dev/null || exit 0
dir=$(printf '%s' "$INPUT" | jq -r '.scratchpad_dir // empty' 2>/dev/null)
if [ ! -d "$dir" ]; then  # Claude Code before 2.1.257 sends no scratchpad_dir
  dir=$(session_scratchpads "$(printf '%s' "$INPUT" | jq -r '.session_id // empty')" | head -1)
fi
[ -d "$dir" ] || exit 0
printf 'permission_mode: %s\n' "$mode" > "$dir/$WORKER_SPAWN_MODE_FILE.tmp" && mv "$dir/$WORKER_SPAWN_MODE_FILE.tmp" "$dir/$WORKER_SPAWN_MODE_FILE"
exit 0
