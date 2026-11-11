#!/usr/bin/env bash
# Hermetic behavior suite for run-checkpoint.py. Lays out synthetic run folders as <session>/subagents/workflows/<runId>
# with their summaries at <session>/workflows/<runId>.json under a temporary HOME's ~/.claude/projects, the way the Workflow runtime does. No network, no claude binary.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP="$HERE/../../run-checkpoint.py"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d -t run-checkpoint.XXXXXX)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
S="$HOME/.claude/projects/-tmp-repo/sess"; mkdir -p "$S/workflows"
mkdir -p "$T/plugin/scripts" "$T/bare" "$T/repo"; : > "$T/plugin/scripts/vault-fs.sh"

started() { printf '{"type":"started","key":"k-%s","agentId":"%s","label":"%s","phase":"%s"}\n' "$1" "$1" "$2" "$3"; }
result() { printf '{"type":"result","key":"k-%s","agentId":"%s","result":%s,"toolsUsed":[]}\n' "$1" "$1" "$2"; }
# Each journal predates its summary's timestamp, as in a run that ended.
journal() { mkdir -p "$S/subagents/workflows/$1"; cat > "$S/subagents/workflows/$1/journal.jsonl"; touch -t 202501010000 "$S/subagents/workflows/$1/journal.jsonl"; }
SCRIPT='"const x = 1\nconst REPLAY = null\nlet a = args\n"'
ARGS="{\"planName\":\"p\",\"repoRoot\":\"$T/repo\",\"scratchDir\":\"/old\",\"pluginRoot\":\"$T/plugin\"}"
PLAN=(--plan p --repo-root "$T/repo")
summary() { printf '{"status":"%s","timestamp":"2026-01-01T00:00:00.000Z","script":%s,"args":%s}' "$2" "${3:-$SCRIPT}" "${4:-$ARGS}" > "$S/workflows/$1.json"; }
# A continuation launches with scratchDir alone, and its script's REPLAY record holds the plan args.
cont_summary() { python3 -c 'import json, sys; rec = {"args": json.loads(sys.argv[2]), "index": {}, "runner": {}, "child": {}, **({"from": sys.argv[3]} if len(sys.argv) > 3 else {})}; json.dump({"status": "killed", "timestamp": "2026-01-01T00:00:00.000Z", "script": "const x = 1\nconst REPLAY = " + json.dumps(rec) + "\nlet a = args\n", "args": {"scratchDir": "/new"}}, open(sys.argv[1], "w"))' "$S/workflows/$1.json" "${@:2}"; }
dir() { printf '%s' "$S/subagents/workflows/$1"; }
run() { OUT="$(python3 "$CP" "$@" 2>"$T/err")"; RC=$?; }
q() { printf '%s' "$OUT" | PYTHONIOENCODING=utf-8 python3 -c "import json, sys; d = json.load(sys.stdin); print($1)"; }
refused() { [ "$RC" -eq "$1" ] && [ ! -e "$T/out/copy.js" ] && grep -q "^refused: .*${2:-}" "$T/err"; }
echo "diff a" > "$T/slice-a.diff"; echo "diff b" > "$T/slice-b.diff"

{
  printf '{"type":"launched"}\n'
  started a1 plan:index Prep; result a1 '{"sha256":"one"}'
  started a2 implement:1 Implement; result a2 '{"changedPaths":["src/a.js","src/b.js"]}'
  started a3 diff:red-team 'Red team'; result a3 "{\"diffPath\":\"$T/slice-a.diff\",\"hash12\":\"aaaaaaaaaaaa\",\"empty\":false,\"paths\":[\"src/a.js\",\"src/b.js\",\"notes.md\"]}"
  started a4 review:code-reviewer '▸ review-mr'; result a4 '{"findings":[]}'
  started a5 verify:code-reviewer '▸ review-mr'; result a5 '{"reproduced":true}'
  started a6 fix:1 Fix; result a6 '{"changedPaths":["src/b.js","src/c.js"]}'
  started a7 diff:post-doc 'Doc pass'
} | journal wf_one
summary wf_one killed
{
  printf '{"type":"launched"}\n'
  started b1 plan:index Prep; result b1 '{"sha256":"two"}'
  started b2 diff:post-doc 'Doc pass'; result b2 "{\"diffPath\":\"$T/slice-b.diff\",\"hash12\":\"bbbbbbbbbbbb\",\"empty\":false,\"paths\":[\"src/a.js\",\"src/b.js\",\"src/c.js\"]}"
  started b3 remember:pass Remember
} | journal wf_two
# A continuation's own summary holds its replay copy, so --replay must read the script from the first run.
cont_summary wf_two "$ARGS"
{ started r1 plan:index Prep; result r1 '{"sha256":"r"}'; } | journal wf_noargs; summary wf_noargs killed '"const x = 1\nconst REPLAY = {\"runner\":{}}\nlet a = args\n"'

