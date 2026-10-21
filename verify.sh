#!/usr/bin/env bash
# Mechanical acceptance battery for the toolkit plugin. Deterministic checks only;
# live-session behavior (agent spawns, skill prompts, doctrine adherence) is covered
# by the companion checklist in VERIFY.md. Run from anywhere: bash verify.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$ROOT/plugins/toolkit"
export CLAUDE_PLUGIN_ROOT="$P"
pass=0; fail=0; skip=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
skip() { printf '  \033[33m-\033[0m %s\n' "$1"; skip=$((skip+1)); }
# report: name, actual, expected-substring (an empty needle is a caller bug, not a match)
want() { [ -z "$3" ] && { no "$1 (got: ${2:0:60})"; return; }; case "$2" in *"$3"*) ok "$1";; *) no "$1 (got: ${2:0:60})";; esac; }
# report on exit code
code() { if [ "$2" -eq "$3" ]; then ok "$1"; else no "$1 (exit $2, wanted $3)"; fi; }
# suite_pass: pure predicate (no printing). "RESULT: N passed, M failed" line +
# minimum-expected-passed -> exit 0 iff 0 failed AND at least <min> passed. An empty
# suite ("0 passed, 0 failed", e.g. a fixtures dir that globbed nothing) FAILS here,
# instead of green-passing the old `, 0 failed` substring match.
suite_pass() {
  local p f
  p=$(printf '%s' "$1" | sed -nE 's/.*RESULT: ([0-9]+) passed.*/\1/p')
  f=$(printf '%s' "$1" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')
  [ "${f:-1}" = "0" ] && [ "${p:-0}" -ge "$2" ]
}
# suite_ok: name, RESULT line, min-passed -> report via ok/no.
suite_ok() { if suite_pass "$2" "$3"; then ok "$1"; else no "$1 (got: ${2:0:60})"; fi; }
# Self-check the reporting helpers (the meta-verifier must fail closed — this is the
# class of bug that let a failing/empty suite read as green). Drives the REAL want/code
# in subshells (so the live pass/fail counters are never written) and requires `fail`
# to have incremented. A failure here bypasses ok/no entirely and exits 2 directly: this
# is the one verdict that cannot be reported through the counters it is testing.
_sc=0
suite_pass "RESULT: 0 passed, 0 failed" 1 && _sc=1                       # empty suite must NOT pass
suite_pass "RESULT: 40 passed, 3 failed" 1 && _sc=1                      # any failures must NOT pass
suite_pass "RESULT: 55 passed, 0 failed" 55 || _sc=1                     # a real green must pass
_f1=$(fail=0; want "sc-mismatch" "abc" "xyz" >/dev/null; printf '%s' "$fail");  [ "$_f1" = "1" ] || _sc=1
_f1=$(fail=0; want "sc-empty-needle" "abc" "" >/dev/null; printf '%s' "$fail"); [ "$_f1" = "1" ] || _sc=1
_f1=$(fail=0; code "sc-wrong-exit" 1 0 >/dev/null; printf '%s' "$fail");        [ "$_f1" = "1" ] || _sc=1
if [ "$_sc" != "0" ]; then
  echo "FATAL: verify helpers do NOT fail closed" >&2
  exit 2
fi
ok "verify helpers fail closed (reject mismatch, empty suite, and failures)"

echo "== Structure =="
n() { ls $1 2>/dev/null | wc -l | tr -d ' '; }
[ "$(ls $P/agents/*.md 2>/dev/null | wc -l)" -eq 14 ] && ok "14 agents" || no "14 agents"
[ "$(ls -d $P/skills/*/ 2>/dev/null | wc -l)" -eq 19 ] && ok "19 skills" || no "19 skills"
[ "$(ls $P/commands/*.md 2>/dev/null | wc -l)" -eq 7 ] && ok "7 commands" || no "7 commands"
[ "$(ls $P/rules/*.md 2>/dev/null | wc -l)" -eq 10 ] && ok "10 rules" || no "10 rules"
# design/ catalog coverage, both directions: every rules/design/*.md concern file must be
# listed in the rules/design.md index, and every design/<name>.md reference the index makes
# must resolve to a real file (catches a stale entry pointing at a deleted concern file).
n_design_files="$(ls "$P"/rules/design/*.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n_design_files" -eq 0 ]; then
  no "design.md indexes every rules/design/*.md file (no rules/design/*.md files found)"
