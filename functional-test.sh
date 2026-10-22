#!/usr/bin/env bash
# Functional battery: exercises the plugin's live behavior through headless,
# HERMETIC claude sessions and asserts on the strongest available evidence.
# Complements verify.sh (mechanical wiring) — see VERIFY.md for what each layer
# proves and what stays manual.
#
#   bash functional-test.sh self-test      # harness self-tests, NO Claude calls
#   bash functional-test.sh rules          # rules + doctrine reach a session (1 call, low cost)
#   bash functional-test.sh skills         # each skill's contract facts load (14 calls, medium)
#   bash functional-test.sh agents         # fixture-based agent probes (15 calls, high)
#   bash functional-test.sh agents <name>  # a single agent probe (1 call); unknown <name> ERRORS
#   bash functional-test.sh orchestration  # no live calls — static + manual (see below)
#   bash functional-test.sh all            # rules + skills + agents (30 calls, high)
#
# Isolation: every live probe runs inside a fresh `mktemp -d` workspace (its own
# throwaway git repo when needed) — never against this checkout or any real
# project. The checkout's `git status --porcelain` is snapshotted before the
# battery and must be byte-identical after. Failed probes preserve their
# workspace for diagnosis; successful ones are cleaned.
#
# Assertion hierarchy (strongest wins): observable file/command result in the
# workspace > structured tool event proving the agent ran > schema-validated
# final output > content facts not present verbatim in the prompt > labeled
# smoke checks. Expected success markers NEVER appear verbatim in prompts, and
# every probe checks the CLI exit code before reading output.
set -uo pipefail

SELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-}"
only_agent="${2:-}"
[ -n "$mode" ] || { sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 2; }

MODEL="sonnet"
# Agent subagents default to BACKGROUND (the Agent tool runs them detached), which
# lets the headless -p session end before the subagent finishes — its finding then
# never lands in the stream. Every agent probe appends this so the conductor runs the
# subagent synchronously and its result is a foreground tool_result we can assert on.
SYNC_HINT="Spawn it synchronously with run_in_background set to false, and wait for its full result before you reply; do NOT run it as a background agent."
PROBE_TIMEOUT="${FT_TIMEOUT:-300}"
pass=0; fail=0
PRESERVED=()

# Every valid <name> for `agents <name>`, kept in lockstep with probe_agents()'s run_one
# calls below. An unrecognized name must ERROR (nonzero exit), never silently select
# nothing and let the battery report a false success (zero probes run, zero failures).
AGENT_PROBE_NAMES=(explorer implementer planner verifier code-reviewer security-reviewer silent-failure-hunter pr-test-analyzer performance-reviewer doc-reviewer plan-critic coupling-reviewer frontend-designer subagent-rules config-coupling-bait)

known_agent_probe() { local n="$1" p; for p in "${AGENT_PROBE_NAMES[@]}"; do [ "$p" = "$n" ] && return 0; done; return 1; }

ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }

# ---------- workspace + snapshot plumbing ----------

mkws() { mktemp -d -t toolkit-ftest; }

# Remove a workspace ONLY if it looks like ours (guards the trap/cleanup path).
cleanup_ws() {
  case "${1:-}" in
    */toolkit-ftest*) rm -rf "$1" ;;
    *) echo "  (refusing to clean unexpected path: ${1:-<empty>})" >&2 ;;
  esac
}

preserve_ws() { PRESERVED+=("$1"); echo "  workspace preserved for diagnosis: $1"; }

fixture_repo() { # $1 = workspace; init a disposable repo. Returns nonzero on failure.
  git -C "$1" init -q || return 1
  git -C "$1" config user.email "fixture@test.invalid" || return 1
  git -C "$1" config user.name "Fixture" || return 1
  # Disable commit signing so fixture commits never depend on (or hang on) the
  # machine's gpg/signing config.
  git -C "$1" config commit.gpgsign false || return 1
}

# fixture_commit <workspace>: stage everything and commit, checked. Returns nonzero
# (without aborting the whole run) if add or commit fails, so the caller fails the
# probe closed instead of launching a Claude call against an unbuilt fixture.
fixture_commit() {
  git -C "$1" add -A >/dev/null 2>&1 || return 1
  git -C "$1" commit -qm fixture >/dev/null 2>&1 || return 1
}

# fixture_subagent_hook_ws <workspace>: registers THIS CHECKOUT's SubagentStart hook
# (subagent-rules.sh) as the workspace's local settings, pinned to this checkout's own
# plugin root — never an installed/system plugin — so a probe run against it proves the
# code under test, not whatever version happens to be installed elsewhere. Returns
# nonzero if the settings file cannot be written.
fixture_subagent_hook_ws() {
  local ws="$1" hook="$SELF_ROOT/plugins/toolkit/hooks/subagent-rules.sh" proot="$SELF_ROOT/plugins/toolkit"
  mkdir -p "$ws/.claude" || return 1
  cat > "$ws/.claude/settings.json" <<EOF || return 1
{
  "hooks": {
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "CLAUDE_PLUGIN_ROOT='$proot' bash '$hook'", "timeout": 10 } ] }
    ]
  }
}
EOF
}

snapshot_checkout() { git -C "$SELF_ROOT" status --porcelain 2>/dev/null; }

# ---------- bounded, captured claude invocation ----------

# run_probe <workdir> <capdir> <prompt> [extra claude args...]
# Runs claude -p in <workdir>, bounded by $PROBE_TIMEOUT seconds. Captures
# stdout -> $capdir/out, stderr -> $capdir/err, exit code -> $capdir/rc.
run_probe() {
  local workdir="$1" capdir="$2" prompt="$3"; shift 3
  local args=(-p "$prompt" --model "$MODEL" "$@")
  (
    cd "$workdir" || exit 97
    claude "${args[@]}" >"$capdir/out" 2>"$capdir/err"
    echo $? >"$capdir/rc"
  ) &
  local pid=$!
  ( sleep "$PROBE_TIMEOUT" && kill -TERM "$pid" 2>/dev/null ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  [ -f "$capdir/rc" ] || echo 96 >"$capdir/rc"  # killed by watchdog / never wrote rc
}

probe_rc() { cat "$1/rc" 2>/dev/null || echo 95; }

# ---------- structured parsing (python3 stdlib; also exercised by self-test) ----------

# json_result <capdir>: prints the .result of an --output-format json capture,
# exits nonzero on parse failure or is_error=true.
json_result() {
  python3 - "$1/out" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)
if d.get("is_error"):
    sys.exit(4)
r = d.get("result", "")
print(r if isinstance(r, str) else json.dumps(r))
PY
}