{ started c1 plan:index Prep; result c1 '{"sha256":"c"}'; } | journal wf_nosum
{ started d1 plan:index Prep; result d1 '{"sha256":"d"}'; } | journal wf_live; summary wf_live running
{ started e1 plan:index Prep; result e1 '{"sha256":"e"}'; } | journal wf_noline; summary wf_noline killed '"const x = 1\n"'
{ started f1 plan:index Prep; result f1 '{"sha256":"f"}'; started f2 implement:1 Implement; } | journal wf_writer; summary wf_writer killed
{ started m1 plan:index Prep; result m1 '{"sha256":"m"}'; started m2 fix:1 Fix; } | journal wf_fix; summary wf_fix killed
{ started n1 plan:index Prep; result n1 '{"sha256":"n"}'; started n2 fix:validation Fix; } | journal wf_fixval; summary wf_fixval killed
{ started o1 plan:index Prep; result o1 '{"sha256":"o"}'; started o2 doc:pass 'Doc pass'; } | journal wf_doc; summary wf_doc killed
{
  started p1 plan:index Prep; result p1 '{"sha256":"p"}'
  started p2 prep:baseline Prep; printf '{"type":"failed","agentId":"p2"}\n'
  started p3 implement:1 Implement; result p3 '{"changedPaths":["src/a.js"]}'
  started p4 fix:1 Fix; printf '{"type":"failed","agentId":"p4"}\n'
  started p5 verify:validation Validate
} | journal wf_failed; summary wf_failed killed
{ started g1 plan:index Prep; result g1 '{"sha256":"g"}'; started g2 diff:red-team 'Red team'; result g2 "{\"diffPath\":\"$T/missing.diff\",\"hash12\":\"cccccccccccc\",\"paths\":[]}"; } | journal wf_gone; summary wf_gone killed
started h1 plan:index Prep | journal wf_noindex; summary wf_noindex killed
mkdir -p "$S/subagents/workflows/wf_nojournal"
printf 'not json\n{"type":"launched"}\n' | journal wf_badjson
{ started t1 plan:index Prep; result t1 '{"sha256":"t"}'; started t2 implement:1 Implement; printf '{"type":"result","agentId":"t2","res'; } | journal wf_torn; summary wf_torn killed
{ started t1 plan:index Prep; result t1 '{"sha256":"t"}'; started t2 implement:1 Implement; printf '{"type":"result","agentId":"t2","res\n\n'; } | journal wf_tornnl
{ started t1 plan:index Prep; result t1 '{"sha256":"t"}'; printf '{"type":"started","agentId":"t2","label":"implement:1","phase":"Implem'; } | journal wf_tornstart; summary wf_tornstart killed
{ started t1 plan:index Prep; result t1 '{"sha256":"t"}'; started t2 prep:baseline Prep; printf '{"type":"result","agentId":"t2","res'; } | journal wf_tornres; summary wf_tornres killed
mkdir -p "$S/subagents/x" "$S/subagents/other/wf_x"
# The summary timestamp is 2026-01-01T00:00:00.000Z, cut to the millisecond, while a journal mtime keeps its fraction.
mtime_past_end() { python3 -c 'import os, sys; t = 1767225600 + float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$S/subagents/workflows/$1/journal.jsonl" "$2"; }
{ started k1 plan:index Prep; result k1 '{"sha256":"k"}'; } | journal wf_halfsec; summary wf_halfsec killed; mtime_past_end wf_halfsec 0.5
{ started l1 plan:index Prep; result l1 '{"sha256":"l"}'; } | journal wf_twosec; summary wf_twosec killed; mtime_past_end wf_twosec 2
{ started u1 plan:index Prep; printf '{"type":"result","agentId":"u1","res\n'; started u2 implement:1 Implement; } | journal wf_tornmid
{ started v1 plan:index Prep; result v1 '{"sha256":"v"}'; } | journal wf_behind; summary wf_behind killed; touch "$S/subagents/workflows/wf_behind/journal.jsonl"
{ started w1 plan:index Prep; result w1 '{"sha256":"w"}'; } | journal wf_notime; printf '{"status":"killed","script":%s,"args":%s}' "$SCRIPT" "$ARGS" > "$S/workflows/wf_notime.json"
{ started x1 plan:index Prep; result x1 '{"sha256":"x"}'; } | journal wf_noplugin; summary wf_noplugin killed "$SCRIPT" "{\"planName\":\"p\",\"repoRoot\":\"$T/repo\",\"pluginRoot\":\"$T/gone\"}"
{ started y1 plan:index Prep; result y1 '{"sha256":"y"}'; } | journal wf_novaultfs; summary wf_novaultfs killed "$SCRIPT" "{\"planName\":\"p\",\"repoRoot\":\"$T/repo\",\"pluginRoot\":\"$T/bare\"}"
O="$T/elsewhere/-tmp-repo/sess"; mkdir -p "$O/workflows" "$O/subagents/workflows/wf_out"
{ started z1 plan:index Prep; result z1 '{"sha256":"z"}'; } > "$O/subagents/workflows/wf_out/journal.jsonl"
printf '{"status":"killed","timestamp":"2099-01-01T00:00:00.000Z","script":%s,"args":%s}' "$SCRIPT" "$ARGS" > "$O/workflows/wf_out.json"
ln -s "$O/subagents/workflows/wf_out" "$S/subagents/workflows/wf_link"
# A continuation of a continuation: each newer journal holds only the stages its run called live.
{
  started c1 plan:index Prep; result c1 '{"sha256":"c1"}'
  started c2 prep:baseline Prep; result c2 '{"verify":{}}'
  started c3 implement:1 Implement; result c3 '{"changedPaths":["src/a.js"]}'
  started c4 implement:2 Implement
} | journal wf_chain1; summary wf_chain1 killed
{
  started d1 plan:index Prep; result d1 '{"sha256":"c2"}'
  started d2 implement:2 Implement; result d2 '{"changedPaths":["src/b.js"]}'
  started d3 review:code-reviewer '▸ review-mr'; result d3 '{"findings":[]}'
  started d4 verify:code-reviewer '▸ review-mr'
} | journal wf_chain2; cont_summary wf_chain2 "$ARGS"
{
  started e1 plan:index Prep; result e1 '{"sha256":"c3"}'
  started e2 verify:code-reviewer '▸ review-mr'; result e2 '{"reproduced":true}'
  started e3 implement:3 Implement; result e3 '{"changedPaths":["src/c.js"]}'
  started e4 cold:read 'Cold read'
} | journal wf_chain3; cont_summary wf_chain3 "$ARGS"
cp -Rp "$S/subagents/workflows/wf_chain3" "$S/subagents/workflows/wf_chainr"
cont_summary wf_chainr "{\"planName\":\"p\",\"repoRoot\":\"$T/plugin\"}"
{ started q1 plan:index Prep; result q1 '{"sha256":"q"}'; } | journal wf_otherplan; summary wf_otherplan killed "$SCRIPT" "{\"planName\":\"q\",\"repoRoot\":\"$T/repo\",\"pluginRoot\":\"$T/plugin\"}"
printf '{"type":"started","key":"k","agentId":"i1","phase":"Prep"}\n' | journal wf_nolabel
{ started j1 plan:index Prep; printf '{"type":"result","key":"k","agentId":"j1"}\n'; } | journal wf_noresult
# A run that blocked after its panel, with one failed reviewer, and recorded its tree in diff:blocked.
{
  started k1 plan:index Prep; result k1 '{"sha256":"k"}'
  started k2 implement:1 Implement; result k2 '{"changedPaths":["src/a.js"]}'
  started k3 diff:red-team 'Red team'; result k3 "{\"diffPath\":\"$T/slice-a.diff\",\"hash12\":\"aaaaaaaaaaaa\",\"empty\":false,\"paths\":[\"src/a.js\"]}"
  started k4 review:code-reviewer '▸ review-mr'; result k4 '{"findings":[]}'
  started k5 review:security '▸ review-mr'; printf '{"type":"failed","agentId":"k5"}\n'
  started k6 verify:security '▸ review-mr'; result k6 '{"reproduced":true}'
  started k7 fix:1 Fix; result k7 '{"changedPaths":["src/b.js"]}'
  started k8 remember:pass Remember; result k8 '{"facts":[]}'
  started k9 diff:blocked Finish; result k9 "{\"diffPath\":\"$T/slice-b.diff\",\"hash12\":\"dddddddddddd\",\"empty\":false,\"paths\":[\"src/a.js\",\"src/b.js\"]}"
} | journal wf_blocked; summary wf_blocked completed
{ started l1 plan:index Prep; result l1 '{"sha256":"l"}'; started l2 fix:1 Fix; result l2 '{"changedPaths":[]}'; } | journal wf_noblock; summary wf_noblock completed
# A journal resume of wf_blocked from fix:1 that ran fix:1 live, then blocked at remember:pass with its own tree.
{
  started r1 plan:index Prep; result r1 '{"sha256":"r"}'
  started r2 fix:1 Fix; result r2 '{"changedPaths":["src/c.js"]}'
  started r3 remember:pass Remember; result r3 '{"facts":[]}'
  started r4 diff:blocked Finish; result r4 "{\"diffPath\":\"$T/slice-b.diff\",\"hash12\":\"eeeeeeeeeeee\",\"empty\":false,\"paths\":[\"src/a.js\",\"src/c.js\"]}"
} | journal wf_resumed; cont_summary wf_resumed "$ARGS" fix:1
labels() { q '[s["label"] for s in d["stages"]]'; }
copied() { python3 -c '
import json, sys
line = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("const REPLAY = ")][0]
r = json.loads(line[len("const REPLAY = "):])
print(sorted(r["runner"]), sorted(r["child"]))' "$T/out/copy.js" 2>&1; }

run "$(dir wf_one)"
[ "$(q 'd["done"]')" = "6" ] && ok "counts every stage with a result as done" || no "done count (rc=$RC): $(q 'd["done"]')"
[ "$(q 'd["open"]')" = "['diff:post-doc']" ] && ok "lists a started stage with no result as open" || no "open list: $(q 'd["open"]')"
[ "$(q '[s["phase"] for s in d["stages"] if s["label"] == "review:code-reviewer"]')" = "['▸ review-mr']" ] && ok "keeps the child phase on a review-mr stage" || no "child phase: $OUT"
[ "$(q 'd["changedPaths"]')" = "['src/a.js', 'src/b.js', 'src/c.js']" ] && ok "unions the implementer and fix changedPaths in first-seen order" || no "changedPaths: $(q 'd["changedPaths"]')"

run "$(dir wf_one)" "$(dir wf_two)"
[ "$(q '(d["capture"]["label"], d["capture"]["hash12"], d["capture"]["paths"])')" = "('diff:post-doc', 'bbbbbbbbbbbb', ['src/a.js', 'src/b.js', 'src/c.js'])" ] && ok "reports the newest done capture and its paths" || no "capture: $(q 'd["capture"]')"

run "$(dir wf_one)" "$(dir wf_nosum)"
[ "$(q '[r["status"] for r in d["runs"]]')" = "['killed', None]" ] && ok "reports each run's summary status, and none for a run with no summary" || no "runs: $(q 'd["runs"]')"

before="$(find "$T" -type f | wc -l)"; run "$(dir wf_one)" "$(dir wf_two)"
{ [ "$(find "$T" -type f | wc -l)" = "$before" ] && [ "$(q 'd["replay"]')" = "None" ]; } && ok "writes no replay copy without --replay" || no "file count or replay field changed: $(q 'd["replay"]')"

[ "$(q '(d["done"], d["open"])')" = "(8, ['remember:pass'])" ] && ok "drops an older run's open stage and keeps the newest run's" || no "two runs: $(q '(d["done"], d["open"])')"

run "$(dir wf_one)" "$(dir wf_two)" --replay "$T/out/copy.js" "${PLAN[@]}"
python3 -c 'import json, sys; sys.stdout.write(json.load(open(sys.argv[1]))["script"])' "$S/workflows/wf_one.json" > "$T/recorded.js"
{ [ "$(diff "$T/recorded.js" "$T/out/copy.js" | grep -c '^[<>]')" = "2" ] && [ "$(diff "$T/recorded.js" "$T/out/copy.js" | grep -c '^> const REPLAY = {')" = "1" ]; } \
  && ok "--replay changes only the REPLAY line of the recorded script" || no "replay diff (rc=$RC): $(diff "$T/recorded.js" "$T/out/copy.js" | head -5)"

rec="$(python3 -c '
import json, sys
line = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("const REPLAY = ")][0]
r = json.loads(line[len("const REPLAY = "):])
print(r["args"], r["index"], sorted(r["runner"]), sorted(r["child"]))' "$T/out/copy.js")"
[ "$rec" = "{'planName': 'p', 'repoRoot': '$T/repo', 'scratchDir': '/old', 'pluginRoot': '$T/plugin'} {'sha256': 'two'} ['diff:post-doc', 'diff:red-team', 'fix:1', 'implement:1'] ['review:code-reviewer', 'verify:code-reviewer']" ] \
  && ok "--replay puts the args, plan:index, runner labels and child labels in their places" || no "replay record: $rec"

