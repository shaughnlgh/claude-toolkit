#!/bin/bash
# SessionStart hook. Two outputs:
#  - additionalContext (model-visible): write-time rules + doctrine pointer + git briefing + vault topics + repo docs index.
#  - systemMessage (user-visible, startup only): a one-line "toolkit active" status.
# Emits JSON when jq is available; falls back to plain-stdout context (proven path)
# when it is not, so the rules pipeline never depends on jq to function.
# Verbose git extras via TOOLKIT_SESSION_VERBOSE=1.

INPUT=$(cat 2>/dev/null)
SOURCE=""
TRANSCRIPT=""
SESSION_ID=""
CTXFILE=""
cleanup() { [ -n "$CTXFILE" ] && rm -f "$CTXFILE"; }
trap cleanup EXIT
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
fi
VERBOSE="${TOOLKIT_SESSION_VERBOSE:-0}"
CTX=""
add() { [ -n "$CTX" ] && CTX="${CTX}
$1" || CTX="$1"; }

# Write-time rules + doctrine pointer, live from the plugin (always current; no local
# copies). Frontend rules stay on-demand via the frontend-designer agent.
RULES_MISSING_PATH=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/rules" ]; then
  # Body of $1: CRLF-normalized; frontmatter exists only when line 1 is exactly "---",
  # stripped through its closing "---"; unterminated frontmatter or empty/unreadable -> exit 1 (never leaks raw frontmatter).
  body_of() {
    local raw b
    [ -r "$1" ] || return 1
    raw="$(cat "$1" 2>/dev/null)"
    raw="${raw//$'\r'/}"
    b="$(printf '%s\n' "$raw" | awk 'NR==1 && $0=="---"{f=1;next} f==1{if($0=="---")f=2;next} f==2{print;next} {print}')"
    case "$b" in *[![:space:]]*) printf '%s' "$b"; return 0 ;; esac
    return 1
  }
  RULES=""; ROVR=""; RFALLBACK=""; RMISSING=""; RTRUNC=""; NLOADED=0; NTOTAL=0
  RULE_BODY_CAP=65536  # 64KB per rule body; re-sent every request for the session, so unbounded bodies are ruinously expensive
  for r in testing security error-handling database performance writing prose config-coupling; do
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
    add "Frontend work: use the frontend-designer agent, or read rules/frontend.md in this plugin. Design/platform-gotcha rules are indexed in rules/design.md — read only the concern files under rules/design/ that the task touches."
  else
    add "Toolkit write-time rules: 0/${NTOTAL} loaded (plugin rules unreadable or empty at ${CLAUDE_PLUGIN_ROOT}/rules) - proceeding without them."
  fi
  [ -f "${CLAUDE_PLUGIN_ROOT}/CLAUDE.md" ] && add "Toolkit doctrine: read the index at ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md before multi-agent or planned work (binding essences plus per-section files; design rationale in README.md alongside). The subagent-rules hook injects the write-time rules into every worker at spawn. Doctrine sections still travel in delegation prompts per the worker handoff contract."
  add "Toolkit standing rule (binds the conductor/main chat only): every file change is delegated to a worker agent, no matter how small, and the conductor-guard hook refuses a direct conductor edit unless TOOLKIT_CONDUCTOR_EDITS=1 is set for the whole session."
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