# structured_field <capdir> <field>: parses the json result, then parses THAT as
# JSON (the --json-schema structured output), prints the named field.
structured_field() {
  python3 - "$1/out" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if d.get("is_error"):
        sys.exit(4)
    r = d.get("result", "")
    obj = r if isinstance(r, dict) else json.loads(r)
    v = obj[sys.argv[2]]
except Exception:
    sys.exit(3)
print(v if isinstance(v, str) else json.dumps(v))
PY
}

# agent_result <stream-events-file> <subagent-name>: prints the matched agent's real
# RETURNED finding and exits 0 only if one is found. Handles both spawn modes:
#   * foreground: the Agent/Task tool_use's own non-error tool_result IS the finding.
#   * background: that tool_result is only an "Async agent launched successfully" ack
#     carrying `agentId: <hex>`; the real finding arrives later in a separate
#     tool_result whose content includes `<task_id><hex></task_id>` (the retrieval /
#     task-notification). We match on that id.
# The launch-ack itself is NEVER treated as the finding (else a backgrounded agent
# false-passes), an error tool_result is never a finding (H2: a missing-agent Task must
# not count as ran), and echoed fixture-file Reads are excluded because we only take the
# launched-id result or the agentId-matched retrieval — not arbitrary stream text.
agent_result() {
  python3 - "$1" "$2" <<'PY'
import json, re, sys
path, want = sys.argv[1], sys.argv[2]
launched = set()          # Agent/Task tool_use ids for the wanted subagent
ack_agent_ids = set()     # background agent ids harvested from launch-ack results
fg, results_by_task = [], []
pending = []              # all (tool_use_id, is_error, text) to scan for task-id match

def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") if isinstance(b, dict) else str(b) for b in c)
    return ""

for line in open(path, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    msg = ev.get("message")
    if not isinstance(msg, dict):
        continue  # e.g. a "system" event whose message is a plain string, not content blocks
    for b in (msg.get("content") or []):
        if not isinstance(b, dict):
            continue
        if b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task"):
            if want in str((b.get("input") or {}).get("subagent_type", "")):
                launched.add(b.get("id"))
        if b.get("type") == "tool_result":
            txt = text_of(b.get("content"))
            err = bool(b.get("is_error"))
            if b.get("tool_use_id") in launched and not err:
                if "Async agent launched successfully" in txt:
                    # background launch-ack — never a finding; harvest the agent id if present
                    m = re.search(r"agentId:\s*(\S+)", txt)
                    if m:
                        ack_agent_ids.add(m.group(1).rstrip(".,)"))
                else:
                    fg.append(txt)                  # foreground: the real finding
            if not err:
                pending.append(txt)

# background: the finding is the retrieval/notification tool_result carrying the agent id
for txt in pending:
    if any(("<task_id>%s</task_id>" % aid) in txt or ("task_id: %s" % aid) in txt
           for aid in ack_agent_ids):
        results_by_task.append(txt)

out = fg + results_by_task
if out:
    sys.stdout.write("\n".join(out))
    sys.exit(0)
sys.exit(1)
PY
}

# agent_ran <file> <name>: boolean form of agent_result (spawn + non-error return).
agent_ran() { agent_result "$1" "$2" >/dev/null; }

# refusal_guard <text>: exits 1 (i.e. "looks like a refusal") when the text reads
# as a refusal/apology rather than an answer. Belt-and-braces on top of the
# structural assertions; never the primary check.
refusal_guard() {
  python3 - "$1" <<'PY'
import re, sys
t = sys.argv[1].lower()
bad = ["i can't", "i cannot", "i won't", "unable to", "i'm sorry", "cannot comply", "no such skill", "is not in my context", "don't have access"]
sys.exit(1 if any(b in t for b in bad) else 0)
PY
}

# ---------- cost banner ----------

announce() { # $1 calls  $2 writes-description  $3 relative cost
  echo "mode: $mode — live Claude calls: $1 · disposable-workspace writes: $2 · relative cost: $3"
  echo "checkout snapshot taken; will be compared after the battery."
  echo
}

# ---------- probes: rules ----------

probe_rules() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  local schema='{"type":"object","properties":{"rule_titles":{"type":"array","items":{"type":"string"}},"doctrine_pointer_present":{"type":"boolean"},"doctrine_index_path":{"type":"string"}},"required":["rule_titles","doctrine_pointer_present","doctrine_index_path"]}'
  run_probe "$ws" "$cap" \
    "Without using any tools: report the titles of the write-time rules currently in your context, whether a Toolkit doctrine pointer is present, and the path that pointer names. If none are present, return empty values honestly." \
    --output-format json --json-schema "$schema" --disallowedTools "Write" "Edit" "NotebookEdit" "Bash"
  if [ "$(probe_rc "$cap")" != "0" ]; then
    no "rules: session failed (rc=$(probe_rc "$cap"), stderr: $(head -c 120 "$cap/err" 2>/dev/null))"; preserve_ws "$cap"; cleanup_ws "$ws"; return
  fi
  local titles pointer path
  titles="$(structured_field "$cap" rule_titles 2>/dev/null)" || { no "rules: structured output unparseable"; preserve_ws "$cap"; cleanup_ws "$ws"; return; }
  pointer="$(structured_field "$cap" doctrine_pointer_present)"
  path="$(structured_field "$cap" doctrine_index_path)"
  local lc; lc="$(printf '%s' "$titles" | tr '[:upper:]' '[:lower:]')"
  local hits=0
  for t in test security error database; do case "$lc" in *"$t"*) hits=$((hits+1));; esac; done
  # Expected facts come from the injected rules, never from this prompt.
  if [ "$hits" -ge 3 ]; then ok "write-time rules reached the session ($hits/4 expected concerns named)"; else no "rules: expected rule concerns missing (got: $(printf '%.100s' "$titles"))"; preserve_ws "$cap"; fi
  if [ "$pointer" = "True" ] || [ "$pointer" = "true" ]; then
    case "$path" in *CLAUDE.md*) ok "doctrine pointer present and names the index";; *) no "doctrine pointer present but path wrong: $path"; preserve_ws "$cap";; esac
  else
    no "doctrine pointer NOT in context (honest negative — this must fail)"; preserve_ws "$cap"
  fi
  cleanup_ws "$ws"; [ "${PRESERVED[*]:-}" = "" ] && cleanup_ws "$cap" || true
}

# ---------- probes: skills (schema-structured content facts; the asked-for fact
# is never in the prompt; interactive behavior stays manual per VERIFY.md) ----------