{ [ "$(q 'd["replay"]["sha256"]')" = "$(shasum -a 256 "$T/out/copy.js" | cut -c1-12)" ] && [ "$(q '(d["replay"]["runnerResults"], d["replay"]["childResults"])')" = "(4, 2)" ]; } \
  && ok "--replay prints the copy's sha256 prefix and its result counts" || no "replay summary: $(q 'd["replay"]')"
rm -f "$T/out/copy.js"

run "$(dir wf_nosum)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 3 && ok "--replay exits 3 for a run with no summary" || no "no summary (rc=$RC): $(cat "$T/err")"
run "$(dir wf_live)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 3 && ok "--replay exits 3 for a run whose status is running" || no "running (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noline)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 && ok "--replay refuses a recorded script with no REPLAY null line" || no "no REPLAY line (rc=$RC): $(cat "$T/err")"
run "$(dir wf_writer)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'writer stage implement:1' && ok "--replay refuses a run that died inside implement:1" || no "writer stage implement:1 (rc=$RC): $(cat "$T/err")"
run "$(dir wf_fix)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'writer stage fix:1' && ok "--replay refuses a run that died inside fix:1" || no "writer stage fix:1 (rc=$RC): $(cat "$T/err")"
run "$(dir wf_fixval)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'writer stage fix:validation' && ok "--replay refuses a run that died inside fix:validation" || no "writer stage fix:validation (rc=$RC): $(cat "$T/err")"
run "$(dir wf_doc)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'writer stage doc:pass' && ok "--replay refuses a run that died inside doc:pass" || no "writer stage doc:pass (rc=$RC): $(cat "$T/err")"
run "$(dir wf_failed)" --replay "$T/out/copy.js" "${PLAN[@]}"
rec="$(python3 -c '
import json, sys
line = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("const REPLAY = ")][0]
print(json.loads(line[len("const REPLAY = "):])["runner"])' "$T/out/copy.js" 2>&1)"
[ "$RC.$rec" = "0.{'prep:baseline': [None], 'implement:1': [{'changedPaths': ['src/a.js']}], 'fix:1': [None]}" ] \
  && ok "--replay records a failed stage's result as null and continues past it" || no "failed stage (rc=$RC): $rec $(cat "$T/err")"
