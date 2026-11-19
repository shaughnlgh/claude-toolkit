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
[ "$(ls -d $P/skills/*/ 2>/dev/null | wc -l)" -eq 20 ] && ok "20 skills" || no "20 skills"
[ "$(ls $P/commands/*.md 2>/dev/null | wc -l)" -eq 8 ] && ok "8 commands" || no "8 commands"
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
[ "$(ls $P/hooks/*.sh 2>/dev/null | wc -l)" -eq 13 ] && ok "13 hook scripts" || no "13 hook scripts"
[ -z "$(find "$P" -type l 2>/dev/null)" ] && ok "plugin tree ships no symlinks (the installer drops them)" || no "plugin tree ships no symlinks (the installer drops them)"
for f in hooks/hooks.json CLAUDE.md README.md workflows/review-mr.js workflows/plan-builder.js \
         workflows/execute-runner.js workflows/ship-runner.js \
         skills/gitlab-mr-review/scripts/post_mr_comments.py \
         skills/grill/SKILL.md skills/plan-flow/SKILL.md skills/execute-flow/SKILL.md \
         skills/ship-flow/SKILL.md \
         scripts/vault-fs.sh scripts/plan-index.py scripts/run-checkpoint.py scripts/git-ro.sh scripts/seat-check.sh scripts/seat-queue.sh scripts/watch-mr.sh \
         scripts/worker-spawn.sh scripts/worker-watch.sh scripts/lib/agents-list.sh hooks/worker-spawn-mode.sh \
         templates/worker-plan.md templates/worker-execute.md templates/worker-ship.md templates/worker-investigate.md; do
  [ -f "$P/$f" ] && ok "present: $f" || no "MISSING: $f"
done
# node --check says nothing about a workflow script either way, because the bodies use top-level await and return, so compile each body in an AsyncFunction, which accepts both.
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
grep -qE '^## Run options$' "$P/skills/plan-guide/SKILL.md" && ok "plan-guide carries the Run options section" || no "plan-guide missing the Run options section"
ro_bad=""
for s in crawl plan-flow execute-flow ship-flow testing-gate; do
  f="$P/skills/$s/SKILL.md"
  grep -qF 'Run options' "$f" || ro_bad="${ro_bad} ${s}:no-reference"
  grep -qF 'Do I have permission' "$f" && ro_bad="${ro_bad} ${s}:asks-permission"
done
[ -z "$ro_bad" ] && ok "crawl, plan-flow, execute-flow, ship-flow and testing-gate reference Run options and none asks the git-permission question" || no "run-options reference drift ->${ro_bad}"
# The question sentences are extracted from plan-guide's Question set, never hardcoded here.
rq_n=0; rq_bad=""
while IFS= read -r q; do
  rq_n=$((rq_n+1))
  for f in $(grep -rlF -- "$q" "$P/skills" | grep -v '/skills/plan-guide/'); do rq_bad="${rq_bad} ${f#"$P"/skills/}:\"${q}\""; done
done < <(sed -n '/^### Question set$/,/^### Cache$/p' "$P/skills/plan-guide/SKILL.md" | grep -oE '"[^"]*\?"' | tr -d '"')
if [ "$rq_n" -gt 0 ] && [ -z "$rq_bad" ]; then
  ok "each of the ${rq_n} run option questions in plan-guide's Question set appears in no other skill"
else
  no "run option question drift (${rq_n} extracted) ->${rq_bad}"
fi
# The ceiling set is extracted from each carrier file, never hardcoded here.
vp_ceil="$(sed -nE 's/^ *"ceiling": \{([^}]*)\},?$/\1/p' "$P/scripts/validate-plan.py" | tr -d '" ' | tr ',' '\n' | sort | tr '\n' ' ')"
sr_ceil="$(sed -nE 's/^const CEILING = \{(.*)\}$/\1/p' "$P/workflows/ship-runner.js" | tr ',' '\n' | sed -E 's/^ *([a-z]+):.*$/\1/' | sort | tr '\n' ' ')"
ss_ceil="$(sed -nE 's/^ *case "\$I_CEIL" in ([a-z|]+)\).*$/\1/p' "$P/hooks/session-start.sh" | tr '|' '\n' | sort | tr '\n' ' ')"
if [ -n "$vp_ceil" ] && [ "$vp_ceil" = "$sr_ceil" ] && [ "$vp_ceil" = "$ss_ceil" ]; then
  ok "validate-plan.py, ship-runner.js and session-start.sh carry the same ceiling set"
else
  no "ceiling set drift -> validate-plan.py: [${vp_ceil:-<missing>}] ship-runner.js: [${sr_ceil:-<missing>}] session-start.sh: [${ss_ceil:-<missing>}]"
fi
# The CI path lists are extracted from CI_CONFIG and ship-flow sections 3 and 6, except .github/, which section 3 must name as .github/workflows.
sf_md="$P/skills/ship-flow/SKILL.md"
ci_sr="$(sed -nE "s/^const CI_CONFIG = \[(.*)\]$/\1/p" "$P/workflows/ship-runner.js" | tr -d "' " | tr ',' '\n' | sort | tr '\n' ' ')"
ci_s6="$(sed -nE 's/.*the protected paths: CI configuration \(([^)]*)\).*/\1/p' "$sf_md" | tr -d '` ' | tr ',' '\n' | sort | tr '\n' ' ')"
sf_s3="$(sed -n '/^## 3\. /,/^## 3b\. /p' "$sf_md")"
ci_s3="$(printf '%s\n' "$sf_s3" | grep -oE 'The CI paths are ([^`.]*`[^`]+`)+' | grep -oE '`[^`]+`' | tr -d '`' | tr '\n' ' ')"
ci_miss=""
for c in $ci_sr; do
  [ "$c" = ".github/" ] && continue
  [[ " $ci_s3" == *" ${c%/} "* ]] || ci_miss="${ci_miss} ${c%/}"
done
if [ -n "$ci_sr" ] && [ "$ci_sr" = "$ci_s6" ] && [ -n "$ci_s3" ] && [ -z "$ci_miss" ] && [[ "$sf_s3" == *'.github/workflows'* ]]; then
  ok "ship-flow section 6 lists CI_CONFIG, and section 3 names .github/workflows and every other CI_CONFIG path"
else
  no "CI path drift -> ship-runner.js CI_CONFIG: [${ci_sr:-<missing>}] ship-flow section 6: [${ci_s6:-<missing>}] ship-flow section 3: [${ci_s3:-<missing>}]"
fi
nm_sr="$(sed -nE 's/^const NONE_MINUTES = ([0-9]+)$/\1/p' "$P/workflows/ship-runner.js")"
nm_7b="$(sed -n '/^## 7b\. /,/^## 8\. /p' "$sf_md" | grep -oE -- '--none [0-9]+' | cut -d' ' -f2 | sort -u | tr '\n' ' ')"
if [ -n "$nm_sr" ] && [ "$nm_7b" = "$nm_sr " ]; then ok "ship-flow section 7b passes --none as ship-runner's NONE_MINUTES"; else no "no-check window drift -> ship-runner.js NONE_MINUTES: [${nm_sr:-<missing>}] ship-flow section 7b --none: [${nm_7b:-<missing>}]"; fi
cp_txt="$(awk '/^const CAPTURE_PROMPT = /{f=1; print; next} f && /^const /{exit} f' "$P/workflows/execute-runner.js")"
if [[ "$cp_txt" == *'slice-capture.py'* ]] && grep -qF 'REPO_FLAGS' "$P/skills/execute-flow/SKILL.md" && grep -qF 'REPO_FLAGS' "$sf_md"; then ok "execute-runner's CAPTURE_PROMPT runs slice-capture.py, and execute-flow and ship-flow name REPO_FLAGS in their capture brief"; else no "CAPTURE_PROMPT no longer runs slice-capture.py, or execute-flow or ship-flow no longer names REPO_FLAGS"; fi
ef_s11="$(sed -n '/^## 11\. Seat run/,/^## /p' "$P/skills/execute-flow/SKILL.md")"
s11_miss=""
for t in 'fixBudget' 'Fix rounds used:'; do [[ "$ef_s11" == *"$t"* ]] || s11_miss="${s11_miss} '${t}'"; done
[ -n "$ef_s11" ] && [ -z "$s11_miss" ] && ok "execute-flow section 11 passes fixBudget and records Fix rounds used:" || no "execute-flow section 11 missing:${s11_miss:- the section}"
# The Own PR Merge and Own MR Merge entries in setup.md quote mergeCmd in ship-runner.js, so their flags must match.
mc_flags() { grep -oE -- '--[a-z-]+(=[a-z]+)?' | tr '\n' ' '; }
mc="$(sed -n '/^const mergeCmd = /,/)$/p' "$P/workflows/ship-runner.js")"
sr_gh="$(printf '%s\n' "$mc" | grep -F '`gh pr merge ' | mc_flags)"
sr_gl="$(printf '%s\n' "$mc" | grep -F '`glab mr merge ' | mc_flags)"
su_gh="$(sed -nE 's/.*Own PR Merge: .* with (gh pr merge [^.]*) is allowed when .*/\1/p' "$P/commands/setup.md" | mc_flags)"
su_gl="$(sed -nE 's/.*Own MR Merge: .* with (glab mr merge [^.]*) is allowed when .*/\1/p' "$P/commands/setup.md" | mc_flags)"
if [ -n "$sr_gh" ] && [ "$sr_gh" = "$su_gh" ] && [ -n "$sr_gl" ] && [ "$sr_gl" = "$su_gl" ]; then
  ok "setup.md's Own PR Merge and Own MR Merge entries carry the flags of ship-runner.js mergeCmd"
