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
[ "$(ls $P/agents/*.md 2>/dev/null | wc -l)" -eq 13 ] && ok "13 agents" || no "13 agents"
[ "$(ls -d $P/skills/*/ 2>/dev/null | wc -l)" -eq 12 ] && ok "12 skills" || no "12 skills"
[ "$(ls $P/commands/*.md 2>/dev/null | wc -l)" -eq 8 ] && ok "8 commands" || no "8 commands"
[ "$(ls $P/rules/*.md 2>/dev/null | wc -l)" -eq 7 ] && ok "7 rules" || no "7 rules"
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
[ "$(ls $P/doctrine/*.md 2>/dev/null | wc -l)" -eq 13 ] && ok "13 doctrine files" || no "13 doctrine files"
[ "$(ls $P/hooks/*.sh 2>/dev/null | wc -l)" -eq 8 ] && ok "8 hook scripts" || no "8 hook scripts"
for f in hooks/hooks.json CLAUDE.md README.md workflows/review-mr.js \
         skills/gitlab-mr-review/scripts/post_mr_comments.py \
         skills/grill/SKILL.md \
         scripts/vault-fs.sh scripts/git-ro.sh; do
  [ -f "$P/$f" ] && ok "present: $f" || no "MISSING: $f"
done

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
  if [ "$hrc" -eq 0 ] && suite_pass "$out" 127; then
    ok "hook fixture suite"
  else
    no "hook fixture suite (exit $hrc, got: ${out:0:60})"
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
want "override lists components (no arg)" "$(bash "$P/scripts/override.sh" 2>&1)" "conventions"
want "override refuses unknown name"      "$(bash "$P/scripts/override.sh" nonesuch 2>&1)" "refused"
want "override refuses ambiguous name"    "$(bash "$P/scripts/override.sh" security 2>&1)" "ambiguous"
doh="$(mktemp -d)"; HOME="$doh" bash "$P/scripts/override.sh" conventions >/dev/null 2>&1; HOME="$doh" bash "$P/scripts/override.sh" testing >/dev/null 2>&1
{ [ -f "$doh/.claude/doctrine/conventions.md" ] && [ -f "$doh/.claude/rules/testing.md" ]; } && ok "override copies doctrine + rule into ~/.claude" || no "override copy"; rm -rf "$doh"

echo "== Plan validator =="
out="$(bash "$P/scripts/tests/validate-plan/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "plan-validator fixture suite" "$out" 24

echo "== vault-fs containment =="
out="$(bash "$P/scripts/tests/vault-fs/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "vault-fs behavior suite" "$out" 15

echo "== git-ro execution boundary =="
out="$(bash "$P/scripts/tests/git-ro/run-tests.sh" 2>/dev/null | tail -1)"
suite_ok "git-ro behavior suite" "$out" 12
python3 "$P/scripts/validate-plan.py" "$P/scripts/tests/validate-plan/fixtures/2026-01-01-example-feature/plan - example-feature.md" >/dev/null 2>&1
code "validate-plan accepts a canonical plan" "$?" 0

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

echo
echo "RESULT: $pass passed, $skip skipped, $fail failed"
# Floor, not just zero-failures: silently deleting real checks must not read green.
# Floor on pass+skip, not pass alone: an environment-dependent skip (no claude CLI,
# no node, no local plugin install) must not read as a vanished check.
[ "$fail" -eq 0 ] && [ "$((pass+skip))" -ge 42 ]