skill_probe() { # $1 name  $2 prompt  $3 python-check-expr on `a` (lowercased answer)
  local name="$1" prompt="$2" check="$3" ws cap a
  ws="$(mkws)"; cap="$(mkws)"
  run_probe "$ws" "$cap" "$prompt" \
    --output-format json --json-schema '{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}' \
    --disallowedTools "Write" "Edit" "NotebookEdit"
  if [ "$(probe_rc "$cap")" != "0" ]; then no "$name (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; cleanup_ws "$ws"; return; fi
  a="$(structured_field "$cap" answer 2>/dev/null)" || { no "$name (unparseable output)"; preserve_ws "$cap"; cleanup_ws "$ws"; return; }
  if ! refusal_guard "$a"; then no "$name (refusal/absence answer: $(printf '%.80s' "$a"))"; preserve_ws "$cap"; cleanup_ws "$ws"; return; fi
  if python3 -c "import sys; a=sys.argv[1].lower(); sys.exit(0 if ($check) else 1)" "$a"; then
    ok "$name"
  else
    no "$name (got: $(printf '%.80s' "$a"))"; preserve_ws "$cap"
  fi
  cleanup_ws "$ws"
}

probe_skills() {
  skill_probe "testing-gate states its one question" \
    "Invoke the testing-gate skill. Without waiting for my reply, report as the answer the exact question it asks." \
    "'manual verification' in a and 'test' in a"
  skill_probe "plan-guide knows its lifecycle + naming" \
    "Load the plan-guide skill. Report as the answer: the canonical plan note filename pattern, and every status lifecycle value it defines." \
    "'plan - ' in a and 'in-progress' in a and 'abandoned' in a"
  skill_probe "execution-guide knows its progress sections" \
    "Load the execution-guide skill. Report as the answer the exact headings of its progress-report format." \
    "'files inspected' in a and 'checks performed' in a"
  skill_probe "gitlab-mr-review knows its tooling" \
    "Load the gitlab-mr-review skill. Report as the answer the CLI tool it depends on for API access." \
    "'glab' in a"
  skill_probe "grill knows its artifact targets" \
    "Invoke the grill skill conceptually. Do not write files and do not wait for answers. Report as the answer the artifact paths it writes at the end." \
    "'docs/glossary.md' in a and 'docs/decisions' in a"
  skill_probe "test-first knows its loop" \
    "Load the test-first skill. Report as the answer the name of the loop it runs and when it engages." \
    "'red' in a and 'green' in a"
  skill_probe "handoff knows its fallback location" \
    "Load the handoff skill. Report as the answer where the note goes when no active plan directory exists." \
    "'_handoffs' in a"
  skill_probe "resolving-merge-conflicts knows its helper script" \
    "Load the resolving-merge-conflicts skill. Report as the answer the name of the script it runs for the overview." \
    "'merge-conflict-overview' in a"
  skill_probe "wayfinder knows its outputs" \
    "Load the wayfinder skill. Report as the answer what kinds of plan notes it emits." \
    "('umbrella' in a or 'parent' in a) and ('child' in a or 'stub' in a)"
  skill_probe "jira knows its fail-fast probe, verbatim-fetch rule, and read-only boundary" \
    "Load the jira skill. Without fetching any real ticket, answer these four questions in one message: (1) the exact command it runs first to fail fast on auth, (2) the exact flag that fetches ticket content byte-for-byte, (3) the flag it must never use as a content source, (4) does it ever write back to Jira, answered yes or no." \
    "'jira me' in a and '--raw' in a and '--plain' in a and ('no' in a or 'never' in a or 'read-only' in a)"
  skill_probe "red-team knows its engine and standing panel" \
    "Load the red-team skill. Report as the answer: the workflow it reuses for the review and the reviewer agents that are always on its panel." \
    "'review-mr' in a and 'code-reviewer' in a and 'silent-failure-hunter' in a and 'pr-test-analyzer' in a"
  skill_probe "inversion knows its sections and horizons" \
    "Load the inversion skill. Report as the answer its section headings in order and the two default horizons." \
    "a.find('autopsy')>=0 and a.find('autopsy')<a.find('verdict')<a.find('rebuild')<a.find('adversary')<a.find('tripwires') and 'six months' in a and 'three weeks' in a"
  skill_probe "review-threads knows its GitHub fix-then-resolve flow and merge gate" \
    "Load the review-threads skill. Report as the answer what it does on GitHub after the fix commit for a thread is pushed, and the two conditions of its merge gate." \
    "'resolve' in a and ('repl' in a or 'comment' in a) and 'merge' in a and 'green' in a"
  skill_probe "incident-investigate knows its scope fence" \
    "Load the incident-investigate skill. Without investigating anything, report as the answer: what does step 0, the scope fence, of the incident-investigate skill do, and where do adjacent findings go?" \
    "('restat' in a or 'named item' in a or 'question asked' in a) and 'outside scope' in a"
}

# ---------- probes: agents (fixture-based, event-verified) ----------

agent_events_flags() { printf -- "--output-format\nstream-json\n--verbose\n"; }

# Read-only agent probe: explorer digs a planted fact out of a fixture tree.
probe_agent_explorer() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "explorer: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  mkdir -p "$ws/src/deep/nested"
  printf '<?php\nclass Cfg {\n  const MAGIC_TIMEOUT = 4711;\n}\n' > "$ws/src/deep/nested/config.php"
  printf 'decoy\n' > "$ws/src/readme.txt"
  if ! fixture_commit "$ws"; then no "explorer: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  run_probe "$ws" "$cap" \
    "Spawn the toolkit:explorer subagent to find the numeric value of the MAGIC_TIMEOUT constant somewhere in this repository and report just that number back. Then state the number it found. $SYNC_HINT" \
    --output-format stream-json --verbose --disallowedTools "Write" "Edit" "NotebookEdit"
  if [ "$(probe_rc "$cap")" != "0" ]; then no "explorer probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  local res okev=1; res="$(agent_result "$cap/out" "explorer")" && okev=0
  local dirty; dirty="$(git -C "$ws" status --porcelain)"
  # 4711 comes from the fixture file; grep the agent's RETURNED result, not the whole
  # stream (which echoes the fixture it Read). Never in this prompt's assertion side.
  if [ $okev -eq 0 ] && printf '%s' "$res" | grep -q "4711" && [ -z "$dirty" ]; then
    ok "explorer: event-verified spawn+return, planted fact in its result, workspace untouched"
  else
    no "explorer: event=$okev fact-in-result=$(printf '%s' "$res" | grep -c 4711) dirty='${dirty}'"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

