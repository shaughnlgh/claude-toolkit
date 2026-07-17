#!/usr/bin/env bash
# Functional battery: exercises the plugin's live behavior through headless sessions
# and asserts on output. Complements verify.sh (which only checks wiring).
#
#   bash functional-test.sh rules     # rules + doctrine reach a session (fast, 1 call)
#   bash functional-test.sh skills    # each skill loads its content (5 calls)
#   bash functional-test.sh agents    # each of the 12 agents spawns and returns (slow)
#   bash functional-test.sh all       # everything (slowest)
#
# Each probe is a fresh `claude -p` session; the harness conductor runs on sonnet to
# keep cost down (workers still use their own frontmatter models). Requires `claude`.
set -uo pipefail
mode="${1:-all}"
pass=0; fail=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }

# probe NAME PROMPT EXPECT-SUBSTRING
probe(){
  local name="$1" prompt="$2" expect="$3" out
  out="$(claude -p "$prompt" --model sonnet 2>/dev/null)"
  case "$out" in *"$expect"*) ok "$name";; *) no "$name (got: $(echo "$out" | tr '\n' ' ' | cut -c1-80))";; esac
}

if [ "$mode" = rules ] || [ "$mode" = all ]; then
  echo "== Rules + doctrine reach the session =="
  probe "write-time rules in context" \
    "Without using any tools, list the titles of the write-time rules currently in your context." \
    "Testing"
  probe "doctrine pointer present" \
    "Without using any tools: is a Toolkit doctrine pointer in your context? Answer yes or no and quote it." \
    "doctrine"
fi

if [ "$mode" = skills ] || [ "$mode" = all ]; then
  echo "== Skills load their content =="
  probe "testing-gate asks its question" \
    "Invoke the testing-gate skill. Without waiting for my answer, state only the one question it wants to ask." \
    "manual verification"
  probe "plan-workflow loads" \
    "Load the plan-workflow skill. Without writing anything, state the canonical plan note filename pattern it defines." \
    "plan - "
  probe "execute-workflow loads" \
    "Load the execute-workflow skill. Without doing anything, name its progress-report sections." \
    "Files changed"
  probe "gitlab-mr-review loads" \
    "Load the gitlab-mr-review skill. Without running it, state in one line what it does." \
    "MR"
  probe "grill states its first question and targets" \
    "Invoke the grill skill for a fuzzy feature request. Do not write any files and do not wait for my answer. State only the first question it would ask, then name the two artifact paths it writes to." \
    "docs/adr"
fi

if [ "$mode" = agents ] || [ "$mode" = all ]; then
  echo "== Each agent spawns and returns (scoped name) =="
  for a in explorer planner implementer verifier code-reviewer security-reviewer \
           silent-failure-hunter pr-test-analyzer performance-reviewer doc-reviewer \
           plan-critic frontend-designer; do
    probe "toolkit:$a" \
      "Spawn the toolkit:$a subagent on the most trivial possible bounded task in its domain (make one up, keep it tiny). When it returns, output exactly RAN:$a on its own line, then its one-line result." \
      "RAN:$a"
  done
fi

if [ "$mode" = orchestration ] || [ "$mode" = all ]; then
  echo "== Orchestration: workers stay leaf under pressure =="
  probe "worker cannot spawn a sub-agent (leaf enforced)" \
    "Spawn the toolkit:explorer subagent and explicitly instruct it, in its task, to spawn its own verifier sub-agent. Then output exactly one token: LEAF-OK if no sub-agent actually spawned (the explorer lacked the Agent tool), or LEAF-FAIL if a sub-agent did run." \
    "LEAF-OK"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