rm -f "$T/out/copy.js"
run "$(dir wf_gone)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 && ok "--replay refuses when a recorded capture's diff file is gone" || no "diff gone (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noindex)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 && ok "--replay refuses when no run recorded a plan:index result" || no "no plan:index (rc=$RC): $(cat "$T/err")"
run "$(dir wf_behind)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 3 'journal written after' && ok "--replay exits 3 for a run whose journal changed after its summary's timestamp" || no "journal after summary (rc=$RC): $(cat "$T/err")"
run "$(dir wf_notime)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 3 && ok "--replay exits 3 for a run whose summary has no timestamp" || no "no timestamp (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noplugin)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'pluginRoot' && ok "--replay refuses when the recorded pluginRoot is gone" || no "pluginRoot gone (rc=$RC): $(cat "$T/err")"
run "$(dir wf_novaultfs)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'pluginRoot' && ok "--replay refuses when the recorded pluginRoot has no scripts/vault-fs.sh" || no "vault-fs.sh gone (rc=$RC): $(cat "$T/err")"

run "$(dir wf_halfsec)" --replay "$T/out/copy.js" "${PLAN[@]}"
[ "$RC" -eq 0 ] && [ -f "$T/out/copy.js" ] && ok "--replay reads a journal written 0.5 s after its summary's timestamp as ended" || no "half second (rc=$RC): $(cat "$T/err")"
rm -f "$T/out/copy.js"
run "$(dir wf_twosec)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 3 'journal written after' && ok "--replay exits 3 for a journal written 2 s after its summary's timestamp" || no "two seconds (rc=$RC): $(cat "$T/err")"
run "$(dir wf_one)" "$(dir wf_two)" --replay "$T/out/copy.js" --plan other --repo-root "$T/repo"
refused 1 'planName' && ok "--replay refuses a run recorded for another planName" || no "planName mismatch (rc=$RC): $(cat "$T/err")"
run "$(dir wf_one)" "$(dir wf_two)" --replay "$T/out/copy.js" --plan p --repo-root "$T/plugin"
refused 1 'repoRoot' && ok "--replay refuses a run recorded for another repoRoot" || no "repoRoot mismatch (rc=$RC): $(cat "$T/err")"
run "$(dir wf_one)" "$(dir wf_two)" --replay "$T/out/copy.js"
[ "$RC" -eq 2 ] && [ ! -e "$T/out/copy.js" ] && ok "--replay without --plan and --repo-root exits 2" || no "missing --plan (rc=$RC): $(cat "$T/err")"

