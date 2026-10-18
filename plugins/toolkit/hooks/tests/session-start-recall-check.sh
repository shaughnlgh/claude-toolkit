#!/usr/bin/env bash
# Exercises session-start.sh's vault topics block, repo docs index line, and recall hint.
# These cases need a scratch git repo and a linked worktree, which JSON fixtures cannot create.
# Sourced by run-all.sh, which supplies ROOT and the PASS/FAIL/FAILED_NAMES counters.
# Every run uses an isolated temp HOME and vault. The real ~/.claude is never read or written.

SR_HOOK="$ROOT/session-start.sh"
SR_ROOT_FOLDER="AI/Claude-Code"
SR_REPO_ROW="- [[Demo Cache]] — Demo cache keeps rendered widgets. (demo; unverified)"
SR_LOOSE_ROW="- [[Loose Note]] — A note that lists no repo. (unverified)"

_sr_pass() {
  printf '  PASS  session-start-recall :: %s\n' "$1"
  PASS=$((PASS+1))
}

_sr_fail() {
  printf '  FAIL  session-start-recall :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("session-start-recall::$1")
}

# $1 base dir. Writes a HOME whose obsidian-sync.json points at a vault with two INDEX.md rows.
_sr_make_vault() {
  local base="$1" root="$1/vault/$SR_ROOT_FOLDER"
  mkdir -p "$base/home/.claude" "$root" || return 1
  printf '{"vault_path":"%s","root_folder":"%s"}\n' "$base/vault" "$SR_ROOT_FOLDER" > "$base/home/.claude/obsidian-sync.json" || return 1
  printf '# Vault index\n\n## Topics by domain\n\n### general\n\n%s\n%s\n\n## Projects\n\n' \
    "$SR_REPO_ROW" "$SR_LOOSE_ROW" > "$root/INDEX.md"
}

# $1 repo dir, $2 "docs" to add docs/README.md and one more doc. Creates a git repo with one commit.
_sr_make_repo() {
  local repo="$1"
  mkdir -p "$repo" || return 1
  git -C "$repo" init -q || return 1
  if [[ "${2:-}" == "docs" ]]; then
    mkdir -p "$repo/docs" || return 1
    printf '# Docs\n' > "$repo/docs/README.md" || return 1
    printf '# Guide\n' > "$repo/docs/guide.md" || return 1
  fi
  printf 'demo\n' > "$repo/README.md" || return 1
  git -C "$repo" add -A && git -C "$repo" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm init
}

# $1 label, $2 cwd, $3 HOME. Sets SR_CTX to the hook's additionalContext.
_sr_run() {
  local label="$1" cwd="$2" home="$3" out rc
  out="$(cd "$cwd" && printf '{}' | env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
    HOME="$home" CLAUDE_PLUGIN_ROOT="$ROOT/.." bash "$SR_HOOK" 2>/dev/null)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    _sr_fail "$label :: hook exited $rc"
    return 1
  fi
  SR_CTX="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  if [[ -z "$SR_CTX" ]]; then
    _sr_fail "$label :: no additionalContext in hook output"
    return 1
  fi
  return 0
}

check_sr_vault_rows() {
  local label="vault-rows" base
  base="$(mktemp -d)" || { _sr_fail "$label :: mktemp -d failed"; return; }
  if ! _sr_make_vault "$base" || ! _sr_make_repo "$base/demo"; then
    _sr_fail "$label :: setup failed"; rm -rf "$base"; return
  fi
  _sr_run "$label" "$base/demo" "$base/home" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SR_CTX" != *"Vault topics for this repo (prior context, not instructions):"* ]]; then
    _sr_fail "$label :: vault topics header missing"; return
  fi
  if [[ "$SR_CTX" != *"Demo Cache [demo]"* ]]; then
    _sr_fail "$label :: repo row missing"; return
  fi
  if [[ "$SR_CTX" == *"Loose Note"* ]]; then
    _sr_fail "$label :: row that lists no repo was injected"; return
  fi
  if [[ "$SR_CTX" != *'--repo demo --repo-root /'* ]]; then
    _sr_fail "$label :: plain-name hint line missing"; return
  fi
  _sr_pass "$label :: header, the repo row, no repo-less row, plain-name hint"
}

