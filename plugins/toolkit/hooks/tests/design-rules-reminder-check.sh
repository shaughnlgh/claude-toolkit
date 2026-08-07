#!/usr/bin/env bash
# Exercises design-rules-reminder.sh's stateful behavior: the real once-per-session
# marker dedup, cleanliness of the temp dir it writes into, and malformed stdin — none
# of which the declarative JSON fixtures can express (fixtures always run stateless via
# TOOLKIT_DESIGN_REMINDER_STATELESS=1, and the fixture stdin field is always valid JSON).
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters
# these add to. Every invocation runs with an isolated TMPDIR so the real system temp
# dir is never touched.

DRR_HOOK="$ROOT/design-rules-reminder.sh"

_drr_pass() {
  printf '  PASS  design-rules-reminder :: %s\n' "$1"
  PASS=$((PASS+1))
}

_drr_fail() {
  printf '  FAIL  design-rules-reminder :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("design-rules-reminder::$1")
}

# Same session, same matching file, twice: first call emits, second is silent, and the
# isolated TMPDIR holds nothing but the one expected marker file afterward.
check_drr_dedup_and_no_leak() {
  local scratch out1 out2 leftover
  scratch="$(mktemp -d)" || { _drr_fail "dedup :: mktemp -d failed for scratch TMPDIR"; return; }

  out1="$(printf '{"session_id":"drr-dedup-1","tool_name":"Write","tool_input":{"file_path":"src/components/Foo.tsx"}}' | TMPDIR="$scratch" bash "$DRR_HOOK" 2>/dev/null)"
  if [[ "$out1" != *"design rules catalog"* || "$out1" != *"design.md"* ]]; then
    _drr_fail "dedup :: first call did not emit the reminder naming design.md"
    rm -rf "$scratch"
    return
  fi

  out2="$(printf '{"session_id":"drr-dedup-1","tool_name":"Write","tool_input":{"file_path":"src/components/Foo.tsx"}}' | TMPDIR="$scratch" bash "$DRR_HOOK" 2>/dev/null)"
  if [[ -n "$out2" ]]; then
    _drr_fail "dedup :: second call in the same session was not silent (got: ${out2:0:60})"
    rm -rf "$scratch"
    return
  fi
  _drr_pass "dedup :: first call emits the reminder, second call in the same session is silent"

  leftover="$(ls -1 "$scratch" 2>/dev/null | grep -v '^toolkit-design-reminder-drr-dedup-1$' || true)"
  if [[ -n "$leftover" ]]; then
    _drr_fail "no-leak :: unexpected file(s) in isolated TMPDIR beyond the session marker: $(printf '%s' "$leftover" | tr '\n' ' ')"
  elif [[ ! -f "$scratch/toolkit-design-reminder-drr-dedup-1" ]]; then
    _drr_fail "no-leak :: expected session marker file was not created"
  else
    _drr_pass "no-leak :: TMPDIR holds exactly the one expected session marker, nothing else"
  fi
  rm -rf "$scratch"
}

# A different session_id, still under the isolated TMPDIR, sees no prior marker and
# emits on its first call too (dedup is scoped per session, not global).
check_drr_new_session_emits() {
  local scratch out
  scratch="$(mktemp -d)" || { _drr_fail "new-session :: mktemp -d failed for scratch TMPDIR"; return; }
  out="$(printf '{"session_id":"drr-dedup-2","tool_name":"Write","tool_input":{"file_path":"src/styles/main.css"}}' | TMPDIR="$scratch" bash "$DRR_HOOK" 2>/dev/null)"
  rm -rf "$scratch"
  if [[ "$out" == *"design rules catalog"* ]]; then
    _drr_pass "new-session :: a different session_id emits on its own first call"
  else
    _drr_fail "new-session :: expected a reminder for an unseen session_id (got: ${out:0:60})"
  fi
}

# Non-JSON stdin: the fixture harness always feeds valid JSON, so this genuinely
# malformed case can only be exercised directly.
check_drr_malformed_stdin() {
  local out rc
  out="$(printf 'not { valid json at all' | bash "$DRR_HOOK" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    _drr_pass "malformed-stdin :: exits 0 with no output (fail-open)"
  else
    _drr_fail "malformed-stdin :: expected exit 0 and empty stdout (got exit $rc, output: ${out:0:60})"
  fi
}

run_design_rules_reminder_checks() {
  check_drr_dedup_and_no_leak
  check_drr_new_session_emits
  check_drr_malformed_stdin
}