run "$(dir wf_chain1)" "$(dir wf_chain2)" "$(dir wf_chain3)" --replay "$T/out/copy.js" "${PLAN[@]}"
python3 -c 'import json, sys; sys.stdout.write(json.load(open(sys.argv[1]))["script"])' "$S/workflows/wf_chain1.json" > "$T/recorded.js"
{ [ "$RC" -eq 0 ] && [ "$(diff "$T/recorded.js" "$T/out/copy.js" | grep -c '^[<>]')" = "2" ]; } \
  && ok "a chained continuation copies the first run's script though a newer summary holds a REPLAY record" || no "chained copy (rc=$RC): $(cat "$T/err") $(diff "$T/recorded.js" "$T/out/copy.js" | head -5)"
[ "$(q '(d["replay"]["runnerResults"], d["replay"]["childResults"])')" = "(4, 2)" ] \
  && ok "a chained continuation counts the recorded results of every run folder" || no "chained counts: $(q 'd["replay"]')"
[ "$(q 'd["open"]')" = "['cold:read']" ] && ok "a chained continuation drops the older runs' open stages and keeps the newest run's" || no "chained open: $(q 'd["open"]')"
rm -f "$T/out/copy.js"
run "$(dir wf_one)" "$(dir wf_otherplan)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'wf_otherplan recorded planName' && ok "--replay refuses a later run folder that another plan recorded" || no "later folder of another plan (rc=$RC): $(cat "$T/err")"
run "$(dir wf_one)" "$(dir wf_noargs)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'wf_noargs has no recorded args' && ok "--replay refuses a continuation whose REPLAY record holds no args" || no "REPLAY record without args (rc=$RC): $(cat "$T/err")"
run "$(dir wf_chain1)" "$(dir wf_chain2)" "$(dir wf_chainr)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'wf_chainr recorded repoRoot' && ok "--replay refuses a later continuation whose REPLAY record names another repoRoot" || no "later folder of another repo (rc=$RC): $(cat "$T/err")"
rm -f "$T/out/copy.js"