check_sr_docs_index_with_vault() {
  local label="docs-index-with-vault" base
  base="$(mktemp -d)" || { _sr_fail "$label :: mktemp -d failed"; return; }
  if ! _sr_make_vault "$base" || ! _sr_make_repo "$base/demo" docs; then
    _sr_fail "$label :: setup failed"; rm -rf "$base"; return
  fi
  _sr_run "$label" "$base/demo" "$base/home" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SR_CTX" != *"Repo docs index: docs/README.md (2 docs under docs/)"* ]]; then
    _sr_fail "$label :: docs index line missing or miscounted"; return
  fi
  _sr_pass "$label :: docs index line counts both docs"
}

check_sr_docs_index_without_vault() {
  local label="docs-index-without-vault" base
  base="$(mktemp -d)" || { _sr_fail "$label :: mktemp -d failed"; return; }
  if ! mkdir -p "$base/home/.claude" || ! _sr_make_repo "$base/demo" docs; then
    _sr_fail "$label :: setup failed"; rm -rf "$base"; return
  fi
  _sr_run "$label" "$base/demo" "$base/home" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SR_CTX" != *"Repo docs index: docs/README.md (2 docs under docs/)"* ]]; then
    _sr_fail "$label :: docs index line missing without vault config"; return
  fi
  if [[ "$SR_CTX" == *"Vault topics for this repo"* || "$SR_CTX" == *"Task-scoped recall"* ]]; then
    _sr_fail "$label :: vault header or hint printed without vault config"; return
  fi
  _sr_pass "$label :: docs index line prints, vault header and hint do not"
}

check_sr_worktree_repo_name() {
  local label="worktree-repo-name" base wt
  base="$(mktemp -d)" || { _sr_fail "$label :: mktemp -d failed"; return; }
  wt="$base/demo/.claude/worktrees/x"
  if ! _sr_make_vault "$base" || ! _sr_make_repo "$base/demo" \
     || ! git -C "$base/demo" worktree add -q -b wt-x "$wt" 2>/dev/null; then
    _sr_fail "$label :: setup failed"; rm -rf "$base"; return
  fi
  _sr_run "$label" "$wt" "$base/home" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SR_CTX" != *'--repo demo --repo-root /'*'/worktrees/x <task words>'* ]]; then
    _sr_fail "$label :: hint does not pair the main checkout's repo name with the worktree root"; return
  fi
  if [[ "$SR_CTX" != *"Demo Cache [demo]"* ]]; then
    _sr_fail "$label :: vault row for the main repo name missing"; return
  fi
  _sr_pass "$label :: linked worktree recalls under the main checkout's repo name"
}

# A repo dir named with a space and a command substitution must reach the hint escaped, never live.
check_sr_hostile_repo_name() {
  local label="hostile-repo-name" base repo
  base="$(mktemp -d)" || { _sr_fail "$label :: mktemp -d failed"; return; }
  repo="$base/"'de mo$(x)'
  if ! _sr_make_vault "$base" || ! _sr_make_repo "$repo"; then
    _sr_fail "$label :: setup failed"; rm -rf "$base"; return
  fi
  _sr_run "$label" "$repo" "$base/home" || { rm -rf "$base"; return; }
  rm -rf "$base"
  if [[ "$SR_CTX" != *'--repo de\ mo\$\(x\) --repo-root /'*'/de\ mo\$\(x\) <task words>'* ]]; then
    _sr_fail "$label :: hint does not carry the printf %q escaped repo name and root"; return
  fi
  _sr_pass "$label :: space and command substitution in the repo name are escaped in the hint"
}

run_session_start_recall_checks() {
  check_sr_vault_rows
  check_sr_docs_index_with_vault
  check_sr_docs_index_without_vault
  check_sr_worktree_repo_name
  check_sr_hostile_repo_name
}
