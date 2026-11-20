#!/usr/bin/env bash
# Exercises remember-guard.sh, the Stop hook that warns when a reply suggests a commit but the
# session's in-progress plan note has no Remember: line.
# These cases need a scratch git repo, a linked worktree, vault plan notes, and real marker
# persistence, which JSON fixtures cannot create.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters.
# Every run uses an isolated temp HOME, TMPDIR, and vault. The real ~/.claude is never read or written.

RG_HOOK="$ROOT/remember-guard.sh"
RG_ROOT_FOLDER="AI/Claude-Code"
RG_PLAN_REL="Projects/demo/2026-01-01-x/plan - x.md"
RG_PLAN2_REL="Projects/demo/2026-01-02-y/plan - y.md"
RG_MSG="$(printf 'Suggested commit\n\nfeat: add x')"

_rg_pass() {
  printf '  PASS  remember-guard :: %s\n' "$1"
  PASS=$((PASS+1))
}

_rg_fail() {
  printf '  FAIL  remember-guard :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("remember-guard::$1")
}

# $1 plan file, $2 status, $3 session id. Writes a plan whose Plan Changes section says "None yet.".
_rg_write_plan() {
  mkdir -p "$(dirname "$1")" || return 1
  printf -- '---\ntype: plan\nplan: x\nstatus: %s\nsessions:\n  - date: 2026-01-01\n    summary: fixture\n    id: %s\n---\n\n## Objective\n\nFixture.\n\n## Plan Changes During Execution\n\nNone yet.\n' \
    "$2" "$3" > "$1"
}

# $1 base dir. Builds a HOME whose toolkit-vault.json points at a vault holding one in-progress plan
# that lists session fx-rg-1, a one-commit git repo named demo, and an empty TMPDIR for the marker.
_rg_setup() {
  local base="$1"
  mkdir -p "$base/home/.claude" "$base/tmp" "$base/demo" || return 1
  printf '{"vault_path":"%s","root_folder":"%s"}\n' "$base/vault" "$RG_ROOT_FOLDER" > "$base/home/.claude/toolkit-vault.json" || return 1
  _rg_write_plan "$base/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" in-progress fx-rg-1 || return 1
  git -C "$base/demo" init -q || return 1
  printf 'demo\n' > "$base/demo/README.md" || return 1
  git -C "$base/demo" add -A && git -C "$base/demo" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm init
}

# $1 base, $2 cwd, $3 session id, $4 stop_hook_active (true|false), $5 last_assistant_message,
# then optional NAME=value env assignments. Sets RG_OUT and RG_ERR. Returns the hook's exit code.
_rg_run() {
  local base="$1" cwd="$2" sid="$3" active="$4" msg="$5" rc
  shift 5
  RG_OUT="$(jq -nc --arg sid "$sid" --arg cwd "$cwd" --arg active "$active" --arg msg "$msg" \
      '{session_id:$sid, cwd:$cwd, stop_hook_active:($active=="true"), last_assistant_message:$msg, hook_event_name:"Stop"}' \
    | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR HOME="$base/home" TMPDIR="$base/tmp" "$@" \
      bash "$RG_HOOK" 2>"$base/err")"
  rc=$?
  RG_ERR="$(cat "$base/err" 2>/dev/null)"
  return $rc
}

_rg_warned() { [[ "$RG_OUT" == *'"systemMessage"'*'no Remember: line'* ]]; }

# $1 label, then the _rg_run arguments. Fresh base with the default setup, expects a warning.
_rg_expect_warn() {
  local label="$1" base="$2"
  shift
  _rg_run "$@" || { _rg_fail "$label :: hook exited non-zero"; rm -rf "$base"; return; }
  rm -rf "$base"
  if _rg_warned; then _rg_pass "$label"; else _rg_fail "$label :: no systemMessage"; fi
}

# $1 label, then the _rg_run arguments. Expects no output.
_rg_expect_silent() {
  local label="$1" base="$2"
  shift
  _rg_run "$@" || { _rg_fail "$label :: hook exited non-zero"; rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ -z "$RG_OUT" ]]; then _rg_pass "$label"; else _rg_fail "$label :: hook printed output"; fi
}

# $1 label. Sets RG_BASE to a fresh base with the default setup, or reports the failure.
_rg_new_base() {
  RG_BASE="$(mktemp -d)" || { _rg_fail "$1 :: mktemp -d failed"; return 1; }
  _rg_setup "$RG_BASE" || { _rg_fail "$1 :: setup failed"; rm -rf "$RG_BASE"; return 1; }
}

