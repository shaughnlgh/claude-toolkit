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
git -C "$dir" "$sub" "$@"