else
  missing_design=""
  for f in "$P"/rules/design/*.md; do
    b="$(basename "$f")"
    grep -q "$b" "$P/rules/design.md" 2>/dev/null || missing_design="${missing_design} $b"
  done
  [ -z "$missing_design" ] && ok "design.md indexes every rules/design/*.md file" || no "design.md missing:${missing_design}"
fi
stale_design=""
for ref in $(grep -oE 'design/[A-Za-z0-9_-]+\.md' "$P/rules/design.md" 2>/dev/null | sort -u); do
  [ -f "$P/rules/${ref}" ] || stale_design="${stale_design} ${ref}"
done
[ -z "$stale_design" ] && ok "rules/design.md references only files that exist" || no "rules/design.md references missing file(s):${stale_design}"
# design-rules-reminder.sh's pattern list is an operational copy of design.md's paths:
# frontmatter; the two must name the same set of extension/segment tokens in EITHER
# direction, or a frontend edit one side claims to cover silently drifts from the other.
drr_sync="$(python3 - "$P" <<'PY'
import re,sys
P=sys.argv[1]
fm=open(P+"/rules/design.md").read()
paths=re.findall(r'^\s*-\s*"([^"]+)"', fm, re.M)
hook=open(P+"/hooks/design-rules-reminder.sh").read()

fm_tokens=set(); unparsed=[]
for p in paths:
    m=re.match(r'\*\*/\*\.([A-Za-z0-9]+)$', p) or re.match(r'\*\*/([A-Za-z0-9_-]+)/\*\*$', p)
    if m: fm_tokens.add(m.group(1))
    else: unparsed.append(p)

hook_tokens = set(re.findall(r'\*\.([A-Za-z0-9]+)\b', hook)) | \
              set(re.findall(r'\b([A-Za-z][A-Za-z0-9_-]*)/\*(?!\.)', hook))

only_fm = sorted(fm_tokens - hook_tokens)
only_hook = sorted(hook_tokens - fm_tokens)
out=[]
if unparsed: out.append("unparsed design.md pattern(s): " + "; ".join(unparsed))
if only_fm: out.append("in design.md but missing from the hook: " + ", ".join(only_fm))
if only_hook: out.append("in the hook but missing from design.md: " + ", ".join(only_hook))
print("MISSING:"+("; ".join(out) if out else "NONE"))
PY
)"
case "$drr_sync" in *"MISSING:NONE"*) ok "design-rules-reminder.sh's pattern list and rules/design.md's paths: frontmatter name the same tokens";; *) no "design-rules-reminder.sh <-> design.md pattern drift -> ${drr_sync#*MISSING:}";; esac
# Injected-rule-list sync: session-start.sh (conductor) and subagent-rules.sh (worker)
# each hardcode their own copy of the "for r in ..." rule-name list; the two must name
# the same rules, every named rule must resolve to a real file, and docs/rules.md must
# describe every one of them, or an added/renamed rule silently reaches one path and not
# the other (or reaches neither doc).
ss_rule_list="$(sed -nE 's/^[[:space:]]*for r in (.*); do$/\1/p' "$P/hooks/session-start.sh" | head -1)"
sa_rule_list="$(sed -nE 's/^[[:space:]]*for r in (.*); do$/\1/p' "$P/hooks/subagent-rules.sh" | head -1)"
if [ -n "$ss_rule_list" ] && [ "$ss_rule_list" = "$sa_rule_list" ]; then
  ok "session-start.sh and subagent-rules.sh inject the identical rule list"
else
  no "session-start.sh <-> subagent-rules.sh rule-list drift -> session-start: [${ss_rule_list:-<unparsed>}] subagent-rules: [${sa_rule_list:-<unparsed>}]"
