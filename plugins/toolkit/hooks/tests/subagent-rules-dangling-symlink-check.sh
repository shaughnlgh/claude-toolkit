#!/usr/bin/env bash
# Exercises subagent-rules.sh's fallback when a rule override is a dangling symlink.
# This case creates the symlink at test time. The plugin installer drops symlinks.
# A symlink shipped in the fixture tree does not exist in the installed copy.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters.
# The run uses an isolated temp HOME. The real ~/.claude is never read or written.

DS_HOOK="$ROOT/subagent-rules.sh"
DS_TARGET="/nonexistent-path-for-dangling-symlink-fixture-xyz"

_ds_pass() {
  printf '  PASS  subagent-rules-dangling-symlink :: %s\n' "$1"
  PASS=$((PASS+1))
}

_ds_fail() {
  printf '  FAIL  subagent-rules-dangling-symlink :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("subagent-rules-dangling-symlink::$1")
}

check_ds_falls_back() {
  local label="falls-back" ds_home out rc
  ds_home="$(mktemp -d)" || { _ds_fail "$label :: mktemp -d failed for temp HOME"; return; }
  if ! mkdir -p "$ds_home/.claude/rules" \
    || ! ln -s "$DS_TARGET" "$ds_home/.claude/rules/security.md" \
    || [[ ! -L "$ds_home/.claude/rules/security.md" || -e "$ds_home/.claude/rules/security.md" ]]; then
    _ds_fail "$label :: could not create dangling symlink override"
    rm -rf "$ds_home"
    return
  fi

  out="$(printf '{}' | HOME="$ds_home" CLAUDE_PLUGIN_ROOT="$ROOT/.." bash "$DS_HOOK" 2>/dev/null)"
  rc=$?
  rm -rf "$ds_home"

  if [[ $rc -ne 0 ]]; then
    _ds_fail "$label :: hook exited $rc"
    return
  fi
  if [[ "$out" != *"Toolkit write-time rules (8/8 loaded):"* ]]; then
    _ds_fail "$label :: plugin defaults not all loaded"
    return
  fi
  if [[ "$out" != *"Rule override(s) empty or unreadable, plugin default used instead: security"* ]]; then
    _ds_fail "$label :: fallback not announced by rule name"
    return
  fi
  _ds_pass "$label :: dangling symlink override falls back to plugin default, announced by name"
}

run_subagent_rules_dangling_symlink_checks() {
  check_ds_falls_back
}