# Writing agent probe: implementer creates one exact file in the disposable repo.
probe_agent_implementer() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "implementer: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  printf 'seed\n' > "$ws/README.md"
  if ! fixture_commit "$ws"; then no "implementer: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  run_probe "$ws" "$cap" \
    "Spawn the toolkit:implementer subagent with this exact bounded task: create a file named greeting.txt in the repository root whose entire content is the single line: hello from fixture 4711. $SYNC_HINT" \
    --output-format stream-json --verbose --permission-mode acceptEdits
  if [ "$(probe_rc "$cap")" != "0" ]; then no "implementer probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  local okev=1; agent_ran "$cap/out" "implementer" && okev=0
  # Level-1 evidence: the observable file. A refusal cannot fake this.
  if [ $okev -eq 0 ] && [ -f "$ws/greeting.txt" ] && [ "$(cat "$ws/greeting.txt")" = "hello from fixture 4711" ]; then
    ok "implementer: event-verified spawn+return, exact file created in disposable repo"
  else
    no "implementer: event=$okev file=$([ -f "$ws/greeting.txt" ] && echo yes || echo no)"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

# Generic fixture probes for the remaining agents: planted-defect review fixtures
# (read-only) or bounded artifacts. Each asserts: rc 0, event-verified spawn+return,
# and a fixture-derived fact / observable result. See VERIFY.md for what stays manual.
probe_agent_generic() { # $1 agent  $2 fixture-fn  $3 prompt  $4 grep-fact  $5 writes(yes/no)
  local agent="$1" fixfn="$2" prompt="$3" fact="$4" writes="$5" ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "$agent: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  "$fixfn" "$ws"
  if ! fixture_commit "$ws"; then no "$agent: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  local -a flags=(--output-format stream-json --verbose)
  [ "$writes" = yes ] && flags+=(--permission-mode acceptEdits) || flags+=(--disallowedTools "Write" "Edit" "NotebookEdit")
  run_probe "$ws" "$cap" "$prompt $SYNC_HINT" "${flags[@]}"
  if [ "$(probe_rc "$cap")" != "0" ]; then no "$agent probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  # Grep the agent's RETURNED result, not the whole event stream (which echoes the
  # fixture the agent Read and the delegation prompt). Fact is an ERE (may be an
  # alternation of defect concepts).
  local res okev=1; res="$(agent_result "$cap/out" "$agent")" && okev=0
  if [ $okev -eq 0 ] && printf '%s' "$res" | grep -qiE -- "$fact"; then
    ok "$agent: event-verified spawn+return, fixture fact in its result"
  else
    no "$agent: event=$okev fact-in-result=$(printf '%s' "$res" | grep -qiE -- "$fact" && echo yes || echo no)"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

# Writing agent probe: frontend-designer must produce the exact artifact. The marker
# is allowed in the prompt because the assertion is on the FILE it wrote, not stream text.
probe_agent_frontend() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "frontend-designer: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  printf 'seed\n' > "$ws/README.md"
  if ! fixture_commit "$ws"; then no "frontend-designer: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  run_probe "$ws" "$cap" \
    "Spawn the toolkit:frontend-designer subagent with this exact bounded task: create a single self-contained page.html in the repository root with a heading that reads Fixture Dashboard and one styled button. No other files. $SYNC_HINT" \
    --output-format stream-json --verbose --permission-mode acceptEdits
  if [ "$(probe_rc "$cap")" != "0" ]; then no "frontend-designer probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  local okev=1; agent_ran "$cap/out" "frontend-designer" && okev=0
  # Level-1 evidence on the produced artifact: the requested heading, a <button>, and
  # styling (inline style=, a <style> block, or a class), AND that the only new/changed
  # path in the workspace is page.html.
  local haveheading havebutton havestyle changedok=0
  haveheading=$([ -f "$ws/page.html" ] && grep -q "Fixture Dashboard" "$ws/page.html" && echo 1 || echo 0)
  havebutton=$([ -f "$ws/page.html" ] && grep -qiE '<button' "$ws/page.html" && echo 1 || echo 0)
  havestyle=$([ -f "$ws/page.html" ] && grep -qiE '<style|style=|class=' "$ws/page.html" && echo 1 || echo 0)
  # extract the porcelain PATH field (2 status chars + space + path) and require the
  # only changed path to be page.html
  [ "$(git -C "$ws" status --porcelain | awk '{print $2}' | grep -vc '^page\.html$')" = "0" ] && changedok=1
  if [ $okev -eq 0 ] && [ "$haveheading" = 1 ] && [ "$havebutton" = 1 ] && [ "$havestyle" = 1 ] && [ "$changedok" = 1 ]; then
    ok "frontend-designer: event-verified, page.html has heading+button+styling, only page.html changed"
  else
    no "frontend-designer: event=$okev heading=$haveheading button=$havebutton style=$havestyle only-page=$changedok"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

# ---------- probes: SubagentStart hook (recital + bait) ----------

# Recital probe: proves the SubagentStart hook actually reaches a spawned worker on
# THIS machine's Claude Code version, by pointing a disposable workspace's local
# settings at THIS CHECKOUT's subagent-rules.sh (fixture_subagent_hook_ws) and asking
# the spawned worker to name what is in its own context. "config coupling" is never
# named in the prompt: a hit can only come from the hook-injected rule body.
probe_subagent_rules() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "subagent-rules: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  if ! fixture_subagent_hook_ws "$ws"; then no "subagent-rules: workspace hook registration failed (setup)"; preserve_ws "$ws"; return; fi
  printf 'seed\n' > "$ws/README.md"
  if ! fixture_commit "$ws"; then no "subagent-rules: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  run_probe "$ws" "$cap" \
    "Spawn the toolkit:explorer subagent and ask it this exact question, without using any tools: list the titles of every write-time rule currently present in your own context. Report its answer back to me verbatim. $SYNC_HINT" \
    --output-format stream-json --verbose --disallowedTools "Write" "Edit" "NotebookEdit"
  if [ "$(probe_rc "$cap")" != "0" ]; then no "subagent-rules probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  local res okev=1; res="$(agent_result "$cap/out" "explorer")" && okev=0
  if [ $okev -eq 0 ] && printf '%s' "$res" | grep -qiE "config[- ]coupling"; then
    ok "subagent-rules: SubagentStart hook injects toolkit rules into a spawned worker (config coupling named, never in the prompt)"
  else
    no "subagent-rules: event=$okev config-coupling-named=$(printf '%s' "$res" | grep -qiE "config[- ]coupling" && echo yes || echo no)"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

# Bait fixture: a route already centrally defined once (src/api.js) and a tenant value
# already externalized to committed config (tenants.json) — the compliant shape the
# config-coupling rule asks for. A per-tenant CONFIG file carrying a tenant id is itself
# a legitimate committed-config surface (the rule's bullet 1 targets values whose change
# would require a CODE edit), so a bait that only ever writes config cannot produce an
# unambiguous violation. This fixture instead asks for a new CODE file (a handler), so
# reusing the seeded const/config — rather than copying their values inline — is the
# only compliant way to satisfy the brief.
fx_tenant_webhook() {
  mkdir -p "$1/src"
  printf "export const ORDERS_ROUTE = '/api/v1/orders';\n\nexport function ordersHandler(req, res) {\n  res.send(ORDERS_ROUTE);\n}\n" > "$1/src/api.js"
  printf '{\n  "tenant": "acme"\n}\n' > "$1/tenants.json"
}

# strip_js_comments <file>: prints the file's content with // line comments and /* */
# block comments removed, honoring string/template-literal state (', ", `) so a "//" or
# "/*" inside a real string/URL is never mistaken for a comment start. Used so the bait
# probe's positive checks (route/tenant referenced) cannot be satisfied by a comment-only
# mention that never actually exercises the seam.
# Limitation: a regex literal holding an unbalanced quote char can desync the scanner's
# string-tracking; acceptable at the scale of these small generated fixtures.
strip_js_comments() {
  python3 - "$1" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out, i, n, in_str = [], 0, len(s), None
while i < n:
    c = s[i]
    if in_str:
        out.append(c)
        if c == "\\" and i + 1 < n:
            out.append(s[i + 1]); i += 2; continue
        if c == in_str:
            in_str = None
        i += 1; continue
    if c in ("'", '"', "`"):
        in_str = c; out.append(c); i += 1; continue
    if c == "/" and i + 1 < n and s[i + 1] == "/":
        while i < n and s[i] != "\n":
            i += 1
        continue
    if c == "/" and i + 1 < n and s[i + 1] == "*":
        i += 2
        while i + 1 < n and not (s[i] == "*" and s[i + 1] == "/"):
            i += 1
        i += 2
        continue
    out.append(c); i += 1
sys.stdout.write("".join(out))
PY
}

# tenant_literal_hit <file>: true if the tenant value "acme" appears as, or embedded in,
# any single-quoted, double-quoted, or backtick(-template) string literal in the file —
# catches `acme`, longer strings like "prefix-acme-suffix", and template literals, not
# just an exact bare 'acme'/"acme" match.
tenant_literal_hit() {
  local f="$1"
  grep -qE "'[^']*acme[^']*'" "$f" 2>/dev/null && return 0
  grep -qE "\"[^\"]*acme[^\"]*\"" "$f" 2>/dev/null && return 0
  grep -qE '`[^`]*acme[^`]*`' "$f" 2>/dev/null && return 0
  return 1
}

# tenantref_hit <file>: true only if the file references the seeded config, either the
# file path tenants.json (require/import/read of it) or a dotted access on its "tenant"
# key (e.g. config.tenant) — mirrors how the route side is pinned by the ORDERS_ROUTE
# symbol name, not just the bare word "route". A variable merely named "tenant" that
# never touches the config (vacuous) does not count.
tenantref_hit() {
  local f="$1"
  grep -qiE "tenants\.json" "$f" 2>/dev/null && return 0
  grep -qiE '\.tenant\b' "$f" 2>/dev/null && return 0
  return 1
}

# Bait probe: proves the injected config-coupling rule changes what a writing worker
# produces, not just that text reaches it. The brief states the parent plan already
# commits to a second tenant and asks for a tiny new file (webhooks.js) that reuses the
# seeded route const and tenant config. Assertions require BOTH a positive (webhooks.js
# actually references the shared route const and actually mentions tenant at all) and a
# negative (the route literal appears nowhere else, the tenant literal appears nowhere)
# so omitting the route or tenant handling entirely cannot pass vacuously. The assertion
# is on the written file(s) only; config-coupling.md is never quoted in the prompt.
probe_config_coupling_bait() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "config-coupling-bait: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  if ! fixture_subagent_hook_ws "$ws"; then no "config-coupling-bait: workspace hook registration failed (setup)"; preserve_ws "$ws"; return; fi
  fx_tenant_webhook "$ws"
  if ! fixture_commit "$ws"; then no "config-coupling-bait: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  run_probe "$ws" "$cap" \
    "The parent plan already commits to onboarding a second tenant next quarter — this is decided, not speculative. Spawn the toolkit:implementer subagent with this exact bounded task: create a file named webhooks.js in the repository root. It must export a handler that posts to the orders route defined in src/api.js and logs a message prefixed with the tenant configured in tenants.json. $SYNC_HINT" \
    --output-format stream-json --verbose --permission-mode acceptEdits
  if [ "$(probe_rc "$cap")" != "0" ]; then no "config-coupling-bait probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  local okev=1; agent_ran "$cap/out" "implementer" && okev=0
  local wf="$ws/webhooks.js" routecount=0 routeref=0 tenantlit=0 tenantref=0
  # Both positive and negative checks run against comment-stripped content (temp files):
  # a "// uses ORDERS_ROUTE" mention must not count as a real reference, and a compliant
  # "// never hardcode 'acme'" comment must not count as a hardcoded literal or route dup.
  local wf_nc all_nc jsf
  wf_nc="$(mktemp -t toolkit-ftest-nc)"; all_nc="$(mktemp -t toolkit-ftest-nc)"
  [ -f "$wf" ] && strip_js_comments "$wf" > "$wf_nc"
  while IFS= read -r jsf; do strip_js_comments "$jsf" >> "$all_nc"; done < <(find "$ws" -name '*.js')
  routecount="$(grep -o '/api/v1/orders' "$all_nc" 2>/dev/null | wc -l | tr -d ' ')"
  [ -f "$wf" ] && grep -q "ORDERS_ROUTE" "$wf_nc" && routeref=1
  [ -f "$wf" ] && tenant_literal_hit "$wf_nc" && tenantlit=1
  [ -f "$wf" ] && tenantref_hit "$wf_nc" && tenantref=1
  rm -f "$wf_nc" "$all_nc"
  if [ $okev -eq 0 ] && [ -f "$wf" ] && [ "$routeref" = "1" ] && [ "$routecount" = "1" ] && [ "$tenantlit" = "0" ] && [ "$tenantref" = "1" ]; then
    ok "config-coupling-bait: webhooks.js reuses the shared route const (defined once workspace-wide) and derives the tenant instead of hardcoding it"
  else
    no "config-coupling-bait: event=$okev file=$([ -f "$wf" ] && echo yes || echo no) route-ref=$routeref route-occurrences=$routecount hardcoded-tenant=$tenantlit tenant-ref=$tenantref"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

fx_offbyone() { mkdir -p "$1/src"; printf 'function lastItem(arr) {\n  // returns the last element\n  return arr[arr.length];\n}\nmodule.exports = { lastItem };\n' > "$1/src/util.js"; }
fx_sqli()     { mkdir -p "$1/src"; printf '<?php\nfunction findUser($db, $name) {\n  return $db->query("SELECT * FROM users WHERE name = \x27" . $name . "\x27");\n}\n' > "$1/src/repo.php"; }
fx_swallow()  { mkdir -p "$1/src"; printf 'async function save(data) {\n  try {\n    await api.post("/save", data);\n  } catch (e) {\n    // ignore\n  }\n  return true;\n}\n' > "$1/src/save.js"; }
fx_mocktest() { mkdir -p "$1/test"; printf 'test("saves data", () => {\n  const spy = jest.fn().mockReturnValue(true);\n  expect(spy()).toBe(true);\n});\n' > "$1/test/save.test.js"; }
fx_nplus1()   { mkdir -p "$1/src"; printf 'async function orderTotals(orders) {\n  const out = [];\n  for (const o of orders) {\n    const items = await db.query("SELECT * FROM items WHERE order_id = ?", [o.id]);\n    out.push(items.length);\n  }\n  return out;\n}\n' > "$1/src/report.js"; }
fx_staledoc() { mkdir -p "$1/docs" "$1/src"; printf '# API\n\nCall `fetchUser(id, options)` to load a user.\n' > "$1/docs/api.md"; printf 'function fetchAccount(id) { return http.get(`/accounts/${id}`); }\nmodule.exports = { fetchAccount };\n' > "$1/src/api.js"; }
fx_badplan()  { printf -- '---\ntype: plan\nplan: fixture-plan\nstatus: review\n---\n\n## Objective\nMigrate the sessions table to a new schema.\n\n## Implementation Steps\n1. Run the migration directly in production.\n\n## Validation Steps\nIt will probably work.\n\n## Rollback Notes\n\n## Risks\n' > "$1/plan - fixture-plan.md"; }
fx_data()     { printf 'id,name\n1,a\n2,b\n3,c\n' > "$1/data.csv"; }
fx_planfix()  { printf 'Feature request: add a --verbose flag to the CLI entry in src/cli.js that logs each step.\n' > "$1/REQUEST.md"; mkdir -p "$1/src"; printf 'function main(args) { run(args); }\nmodule.exports = { main };\n' > "$1/src/cli.js"; }
# Roadmap states the committed second tenant (coupling-reviewer's own rule requires a
# findable commitment before it may flag an axis), src/orders.js hardcodes that tenant's
# id in a logic-path comparison, and src/routes.js duplicates the route string that
# orders.js already carries as a named const — two independent, obvious defects.
fx_hardcoded_tenant() {
  mkdir -p "$1/src" "$1/docs"
  printf '# Roadmap\n\nQ3: onboard a second tenant, "beta-co", onto the same order pipeline. This is committed, not speculative.\n' > "$1/docs/roadmap.md"
  printf "export const ORDERS_ROUTE = '/api/v1/orders';\n\nfunction handleOrder(req, res) {\n  if (req.tenantId === 'acme-co') {\n    res.send(ORDERS_ROUTE);\n  }\n}\n\nmodule.exports = { handleOrder };\n" > "$1/src/orders.js"
  printf "function registerRoutes(router) {\n  router.post('/api/v1/orders', require('./orders').handleOrder);\n}\n\nmodule.exports = { registerRoutes };\n" > "$1/src/routes.js"
}

# Bespoke (not probe_agent_generic) because the fact check needs AND, not OR: a single
# ERE like "acme-co|duplicat" would false-pass on a clean verdict such as "no duplication
# found" (matches "duplicat" alone). Require the fixture's own hardcoded tenant token AND
# an independent defect term, so a clean-verdict sentence cannot satisfy both.
probe_coupling_reviewer() {
  local ws cap
  ws="$(mkws)"; cap="$(mkws)"
  if ! fixture_repo "$ws"; then no "coupling-reviewer: fixture repo init failed (setup)"; preserve_ws "$ws"; return; fi
  fx_hardcoded_tenant "$ws"
  if ! fixture_commit "$ws"; then no "coupling-reviewer: fixture commit failed (setup) — no Claude call made"; preserve_ws "$ws"; return; fi
  run_probe "$ws" "$cap" \
    "Spawn the toolkit:coupling-reviewer subagent to review src/orders.js and src/routes.js in this repository, using docs/roadmap.md for commitment context. Report its findings. $SYNC_HINT" \
    --output-format stream-json --verbose --disallowedTools "Write" "Edit" "NotebookEdit"
  if [ "$(probe_rc "$cap")" != "0" ]; then no "coupling-reviewer probe (rc=$(probe_rc "$cap"))"; preserve_ws "$cap"; preserve_ws "$ws"; return; fi
  local res okev=1; res="$(agent_result "$cap/out" "coupling-reviewer")" && okev=0
  local tenant_named=0 defect_named=0
  printf '%s' "$res" | grep -qiE "acme-co" && tenant_named=1
  printf '%s' "$res" | grep -qiE "duplicat(e|ed|ion)|two places|defined (twice|in (two|multiple) places)" && defect_named=1
  if [ $okev -eq 0 ] && [ "$tenant_named" = 1 ] && [ "$defect_named" = 1 ]; then
    ok "coupling-reviewer: event-verified spawn+return, names the hardcoded tenant and the duplicated route"
  else
    no "coupling-reviewer: event=$okev tenant-named=$tenant_named defect-named=$defect_named"
    preserve_ws "$cap"; preserve_ws "$ws"; return
  fi
  cleanup_ws "$ws"; cleanup_ws "$cap"
}

probe_agents() {
  local want="$only_agent"
  run_one() { [ -z "$want" ] || [ "$want" = "$1" ]; }
  run_one explorer && probe_agent_explorer
  run_one implementer && probe_agent_implementer
  run_one planner && probe_agent_generic planner fx_planfix \
    "Spawn the toolkit:planner subagent to produce a short bounded implementation plan for the request in REQUEST.md against this repository. Have it name the exact function it would modify. Report its plan." \
    "main" no
  run_one verifier && probe_agent_generic verifier fx_data \
    "Spawn the toolkit:verifier subagent to open data.csv in this repository, count the data rows excluding the header line, and report the number it measured." \
    "(^|[^0-9])3([^0-9]|\$)" no
  run_one code-reviewer && probe_agent_generic code-reviewer fx_offbyone \
    "Spawn the toolkit:code-reviewer subagent to review src/util.js in this repository. Report the defects it finds, naming the function." \
    "lastItem" no
  run_one security-reviewer && probe_agent_generic security-reviewer fx_sqli \
    "Spawn the toolkit:security-reviewer subagent to review src/repo.php in this repository. Report what it finds, naming the vulnerability class." \
    "injection" no
  run_one silent-failure-hunter && probe_agent_generic silent-failure-hunter fx_swallow \
    "Spawn the toolkit:silent-failure-hunter subagent to review src/save.js in this repository. Report the error-handling defect it finds and what happens to a failure at runtime." \
    "swallow|silent|ignored|discard|suppress" no
  run_one pr-test-analyzer && probe_agent_generic pr-test-analyzer fx_mocktest \
    "Spawn the toolkit:pr-test-analyzer subagent to judge test/save.test.js in this repository. Report its verdict on what the test actually verifies." \
    "mock" no
  run_one performance-reviewer && probe_agent_generic performance-reviewer fx_nplus1 \
    "Spawn the toolkit:performance-reviewer subagent to review src/report.js in this repository. Report the bottleneck it identifies by its usual name." \
    "n+1" no
  run_one doc-reviewer && probe_agent_generic doc-reviewer fx_staledoc \
    "Spawn the toolkit:doc-reviewer subagent to cross-check docs/api.md against src/api.js in this repository. Report the mismatch it finds." \
    "fetchUser" no
  run_one plan-critic && probe_agent_generic plan-critic fx_badplan \
    "Spawn the toolkit:plan-critic subagent to red-team the plan note in this directory. Report its material objections." \
    "rollback" no
  # coupling-reviewer is defined in THIS checkout (plugins/toolkit/agents/coupling-reviewer.md)
  # but is currently untracked/uncommitted, so it is NOT part of the INSTALLED plugin
  # snapshot that subagent_type resolution reads from. Only the SubagentStart hook path
  # (fixture_subagent_hook_ws) is pinned to this checkout by absolute path; agent
  # resolution itself is not, and there is no equivalent override for it. Until the next
  # `/plugin` install/update pulls this file into the installed snapshot, this probe will
  # genuinely fail with an "Agent type ... not found" tool_result — agent_result already
  # refuses to count an is_error tool_result as "ran" (see self-test), so that failure is
  # honestly reported, not silently swallowed. That is the correct outcome right now, not
  # a harness bug — never special-case it into a fake pass.
  run_one coupling-reviewer && probe_coupling_reviewer
  run_one frontend-designer && probe_agent_frontend
  run_one subagent-rules && probe_subagent_rules
  run_one config-coupling-bait && probe_config_coupling_bait
}

# ---------- self-test (no network, no Claude) ----------

self_test() {
  echo "== Harness self-tests (no Claude calls) =="
  local t; t="$(mkws)"

  # workspace + fixture creation
  fixture_repo "$t"; fx_offbyone "$t"
  [ -f "$t/src/util.js" ] && git -C "$t" rev-parse --git-dir >/dev/null 2>&1 && ok "workspace + fixture repo setup" || no "workspace setup"

  # structured-output parsing from synthetic captures
  local cap; cap="$(mkws)"
  printf '{"is_error": false, "result": "{\\"answer\\": \\"the loop is red-green\\"}"}\n' > "$cap/out"; echo 0 > "$cap/rc"
  [ "$(structured_field "$cap" answer)" = "the loop is red-green" ] && ok "structured field parsing" || no "structured field parsing"

  # is_error must fail parsing
  printf '{"is_error": true, "result": "boom"}\n' > "$cap/out"
  structured_field "$cap" answer >/dev/null 2>&1 && no "is_error not rejected" || ok "is_error rejected"

  # agent event parsing: launch + return detected
  cat > "$cap/events" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Agent","input":{"subagent_type":"toolkit:explorer","prompt":"find it"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"found 4711"}]}}
EOF
  agent_ran "$cap/events" "explorer" && ok "agent spawn+return detected in events" || no "agent event detection"

  # agent_result returns ONLY the matched agent's result text (not echoed stream content)
  [ "$(agent_result "$cap/events" "explorer")" = "found 4711" ] && ok "agent_result returns the agent's result text" || no "agent_result text extraction"

  # launch without return must NOT pass
  head -1 "$cap/events" > "$cap/events2"
  agent_ran "$cap/events2" "explorer" && no "missing tool_result not caught" || ok "launch-without-return rejected"

  # an ERROR tool_result must NOT count as "ran" (broken/missing agent → error result)
  cat > "$cap/events_err" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_9","name":"Task","input":{"subagent_type":"toolkit:explorer","prompt":"x"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_9","is_error":true,"content":"Agent type 'toolkit:explorer' not found"}]}}
