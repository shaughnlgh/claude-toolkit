# Sourced by session-start.sh and agent-model.sh: the one definition of where Claude Code keeps a session's scratchpad.
# Prints each scratchpad directory of session id $1, one per line, and nothing for an id that is not a plain id.
session_scratchpads() {
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  local d
  for d in /tmp/claude-"$(id -u)"/*/"$1"/scratchpad; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
  return 0
}
# Prints the newest <scratchpad>/$2 of session id $1, because two slug directories can hold one session.
session_scratch_file() {
  local d best=""
  while IFS= read -r d; do
    [ -f "$d/$2" ] || continue
    if [ -z "$best" ] || [ "$d/$2" -nt "$best" ]; then best="$d/$2"; fi
  done < <(session_scratchpads "$1")
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}
# Prints the newest plan-guide run options cache of session id $1. The one place the cache file name lives.
session_run_options_file() { session_scratch_file "$1" flow-run-options; }