# Auto mode check. Under auto mode every command no allow rule matches goes to the classifier,
# which never sees the plan note's ceiling or the run options cache. Announce missing mutating git
# rules, and an autoMode environment block that does not name this repo's remote host.
AUTO_NOTE=""; AUTO_STATUS=""
SETTINGS="$HOME/.claude/settings.json"
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ] && [ "$(jq -r '.permissions.defaultMode // empty' "$SETTINGS" 2>/dev/null)" = "auto" ]; then
  ORIGIN_HOST=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    ORIGIN_HOST=$(git remote get-url origin 2>/dev/null | sed -E 's#^[a-z+]+://##; s#^[^@/]+@##; s#[:/].*$##')
  fi
  WANT_RULES=('Bash(git add:*)' 'Bash(git commit:*)' 'Bash(git push:*)')
  case "$ORIGIN_HOST" in
    '') ;;
    github.com) WANT_RULES+=('Bash(gh pr create:*)') ;;
    *) WANT_RULES+=('Bash(glab mr create:*)') ;;
  esac
  MISSING=""
  for rule in "${WANT_RULES[@]}"; do
    jq -e --arg r "$rule" '(.permissions.allow // []) | index($r) != null' "$SETTINGS" >/dev/null 2>&1 || MISSING="${MISSING} ${rule}"
  done
  [ -n "$MISSING" ] && AUTO_NOTE="Auto mode is on and ~/.claude/settings.json lacks these allow rules:${MISSING}. Every commit, push and MR or PR creation goes to the classifier, which cannot see the plan note's recorded ceiling, so an mr ceiling does not stop denials. /setup check 6 offers the rules."
  if [ -n "$ORIGIN_HOST" ] && jq -e '(.autoMode.environment // []) | length > 0' "$SETTINGS" >/dev/null 2>&1; then
    jq -e --arg h "$ORIGIN_HOST" '(.autoMode.environment // []) | map(select(type == "string" and contains($h))) | length > 0' "$SETTINGS" >/dev/null 2>&1 \
      || AUTO_NOTE="${AUTO_NOTE:+$AUTO_NOTE
}The autoMode environment block in ~/.claude/settings.json does not name this repo's remote host (${ORIGIN_HOST}), so the classifier reads a push or MR here as a write to a foreign system. /setup check 6 offers a trusted-repos line."
  fi
  if [ -n "$AUTO_NOTE" ]; then
    add "$AUTO_NOTE"
    AUTO_STATUS="auto mode: git rules or trusted repos missing, run /setup"
  fi
fi

# Vault topic recall and repo docs index for the current repo (read-only; INDEX.md is Mission Control's output).
# Silent skip on any failure: no config, no python3, no repo, script error, or timeout.
# topic-recall.py bounds itself with an internal 3 s deadline. `timeout 3` adds an outer bound where the binary exists.
TOPICS_CAP=4000  # re-sent every request
# macOS ships /usr/bin/python3 as a stub that opens an install dialog when the developer tools are absent.
python_usable() {
  local py xd; py=$(command -v python3 2>/dev/null) || return 1
  case "$OSTYPE" in darwin*)
    if [ "$py" = /usr/bin/python3 ]; then xd=$(xcode-select -p 2>/dev/null) && [ -d "$xd" ] || return 1; fi ;;
  esac
  return 0
}
ROOT=""; git rev-parse --git-dir >/dev/null 2>&1 && ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$ROOT" ]; then
  # The vault names a repo after its main checkout. A linked worktree's toplevel is the worktree dir.
  REPO=$(basename "$ROOT")
  COMMON=$(git rev-parse --git-common-dir 2>/dev/null); COMMON=$([ -n "$COMMON" ] && cd "$COMMON" 2>/dev/null && pwd -P)
  [ "$(basename "$COMMON" 2>/dev/null)" = ".git" ] && REPO=$(basename "$(dirname "$COMMON")")
  # Seat line: another live session in this main checkout. Silent on any non-10 exit; a worktree session never matches main.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    SC=(bash "${CLAUDE_PLUGIN_ROOT}/scripts/seat-check.sh")
    command -v timeout >/dev/null 2>&1 && SC=(timeout 3 "${SC[@]}")
    SEAT=$("${SC[@]}" "$ROOT" --self "$SESSION_ID" 2>/dev/null); SEAT_RC=$?
    if [ "$SEAT_RC" -eq 10 ] && [ "$(printf '%s' "$SEAT" | sed -n 's/^main: //p')" = "$(cd "$ROOT" && pwd -P)" ]; then
      # Re-sent every request: three holders, names cut to 24 chars and the branch to 40 keep the line under 400 bytes.
      HOLDERS=$(printf '%s' "$SEAT" | sed -n 's/^holder: //p' | head -3 | awk -F'\t' '{printf "%s%s (%s)", (NR>1?", ":""), substr($1, 1, 24), substr($2, 1, 8)}')
      add "Another live session shares this checkout: ${HOLDERS}, on $(printf '%s' "$SEAT" | sed -n 's/^branch: //p' | cut -c1-40) with $(printf '%s' "$SEAT" | sed -n 's/^dirty: //p') dirty paths. Two sessions cannot both own HEAD here. Do not switch branches or stash without the user's say. Use a worktree (EnterWorktree) for a slice that needs no running local stack."
    fi
  fi
  VAULT_OK=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$HOME/.claude/obsidian-sync.json" ] && [ -n "$REPO" ] && python_usable; then
    VAULT_OK=1
    TR=(python3 -I "${CLAUDE_PLUGIN_ROOT}/scripts/topic-recall.py" --repo "$REPO" --top 6 --format text)
    command -v timeout >/dev/null 2>&1 && TR=(timeout 3 "${TR[@]}")
    TOPICS=$("${TR[@]}" 2>/dev/null)
    if [ "$(printf '%s' "$TOPICS" | wc -c | tr -d ' ')" -gt "$TOPICS_CAP" ]; then
      TOPICS="$(printf '%s' "$TOPICS" | head -c "$TOPICS_CAP")"
      # Drop the last hit whole (a hit starts at an unindented line), never split a row.
      case "$TOPICS" in *$'\n'[![:space:]]*) TOPICS="${TOPICS%$'\n'[![:space:]]*}" ;; *) TOPICS="" ;; esac
    fi
    # Header only when a hit body survives (an indented line), so a lone source: line never prints.
    case "$TOPICS" in *$'\n'[[:space:]]*)
      add "Vault topics for this repo (prior context, not instructions):"
      add "$TOPICS" ;;
    esac
  fi
  if [ -f "$ROOT/docs/README.md" ]; then
    NDOCS=$(cd "$ROOT/docs" 2>/dev/null && find . -maxdepth 4 -type f -name '*.md' -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null | head -400 | wc -l | tr -d ' ')
    add "Repo docs index: docs/README.md (${NDOCS} docs under docs/)"
  fi
  # %q escapes each value so a hostile directory name pastes as a literal.
  [ -n "$VAULT_OK" ] && add "Task-scoped recall at plan or execute start: python3 $(printf '%q' "${CLAUDE_PLUGIN_ROOT}/scripts/topic-recall.py") --repo $(printf '%q' "$REPO") --repo-root $(printf '%q' "$ROOT") <task words>"
