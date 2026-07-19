#!/bin/bash
# Scans file content for accidental secrets before writing.
# Used as a PreToolUse hook for Edit|Write operations.
# Exit 2 = block. Exit 0 = allow.

# Requires jq for JSON parsing. Allow if missing (don't block the user)
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Extract the content being written. The Edit|Write matcher also routes MultiEdit
# (its name contains "Edit"); NotebookEdit uses new_source — both were previously
# unscanned, so a secret written via either slipped past.
case "$TOOL_NAME" in
  Write)        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty') ;;
  Edit)         CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty') ;;
  MultiEdit)    CONTENT=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")') ;;
  NotebookEdit) CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_source // empty') ;;
  *) exit 0 ;;
esac

if [ -z "$CONTENT" ]; then
  exit 0
fi

# --- High-confidence secret patterns ---

MATCHES=""

# AWS Access Key IDs
if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  MATCHES="$MATCHES AWS access key (AKIA...);"
fi

# AWS Secret Access Keys (40 chars base64 after a key assignment)
if echo "$CONTENT" | grep -qiE '(aws_secret_access_key|secret_key)[[:space:]]*[=:][[:space:]]*["'\''"]?[A-Za-z0-9/+=]{40}'; then
  MATCHES="$MATCHES AWS secret key;"
fi

# GitHub tokens (PAT, OAuth, App)
if echo "$CONTENT" | grep -qE '(ghp_|gho_|ghs_|ghr_|github_pat_)[a-zA-Z0-9_]{20,}'; then
  MATCHES="$MATCHES GitHub token;"
fi

# OpenAI / Stripe / Anthropic style keys (sk-..., incl. hyphenated sk-ant-api03-...)
if echo "$CONTENT" | grep -qE 'sk-[a-zA-Z0-9-]{20,}'; then
  MATCHES="$MATCHES API key (sk-...);"
fi

# Slack tokens
if echo "$CONTENT" | grep -qE 'xox[bpras]-[0-9a-zA-Z-]{10,}'; then
  MATCHES="$MATCHES Slack token;"
fi

# Private key blocks
if echo "$CONTENT" | grep -qE -- '-----BEGIN[[:space:]]+(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
  MATCHES="$MATCHES private key block;"
fi

# Connection strings with embedded credentials
if echo "$CONTENT" | grep -qE '(mongodb|postgres|mysql|redis|amqp|smtp)(\+[a-z]+)?://[^:[:space:]]+:[^@[:space:]]+@'; then
  MATCHES="$MATCHES connection string with credentials;"
fi

# Generic credential assignments with a QUOTED literal value. Broadened name set
# (passwd, db_pass, creds, bearer, private_key, ... — not just the original six).
# Deliberately quoted-only: unquoted values (`password: required`, `token: application/json`)
# are too low-signal for an advisory hook and train prompt-fatigue; genuinely dangerous
# UNQUOTED secrets have distinctive shapes (AWS/GitHub/sk-/PEM/connection-string) and
# are caught by those rules above regardless of quoting.
# Excludes env references. A double-quoted `"$VAR"` is a shell expansion (excluded); a
# single-quoted '$literal' is a real literal (NOT excluded — the old `["']?$` over-excluded it).
# Evaluated per line so an env reference on one line can't suppress a literal on another.
if echo "$CONTENT" | grep -iE '(password|passwd|secret|secret_key|token|access_token|api_key|apikey|api_secret|client_secret|credential|creds|bearer|auth_token|private_key|db_pass[a-z]*)[[:space:]]*[=:][[:space:]]*["'\''][^"'\'']{8,}["'\'']' | \
   grep -qivE '[=:][[:space:]]*(["'\'']?(process\.env|os\.environ|getenv|ENV\[|env\(|import\.meta)|"\$\{?[A-Za-z_])'; then
  MATCHES="$MATCHES hardcoded credential;"
fi

if [ -n "$MATCHES" ]; then
  # Use "ask" not "deny". Warn the user but let them override (could be test fixtures)
  REASON="Possible secret detected in content:$MATCHES Review carefully before allowing."
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"$REASON\"}}"
  exit 0
fi

exit 0
