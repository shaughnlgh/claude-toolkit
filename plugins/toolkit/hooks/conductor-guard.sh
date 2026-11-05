#!/bin/bash
# PreToolUse hook (Edit|Write|NotebookEdit): conductor guard. The orchestration
# doctrine delegates every change to a worker; the guard refuses a direct edit from
# the MAIN conversation (no agent_id in the payload) to a file inside the project
# (cwd), and the refusal reason tells the model to route the edit to a worker.
# Subagent edits pass untouched. Conductor-owned artifacts always pass: any path under
# ~/.claude/, under the vault_path in ~/.claude/obsidian-sync.json, or under the
# /tmp/claude-*/ (or /private/tmp/claude-*/) scratchpad, as do other paths outside cwd.
# TOOLKIT_CONDUCTOR_EDITS=1 is the human's override and disables the guard for the
# session. Fails open without jq.
# Subagent detection rests on the documented agent_id payload field (transcript-path
# fallback), a Claude Code version dependency; if worker edits start being refused,
# that signal changed.

[ "${TOOLKIT_CONDUCTOR_EDITS:-0}" = "1" ] && { cat >/dev/null 2>&1; exit 0; }
command -v jq >/dev/null 2>&1 || exit 0   # no jq: skip silently, never obstruct work
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
[ -n "$AGENT_ID" ] && exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
case "$TRANSCRIPT" in */subagents/*) exit 0 ;; esac   # belt-and-braces for payloads without agent_id

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -n "$FP" ] || exit 0

# Checked before the cwd test so a session started in $HOME still writes them; a /../ path never qualifies.
H="$HOME"; while [ "$H" != "${H%/}" ]; do H="${H%/}"; done
VAULT=""
[ -n "$H" ] && [ -f "$H/.claude/obsidian-sync.json" ] && VAULT=$(jq -r '.vault_path // empty' "$H/.claude/obsidian-sync.json" 2>/dev/null)
while [ "$VAULT" != "${VAULT%/}" ]; do VAULT="${VAULT%/}"; done
case "$FP" in */../*) ;; *)
  case "$FP" in /tmp/claude-*/*|/private/tmp/claude-*/*) exit 0 ;; esac
  [ -n "$H" ] && case "$FP" in "$H"/.claude/*) exit 0 ;; esac
  [ -n "$VAULT" ] && case "$FP" in "$VAULT"/*) exit 0 ;; esac ;;
esac

# Guard only project files: relative paths resolve under cwd; absolute paths must be
# inside cwd. Other paths outside the project pass.
# Strip trailing slashes so "/repo/" and "/" compare correctly. An empty or root cwd
# then yields the pattern "/*", so an abnormal payload guards every absolute path.
while [ "$CWD" != "${CWD%/}" ]; do CWD="${CWD%/}"; done
GUARD=0
case "$FP" in
  "$CWD"/*) GUARD=1 ;;
  /*) ;;
  *) GUARD=1 ;;
esac
[ "$GUARD" = "1" ] || exit 0

jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Conductor guard: the main conversation tried to edit a project file directly. Toolkit doctrine (orchestration.md) delegates every change, however small, to a worker agent: route this edit to toolkit:implementer or to the worker already on the job. The human can allow direct conductor edits for a session with TOOLKIT_CONDUCTOR_EDITS=1."}}'
exit 0