else
  no "merge entry drift -> ship-runner.js gh: [${sr_gh:-<missing>}] setup.md Own PR Merge: [${su_gh:-<missing>}] ship-runner.js glab: [${sr_gl:-<missing>}] setup.md Own MR Merge: [${su_gl:-<missing>}]"
fi
# Two allowances beside setup's blocks: the plugin manifest fallback reads the toolkit root, and a line whose only plugin read is the every-plugin list finds another plugin's file.
ipj="$(cd "$P" && grep -rn 'installed_plugins.json' skills agents commands 2>/dev/null | grep -v '^commands/setup\.md:' | grep -vE '^(skills|agents)/[^:]+:[0-9]+:.*\.claude-plugin/plugin\.json' | awk 'index($0, ".plugins[][0].installPath") && !index($0, ".plugins[\"") {next} {print}' | cut -d: -f1 | sort -u | tr '\n' ' ')"
[ -z "$ipj" ] && ok "only setup's CLAUDE.md blocks and the plugin manifest fallback in skills and agents read the toolkit root from installed_plugins.json, and any other line that names it lists every plugin's root" || no "toolkit root read from installed_plugins.json outside setup's blocks and the plugin manifest fallback, or a keyed read beside the every-plugin list, in: $ipj"
# The installed-root expression is extracted from setup.md's CLAUDE.md block, never hardcoded here.
ir_jq="$(grep -m1 -oE "jq -r '[^']+' ~/.claude/plugins/installed_plugins.json" "$P/commands/setup.md")"
pr_n=0; pr_bad=""
for f in "$P"/skills/*/SKILL.md; do
  while IFS= read -r l; do
    pr_n=$((pr_n+1))
    if [[ "$l" != *'This root takes precedence over a CLAUDE.md line that resolves the installed root.'* ]] || [[ "$l" != *'`../../.claude-plugin/plugin.json` does not exist'* ]] || [ -z "$ir_jq" ] || [[ "$l" != *"$ir_jq"* ]]; then pr_bad="${pr_bad} $(basename "$(dirname "$f")")"; fi
  done < <(grep -E '(plugin root|`<plugin-root>`) is `\.\./\.\.` from this skill' "$f")
done
if [ "$pr_n" -gt 0 ] && [ -z "$pr_bad" ]; then ok "each of the ${pr_n} skill plugin-root sentences states its precedence and falls back to the installed root when ../.. holds no plugin manifest"; else no "skill plugin-root sentence without the precedence sentence or the plugin manifest fallback (${pr_n} found) ->${pr_bad}"; fi
# A /toolkit:override copy reaches plugin files only through <plugin-root>, so ../ survives only in the plugin-root sentence.
bare_rel="$(cd "$P" && grep -nE '(^|[^.])\.\./' skills/*/SKILL.md | sed -e 's/`\.\.\/\.\.` from this skill//g' -e 's/`\.\.\/\.\.\/\.claude-plugin\/plugin\.json` does not exist//g' | grep -E '(^|[^.])\.\./' | cut -d: -f1,2 | tr '\n' ' ')"
[ -z "$bare_rel" ] && ok "no skill line outside its plugin-root sentence reaches a plugin file by a bare ../.. or ../<name>/ path" || no "skill line reaches a plugin file by a bare ../.. or ../<name>/ path instead of <plugin-root>: $bare_rel"
fd_blk="$(sed -n '/^```bash$/,/^```$/p' "$P/agents/frontend-designer.md")"
if [ -n "$ir_jq" ] && [[ "$fd_blk" == *'[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ] || PLUGIN_ROOT="$('"$ir_jq"')"'* ]]; then ok "frontend-designer's detector block falls back to the installed root when its plugin root holds no plugin manifest"; else no "frontend-designer detector block lacks the plugin manifest fallback"; fi
grep -qF '## Flows' "$P/doctrine/git-safety.md" && ok "git-safety carries the Flows section" || no "git-safety missing the Flows section"
if grep -qF 'Worktree install:' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Worktree install:' "$ROOT/docs/context/context-worktree-seat.md" && grep -qF "runs the repo's install step there as execute-flow section 2a defines" "$P/doctrine/orchestration.md"; then
  ok "execute-flow, the worktree seat context, and orchestration carry the worktree install step"
else
  no "worktree install step missing from execute-flow, context-worktree-seat.md, or orchestration.md"