fi
missing_rule_files=""
for r in $ss_rule_list; do [ -f "$P/rules/${r}.md" ] || missing_rule_files="${missing_rule_files} ${r}"; done
if [ -n "$ss_rule_list" ] && [ -z "$missing_rule_files" ]; then
  ok "every injected rule name resolves to a rules/<name>.md file"
else
  no "injected rule name(s) with no rules/<name>.md:${missing_rule_files:- (rule list itself unparsed)}"
fi
missing_in_docs=""
for r in $ss_rule_list; do grep -qF "\`${r}.md\`" "$ROOT/docs/rules.md" 2>/dev/null || missing_in_docs="${missing_in_docs} ${r}"; done
if [ -n "$ss_rule_list" ] && [ -z "$missing_in_docs" ]; then
  ok "docs/rules.md mentions every injected rule"
else
  no "docs/rules.md missing mention of injected rule(s):${missing_in_docs:- (rule list itself unparsed)}"
fi
[ "$(ls $P/doctrine/*.md 2>/dev/null | wc -l)" -eq 13 ] && ok "13 doctrine files" || no "13 doctrine files"
[ "$(ls $P/hooks/*.sh 2>/dev/null | wc -l)" -eq 12 ] && ok "12 hook scripts" || no "12 hook scripts"
[ -z "$(find "$P" -type l 2>/dev/null)" ] && ok "plugin tree ships no symlinks (the installer drops them)" || no "plugin tree ships no symlinks (the installer drops them)"
for f in hooks/hooks.json CLAUDE.md README.md workflows/review-mr.js workflows/plan-builder.js \
         workflows/execute-runner.js workflows/ship-runner.js \
         skills/gitlab-mr-review/scripts/post_mr_comments.py \
         skills/grill/SKILL.md skills/plan-flow/SKILL.md skills/execute-flow/SKILL.md \
         skills/ship-flow/SKILL.md \
         scripts/vault-fs.sh scripts/git-ro.sh; do
  [ -f "$P/$f" ] && ok "present: $f" || no "MISSING: $f"
done
# node --check exits 0 on broken workflow scripts, so compile each body in an AsyncFunction, which accepts top-level await and return.
WF_PARSE='const s = require("fs").readFileSync(process.argv[1], "utf8").replace(/^export const meta/m, "const meta"); new (Object.getPrototypeOf(async function () {}).constructor)(s)'
for w in "$P"/workflows/*.js; do
  if ! command -v node >/dev/null 2>&1; then
    skip "skipped: node not found; syntax: workflows/$(basename "$w")"
  elif node -e "$WF_PARSE" "$w" >/dev/null 2>&1; then
    ok "syntax: workflows/$(basename "$w")"
  else
    no "syntax: workflows/$(basename "$w")"
  fi
done
# A skill and a workflow register in the same toolkit: namespace, and the workflow shadows the skill.
wf_skill_clash=""
for w in "$P"/workflows/*.js; do
  wf_name="$(sed -nE "s/^[[:space:]]*name: '([^']+)'.*/\1/p" "$w" | head -1)"
  [ -n "$wf_name" ] && [ -d "$P/skills/$wf_name" ] && wf_skill_clash="${wf_skill_clash} ${wf_name}"
done
[ -z "$wf_skill_clash" ] && ok "no skill shares a workflow name" || no "skill and workflow share a name:${wf_skill_clash}"
gq_skill="$(grep -o 'Do I have permission[^?]*?' "$P/skills/plan-flow/SKILL.md" 2>/dev/null | head -1)"
gq_doctrine="$(grep -o 'Do I have permission[^?]*?' "$P/doctrine/git-safety.md" 2>/dev/null | head -1)"
if [ -n "$gq_skill" ] && [ "$gq_skill" = "$gq_doctrine" ]; then
  ok "plan-flow skill and git-safety carry the identical git-permission question"
else
  no "git-permission question drift -> skill: [${gq_skill:-<missing>}] git-safety: [${gq_doctrine:-<missing>}]"
