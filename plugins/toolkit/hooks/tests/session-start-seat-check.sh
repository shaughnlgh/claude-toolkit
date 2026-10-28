#!/usr/bin/env bash
# Exercises session-start.sh's seat line against a scratch git repo and a supplied agents list.
# Sourced by run-all.sh after session-start-recall-check.sh, whose _sr_make_repo it reuses.
# Every run uses an isolated temp HOME. The real ~/.claude and the live session list are never read.

SS_HOOK="$ROOT/session-start.sh"
SS_LINE="Another live session shares this checkout"

_ss_pass() {
  printf '  PASS  session-start-seat :: %s\n' "$1"
  PASS=$((PASS+1))
}

_ss_fail() {
  printf '  FAIL  session-start-seat :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("session-start-seat::$1")
}

# $1 label, $2 base dir. Builds base/demo and base/home.
_ss_setup() {
  if ! mkdir -p "$2/home/.claude" || ! _sr_make_repo "$2/demo"; then
    _ss_fail "$1 :: setup failed"; return 1
  fi
}

# $1 label, $2 base dir, $3 agents JSON, $4 run dir. Runs the hook in the run dir as session "self".
# Sets SS_CTX to the hook's additionalContext.
_ss_hook() {
  local label="$1" base="$2" agents="$3" dir="$4" out rc
  printf '%s' "$agents" > "$base/agents.json" || { _ss_fail "$label :: agents file write failed"; return 1; }
  out="$(cd "$dir" && printf '{"session_id":"self","cwd":"%s"}' "$dir" \
    | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
      HOME="$base/home" CLAUDE_PLUGIN_ROOT="$ROOT/.." TOOLKIT_AGENTS_FILE="$base/agents.json" \
      bash "$SS_HOOK" 2>/dev/null)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    _ss_fail "$label :: hook exited $rc"; return 1
  fi
  SS_CTX="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  return 0
}

# $1 label, $2 base dir, $3 agents JSON. Setup, then the hook in base/demo.
_ss_run() {
  _ss_setup "$1" "$2" && _ss_hook "$1" "$2" "$3" "$2/demo"
}

# $1 sessionId, $2 cwd. One live interactive entry, using this shell's pid so kill -0 succeeds.
_ss_entry() {
  printf '[{"pid":%s,"sessionId":"%s","cwd":"%s","name":"other","kind":"interactive","status":"busy"}]' "$$" "$1" "$2"
}

# $1 cwd, then one name per live busy entry. Each entry's sessionId is s-<name>.
_ss_entries() {
  local cwd="$1"; shift
  jq -nc --arg cwd "$cwd" --argjson pid "$$" \
    '$ARGS.positional | map({pid: $pid, sessionId: ("s-" + .), cwd: $cwd, name: ., kind: "interactive", status: "busy"})' --args "$@"
}

check_ss_live_holder() {
  local label="live-holder" base
  base="$(mktemp -d)" || { _ss_fail "$label :: mktemp -d failed"; return; }
  _ss_run "$label" "$base" "$(_ss_entry other-session "$base/demo")" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SS_CTX" != *"$SS_LINE: other (busy), on "* ]]; then
    _ss_fail "$label :: seat line missing for a live holder at the repo root"; return
  fi
  _ss_pass "$label :: a live holder at the repo root prints the seat line"
}

check_ss_empty_list() {
  local label="empty-list" base
  base="$(mktemp -d)" || { _ss_fail "$label :: mktemp -d failed"; return; }
  _ss_run "$label" "$base" '[]' || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SS_CTX" == *"$SS_LINE"* ]]; then
    _ss_fail "$label :: seat line printed for an empty agents list"; return
  fi
  _ss_pass "$label :: an empty agents list prints no seat line"
}

check_ss_self_excluded() {
  local label="self-excluded" base
  base="$(mktemp -d)" || { _ss_fail "$label :: mktemp -d failed"; return; }
  _ss_run "$label" "$base" "$(_ss_entry self "$base/demo")" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SS_CTX" == *"$SS_LINE"* ]]; then
    _ss_fail "$label :: seat line printed for the hook's own session"; return
  fi
  _ss_pass "$label :: an entry matching the payload session_id prints no seat line"
}

check_ss_worktree_silent() {
  local label="worktree-silent" base
  base="$(mktemp -d)" || { _ss_fail "$label :: mktemp -d failed"; return; }
  _ss_setup "$label" "$base" || { rm -rf "$base"; return; }
  if ! git -C "$base/demo" worktree add -q -b wt "$base/wt" >/dev/null 2>&1; then
    _ss_fail "$label :: worktree add failed"; rm -rf "$base"; return
  fi
  _ss_hook "$label" "$base" "$(_ss_entry other-session "$base/demo")" "$base/wt" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SS_CTX" == *"$SS_LINE"* ]]; then
    _ss_fail "$label :: seat line printed for a linked worktree session"; return
  fi
  _ss_pass "$label :: a linked worktree session prints no seat line while main has a live holder"
}

check_ss_three_holders() {
  local label="three-holders" base
  base="$(mktemp -d)" || { _ss_fail "$label :: mktemp -d failed"; return; }
  _ss_run "$label" "$base" "$(_ss_entries "$base/demo" h1 h2 h3 h4 h5)" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SS_CTX" != *"$SS_LINE: h1 (busy), h2 (busy), h3 (busy), on "* ]]; then
    _ss_fail "$label :: seat line does not list exactly the first three of five holders"; return
  fi
  _ss_pass "$label :: five live holders list only the first three"
}

check_ss_line_cap() {
  local label="line-cap" base long bytes
  base="$(mktemp -d)" || { _ss_fail "$label :: mktemp -d failed"; return; }
  _ss_setup "$label" "$base" || { rm -rf "$base"; return; }
  long="feature/a-branch-name-that-runs-well-past-forty-characters-to-pin-the-cut"
  if ! git -C "$base/demo" checkout -q -b "$long" 2>/dev/null; then
    _ss_fail "$label :: branch create failed"; rm -rf "$base"; return
  fi
  _ss_hook "$label" "$base" "$(_ss_entries "$base/demo" \
    "refactor the checkout totals pipeline end to end" \
    "investigate the flaky payments webhook retries" \
    "upgrade the storefront framework and fix the fallout")" "$base/demo" || { rm -rf "$base"; return; }
  rm -rf "$base"
  bytes="$(printf '%s\n' "$SS_CTX" | grep -F "$SS_LINE" | tr -d '\n' | wc -c | tr -d ' ')"
  if [[ -z "$bytes" || "$bytes" -eq 0 || "$bytes" -ge 400 ]]; then
    _ss_fail "$label :: seat line is ${bytes:-0} bytes, want 1 to 399"; return
  fi
  _ss_pass "$label :: three long holder names and a long branch keep the seat line under 400 bytes"
}

run_session_start_seat_checks() {
  check_ss_live_holder
  check_ss_empty_list
  check_ss_self_excluded
  check_ss_worktree_silent
  check_ss_three_holders
  check_ss_line_cap
}
