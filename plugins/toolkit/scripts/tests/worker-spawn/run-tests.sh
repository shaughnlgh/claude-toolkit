#!/usr/bin/env bash
# Hermetic behavior suite for worker-spawn.sh. A stub claude first on PATH answers --help,
# agents --json --all from a per-call output list, and a spawn call whose argv, working
# directory and prompt it records per case. HOME points at the temp dir. No network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="$(cd "$HERE/../../.." && pwd -P)"
SPAWN="$TOOLKIT/scripts/worker-spawn.sh"
PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

T="$(cd "$(mktemp -d -t wspawn.XXXXXX)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME" "$T/bin" "$T/repo" "$T/notes"
unset TOOLKIT_AGENTS_FILE
SP="$T/sessions/lead-sid-1/scratchpad"; mkdir -p "$SP"

# The stub answers agents.<n> before agents for the n-th agents call, and out/rc for a spawn.
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$CASE/calls"
if [ "$1" = --help ]; then
  echo "  -n, --name <name>   Set a display name"
  [ -e "$CASE/nobg" ] || echo "  --bg, --background   Start the session in the background"
  exit 0
fi
if [ "$1" = agents ]; then
  n=$(( $(cat "$CASE/.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CASE/.n"
  if [ -e "$CASE/agents.$n" ]; then cat "$CASE/agents.$n"; elif [ -e "$CASE/agents" ]; then cat "$CASE/agents"; else echo '[]'; fi
  exit 0
fi
printf '%s\n' "$@" > "$CASE/argv"
printf '%s' "${@: -1}" > "$CASE/prompt"
pwd -P > "$CASE/pwd"
name=""; prev=""; for a in "$@"; do [ "$prev" = -n ] && name=$a; prev=$a; done
if [ -e "$CASE/out" ]; then cat "$CASE/out"; else echo "backgrounded · a1b2c3d4 · $name"; fi
exit "$(cat "$CASE/rc" 2>/dev/null || echo 0)"
STUB
chmod +x "$T/bin/claude"
export PATH="$T/bin:$PATH"

ago() { local e=$(( $(date +%s) - $1 )); date -r "$e" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$e" +%Y%m%d%H%M.%S; }
NOTE="$T/notes/plan - proj-12.md"
printf -- '---\nstatus: approved\nceiling: mr\nnits: fix\nsession_model: opus\nsession_effort: high\n---\n\n## Objective\n' > "$NOTE"
mkdir -p "$T/bare"; BARE="$T/bare/plan - proj-12.md"
printf -- '---\nstatus: approved\n---\n' > "$BARE"
TASK="$T/task.txt"; printf 'Build the widget & ship it\n' > "$TASK"
N=0
case_() {  # $1 the recorded mode, or - for no record
  N=$((N + 1)); export CASE="$T/case.$N"; mkdir -p "$CASE"
  rm -f "$SP/workers" "$SP/worker-spawn-mode"
  touch -t "$(ago 180)" "$TASK"
  [ "${1:-auto}" = - ] || { printf 'permission_mode: %s\n' "${1:-auto}" > "$SP/worker-spawn-mode"; touch -t "$(ago 120)" "$SP/worker-spawn-mode"; }
}
BASE=(--scratchpad "$SP" --type execute --key proj-12 --plan proj-12 --note "$NOTE" --lead-name lead-proj --model opus --effort high --task-file "$TASK" --cwd "$T/repo")
run() { OUT="$(bash "$SPAWN" "$@" 2>"$CASE/err")"; RC=$?; ERR="$(cat "$CASE/err")"; }
calls() { cat "$CASE/calls" 2>/dev/null; }
argv_has() { grep -qxF -- "$1" "$CASE/argv" 2>/dev/null; }
argv_pair() { grep -A1 -xF -- "$1" "$CASE/argv" 2>/dev/null | sed -n 2p; }
no_stub() { [ ! -e "$CASE/calls" ]; }
no_spawn() { [ ! -e "$CASE/argv" ]; }

case_; run "${BASE[@]}"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "STARTED a1b2c3d4 worker-execute-proj-12" ]; } && ok "clean spawn prints STARTED with id and name" || no "clean spawn (rc=$RC): $OUT $ERR"
awk -F'\t' 'NF == 5 && $1 == "a1b2c3d4" && $2 == "worker-execute-proj-12" && $3 == "execute" && $4 == "proj-12" && $5 ~ /^[0-9]+$/' "$SP/workers" | grep -q . \
  && [ "$(wc -l < "$SP/workers" | tr -d ' ')" -eq 1 ] && ok "workers line holds id, name, type, plan and epoch" || no "workers line: $(cat "$SP/workers" 2>&1)"
{ argv_has --bg && [ "$(argv_pair -n)" = worker-execute-proj-12 ] && [ "$(argv_pair --permission-mode)" = auto ] \
  && [ "$(argv_pair --model)" = opus ] && [ "$(argv_pair --effort)" = high ]; } && ok "argv carries --bg, -n, mode, --model and --effort" || no "argv: $(cat "$CASE/argv")"
! argv_has -w && ok "no -w without --worktree" || no "-w passed without --worktree"
[ "$(cat "$CASE/pwd")" = "$T/repo" ] && ok "the spawn runs in --cwd" || no "spawn pwd: $(cat "$CASE/pwd")"
[ "$(argv_pair --plugin-dir)" = "$TOOLKIT" ] && ok "run from the repo passes --plugin-dir" || no "plugin-dir: $(argv_pair --plugin-dir)"
grep -qF "Run options recorded for this task: ceiling: mr, nits: fix, session_model: opus, session_effort: high. " "$CASE/prompt" && ok "execute prompt holds every run option the note records" || no "run options line: $(grep '^Run options' "$CASE/prompt")"
grep -qF 'Build the widget & ship it' "$CASE/prompt" && ok "an & in the task text stays literal" || no "task text: $(grep '^Task' "$CASE/prompt")"

case_; run "${BASE[@]}" --worktree proj-12
[ "$(argv_pair -w)" = proj-12 ] && ok "--worktree passes -w <name>" || no "-w: $(cat "$CASE/argv")"

case_; printf 'Starting background service…\nbackgrounded · a1b2c3d4 · worker-execute-proj-12\n' > "$CASE/out"; run "${BASE[@]}"
[ "$OUT" = "STARTED a1b2c3d4 worker-execute-proj-12" ] && ok "id read below a Starting background service line" || no "service line (rc=$RC): $OUT"

for drop in --model --effort; do
  case_; A=(); skip=""
  for a in "${BASE[@]}"; do if [ -n "$skip" ]; then skip=""; elif [ "$a" = "$drop" ]; then skip=1; else A+=("$a"); fi; done
  run "${A[@]}"
  { [ "$RC" -eq 2 ] && no_stub; } && ok "a missing $drop exits 2 with no stub call" || no "missing $drop (rc=$RC): $OUT $ERR"
done
for m in inherit haiku claude-haiku-4-5 -p; do
  case_; run "${BASE[@]}" --model "$m"
  { [ "$RC" -eq 2 ] && no_stub; } && ok "--model $m exits 2 with no stub call" || no "--model $m (rc=$RC): $ERR"
done
case_; run "${BASE[@]}" --effort inherit
{ [ "$RC" -eq 2 ] && no_stub; } && ok "--effort inherit exits 2 with no stub call" || no "--effort inherit (rc=$RC): $ERR"
case_; run "${BASE[@]}" --model 'claude-opus-4-7[1m]'
[ "$(argv_pair --model)" = 'claude-opus-4-7[1m]' ] && ok "a model with the [1m] suffix spawns" || no "[1m] model (rc=$RC): $ERR"
case_; run "${BASE[@]}" --plan -
{ [ "$RC" -eq 2 ] && no_stub; } && ok "an execute worker with --plan - exits 2 with no stub call" || no "execute plan - (rc=$RC): $ERR"
case_; OUT="$(cd "$T" && bash "$SPAWN" "${BASE[@]}" --note "notes/plan - proj-12.md" 2>"$CASE/err")"; RC=$?
grep -qxF "Plan note: $NOTE" "$CASE/prompt" && ok "a relative --note reaches the prompt as an absolute path" || no "relative note (rc=$RC): $(grep '^Plan note' "$CASE/prompt" 2>&1) $(cat "$CASE/err")"
QUOTED="$T/quoted/plan - proj-12.md"; mkdir -p "$T/quoted"
printf -- '---\r\nstatus: approved\r\nceiling: "merge" \r\nsession_model: opus\r\n---\r\n' > "$QUOTED"
case_; run "${BASE[@]}" --note "$QUOTED"
{ [ "$RC" -eq 0 ] && grep -qF "Run options recorded for this task: ceiling: merge, session_model: opus. " "$CASE/prompt"; } \
  && ok "a quoted ceiling with trailing space in a CRLF note reads as validate-plan reads it" || no "quoted ceiling (rc=$RC): $ERR $(grep '^Run options' "$CASE/prompt" 2>&1)"

case_ default; run "${BASE[@]}"
[ "$(argv_pair --permission-mode)" = manual ] && ok "a default record spawns with --permission-mode manual" || no "default mode: $(argv_pair --permission-mode) rc=$RC"

case_ -; run "${BASE[@]}"
{ [ "$RC" -eq 13 ] && [ "$OUT" = NOMODE ] && no_spawn; } && ok "no mode record gives NOMODE and no spawn" || no "no record (rc=$RC): $OUT"
case_; touch -t "$(ago 240)" "$SP/worker-spawn-mode"; run "${BASE[@]}"
{ [ "$RC" -eq 13 ] && [ "$OUT" = NOMODE ] && no_spawn; } && ok "a record older than the task file gives NOMODE" || no "old record (rc=$RC): $OUT"
case_ weird; run "${BASE[@]}"
{ [ "$RC" -eq 13 ] && [ "$OUT" = NOMODE ] && no_spawn; } && ok "an unknown mode gives NOMODE" || no "unknown mode (rc=$RC): $OUT"
case_; run "${BASE[@]}"
[ "$RC" -eq 0 ] && ok "a record two minutes old, newer than a task file three minutes old, spawns" || no "two-minute record (rc=$RC): $OUT $ERR"

case_; : > "$CASE/nobg"; run "${BASE[@]}"
{ [ "$RC" -eq 12 ] && [ "$OUT" = NOBG ] && no_spawn; } && ok "a --help without --bg gives NOBG" || no "nobg (rc=$RC): $OUT"

case_; echo '[{"name":"worker-execute-proj-12","pid":null,"state":"done"}]' > "$CASE/agents"; run "${BASE[@]}"
[ "$OUT" = "STARTED a1b2c3d4 worker-execute-proj-12-2" ] && ok "a stopped row with the base name gives -2" || no "collision -2: $OUT $ERR"
case_; echo '[{"name":"worker-execute-proj-12","pid":1},{"name":"worker-execute-proj-12-2","pid":2}]' > "$CASE/agents"; run "${BASE[@]}"
[ "$OUT" = "STARTED a1b2c3d4 worker-execute-proj-12-3" ] && ok "rows with the base name and -2 give -3" || no "collision -3: $OUT $ERR"
case_; printf '%s' '[{"name":"worker-plan-a","pid":1,"state":"working"},{"name":"worker-plan-b","pid":2,"state":"working"},{"name":"worker-plan-c","pid":3,"state":"working"}]' > "$CASE/agents"
printf 'a1\tworker-plan-a\tplan\ta\t1\nb1\tworker-plan-b\tplan\tb\t1\nc1\tworker-plan-c\tplan\tc\t1\n' > "$SP/workers"; run "${BASE[@]}"
[ "$RC" -eq 0 ] && ok "three owned working rows still spawn" || no "no cap (rc=$RC): $OUT $ERR"

case_; echo 'not json' > "$CASE/agents.1"; run "${BASE[@]}"
[ "$RC" -eq 0 ] && ok "a failed first agents read followed by a valid list spawns" || no "one bad read (rc=$RC): $OUT $ERR"
case_; echo 'not json' > "$CASE/agents"; run "${BASE[@]}"
{ [ "$RC" -eq 3 ] && no_spawn; } && ok "three failed agents reads exit 3 with no spawn" || no "three bad reads (rc=$RC): $OUT"

for ty in plan execute ship investigate; do
  case_
  if [ "$ty" = investigate ]; then run "${BASE[@]}" --type "$ty" --note - --plan -; want=none; else run "${BASE[@]}" --type "$ty"; want=$NOTE; fi
  P="$CASE/prompt"
  { [ "$RC" -eq 0 ] && grep -qF "worker-$ty-proj-12" "$P" && grep -qF '"lead-proj"' "$P" && grep -qF lead-sid-1 "$P" \
    && grep -qxF "Plan note: $want" "$P" && grep -qF 'Build the widget' "$P" && grep -qF "$TOOLKIT/scripts/" "$P" && ! grep -qF '{{' "$P"; } \
    && ok "the $ty template fills every placeholder" || no "$ty template (rc=$RC): $ERR $(cat "$P" 2>&1)"
done
grep -qF 'The ceiling none is' "$CASE/prompt" && ok "an investigate prompt holds ceiling none" || no "investigate ceiling: $(grep '^Run options' "$CASE/prompt")"

case_; run "${BASE[@]}" --note "$BARE"
{ [ "$RC" -eq 2 ] && no_stub; } && ok "an execute note with no ceiling exits 2 with no stub call" || no "no ceiling (rc=$RC): $ERR"

C="$T/copy"; mkdir -p "$C/scripts" "$C/templates" "$C/hooks"; cp "$SPAWN" "$C/scripts/"; cp -R "$TOOLKIT/scripts/lib" "$C/scripts/"; cp -R "$TOOLKIT/hooks/lib" "$C/hooks/"
printf 'You are {{worker_name}} with {{unknown}}.\n' > "$C/templates/worker-execute.md"
case_; OUT="$(bash "$C/scripts/worker-spawn.sh" "${BASE[@]}" 2>"$CASE/err")"; RC=$?
{ [ "$RC" -eq 2 ] && grep -q '^error: .*{{unknown}}' "$CASE/err" && no_stub; } && ok "an unfilled placeholder exits 2 naming it" || no "unknown placeholder (rc=$RC): $(cat "$CASE/err")"
rm -f "$C/templates/worker-execute.md"
case_; OUT="$(bash "$C/scripts/worker-spawn.sh" "${BASE[@]}" 2>"$CASE/err")"; RC=$?
[ "$RC" -eq 3 ] && ok "a missing template exits 3" || no "missing template (rc=$RC): $(cat "$CASE/err")"

case_; run "${BASE[@]}" --lead-name 'lead "x"'
{ [ "$RC" -eq 2 ] && no_stub; } && ok "a lead name with a double quote exits 2" || no "quoted lead name (rc=$RC): $ERR"
case_; printf 'use {{key}} here\n' > "$T/bad-task.txt"; run "${BASE[@]}" --task-file "$T/bad-task.txt"
{ [ "$RC" -eq 2 ] && no_stub; } && ok "a task file holding {{ exits 2" || no "task braces (rc=$RC): $ERR"

K="$HOME/.claude/plugins/cache/shaughn-toolkit/toolkit/9.9.9"; mkdir -p "$K/scripts" "$K/hooks"
cp "$SPAWN" "$K/scripts/"; cp -R "$TOOLKIT/scripts/lib" "$K/scripts/"; cp -R "$TOOLKIT/templates" "$K/"; cp -R "$TOOLKIT/hooks/lib" "$K/hooks/"
case_; OUT="$(bash "$K/scripts/worker-spawn.sh" "${BASE[@]}" 2>"$CASE/err")"; RC=$?
{ [ "$RC" -eq 0 ] && ! argv_has --plugin-dir; } && ok "a plugin cache copy passes no --plugin-dir" || no "cache copy (rc=$RC): $(cat "$CASE/argv" "$CASE/err" 2>&1)"

for bad in "--type explore" "--key Bad_Key" "--scratchpad $T/repo" "--note $TASK" "--worktree a/b"; do
  case_; run "${BASE[@]}" ${bad%% *} "${bad#* }"
  { [ "$RC" -eq 2 ] && no_stub; } && ok "bad ${bad%% *} exits 2 with no stub call" || no "bad ${bad%% *} (rc=$RC): $ERR"
done

case_; echo 1 > "$CASE/rc"; printf 'Workspace not trusted. Run `claude` in %s once and accept the trust prompt, then retry.\n' "$T/repo" > "$CASE/out"; run "${BASE[@]}"
{ [ "$RC" -eq 3 ] && printf '%s' "$ERR" | grep -qF 'Workspace not trusted.' && [ ! -e "$SP/workers" ]; } && ok "an untrusted repo exits 3 with Claude Code's line and no workers line" || no "untrusted (rc=$RC): $ERR"
case_; echo 'started something' > "$CASE/out"; run "${BASE[@]}"
{ [ "$RC" -eq 14 ] && [ "$OUT" = "UNRECORDED worker-execute-proj-12" ] && [ ! -e "$SP/workers" ]; } \
  && ok "a started spawn with no 8-hex id gives UNRECORDED exit 14 and writes no workers line" || no "no id (rc=$RC): $OUT $ERR"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