fi
if grep -qF 'Seat run passed:' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Seat run passed:' "$P/skills/ship-flow/SKILL.md"; then ok "execute-flow writes and ship-flow reads the seat run outcome line"; else no "seat run outcome line missing from execute-flow or ship-flow"; fi
if grep -qF '[e2e]' "$P/skills/plan-guide/SKILL.md" && grep -qF 'E2E_MARK' "$P/scripts/plan-index.py" && grep -qF 'E2E_MARK.test' "$P/workflows/execute-runner.js"; then ok "plan-guide defines the [e2e] marker, and plan-index.py and execute-runner.js read it"; else no "[e2e] marker missing from plan-guide, plan-index.py or execute-runner.js"; fi
if grep -qF 'vault-fs.sh index' "$P/workflows/execute-runner.js" && grep -qF 'vault-fs.sh sha256' "$P/workflows/execute-runner.js" && grep -qE '^  index\)' "$P/scripts/vault-fs.sh" && grep -qE '^  sha256\)' "$P/scripts/vault-fs.sh" && grep -qF '`planPath`:' "$P/skills/execute-flow/SKILL.md"; then ok "execute-runner indexes the plan note through vault-fs.sh index and sha256, and execute-flow passes planPath"; else no "plan index by path missing from execute-runner.js, vault-fs.sh or execute-flow"; fi
if grep -qE '^  cp\)' "$P/scripts/vault-fs.sh" && grep -qE '^  attach\)' "$P/scripts/vault-fs.sh" && grep -qF 'vault-fs.sh attach' "$P/skills/execute-flow/SKILL.md" && grep -qF 'SCREENSHOT_RULE' "$P/workflows/execute-runner.js" && grep -qF 'SCREENSHOT_RULE' "$P/skills/execute-flow/SKILL.md" && grep -qF 'const MAX_SHOTS = 5' "$P/workflows/execute-runner.js" && grep -qF "the runner's \`MAX_SHOTS\`" "$P/skills/execute-flow/SKILL.md"; then ok "vault-fs.sh carries cp and attach, and execute-flow attaches screenshots under SCREENSHOT_RULE and the MAX_SHOTS cap"; else no "cp, attach, SCREENSHOT_RULE or the MAX_SHOTS cap missing from vault-fs.sh, execute-flow or execute-runner.js"; fi
if (for f in skills/plan-guide/SKILL.md skills/execute-flow/SKILL.md skills/ship-flow/SKILL.md skills/plan-flow/SKILL.md skills/handoff/SKILL.md; do grep -qF 'vault-fs.sh cp' "$P/$f" || exit 1; done) && ! grep -rqF 'Write the note to a `.tmp.md` file beside it' "$P" && ! grep -rqF 'same atomic write' "$P"; then ok "every skill that changes an existing plan note names the vault-fs.sh cp changed-lines path"; else no "a plan note writer still restates the whole-file write or lacks vault-fs.sh cp"; fi
if (for f in skills/plan-guide/SKILL.md workflows/plan-builder.js agents/plan-critic.md; do for t in 'scratch vault' 'Projects/<repo>-scratch/'; do grep -qF -- "$t" "$P/$f" || exit 1; done; done); then ok "plan-guide, plan-builder and plan-critic keep fixture plan notes in a scratch vault and live-session notes under Projects/<repo>-scratch/"; else no "fixture or live-session note rule missing from plan-guide, plan-builder or plan-critic"; fi
if grep -qF 'SHOTS_MARK' "$P/scripts/plan-index.py" && grep -qF -- '--output tests/' "$P/skills/plan-guide/SKILL.md" && (for f in skills/plan-guide/SKILL.md workflows/plan-builder.js agents/plan-critic.md; do for t in '[shots]' 'captures on pass' 'anonymised'; do grep -qF -- "$t" "$P/$f" || exit 1; done; done); then ok "plan-guide, plan-builder and plan-critic bind a [shots] step to its own output directory, capture on pass and anonymised data, and plan-index.py reads the marker"; else no "[shots] marker, capture-on-pass or screenshot data rule missing from plan-guide, plan-builder, plan-critic or plan-index.py"; fi
if grep -qxF 'const REPLAY = null' "$P/workflows/execute-runner.js" && grep -qF 'REPLAY_LINE = "const REPLAY = null"' "$P/scripts/run-checkpoint.py" && grep -qF 'a.replay' "$P/workflows/review-mr.js" && grep -qF 'run-checkpoint.py' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Launch: execute run' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Run: <runId>' "$P/skills/execute-flow/SKILL.md"; then ok "execute-runner.js holds the REPLAY line that run-checkpoint.py replaces, review-mr takes replay, and execute-flow records the Launch and Run lines and reads the checkpoint"; else no "REPLAY line, review-mr replay arg, or execute-flow launch record or checkpoint read missing"; fi
if python3 - "$P/workflows/execute-runner.js" "$P/scripts/run-checkpoint.py" <<'PY'
import re, sys
src, cp = (open(p, encoding="utf-8").read() for p in sys.argv[1:])
writer = re.compile(re.search(r'^WRITER = re\.compile\(r"(.+)"\)$', cp, re.M).group(1))
named = re.search(r"const label = `([^`]+)`", src).group(1)
labels = [m.group(1) or m.group(2) or named for m in re.finditer(r"\{ (?:label: (?:'([^']+)'|`([^`]+)`)|label), [^\n]*agentType: 'toolkit:implementer'", src)]
labels = [re.sub(r"\$\{[^}]+\}", "1", l) for l in labels if l != "remember:pass"]
sys.exit(0 if len(labels) >= 4 and all(writer.match(l) for l in labels) else 1)
PY
then ok "run-checkpoint.py's WRITER matches every execute-runner implementer label that edits the tree"; else no "an execute-runner implementer label other than remember:pass is missing from run-checkpoint.py's WRITER"; fi
if grep -qF "capture('diff:blocked'" "$P/workflows/execute-runner.js" && grep -qF 's["label"] == "diff:blocked"' "$P/scripts/run-checkpoint.py" && grep -qF "lastLabel = 'review'" "$P/workflows/execute-runner.js" && grep -qF 'label == "review"' "$P/scripts/run-checkpoint.py"; then ok "run-checkpoint.py reads the diff:blocked and review labels execute-runner.js writes"; else no "the diff:blocked or review resume label differs between execute-runner.js and run-checkpoint.py"; fi
if grep -qF 'a.nits' "$P/workflows/execute-runner.js" && grep -qF 'a.nits' "$P/workflows/ship-runner.js" && grep -qF '`nits`: the section 2 `nits` value' "$P/skills/execute-flow/SKILL.md" && grep -qF '`nits`: the note' "$P/skills/ship-flow/SKILL.md"; then ok "both runners take and both flows pass the nits run option"; else no "nits run option missing from a runner or a flow's args"; fi
if grep -qF 'a.noCiConfig' "$P/workflows/ship-runner.js" && grep -qF '`noCiConfig`: the section 3' "$P/skills/ship-flow/SKILL.md"; then ok "ship-runner takes and ship-flow passes noCiConfig"; else no "noCiConfig missing from ship-runner.js or the ship-flow args"; fi
if grep -qF 'toolkit-review-bots.json' "$P/commands/setup.md" && grep -qF 'toolkit-review-bots.json' "$P/skills/ship-flow/SKILL.md"; then ok "setup writes and ship-flow reads the review bot logins file"; else no "review bot logins file missing from setup or ship-flow"; fi
if grep -qE '^### Ticket$' "$P/skills/plan-guide/SKILL.md" && grep -qF 'On the plan-guide route the set also carries the ticket question' "$P/skills/crawl/SKILL.md" && sed -n '/^## 4\./,/^## Boundary$/p' "$P/skills/crawl/SKILL.md" | grep -qF '`ticket`' && grep -qF 'ticket_work:' "$P/skills/plan-guide/SKILL.md" && grep -qF 'ticket_work:' "$P/skills/testing-gate/SKILL.md" && grep -qF 'ticket_work:' "$P/doctrine/git-safety.md" && grep -qF 'after the type prefix' "$P/skills/plan-flow/SKILL.md" && sed -n '/^## 4\. /,/^## 5\. /p' "$P/skills/plan-flow/SKILL.md" | grep -qF 'ask the ticket question in its own AskUserQuestion call' && sed -n '/^## 4\. /,/^## 5\. /p' "$P/skills/plan-flow/SKILL.md" | grep -qF 'run the create procedure in that subsection before deriving `planName`'; then ok "plan-guide defines the ticket question and its work-scoped cache lines, crawl asks it and writes it to the scaffold, testing-gate and git-safety honor the cache lines, and plan-flow asks it in section 4 and puts the ticket in the branch"; else no "ticket question, crawl ask or scaffold ticket write, ticket_work line, plan-flow section 4 ask or branch ticket insertion missing"; fi
if grep -qF 'flows never ask the ticket question' "$P/doctrine/git-safety.md" && grep -qF 'flows never ask the ticket question' "$P/skills/plan-guide/SKILL.md" && grep -qF 'never asks the ticket question' "$P/skills/incident-investigate/SKILL.md" && grep -qF 'When the brief names no ticket, ask the ticket question' "$P/skills/expedition/SKILL.md" && grep -qF 'parent names no branch' "$P/skills/plan-guide/SKILL.md" && grep -qF 'parent names no branch' "$P/skills/crawl/SKILL.md" && grep -qF 'parent names no branch' "$P/skills/wayfinder/SKILL.md"; then ok "the execute and ship flows, incident-investigate and wayfinder parents never ask the ticket question, and expedition asks it at ingestion"; else no "ticket question scope missing from git-safety, plan-guide, crawl, wayfinder, incident-investigate or expedition"; fi
if grep -qiF 'wherever HEAD is' "$P/doctrine/git-safety.md" && grep -qF 'after the ticket question' "$P/CLAUDE.md"; then ok "git-safety settles the ticket before it suggests any branch for work with no recorded ticket, wherever HEAD is, and the doctrine index says so"; else no "ticket rule for every branch suggestion missing from git-safety.md or the doctrine index"; fi
if grep -qF 'toolkit-trackers.json' "$P/skills/plan-guide/SKILL.md" && grep -qF 'toolkit-trackers.json' "$ROOT/docs/prerequisites.md" && grep -qF 'JIRA_CONFIG_FILE' "$P/skills/plan-guide/SKILL.md"; then ok "plan-guide reads the tracker override file and the jira-cli config signal, and the prerequisites doc names the override file"; else no "tracker override file or jira-cli config signal missing from plan-guide or docs/prerequisites.md"; fi
if grep -qF 'toolkit-trackers.json' "$P/commands/setup.md" && grep -qF '| Ticket tracker |' "$P/commands/setup.md" && grep -qF 'toolkit-trackers.json' "$ROOT/docs/commands.md"; then ok "setup reports the tracker override file with a Ticket tracker readiness row, and docs/commands.md lists the check"; else no "tracker override file check or Ticket tracker readiness row missing from setup.md or docs/commands.md"; fi
tq_adr="$(find "$ROOT/docs/decisions" -name '*-ticket-question-and-creation-on-yes.md' | head -1)"
if [ -n "$tq_adr" ] && grep -qF 'jira issue create' "$P/skills/jira/SKILL.md" && grep -qF 'create confirmation' "$P/skills/plan-guide/SKILL.md" && grep -qF 'create confirmation' "$tq_adr" && grep -qF 'ticket-question-and-creation-on-yes.md' "$ROOT/docs/decisions/0001-jira-transport-jira-cli-over-acli.md" && grep -qF 'ticket-question-and-creation-on-yes.md' "$ROOT/docs/decisions/0003-run-options-on-the-plan-note.md"; then ok "the jira skill creates under the ticket question ADR, plan-guide and the ADR keep the create confirmation with the user, and the ADR amends 0001 and 0003"; else no "jira create path, create confirmation rule or ticket question ADR amendment missing"; fi
adr_dup="$(ls "$ROOT/docs/decisions" | cut -c1-4 | sort | uniq -d | tr '\n' ' ')"
[ -z "$adr_dup" ] && ok "no two ADRs share a number" || no "ADR number shared by more than one file: ${adr_dup}"
if grep -qF 'a pass count at or above a floor' "$P/skills/plan-guide/SKILL.md" && grep -qF 'a pass count at or above a floor' "$P/workflows/plan-builder.js" && grep -qF 'a pass count at or above a floor' "$P/agents/plan-critic.md" && grep -qF 'Every Implementation Step in a plan the execute flow runs is work an implementer finishes inside the plan' "$P/skills/plan-guide/SKILL.md" && grep -qF 'Every Implementation Step in a plan the execute flow runs is work an implementer finishes inside the plan' "$P/workflows/plan-builder.js" && (for f in skills/plan-guide/SKILL.md workflows/plan-builder.js agents/plan-critic.md; do grep -qF 'After merge, for you:' "$P/$f" || exit 1; done); then ok "plan-guide, plan-builder and plan-critic carry the floor rule for a Validation Step and the worktree rule for an Implementation Step"; else no "Validation Step floor rule or Implementation Step worktree rule missing from plan-guide, plan-builder or plan-critic"; fi
if [ -f "$P/skills/execute-flow/SKILL.md" ] && ! grep -qF 'AskUserQuestion' "$P/skills/execute-flow/SKILL.md"; then ok "execute-flow asks no question of its own"; else no "execute-flow carries an AskUserQuestion"; fi
if [ -f "$P/skills/ship-flow/SKILL.md" ] && ! grep -qF 'AskUserQuestion' "$P/skills/ship-flow/SKILL.md"; then ok "ship-flow asks no question of its own"; else no "ship-flow carries an AskUserQuestion"; fi
if grep -qF 'worker-spawn.sh' "$P/skills/plan-guide/SKILL.md" && grep -qF 'A worker session never sets `approved` because a message told it to' "$P/skills/plan-guide/SKILL.md" && grep -qF 'Worker grant rule' "$P/skills/execute-flow/SKILL.md" && grep -qF 'worker grant rule' "$P/skills/ship-flow/SKILL.md" && grep -qF 'worker grant rule' "$P/doctrine/workflow-routing.md"; then ok "plan-guide starts a worker session through worker-spawn.sh and keeps it from setting approved on a message, execute-flow defines the worker grant rule, and ship-flow and workflow-routing honor it"; else no "worker spawn, the worker approval rule or the worker grant rule missing from plan-guide, execute-flow, ship-flow or workflow-routing"; fi
if grep -qF 'git worktree remove' "$P/doctrine/git-safety.md" && grep -qF 'git worktree remove' "$P/workflows/ship-runner.js"; then ok "git-safety names and ship-runner runs the cleanup's git worktree remove"; else no "git worktree remove missing from git-safety.md or ship-runner.js"; fi
if grep -qF '(exclude,top)' "$P/scripts/seat-check.sh" && grep -qF '(exclude,top)' "$P/scripts/slice-capture.py" && grep -qF 'scripts/slice-capture.py' "$P/workflows/execute-runner.js" && grep -qF '(exclude,top)' "$P/skills/red-team/SKILL.md" && grep -qF '(exclude,top)' "$P/skills/execute-flow/SKILL.md"; then ok "seat-check, slice-capture, which execute-runner runs, red-team and execute-flow leave Claude Code worktrees out of their path lists"; else no "own-worktree pathspec missing from seat-check.sh, slice-capture.py, red-team or execute-flow, or execute-runner.js no longer runs slice-capture.py"; fi
grep -qF 'worktree name `<name>` is `<planName>`' "$P/skills/execute-flow/SKILL.md" && ok "execute-flow names the worktree after the plan name" || no "execute-flow no longer names the worktree after the plan name"
pa_sec="$(sed -n '/^### After approval$/,/^### Record the session on the plan$/p' "$P/skills/plan-guide/SKILL.md")"
if [[ "$pa_sec" == *'run the execute flow here'* ]] && [[ "$pa_sec" == *'never asks this question through AskUserQuestion'* ]] && grep -qF '§ After approval' "$P/skills/plan-flow/SKILL.md"; then ok "plan-guide defines the post-approval question in plain text and plan-flow asks it"; else no "post-approval question missing from plan-guide or plan-flow, or asked through AskUserQuestion"; fi
if grep -qF 'such as `yes` or `run the execute flow here`' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Type `run the execute flow here` to ask again' "$P/skills/execute-flow/SKILL.md" && grep -qF 'run the execute flow here' "$P/doctrine/workflow-routing.md"; then ok "execute-flow and workflow-routing take the typed post-approval reply as the ask by name, and a denial report quotes the retype"; else no "post-approval reply or its retype line missing from execute-flow or workflow-routing"; fi
if grep -qF 'worker-execute-<key>' "$P/skills/plan-guide/SKILL.md" && grep -qF 'worker-<type>-<key>' "$P/doctrine/orchestration.md" && [[ "$pa_sec" == *'cannot read its own name'* ]] && [[ "$pa_sec" == *'without the bracketed short id'* ]] && ! grep -qF "claude -n 'child-" "$P/skills/plan-guide/SKILL.md" && ! grep -qF "claude -n 'child-" "$P/doctrine/orchestration.md"; then ok "plan-guide names the worker-execute-<key> worker session, orchestration defines worker-<type>-<key>, and neither hands a child launch command"; else no "worker session name missing from plan-guide or orchestration, or a child launch command remains"; fi
rs_sec="$(sed -n '/^### Record the session on the plan$/,/^## Session Closure$/p' "$P/skills/plan-guide/SKILL.md")"
if [[ "$rs_sec" == *'ListAgents'* ]] && [[ "$rs_sec" == *'`name`'* ]] && [[ "$rs_sec" == *'double-quoted'* ]] && [[ "$rs_sec" == *'a double quote, a backslash, or a control character'* ]] && [[ "$rs_sec" == *'write no new `name`'* ]] && [[ "$rs_sec" == *'without the bracketed short id'* ]] && [[ "$rs_sec" == *'starts `worker-` marks a worker session'* ]] && [[ "$rs_sec" == *'lead-<key>'* ]]; then ok "plan-guide records each session's name from ListAgents as a double-quoted scalar, where a worker- name marks a worker session and any other name a lead"; else no "session name rule, its double-quoted form or its worker and lead marking missing from plan-guide Record the session"; fi
c4="$(sed -n '/^## 4\. Hand off with the evidence$/,/^## Boundary$/p' "$P/skills/crawl/SKILL.md")"
pf1="$(sed -n '/^## 1\. Trigger$/,/^## 2\. Run options$/p' "$P/skills/plan-flow/SKILL.md")"
pf3a="$(sed -n '/^## 3a\. Route$/,/^## 4\. Launch$/p' "$P/skills/plan-flow/SKILL.md")"
pf4="$(sed -n '/^## 4\. Launch$/,/^## 5\. Write the plan note$/p' "$P/skills/plan-flow/SKILL.md")"
if [[ "$c4" == *'run the plan flow'* ]] && [[ "$c4" == *'Never ask it through AskUserQuestion'* ]] && [[ "$c4" == *'/rename lead-<key>'* ]] && [[ "$c4" == *'prints a name that does not start `lead-`'* ]] && [[ "$c4" == *'Start worker-plan-<key> to plan it?'* ]] && [[ "$c4" != *'/rename parent-'* ]] && [[ "$pf1" == *'plan flow offer'* ]] && [[ "$pf1" == *'brief - <plan>.md'* ]] && [[ "$pf3a" == *'plan flow offer'* ]] && [[ "$pf4" == *'plan flow offer'* ]] && [[ "$pf4" == *'on any by-name run'* ]] && [[ "$c4" == *'without the bracketed short id'* ]] && grep -qF 'run the plan flow' "$P/doctrine/workflow-routing.md"; then ok "crawl offers the plan flow in plain text with the optional lead rename line and the plan worker form, plan-flow and workflow-routing take the typed reply as the ask, and plan-flow passes the crawl sections as knownEvidence"; else no "crawl plan flow offer, its plain-text rule, its lead rename line, its plan worker form, or its carve-out or knownEvidence hand-off in plan-flow or workflow-routing missing, or a parent rename line remains"; fi
if grep -qF 'send <own name> the message' "$P/skills/execute-flow/SKILL.md" && grep -qF '`<own name>` is this session' "$P/skills/execute-flow/SKILL.md" && grep -qF 'the name the first prompt gives this worker' "$P/skills/execute-flow/SKILL.md" && grep -qF 'without the bracketed short id after the name' "$P/skills/execute-flow/SKILL.md" && grep -qF 'send <own name> the message' "$P/skills/ship-flow/SKILL.md" && grep -qF '`<own name>` is the name execute-flow section 10 defines' "$P/skills/ship-flow/SKILL.md"; then ok "execute-flow and ship-flow reports name the worker session's own name as the continue recipient"; else no "dispatch recipient in the execute-flow or ship-flow Next line is not the reporting session's own name"; fi
if [[ "$pa_sec" == *'Start worker-execute-<key> to build it?'* ]] && [[ "$pa_sec" == *'`start the worker` or `yes`'* ]] && [[ "$pa_sec" == *'The ceiling you picked is your permission'* ]] && [[ "$pa_sec" != *'~200k token nudge'* ]] && grep -qF 'types yes to the run-here form' "$P/skills/execute-flow/SKILL.md" && grep -qF 'bare `yes` in the run-here form' "$P/doctrine/workflow-routing.md" && grep -qF 'in the worker form `yes` starts a worker session' "$P/skills/execute-flow/SKILL.md"; then ok "the worker form puts yes on the recommended worker line and states the ceiling as the user's permission, and execute-flow and workflow-routing take a bare yes as the ask only in the run-here form"; else no "worker form of the post-approval question, its ceiling permission line, or the run-here qualifier on a bare yes missing from plan-guide, execute-flow or workflow-routing, or the token nudge remains"; fi
if grep -qF 'SendMessage' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Deferred to the seat: ' "$P/skills/execute-flow/SKILL.md" && grep -qF 'Left the worktree with keep' "$P/skills/execute-flow/SKILL.md" && grep -qF 'execute-flow section 10' "$P/doctrine/orchestration.md"; then ok "execute-flow reports to a named lead session in the shape orchestration names, then leaves its worktree with keep"; else no "lead report or its ExitWorktree keep step missing from execute-flow or orchestration"; fi
p10="$(grep -F '`<next step>` is' "$P/skills/execute-flow/SKILL.md")"
if [[ "$p10" == *'begins `stop <own name>` and `pwd -P` sits under'* ]] && [[ "$p10" == *'stay in the worktree'* ]]; then ok "a worker session leaves its worktree after a lead report only when the report tells the lead to stop it"; else no "execute-flow section 10 leaves the worktree after a continue or rerun report"; fi
sr_step1="$(sed -n '/^## 11\. Seat run$/,$p' "$P/skills/execute-flow/SKILL.md" | grep -F '1. Seat check and location')"
if [[ "$sr_step1" == *'seat-queue.sh join'* ]] && [[ "$sr_step1" == *'call ExitWorktree with `action` set to `keep`'* ]] && [[ "$sr_step1" == *'before any ExitWorktree call'* ]]; then ok "the seat run joins the seat queue and leaves the worktree with ExitWorktree keep only on its turn"; else no "seat run step 1 does not join the seat queue or leave the worktree with ExitWorktree keep on its turn"; fi
sr_rel="$(sed -n '/^## 11\. Seat run$/,$p' "$P/skills/execute-flow/SKILL.md" | grep -F -- '- The release.')"
if [[ "$sr_rel" == *'call EnterWorktree with `path` set to that path'* ]] && [[ "$sr_rel" == *'delete `<return file>` and run the queue leave'* ]]; then ok "the seat run release returns to the worktree it left through EnterWorktree path, then leaves the queue"; else no "the seat run release lacks the EnterWorktree path return or the queue leave"; fi
if grep -qF 'Unrecorded worktree rule' "$P/skills/execute-flow/SKILL.md" && grep -qF 'unrecorded worktree rule' "$ROOT/docs/context/context-worktree-seat.md"; then ok "execute-flow adopts an unrecorded worktree by the ownership rule"; else no "unrecorded worktree rule missing from execute-flow or context-worktree-seat.md"; fi
own_rule="$(grep -F 'Ownership rule:' "$P/skills/execute-flow/SKILL.md")"
if [ -n "$own_rule" ] && [[ "$own_rule" != *'rev-list'* ]]; then ok "execute-flow owns a worktree by plan name and branch, with no commit count"; else no "execute-flow ownership rule missing or still counts commits"; fi
occ_rule="$(grep -F 'Occupant check: before an EnterWorktree `path` call on an existing worktree' "$P/skills/execute-flow/SKILL.md")"
if [[ "$occ_rule" == *"--worktree '<path>'"* ]] && [[ "$occ_rule" == *'stop with the plan note untouched'* ]] && grep -qF 'run the occupant check below on `<path>`, then call EnterWorktree' "$P/skills/execute-flow/SKILL.md" && grep -qF 'run the section 1 occupant check on that directory, then call EnterWorktree' "$P/skills/execute-flow/SKILL.md"; then ok "execute-flow stops before re-entering a worktree another live session occupies"; else no "execute-flow occupant stop missing before a section 1 or section 2a worktree entry"; fi
if [[ "$occ_rule" == *'A held seat, exit 10, does not stop this check'* ]] && [[ "$occ_rule" == *'unrecorded worktree rule adopts'* ]]; then ok "the occupant check carves out a held seat and runs before an adoption"; else no "occupant check lost the held-seat carve-out or the adoption case"; fi
if [[ "$pa_sec" == *'When this session runs in a linked worktree, it does not hold the seat'* ]] && [[ "$pa_sec" == *'seat queue'* ]]; then ok "plan-guide states where a linked-worktree lead's worker session runs and that the seat run waits in the seat queue"; else no "plan-guide After approval lost the linked-worktree lead bullet or the seat queue wait"; fi
sr_sec="$(sed -n '/^## 11\. Seat run$/,$p' "$P/skills/execute-flow/SKILL.md")"
if [[ "$sr_sec" == *'seat-queue.sh wait'* ]] && [[ "$sr_sec" == *'seat-queue.sh leave'* ]] && [[ "$sr_sec" == *'seat-run-<planName>.return'* ]] && [[ "$sr_sec" == *'seated entry'* ]] && [[ "$sr_sec" == *'unqueued:'* ]] && [[ "$sr_sec" != *'TODO(seat-run): wait'* ]]; then ok "the seat run waits in the seat queue, names unqueued holders, holds a seated entry, and returns to the worktree it left"; else no "seat run queue wait, unqueued naming, seated entry, leave, or worktree return missing from execute-flow section 11"; fi
if [[ "$sr_sec" == *'<lead flag>'* ]] && [[ "$sr_sec" == *'LEAD'* ]] && [[ "$sr_sec" == *'starts no watcher'* ]] && [[ "$sr_sec" == *'runs the seat run itself'* ]] && grep -qF 'starts no watcher' "$P/doctrine/orchestration.md" && grep -qF 'starts no watcher' "$P/skills/plan-guide/SKILL.md"; then ok "the seat run starts no watcher and stops when its lead holds the main checkout, and doctrine and plan-guide say so"; else no "the lead stop is missing from execute-flow section 11, orchestration.md or plan-guide"; fi
or_miss=""
for t in 'claude stop' '--hold' 'NOSTART' 'second exit 3 in a row' "the user's permission, given in advance" 'templates/worker-<type>.md'; do grep -qF -- "$t" "$P/doctrine/orchestration.md" || or_miss="${or_miss} '${t}'"; done
for t in 'MAX_WORKING' 'Stop <name> now?'; do grep -qF -- "$t" "$P/doctrine/orchestration.md" && or_miss="${or_miss} still holds '${t}'"; done
[ -z "$or_miss" ] && ok "orchestration stops worker sessions with claude stop, holds the watch, NOSTART and second exit 3 rules, states the ceiling as the user's permission, points at the templates, and sets no worker cap or stop question" || no "orchestration lead and worker rules:${or_miss}"
for w in plan execute ship investigate; do
  tp_miss=""
  tp_terms=('{{worker_name}}' '{{lead_name}}' '{{lead_session_id}}' '{{plan_note}}' '{{task}}' '{{run_options}}' '{{ceiling}}' "is the user's permission, given in advance through the run options" 'make no other commit, push or pull request when you finish' 'AskUserQuestion' 'Stop point:')
  [ "$w" = execute ] && tp_terms+=('run the ship flow')
  for t in "${tp_terms[@]}"; do grep -qF -- "$t" "$P/templates/worker-$w.md" 2>/dev/null || tp_miss="${tp_miss} '${t}'"; done
  [ -z "$tp_miss" ] && ok "templates/worker-$w.md carries every placeholder, the ceiling as the user's permission, the git sentence, the question routing and the stop point" || no "templates/worker-$w.md missing:${tp_miss}"
