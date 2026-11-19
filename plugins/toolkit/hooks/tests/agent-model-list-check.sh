#!/usr/bin/env bash
# Exercises the agent model list that session-start.sh injects: each line must match what agent-model.sh adds for that agent,
# the list must reach the first 1500 bytes of additionalContext, it must follow the session's run options cache, and a resolver failure must leave a note.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters. Run directly, it supplies its own and prints a RESULT line.
# The directories it creates are removed inline at the end, because run-all.sh owns the EXIT trap. The real ~/.claude is never read.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PASS=0; FAIL=0; FAILED_NAMES=()
  AML_STANDALONE=1
fi

# $1 label, $2 1 when the check held.
_aml_report() {
  if [[ $2 -eq 1 ]]; then
    printf '  PASS  agent-model-list :: %s\n' "$1"
    PASS=$((PASS+1))
  else
    printf '  FAIL  agent-model-list :: %s\n' "$1"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("agent-model-list::$1")
  fi
}

# $1 user file. Prints, per shipped agent, the list line built from the model and effort agent-model.sh adds to a bare call.
_aml_from_hook() {
  local n out m e
  for n in $(jq -r '.agents | keys_unsorted[]' "$ROOT/../scripts/toolkit-models.json.template"); do
    out="$(jq -nc --arg a "toolkit:$n" '{tool_name:"Agent",tool_input:{description:"d",prompt:"p",subagent_type:$a}}' \
      | HOME="$AML_BASE/home" TOOLKIT_MODELS_FILE="$1" bash "$ROOT/agent-model.sh" 2>/dev/null)"
    m="$(printf '%s' "${out:-{\}}" | jq -r '.hookSpecificOutput.updatedInput.model // ""')"
    e="$(printf '%s' "${out:-{\}}" | jq -r '.hookSpecificOutput.updatedInput.effort // ""')"
    printf 'toolkit:%s: %s, %s\n' "$n" "${m:+model $m}" "${e:+effort $e}" | sed 's/: , /: omit model, /; s/, $/, omit effort/'
  done
}

# $1 user file, $2 session id (optional). Prints session-start's additionalContext.
_aml_session_start() {
  jq -nc --arg s "${2:-}" '{session_id:$s,source:"startup"}' \
    | HOME="$AML_BASE/home" CLAUDE_PLUGIN_ROOT="$ROOT/.." TOOLKIT_MODELS_FILE="$1" bash "$ROOT/session-start.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext'
}

AML_HEADER='Toolkit agent models: on every Agent-tool spawn of a toolkit:<name> agent, pass model and effort from this list'

run_agent_model_list_checks() {
  local tmp="/tmp/claude-$(id -u)" made_tmp="" sid="aml-$$-$RANDOM$RANDOM" ok list ctx
  local full_id="$ROOT/tests/fixtures/agent-model/aux/full-id.json"
  if [[ ! -d "$tmp" ]]; then
    mkdir -p "$tmp" && made_tmp=1
  fi
  AML_BASE="$tmp/agent-model-list-$$"
  mkdir -p "$AML_BASE/home"

  list="$(TOOLKIT_MODELS_FILE="$AML_BASE/no-user-file.json" bash "$ROOT/../scripts/resolve-models.sh" --list 2>/dev/null)"
  ok=0; [[ -n "$list" && "$list" == "$(_aml_from_hook "$AML_BASE/no-user-file.json")" ]] && ok=1
  _aml_report "with the template defaults each list line carries the model and effort agent-model.sh adds" "$ok"

  list="$(TOOLKIT_MODELS_FILE="$full_id" bash "$ROOT/../scripts/resolve-models.sh" --list 2>/dev/null)"
  ok=0; [[ -n "$list" && "$list" == "$(_aml_from_hook "$full_id")" ]] && ok=1
  _aml_report "with a user file holding full model ids each list line carries the model and effort agent-model.sh adds" "$ok"

  ctx="$(_aml_session_start "$full_id")"
  ok=0; [[ -n "$list" && "$ctx" == *"$list"* ]] && ok=1
  _aml_report "session-start adds the list to additionalContext" "$ok"

  ok=0; [[ -n "$list" && "$(printf '%s' "$ctx" | head -c 1500)" == *"$AML_HEADER"*$'\n'"$list"* ]] && ok=1
  _aml_report "with full model ids the header and every list line sit in the first 1500 bytes of additionalContext" "$ok"

  list="$(TOOLKIT_MODELS_FILE="$AML_BASE/no-user-file.json" bash "$ROOT/../scripts/resolve-models.sh" --list 2>/dev/null)"
  ctx="$(_aml_session_start "$AML_BASE/no-user-file.json")"
  ok=0; [[ -n "$list" && "$(printf '%s' "$ctx" | head -c 1500)" == *"$AML_HEADER"*$'\n'"$list"* ]] && ok=1
  _aml_report "with the template defaults the header and every list line sit in the first 1500 bytes of additionalContext" "$ok"

  ok=0
  if mkdir -p "$AML_BASE/$sid/scratchpad" \
    && printf 'plan: example-plan\nworker_model: sonnet\n' > "$AML_BASE/$sid/scratchpad/flow-run-options"; then
    ctx="$(_aml_session_start "$AML_BASE/no-user-file.json" "$sid")"
    [[ "$ctx" == *$'\ntoolkit:implementer: model sonnet, effort '* ]] && ok=1
  fi
  _aml_report "session-start resolves the list with the session's run options cache" "$ok"

  ok=0
  if printf '{"agents":' > "$AML_BASE/broken-template.json"; then
    ctx="$(jq -nc '{source:"startup"}' | HOME="$AML_BASE/home" TOOLKIT_MODELS_TEMPLATE="$AML_BASE/broken-template.json" bash "$ROOT/session-start.sh" 2>/dev/null \
      | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *'Toolkit agent models: not resolved'* && "$ctx" != *'toolkit:implementer:'* ]] && ok=1
  fi
  _aml_report "a resolver failure leaves a one-line note in place of the list" "$ok"

  rm -rf "$AML_BASE"
  [[ -n "$made_tmp" ]] && rmdir "$tmp" 2>/dev/null
}

if [[ -n "${AML_STANDALONE:-}" ]]; then
  run_agent_model_list_checks
  echo
  echo "RESULT: $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]] || exit 1
fi
