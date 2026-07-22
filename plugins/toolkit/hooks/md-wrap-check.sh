#!/bin/bash
# PostToolUse hook (Edit|Write): flags hard-wrapped markdown prose so it gets fixed
# at write time. Doctrine: one line per paragraph; let the editor soft-wrap.
# Heuristic, tuned for low false positives: a prose line of 60+ chars that ends
# mid-clause (word character or comma), followed by a line starting with a lowercase
# letter, is a wrapped paragraph. Code fences, YAML keys, headings, lists, tables,
# and quotes never match. Warning only: exit 2 feeds the finding back to the model;
# nothing is blocked (the write has already happened).

command -v jq >/dev/null 2>&1 || exit 0   # no jq: skip silently, never obstruct work
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE" in *.md) ;; *) exit 0 ;; esac

# Check only the content this call wrote (Write) or inserted (Edit), never the whole
# file — pre-existing wrapped prose elsewhere is not this edit's fault.
TEXT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty')
[ -n "$TEXT" ] || exit 0

HITS=$(printf '%s\n' "$TEXT" | awk '
  /^```/ { fence = !fence; prev = ""; next }
  fence  { prev = ""; next }
  {
    if (prev != "" && $0 ~ /^[a-z]/ && $0 !~ /^[a-z][a-zA-Z_-]*:/) {
      print "  line " NR-1 ": " substr(prev, 1, 60) "..."
      if (++found >= 3) exit
    }
    # candidate for a wrapped line: prose start, long, ends mid-clause, not a
    # YAML key line, not a numbered list item
    if (length($0) >= 60 && $0 ~ /^[A-Za-z0-9]/ && $0 ~ /[A-Za-z0-9,]$/ \
        && $0 !~ /^[A-Za-z][a-zA-Z_-]*:/ && $0 !~ /^[0-9]+\. /)
      prev = $0
    else
      prev = ""
  }
')

[ -z "$HITS" ] && exit 0
{
  echo "Hard-wrapped prose detected in $FILE (toolkit doctrine: write each paragraph as one continuous line and let the editor soft-wrap):"
  echo "$HITS"
  echo "Rewrite the affected paragraphs as single lines."
} >&2
exit 2