done
if grep -qF 'templates/worker-' "$P/scripts/worker-spawn.sh" && grep -qF 'unfilled placeholder' "$P/scripts/worker-spawn.sh" && ! grep -qF 'MAX_WORKING' "$P/scripts/worker-spawn.sh"; then ok "worker-spawn.sh fills the plugin's templates, refuses an unfilled placeholder, and sets no worker cap"; else no "worker-spawn.sh lacks the template fill or the unfilled placeholder refusal, or holds MAX_WORKING"; fi
pg_ro="$(sed -n '/^## Run options$/,/^## [^#]/p' "$P/skills/plan-guide/SKILL.md")"
if [[ "$pg_ro" == *'session_model'* ]] && [[ "$pg_ro" == *'session_effort'* ]] && [[ "$pg_ro" == *'Which model and effort run the worker sessions?'* ]] && grep -qF 'session_model' "$P/scripts/validate-plan.py" && grep -qF 'session_effort' "$P/scripts/validate-plan.py"; then ok "plan-guide's Run options asks the worker session question and records session_model and session_effort, and validate-plan.py checks both"; else no "worker session run option keys or question missing from plan-guide's Run options or validate-plan.py"; fi
if grep -qF 'Fresh worktree base' "$P/skills/execute-flow/SKILL.md" && grep -qF 'worktree.baseRef' "$P/skills/execute-flow/SKILL.md"; then ok "execute-flow checks a fresh worktree's base against worktree.baseRef"; else no "fresh worktree base check missing from execute-flow"; fi
lw_adr="$(find "$ROOT/docs/decisions" -name '*-lead-and-worker-sessions.md' | wc -l | tr -d ' ')"
lw_miss=""
[ "$lw_adr" = 1 ] || lw_miss="${lw_miss} decision records named *-lead-and-worker-sessions.md: ${lw_adr}, wanted 1"
grep -qF 'superseded_by' "$ROOT/docs/decisions/0008-crawl-session-is-the-parent.md" || lw_miss="${lw_miss} 0008:'superseded_by'"
for a in 0005 0006 0007 0009 0012; do grep -qF 'lead-and-worker-sessions.md' "$ROOT"/docs/decisions/"$a"-*.md 2>/dev/null || lw_miss="${lw_miss} ${a}:'lead-and-worker-sessions.md'"; done
[ -z "$lw_miss" ] && ok "one lead and worker sessions decision record supersedes 0008 and amends 0005, 0006, 0007, 0009 and 0012" || no "lead and worker sessions decision record:${lw_miss}"
if grep -qF 'scripts/seat-queue.sh *)' "$P/commands/setup.md" && grep -qF 'scripts/seat-queue.sh <join|leave|list|wait>' "$P/commands/setup.md" && grep -qF 'scripts/worker-spawn.sh *)' "$P/commands/setup.md" && grep -qF 'scripts/worker-watch.sh *)' "$P/commands/setup.md" && grep -qF '[--lead <sessionId>]' "$P/commands/setup.md" && grep -qF 'claude --bg' "$P/commands/setup.md"; then ok "setup offers the prompt-free seat-queue and worker script rules, the seat-queue usage line with its lead flag, and checks for claude --bg"; else no "setup lacks the seat-queue or worker script allow rules, the seat-queue usage line or its lead flag, or the claude --bg check"; fi
su_rules="$(sed -n '/^## Rules$/,$p' "$P/commands/setup.md")"
su_doc="$(sed -n '/^### `\/toolkit:setup`$/,/^### `\/toolkit:topic`$/p' "$ROOT/docs/commands.md")"
su_miss=""
for t in 'AskUserQuestion' '(Recommended)' 'yes <name>' 'pending (human)' 'protect-files.sh'; do [[ "$su_rules" == *"$t"* ]] || su_miss="${su_miss} rules:'${t}'"; done
for t in 'AskUserQuestion' 'yes <name>' 'pending (human)'; do [[ "$su_doc" == *"$t"* ]] || su_miss="${su_miss} docs:'${t}'"; done
grep -qF 'yes <name>' "$P/doctrine/git-safety.md" || su_miss="${su_miss} git-safety:'yes <name>'"
for t in 'Toolkit Scripts watch-mr line' 'Toolkit Scripts topic-index line' 'replace Own PR Merge' 'replace Own MR Merge' 'rewrite repository environment entries' 'worker scripts rules' 'Toolkit Scripts worker lines' 'Toolkit Scripts seat-queue lead flag'; do grep -qF "$t" "$P/commands/setup.md" && [[ "$su_doc" == *"$t"* ]] || su_miss="${su_miss} offer:'${t}'"; done
[ -z "$su_miss" ] && ok "setup's Rules, its doc and git-safety state the yes <name> line, the Rules and doc the question form and the other-session rule, the Rules the file guard confirm, and setup and its doc name the new offers" || no "setup question wording missing:${su_miss}"
su_old=""
[[ "$su_rules" == *'Never ask through AskUserQuestion'* ]] && su_old="${su_old} rules:'Never ask through AskUserQuestion'"
[[ "$su_doc" == *'answer never counts'* ]] && su_old="${su_old} docs:'answer never counts'"
grep -qF 'Reply "yes ' "$P/commands/setup.md" && su_old="${su_old} setup:'Reply \"yes '"
grep -qF 'a setup write that meets it goes through' "$P/doctrine/git-safety.md" && su_old="${su_old} git-safety:'a setup write that meets it goes through'"
[ -z "$su_old" ] && ok "setup, its doc and git-safety carry none of the old typed-reply consent wording" || no "old setup consent wording still present:${su_old}"
su_pr="$(grep -cE '^ +Own PR Merge: ' "$P/commands/setup.md")"
su_mr="$(grep -cE '^ +Own MR Merge: ' "$P/commands/setup.md")"
[ "$su_pr" = 1 ] && [ "$su_mr" = 1 ] && ok "setup.md holds each shipped merge entry once" || no "setup.md shipped merge entry count -> Own PR Merge: ${su_pr} Own MR Merge: ${su_mr}, wanted 1 each"
cg_sec="$(sed -n '/^## 3\. Route/,/^## 4\. Hand off with the evidence$/p' "$P/skills/crawl/SKILL.md")"
gr_fm="$(sed -n '2,/^---$/p' "$P/skills/grill/SKILL.md")"
gr_done="$(sed -n '/^## Done signal/,/^## Boundary$/p' "$P/skills/grill/SKILL.md")"
cg_miss=""
for t in 'Grill check' 'skills/grill/SKILL.md' 'nothing in the evidence needs your answer' 'Outcome:'; do [[ "$cg_sec" == *"$t"* ]] || cg_miss="${cg_miss} '${t}'"; done
[ -z "$cg_miss" ] && ok "crawl section 3 runs the grill check, loads the grill skill, and states the one line for nothing found" || no "crawl section 3 grill check missing:${cg_miss}"
cg_bnd=""
grep -qF 'recommend a grill and stop' "$P/skills/crawl/SKILL.md" && cg_bnd="${cg_bnd} still holds 'recommend a grill and stop'"
sed -n '/^## Boundary/,$p' "$P/skills/crawl/SKILL.md" | grep -qF 'grill check' || cg_bnd="${cg_bnd} Boundary lacks 'grill check'"
[ -z "$cg_bnd" ] && ok "crawl's Boundary names the grill check and no longer recommends a grill and stops" || no "crawl Boundary:${cg_bnd}"
gr_miss=""
[[ "$gr_fm" == *'grill check'* ]] || gr_miss="${gr_miss} frontmatter:'grill check'"
[[ "$gr_done" == *'run options'* ]] || gr_miss="${gr_miss} Done signal:'run options'"
[ -z "$gr_miss" ] && ok "grill's description takes the crawl's grill check as a trigger and its hand off returns to the crawl's run options" || no "grill crawl trigger or hand back missing:${gr_miss}"
rt_miss=""
grep -qF 'grill check' "$P/doctrine/workflow-routing.md" || rt_miss="${rt_miss} workflow-routing:'grill check'"
grep -qF 'grill check' "$ROOT/docs/skills.md" || rt_miss="${rt_miss} docs/skills.md:'grill check'"
grep -qF 'Five carve-outs' "$P/doctrine/workflow-routing.md" && rt_miss="${rt_miss} workflow-routing still says 'Five carve-outs'"
grep -qF 'five narrow carve-outs' "$ROOT/docs/skills.md" && rt_miss="${rt_miss} docs/skills.md still says 'five narrow carve-outs'"
grep -qF 'Six carve-outs' "$P/doctrine/workflow-routing.md" && rt_miss="${rt_miss} workflow-routing still says 'Six carve-outs'"
grep -qF 'six narrow carve-outs' "$ROOT/docs/skills.md" && rt_miss="${rt_miss} docs/skills.md still says 'six narrow carve-outs'"
grep -qF 'Ten carve-outs' "$P/doctrine/workflow-routing.md" || rt_miss="${rt_miss} workflow-routing:'Ten carve-outs'"
grep -qF 'ten narrow carve-outs' "$ROOT/docs/skills.md" || rt_miss="${rt_miss} docs/skills.md:'ten narrow carve-outs'"
[ -z "$rt_miss" ] && ok "workflow-routing and docs/skills.md name the grill check carve-out and count ten carve-outs" || no "grill check carve-out:${rt_miss}"
pg_plan="$(sed -n '/^## Planning Workflow$/,/^### Plan status lifecycle$/p' "$P/skills/plan-guide/SKILL.md")"
wf_s4="$(sed -n '/^## 4\. Emit the parent umbrella plan$/,/^## 5\. Emit child plan stubs$/p' "$P/skills/wayfinder/SKILL.md")"
wf_s5="$(sed -n '/^## 5\. Emit child plan stubs$/,/^## 6\. Hand off$/p' "$P/skills/wayfinder/SKILL.md")"
pg_miss=""
for t in '### Planning grill' 'skills/grill/SKILL.md' 'Agreed in the grill:' 'Agreed in the grill check:' 'plan - <parent>.md' 'route rubric' 'Outcome:'; do [[ "$pf4" == *"$t"* ]] || pg_miss="${pg_miss} plan-flow:'${t}'"; done
for t in '### Planning grill' 'Agreed in the grill:' 'Agreed in the grill check:' 'plan - <parent>.md' 'new scope' 'route rubric' 'kebab title' 'from agent view' 'never counts as an answer' 'Outcome:'; do [[ "$pg_plan" == *"$t"* ]] || pg_miss="${pg_miss} plan-guide:'${t}'"; done
[[ "$gr_fm" == *'planning grill'* ]] || pg_miss="${pg_miss} grill frontmatter:'planning grill'"
for t in 'Loaded grills' 'outcome line' 'more than one reasonable reading' 'A finding is not an answer' 'kebab title' 'plan - <parent>.md' 'from agent view' 'never counts as an answer'; do grep -qF "$t" "$P/skills/grill/SKILL.md" || pg_miss="${pg_miss} grill:'${t}'"; done
for t in 'planning grill question' 'from agent view'; do grep -qF "$t" "$P/skills/wayfinder/SKILL.md" || pg_miss="${pg_miss} wayfinder:'${t}'"; done
[[ "$wf_s4" == *'Agreed in the grill check:'* ]] || pg_miss="${pg_miss} wayfinder section 4:'Agreed in the grill check:'"
[[ "$wf_s5" == *'grill check block'* ]] || pg_miss="${pg_miss} wayfinder section 5:'grill check block'"
for t in 'planning grill question' 'Loaded grills'; do grep -qF "$t" "$P/doctrine/orchestration.md" || pg_miss="${pg_miss} orchestration:'${t}'"; done
[[ "$cg_sec" == *'On the wayfinder route only'* ]] || pg_miss="${pg_miss} crawl section 3:'On the wayfinder route only'"
grep -qF 'planning grill' "$P/doctrine/workflow-routing.md" || pg_miss="${pg_miss} workflow-routing:'planning grill'"
grep -qF 'planning grill' "$ROOT/docs/skills.md" || pg_miss="${pg_miss} docs/skills.md:'planning grill'"
for t in '### Planning grill' '### Grill check' '### Outcome line'; do grep -qF "$t" "$ROOT/docs/glossary.md" || pg_miss="${pg_miss} glossary:'${t}'"; done
pg_adr="$(find "$ROOT/docs/decisions" -name '*-grill-is-a-fixed-step-of-planning.md' | wc -l | tr -d ' ')"
[ "$pg_adr" = 1 ] || pg_miss="${pg_miss} decision records named *-grill-is-a-fixed-step-of-planning.md: ${pg_adr}, wanted 1"
[ -z "$pg_miss" ] && ok "plan-flow, plan-guide, grill, wayfinder, crawl, doctrine, docs/skills.md, the glossary and one decision record define the planning grill and that only the user's own answer counts" || no "planning grill missing:${pg_miss}"
gs_old=""
for t in 'Agreed in the grill:' 'On the plan-guide and wayfinder routes, once the route is confirmed and before the run options'; do grep -qF "$t" "$P/skills/crawl/SKILL.md" && gs_old="${gs_old} crawl:'${t}'"; done
for t in 'Crawl-scoped grills' 'one of those two gates'; do grep -qF "$t" "$P/skills/grill/SKILL.md" && gs_old="${gs_old} grill:'${t}'"; done
for t in 'grill recommended' 'explicitly user-invoked'; do grep -qF "$t" "$P/skills/wayfinder/SKILL.md" && gs_old="${gs_old} wayfinder:'${t}'"; done
[[ "$wf_s5" == *'Agreed in the grill check:'* ]] && gs_old="${gs_old} wayfinder section 5:'Agreed in the grill check:'"
grep -qF 'scoped deep grill where requirements are not pinned' "$P/skills/expedition/SKILL.md" && gs_old="${gs_old} expedition:'scoped deep grill where requirements are not pinned'"
grep -qF 'recommended a scoped grill' "$ROOT/docs/skills.md" && gs_old="${gs_old} docs/skills.md:'recommended a scoped grill'"
for s in grill plan-guide plan-flow wayfinder; do grep -qF "User's own answer:" "$P/skills/$s/SKILL.md" && gs_old="${gs_old} ${s}:\"User's own answer:\""; done
[ -z "$gs_old" ] && ok "crawl, grill, plan-guide, plan-flow, wayfinder, expedition and docs/skills.md carry none of the old grill wording or the grill answer relay, and no wayfinder child stub copies the grill check block" || no "old grill wording still present:${gs_old}"
pb_doc="$(sed -n '/^## plan-builder\.js$/,/^## execute-runner\.js$/p' "$ROOT/docs/workflows.md")"
tl_miss=""
for t in 'a.discoveryOnly' 'a.skipDiscovery' 'a.grill' 'PLAN_CONTEXT'; do grep -qF "$t" "$P/workflows/plan-builder.js" || tl_miss="${tl_miss} plan-builder.js:'${t}'"; done
for t in '`discoveryOnly: true`' '`skipDiscovery: true`' 'add `grill`' 'pass `resumeFromRunId` with that runId' '.args.json'; do [[ "$pf4" == *"$t"* ]] || tl_miss="${tl_miss} plan-flow:'${t}'"; done
for t in '- `discoveryOnly` (optional' '- `skipDiscovery` (optional' '- `grill` (optional'; do [[ "$pb_doc" == *"$t"* ]] || tl_miss="${tl_miss} docs/workflows.md plan-builder section:'${t}'"; done
[[ "$pb_doc" == *'resumeFromRunId'* ]] || tl_miss="${tl_miss} docs/workflows.md plan-builder section:'resumeFromRunId'"
[ -z "$tl_miss" ] && ok "plan-builder.js, plan-flow section 4 and docs/workflows.md name the two-launch args, and plan-flow and the doc name the resume" || no "two-launch contract missing:${tl_miss}"
if grep -qF 'Default branch rule' "$P/skills/execute-flow/SKILL.md" && grep -qF '| free | 0 | from approved or start-work | a default branch | worktree |' "$P/skills/execute-flow/SKILL.md" && grep -qF 'default branch rule' "$ROOT/docs/context/context-worktree-seat.md"; then ok "execute-flow opens a worktree on a free, clean main checkout that sits on a default branch"; else no "default branch rule missing from execute-flow or context-worktree-seat.md"; fi
# Claude Code truncates a skill's description plus when_to_use at 1,536 characters in the skill listing.
dl="$(python3 - "$P/skills" <<'PY'
import glob, os, re, sys
over = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*', 'SKILL.md'))):
    fm = open(f).read().split('\n---', 1)[0]
    total = 0
    for key in ('description', 'when_to_use'):
        m = re.search(r'^' + key + r':[ \t]*(.*)\n((?:[ \t]+.*\n?|\n)*)', fm, re.M)
        if not m:
            continue
        head, block = m.group(1).strip(), m.group(2)
        if head[:1] in ('>', '|'):
            parts = [l.strip() for l in block.splitlines() if l.strip()]
            total += len(('\n' if head[:1] == '|' else ' ').join(parts))
        else:
            total += len(head.strip(chr(34) + chr(39)))
    if total > 1536:
        over.append(os.path.basename(os.path.dirname(f)) + ' ' + str(total))
