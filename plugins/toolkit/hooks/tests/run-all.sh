#!/usr/bin/env bash
# Hook test runner. Iterates every fixture under hooks/tests/fixtures/<hook>/
# and invokes hooks/<hook>.sh with the fixture's stdin, comparing exit code
# and stdout/stderr substrings against the fixture's expectations.
#
# Fixture format (JSON):
#   {
#     "name":        "human readable",
#     "stdin":       <object passed to the hook as JSON>,
#     "expect_exit": 0 | 2,
#     "expect_stdout_contains": ["substring", ...],   // optional
#     "expect_stdout_not_contains": ["substring", ...], // optional
#     "expect_stderr_contains": ["substring", ...]    // optional
#   }
#
# Also runs notify-osascript-argv-check.sh for checks fixtures can't express
# (PATH stubs, argv capture); its result folds into the same PASS/FAIL totals.
#
# Exit 0 on all pass, 1 on any fail.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"

# Anchor the cwd to tests/ so fixture-relative env values (e.g.
# CLAUDE_PLUGIN_ROOT="../.." resolving to plugins/toolkit) mean the same thing
# no matter where the runner is invoked from.
cd "$ROOT/tests" || { echo "FATAL: cannot cd to $ROOT/tests" >&2; exit 2; }

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq required" >&2
  exit 2
fi

# An empty session list keeps every hook run off the real `claude agents --json`.
TOOLKIT_AGENTS_FILE="$(mktemp)" || { echo "FATAL: mktemp failed for the agents file" >&2; exit 2; }
# The handoff checks lay out scratchpads under /tmp/claude-<uid>, removed here too if the run dies mid-check.
trap 'rm -f "$TOOLKIT_AGENTS_FILE"; declare -F _sh_cleanup >/dev/null && _sh_cleanup' EXIT
printf '[]\n' > "$TOOLKIT_AGENTS_FILE"
export TOOLKIT_AGENTS_FILE

PASS=0
FAIL=0
FAILED_NAMES=()

run_case() {
  local hook_name="$1"
  local fixture="$2"
  local hook_path="$ROOT/${hook_name}.sh"
  [[ -x "$hook_path" ]] || chmod +x "$hook_path" 2>/dev/null || true

  local name stdin expect_exit
  name=$(jq -r '.name' "$fixture")
  stdin=$(jq -c '.stdin' "$fixture")
  expect_exit=$(jq -r '.expect_exit' "$fixture")

  local out_file err_file actual_exit
  out_file=$(mktemp)
  err_file=$(mktemp)

  local env_exports
  env_exports=$(jq -r '(.env // {}) | to_entries | map("\(.key)=\(.value|tostring)") | .[]' "$fixture")

  if [[ -n "$env_exports" ]]; then
    printf '%s' "$stdin" | env $env_exports bash "$hook_path" >"$out_file" 2>"$err_file"
  else
    printf '%s' "$stdin" | bash "$hook_path" >"$out_file" 2>"$err_file"
  fi
  actual_exit=$?

  local ok=1
  if [[ "$actual_exit" != "$expect_exit" ]]; then
    ok=0
  fi

  check_subs() {
    local field="$1" file="$2" invert="$3"
    local count
    count=$(jq -r "(.${field} // []) | length" "$fixture")
    local i=0
    while [[ $i -lt $count ]]; do
      local sub
      sub=$(jq -r ".${field}[$i]" "$fixture")
      if [[ "$invert" == "no" ]]; then
        grep -qF -- "$sub" "$file" || ok=0
      else
        grep -qF -- "$sub" "$file" && ok=0
      fi
      i=$((i+1))
    done
  }

  check_subs "expect_stdout_contains"     "$out_file" "no"
  check_subs "expect_stdout_not_contains" "$out_file" "yes"
  check_subs "expect_stderr_contains"     "$err_file" "no"

  if [[ $ok -eq 1 ]]; then
    printf '  PASS  %s :: %s\n' "$hook_name" "$name"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %s :: %s (exit=%s, expected=%s)\n' "$hook_name" "$name" "$actual_exit" "$expect_exit"
    printf '        stdout: %s\n' "$(head -c 500 "$out_file")"
    [[ -s "$err_file" ]] && printf '        stderr: %s\n' "$(head -c 500 "$err_file")"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$hook_name::$name")
  fi
  rm -f "$out_file" "$err_file"
}

