#!/usr/bin/env bash
# Mechanical acceptance battery for the toolkit plugin. Deterministic checks only;
# live-session behavior (agent spawns, skill prompts, doctrine adherence) is covered
# by the companion checklist in VERIFY.md. Run from anywhere: bash verify.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$ROOT/plugins/toolkit"
export CLAUDE_PLUGIN_ROOT="$P"
pass=0; fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
# report: name, actual, expected-substring
want() { case "$2" in *"$3"*) ok "$1";; *) no "$1 (got: ${2:0:60})";; esac; }
# report on exit code
code() { if [ "$2" -eq "$3" ]; then ok "$1"; else no "$1 (exit $2, wanted $3)"; fi; }

echo "== Structure =="
n() { ls $1 2>/dev/null | wc -l | tr -d ' '; }
[ "$(ls $P/agents/*.md 2>/dev/null | wc -l)" -eq 12 ] && ok "12 agents" || no "12 agents"
[ "$(ls -d $P/skills/*/ 2>/dev/null | wc -l)" -eq 9 ] && ok "9 skills" || no "9 skills"
[ "$(ls $P/commands/*.md 2>/dev/null | wc -l)" -eq 7 ] && ok "7 commands" || no "7 commands"
[ "$(ls $P/rules/*.md 2>/dev/null | wc -l)" -eq 5 ] && ok "5 rules" || no "5 rules"
[ "$(ls $P/doctrine/*.md 2>/dev/null | wc -l)" -eq 12 ] && ok "12 doctrine files" || no "12 doctrine files"
[ "$(ls $P/hooks/*.sh 2>/dev/null | wc -l)" -eq 5 ] && ok "5 hook scripts" || no "5 hook scripts"
for f in hooks/hooks.json CLAUDE.md README.md workflows/review-mr.js \
         skills/gitlab-mr-review/scripts/post_mr_comments.py \
         skills/grill/SKILL.md \
         scripts/vault-fs.sh scripts/git-ro.sh; do
  [ -f "$P/$f" ] && ok "present: $f" || no "MISSING: $f"
done

echo "== Manifest =="
if claude plugin validate "$ROOT" >/dev/null 2>&1; then ok "plugin validate"; else no "plugin validate"; fi

echo "== Hook behavior (fixture suite is authoritative) =="
out="$(cd "$P/hooks/tests" && bash run-all.sh 2>/dev/null | tail -1)"
want "hook fixture suite" "$out" "0 failed"
# spot-confirm session-start's two injections directly (no fixture asserts the pair)
ss="$(echo '{}' | bash "$P/hooks/session-start.sh" 2>/dev/null)"
want "session-start injects a write-time rule" "$ss" "Verify behavior, not implementation"
want "session-start injects doctrine pointer"  "$ss" "Toolkit doctrine: read the index"

echo "== Scripts (guardrails) =="
want "vault-fs refuses traversal"  "$(bash "$P/scripts/vault-fs.sh" rm '../x.md' 2>&1)" "refused"
want "git-ro refuses mutation"     "$(bash "$P/scripts/git-ro.sh" "$ROOT" commit 2>&1)" "refused"
bash "$P/scripts/git-ro.sh" "$ROOT" status >/dev/null 2>&1; code "git-ro allows status" "$?" 0

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
  printf '  - node not found; skipped detector smoke test\n'
fi

echo "== Resolver (installed copy) =="
IP="$(jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null)"
if [ -n "$IP" ] && [ -d "$IP" ]; then ok "installed_plugins.json resolves to a real dir"; else no "resolver ($IP)"; fi

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
import os,sys,glob
P,ROOT=sys.argv[1],sys.argv[2]
def doc(rel):
    p=os.path.join(ROOT,rel)
    return open(p).read().lower() if os.path.exists(p) else ""
missing=[]
def check(items,rel,label):
    t=doc(rel)
    for it in items:
        if it.lower() not in t: missing.append(f"{label} '{it}' not in {rel}")
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
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