print(','.join(over) or 'NONE')
PY
)"
[ "$dl" = "NONE" ] && ok "every skill's description and when_to_use fit the 1,536-character skill listing cap" || no "skill listing cap exceeded: ${dl:-python3 failed}"
if grep -qF 'occupant: ' "$P/scripts/seat-check.sh" && grep -qF 'occupant:' "$P/skills/execute-flow/SKILL.md"; then ok "seat-check prints and execute-flow reads the worktree occupant line"; else no "occupant line missing from seat-check.sh or execute-flow"; fi
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
# worker-spawn-mode.sh only fires if hooks.json wires it to a PreToolUse entry matched on Bash.
want "hooks.json wires worker-spawn-mode.sh to PreToolUse matcher Bash" \
  "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); m=[e for e in d.get('hooks',{}).get('PreToolUse',[]) if e.get('matcher')=='Bash']; print(json.dumps(m))" "$P/hooks/hooks.json" 2>/dev/null)" \
  "worker-spawn-mode.sh"
# toolkit-models.json.template must offer every shipped agent under "agents" as a {model, effort}
# object, or a new agent silently has no default layer for resolve-models.sh.
tm_match="$(python3 -c "
import json,glob,os,sys
P=sys.argv[1]
agents=sorted(os.path.basename(f)[:-3] for f in glob.glob(P+'/agents/*.md'))
tmpl=json.load(open(P+'/scripts/toolkit-models.json.template'))
keys=sorted(tmpl.get('agents',{}).keys())
vals=tmpl.get('agents',{}).values()
shaped=all(isinstance(v,dict) and isinstance(v.get('model'),str) and isinstance(v.get('effort'),str) for v in vals)
print('MATCH' if agents==keys and shaped else 'MISMATCH agents=%s template=%s shaped=%s' % (agents, keys, shaped))
" "$P" 2>/dev/null)"
case "$tm_match" in
  MATCH) ok "toolkit-models.json.template lists every shipped agent as {model, effort} objects" ;;
  *) no "toolkit-models.json.template lists every shipped agent as {model, effort} objects (${tm_match:-python3 failed})" ;;
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
pv="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$P/.claude-plugin/plugin.json" 2>/dev/null)"
if [[ "$pv" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then ok "plugin.json version is three dot-separated numbers"; else no "plugin.json version is not three dot-separated numbers (got: ${pv:0:60})"; fi
mv_keys="$(python3 -c 'import json,sys; print(" ".join(sorted(k for p in json.load(open(sys.argv[1]))["plugins"] if p.get("name")=="toolkit" for k in p)))' "$ROOT/.claude-plugin/marketplace.json" 2>/dev/null)"
if [ -n "$mv_keys" ] && [[ " $mv_keys " != *" version "* ]]; then ok "marketplace entry for toolkit carries no version key"; else no "marketplace entry for toolkit is missing or carries a version key (keys: ${mv_keys:0:60})"; fi
if [ -n "$pv" ] && grep -qF "id=\"v$pv\"" "$ROOT/site/release-notes.html"; then ok "site/release-notes.html holds an entry for plugin.json version $pv"; else no "site/release-notes.html holds no entry with id=\"v$pv\" for the plugin.json version"; fi

echo "== Hook behavior (fixture suite is authoritative) =="
hout="$(cd "$P/hooks/tests" && bash run-all.sh 2>&1)"; hrc=$?
if [ "$hrc" -eq 2 ]; then
  fmsg="$(printf '%s' "$hout" | grep '^FATAL:' | tail -1)"
  no "hook fixture suite (${fmsg:-suite exited 2 with no FATAL message})"
else
  # exit code is part of the pass condition and the RESULT line is picked by prefix,
  # not by trailing position: a merged stderr line must not masquerade as the verdict.
  out="$(printf '%s' "$hout" | grep -E '^RESULT: ' | tail -1)"
  if [ "$hrc" -eq 0 ] && suite_pass "$out" 240; then
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
# agent and skill overrides match by frontmatter name, never by file name (isolated temp HOME)
avh="$(mktemp -d)"; mkdir -p "$avh/.claude/agents/sub"; printf -- '---\nname: code-reviewer\n---\n' > "$avh/.claude/agents/sub/mine.md"
avout="$(echo '{}' | HOME="$avh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$avh"
want "session-start announces an agent override by its frontmatter name" "$avout" "agent:code-reviewer"
avh="$(mktemp -d)"; mkdir -p "$avh/.claude/agents"; printf -- '---\nname: my-verifier\n---\n' > "$avh/.claude/agents/verifier.md"
avout="$(echo '{}' | HOME="$avh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$avh"
case "$avout" in *"agent:verifier"*) no "session-start announces no agent override for a plugin agent's file name under another frontmatter name" ;; *) ok "session-start announces no agent override for a plugin agent's file name under another frontmatter name" ;; esac
svh="$(mktemp -d)"; mkdir -p "$svh/.claude/skills/mine"; printf -- '---\nname: grill\n---\n' > "$svh/.claude/skills/mine/SKILL.md"
svout="$(echo '{}' | HOME="$svh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$svh"
want "session-start announces a skill override by its frontmatter name" "$svout" "skill:grill"
svh="$(mktemp -d)"; mkdir -p "$svh/.claude/skills/grill"; printf -- '---\nname: other\n---\n' > "$svh/.claude/skills/grill/SKILL.md"
svout="$(echo '{}' | HOME="$svh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$svh"
want "session-start announces a skill override by its directory name" "$svout" "skill:grill"
# auto mode: missing mutating git rules and an environment block naming another host are announced (isolated temp HOME)
amh="$(mktemp -d)"; mkdir -p "$amh/.claude"
printf '{"permissions":{"defaultMode":"auto","allow":["Bash(git push:*)"]},"autoMode":{"environment":["- Trusted repo: gitlab.example.com only"]}}\n' > "$amh/.claude/settings.json"
amout="$(echo '{"source":"startup"}' | HOME="$amh" bash "$P/hooks/session-start.sh" 2>/dev/null)"
want "session-start announces missing auto mode git rules" "$amout" "lacks these allow rules: Bash(git add:*) Bash(git commit:*)"
want "session-start announces an environment block that omits this repo's host" "$amout" "does not name this repo's remote host"
want "session-start status line points auto mode gaps at /toolkit:setup" "$amout" "auto mode: classifier settings incomplete, run /toolkit:setup"
printf '{"permissions":{"defaultMode":"auto"},"autoMode":{"environment":["x"],"allow":["Own PR Merge: x"],"soft_deny":["y"],"hard_deny":["z"]}}\n' > "$amh/.claude/settings.json"
amout="$(echo '{"source":"startup"}' | HOME="$amh" bash "$P/hooks/session-start.sh" 2>/dev/null)"
want "session-start names every autoMode array without \$defaults" "$amout" 'no $defaults entry: environment allow soft_deny hard_deny.'
printf '{"permissions":{"defaultMode":"auto"},"autoMode":{"environment":["$defaults","x"],"allow":["$defaults","x"],"soft_deny":["$defaults","x"],"hard_deny":["$defaults","x"]}}\n' > "$amh/.claude/settings.json"
amout="$(echo '{"source":"startup"}' | HOME="$amh" bash "$P/hooks/session-start.sh" 2>/dev/null)"
case "$amout" in *'no $defaults entry'*) no "session-start names no autoMode array that holds \$defaults" ;; *) ok "session-start names no autoMode array that holds \$defaults" ;; esac
printf '{"permissions":{"defaultMode":"auto"},"autoMode":{"environment":["x"],"allow":["$defaults","x"]}}\n' > "$amh/.claude/settings.json"
amout="$(echo '{"source":"startup"}' | HOME="$amh" bash "$P/hooks/session-start.sh" 2>/dev/null)"
want "session-start names only the autoMode arrays without \$defaults" "$amout" 'no $defaults entry: environment.'
printf '{"permissions":{"defaultMode":"default","allow":[]}}\n' > "$amh/.claude/settings.json"
amout="$(echo '{"source":"startup"}' | HOME="$amh" bash "$P/hooks/session-start.sh" 2>/dev/null)"; rm -rf "$amh"
case "$amout" in *"Auto mode is on"*) no "session-start stays silent on auto mode outside auto mode" ;; *) ok "session-start stays silent on auto mode outside auto mode" ;; esac
want "setup offers the auto mode git rules" "$(cat "$P/commands/setup.md")" "Bash(git push:*)"
want "git-safety carries the classifier command-shape section" "$(cat "$P/doctrine/git-safety.md")" "## Command shape under the permission classifier"