run "$(dir wf_nojournal)"
refused 2 && ok "a folder with no journal exits 2" || no "no journal (rc=$RC): $(cat "$T/err")"
run "$(dir wf_badjson)"
refused 2 && ok "a journal line that is not JSON before the last line exits 2" || no "bad JSON (rc=$RC): $(cat "$T/err")"
run "$(dir wf_tornmid)"
refused 2 && ok "a torn result line followed by another entry exits 2" || no "torn middle line (rc=$RC): $(cat "$T/err")"
run "$(dir wf_tornnl)"
[ "$RC.$(q '(d["done"], d["open"])')" = "0.(1, ['implement:1'])" ] && ok "a torn line followed by blank lines is the last line and is ignored" || no "torn line before blank lines (rc=$RC): $(cat "$T/err") $OUT"
run "$(dir wf_tornstart)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'torn line' && ok "--replay refuses a journal whose torn last line is a started entry for a writer stage" || no "torn started line (rc=$RC): $(cat "$T/err")"
run "$(dir wf_torn)" --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'writer stage implement:1' && ok "--replay leaves a torn result line's stage open, so a writer stage still refuses" || no "torn result of a writer (rc=$RC): $(cat "$T/err")"
run "$(dir wf_tornres)" --replay "$T/out/copy.js" "${PLAN[@]}"
[ "$RC" -eq 0 ] && [ -f "$T/out/copy.js" ] && ok "--replay continues past a torn result line of a stage that edits nothing" || no "torn result of a reader (rc=$RC): $(cat "$T/err")"
rm -f "$T/out/copy.js"
run "$S"
refused 1 'not a run folder' && ok "a session folder is refused as a run folder" || no "session folder (rc=$RC): $(cat "$T/err")"
run "$S/subagents/x"
refused 1 'not a run folder' && ok "a folder one level short of the run folder layout is refused" || no "short folder (rc=$RC): $(cat "$T/err")"
run "$S/subagents/other/wf_x"
refused 1 'not a run folder' && ok "a folder of the right depth outside subagents/workflows is refused" || no "wrong middle (rc=$RC): $(cat "$T/err")"
run --replay "$T/out/copy.js" "${PLAN[@]}" -- -h
refused 1 'not an absolute run folder' && ok "a folder argument of -h after -- is refused, not read as help" || no "-h folder (rc=$RC): $(cat "$T/err") $OUT"
run "$(dir wf_torn)"
[ "$RC.$(q '(d["done"], d["open"])')" = "0.(1, ['implement:1'])" ] && ok "a torn last journal line is ignored and its stage stays open" || no "torn last line (rc=$RC): $(cat "$T/err") $OUT"
run "$O/subagents/workflows/wf_out"
refused 1 'not a run folder' && ok "a run folder outside ~/.claude/projects is refused" || no "outside folder (rc=$RC): $(cat "$T/err")"
run "$(dir wf_link)"
refused 1 'not a run folder' && ok "a symlinked run folder that resolves outside ~/.claude/projects is refused" || no "symlinked folder (rc=$RC): $(cat "$T/err")"
run "$(dir wf_nolabel)"
refused 2 && ok "a started entry with no label exits 2" || no "no label (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noresult)"
refused 2 && ok "a result entry with no result exits 2" || no "no result (rc=$RC): $(cat "$T/err")"

