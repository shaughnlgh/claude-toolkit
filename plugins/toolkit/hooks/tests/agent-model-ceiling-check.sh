#!/usr/bin/env bash
# Exercises the model ceiling in agent-model.sh: a built-in Agent type, or a call with no type, under a session model above Opus.
# Each case writes a temp transcript and runs the hook under a temp HOME, so the real ~/.claude is never read.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters. Run directly, it supplies its own and prints a RESULT line.
# The directory it creates is removed inline at the end, because run-all.sh owns the EXIT trap.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PASS=0; FAIL=0; FAILED_NAMES=()
  ACC_STANDALONE=1
fi

# $1 tool_input JSON, $2 transcript path, $3 HOME, then any NAME=value env assignments. Prints the hook's stdout.
_acc_hook() {
  local ti=$1 tp=$2 home=$3
  shift 3
  jq -nc --argjson ti "$ti" --arg tp "$tp" --arg c "$ACC_BASE/project" '{session_id:"acc",cwd:$c,transcript_path:$tp,tool_name:"Agent",tool_input:$ti}' \
    | env -u TOOLKIT_MODELS_FILE -u TOOLKIT_MODELS_TEMPLATE -u CLAUDE_CODE_SUBAGENT_MODEL HOME="$home" "$@" bash "$ROOT/agent-model.sh" 2>/dev/null
}

# $1 session model. Prints one assistant transcript line.
_acc_line() {
  jq -nc --arg m "$1" '{type:"assistant",message:{model:$m,content:[]}}'
}

# $1 home suffix, $2 user models file JSON. Writes $ACC_BASE/home-$1/.claude/toolkit-models.json.
_acc_user() {
  mkdir -p "$ACC_BASE/home-$1/.claude"
  printf '%s' "$2" > "$ACC_BASE/home-$1/.claude/toolkit-models.json"
}

# $1 label, $2 1 when the check held.
_acc_report() {
  if [[ $2 -eq 1 ]]; then
    printf '  PASS  agent-model-ceiling :: %s\n' "$1"
    PASS=$((PASS+1))
  else
    printf '  FAIL  agent-model-ceiling :: %s\n' "$1"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("agent-model-ceiling::$1")
  fi
}

