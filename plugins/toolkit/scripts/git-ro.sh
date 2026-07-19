#!/bin/bash
# git-ro.sh — read-only git in any directory
set -euo pipefail
dir="${1:?usage: git-ro.sh <dir> <status|diff|log|show> [args]}"
sub="${2:?subcommand required}"
case "$sub" in
  status|diff|log|show) ;;
  *) echo "refused: read-only subcommands only" >&2; exit 1 ;;
esac
shift 2
# Refuse the options that actually WRITE or EXECUTE via these subcommands: `--output`/`-o`
# (writes the diff/log to a file) and `--ext-diff` (runs an external diff command). NOT
# `-c` (git's exec-capable `-c key=val` is only valid BEFORE the subcommand, unreachable
# here; `git log -c` / `git show -c` is a read-only combined-diff flag) and NOT `-O`
# (diff order-file, a read).
for arg in "$@"; do
  case "$arg" in
    --output|--output=*|-o|--ext-diff)
      echo "refused: option '$arg' can write files or execute commands (read-only tool)" >&2; exit 1 ;;
  esac
done
# Neutralise the real execute-on-read vectors regardless of the target repo's config:
# core.pager (pager exec), core.fsmonitor (runs on `git status`), and the external-diff
# driver + textconv drivers (run on diff/log/show -p). --no-textconv/--no-ext-diff apply
# only to the diff-capable subcommands (status rejects them).
noext=()
case "$sub" in diff|log|show) noext=(--no-ext-diff --no-textconv) ;; esac
GIT_PAGER=cat PAGER=cat git -C "$dir" \
  -c core.pager=cat -c core.fsmonitor= -c core.hooksPath=/dev/null \
  "$sub" ${noext[@]+"${noext[@]}"} "$@"