fi
gq_exec="$(grep -o 'Do I have permission[^?]*?' "$P/skills/execute-flow/SKILL.md" 2>/dev/null | head -1)"
if [ -n "$gq_exec" ] && [ "$gq_exec" = "$gq_doctrine" ]; then
  ok "execute-flow skill and git-safety carry the identical git-permission question"
else
  no "git-permission question drift -> execute-flow skill: [${gq_exec:-<missing>}] git-safety: [${gq_doctrine:-<missing>}]"
fi
gq_ship="$(grep -o 'Do I have permission[^?]*?' "$P/skills/ship-flow/SKILL.md" 2>/dev/null | head -1)"
if [ -n "$gq_ship" ] && [ "$gq_ship" = "$gq_doctrine" ]; then
  ok "ship-flow skill and git-safety carry the identical git-permission question"
else
  no "git-permission question drift -> ship-flow skill: [${gq_ship:-<missing>}] git-safety: [${gq_doctrine:-<missing>}]"
fi
GQ_OPTS='^[123]\. ".*writes `(none|push|release)`\.$'
go_plan="$(grep -E "$GQ_OPTS" "$P/skills/plan-flow/SKILL.md" 2>/dev/null)"
go_exec="$(grep -E "$GQ_OPTS" "$P/skills/execute-flow/SKILL.md" 2>/dev/null)"
if [ "$(printf '%s\n' "$go_plan" | grep -c .)" -eq 3 ] && [ "$go_plan" = "$go_exec" ]; then
  ok "plan-flow and execute-flow carry the identical three git-permission options"
else
  no "git-permission option drift -> plan-flow: [${go_plan:-<missing>}] execute-flow: [${go_exec:-<missing>}]"
fi
go_ship="$(grep -E "$GQ_OPTS" "$P/skills/ship-flow/SKILL.md" 2>/dev/null)"
if [ "$(printf '%s\n' "$go_exec" | grep -c .)" -eq 3 ] && [ "$go_exec" = "$go_ship" ]; then
  ok "execute-flow and ship-flow carry the identical three git-permission options"
else
  no "git-permission option drift -> execute-flow: [${go_exec:-<missing>}] ship-flow: [${go_ship:-<missing>}]"
fi
grep -qF '## Flows' "$P/doctrine/git-safety.md" && ok "git-safety carries the Flows section" || no "git-safety missing the Flows section"
# subagent-rules.sh only fires if hooks.json actually wires it to SubagentStart; a hook
# file can exist and still never run.
want "hooks.json wires subagent-rules.sh to SubagentStart" \
  "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d.get('hooks',{}).get('SubagentStart',[])))" "$P/hooks/hooks.json" 2>/dev/null)" \
  "subagent-rules.sh"
# remember-guard.sh only fires if hooks.json wires it to Stop. A hook file can exist and still never run.
want "hooks.json wires remember-guard.sh to Stop" \
  "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d.get('hooks',{}).get('Stop',[])))" "$P/hooks/hooks.json" 2>/dev/null)" \
  "remember-guard.sh"
# agent-model.sh only fires if hooks.json wires it to a PreToolUse entry matched exactly
# on "Agent". A broader or missing matcher means it never reaches an Agent-tool spawn.
want "hooks.json wires agent-model.sh to PreToolUse matcher Agent" \
  "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); m=[e for e in d.get('hooks',{}).get('PreToolUse',[]) if e.get('matcher')=='Agent']; print(json.dumps(m))" "$P/hooks/hooks.json" 2>/dev/null)" \
  "agent-model.sh"
# toolkit-models.json.template must offer every shipped agent under "agents", or a new
# agent silently has no model-routing entry to fill in.
tm_match="$(python3 -c "
import json,glob,os,sys
P=sys.argv[1]
agents=sorted(os.path.basename(f)[:-3] for f in glob.glob(P+'/agents/*.md'))
tmpl=json.load(open(P+'/scripts/toolkit-models.json.template'))
keys=sorted(tmpl.get('agents',{}).keys())
print('MATCH' if agents==keys else 'MISMATCH agents=%s template=%s' % (agents, keys))
" "$P" 2>/dev/null)"
case "$tm_match" in
  MATCH) ok "toolkit-models.json.template lists every shipped agent" ;;
  *) no "toolkit-models.json.template lists every shipped agent (${tm_match:-python3 failed})" ;;