run_agent_model_ceiling_checks() {
  local ok out home fable opus synth pad gp sonnet bedrock
  ACC_BASE="$(mktemp -d -t agent-model-ceiling.XXXXXX)" || { _acc_report "the temp dir was created" 0; return; }
  home="$ACC_BASE/home"
  fable="$ACC_BASE/fable.jsonl"; opus="$ACC_BASE/opus.jsonl"; synth="$ACC_BASE/synthetic.jsonl"; pad="$ACC_BASE/padded.jsonl"
  sonnet="$ACC_BASE/sonnet.jsonl"; bedrock="$ACC_BASE/bedrock.jsonl"
  gp='{"description":"d","prompt":"x","subagent_type":"general-purpose"}'
  mkdir -p "$home/.claude" "$ACC_BASE/project" "$ACC_BASE/home-explore/.claude/agents" "$ACC_BASE/home-inherit/.claude" "$ACC_BASE/home-fable/.claude"
  _acc_line claude-fable-test > "$fable"
  _acc_line claude-opus-5-5 > "$opus"
  _acc_line claude-sonnet-test > "$sonnet"
  _acc_line us.anthropic.claude-fable-test-v1:0 > "$bedrock"
  { _acc_line claude-sonnet-test; _acc_line '<synthetic>'; } > "$synth"
  { printf '{"type":"user","pad":"%s"}\n' "$(head -c 300000 /dev/zero | tr '\0' a)"; _acc_line claude-fable-test; } > "$pad"
  printf -- '---\nname: Explore\n---\n' > "$ACC_BASE/home-explore/.claude/agents/explore.md"
  printf '{"agents":{"general-purpose":{"model":"inherit"}}}' > "$ACC_BASE/home-inherit/.claude/toolkit-models.json"
  printf '{"agents":{"general-purpose":"fable"}}' > "$ACC_BASE/home-fable/.claude/toolkit-models.json"

  out="$(_acc_hook "$gp" "$fable" "$home" | jq -c '.hookSpecificOutput.updatedInput' 2>/dev/null)"
  [[ "$out" == '{"description":"d","prompt":"x","subagent_type":"general-purpose","model":"opus"}' ]] && ok=1 || ok=0
  _acc_report "a general-purpose call under a Fable session gets model opus with the full tool_input kept" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x"}' "$fable" "$home" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "a call with no subagent_type under a Fable session gets model opus" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x","subagent_type":"Explore"}' "$fable" "$home" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "an Explore call under a Fable session gets model opus" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x","subagent_type":"Plan"}' "$fable" "$home" CLAUDE_CODE_SUBAGENT_MODEL=sonnet | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "a Plan call gets model opus even with CLAUDE_CODE_SUBAGENT_MODEL set" "$ok"

  out="$(_acc_hook "$gp" "$fable" "$home" CLAUDE_CODE_SUBAGENT_MODEL=sonnet)"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a general-purpose call with CLAUDE_CODE_SUBAGENT_MODEL set gets nothing added" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x","subagent_type":"Explore"}' "$fable" "$ACC_BASE/home-explore")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "an Explore call shadowed by a user agent file named Explore gets nothing added" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x","subagent_type":"general-purpose","model":"fable"}' "$fable" "$home")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a call that carries model fable gets nothing added" "$ok"

  out="$(_acc_hook "$gp" "$opus" "$home")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a general-purpose call under an Opus session gets nothing added" "$ok"

  out="$(_acc_hook "$gp" "$synth" "$home")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a newest synthetic line is skipped for the Sonnet session model before it, so nothing is added" "$ok"

  out="$(_acc_hook "$gp" "$sonnet" "$home")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a general-purpose call under a Sonnet session gets nothing added" "$ok"

  out="$(_acc_hook "$gp" "$bedrock" "$home" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "a provider-prefixed Fable session model gets model opus" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x","subagent_type":"claude"}' "$fable" "$home" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "a claude call under a Fable session gets model opus" "$ok"

  out="$(_acc_hook '{"description":"d","prompt":"x","subagent_type":"Explore"}' "$fable" "$home" CLAUDE_CODE_SUBAGENT_MODEL=sonnet | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "an Explore call gets model opus even with CLAUDE_CODE_SUBAGENT_MODEL set" "$ok"

  _acc_user haiku '{"agents":{"general-purpose":"haiku"}}'
  out="$(_acc_hook "$gp" "$fable" "$ACC_BASE/home-haiku" | jq -r '[.hookSpecificOutput.updatedInput.model, .systemMessage] | join("|")' 2>/dev/null)"
  [[ "$out" == 'opus|'*'refused by the toolkit model policy, so this spawn went to opus'* ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry of haiku under a Fable session gets model opus and says it was refused" "$ok"

  _acc_user fullid '{"agents":{"general-purpose":"claude-fable-5"}}'
  out="$(_acc_hook "$gp" "$fable" "$ACC_BASE/home-fullid" | jq -r '[.hookSpecificOutput.updatedInput.model, .systemMessage] | join("|")' 2>/dev/null)"
  [[ "$out" == 'fable|'*'is not an Agent-tool alias, sent as fable' ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry of a full model id gets its family alias and says so" "$ok"

  _acc_user multi '{"agents":{"general-purpose":"opus-or-sonnet"}}'
  out="$(_acc_hook "$gp" "$fable" "$ACC_BASE/home-multi" | jq -r '[.hookSpecificOutput.updatedInput.model, .systemMessage] | join("|")' 2>/dev/null)"
  [[ "$out" == 'opus|'*'names no single model family, so this spawn went to opus'* ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry naming two families under a Fable session gets model opus and says so" "$ok"

  out="$(_acc_hook "$gp" "$opus" "$ACC_BASE/home-multi" | jq -r '[(.hookSpecificOutput | tostring), .systemMessage] | join("|")' 2>/dev/null)"
  [[ "$out" == 'null|'*'names no single model family, so no model was added' ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry naming two families under an Opus session adds no model and says so" "$ok"

  _acc_user caps '{"agents":{"general-purpose":"Opus"}}'
  out="$(_acc_hook "$gp" "$fable" "$ACC_BASE/home-caps" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "a capitalized general-purpose user entry of Opus gets model opus" "$ok"

  _acc_user sonnet '{"agents":{"general-purpose":{"model":"sonnet","effort":"low"}}}'
  out="$(_acc_hook "$gp" "$opus" "$ACC_BASE/home-sonnet" | jq -c '[.hookSpecificOutput.updatedInput.model, .hookSpecificOutput.updatedInput.effort, .systemMessage]' 2>/dev/null)"
  [[ "$out" == '["sonnet","low",null]' ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry of sonnet at low effort applies under an Opus session" "$ok"

  out="$(_acc_hook "$gp" "$ACC_BASE/missing.jsonl" "$home")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a missing transcript gets nothing added" "$ok"

  out="$(_acc_hook "$gp" "$fable" "$ACC_BASE/home-inherit")"
  [[ -z "$out" ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry of inherit gets nothing added" "$ok"

  out="$(_acc_hook "$gp" "$fable" "$ACC_BASE/home-fable" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == fable ]] && ok=1 || ok=0
  _acc_report "a general-purpose user entry of fable gets model fable" "$ok"

  out="$(_acc_hook "$gp" "$pad" "$home" | jq -r '.hookSpecificOutput.updatedInput.model' 2>/dev/null)"
  [[ "$out" == opus ]] && ok=1 || ok=0
  _acc_report "a transcript tail that starts mid-line skips the partial line and still gets model opus" "$ok"

  rm -rf "$ACC_BASE"
}

if [[ -n "${ACC_STANDALONE:-}" ]]; then
  run_agent_model_ceiling_checks
  echo
  echo "RESULT: $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]] || exit 1
fi
