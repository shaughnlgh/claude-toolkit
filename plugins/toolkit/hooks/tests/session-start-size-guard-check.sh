#!/usr/bin/env bash
# Exercises session-start.sh's rule-body size guard: the 64KB per-rule truncation cap,
# its by-name announcement, and the --rawfile emission path that keeps output immune to
# ARG_MAX regardless of input size. Sourced by run-all.sh, which supplies ROOT and the
# PASS/FAIL/FAILED_NAMES counters these add to. Every invocation runs with an isolated
# HOME and plugin root: the real ~/.claude is never read or written.

SG_HOOK="$ROOT/session-start.sh"
SG_RULE="performance"
SG_START="SGSTART_MARK_9c1"
SG_END="SGEND_MARK_9c1"
SG_UNDER_CAP_SIZE=2048
SG_CAP=65536  # must match RULE_BODY_CAP in session-start.sh; not introspectable from outside the hook
SG_OVER_CAP_SIZE=$((SG_CAP + 2048))
SG_ARGMAX_SIZE=1200000  # comfortably over this machine's 1MB ARG_MAX (getconf ARG_MAX)
SG_OUTPUT_BOUND=100000  # generous ceiling: real capped output is ~66KB regardless of input size

_sg_pass() {
  printf '  PASS  session-start-size-guard :: %s\n' "$1"
  PASS=$((PASS+1))
}

_sg_fail() {
  printf '  FAIL  session-start-size-guard :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("session-start-size-guard::$1")
}

# Plugin-default stub for all six rule names the hook always looks for, so the run
# under test loads only via the one override the case under test writes into $HOME.
_sg_setup_plugin_root() {
  local dir="$1" r
  mkdir -p "$dir/rules" || return 1
  for r in testing security error-handling database performance writing; do
    printf 'stub body for %s\n' "$r" > "$dir/rules/$r.md" || return 1
  done
}