esac
# coupling-reviewer must be both registered in review-mr.js's REVIEWERS array (or it never
# runs in an MR review) and present as an agent file (or the registration invokes nothing).
grep -qF "toolkit:coupling-reviewer" "$P/workflows/review-mr.js" 2>/dev/null && ok "review-mr.js REVIEWERS registers toolkit:coupling-reviewer" || no "review-mr.js REVIEWERS missing toolkit:coupling-reviewer"
[ -f "$P/agents/coupling-reviewer.md" ] && ok "coupling-reviewer.md agent file exists" || no "coupling-reviewer.md agent file missing"
# functional-test.sh's header comment states the skills mode's call count; it must
# equal the actual skill_probe() call count, or the two silently drift apart.
stated_skills="$(sed -nE 's/.*functional-test\.sh skills.*\(([0-9]+) calls.*/\1/p' "$ROOT/functional-test.sh")"
actual_skills="$(grep -c 'skill_probe "' "$ROOT/functional-test.sh")"
[ "$stated_skills" = "$actual_skills" ] && ok "functional-test.sh skills header count matches actual skill_probe calls" || no "functional-test.sh skills header ($stated_skills) != actual skill_probe calls ($actual_skills)"

echo "== Manifest =="
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate "$ROOT" >/dev/null 2>&1; then ok "plugin validate"; else no "plugin validate"; fi
else
  skip "skipped: claude CLI not found"
fi

echo "== Hook behavior (fixture suite is authoritative) =="
hout="$(cd "$P/hooks/tests" && bash run-all.sh 2>&1)"; hrc=$?
if [ "$hrc" -eq 2 ]; then
  fmsg="$(printf '%s' "$hout" | grep '^FATAL:' | tail -1)"
  no "hook fixture suite (${fmsg:-suite exited 2 with no FATAL message})"
else
  # exit code is part of the pass condition and the RESULT line is picked by prefix,
  # not by trailing position: a merged stderr line must not masquerade as the verdict.
  out="$(printf '%s' "$hout" | grep -E '^RESULT: ' | tail -1)"
  if [ "$hrc" -eq 0 ] && suite_pass "$out" 180; then
    ok "hook fixture suite"
  else
    no "hook fixture suite (exit $hrc, got: ${out:0:60})"
    # The runner names each failed case on a Failed: line. Print them, because a CI log that
    # shows only the totals cannot say which case failed.
    printf '%s\n' "$hout" | grep -E '^(Failed: |  FAIL  )' | sed 's/^/    /'
  fi
fi
# spot-confirm session-start's two injections directly (no fixture asserts the pair)
ss="$(echo '{}' | bash "$P/hooks/session-start.sh" 2>/dev/null)"
want "session-start injects a write-time rule" "$ss" "Verify behavior, not implementation"
want "session-start injects doctrine pointer"  "$ss" "Toolkit doctrine: read the index"
# doctrine override: a file in ~/.claude/doctrine/ makes the hook announce it (isolated temp HOME)
ovh="$(mktemp -d)"; mkdir -p "$ovh/.claude/doctrine"; : > "$ovh/.claude/doctrine/conventions.md"
ovout="$(echo '{}' | HOME="$ovh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$ovh"
want "session-start announces a doctrine override when present" "$ovout" "Doctrine overrides active"
# rule override: assert the override BODY is injected (sentinel), not just the banner.
rvh="$(mktemp -d)"; mkdir -p "$rvh/.claude/rules"; printf -- '---\nx: 1\n---\nRULE_OVERRIDE_SENTINEL_XYZ\n' > "$rvh/.claude/rules/testing.md"
rvout="$(echo '{}' | HOME="$rvh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$rvh"
want "session-start announces a rule override" "$rvout" "Rule overrides active"
want "session-start injects the override rule body (not just the banner)" "$rvout" "RULE_OVERRIDE_SENTINEL_XYZ"
avh="$(mktemp -d)"; mkdir -p "$avh/.claude/agents"; : > "$avh/.claude/agents/code-reviewer.md"
avout="$(echo '{}' | HOME="$avh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$avh"
want "session-start announces an agent override" "$avout" "Agent/skill overrides active"

