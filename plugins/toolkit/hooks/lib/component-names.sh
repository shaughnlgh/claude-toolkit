# Sourced by agent-model.sh, session-start.sh and scripts/override.sh: the one definition of the names Claude Code resolves an agent or a skill by.
# Prints the frontmatter name of each file it reads, with a trailing CR stripped from each line before any compare,
# the value inside single or double quotes when quoted, else the value without a trailing YAML comment.
_FRONTMATTER_NAME_AWK='
  FNR == 1 { done = 0 }
  done { next }
  { sub(/\r$/, "") }
  FNR == 1 { if ($0 != "---") done = 1; next }
  $0 == "---" { done = 1; next }
  /^name:/ {
    v = $0; sub(/^name:[[:space:]]*/, "", v); q = substr(v, 1, 1)
    if (q == "\"" || q == "\047") { v = substr(v, 2); i = index(v, q); if (i) v = substr(v, 1, i - 1) }
    else { sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v) }
    print v; done = 1 }'
# Prints the frontmatter name of each .md file at any depth under $1, because Claude Code keys an agent by that name, never by its file name.
# One awk reads every file, so a large linked agents folder costs one process per batch, not one per file.
agent_names() {
  [ -d "$1" ] || return 0
  find -L "$1" -type f -name '*.md' -exec awk "$_FRONTMATTER_NAME_AWK" {} + 2>/dev/null
  return 0
}
# Prints the directory name and the frontmatter name of each <dir>/SKILL.md under $1, because Claude Code invokes a personal skill by both.
skill_names() {
  local d
  [ -d "$1" ] || return 0
  for d in "$1"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    basename "$d"
    awk "$_FRONTMATTER_NAME_AWK" "$d/SKILL.md"
  done
  return 0
}
