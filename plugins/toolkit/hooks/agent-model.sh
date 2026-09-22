#!/bin/bash
# PreToolUse hook (Agent): re-routes a named agent's model from the user's
# per-machine config (~/.claude/toolkit-models.json, see the shipped
# scripts/toolkit-models.json.template) without shadowing the agent file.
# Only the model changes; the agent's prompt, tools, and every other field
# on the call pass through untouched. Advisory, fails open: no jq, no
# config, a malformed config, or an unlisted/blank-mapped agent all let the
# call through with no model added. An explicit per-call model always wins,
# and so does CLAUDE_CODE_SUBAGENT_MODEL_FORCE when it is set.
# A partial updatedInput (just {"model": ...}) replaces tool_input wholesale
# and fails Agent-tool schema validation, so the emitted updatedInput is
# always the full original tool_input plus the added model key.
# A configured model value may carry a trailing [1m] suffix to select the
# 1M-token context window, for example in a user's settings model value, so
# the validation regex below admits it.

command -v jq >/dev/null 2>&1 || exit 0   # no jq: skip silently, never obstruct work
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

# An explicit per-call model always wins; this hook only fills in a model
# when the call itself didn't ask for one.
CALL_MODEL=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input.model? | type) == "string" then .tool_input.model else empty end' 2>/dev/null)
[ -n "$CALL_MODEL" ] && exit 0

CONFIG="${TOOLKIT_MODELS_FILE:-$HOME/.claude/toolkit-models.json}"
[ -f "$CONFIG" ] || exit 0   # unconfigured: every agent runs on its own frontmatter model

warn_bad_config() {
  jq -n --arg sm "toolkit agent-model: $CONFIG unreadable or has no \"agents\" object; ignored" '{systemMessage:$sm}'
  exit 0
}
jq -e . "$CONFIG" >/dev/null 2>&1 || warn_bad_config
AGENTS_TYPE=$(jq -r '(.agents | type) // "missing"' "$CONFIG" 2>/dev/null)
[ "$AGENTS_TYPE" = "object" ] || warn_bad_config

NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
NAME="${NAME#toolkit:}"
[ -n "$NAME" ] || exit 0

VTYPE=$(jq -r --arg n "$NAME" '(.agents[$n]? | type) // "null"' "$CONFIG" 2>/dev/null)
[ "$VTYPE" = "string" ] || exit 0   # unlisted or non-string mapping: no opinion
MODEL=$(jq -r --arg n "$NAME" '.agents[$n]' "$CONFIG" 2>/dev/null)
[ -n "$MODEL" ] || exit 0   # empty string means "use the agent file's own default"

VALID=$(jq -n --arg m "$MODEL" '$m | test("^[A-Za-z][A-Za-z0-9.:_-]*(\\[1m\\])?$")' 2>/dev/null)
if [ "$VALID" != "true" ]; then
  jq -n --arg sm "toolkit agent-model: invalid model value for $NAME; ignored" '{systemMessage:$sm}'
  exit 0
fi

MODEL_LC=$(printf '%s' "$MODEL" | tr '[:upper:]' '[:lower:]')
case "$MODEL_LC" in
  *haiku*)
    jq -n --arg sm "toolkit agent-model: haiku is refused by the toolkit model policy ($NAME); ignored" '{systemMessage:$sm}'
    exit 0
    ;;
esac

printf '%s' "$INPUT" | jq -c --arg m "$MODEL" '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input + {model:$m})}}'
exit 0