# Emits a body of exactly $1 bytes: a leading marker (survives truncation), filler, a
# trailing marker (survives only if the whole body made it through uncapped).
_sg_body() {
  local total="$1" filler_len
  filler_len=$((total - ${#SG_START} - ${#SG_END}))
  printf '%s' "$SG_START"
  printf '%*s' "$filler_len" '' | tr ' ' 'x'
  printf '%s' "$SG_END"
}

# stdin: candidate output. Never use echo on JSON text here: echo in this shell
# interprets the literal backslash-n jq emits for embedded newlines, corrupting it.
_sg_json_ok() {
  jq empty >/dev/null 2>&1
}

# Sets SG_OUT on success. On any setup failure, fails loudly via _sg_fail and returns 1
# rather than leaving the case to pass vacuously against an empty/absent result.
# $3, if given, overrides TMPDIR for the hook invocation (used by the cleanup case).
_sg_run_case() {
  local label="$1" size="$2" tmp_override="${3:-}" out rc
  SG_HOME="$(mktemp -d)" || { _sg_fail "$label :: mktemp -d failed for temp HOME"; return 1; }
  SG_PROOT="$(mktemp -d)" || { _sg_fail "$label :: mktemp -d failed for temp plugin root"; rm -rf "$SG_HOME"; return 1; }
  if ! _sg_setup_plugin_root "$SG_PROOT"; then
    _sg_fail "$label :: plugin root setup failed"
    rm -rf "$SG_HOME" "$SG_PROOT"
    return 1
  fi
  if ! mkdir -p "$SG_HOME/.claude/rules"; then
    _sg_fail "$label :: cannot create override rules dir"
    rm -rf "$SG_HOME" "$SG_PROOT"
    return 1
  fi
  _sg_body "$size" > "$SG_HOME/.claude/rules/${SG_RULE}.md"
  if [[ ! -s "$SG_HOME/.claude/rules/${SG_RULE}.md" ]]; then
    _sg_fail "$label :: override rule file was not created"
    rm -rf "$SG_HOME" "$SG_PROOT"
    return 1
  fi

  if [[ -n "$tmp_override" ]]; then
    out="$(printf '{}' | HOME="$SG_HOME" CLAUDE_PLUGIN_ROOT="$SG_PROOT" TMPDIR="$tmp_override" bash "$SG_HOOK" 2>/dev/null)"
  else
    out="$(printf '{}' | HOME="$SG_HOME" CLAUDE_PLUGIN_ROOT="$SG_PROOT" bash "$SG_HOOK" 2>/dev/null)"
  fi
  rc=$?
  rm -rf "$SG_HOME" "$SG_PROOT"

  if [[ $rc -ne 0 ]]; then
    _sg_fail "$label :: hook exited $rc"
    return 1
  fi
  SG_OUT="$out"
  return 0
}

check_sg_under_cap() {
  _sg_run_case "under-cap" "$SG_UNDER_CAP_SIZE" || return
  if ! printf '%s' "$SG_OUT" | _sg_json_ok; then
    _sg_fail "under-cap :: output did not parse as JSON"
    return
  fi
  if [[ "$SG_OUT" != *"$SG_START"* || "$SG_OUT" != *"$SG_END"* ]]; then
    _sg_fail "under-cap :: body was not injected in full"
    return
  fi
  if [[ "$SG_OUT" == *"exceeded the 64KB cap"* ]]; then
    _sg_fail "under-cap :: truncation announced for a body under the cap"
    return
  fi
  _sg_pass "under-cap :: body injected in full, no truncation announced, output parses as JSON"
}

check_sg_over_cap() {
  local outlen
  _sg_run_case "over-cap" "$SG_OVER_CAP_SIZE" || return
  if ! printf '%s' "$SG_OUT" | _sg_json_ok; then
    _sg_fail "over-cap :: output did not parse as JSON"
    return
  fi
  outlen=${#SG_OUT}
  if [[ "$SG_OUT" != *"$SG_START"* ]]; then
    _sg_fail "over-cap :: start of body missing (should survive truncation)"
    return
  fi
  if [[ "$SG_OUT" == *"$SG_END"* ]]; then
    _sg_fail "over-cap :: end of body present (should have been truncated away)"
    return
  fi
  if [[ "$SG_OUT" != *"rest omitted: ${SG_RULE}"* ]]; then
    _sg_fail "over-cap :: truncation not announced by rule name"
    return
  fi
  if [[ $outlen -gt $SG_OUTPUT_BOUND ]]; then
    _sg_fail "over-cap :: output size $outlen exceeds bound $SG_OUTPUT_BOUND (not capped)"
    return
  fi
  _sg_pass "over-cap :: truncated, announced by name, output bounded ($outlen bytes), parses as JSON"
}

check_sg_argmax() {
  local outlen
  _sg_run_case "argmax" "$SG_ARGMAX_SIZE" || return
  if [[ -z "$SG_OUT" ]]; then
    _sg_fail "argmax :: output was empty (the pre-fix ARG_MAX failure mode)"
    return
  fi
  if ! printf '%s' "$SG_OUT" | _sg_json_ok; then
    _sg_fail "argmax :: output did not parse as JSON"
    return
  fi
  outlen=${#SG_OUT}
  if [[ "$SG_OUT" != *"$SG_START"* ]]; then
    _sg_fail "argmax :: start of body missing (should survive truncation)"
    return
  fi
  if [[ "$SG_OUT" == *"$SG_END"* ]]; then
    _sg_fail "argmax :: end of body present (should have been truncated away)"
    return
  fi
  if [[ $outlen -gt $SG_OUTPUT_BOUND ]]; then
    _sg_fail "argmax :: output size $outlen exceeds bound $SG_OUTPUT_BOUND (grew with input instead of staying capped)"
    return
  fi
  _sg_pass "argmax :: >1MB rule body still yields valid, bounded JSON ($outlen bytes)"
}

# Points TMPDIR at an isolated scratch dir for the run and asserts no toolkit-ctx.*
# file remains there afterward: catches a leaked CTXFILE without depending on the
# shared system temp dir (and the race that watching it would carry).
check_sg_cleanup() {
  local scratch leftover
  scratch="$(mktemp -d)" || { _sg_fail "cleanup :: mktemp -d failed for scratch TMPDIR"; return; }
  if ! _sg_run_case "cleanup" "$SG_UNDER_CAP_SIZE" "$scratch"; then
    rm -rf "$scratch"
    return
  fi
  leftover="$(ls -1 "$scratch" 2>/dev/null | grep '^toolkit-ctx\.' || true)"
  if [[ -n "$leftover" ]]; then
    _sg_fail "cleanup :: toolkit-ctx temp file(s) left behind in isolated TMPDIR: $(printf '%s' "$leftover" | tr '\n' ' ')"
    rm -rf "$scratch"
    return
  fi
  rm -rf "$scratch"
  _sg_pass "cleanup :: no leftover toolkit-ctx.* files in isolated TMPDIR after a run"
}

run_session_start_size_guard_checks() {
  check_sg_under_cap
  check_sg_over_cap
  check_sg_argmax
  check_sg_cleanup
}
