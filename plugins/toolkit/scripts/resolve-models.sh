#!/usr/bin/env bash
# Resolves each shipped agent's model and effort: template defaults, then the user file, then the plan note options. Prints {"agents":{...}}, or with --list one line per agent in the form a session passes on an Agent-tool call. --alias, which --list implies, turns a model that is not an Agent-tool alias into the one family alias it names, or blank, with a warning. Exit 0, or 2 on an unknown option, a flag with no value, a missing jq, a missing template, a template that is not valid JSON or has no "agents" object, or a failed resolution or alias conversion.
set -uo pipefail

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
warn() { printf 'toolkit resolve-models: %s\n' "$1" >&2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TOOLKIT_MODELS_TEMPLATE:-$HERE/toolkit-models.json.template}"
USER_FILE="${TOOLKIT_MODELS_FILE:-$HOME/.claude/toolkit-models.json}"

options=""; worker_model=""; verifier_model=""; verifier_effort=""; agent_name=""; alias=""; list=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) [ $# -ge 2 ] || die "--agent needs a name"; agent_name=$2; shift 2 ;;
    --options) [ $# -ge 2 ] || die "--options needs a file"; options=$2; shift 2 ;;
    --worker-model) [ $# -ge 2 ] || die "--worker-model needs a value"; worker_model=$2; shift 2 ;;
    --verifier-model) [ $# -ge 2 ] || die "--verifier-model needs a value"; verifier_model=$2; shift 2 ;;
    --verifier-effort) [ $# -ge 2 ] || die "--verifier-effort needs a value"; verifier_effort=$2; shift 2 ;;
    --alias) alias=1; shift ;;
    --list) list=1; alias=1; shift ;;
    *) die "usage: resolve-models.sh [--agent <name>] [--options <file>] [--worker-model <m>] [--verifier-model <m>] [--verifier-effort <e>] [--alias] [--list]" ;;
  esac
done
command -v jq >/dev/null 2>&1 || die "jq not found"
[ -f "$TEMPLATE" ] || die "template not found: $TEMPLATE"

# The options file is the plan-guide run options cache. Only its three model and effort lines are read, never its plan: line, and a flag wins over a line.
if [ -n "$options" ]; then
  if [ -f "$options" ]; then
    # Reads a line the way session-start.sh's ro_line does: leading spaces allowed, the value trimmed at both ends.
    opt() { sed -nE "s/^[[:space:]]*$1:[[:space:]]*//p" "$options" | head -1 | sed 's/[[:space:]]*$//'; }
    [ -n "$worker_model" ] || worker_model=$(opt worker_model)
    [ -n "$verifier_model" ] || verifier_model=$(opt verifier_model)
    [ -n "$verifier_effort" ] || verifier_effort=$(opt verifier_effort)
  else
    warn "options file not found: $options; ignored"
  fi
fi

TMPL=$(jq -ce '.agents | select(type == "object")' "$TEMPLATE" 2>/dev/null) || die "template is not valid JSON or has no \"agents\" object: $TEMPLATE"
USER_AGENTS='{}'
if [ -f "$USER_FILE" ]; then
  USER_AGENTS=$(jq -ce '.agents | select(type == "object")' "$USER_FILE" 2>/dev/null) || { USER_AGENTS='{}'; warn "$USER_FILE unreadable or has no \"agents\" object; ignored"; }
fi
NOTE=$(jq -nc --arg wm "$worker_model" --arg vm "$verifier_model" --arg ve "$verifier_effort" '{implementer: {model: $wm, effort: ""}, verifier: {model: $vm, effort: $ve}}')

OUT=$(jq -nc --argjson tmpl "$TMPL" --argjson user "$USER_AGENTS" --argjson note "$NOTE" '
  # A value that is neither a string nor an object reads as null, and pick warns on any field that is not a string.
  def field($f): if type == "string" then (if $f == "model" then . else "" end) elif type == "object" then (if has($f) then .[$f] else "" end) elif type == "null" then "" else null end;
  def model_ok: test("^[A-Za-z][A-Za-z0-9.:_-]*(\\[1m\\])?$");
  def effort_ok: IN("low", "medium", "high", "xhigh", "max");  # mirrors EFFORTS in validate-plan.py, minus inherit
  def pick($name; $field; $layers):
    reduce ($layers[] | {layer, raw: .agents[$name]} | .value = (.raw | field($field))) as $c ({value: "", warnings: []};
      (if $field == "model" and ($c.raw | type) == "object" then [$c.raw | keys[] | select(IN("model", "effort") | not)] else [] end) as $unknown
      | if ($unknown | length) > 0 then .warnings += ["[\($name)] unknown key \($unknown | join(", ")) in the \($c.layer) layer; ignored"] else . end
      | if ($c.value | type) != "string" then .warnings += ["[\($name)] invalid \($field) value in the \($c.layer) layer; ignored"]
      elif $c.value == "" then .
      elif $c.value == "inherit" then .value = ""
      elif $field == "model" and ($c.value | ascii_downcase | contains("haiku")) then .warnings += ["[\($name)] haiku is refused by the toolkit model policy in the \($c.layer) layer; ignored"]
      elif ($field == "model" and ($c.value | model_ok | not)) or ($field == "effort" and ($c.value | effort_ok | not)) then .warnings += ["[\($name)] invalid \($field) value in the \($c.layer) layer; ignored"]
      else .value = $c.value end);
  [{layer: "template", agents: $tmpl}, {layer: "user file", agents: $user}, {layer: "plan note", agents: $note}] as $layers
  | ($tmpl | keys_unsorted) as $names
  | {agents: ([$names[] | {key: ., value: {model: pick(.; "model"; $layers).value, effort: pick(.; "effort"; $layers).value}}] | from_entries),
     warnings: ([($user | keys) - $names | .[] | "unknown agent \(.) in the user file layer; ignored"] + [$names[] as $n | ("model", "effort") as $f | pick($n; $f; $layers).warnings[]])}') || die "resolution failed"
if [ -n "$alias" ]; then
  OUT=$(printf '%s\n' "$OUT" | jq -c '
    def family: [scan("opus|sonnet|haiku|fable")] | unique | if length == 1 then .[0] else "" end;
    reduce (.agents | to_entries[] | select(.value.model | IN("", "sonnet", "opus", "haiku", "fable") | not)) as $a (.;
      ($a.value.model | family) as $f
      | .agents[$a.key].model = $f
      | .warnings += [if $f != "" then "[\($a.key)] model \($a.value.model) is not an Agent-tool alias, sent as \($f)"
          else "[\($a.key)] model \($a.value.model) is not an Agent-tool alias and names no single model family, so no model was added" end])') || die "alias conversion failed"
fi
printf '%s\n' "$OUT" | jq -r --arg n "$agent_name" '.warnings[] | select($n == "" or (startswith("[") | not) or startswith("[" + $n + "]"))' | while IFS= read -r w; do warn "$w"; done
if [ -n "$list" ]; then
  printf '%s\n' "$OUT" | jq -r '.agents | to_entries[] | "toolkit:\(.key): \(if .value.model == "" then "omit model" else "model \(.value.model)" end), \(if .value.effort == "" then "omit effort" else "effort \(.value.effort)" end)"'
else
  printf '%s\n' "$OUT" | jq -c '{agents: .agents}'
fi
exit 0
