#!/bin/bash
# PreToolUse hook (Edit|Write|NotebookEdit): design rules reminder. The design catalog
# (rules/design.md and its per-concern files under rules/design/) is reference-only —
# it reaches the model only via the frontend-designer agent or this hook, never through
# SessionStart injection. When the target file matches a frontend pattern, injects a
# one-line pointer at the catalog, once per session. Advisory only: additionalContext,
# no permissionDecision, never blocks. Fails open on missing jq, malformed/empty input,
# or an unwritable marker dir — exits 0 silently in every such case.
# TOOLKIT_DESIGN_REMINDER_STATELESS=1 skips the once-per-session dedup (used by the
# fixture tests, not meant for real sessions) — mirrors context-sentinel.sh.

command -v jq >/dev/null 2>&1 || exit 0   # no jq: skip silently, never obstruct work
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -n "$FP" ] || exit 0

# Operational copy of the paths: globs in rules/design.md's frontmatter (kept in sync by
# a verify.sh check): extensions, then directory segments, either leading or nested.
case "$FP" in
  *.css|*.scss|*.sass|*.less|*.html|*.phtml|*.tsx|*.jsx|*.vue|*.svelte) ;;
  components/*|*/components/*|pages/*|*/pages/*|views/*|*/views/*|layouts/*|*/layouts/*|styles/*|*/styles/*|templates/*|*/templates/*) ;;
  *) exit 0 ;;
esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SID="${SID//[!A-Za-z0-9_-]/_}"   # state-file path component: never trust it raw

if [ "${TOOLKIT_DESIGN_REMINDER_STATELESS:-0}" != "1" ] && [ -n "$SID" ]; then
  STATE="${TMPDIR:-/tmp}/toolkit-design-reminder-${SID}"
  [ -f "$STATE" ] && exit 0
  { : > "$STATE"; } 2>/dev/null || exit 0   # unwritable marker dir: fail open, silently, no reminder this call
fi

# Resolve the rules dir from this script's own location, not $CLAUDE_PLUGIN_ROOT, so the
# pointer survives a plugin version bump or a dev checkout without the env var set.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || exit 0
RULES_DIR="$(cd "$HOOK_DIR/../rules" 2>/dev/null && pwd)"
[ -n "$RULES_DIR" ] || exit 0

jq -n --arg dir "$RULES_DIR" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("This file matches the design rules catalog — read " + $dir + "/design.md and the concern files this task touches before writing.")}}' \
  2>/dev/null
exit 0