echo "== Scripts (guardrails) =="
vfh="$(mktemp -d)"; mkdir -p "$vfh/.claude" "$vfh/vault/notes"
printf '{"vault_path":"%s","root_folder":"notes"}\n' "$vfh/vault" > "$vfh/.claude/toolkit-vault.json"
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
oah="$(mktemp -d)"; mkdir -p "$oah/.claude/agents/sub"; printf -- '---\nname: verifier\n---\n' > "$oah/.claude/agents/sub/mine.md"
want "override refuses an agent a user agent under another file name already names" "$(HOME="$oah" bash "$P/scripts/override.sh" agents verifier 2>&1)" "'verifier' already exists as a user agent"
rm -rf "$oah"
osh="$(mktemp -d)"; mkdir -p "$osh/.claude/skills/mine"; printf -- '---\nname: grill\n---\n' > "$osh/.claude/skills/mine/SKILL.md"
want "override refuses a skill a personal skill under another directory name already names" "$(HOME="$osh" bash "$P/scripts/override.sh" skills grill 2>&1)" "'grill' already exists as a user skill"
rm -rf "$osh"
onh="$(mktemp -d)"; mkdir -p "$onh/plugin/scripts" "$onh/plugin/agents"; cp "$P/scripts/override.sh" "$onh/plugin/scripts/"; cp "$P/agents/verifier.md" "$onh/plugin/agents/"
want "override refuses an agent override when hooks/lib/component-names.sh is missing" "$(HOME="$onh" bash "$onh/plugin/scripts/override.sh" agents verifier 2>&1)" "refused: hooks/lib/component-names.sh not found"
rm -rf "$onh"