fixture_dir_count=0
fixture_case_count=0
for dir in "$FIXTURES"/*/; do
  [[ -d "$dir" ]] || continue
  fixture_dir_count=$((fixture_dir_count+1))
  hook_name=$(basename "$dir")
  echo "== $hook_name =="
  for f in "$dir"*.json; do
    [[ -f "$f" ]] || continue
    fixture_case_count=$((fixture_case_count+1))
    run_case "$hook_name" "$f"
  done
done

# A vanished/emptied fixtures/ dir must fail the suite, not glob to nothing and pass.
if [[ $fixture_dir_count -eq 0 || $fixture_case_count -eq 0 ]]; then
  echo "FATAL: no fixture directories/cases found under $FIXTURES" >&2
  exit 2
fi

# Checks that need a PATH stub or argv capture, which JSON fixtures can't express.
# A missing/unsourceable file or missing function must fail the suite, not go silently uncounted.
source "$ROOT/tests/notify-osascript-argv-check.sh" || { echo "FATAL: cannot source notify-osascript-argv-check.sh" >&2; exit 2; }
declare -F run_notify_checks >/dev/null || { echo "FATAL: run_notify_checks not defined" >&2; exit 2; }
echo "== notify (non-fixture) =="
run_notify_checks

# Checks that need an oversized rule body, which JSON fixtures can't express.
source "$ROOT/tests/session-start-size-guard-check.sh" || { echo "FATAL: cannot source session-start-size-guard-check.sh" >&2; exit 2; }
declare -F run_session_start_size_guard_checks >/dev/null || { echo "FATAL: run_session_start_size_guard_checks not defined" >&2; exit 2; }
echo "== session-start size guard (non-fixture) =="
run_session_start_size_guard_checks

# Checks that need real (non-stateless) marker persistence, an isolated TMPDIR, or
# genuinely malformed stdin, which JSON fixtures can't express.
source "$ROOT/tests/design-rules-reminder-check.sh" || { echo "FATAL: cannot source design-rules-reminder-check.sh" >&2; exit 2; }
declare -F run_design_rules_reminder_checks >/dev/null || { echo "FATAL: run_design_rules_reminder_checks not defined" >&2; exit 2; }
echo "== design rules reminder (non-fixture) =="
run_design_rules_reminder_checks

# Checks that need a symlink, which the plugin installer does not copy into the installed tree.
source "$ROOT/tests/subagent-rules-dangling-symlink-check.sh" || { echo "FATAL: cannot source subagent-rules-dangling-symlink-check.sh" >&2; exit 2; }
declare -F run_subagent_rules_dangling_symlink_checks >/dev/null || { echo "FATAL: run_subagent_rules_dangling_symlink_checks not defined" >&2; exit 2; }
echo "== subagent-rules dangling symlink (non-fixture) =="
run_subagent_rules_dangling_symlink_checks

# Checks that need a scratch git repo and a linked worktree, which JSON fixtures can't express.
source "$ROOT/tests/session-start-recall-check.sh" || { echo "FATAL: cannot source session-start-recall-check.sh" >&2; exit 2; }
declare -F run_session_start_recall_checks >/dev/null || { echo "FATAL: run_session_start_recall_checks not defined" >&2; exit 2; }
echo "== session-start recall (non-fixture) =="
run_session_start_recall_checks

# Seat line checks reuse the recall file's scratch repo helper, so they source after it.
source "$ROOT/tests/session-start-seat-check.sh" || { echo "FATAL: cannot source session-start-seat-check.sh" >&2; exit 2; }
declare -F run_session_start_seat_checks >/dev/null || { echo "FATAL: run_session_start_seat_checks not defined" >&2; exit 2; }
echo "== session-start seat (non-fixture) =="
run_session_start_seat_checks

# Checks that need a real scratchpad under /tmp/claude-<uid> and a read-only directory, which JSON fixtures can't express.
source "$ROOT/tests/session-start-handoff-check.sh" || { echo "FATAL: cannot source session-start-handoff-check.sh" >&2; exit 2; }
declare -F run_session_start_handoff_checks >/dev/null || { echo "FATAL: run_session_start_handoff_checks not defined" >&2; exit 2; }
echo "== session-start handoff (non-fixture) =="
run_session_start_handoff_checks

# Checks that need a scratch git repo, a vault plan note, a linked worktree, and real marker persistence,
# which JSON fixtures cannot express.
source "$ROOT/tests/remember-guard-check.sh" || { echo "FATAL: cannot source remember-guard-check.sh" >&2; exit 2; }
declare -F run_remember_guard_checks >/dev/null || { echo "FATAL: run_remember_guard_checks not defined" >&2; exit 2; }
echo "== remember-guard (non-fixture) =="
run_remember_guard_checks

# Checks that need a real scratchpad under /tmp/claude-<uid> holding the run options cache, which JSON fixtures cannot express.
source "$ROOT/tests/agent-model-options-check.sh" || { echo "FATAL: cannot source agent-model-options-check.sh" >&2; exit 2; }
declare -F run_agent_model_options_checks >/dev/null || { echo "FATAL: run_agent_model_options_checks not defined" >&2; exit 2; }
echo "== agent-model options (non-fixture) =="
run_agent_model_options_checks

# Checks that need a temp transcript and a temp HOME to read the session model and the user models file, which JSON fixtures cannot express.
source "$ROOT/tests/agent-model-ceiling-check.sh" || { echo "FATAL: cannot source agent-model-ceiling-check.sh" >&2; exit 2; }
declare -F run_agent_model_ceiling_checks >/dev/null || { echo "FATAL: run_agent_model_ceiling_checks not defined" >&2; exit 2; }
echo "== agent-model ceiling (non-fixture) =="
run_agent_model_ceiling_checks

# Checks that compare the session-start agent list with agent-model.sh's output per agent and need a real scratchpad, which JSON fixtures cannot express.
source "$ROOT/tests/agent-model-list-check.sh" || { echo "FATAL: cannot source agent-model-list-check.sh" >&2; exit 2; }
declare -F run_agent_model_list_checks >/dev/null || { echo "FATAL: run_agent_model_list_checks not defined" >&2; exit 2; }
echo "== agent-model list (non-fixture) =="
run_agent_model_list_checks

# Checks that need a real scratchpad under /tmp/claude-<uid> to read the recorded mode back, which JSON fixtures cannot express.
source "$ROOT/tests/worker-spawn-mode-check.sh" || { echo "FATAL: cannot source worker-spawn-mode-check.sh" >&2; exit 2; }
declare -F run_worker_spawn_mode_checks >/dev/null || { echo "FATAL: run_worker_spawn_mode_checks not defined" >&2; exit 2; }
echo "== worker-spawn-mode (non-fixture) =="
run_worker_spawn_mode_checks

# Checks that need a real scratchpad under /tmp/claude-<uid> holding a workers file, which JSON fixtures cannot express.
source "$ROOT/tests/session-start-workers-check.sh" || { echo "FATAL: cannot source session-start-workers-check.sh" >&2; exit 2; }
declare -F run_session_start_workers_checks >/dev/null || { echo "FATAL: run_session_start_workers_checks not defined" >&2; exit 2; }
echo "== session-start workers (non-fixture) =="
run_session_start_workers_checks

echo
echo "RESULT: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  printf 'Failed: %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