echo "== Scripts (guardrails) =="
vfh="$(mktemp -d)"; mkdir -p "$vfh/.claude" "$vfh/vault/notes"
printf '{"vault_path":"%s","root_folder":"notes"}\n' "$vfh/vault" > "$vfh/.claude/obsidian-sync.json"
want "vault-fs refuses traversal"  "$(HOME="$vfh" bash "$P/scripts/vault-fs.sh" rm '../x.md' 2>&1)" "refused"
rm -rf "$vfh"
want "git-ro refuses mutation"     "$(bash "$P/scripts/git-ro.sh" "$ROOT" commit 2>&1)" "refused"
bash "$P/scripts/git-ro.sh" "$ROOT" status >/dev/null 2>&1; code "git-ro allows status" "$?" 0
noarg="$(bash "$P/scripts/override.sh" 2>&1)"
want "override lists components (no arg)" "$noarg" "conventions"
want "override no-arg listing marks frontend/design reference-only" "$noarg" "reference-only, not overridable"
want "override refuses unknown name"      "$(bash "$P/scripts/override.sh" nonesuch 2>&1)" "refused"
want "override refuses ambiguous name"    "$(bash "$P/scripts/override.sh" security 2>&1)" "ambiguous"
frh="$(mktemp -d)"; frout="$(HOME="$frh" bash "$P/scripts/override.sh" rules frontend 2>&1)"; frrc=$?
want "override refuses frontend rule (reference-only, no injection to replace)" "$frout" "refused: the 'frontend' rule is reference-only"
code "override refuses frontend rule (exit code)" "$frrc" 1
[ ! -e "$frh/.claude/rules/frontend.md" ] && ok "override refuses frontend rule (no file created)" || no "override refuses frontend rule (no file created)"
rm -rf "$frh"
dsh="$(mktemp -d)"; dsout="$(HOME="$dsh" bash "$P/scripts/override.sh" rules design 2>&1)"; dsrc=$?
want "override refuses design rule (reference-only, no injection to replace)" "$dsout" "refused: the 'design' rule is reference-only"
code "override refuses design rule (exit code)" "$dsrc" 1
[ ! -e "$dsh/.claude/rules/design.md" ] && ok "override refuses design rule (no file created)" || no "override refuses design rule (no file created)"
rm -rf "$dsh"
doh="$(mktemp -d)"; HOME="$doh" bash "$P/scripts/override.sh" conventions >/dev/null 2>&1; HOME="$doh" bash "$P/scripts/override.sh" testing >/dev/null 2>&1
{ [ -f "$doh/.claude/doctrine/conventions.md" ] && [ -f "$doh/.claude/rules/testing.md" ]; } && ok "override copies doctrine + rule into ~/.claude" || no "override copy"; rm -rf "$doh"

echo "== Plan validator =="
out="$(bash "$P/scripts/tests/validate-plan/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "plan-validator fixture suite" "$out" 37

echo "== Topic recall =="
out="$(bash "$P/scripts/tests/topic-recall/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "topic-recall behavior suite" "$out" 45

echo "== vault-fs containment =="
out="$(bash "$P/scripts/tests/vault-fs/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "vault-fs behavior suite" "$out" 19

echo "== git-ro execution boundary =="
out="$(bash "$P/scripts/tests/git-ro/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "git-ro behavior suite" "$out" 12
python3 "$P/scripts/validate-plan.py" "$P/scripts/tests/validate-plan/fixtures/2026-01-01-example-feature/plan - example-feature.md" >/dev/null 2>&1
code "validate-plan accepts a canonical plan" "$?" 0

echo "== plan-builder control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/plan-builder/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "plan-builder control-flow suite" "$out" 25
else
  skip "skipped: node not found; plan-builder control-flow suite"
fi