echo "== Plan validator =="
out="$(bash "$P/scripts/tests/validate-plan/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "plan-validator fixture suite" "$out" 51

echo "== Topic recall =="
out="$(bash "$P/scripts/tests/topic-recall/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "topic-recall behavior suite" "$out" 62

echo "== vault-fs containment =="
out="$(bash "$P/scripts/tests/vault-fs/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "vault-fs behavior suite" "$out" 47

echo "== run-checkpoint journal read =="
out="$(bash "$P/scripts/tests/run-checkpoint/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "run-checkpoint behavior suite" "$out" 71

echo "== slice-capture =="
out="$(bash "$P/scripts/tests/slice-capture/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "slice-capture behavior suite" "$out" 18

echo "== several-repos commands =="
out="$(bash "$P/scripts/tests/several-repos/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "several-repos commands suite" "$out" 18

echo "== git-ro execution boundary =="
out="$(bash "$P/scripts/tests/git-ro/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "git-ro behavior suite" "$out" 12
python3 "$P/scripts/validate-plan.py" "$P/scripts/tests/validate-plan/fixtures/2026-01-01-example-feature/plan - example-feature.md" >/dev/null 2>&1
code "validate-plan accepts a canonical plan" "$?" 0

echo "== seat-check holder rule =="
out="$(bash "$P/scripts/tests/seat-check/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "seat-check behavior suite" "$out" 20