EOF
  agent_ran "$cap/events_err" "explorer" && no "error tool_result false-passed as ran" || ok "error tool_result rejected (not counted as ran)"

  # BACKGROUND agent: the launched tool_result is only a launch-ack; the finding
  # arrives in a later tool_result carrying <task_id> matching the ack's agentId.
  cat > "$cap/events_bg" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_bg","name":"Task","input":{"subagent_type":"toolkit:explorer","prompt":"x"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_bg","content":"Async agent launched successfully. agentId: abc123def0"}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_poll","content":"<task_id>abc123def0</task_id>\nthe agent found 4711 in config"}]}}
EOF
  printf '%s' "$(agent_result "$cap/events_bg" explorer)" | grep -q 4711 && ok "background finding extracted via task-id-matched retrieval" || no "background finding not extracted"

  # a background launch-ack with NO matching completion must NOT count (can't prove it)
  printf '%s\n%s\n' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_b2","name":"Task","input":{"subagent_type":"toolkit:explorer"}}]}}' \
    '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_b2","content":"Async agent launched successfully. agentId: zzz999"}]}}' > "$cap/events_ackonly"
  agent_ran "$cap/events_ackonly" "explorer" && no "launch-ack alone false-passed" || ok "background launch-ack alone rejected (no completion)"

  # agent_result's isinstance(msg, dict) guard must survive a "system" event whose
  # "message" is a plain string (not content blocks) interleaved with a real spawn+return,
  # and still reach the correct verdict rather than crashing or losing the finding.
  cat > "$cap/events_sysmsg" <<'EOF'
{"type":"system","message":"Session started"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_sys","name":"Agent","input":{"subagent_type":"toolkit:explorer","prompt":"find it"}}]}}
{"type":"system","message":"a plain-string system message mid-stream"}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_sys","content":"found 4711 despite the string system messages"}]}}
EOF
  printf '%s' "$(agent_result "$cap/events_sysmsg" explorer)" | grep -q 4711 && ok "plain-string system-event message does not break the parser (isinstance guard)" || no "plain-string system-event message broke agent_result"

  # a refusal that merely ECHOES the marker must not pass: no tool_use event at all
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"I cannot spawn agents, but RAN:explorer 4711"}]}}\n' > "$cap/events3"
  agent_ran "$cap/events3" "explorer" && no "echo-refusal false-passed event check" || ok "echo-refusal cannot pass the event check"

  # refusal guard on content probes
  refusal_guard "I'm sorry, that skill is not in my context, manual verification impossible" && no "refusal guard missed a refusal" || ok "refusal answer rejected despite matching words"
  refusal_guard "the gate asks: do we require tests or is manual verification sufficient" && ok "genuine answer passes refusal guard" || no "refusal guard too aggressive"

  # nonzero rc short-circuits
  echo 1 > "$cap/rc"
  [ "$(probe_rc "$cap")" = "1" ] && ok "exit-code capture readable" || no "exit-code capture"

  # fixture setup fails closed: force a failing commit signer (deterministic, does
  # not depend on the machine's git config) and confirm fixture_commit reports failure
  # rather than returning success while git printed a fatal error.
  local fs; fs="$(mkws)"
  fixture_repo "$fs" >/dev/null 2>&1
  git -C "$fs" config commit.gpgsign true; git -C "$fs" config gpg.program /bin/false
  echo x > "$fs/f.txt"
  if fixture_commit "$fs"; then no "fixture_commit did NOT fail closed on a failing signer"; else ok "fixture setup fails closed (commit failure detected, no false success)"; fi
  cleanup_ws "$fs"

  # checkout drift detection
  local fake; fake="$(mkws)"
  fixture_repo "$fake"; echo x > "$fake/a.txt"; git -C "$fake" add -A >/dev/null; git -C "$fake" commit -qm x
  local before after
  before="$(git -C "$fake" status --porcelain)"
  echo y > "$fake/b.txt"
  after="$(git -C "$fake" status --porcelain)"
  [ "$before" != "$after" ] && ok "checkout drift detection catches a new file" || no "drift detection"

  # H1 regression: an unrecognized `agents <name>` selector must ERROR (nonzero exit,
  # message listing valid probe names), never silently select nothing and let the
  # battery report a false success. The subprocess exits before any run_probe call, so
  # this makes no Claude call itself.
  local unk_rc unk_err
  bash "$SELF_ROOT/functional-test.sh" agents totally-bogus-probe-name >"$cap/unknown_out" 2>"$cap/unknown_err"
  unk_rc=$?
  unk_err="$(cat "$cap/unknown_err" 2>/dev/null)"
  if [ "$unk_rc" -ne 0 ] && printf '%s' "$unk_err" | grep -qi "valid probes"; then
    ok "unknown probe-selection argument errors (rc=$unk_rc) and lists valid probe names"
  else
    no "unknown probe-selection argument did not error correctly (rc=$unk_rc, stderr: $(printf '%.120s' "$unk_err"))"
  fi

  # H1 drift guard: AGENT_PROBE_NAMES (what known_agent_probe validates against) must
  # match every name actually dispatched via `run_one NAME &&` in probe_agents(), both
  # ways ("&&" anchors on the real dispatch idiom, not prose that happens to say run_one).
  local rn ap
  rn="$(grep -oE 'run_one [a-z0-9-]+ &&' "$SELF_ROOT/functional-test.sh" | sed -E 's/^run_one ([a-z0-9-]+) &&/\1/' | sort -u)"
  ap="$(printf '%s\n' "${AGENT_PROBE_NAMES[@]}" | sort -u)"
  [ "$rn" = "$ap" ] && ok "AGENT_PROBE_NAMES matches every run_one probe name (no drift)" || no "AGENT_PROBE_NAMES drifted from run_one probe names"

  # cleanup guard refuses non-harness paths
  cleanup_ws "/etc" 2>/dev/null
  [ -d /etc ] && ok "cleanup guard refuses foreign paths" || no "cleanup guard"

  # failure preservation records the path
  PRESERVED=()
  preserve_ws "$cap" >/dev/null
  [ "${#PRESERVED[@]}" -eq 1 ] && ok "failed workspace preserved" || no "workspace preservation"
  PRESERVED=()

  cleanup_ws "$t"; cleanup_ws "$cap"; cleanup_ws "$fake"
}

