#!/usr/bin/env bash
# Behavior tests for the GITLAB_TOKEN guard in post_mr_comments.py. One case per
# GITLAB_TOKEN shape: unset, empty, whitespace-padded, embedded-newline (the real
# capture-failure shape), and a valid-looking fake token that must pass the guard.
# SECURITY: every case below sets a hardcoded FAKE token or unsets the var. No real
# token is ever read or referenced, and no `glab` command is ever run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../../skills/gitlab-mr-review/scripts/post_mr_comments.py"
PASS=0; FAIL=0

# The guard runs after `json.load(open(sys.argv[1]))` succeeds, so argv[1] must be
# valid JSON with the keys main() dereferences past the guard. host is on the
# .invalid TLD (RFC 2606): guaranteed non-resolvable, so case 05's pass-through
# never causes real network egress — it fails fast at DNS resolution instead.
TMP_CFG="$(mktemp -t post-mr-comments-fixture)"
trap 'rm -f "$TMP_CFG"' EXIT
cat > "$TMP_CFG" <<'JSON'
{
  "host": "https://nonexistent.invalid",
  "project": "group/subgroup/repo",
  "mr_iid": 1,
  "expected_head_sha": "0000000000000000000000000000000000000",
  "diff_path": "/nonexistent/does-not-exist.diff",
  "comments": [],
  "summary": null
}
JSON

# run: $1 name, $2 expected outcome — "abort" (guard fires, exit 1, ABORT: present)
# or "pass" (guard lets the request through: ABORT: absent, exit non-zero for the
# unrelated DNS/network failure that follows). Reads GITLAB_TOKEN from the caller's
# environment (set immediately before each call, since some values embed a newline).
run() {
  local name="$1" expect="$2" out actual
  out="$(python3 "$SCRIPT" "$TMP_CFG" --dry-run 2>&1)"; actual=$?
  case "$expect" in
    abort)
      if [ "$actual" -eq 1 ] && { case "$out" in *"ABORT:"*) true;; *) false;; esac; }; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS+1))
      else
        printf '  FAIL  %s (exit %s, wanted 1 + ABORT:)\n        %s\n' "$name" "$actual" "$(printf '%s' "$out" | head -3)"
        FAIL=$((FAIL+1))
      fi
      ;;
    pass)
      if [ "$actual" -ne 0 ] && { case "$out" in *"ABORT:"*) false;; *) true;; esac; }; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS+1))
      else
        printf '  FAIL  %s (exit %s, wanted nonzero + no ABORT:)\n        %s\n' "$name" "$actual" "$(printf '%s' "$out" | head -3)"
        FAIL=$((FAIL+1))
      fi
      ;;
  esac
}

unset GITLAB_TOKEN
run "01 GITLAB_TOKEN unset" abort

export GITLAB_TOKEN=""
run "02 GITLAB_TOKEN empty" abort

export GITLAB_TOKEN="  padded  "
run "03 GITLAB_TOKEN leading/trailing whitespace" abort

export GITLAB_TOKEN=$'multi\nline'
run "04 GITLAB_TOKEN embedded newline (captured CLI help text shape)" abort

export GITLAB_TOKEN="fake-single-line-dummy-token"
run "05 GITLAB_TOKEN well-formed fake — guard passes through" pass

unset GITLAB_TOKEN

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