echo "== execute-runner control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/execute-runner/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "execute-runner control-flow suite" "$out" 153
else
  skip "skipped: node not found; execute-runner control-flow suite"
fi

echo "== ship-runner control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/ship-runner/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "ship-runner control-flow suite" "$out" 140
else
  skip "skipped: node not found; ship-runner control-flow suite"
fi

echo "== review-mr control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/review-mr/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "review-mr control-flow suite" "$out" 46
else
  skip "skipped: node not found; review-mr control-flow suite"
fi

echo "== post_mr_comments GITLAB_TOKEN guard =="
out="$(bash "$P/scripts/tests/post-mr-comments/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "post-mr-comments token-guard suite" "$out" 5

echo "== Design detector (vendored, Apache-2.0) =="
DD="$P/scripts/design-detector"
[ -f "$DD/LICENSE" ] && ok "detector Apache LICENSE present" || no "detector LICENSE missing"
[ -f "$DD/NOTICE" ] && ok "detector NOTICE present" || no "detector NOTICE missing"
[ "$(grep -rl 'Vendored from pbakaus/impeccable' "$DD/vendor" 2>/dev/null | wc -l | tr -d ' ')" -eq 13 ] && ok "13 vendored files carry source headers" || no "vendored source headers (attribution)"
[ -d "$DD/node_modules" ] && no "detector node_modules committed" || ok "no detector node_modules"
if command -v node >/dev/null 2>&1; then
  ddt="/tmp/dd-verify-$$.css"; printf 'h1{font-family:Inter}\n' > "$ddt"
  ddout="$(node "$DD/detect.mjs" "$ddt" 2>/dev/null)"; rm -f "$ddt"
  want "detector runs zero-dep and flags overused-font" "$ddout" "overused-font"
else
  skip "skipped: node not found; detector smoke test"
fi

echo "== Resolver (installed copy) =="
if [ -f ~/.claude/plugins/installed_plugins.json ]; then
  if [ ! -s ~/.claude/plugins/installed_plugins.json ] || \
     [ -z "$(tr -d '[:space:]' < ~/.claude/plugins/installed_plugins.json)" ]; then
    no "installed_plugins.json empty or whitespace-only"
  elif IP="$(jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath // empty' ~/.claude/plugins/installed_plugins.json 2>/dev/null)"; then
    if [ -z "$IP" ]; then
      skip "skipped: toolkit not installed via plugin manager"
    elif [ -d "$IP" ]; then ok "installed_plugins.json resolves to a real dir"; else no "resolver ($IP)"; fi
  else
    no "installed_plugins.json unparseable"
  fi
else
  skip "skipped: no local plugin install (CI checkout)"
fi

echo "== Orchestration invariants (leaf workers, no Haiku) =="
inv="$(python3 - "$P/agents" <<'PY'
import glob,re,os,sys
bad=[]; none=[]; hk=[]
for f in sorted(glob.glob(sys.argv[1]+"/*.md")):
    parts=open(f).read().split('---')
    b=os.path.basename(f)
    if len(parts)<3: none.append(b); continue
    fm=parts[1]; tl=next((l for l in fm.splitlines() if l.strip().startswith('tools:')),None)
    if tl is None: none.append(b)
    toks=re.findall(r'\b(Agent|Task)\b', tl or '')
    if tl and tl.strip()=='tools:':
        toks+=[m for l in fm.splitlines() for m in re.findall(r'-\s*(Agent|Task)\b',l)]
    if toks: bad.append(b)
    ml=next((l for l in fm.splitlines() if l.strip().startswith('model:')),'')
    if 'haiku' in ml.lower(): hk.append(b)
print("BAD",",".join(bad),"NONE",",".join(none),"HAIKU",",".join(hk))
PY
)"
case "$inv" in *"BAD  NONE  HAIKU"*) ok "no agent can spawn sub-agents (leaf), none omits allowlist, none on Haiku";; *) no "orchestration invariant broken: $inv";; esac
if grep -qF 'Tripwires:' "$P/agents/plan-critic.md" && grep -qF 'Walk-away checks:' "$P/agents/plan-critic.md" && grep -qF '60 lines' "$P/agents/plan-critic.md" \
   && grep -qF 'Tripwires block' "$P/skills/plan-workflow/SKILL.md" && grep -qF 'Walk-away checks block' "$P/skills/plan-workflow/SKILL.md"; then
  ok "plan-critic's Tripwires:/Walk-away checks:/60-line return contract is referenced by plan-workflow"