B="$(dir wf_blocked)"
run "$B" --from remember:pass
[ "$(labels)" = "['plan:index', 'implement:1', 'diff:red-team', 'review:code-reviewer', 'review:security', 'verify:security', 'fix:1']" ] \
  && ok "--from a runner label keeps every earlier runner and child stage and drops the label's own" || no "cut at remember:pass (rc=$RC): $(labels) $(cat "$T/err")"
[ "$(q '(d["from"], d["replay"])')" = "('remember:pass', None)" ] && ok "--from without --replay prints the cut checkpoint and writes no copy" || no "cut checkpoint: $(q '(d["from"], d["replay"])')"
[ "$(q 'd["blockedTree"]')" = "dddddddddddd" ] && ok "the checkpoint reports the newest run's diff:blocked hash as blockedTree" || no "blockedTree: $(q 'd["blockedTree"]')"
run "$B" --from review
[ "$(labels)" = "['plan:index', 'implement:1', 'diff:red-team', 'review:code-reviewer', 'verify:security']" ] \
  && ok "--from review drops a failed reviewer and every later runner stage and keeps the other child results" || no "cut at review (rc=$RC): $(labels) $(cat "$T/err")"
run "$B" --from review:verify:security
[ "$(labels)" = "['plan:index', 'implement:1', 'diff:red-team', 'review:code-reviewer']" ] \
  && ok "--from review:<child label> also drops that child label's recorded result" || no "cut at review:verify:security (rc=$RC): $(labels) $(cat "$T/err")"
