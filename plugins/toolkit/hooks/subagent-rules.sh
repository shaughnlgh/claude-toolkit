#!/bin/bash
# SubagentStart hook. Injects toolkit write-time rules into every spawned worker's context,
# since subagents don't see the SessionStart injection of the conductor that spawned them.
# Emits JSON when jq is available; falls back to plain-stdout context (proven path)
# when it is not, so the rules pipeline never depends on jq to function.

INPUT=$(cat 2>/dev/null)  # drain stdin so the harness's payload write never blocks or EPIPEs

CTXFILE=""
cleanup() { [ -n "$CTXFILE" ] && rm -f "$CTXFILE"; }
trap cleanup EXIT

CTX=""
add() { [ -n "$CTX" ] && CTX="${CTX}
$1" || CTX="$1"; }

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
    if [ -e "$ovf" ] || [ -L "$ovf" ]; then
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
    add "These are write-time rules for artifacts you produce. They are not review dimensions: do not report violations of them as findings unless your task says to."
    [ -f "${CLAUDE_PLUGIN_ROOT}/CLAUDE.md" ] && add "Toolkit doctrine: read the index at ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md. Before writing code, read doctrine/minimalism.md and doctrine/design.md."
    add "Frontend work: read rules/frontend.md in this plugin. Design/platform-gotcha rules are indexed in rules/design.md."
    [ -n "$ROVR" ] && add "Rule overrides active. Your global ~/.claude/rules/ versions were injected above instead of the plugin defaults:${ROVR}."
    [ -n "$RFALLBACK" ] && add "Rule override(s) empty or unreadable, plugin default used instead:${RFALLBACK}."
    [ -n "$RMISSING" ] && add "Rule file(s) unreadable, no override and no usable plugin default:${RMISSING}."
    [ -n "$RTRUNC" ] && add "Rule body(ies) exceeded the 64KB cap and were truncated to the first 64KB, rest omitted:${RTRUNC}."
    add "Apply these rules to every artifact you write in this task."
  else
    # Zero rules loaded: a half-extracted plugin update must be visible to the worker, so
    # this diagnostic still goes out (mirrors session-start.sh's own zero-loaded line), but
    # without the framing lines or the "apply these rules" directive over zero rule content.
    add "Toolkit write-time rules: 0/${NTOTAL} loaded (plugin rules unreadable or empty at ${CLAUDE_PLUGIN_ROOT}/rules) - proceeding without them."
  fi
fi

# Fail open: no plugin root / no rules dir means no context, and no output at all.
[ -z "$CTX" ] && exit 0

# $CTX goes through a file (--rawfile), never argv: it can carry an unbounded-size rule
# body and argv is capped by ARG_MAX (jq -n --arg "$CTX" fails past that with invalid JSON).
if command -v jq >/dev/null 2>&1; then
  CTXFILE="$(mktemp "${TMPDIR:-/tmp}/toolkit-subagent-ctx.XXXXXX" 2>/dev/null)"
  if [ -n "$CTXFILE" ] && printf '%s' "$CTX" > "$CTXFILE" 2>/dev/null; then
    jq -n --rawfile ctx "$CTXFILE" \
      '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$ctx}}'
  else
    printf '%s\n' "$CTX"
  fi
else
  printf '%s\n' "$CTX"
fi
exit 0
