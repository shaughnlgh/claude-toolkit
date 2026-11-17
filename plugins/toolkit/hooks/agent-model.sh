#!/bin/bash
# PreToolUse hook (Agent): adds a named agent's model and effort from scripts/resolve-models.sh, which layers the
# shipped template defaults, then the user's ~/.claude/toolkit-models.json, then the plan-guide run options cache.
# Model and effort are added per field, and a field the call already carries wins for that field only.
# A bare name that a project or user agent file shadows gets nothing added, because that file's agent is the one spawned.
# A shadowing agent is found by its frontmatter name, and resolve-models.sh --alias sends a model that is not an Agent-tool alias as the one family alias it names, or not at all.
# Fails open: a missing jq, a missing hooks/lib, a resolver warning and a resolver failure each surface as a
# systemMessage, and blank resolved fields add nothing. CLAUDE_CODE_SUBAGENT_MODEL_FORCE, when set, wins over the hook.
# A partial updatedInput replaces tool_input wholesale and fails Agent-tool schema validation, so the emitted
# updatedInput is always the full original tool_input plus the added keys.

INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
# The agent files pin no model or effort, so without jq every spawn loses its routing: say so instead of exiting silently.
command -v jq >/dev/null 2>&1 || { printf '%s\n' '{"systemMessage":"toolkit agent-model: jq not found, so the toolkit model config was not applied to this spawn"}'; exit 0; }
. "$(dirname "${BASH_SOURCE[0]}")/lib/session-scratchpad.sh" 2>/dev/null || { printf '%s\n' '{"systemMessage":"toolkit agent-model: hooks/lib/session-scratchpad.sh not found, so the toolkit model config was not applied to this spawn"}'; exit 0; }

CALL_MODEL=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input.model? | type) == "string" then .tool_input.model else empty end' 2>/dev/null)
CALL_EFFORT=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input.effort? | type) == "string" then .tool_input.effort else empty end' 2>/dev/null)
[ -n "$CALL_MODEL" ] && [ -n "$CALL_EFFORT" ] && exit 0

NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[ -n "${NAME#toolkit:}" ] || exit 0
# A bare name that a project or user agent file shadows spawns that agent, which keeps its own frontmatter.
if [ "$NAME" = "${NAME#toolkit:}" ]; then
  . "$(dirname "${BASH_SOURCE[0]}")/lib/component-names.sh" 2>/dev/null || { printf '%s\n' '{"systemMessage":"toolkit agent-model: hooks/lib/component-names.sh not found, so the toolkit model config was not applied to this spawn"}'; exit 0; }
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  { [ -n "$CWD" ] && agent_names "$CWD/.claude/agents" | grep -qxF -- "$NAME"; } && exit 0
  agent_names "$HOME/.claude/agents" | grep -qxF -- "$NAME" && exit 0
fi
NAME="${NAME#toolkit:}"

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
OPTS_FILE=$(session_run_options_file "$SESSION_ID")
OPTS=(); [ -n "$OPTS_FILE" ] && OPTS=(--options "$OPTS_FILE")
[ -n "$CALL_MODEL" ] || OPTS+=(--alias)

RESOLVER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/resolve-models.sh"
WARN_FILE=$(mktemp) || exit 0
RESOLVED=$(bash "$RESOLVER" --agent "$NAME" "${OPTS[@]}" 2>"$WARN_FILE"); RC=$?
# One message per stderr line without the resolver's own prefix, joined with " | " and no trailing space.
WARN=$(awk 'NR > 1 { printf " | " } { sub(/^toolkit resolve-models: /, ""); printf "%s", $0 }' "$WARN_FILE"); rm -f "$WARN_FILE"
if [ "$RC" -ne 0 ] || [ -z "$RESOLVED" ]; then   # resolver failure: fail open, add nothing, say why
  [ -n "$WARN" ] && jq -nc --arg sm "toolkit agent-model: $WARN" '{systemMessage: $sm}'
  exit 0
fi

MODEL=$(printf '%s' "$RESOLVED" | jq -r --arg n "$NAME" '.agents[$n].model // ""' 2>/dev/null)
EFFORT=$(printf '%s' "$RESOLVED" | jq -r --arg n "$NAME" '.agents[$n].effort // ""' 2>/dev/null)
[ -n "$CALL_MODEL" ] && MODEL=""     # an explicit per-call field wins for that field only
[ -n "$CALL_EFFORT" ] && EFFORT=""

printf '%s' "$INPUT" | jq -c --arg m "$MODEL" --arg e "$EFFORT" --arg sm "$WARN" '
  (.tool_input + (if $m != "" then {model: $m} else {} end) + (if $e != "" then {effort: $e} else {} end)) as $ti
  | (if $m == "" and $e == "" then {} else {hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: $ti}} end)
  + (if $sm != "" then {systemMessage: ("toolkit agent-model: " + $sm)} else {} end)
  | if . == {} then empty else . end'
exit 0
