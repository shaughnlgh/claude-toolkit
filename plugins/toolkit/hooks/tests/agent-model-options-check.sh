#!/usr/bin/env bash
# Exercises agent-model.sh against real directories: the plan-guide run options cache in a scratchpad under /tmp/claude-<uid>,
# project and user agent files that shadow a bare name, a plugin copy whose template is broken, a hook copy without hooks/lib, and a PATH without jq.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters. Run directly, it supplies its own and prints a RESULT line.
# The directories it creates are removed inline at the end, because run-all.sh owns the EXIT trap. The real ~/.claude is never read.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PASS=0; FAIL=0; FAILED_NAMES=()
  AMO_STANDALONE=1
fi

# $1 session id, $2 subagent_type, $3 cwd (optional), $4 hook path (optional). Prints the hook's stdout with no user file.
_amo_hook() {
  jq -nc --arg s "$1" --arg a "$2" --arg c "${3:-}" '{session_id:$s,cwd:$c,tool_name:"Agent",tool_input:{description:"d",prompt:"p",subagent_type:$a}}' \
    | HOME="${AMO_HOME:-$AMO_BASE/home}" TOOLKIT_MODELS_FILE="$AMO_BASE/no-user-file.json" bash "${4:-$ROOT/agent-model.sh}" 2>/dev/null
}

# $1 label, $2 1 when the check held.
_amo_report() {
  if [[ $2 -eq 1 ]]; then
    printf '  PASS  agent-model-options :: %s\n' "$1"
    PASS=$((PASS+1))
  else
    printf '  FAIL  agent-model-options :: %s\n' "$1"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("agent-model-options::$1")
  fi
}