else
  no "plan-critic / plan-workflow Tripwires-Walk-away contract broken"
fi

echo "== Docs coverage (every shipped component is documented) =="
cov="$(python3 - "$P" "$ROOT" <<'PY'
import os,sys,glob,re
P,ROOT=sys.argv[1],sys.argv[2]
def doc(rel):
    p=os.path.join(ROOT,rel)
    return open(p).read().lower() if os.path.exists(p) else ""
missing=[]
def anchored(t,it):
    # Documented = the name appears in a heading, a backtick code-span, or a table
    # cell — not merely as a substring somewhere in prose (which "security" in a
    # sentence would falsely satisfy).
    e=re.escape(it)
    return (re.search(rf'(?m)^#{{1,6}}\s.*{e}', t)
            or re.search(rf'`[^`\n]*{e}[^`\n]*`', t)
            or re.search(rf'(?m)^\|.*{e}.*\|', t))
def check(items,rel,label):
    t=doc(rel)
    for it in items:
        if not anchored(t,it.lower()): missing.append(f"{label} '{it}' not documented (heading/code/table) in {rel}")
check([os.path.basename(d.rstrip('/')) for d in glob.glob(P+"/skills/*/")],"docs/skills.md","skill")
check([os.path.basename(f)[:-3] for f in glob.glob(P+"/agents/*.md")],"docs/agents.md","agent")
check([os.path.basename(f)[:-3] for f in glob.glob(P+"/commands/*.md")],"docs/commands.md","command")
check([os.path.basename(f)[:-3] for f in glob.glob(P+"/hooks/*.sh")],"docs/hooks.md","hook")
check([os.path.basename(f)[:-3] for f in glob.glob(P+"/rules/*.md")],"docs/rules.md","rule")
check([os.path.basename(f) for f in glob.glob(P+"/doctrine/*.md")],"plugins/toolkit/CLAUDE.md","doctrine")
check([os.path.basename(f) for f in glob.glob(P+"/scripts/*") if os.path.isfile(f) and not f.endswith(".pyc")],"docs/scripts.md","script")
check([os.path.basename(f) for f in glob.glob(P+"/workflows/*") if os.path.isfile(f)],"docs/workflows.md","workflow")
print("MISSING:"+("; ".join(missing) if missing else "NONE"))
PY
)"
case "$cov" in *"MISSING:NONE"*) ok "docs reference every shipped skill/agent/command/hook/rule/doctrine/script/workflow";; *) no "undocumented -> ${cov#*MISSING:}";; esac

echo "== REVIEW.md high-risk paths =="
if [ ! -f "$ROOT/REVIEW.md" ]; then
  no "REVIEW.md missing at the repo root"
else
  hr="$(awk '$0 == "## High-risk paths"{f=1;next} /^## /{f=0} f && /^- /{print $2}' "$ROOT/REVIEW.md" | tr -d '\140\042\047' | sed 's/[.,:;]*$//')"
  bad="$(printf '%s\n' "$hr" | while read -r p; do [ -n "$p" ] && [ ! -e "$ROOT/$p" ] && echo "$p"; done)"
  if [ -z "$hr" ]; then no "REVIEW.md High-risk paths section missing or empty"
  elif [ -z "$bad" ]; then ok "every REVIEW.md high-risk path exists"; else no "REVIEW.md high-risk path missing -> $bad"; fi
fi

echo
echo "RESULT: $pass passed, $skip skipped, $fail failed"
# Floor, not just zero-failures: silently deleting real checks must not read green.
# Floor on pass+skip, not pass alone: an environment-dependent skip (no claude CLI,
# no node, no local plugin install) must not read as a vanished check.
[ "$fail" -eq 0 ] && [ "$((pass+skip))" -ge 80 ]
