#!/bin/bash
# PreToolUse hook (Edit|Write|NotebookEdit): conductor guard. The orchestration
# doctrine delegates every change to a worker; a direct edit from the MAIN
# conversation (no agent_id in the payload) to a file inside the project (cwd)
# triggers a permission prompt so the human is the override. Subagent edits pass
# untouched. TOOLKIT_CONDUCTOR_EDITS=1 disables the guard for the session.
# Advisory workflow guard: fails open without jq; only ever asks, never denies.
# Subagent detection rests on the documented agent_id payload field (transcript-path
# fallback) — a Claude Code version dependency; if worker edits start prompting, that
# signal changed.

[ "${TOOLKIT_CONDUCTOR_EDITS:-0}" = "1" ] && exit 0
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

# Guard only project files: relative paths resolve under cwd; absolute paths must be
# inside cwd. Vault notes, memory, and scratchpad live outside the project and pass —
# conductor-owned artifacts, not implementation.
# Strip trailing slashes so "/repo/" and "/" compare correctly. An empty or root cwd
# then yields the pattern "/*", guarding every absolute path — abnormal payloads ask
# rather than silently passing; this hook can only ever ask.
while [ "$CWD" != "${CWD%/}" ]; do CWD="${CWD%/}"; done
GUARD=0
case "$FP" in
  "$CWD"/*) GUARD=1 ;;
  /*) ;;
  *) GUARD=1 ;;
esac
[ "$GUARD" = "1" ] || exit 0

jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"Conductor guard: the main conversation is about to edit a project file directly. Toolkit doctrine (orchestration.md) delegates every change, however small, to a worker agent - approve only if you directed this edit yourself; otherwise deny and route it to toolkit:implementer. Set TOOLKIT_CONDUCTOR_EDITS=1 to allow direct conductor edits for a whole session."}}'
exit 0
