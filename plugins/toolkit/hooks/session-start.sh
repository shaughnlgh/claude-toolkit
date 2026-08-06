#!/bin/bash
# SessionStart hook. Two outputs:
#  - additionalContext (model-visible): write-time rules + doctrine pointer + git briefing.
#  - systemMessage (user-visible, startup only): a one-line "toolkit active" status.
# Emits JSON when jq is available; falls back to plain-stdout context (proven path)
# when it is not, so the rules pipeline never depends on jq to function.
# Verbose git extras via TOOLKIT_SESSION_VERBOSE=1.

INPUT=$(cat 2>/dev/null)
SOURCE=""
TRANSCRIPT=""
CTXFILE=""
cleanup() { [ -n "$CTXFILE" ] && rm -f "$CTXFILE"; }
trap cleanup EXIT
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi
VERBOSE="${TOOLKIT_SESSION_VERBOSE:-0}"
CTX=""
add() { [ -n "$CTX" ] && CTX="${CTX}
$1" || CTX="$1"; }

# Write-time rules + doctrine pointer, live from the plugin (always current; no local
# copies). Frontend rules stay on-demand via the frontend-designer agent.
RULES_MISSING_PATH=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/rules" ]; then
  # Body of $1: CRLF-normalized; frontmatter stripped only with >=2 "---" markers (else whole file is the body); empty/unreadable -> exit 1 (never a false "loaded").
  body_of() {
    local raw b dashes
    [ -r "$1" ] || return 1
    raw="$(cat "$1" 2>/dev/null)"
    raw="${raw//$'\r'/}"
    dashes=$(printf '%s\n' "$raw" | grep -c '^---$')
    if [ "$dashes" -eq 0 ]; then
      b="$raw"
    else
      b="$(printf '%s\n' "$raw" | awk 'f{print} /^---$/{c++; if(c==2)f=1}')"
    fi
    case "$b" in *[![:space:]]*) printf '%s' "$b"; return 0 ;; esac
    return 1
  }
  RULES=""; ROVR=""; RFALLBACK=""; RMISSING=""; RTRUNC=""; NLOADED=0; NTOTAL=0
  RULE_BODY_CAP=65536  # 64KB per rule body; re-sent every request for the session, so unbounded bodies are ruinously expensive
  for r in testing security error-handling database performance; do
    NTOTAL=$((NTOTAL+1))
    pf="${CLAUDE_PLUGIN_ROOT}/rules/${r}.md"
    ovf="$HOME/.claude/rules/${r}.md"
    body=""
    if [ -f "$ovf" ]; then
      if body="$(body_of "$ovf")"; then
        ROVR="${ROVR} ${r}"
      elif body="$(body_of "$pf")"; then
        RFALLBACK="${RFALLBACK} ${r}"
      else
        RMISSING="${RMISSING} ${r}"
      fi
    elif ! body="$(body_of "$pf")"; then
      RMISSING="${RMISSING} ${r}"
    fi
    if [ -n "$body" ]; then
      if [ "$(printf '%s' "$body" | wc -c | tr -d ' ')" -gt "$RULE_BODY_CAP" ]; then
        body="$(printf '%s' "$body" | head -c "$RULE_BODY_CAP")"
        RTRUNC="${RTRUNC} ${r}"
      fi
      NLOADED=$((NLOADED+1))
      RULES="${RULES}${body}
