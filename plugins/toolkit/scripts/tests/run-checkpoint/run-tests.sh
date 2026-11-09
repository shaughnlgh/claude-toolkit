#!/usr/bin/env bash
# Hermetic behavior suite for run-checkpoint.py. Lays out synthetic run folders as <session>/subagents/workflows/<runId>
# with their summaries at <session>/workflows/<runId>.json, the way the Workflow runtime does. No network, no claude binary.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP="$HERE/../../run-checkpoint.py"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d -t run-checkpoint.XXXXXX)"
trap 'rm -rf "$T"' EXIT
S="$T/sess"; mkdir -p "$S/workflows"

started() { printf '{"type":"started","key":"k-%s","agentId":"%s","label":"%s","phase":"%s"}\n' "$1" "$1" "$2" "$3"; }
result() { printf '{"type":"result","key":"k-%s","agentId":"%s","result":%s,"toolsUsed":[]}\n' "$1" "$1" "$2"; }
journal() { mkdir -p "$S/subagents/workflows/$1"; cat > "$S/subagents/workflows/$1/journal.jsonl"; }
SCRIPT='"const x = 1\nconst REPLAY = null\nlet a = args\n"'
ARGS='{"planName":"p","scratchDir":"/old"}'
summary() { printf '{"status":"%s","script":%s,"args":%s}' "$2" "${3:-$SCRIPT}" "$ARGS" > "$S/workflows/$1.json"; }
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
summary wf_two killed '"const x = 1\nconst REPLAY = {}\nlet a = args\n"'

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
printf 'not json\n' | journal wf_badjson
printf '{"type":"started","key":"k","agentId":"i1","phase":"Prep"}\n' | journal wf_nolabel
{ started j1 plan:index Prep; printf '{"type":"result","key":"k","agentId":"j1"}\n'; } | journal wf_noresult

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

run "$(dir wf_one)" "$(dir wf_two)" --replay "$T/out/copy.js"
python3 -c 'import json, sys; sys.stdout.write(json.load(open(sys.argv[1]))["script"])' "$S/workflows/wf_one.json" > "$T/recorded.js"
{ [ "$(diff "$T/recorded.js" "$T/out/copy.js" | grep -c '^[<>]')" = "2" ] && [ "$(diff "$T/recorded.js" "$T/out/copy.js" | grep -c '^> const REPLAY = {')" = "1" ]; } \
  && ok "--replay changes only the REPLAY line of the recorded script" || no "replay diff (rc=$RC): $(diff "$T/recorded.js" "$T/out/copy.js" | head -5)"

rec="$(python3 -c '
import json, sys
line = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("const REPLAY = ")][0]
r = json.loads(line[len("const REPLAY = "):])
print(r["args"], r["index"], sorted(r["runner"]), sorted(r["child"]))' "$T/out/copy.js")"
[ "$rec" = "{'planName': 'p', 'scratchDir': '/old'} {'sha256': 'two'} ['diff:post-doc', 'diff:red-team', 'fix:1', 'implement:1'] ['review:code-reviewer', 'verify:code-reviewer']" ] \
  && ok "--replay puts the args, plan:index, runner labels and child labels in their places" || no "replay record: $rec"

{ [ "$(q 'd["replay"]["sha256"]')" = "$(shasum -a 256 "$T/out/copy.js" | cut -c1-12)" ] && [ "$(q '(d["replay"]["runnerResults"], d["replay"]["childResults"])')" = "(4, 2)" ]; } \
  && ok "--replay prints the copy's sha256 prefix and its result counts" || no "replay summary: $(q 'd["replay"]')"
rm -f "$T/out/copy.js"

run "$(dir wf_nosum)" --replay "$T/out/copy.js"
refused 3 && ok "--replay exits 3 for a run with no summary" || no "no summary (rc=$RC): $(cat "$T/err")"
run "$(dir wf_live)" --replay "$T/out/copy.js"
refused 3 && ok "--replay exits 3 for a run whose status is running" || no "running (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noline)" --replay "$T/out/copy.js"
refused 1 && ok "--replay refuses a recorded script with no REPLAY null line" || no "no REPLAY line (rc=$RC): $(cat "$T/err")"
run "$(dir wf_writer)" --replay "$T/out/copy.js"
refused 1 'writer stage implement:1' && ok "--replay refuses a run that died inside implement:1" || no "writer stage implement:1 (rc=$RC): $(cat "$T/err")"
run "$(dir wf_fix)" --replay "$T/out/copy.js"
refused 1 'writer stage fix:1' && ok "--replay refuses a run that died inside fix:1" || no "writer stage fix:1 (rc=$RC): $(cat "$T/err")"
run "$(dir wf_fixval)" --replay "$T/out/copy.js"
refused 1 'writer stage fix:validation' && ok "--replay refuses a run that died inside fix:validation" || no "writer stage fix:validation (rc=$RC): $(cat "$T/err")"
run "$(dir wf_doc)" --replay "$T/out/copy.js"
refused 1 'writer stage doc:pass' && ok "--replay refuses a run that died inside doc:pass" || no "writer stage doc:pass (rc=$RC): $(cat "$T/err")"
run "$(dir wf_failed)" --replay "$T/out/copy.js"
rec="$(python3 -c '
import json, sys
line = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("const REPLAY = ")][0]
print(json.loads(line[len("const REPLAY = "):])["runner"])' "$T/out/copy.js" 2>&1)"
[ "$RC.$rec" = "0.{'prep:baseline': [None], 'implement:1': [{'changedPaths': ['src/a.js']}], 'fix:1': [None]}" ] \
  && ok "--replay records a failed stage's result as null and continues past it" || no "failed stage (rc=$RC): $rec $(cat "$T/err")"
rm -f "$T/out/copy.js"
run "$(dir wf_gone)" --replay "$T/out/copy.js"
refused 1 && ok "--replay refuses when a recorded capture's diff file is gone" || no "diff gone (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noindex)" --replay "$T/out/copy.js"
refused 1 && ok "--replay refuses when no run recorded a plan:index result" || no "no plan:index (rc=$RC): $(cat "$T/err")"

run "$(dir wf_nojournal)"
refused 2 && ok "a folder with no journal exits 2" || no "no journal (rc=$RC): $(cat "$T/err")"
run "$(dir wf_badjson)"
refused 2 && ok "a journal line that is not JSON exits 2" || no "bad JSON (rc=$RC): $(cat "$T/err")"
run "$(dir wf_nolabel)"
refused 2 && ok "a started entry with no label exits 2" || no "no label (rc=$RC): $(cat "$T/err")"
run "$(dir wf_noresult)"
refused 2 && ok "a result entry with no result exits 2" || no "no result (rc=$RC): $(cat "$T/err")"

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