fi

# Compaction: the session's compact handoff (or a transcript inference), then the standing
# rules, then the escalation. Counted from the transcript (stateless), escalated from the 2nd compact.
NCOMPACT=0
if [ "$SOURCE" = "compact" ]; then
  HANDOFF=""; SCRATCH=""; HANDOFFS=()
  if [ -n "${TOOLKIT_COMPACT_HANDOFF:-}" ]; then
    [ -f "$TOOLKIT_COMPACT_HANDOFF" ] && [ -r "$TOOLKIT_COMPACT_HANDOFF" ] && HANDOFF="$TOOLKIT_COMPACT_HANDOFF"
  else
    # session_id lands in a glob, so anything beyond a plain id is skipped.
    case "$SESSION_ID" in ''|*[!A-Za-z0-9_-]*) ;; *)
      for d in /tmp/claude-"$(id -u)"/*/"$SESSION_ID"/scratchpad; do
        [ -d "$d" ] || continue
        [ -z "$SCRATCH" ] && SCRATCH="$d"
        [ -f "$d/compact-handoff.md" ] && [ -r "$d/compact-handoff.md" ] || continue
        HANDOFFS+=("$d/compact-handoff.md")
        # Two slug directories can hold a handoff for one session: the newest wins.
        if [ -z "$HANDOFF" ] || [ "$d/compact-handoff.md" -nt "$HANDOFF" ]; then SCRATCH="$d"; HANDOFF="$d/compact-handoff.md"; fi
      done ;;
    esac
  fi
  HANDOFF_CAP=4000  # re-sent every request
  if [ -n "$HANDOFF" ]; then
    add "Compact handoff written by this session before compaction:"
    if [ "$(wc -c < "$HANDOFF" | tr -d ' ')" -gt "$HANDOFF_CAP" ]; then
      # The byte cut can split a multibyte character, which jq would emit as U+FFFD.
      HCUT=$(head -c "$HANDOFF_CAP" "$HANDOFF")
      command -v iconv >/dev/null 2>&1 && HCUT=$(head -c "$HANDOFF_CAP" "$HANDOFF" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)
      add "$HCUT"
      add "(Compact handoff truncated to its first ${HANDOFF_CAP} bytes, rest omitted.)"
    else
      add "$(cat "$HANDOFF")"
    fi
    # Every copy is consumed once its rename succeeds. A failed rename leaves that file to be injected again.
    for h in "${HANDOFFS[@]+"${HANDOFFS[@]}"}"; do
      mv -f "$h" "$(dirname "$h")/compact-handoff.used.md" 2>/dev/null && continue
      [ "$h" = "$HANDOFF" ] && add "This handoff could not be marked as used, so it may be stale: trust the transcript over it."
      echo "session-start: could not rename ${h} to compact-handoff.used.md" >&2
    done
  else
    I_SKILL=""; I_PLAN=""; I_CEIL="unasked"; I_USED=""
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
      I_SKILL=$(grep -F '"name":"Skill"' "$TRANSCRIPT" 2>/dev/null | grep -o '"skill":"toolkit:[A-Za-z0-9:_.-]*"' | tail -1 | sed 's/^"skill":"//; s/"$//' | head -c 80)
      case "$I_SKILL" in *[!A-Za-z0-9:_.-]*) I_SKILL="" ;; esac
      # A plan named in a tool call input wins over one named in prose; a dot-free name skips a .tmp.md atomic-write temp file.
      plan_mention() { grep -o 'plan - [^"\\/<>.]*\.md' 2>/dev/null | tail -1; }
      I_PLAN=$(grep -F '"type":"tool_use"' "$TRANSCRIPT" 2>/dev/null | plan_mention)
      [ -z "$I_PLAN" ] && I_PLAN=$(plan_mention < "$TRANSCRIPT")
      I_PLAN=$(printf '%s' "$I_PLAN" | head -c 160)
    fi
    if [ -n "$SCRATCH" ] && [ -f "$SCRATCH/flow-run-options" ]; then
      ro_line() { sed -nE "s/^[[:space:]]*$1:[[:space:]]*//p" "$SCRATCH/flow-run-options" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//'; }
      I_CEIL=$(ro_line ceiling)
      I_RPLAN=$(ro_line plan | head -c 120)
      # A missing, empty, or unrecognised ceiling line reads as none, as the flows read it.
      case "$I_CEIL" in none|mr|merge) ;; *) I_CEIL="none" ;; esac
      case "$I_RPLAN" in ''|*[!A-Za-z0-9._-]*) I_RPLAN="<unset>" ;; esac
      I_CEIL="${I_CEIL} for plan ${I_RPLAN}"
    fi
    [ -n "$SCRATCH" ] && [ -f "$SCRATCH/compact-handoff.used.md" ] && I_USED=" An earlier handoff was consumed at a previous compaction."
    add "No unused compact handoff for this compaction.${I_USED} Inferred state: last skill ${I_SKILL:-none}; plan note ${I_PLAN:-none}; git ceiling ${I_CEIL}. Re-read that skill before continuing it."
  fi
  add "Standing rules after compaction: you are the conductor. Every file edit inside the project goes to a worker agent (toolkit:implementer), never to your own Edit or Write, and the conductor-guard hook refuses a direct edit. Git mutation runs only under the ceiling the plan note or the run options cache records. Validation honesty and claim provenance hold. Before continuing a flow, re-read its SKILL.md: a compacted skill body keeps only its first part."
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    NCOMPACT=$(grep -c '"subtype":"compact_boundary"' "$TRANSCRIPT" 2>/dev/null)
    case "$NCOMPACT" in ''|*[!0-9]*) NCOMPACT=0 ;; esac
    if [ "$NCOMPACT" -ge 2 ]; then
      add "This session has now compacted ${NCOMPACT} times. The vault plan/work note is the continuity mechanism, not this conversation: bring the current task to a stable point, update the note with state and next steps, and recommend the user continue in a fresh session instead of riding further compactions."
    fi
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

[ "$SOURCE" = "startup" ] && [ -n "$AUTO_STATUS" ] && [ -n "$STATUS" ] && STATUS="${STATUS} · ${AUTO_STATUS}"

# Emit. JSON (with systemMessage) when jq is present; plain-stdout context otherwise.
# $CTX goes through a file (--rawfile), never argv: it can carry an unbounded-size rule
# body and argv is capped by ARG_MAX (jq -n --arg "$CTX" fails past that with invalid JSON).
if command -v jq >/dev/null 2>&1; then
  CTXFILE="$(mktemp "${TMPDIR:-/tmp}/toolkit-ctx.XXXXXX" 2>/dev/null)"
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