check_rg_warns() {
  local label="warns-when-commit-suggested-and-no-remember-line"
  _rg_new_base "$label" || return
  _rg_expect_warn "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_warns_with_legacy_config_only() {
  local label="warns-with-only-the-legacy-config"
  _rg_new_base "$label" || return
  mv "$RG_BASE/home/.claude/toolkit-vault.json" "$RG_BASE/home/.claude/obsidian-sync.json" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_warn "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_warns_on_prefixed_signature() {
  local label="warns-on-heading-prefixed-lowercase-signature"
  _rg_new_base "$label" || return
  _rg_expect_warn "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$(printf 'Review done.\n\n### suggested commit message\n\nfeat: add x')"
}

# The phrase mid-line is not the signature.
check_rg_silent_without_signature() {
  local label="silent-when-reply-has-no-signature-line"
  _rg_new_base "$label" || return
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$(printf 'Done. The suggested commit is below.\nfeat: add x')"
}

check_rg_silent_with_remember_line() {
  local label="silent-when-remember-line-present"
  _rg_new_base "$label" || return
  printf -- '- Remember: no change (fixture)\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_silent_with_remember_pass_owed_line() {
  local label="silent-when-remember-pass-owed-line-present"
  _rg_new_base "$label" || return
  printf -- '- Remember pass owed: Projects/demo/2026-01-01-x/remember-material - x.md\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_warns_when_remember_line_only_fenced() {
  local label="warns-when-remember-line-is-only-inside-a-fence"
  _rg_new_base "$label" || return
  printf -- '```text\n- Remember: example\n```\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_warn "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_fenced_heading_keeps_section() {
  local label="silent-when-fenced-heading-precedes-the-remember-line"
  _rg_new_base "$label" || return
  printf -- '```text\n## Other\n```\n- Remember: no change (fixture)\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

# The bare ``` line inside the ~~~ block must not close it: only a run of the same char closes a fence.
check_rg_warns_when_remember_line_only_tilde_fenced() {
  local label="warns-when-remember-line-is-only-inside-a-tilde-fence"
  _rg_new_base "$label" || return
  printf -- '~~~\n```\n- Remember: example\n~~~\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_warn "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_tilde_fenced_heading_keeps_section() {
  local label="silent-when-tilde-fenced-heading-precedes-the-remember-line"
  _rg_new_base "$label" || return
  printf -- '~~~text\n## Example\n~~~\n- Remember: no change (fixture)\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_silent_without_matching_plan() {
  local label="silent-when-no-in-progress-plan-lists-the-session"
  _rg_new_base "$label" || return
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-2 false "$RG_MSG"
}

check_rg_silent_when_plan_in_review() {
  local label="silent-when-the-plan-is-at-status-review"
  _rg_new_base "$label" || return
  _rg_write_plan "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" review fx-rg-1 \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

# The plan with the line sorts first, so a loop that keeps only the last plan's result warns.
check_rg_silent_when_one_of_two_plans_has_line() {
  local label="silent-when-one-of-two-matching-plans-has-the-line"
  _rg_new_base "$label" || return
  if ! printf -- '- Remember: no change (fixture)\n' >> "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" \
     || ! _rg_write_plan "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN2_REL" in-progress fx-rg-1; then
    _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return
  fi
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_silent_on_second_stop() {
  local label="silent-on-second-stop-in-the-session"
  _rg_new_base "$label" || return
  _rg_run "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG" || { _rg_fail "$label :: first run exited non-zero"; rm -rf "$RG_BASE"; return; }
  _rg_warned || { _rg_fail "$label :: first stop did not warn"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
}

check_rg_silent_when_stop_hook_active() {
  local label="silent-when-stop-hook-active"
  _rg_new_base "$label" || return
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 true "$RG_MSG"
}

# The non-repo dir is named demo, so only the git check stands between it and the vault plan.
check_rg_silent_outside_git() {
  local label="silent-when-cwd-is-outside-a-git-repo"
  _rg_new_base "$label" || return
  mkdir -p "$RG_BASE/nogit/demo" || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/nogit/demo" fx-rg-1 false "$RG_MSG"
}

# $1 label, $2 hostile session id. The plan lists the same id, so only the id guard keeps the hook silent.
_rg_check_hostile_id() {
  local label="$1" sid="$2" left
  _rg_new_base "$label" || return
  _rg_write_plan "$RG_BASE/vault/$RG_ROOT_FOLDER/$RG_PLAN_REL" in-progress "$sid" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_run "$RG_BASE" "$RG_BASE/demo" "$sid" false "$RG_MSG" || { _rg_fail "$label :: hook exited non-zero"; rm -rf "$RG_BASE"; return; }
  left="$(ls -A "$RG_BASE/tmp")"
  rm -rf "$RG_BASE"
  if [[ -n "$RG_OUT" ]]; then _rg_fail "$label :: hook printed output"; return; fi
  if [[ -n "$left" ]]; then _rg_fail "$label :: marker created"; return; fi
  _rg_pass "$label"
}

check_rg_silent_for_traversal_id() { _rg_check_hostile_id "silent-for-session-id-with-path-traversal" '../x'; }
check_rg_silent_for_semicolon_id() { _rg_check_hostile_id "silent-for-session-id-with-a-semicolon" 'a;b'; }

check_rg_silent_when_disabled() {
  local label="silent-when-TOOLKIT_REMEMBER_GUARD-is-0"
  _rg_new_base "$label" || return
  _rg_expect_silent "$label" "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG" TOOLKIT_REMEMBER_GUARD=0
}

# A dangling symlink at the marker path must stop the hook before it writes through the link.
check_rg_silent_when_marker_is_symlink() {
  local label="silent-when-marker-path-is-a-symlink" wrote
  _rg_new_base "$label" || return
  ln -s "$RG_BASE/target" "$RG_BASE/tmp/toolkit-remember-guard-fx-rg-1" \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_run "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG" || { _rg_fail "$label :: hook exited non-zero"; rm -rf "$RG_BASE"; return; }
  wrote=no; [[ -e "$RG_BASE/target" ]] && wrote=yes
  rm -rf "$RG_BASE"
  if [[ -n "$RG_OUT" ]]; then _rg_fail "$label :: hook printed output"; return; fi
  if [[ "$wrote" == yes ]]; then _rg_fail "$label :: hook wrote through the symlink"; return; fi
  _rg_pass "$label"
}

# An unwritable TMPDIR loses the marker: the hook warns on every qualifying Stop, with no stderr.
check_rg_warns_again_when_tmpdir_unwritable() {
  local label="warns-again-without-stderr-when-tmpdir-is-unwritable" first_ok=1
  _rg_new_base "$label" || return
  chmod 555 "$RG_BASE/tmp" || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_run "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG" || first_ok=0
  _rg_warned && [[ -z "$RG_ERR" ]] || first_ok=0
  _rg_run "$RG_BASE" "$RG_BASE/demo" fx-rg-1 false "$RG_MSG"
  chmod 755 "$RG_BASE/tmp"
  rm -rf "$RG_BASE"
  if [[ $first_ok -eq 0 ]]; then _rg_fail "$label :: first stop did not warn cleanly"; return; fi
  if ! _rg_warned; then _rg_fail "$label :: second stop did not warn"; return; fi
  if [[ -n "$RG_ERR" ]]; then _rg_fail "$label :: hook wrote to stderr"; return; fi
  _rg_pass "$label"
}

check_rg_worktree_uses_main_repo_name() {
  local label="worktree-warns-against-the-main-repo-plan" wt
  _rg_new_base "$label" || return
  wt="$RG_BASE/demo/.claude/worktrees/x"
  git -C "$RG_BASE/demo" worktree add -q -b wt-x "$wt" 2>/dev/null \
    || { _rg_fail "$label :: setup failed"; rm -rf "$RG_BASE"; return; }
  _rg_expect_warn "$label" "$RG_BASE" "$wt" fx-rg-1 false "$RG_MSG"
}

run_remember_guard_checks() {
  check_rg_warns
  check_rg_warns_with_legacy_config_only
  check_rg_warns_on_prefixed_signature
  check_rg_silent_without_signature
  check_rg_silent_with_remember_line
  check_rg_silent_with_remember_pass_owed_line
  check_rg_warns_when_remember_line_only_fenced
  check_rg_fenced_heading_keeps_section
  check_rg_warns_when_remember_line_only_tilde_fenced
  check_rg_tilde_fenced_heading_keeps_section
  check_rg_silent_without_matching_plan
  check_rg_silent_when_plan_in_review
  check_rg_silent_when_one_of_two_plans_has_line
  check_rg_silent_on_second_stop
  check_rg_silent_when_stop_hook_active
  check_rg_silent_outside_git
  check_rg_silent_for_traversal_id
  check_rg_silent_for_semicolon_id
  check_rg_silent_when_disabled
  check_rg_silent_when_marker_is_symlink
  check_rg_warns_again_when_tmpdir_unwritable
  check_rg_worktree_uses_main_repo_name
}