echo "== seat-queue order and watcher =="
out="$(bash "$P/scripts/tests/seat-queue/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "seat-queue behavior suite" "$out" 55

echo "== worker sessions =="
out="$(bash "$P/scripts/tests/worker-spawn/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "worker-spawn behavior suite" "$out" 50
out="$(bash "$P/scripts/tests/worker-watch/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "worker-watch behavior suite" "$out" 47

echo "== resolve-models layering =="
out="$(bash "$P/scripts/tests/resolve-models/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "resolve-models behavior suite" "$out" 34

echo "== watch-mr watcher =="
out="$(bash "$P/scripts/tests/watch-mr/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "watch-mr behavior suite" "$out" 95

echo "== plan-builder control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/plan-builder/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "plan-builder control-flow suite" "$out" 47
else
  skip "skipped: node not found; plan-builder control-flow suite"
fi

echo "== execute-runner control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/execute-runner/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "execute-runner control-flow suite" "$out" 341
else
  skip "skipped: node not found; execute-runner control-flow suite"
fi

echo "== ship-runner control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/ship-runner/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "ship-runner control-flow suite" "$out" 335
else
  skip "skipped: node not found; ship-runner control-flow suite"
fi

echo "== review-mr control flow =="
if command -v node >/dev/null 2>&1; then
  out="$(bash "$P/workflows/tests/review-mr/run-tests.sh" 2>/dev/null | tail -1)"
  suite_ok "review-mr control-flow suite" "$out" 70
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
bad=[]; none=[]; pin=[]
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
    pins=[l.strip().split(':')[0] for l in fm.splitlines() if l.strip().startswith(('model:','effort:'))]
    if pins: pin.append(b)
print("BAD",",".join(bad),"NONE",",".join(none),"PIN",",".join(pin))
PY
)"
[ "$inv" = "BAD  NONE  PIN " ] && ok "no agent can spawn sub-agents (leaf), none omits allowlist, none pins a model or effort" || no "orchestration invariant broken: $inv"
th="$(python3 -c "import json,sys; t=json.load(open(sys.argv[1]))['agents']; h=[k for k,v in t.items() if 'haiku' in json.dumps(v).lower()]; print(','.join(h) or 'NONE')" "$P/scripts/toolkit-models.json.template" 2>/dev/null)"
[ "$th" = "NONE" ] && ok "toolkit-models.json.template routes no agent to Haiku" || no "toolkit-models.json.template routes to Haiku: ${th:-python3 failed}"
if grep -qF 'Tripwires:' "$P/agents/plan-critic.md" && grep -qF 'Walk-away checks:' "$P/agents/plan-critic.md" && grep -qF '60 lines' "$P/agents/plan-critic.md" \
   && grep -qF 'Tripwires block' "$P/skills/plan-guide/SKILL.md" && grep -qF 'Walk-away checks block' "$P/skills/plan-guide/SKILL.md"; then
  ok "plan-critic's Tripwires:/Walk-away checks:/60-line return contract is referenced by plan-guide"
else
  no "plan-critic / plan-guide Tripwires-Walk-away contract broken"
fi

echo "== Vault config =="
vc_bad="$(grep -rlF --exclude-dir=tests --exclude-dir=__pycache__ 'obsidian-sync.json' "$P/hooks" "$P/scripts" | sed "s#^$P/##" | grep -v -x -e 'hooks/lib/vault-config.sh' -e 'scripts/topic-recall.py')"
[ -z "$vc_bad" ] && ok "only hooks/lib/vault-config.sh and scripts/topic-recall.py name the legacy vault config file" || no "legacy vault config file named outside its two readers -> $(printf '%s' "$vc_bad" | tr '\n' ' ')"

echo "== Doc owner =="
[ "$(grep -rh '^owner:' "$ROOT/docs" | sort -u | wc -l)" -eq 1 ] && ok "no two owner lines under docs/ hold different values" || no "docs/ owner lines hold more than one value -> $(grep -rh '^owner:' "$ROOT/docs" | sort -u | tr '\n' ' ')"

echo "== Site =="
site="$(python3 - "$ROOT" <<'PY'
import glob,json,os,sys
from html.parser import HTMLParser
from urllib.parse import urlsplit
ROOT=sys.argv[1]
S=os.path.join(ROOT,"site")
repo=json.load(open(os.path.join(ROOT,"plugins/toolkit/.claude-plugin/plugin.json")))["repository"].rstrip("/")
bad=[]
class Page(HTMLParser):
    def __init__(self,name):
        super().__init__(); self.name=name
    def handle_starttag(self,tag,attrs):
        if tag=="script": bad.append(f"{self.name}: <script> tag")
        for k,v in attrs:
            if k not in ("href","src") or not v: continue
            u=urlsplit(v)
            asset=k=="src" or tag=="link"
            if u.scheme or u.netloc:
                if asset: bad.append(f"{self.name}: asset from another host {v}")
                if u.netloc.lower() in ("github.com","www.github.com") and not (v==repo or v.startswith(repo+"/")):
                    bad.append(f"{self.name}: github link outside the repository {v}")
            elif u.path:
                t=os.path.normpath(os.path.join(S,u.path))
                if not t.startswith(S+os.sep) or not os.path.isfile(t):
                    bad.append(f"{self.name}: {k} {v} does not resolve to a file under site/")
pages=sorted(glob.glob(os.path.join(S,"*.html")))
if not pages: bad.append("no site/*.html pages")
for f in pages:
    Page(os.path.basename(f)).feed(open(f).read())
idx=open(os.path.join(S,"index.html")).read() if os.path.isfile(os.path.join(S,"index.html")) else ""
for h in sorted(glob.glob(os.path.join(ROOT,"plugins/toolkit/hooks/*.sh"))):
    if os.path.basename(h) not in idx: bad.append(f"index.html does not name hook {os.path.basename(h)}")
print("BAD:"+("; ".join(bad) if bad else "NONE"))
PY
)"
case "$site" in *"BAD:NONE"*) ok "site pages resolve their relative links, load nothing from another host, hold no script, link only into the repository on github.com, and index.html names every hook";; *) no "site -> ${site#*BAD:}";; esac

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
[ "$fail" -eq 0 ] && [ "$((pass+skip))" -ge 210 ]
