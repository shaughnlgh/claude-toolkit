#!/bin/bash
# Stop hook: warns the user when a reply suggests a commit but the session's in-progress plan note
# has no Remember: line under Plan Changes During Execution (the remember pass has not run).
# The signal is a last_assistant_message line, anywhere in the message, that begins "Suggested commit",
# which red-team step 8 places after its Repo, Branch, and Scope header lines. The transcript is
# never read. Warn-only: a user-visible systemMessage, never decision: block, always exit 0,
# silent on any failure. Warns once per session when the marker dir is writable, else on every
# qualifying Stop. TOOLKIT_REMEMBER_GUARD=0 disables.

[ "${TOOLKIT_REMEMBER_GUARD:-1}" = "0" ] && { cat >/dev/null 2>&1; exit 0; }
command -v jq >/dev/null 2>&1 || { cat >/dev/null 2>&1; exit 0; }   # no jq: stdin cannot be parsed safely, skip
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

# (a) loop guard: a Stop that follows a stop-hook continuation never warns.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "false" ] || exit 0

# (e) the reply suggests a commit: a line that begins "Suggested commit", case-insensitive,
# after an optional #, *, or ** markdown prefix.
printf '%s\n' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null \
  | grep -qiE '^(#+[[:space:]]*|\*{1,2}[[:space:]]*)?suggested commit' || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$SID" ] && [ -n "$CWD" ] || exit 0
# The id is a path component and a grep pattern: refuse anything outside [A-Za-z0-9_-].
case "$SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac
MARKER="${TMPDIR:-/tmp}/toolkit-remember-guard-${SID}"
[ -L "$MARKER" ] && exit 0
[ -e "$MARKER" ] && exit 0

# (b) inside a git repo. Repo name from the main checkout, as session-start.sh derives it.
cd "$CWD" 2>/dev/null || exit 0
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
REPO=$(basename "$ROOT")
COMMON=$(git rev-parse --git-common-dir 2>/dev/null); COMMON=$([ -n "$COMMON" ] && cd "$COMMON" 2>/dev/null && pwd -P)
[ "$(basename "$COMMON" 2>/dev/null)" = ".git" ] && REPO=$(basename "$(dirname "$COMMON")")

# (c) vault config resolves a Projects folder for this repo.
CFG="$HOME/.claude/obsidian-sync.json"
[ -f "$CFG" ] || exit 0
VAULT=$(jq -r '.vault_path // empty' "$CFG" 2>/dev/null)
FOLDER=$(jq -r '.root_folder // empty' "$CFG" 2>/dev/null)
[ -n "$VAULT" ] && [ -n "$FOLDER" ] && [ -d "$VAULT/$FOLDER/Projects/$REPO" ] || exit 0

# (d) an in-progress plan whose frontmatter sessions list this session id.
# frontmatter_of prints the lines between the opening and closing --- and nothing else.
frontmatter_of() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$1" 2>/dev/null; }
# has_remember_line: a line under ## Plan Changes During Execution that starts with "Remember:" or
# "- Remember:". Lines inside ``` or ~~~ fences never count and never change the section. A fence
# opens on 3+ fence chars plus an optional info word and closes on a bare run of the same char at
# least as long, as strip_fences in validate-plan.py reads them.
has_remember_line() {
  awk '
    match($0, /^[ \t]*(```+|~~~+)/) {
      t = $0; sub(/^[ \t]*/, "", t); c = substr(t, 1, 1); n = 0
      while (substr(t, n + 1, 1) == c) n++
      r = substr(t, n + 1)
      if (fc == "" && r ~ /^[ \t]*[^ \t]*[ \t]*$/) { fc = c; fl = n; next }
      if (fc != "" && c == fc && n >= fl && r ~ /^[ \t]*$/) { fc = ""; next }
    }
    fc != "" { next }
    /^## / { s = ($0 ~ /^## Plan Changes During Execution[[:space:]]*$/) }
    s && /^[[:space:]]*(- )?Remember:/ { f = 1; exit }
    END { exit !f }' "$1" 2>/dev/null
}
MATCHED=0; REMEMBERED=0
for f in "$VAULT/$FOLDER/Projects/$REPO"/*/plan\ -\ *.md; do
  [ -f "$f" ] || continue
  FM=$(frontmatter_of "$f")
  printf '%s\n' "$FM" | grep -q '^status: in-progress[[:space:]]*$' || continue
  printf '%s\n' "$FM" | grep -qE "^[[:space:]]+id: ${SID}[[:space:]]*$" || continue
  MATCHED=1
  has_remember_line "$f" && REMEMBERED=1
done
# (f) silent unless a matching plan exists and none of them carries the line.
[ "$MATCHED" = 1 ] && [ "$REMEMBERED" = 0 ] || exit 0

# A failed marker write still warns: the cost is a repeat warning, never a missed one.
{ : > "$MARKER"; } 2>/dev/null
jq -n --arg sm "A commit was suggested but the plan note has no Remember: line. Run the remember pass (obsidian-topic, § Remember pass) and record its line before the commit suggestion." '{systemMessage:$sm}'
exit 0
