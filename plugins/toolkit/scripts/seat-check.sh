#!/usr/bin/env bash
# Reports which live Claude sessions hold a repo's main checkout. Read-only. Exit 0 free, 10 held, 2 error.
set -uo pipefail

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
main_of() {  # $1 any path inside the repo or a linked worktree of it
  local common; common=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$1" && cd "$common" 2>/dev/null && pwd -P) || return 1
  [ "$(basename "$common")" = ".git" ] && dirname "$common" || (cd "$1" && git rev-parse --show-toplevel)
}
OWN_WT=.claude/worktrees  # Claude Code creates linked worktrees here: they hold no seat and never count as dirty.
holds() {  # $1 session cwd, $2 main. True when cwd is main or under it, and not under main/$OWN_WT/.
  local cwd; cwd=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  case "$cwd" in "$2"|"$2"/*) case "$cwd" in "$2/$OWN_WT"/*) return 1 ;; esac; return 0 ;; esac
  return 1
}
inside() {  # $1 session cwd, $2 resolved dir. True when cwd is that dir or under it.
  local cwd; cwd=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  case "$cwd" in "$2"|"$2"/*) return 0 ;; esac
  return 1
}

repo=""; self=""; wt=""; occupants=""
while [ $# -gt 0 ]; do
  case "$1" in
    --self) [ $# -ge 2 ] || die "--self needs a session id"; self=$2; shift 2 ;;
    --worktree) [ $# -ge 2 ] || die "--worktree needs a path"; wt=$2; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$repo" ] || die "one repo path only"; repo=$1; shift ;;
  esac
done
[ -n "$repo" ] || die "usage: seat-check.sh <repo path> [--self <sessionId>] [--worktree <path>]"
command -v jq >/dev/null 2>&1 || die "jq not found"
main=$(main_of "$repo") || die "not a git repo: $repo"
wt_dir=""; [ -z "$wt" ] || wt_dir=$(cd "$wt" 2>/dev/null && pwd -P) || die "not a directory: $wt"

if [ -n "${TOOLKIT_AGENTS_FILE:-}" ]; then
  agents=$(cat "$TOOLKIT_AGENTS_FILE" 2>/dev/null)
elif command -v perl >/dev/null 2>&1; then
  # macOS ships no timeout binary, so perl kills a stalled claude call after 3 s.
  agents=$(perl -e '$p = fork // exit 127; if (!$p) { exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill 9, $p; exit 124 }; alarm 3; waitpid $p, 0; exit $? >> 8' claude agents --json 2>/dev/null)
else
  agents=$(claude agents --json 2>/dev/null)
fi
# input errors on empty stdin, so a missing or failed claude command is an error, not an empty list.
rows=$(printf '%s' "$agents" | jq -rn 'input | if type == "array" then .[] | select(.pid != null)
  | [.pid, .sessionId, .cwd, .name, .status, .kind] | map(. // "" | tostring | gsub("[\t\n\r\u001f]"; " ")) | join("\u001f")
  else error("not an array") end' 2>/dev/null) || die "agents source is not a JSON array"

holders=""
while IFS=$'\x1f' read -r pid sid cwd name status kind; do
  case "$pid" in ''|*[!0-9]*) continue ;; esac
  [ -n "$self" ] && [ "$sid" = "$self" ] && continue
  kill -0 "$pid" 2>/dev/null || continue
  [ -n "$wt_dir" ] && inside "$cwd" "$wt_dir" && occupants+="occupant: $name"$'\t'"$status"$'\t'"$kind"$'\t'"$sid"$'\t'"$cwd"$'\n'
  holds "$cwd" "$main" || continue
  holders+="holder: $name"$'\t'"$status"$'\t'"$kind"$'\t'"$sid"$'\t'"$cwd"$'\n'
done <<< "$rows"

branch=$(git -C "$main" symbolic-ref --short -q HEAD) || branch=detached
dirty=$(git --no-optional-locks -C "$main" status --porcelain -uall -- ":(exclude,top)$OWN_WT/" 2>/dev/null | wc -l | tr -d ' ')
[ -n "$holders" ] && echo "seat: held" || echo "seat: free"
printf 'main: %s\nbranch: %s\ndirty: %s\n%s%s' "$main" "$branch" "$dirty" "$holders" "$occupants"
[ -n "$holders" ] && exit 10
exit 0