run_agent_model_options_checks() {
  local tmp="/tmp/claude-$(id -u)" made_tmp="" sid="amo-$$-$RANDOM$RANDOM" ok out impl_effort
  if [[ ! -d "$tmp" ]]; then
    mkdir -p "$tmp" && made_tmp=1
  fi
  AMO_BASE="$tmp/agent-model-options-$$"
  impl_effort="$(jq -r '.agents.implementer.effort' "$ROOT/../scripts/toolkit-models.json.template")"

  ok=1
  if mkdir -p "$AMO_BASE/$sid/scratchpad" \
    && printf 'plan: example-plan\nworker_model: sonnet\nverifier_model: fable\nverifier_effort: max\n' > "$AMO_BASE/$sid/scratchpad/flow-run-options"; then
    out="$(_amo_hook "$sid" toolkit:implementer)"
    [[ "$out" == *'"model":"sonnet"'* && "$out" == *"\"effort\":\"$impl_effort\""* ]] || ok=0
    out="$(_amo_hook "$sid" toolkit:verifier)"
    [[ "$out" == *'"model":"fable"'* && "$out" == *'"effort":"max"'* ]] || ok=0
  else
    ok=0
  fi
  _amo_report "the run options cache sets the implementer model and the verifier model and effort" "$ok"

  # Each session puts the older cache in a different slug directory, so a first-match read fails one of them whatever the glob order.
  ok=1
  local older newer s
  for s in "$sid-a:$AMO_BASE:$AMO_BASE-0" "$sid-b:$AMO_BASE-0:$AMO_BASE"; do
    IFS=: read -r s older newer <<<"$s"
    if mkdir -p "$older/$s/scratchpad" "$newer/$s/scratchpad" \
      && printf 'plan: older-plan\nworker_model: fable\n' > "$older/$s/scratchpad/flow-run-options" \
      && touch -t 202001010000 "$older/$s/scratchpad/flow-run-options" \
      && printf 'plan: newer-plan\nworker_model: sonnet\n' > "$newer/$s/scratchpad/flow-run-options"; then
      out="$(_amo_hook "$s" toolkit:implementer)"
      [[ "$out" == *'"model":"sonnet"'* ]] || ok=0
    else
      ok=0
    fi
  done
  _amo_report "the newest run options cache wins when two slug directories hold one session" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/project/.claude/agents" && printf -- '---\nname: code-reviewer\n---\n' > "$AMO_BASE/project/.claude/agents/code-reviewer.md"; then
    out="$(_amo_hook "$sid" code-reviewer "$AMO_BASE/project")"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a project agent file that shadows a bare name gets nothing added" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/home/.claude/agents" && printf -- '---\nname: verifier\n---\n' > "$AMO_BASE/home/.claude/agents/verifier.md"; then
    out="$(_amo_hook "$sid" verifier)"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agent file that shadows a bare name gets nothing added" "$ok"

  ok=1
  out="$(_amo_hook "$sid" toolkit:verifier)"
  [[ -f "$AMO_BASE/home/.claude/agents/verifier.md" && "$out" == *'"model":'* ]] || ok=0
  _amo_report "the scoped name of a user-shadowed agent still gets its model" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/project2/.claude/agents/sub" && printf -- '---\nname: code-reviewer\n---\n' > "$AMO_BASE/project2/.claude/agents/sub/other.md"; then
    out="$(_amo_hook "$sid" code-reviewer "$AMO_BASE/project2")"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a nested project agent whose frontmatter name matches a bare name shadows it" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/home2/.claude/agents" && printf -- '---\nname: my-verifier\n---\n' > "$AMO_BASE/home2/.claude/agents/verifier.md"; then
    out="$(AMO_HOME="$AMO_BASE/home2" _amo_hook "$sid" verifier)"
    [[ "$out" == *'"model":'* ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agent file named after a bare name with another frontmatter name does not shadow it" "$ok"

  # find -L follows a symlinked agents folder.
  ok=1
  if mkdir -p "$AMO_BASE/dotfiles/agents" "$AMO_BASE/home3/.claude" && printf -- '---\nname: verifier\n---\n' > "$AMO_BASE/dotfiles/agents/mine.md" && ln -s "$AMO_BASE/dotfiles/agents" "$AMO_BASE/home3/.claude/agents"; then
    out="$(AMO_HOME="$AMO_BASE/home3" _amo_hook "$sid" verifier)"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agents folder that links to another folder shadows a bare name by frontmatter name" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/home4/.claude/agents" && printf -- '---\r\nname: verifier\r\n---\r\n' > "$AMO_BASE/home4/.claude/agents/mine.md"; then
    out="$(AMO_HOME="$AMO_BASE/home4" _amo_hook "$sid" verifier)"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agent file with CRLF line endings shadows a bare name" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/home5/.claude/agents" && printf -- "---\nname: 'verifier'\n---\n" > "$AMO_BASE/home5/.claude/agents/mine.md"; then
    out="$(AMO_HOME="$AMO_BASE/home5" _amo_hook "$sid" verifier)"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agent file with a single-quoted frontmatter name shadows a bare name" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/home6/.claude/agents" && printf -- '---\nname: "verifier"\n---\n' > "$AMO_BASE/home6/.claude/agents/mine.md"; then
    out="$(AMO_HOME="$AMO_BASE/home6" _amo_hook "$sid" verifier)"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agent file with a double-quoted frontmatter name shadows a bare name" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/home7/.claude/agents" && printf -- '---\nname: verifier # my copy\n---\n' > "$AMO_BASE/home7/.claude/agents/mine.md"; then
    out="$(AMO_HOME="$AMO_BASE/home7" _amo_hook "$sid" verifier)"
    [[ -z "$out" ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a user agent file whose frontmatter name carries a trailing comment shadows a bare name" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/plugin/hooks/lib" "$AMO_BASE/plugin/scripts" \
    && cp "$ROOT/agent-model.sh" "$AMO_BASE/plugin/hooks/agent-model.sh" \
    && cp "$ROOT/lib/session-scratchpad.sh" "$AMO_BASE/plugin/hooks/lib/session-scratchpad.sh" \
    && cp "$ROOT/../scripts/resolve-models.sh" "$AMO_BASE/plugin/scripts/resolve-models.sh" \
    && printf '{"agents":' > "$AMO_BASE/plugin/scripts/toolkit-models.json.template"; then
    out="$(_amo_hook "$sid" toolkit:implementer "" "$AMO_BASE/plugin/hooks/agent-model.sh")"
    [[ "$out" == *'"systemMessage"'* && "$out" == *'template is not valid JSON'* && "$out" != *'updatedInput'* ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a resolver failure adds nothing and surfaces its error as a systemMessage" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/nolib/hooks" && cp "$ROOT/agent-model.sh" "$AMO_BASE/nolib/hooks/agent-model.sh"; then
    out="$(_amo_hook "$sid" toolkit:implementer "" "$AMO_BASE/nolib/hooks/agent-model.sh")"
    [[ "$out" == *'"systemMessage"'* && "$out" == *'session-scratchpad.sh not found'* && "$out" != *'updatedInput'* ]] || ok=0
  else
    ok=0
  fi
  _amo_report "without hooks/lib the hook adds nothing and says so in a systemMessage" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/nonames/hooks/lib" && cp "$ROOT/agent-model.sh" "$AMO_BASE/nonames/hooks/agent-model.sh" \
    && cp "$ROOT/lib/session-scratchpad.sh" "$AMO_BASE/nonames/hooks/lib/session-scratchpad.sh"; then
    out="$(_amo_hook "$sid" verifier "" "$AMO_BASE/nonames/hooks/agent-model.sh")"
    [[ "$out" == *'component-names.sh not found'* && "$out" != *'updatedInput'* ]] || ok=0
  else
    ok=0
  fi
  _amo_report "a bare name without hooks/lib/component-names.sh adds nothing and says so in a systemMessage" "$ok"

  ok=1
  if mkdir -p "$AMO_BASE/nojq-bin" && ln -s "$(command -v cat)" "$AMO_BASE/nojq-bin/cat"; then
    out="$(printf '%s' '{"tool_name":"Agent","tool_input":{"description":"d","prompt":"p","subagent_type":"toolkit:implementer"}}' \
      | PATH="$AMO_BASE/nojq-bin" /bin/bash "$ROOT/agent-model.sh" 2>/dev/null)"
    [[ "$out" == *'"systemMessage"'* && "$out" == *'jq not found'* && "$out" != *'updatedInput'* ]] || ok=0
  else
    ok=0
  fi
  _amo_report "without jq the hook adds nothing and says so in a systemMessage" "$ok"

  rm -rf "$AMO_BASE" "$AMO_BASE-0"
  [[ -n "$made_tmp" ]] && rmdir "$tmp" 2>/dev/null
}

if [[ -n "${AMO_STANDALONE:-}" ]]; then
  run_agent_model_options_checks
  echo
  echo "RESULT: $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]] || exit 1
fi
