#!/usr/bin/env bash
# Hermetic behavior suite for resolve-models.sh. Points TOOLKIT_MODELS_FILE at a per-case user
# file under a temp dir, and copies the script beside a crafted template for the template cases.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE="$HERE/../../resolve-models.sh"
TEMPLATE="$HERE/../../toolkit-models.json.template"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d -t resolve-models.XXXXXX)"
trap 'rm -rf "$T"' EXIT
# A resolver copied to $T/<case>/ sources its lib from $T/hooks/lib.
mkdir -p "$T/hooks/lib"; cp "$HERE/../../../hooks/lib/model-policy.sh" "$T/hooks/lib/"
export TOOLKIT_MODELS_FILE="$T/user.json"
user() { printf '%s' "$1" > "$TOOLKIT_MODELS_FILE"; }
nouser() { rm -f "$TOOLKIT_MODELS_FILE"; }
run_script() { local s=$1; shift; OUT="$(bash "$s" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }
run() { run_script "$RESOLVE" "$@"; }
field() { printf '%s' "$OUT" | jq -r ".agents[\"$1\"].$2"; }

nouser; run
[ "$(field implementer model)/$(field implementer effort)" = "opus/high" ] && ok "missing user file: implementer opus high" || no "implementer default: $OUT"

nouser; run
[ "$(field verifier model)/$(field verifier effort)" = "opus/xhigh" ] && ok "missing user file: verifier opus xhigh" || no "verifier default: $OUT"

nouser; run
[ "$(field planner model)/$(field planner effort)" = "opus/high" ] && ok "missing user file: planner opus high" || no "planner default: $OUT"

nouser; run
[ "$(printf '%s' "$OUT" | jq -r '[.agents[].model | select(. != "opus" and . != "sonnet")] | length')" = "0" ] && ok "missing user file: every agent model is opus or sonnet" || no "non-opus or sonnet default: $OUT"

nouser; run
[ "$(printf '%s' "$OUT" | jq -r '.agents | keys_unsorted | join(",")')" = "$(jq -r '.agents | keys_unsorted | join(",")' "$TEMPLATE")" ] \
  && ok "output lists the template agents in template order" || no "agent order: $OUT"

user '{"agents":{"explorer":{"model":"opus","effort":""}}}'; run
[ "$(field explorer model)/$(field explorer effort)" = "opus/medium" ] && ok "user object sets model and keeps template effort" || no "user model: $OUT"

user '{"agents":{"code-reviewer":{"effort":"low"}}}'; run
[ "$(field code-reviewer model)/$(field code-reviewer effort)" = "opus/low" ] && ok "user object sets effort alone" || no "user effort: $OUT"

user '{"agents":{"implementer":"fable"}}'; run
[ "$(field implementer model)/$(field implementer effort)" = "fable/high" ] && ok "bare string user value sets the model only" || no "bare string: $OUT"

user '{"agents":{"verifier":{"model":"","effort":""}}}'; run
[ "$(field verifier model)/$(field verifier effort)" = "opus/xhigh" ] && ok "blank user fields never override" || no "blank override: $OUT"

user '{"agents":{"no-such-agent":{"model":"opus","effort":"high"}}}'; run
[ "$(printf '%s' "$OUT" | jq -r '.agents | has("no-such-agent")')" = "false" ] && ok "user key not in the template is dropped" || no "unknown key kept: $OUT"

user '{"agents":{"implmenter":{"model":"sonnet"}}}'; run --agent implementer
{ [ "$(field implementer model)" = "opus" ] && printf '%s' "$ERR" | grep -q '^toolkit resolve-models: unknown agent implmenter in the user file layer; ignored$'; } && ok "an unknown user agent name warns, also under --agent" || no "unknown agent name: $OUT / $ERR"

nouser; run; BASE_AGENTS="$(printf '%s' "$OUT" | jq -c .agents)"
user '{"agents":{"general-purpose":{"model":"inherit"},"Plan":"inherit","Explore":"sonnet","claude":"opus"}}'; run
{ [ -z "$ERR" ] && [ "$(printf '%s' "$OUT" | jq -c .agents)" = "$BASE_AGENTS" ]; } && ok "user entries for the four built-in types warn nothing and leave the agents map unchanged" || no "built-in entries: $OUT / $ERR"

user '{"agents":{"implementer":"Sonnet"}}'; run --alias
{ [ "$(field implementer model)" = "sonnet" ] && printf '%s' "$ERR" | grep -q 'model Sonnet is not an Agent-tool alias, sent as sonnet'; } && ok "--alias maps a capitalized family name to its alias" || no "capitalized alias: $OUT / $ERR"

user '{"agents":{"explorer":"haiku"}}'; run
{ [ "$(field explorer model)" = "sonnet" ] && printf '%s' "$ERR" | grep -q 'haiku is refused'; } && ok "haiku in the user file falls to the template and warns" || no "user haiku: $OUT / $ERR"

mkdir -p "$T/tmpl"; cp "$RESOLVE" "$T/tmpl/resolve-models.sh"
printf '%s' '{"agents":{"explorer":{"model":"claude-haiku-4","effort":"low"}}}' > "$T/tmpl/toolkit-models.json.template"
nouser; run_script "$T/tmpl/resolve-models.sh"
{ [ "$(field explorer model)" = "" ] && printf '%s' "$ERR" | grep -q 'haiku is refused'; } && ok "haiku in the template falls to blank and warns" || no "template haiku: $OUT / $ERR"

user '{"agents":{"implementer":"sonnet"}}'; run --worker-model haiku
{ [ "$(field implementer model)" = "sonnet" ] && printf '%s' "$ERR" | grep -q 'haiku is refused'; } && ok "haiku in --worker-model falls to the user file and warns" || no "flag haiku: $OUT / $ERR"

user '{"agents":{"implementer":"bad model!"}}'; run
{ [ "$(field implementer model)" = "opus" ] && printf '%s' "$ERR" | grep -q '\[implementer\] invalid model value'; } && ok "invalid user model warns and falls to the template" || no "invalid model: $OUT / $ERR"

nouser; run --verifier-effort extreme
{ [ "$(field verifier effort)" = "xhigh" ] && printf '%s' "$ERR" | grep -q '\[verifier\] invalid effort value'; } && ok "invalid --verifier-effort warns and falls below" || no "invalid effort: $OUT / $ERR"

user '{"agents": {'; run
{ [ "$RC" -eq 0 ] && [ "$(field implementer model)" = "opus" ] && printf '%s' "$ERR" | grep -q 'ignored'; } && ok "malformed user file warns and applies the template defaults" || no "malformed (rc=$RC): $OUT / $ERR"

user '{"implementer":"sonnet"}'; run
{ [ "$(field implementer model)" = "opus" ] && printf '%s' "$ERR" | grep -q 'no "agents" object'; } && ok "user file with no agents object warns" || no "no agents (rc=$RC): $OUT / $ERR"

printf 'plan: example-plan\nworker_model: sonnet\nverifier_model: fable\nverifier_effort: max\nnits: fix\n' > "$T/options"
nouser; run --options "$T/options"
[ "$(field implementer model)/$(field verifier model)/$(field verifier effort)" = "sonnet/fable/max" ] && ok "options file sets implementer model and verifier model and effort" || no "options file: $OUT / $ERR"

nouser; run --options "$T/options" --worker-model fable
[ "$(field implementer model)" = "fable" ] && ok "a flag overrides the options file" || no "flag over options: $OUT"

user '{"agents":{"verifier":{"model":"sonnet","effort":"low"}}}'; run --options "$T/options"
[ "$(field verifier model)/$(field verifier effort)" = "fable/max" ] && ok "the options file overrides the user file" || no "options over user: $OUT"

user '{"agents":{"implementer":"sonnet"}}'; run --worker-model fable
[ "$(field implementer model)" = "fable" ] && ok "--worker-model overrides the user file" || no "worker flag over user: $OUT"

nouser; run --verifier-model fable
[ "$(field verifier model)/$(field implementer model)" = "fable/opus" ] && ok "--verifier-model sets the verifier model only" || no "verifier model flag: $OUT"

nouser; run --verifier-effort max
[ "$(field verifier effort)/$(field implementer effort)" = "max/high" ] && ok "--verifier-effort sets the verifier effort only" || no "verifier effort flag: $OUT"

nouser; run --options "$T/missing-options"
{ [ "$RC" -eq 0 ] && [ "$(field implementer model)" = "opus" ] && printf '%s' "$ERR" | grep -q 'options file not found'; } && ok "missing options file warns and continues" || no "missing options (rc=$RC): $OUT / $ERR"

mkdir -p "$T/notmpl"; cp "$RESOLVE" "$T/notmpl/resolve-models.sh"
nouser; run_script "$T/notmpl/resolve-models.sh"
{ [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -q '^error: '; } && ok "missing template exits 2 with an error line" || no "missing template (rc=$RC): $ERR"

nouser; run --bogus
[ "$RC" -eq 2 ] && ok "unknown option exits 2" || no "unknown option (rc=$RC): $ERR"

user '{"agents":{"verifier":{"model":"inherit","effort":"inherit"}}}'; run
[ "$(field verifier model)/$(field verifier effort)" = "/" ] && ok "inherit in the user file clears the template value" || no "inherit: $OUT"

user '{"agents":{"explorer":"haiku","implementer":"haiku"}}'; run --agent explorer
{ [ "$(printf '%s\n' "$ERR" | grep -c 'haiku is refused')" -eq 1 ] && printf '%s' "$ERR" | grep -q '\[explorer\]'; } && ok "--agent prints only that agent's warnings" || no "agent filter: $ERR"

printf 'plan: example-plan\n  worker_model:   sonnet  \n' > "$T/padded-options"
nouser; run --options "$T/padded-options"
[ "$(field implementer model)" = "sonnet" ] && ok "an indented, padded options line is read" || no "padded options: $OUT / $ERR"

user '{"agents":{"verifier":{"model":"sonnet","Effort":"low"}}}'; run
{ [ "$(field verifier model)/$(field verifier effort)" = "sonnet/xhigh" ] && printf '%s' "$ERR" | grep -q '\[verifier\] unknown key Effort'; } && ok "an unknown key inside a user object warns" || no "unknown inner key: $OUT / $ERR"

user '{"agents":{"implementer":{"model":["opus"]}}}'; run
{ [ "$(field implementer model)" = "opus" ] && printf '%s' "$ERR" | grep -q '\[implementer\] invalid model value'; } && ok "a non-string user field warns and falls to the template" || no "non-string field: $OUT / $ERR"

user '{"agents":{"explorer":5}}'; run
{ [ "$(field explorer model)" = "sonnet" ] && printf '%s' "$ERR" | grep -q '\[explorer\] invalid model value'; } && ok "a user value that is neither a string nor an object warns" || no "number value: $OUT / $ERR"

mkdir -p "$T/noagents"; cp "$RESOLVE" "$T/noagents/resolve-models.sh"; printf '{}' > "$T/noagents/toolkit-models.json.template"
nouser; run_script "$T/noagents/resolve-models.sh"
{ [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -q '^error: template is not valid JSON or has no "agents" object'; } && ok "a template with no agents object exits 2 naming the template" || no "template no agents (rc=$RC): $ERR"

printf '{"agents":{"implementer":{"model":"fable","effort":"low"}}}' > "$T/crafted-template.json"
export TOOLKIT_MODELS_TEMPLATE="$T/crafted-template.json"; nouser; run; unset TOOLKIT_MODELS_TEMPLATE
[ "$(field implementer model)/$(field implementer effort)" = "fable/low" ] && ok "TOOLKIT_MODELS_TEMPLATE replaces the template layer" || no "template env: $OUT / $ERR"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