run "$B" --from diff:red-team
[ "$RC.$(q 'd["capture"]')" = "0.None" ] && ok "a cut at the first capture leaves the capture null" || no "cut before capture (rc=$RC): $(q 'd["capture"]')"
run "$B" --from fix:1
[ "$(q 'd["capture"]["label"]')" = "diff:red-team" ] && ok "a cut after a capture keeps that capture" || no "cut after capture (rc=$RC): $(q 'd["capture"]')"
run "$B" --from plan:index
[ "$RC" -eq 1 ] && grep -q '^refused: no recorded stage plan:index to resume from' "$T/err" && ok "--from plan:index exits 1" || no "cut at plan:index (rc=$RC): $(cat "$T/err")"
run "$B" --from cold:read
[ "$RC" -eq 1 ] && grep -q '^refused: no recorded stage cold:read to resume from' "$T/err" && ok "--from a label with no recorded stage exits 1" || no "unknown label (rc=$RC): $(cat "$T/err")"
run "$B" --from 'Fix:1'
[ "$RC" -eq 2 ] && ok "--from a malformed label exits 2" || no "bad label (rc=$RC): $(cat "$T/err")"
run "$B" --from review --tree-hash dddddddddddd --replay "$T/out/copy.js" "${PLAN[@]}"
[ "$RC" -eq 0 ] && [ -f "$T/out/copy.js" ] && ok "--replay with --from and the recorded --tree-hash writes the copy" || no "replay with tree hash (rc=$RC): $(cat "$T/err")"
[ "$(copied)" = "['diff:red-team', 'implement:1'] ['review:code-reviewer', 'verify:security']" ] \
  && ok "a copy written with --from holds no result for the cut stages and none for diff:blocked" || no "cut copy record: $(copied)"
rm -f "$T/out/copy.js"
run "$B" --from review --tree-hash eeeeeeeeeeee --replay "$T/out/copy.js" "${PLAN[@]}"
refused 1 'the tree hash is eeeeeeeeeeee, not the dddddddddddd' && ok "--tree-hash that differs from the recorded blocked tree exits 1 with no copy" || no "tree hash mismatch (rc=$RC): $(cat "$T/err")"
run "$B" "$(dir wf_noblock)" --from fix:1 --tree-hash dddddddddddd
refused 1 'wf_noblock recorded no blocked tree' && ok "--tree-hash exits 1 when the newest run recorded no diff:blocked capture" || no "no blocked tree (rc=$RC): $(cat "$T/err")"
run "$B" --from review --replay "$T/out/copy.js" "${PLAN[@]}"
[ "$RC" -eq 2 ] && [ ! -e "$T/out/copy.js" ] && ok "--replay with --from and no --tree-hash exits 2" || no "missing tree hash (rc=$RC): $(cat "$T/err")"
run "$B" --from review --tree-hash DDDDDDDDDDDD --replay "$T/out/copy.js" "${PLAN[@]}"
[ "$RC" -eq 2 ] && [ ! -e "$T/out/copy.js" ] && ok "a malformed --tree-hash exits 2" || no "bad tree hash (rc=$RC): $(cat "$T/err")"

run "$B" --from review:code-reviewer
[ "$(labels)" = "['plan:index', 'implement:1', 'diff:red-team', 'verify:security']" ] \
  && ok "--from review:<reviewer label> as the checkpoint prints it drops that reviewer's result" || no "cut at review:code-reviewer (rc=$RC): $(labels) $(cat "$T/err")"
run "$B" --from fix:1 --tree-hash dddddddddddd --replay "$T/out/copy.js" "${PLAN[@]}"
rec="$(python3 -c '
import json, sys
line = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("const REPLAY = ")][0]
print(json.loads(line[len("const REPLAY = "):]).get("from"))' "$T/out/copy.js" 2>&1)"
[ "$RC.$rec" = "0.fix:1" ] && ok "a copy written with --from records the cut label in its REPLAY record" || no "copy from label (rc=$RC): $rec $(cat "$T/err")"
rm -f "$T/out/copy.js"
run "$B" "$(dir wf_resumed)" --from remember:pass --tree-hash eeeeeeeeeeee
[ "$(q '[s["run"] + " " + s["label"] for s in d["stages"] if s["phase"] != "▸ review-mr"]')" = "['wf_blocked plan:index', 'wf_blocked implement:1', 'wf_blocked diff:red-team', 'wf_resumed plan:index', 'wf_resumed fix:1']" ] \
  && ok "a second resume drops the stages the first resume cut and ran live, so the older blocked result never replays" || no "second resume (rc=$RC): $(labels) $(cat "$T/err")"

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