# ---------- main ----------

case "$mode" in
  self-test)
    self_test
    ;;
  rules)
    announce 1 "none (read-only)" "low"
    SNAP_BEFORE="$(snapshot_checkout)"
    echo "== Rules + doctrine reach the session (schema-structured) =="
    probe_rules
    ;;
  skills)
    announce 14 "none (read-only)" "medium"
    SNAP_BEFORE="$(snapshot_checkout)"
    echo "== Skills load their contract facts (schema-structured; interactive behavior stays manual) =="
    probe_skills
    ;;
  agents)
    if [ -n "$only_agent" ] && ! known_agent_probe "$only_agent"; then
      echo "unknown probe: '$only_agent'" >&2
      echo "valid probes: ${AGENT_PROBE_NAMES[*]}" >&2
      exit 2
    fi
    if [ -n "$only_agent" ]; then announce 1 "implementer/frontend-designer write inside their disposable repos" "low-medium"; else announce 15 "implementer + frontend-designer + config-coupling-bait write inside their disposable repos" "high"; fi
    SNAP_BEFORE="$(snapshot_checkout)"
    echo "== Agent probes (fixture-based, stream-event verified) =="
    probe_agents
    ;;
  orchestration)
    echo "== Orchestration: leaf-worker property =="
    echo "No live probe: a headless conductor transcript cannot prove a NESTED spawn"
    echo "did not happen inside a subagent, and the old LEAF-OK token check could be"
    echo "satisfied by an echo. The property is enforced statically (verify.sh asserts"
    echo "no worker allowlist contains Agent/Task) and verified live via the manual"
    echo "checklist in VERIFY.md."
    exit 0
    ;;
  all)
    announce 30 "implementer + frontend-designer + config-coupling-bait write inside their disposable repos" "high"
    SNAP_BEFORE="$(snapshot_checkout)"
    echo "== Rules =="; probe_rules
    echo "== Skills =="; probe_skills
    echo "== Agents =="; probe_agents
    ;;
  *)
    echo "unknown mode: $mode (use self-test|rules|skills|agents|orchestration|all)" >&2
    exit 2
    ;;
esac

# checkout drift check for live modes
if [ "${SNAP_BEFORE+x}" = x ]; then
  SNAP_AFTER="$(snapshot_checkout)"
  if [ "$SNAP_BEFORE" = "$SNAP_AFTER" ]; then
    ok "toolkit checkout unchanged by the battery (exact status snapshot match)"
  else
    no "toolkit checkout CHANGED during the battery — investigate immediately"
    diff <(printf '%s\n' "$SNAP_BEFORE") <(printf '%s\n' "$SNAP_AFTER") | head -10
  fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
if [ "${#PRESERVED[@]}" -gt 0 ]; then
  echo "preserved workspaces:"; printf '  %s\n' "${PRESERVED[@]}"
fi
[ "$fail" -eq 0 ]
