#!/bin/bash
# SessionStart hook. Two outputs:
#  - additionalContext (model-visible): write-time rules + doctrine pointer + git briefing.
#  - systemMessage (user-visible, startup only): a one-line "toolkit active" status.
# Emits JSON when jq is available; falls back to plain-stdout context (proven path)
# when it is not, so the rules pipeline never depends on jq to function.
# Verbose git extras via TOOLKIT_SESSION_VERBOSE=1.

INPUT=$(cat 2>/dev/null)
SOURCE=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
fi
VERBOSE="${TOOLKIT_SESSION_VERBOSE:-0}"
CTX=""
add() { [ -n "$CTX" ] && CTX="${CTX}
$1" || CTX="$1"; }

# Write-time rules + doctrine pointer, live from the plugin (always current; no local
# copies). Frontend rules stay on-demand via the frontend-designer agent.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/rules" ]; then
  RULES=""; ROVR=""
  for r in testing security error-handling database; do
    f="${CLAUDE_PLUGIN_ROOT}/rules/${r}.md"
    if [ -f "$HOME/.claude/rules/${r}.md" ]; then f="$HOME/.claude/rules/${r}.md"; ROVR="${ROVR} ${r}"; fi
    if [ -f "$f" ]; then
      body="$(awk 'f{print} /^---$/{c++; if(c==2)f=1}' "$f")"
      [ -z "$body" ] && body="$(cat "$f")"   # override without frontmatter: use the whole file, never drop the rule
      RULES="${RULES}${body}
"
    fi
  done
  if [ -n "$RULES" ]; then
    add "Toolkit write-time rules:"
    add "$RULES"
    add "Frontend work: use the frontend-designer agent, or read rules/frontend.md in this plugin."
  fi
  [ -f "${CLAUDE_PLUGIN_ROOT}/CLAUDE.md" ] && add "Toolkit doctrine: read the index at ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md before multi-agent or planned work (binding essences plus per-section files; design rationale in README.md alongside). Subagents do not see this line: pass doctrine constraints down in delegation prompts, or add the pointer to your global CLAUDE.md via /toolkit-setup."
  # Per-file doctrine overrides: a same-named file in ~/.claude/doctrine/ replaces the
  # plugin's copy for that concern. Detected here so it needs no pointer written anywhere.
  if [ -d "$HOME/.claude/doctrine" ]; then
    OVR=""
    for o in "$HOME"/.claude/doctrine/*.md; do
      [ -f "$o" ] && OVR="${OVR} $(basename "$o" .md)"
    done
    [ -n "$OVR" ] && add "Doctrine overrides active. For these concerns read your global ~/.claude/doctrine/<name>.md and follow it INSTEAD of the plugin's doctrine/<name>.md (your copy wins; safety sections may be tightened, not loosened):${OVR}."
  fi
  # Rule overrides: injected above from ~/.claude/rules/ instead of the plugin defaults.
  [ -n "$ROVR" ] && add "Rule overrides active. Your global ~/.claude/rules/ versions were injected above instead of the plugin defaults:${ROVR}."
  # Agent/skill overrides: a same-named file/dir in ~/.claude/{agents,skills} shadows the
  # plugin's (Claude Code resolves it natively for the bare name). Announced for visibility.
  ASOVR=""
  for a in "$HOME"/.claude/agents/*.md; do
    [ -f "$a" ] || continue; n=$(basename "$a" .md)
    [ -f "${CLAUDE_PLUGIN_ROOT}/agents/${n}.md" ] && ASOVR="${ASOVR} agent:${n}"
  done
  for s in "$HOME"/.claude/skills/*/; do
    [ -d "$s" ] || continue; n=$(basename "$s")
    [ -d "${CLAUDE_PLUGIN_ROOT}/skills/${n}" ] && ASOVR="${ASOVR} skill:${n}"
  done
  [ -n "$ASOVR" ] && add "Agent/skill overrides active. Claude Code resolves your global version over the plugin's for the bare name (invoke bare, not toolkit:<name>):${ASOVR}."
fi

# Git briefing (only inside a repo).
if git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  if [ -n "$BRANCH" ]; then G="Branch: $BRANCH"; else
    SS=$(git rev-parse --short HEAD 2>/dev/null); [ -n "$SS" ] && G="HEAD: detached at $SS"; fi
  git diff-index --quiet HEAD -- 2>/dev/null || G="$G | dirty"
  if [ "$VERBOSE" = "1" ]; then
    LC=$(git log --oneline -1 2>/dev/null); [ -n "$LC" ] && G="$G | Last: $LC"
    CH=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' '); [ "$CH" -gt 0 ] 2>/dev/null && G="$G | $CH files changed"
    git diff --cached --quiet 2>/dev/null || G="$G | staged"
    ST=$(git stash list 2>/dev/null | wc -l | tr -d ' '); [ "$ST" -gt 0 ] 2>/dev/null && G="$G | $ST stash(es)"
    if command -v gh >/dev/null 2>&1; then
      PR=$(gh pr view --json number,title,state --jq '"PR #\(.number): \(.title) (\(.state))"' 2>/dev/null)
      [ -n "$PR" ] && G="$G | $PR"; fi
  fi
  [ -n "${G:-}" ] && add "$G"
fi

# User-visible status line, startup only (skip on resume/clear so it doesn't nag).
STATUS=""
if [ "$SOURCE" = "startup" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  VER=$(basename "$CLAUDE_PLUGIN_ROOT")
  case "$VER" in toolkit) VER="";; *) VER=" $VER";; esac  # dev checkout has no version segment
  NA=$(ls "$CLAUDE_PLUGIN_ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
  NS=$(ls -d "$CLAUDE_PLUGIN_ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
  if [ -f "$HOME/.claude/obsidian-sync.json" ]; then
    STATUS="toolkit${VER} active — ${NA} agents, ${NS} skills, planning ready"
  else
    STATUS="toolkit${VER} active — ${NA} agents, ${NS} skills · planning not configured: run /toolkit-setup"
  fi
fi

# Emit. JSON (with systemMessage) when jq is present; plain-stdout context otherwise.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$CTX" --arg sm "$STATUS" \
    'def base: {hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}};
     if $sm=="" then base else base + {systemMessage:$sm} end'
else
  [ -n "$CTX" ] && printf '%s\n' "$CTX"
fi
exit 0