"
    fi
  done
  if [ -n "$RULES" ]; then
    add "Toolkit write-time rules (${NLOADED}/${NTOTAL} loaded):"
    add "$RULES"
    add "Frontend work: use the frontend-designer agent, or read rules/frontend.md in this plugin."
  else
    add "Toolkit write-time rules: 0/${NTOTAL} loaded (plugin rules unreadable or empty at ${CLAUDE_PLUGIN_ROOT}/rules) - proceeding without them."
  fi
  [ -f "${CLAUDE_PLUGIN_ROOT}/CLAUDE.md" ] && add "Toolkit doctrine: read the index at ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md before multi-agent or planned work (binding essences plus per-section files; design rationale in README.md alongside). Subagents do not see this line or the write-time rules above: pass doctrine and rule constraints down in delegation prompts, or add both pointers to your global CLAUDE.md via /setup."
  add "Toolkit standing rule (binds the conductor/main chat only): every file change is delegated to a worker agent, no matter how small; the conductor edits nothing itself unless the human explicitly directs it per instance or TOOLKIT_CONDUCTOR_EDITS=1 is set. Enforced by the conductor-guard hook."
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
  [ -n "$RFALLBACK" ] && add "Rule override(s) empty or unreadable, plugin default used instead:${RFALLBACK}."
  [ -n "$RMISSING" ] && add "Rule file(s) unreadable, no override and no usable plugin default:${RMISSING}."
  [ -n "$RTRUNC" ] && add "Rule body(ies) exceeded the 64KB cap and were truncated to the first 64KB, rest omitted:${RTRUNC}."
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
else
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then RULES_MISSING_PATH="${CLAUDE_PLUGIN_ROOT}/rules"; else RULES_MISSING_PATH="CLAUDE_PLUGIN_ROOT unset"; fi
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

# Compaction escalation: a session that compacts repeatedly re-pays its whole context
# indefinitely. Counted from the transcript (stateless), announced from the 2nd compact.
NCOMPACT=0
if [ "$SOURCE" = "compact" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  NCOMPACT=$(grep -c '"subtype":"compact_boundary"' "$TRANSCRIPT" 2>/dev/null)
  case "$NCOMPACT" in ''|*[!0-9]*) NCOMPACT=0 ;; esac
  if [ "$NCOMPACT" -ge 2 ]; then
    add "This session has now compacted ${NCOMPACT} times. The vault plan/work note is the continuity mechanism, not this conversation: bring the current task to a stable point, update the note with state and next steps, and recommend the user continue in a fresh session instead of riding further compactions."
  fi
fi

# User-visible status line, startup only (skip on resume/clear so it doesn't nag).
STATUS=""
if [ "$SOURCE" = "startup" ]; then
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    VER=$(basename "$CLAUDE_PLUGIN_ROOT")
    case "$VER" in toolkit) VER="";; *) VER=" $VER";; esac  # dev checkout has no version segment
    NA=$(ls "$CLAUDE_PLUGIN_ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
    NS=$(ls -d "$CLAUDE_PLUGIN_ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ -n "$RULES_MISSING_PATH" ] && [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    STATUS="toolkit active — RULES NOT INJECTED (missing ${RULES_MISSING_PATH})"
  elif [ -n "$RULES_MISSING_PATH" ]; then
    STATUS="toolkit${VER} active — RULES NOT INJECTED (missing ${RULES_MISSING_PATH}); ${NA} agents, ${NS} skills"
  elif [ -f "$HOME/.claude/obsidian-sync.json" ]; then
    STATUS="toolkit${VER} active — ${NA} agents, ${NS} skills, planning ready"
  else
    STATUS="toolkit${VER} active — ${NA} agents, ${NS} skills · planning not configured: run /setup"
  fi
elif [ "$NCOMPACT" -ge 2 ]; then
  STATUS="toolkit: session compacted ${NCOMPACT}× — the plan/work note carries the state; consider a fresh session"
fi

# Emit. JSON (with systemMessage) when jq is present; plain-stdout context otherwise.
# $CTX goes through a file (--rawfile), never argv: it can carry an unbounded-size rule
# body and argv is capped by ARG_MAX (jq -n --arg "$CTX" fails past that with invalid JSON).
if command -v jq >/dev/null 2>&1; then
  CTXFILE="$(mktemp 2>/dev/null)"
  if [ -n "$CTXFILE" ] && printf '%s' "$CTX" > "$CTXFILE" 2>/dev/null; then
    jq -n --rawfile ctx "$CTXFILE" --arg sm "$STATUS" \
      'def base: {hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}};
       if $sm=="" then base else base + {systemMessage:$sm} end'
  else
    [ -n "$CTX" ] && printf '%s\n' "$CTX"
  fi
else
  [ -n "$CTX" ] && printf '%s\n' "$CTX"
fi
exit 0
