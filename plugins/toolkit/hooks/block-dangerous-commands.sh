#!/usr/bin/env bash
# Blocks dangerous shell commands: push to protected branches, force push,
# destructive operations. PreToolUse hook for Bash operations.
# Exit 2 = block. Exit 0 = allow.
#
# Configurable via env:
#   CLAUDE_PROTECTED_BRANCHES  comma list (default: derived from git + main,master)

set -uo pipefail

emit_deny() {
  # Emit a JSON deny decision and exit 2.
  local reason="${1//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  emit_deny "jq is required for command protection hooks but is not installed."
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

# ── Protected branch list ────────────────────────────────────────────────
DEFAULT_BRANCHES="main,master"
if GIT_DEFAULT=$(git config --get init.defaultBranch 2>/dev/null) && [ -n "$GIT_DEFAULT" ]; then
  DEFAULT_BRANCHES="$DEFAULT_BRANCHES,$GIT_DEFAULT"
fi
PROTECTED_BRANCHES="${CLAUDE_PROTECTED_BRANCHES:-$DEFAULT_BRANCHES}"
# Build a regex alternation: main|master|develop|...
BR_REGEX=$(printf '%s' "$PROTECTED_BRANCHES" | tr ',' '\n' | awk 'NF{printf "%s%s",sep,$0; sep="|"}')

contains_cmd() { printf '%s' "$COMMAND" | grep -qE "$1"; }
contains_icmd() { printf '%s' "$COMMAND" | grep -qiE "$1"; }

# ── Git push protections ────────────────────────────────────────────────
if contains_cmd '(^|[;&|()]+[[:space:]]*)git[[:space:]]+push'; then
  # Inspect EVERY `git push` clause in a compound command (quotes stripped so `"main"`
  # is seen as main), so a safe push followed by a protected/forced one is still caught.
  # Each clause is token-parsed rather than regex-scanned: flags are skipped (options
  # that consume a separate value skip it too); with no --repo the first non-flag token
  # is the remote and the rest are refspecs; with --repo (=value or separate value)
  # there is no positional remote so every non-flag token is a refspec. A refspec's
  # DESTINATION is the part after the last ':' with a leading '+' and 'refs/heads/'
  # stripped. Raw --force/-f is blocked even alongside --force-with-lease; a lone
  # --force-with-lease is allowed. `git push main feature-x` (main is the remote) and
  # `git push origin feature/main` (a branch merely named so) stay allowed.
  while IFS= read -r clause; do
    V=$(printf '%s' "$clause" | awk -v br="$BR_REGEX" '
      { n=split($0,t,/[[:space:]]+/); pi=0
        for(i=1;i<=n;i++) if(t[i]=="push"){pi=i;break}
        remote=""; refs=0; bad=0; rawforce=0; bb="-"; haverepo=0; i=pi+1
        while(i<=n){ tok=t[i]
          if(tok=="--repo"){ haverepo=1; i+=2; continue }
          if(tok ~ /^--repo=/){ haverepo=1; i++; continue }
          if(tok ~ /^(--push-option|--receive-pack|--exec|-o)$/){ i+=2; continue }
          if(tok=="--force" || tok ~ /^-[a-zA-Z]*f[a-zA-Z]*$/){ rawforce=1; i++; continue }
          if(tok ~ /^-/){ i++; continue }
          if(remote=="" && !haverepo){ remote=tok; i++; continue }
          refs++; dest=tok; sub(/^.*:/,"",dest); sub(/^\+/,"",dest); sub(/^refs\/heads\//,"",dest)
          if(dest ~ ("^(" br ")$")){ bad=1; bb=dest }
          i++ }
        print bad" "rawforce" "refs" "bb }')
    set -- $V; PBAD="${1:-0}"; PFORCE="${2:-0}"; PREFS="${3:-0}"; PBB="${4:--}"
    [ "$PBAD" = "1" ] && emit_deny "Blocked: push affecting protected branch '$PBB'. Use a feature branch and open a PR."
    [ "$PFORCE" = "1" ] && emit_deny "Blocked: force push is not allowed. Use --force-with-lease if you must overwrite remote."
    # A push naming no branch (`git push`, `git push -u`, `git push origin`) while the
    # current branch is protected.
    if [ "$PREFS" = "0" ]; then
      CURRENT=$(git branch --show-current 2>/dev/null || true)
      if [ -n "$CURRENT" ] && printf '%s' ",$PROTECTED_BRANCHES," | grep -q ",$CURRENT,"; then
        emit_deny "Blocked: you are on '$CURRENT' (a protected branch). Switch to a feature branch."
      fi
    fi
  done < <(printf '%s' "$COMMAND" | tr -d "'\"" | grep -oE 'git[[:space:]]+push[^;&|]*')
fi

# ── Destructive filesystem operations ───────────────────────────────────
# rm with BOTH recursive AND force, in any flag arrangement (combined `-rf`,
# separate `-r -f`, long `--recursive --force`), targeting a dangerous path.
# Quotes are stripped first so "my dir" and '$HOME' are inspected. The old single
# regex required r and f in one token and missed split/long flags entirely.
CMD_NOQUOTE=$(printf '%s' "$COMMAND" | tr -d "'\"")
while IFS= read -r seg; do
  # recursive: -r, -R, -rf, --recursive (uppercase -R is BSD/GNU-valid); force: -f, --force
  printf '%s' "$seg" | grep -qE '([[:space:]]--recursive|[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*)([[:space:]]|$)' || continue
  printf '%s' "$seg" | grep -qE '([[:space:]]--force|[[:space:]]-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)' || continue
  # Dangerous targets: /, ~, a $VAR / ${VAR} expansion, bare . / .. / *, a system
  # directory, or any path containing a /../ traversal segment (e.g. /tmp/../).
  if printf '%s' "$seg" | grep -qE '(^|[[:space:]])(/([[:space:]]|$)|/(usr|etc|var|bin|sbin|lib|opt|root|boot)([[:space:]/]|$)|~|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\.\.?/?([[:space:]]|$)|\*([[:space:]]|$)|[^[:space:]]*/\.\.(/|[[:space:]]|$))'; then
    emit_deny "Blocked: recursive force-delete of a dangerous target (/, ~, \$VAR, .., ., *, a /../ traversal, or a system dir). Specify a concrete safe path."
  fi
# Boundary allows a path/escape prefix so `/bin/rm` and `\rm` (which bypass a plain
# alias) are still inspected, not just a bare `rm`.
done < <(printf '%s\n' "$CMD_NOQUOTE" | grep -oE '(^|[;&|/[:space:]\])rm[[:space:]]+[^;&|]*')

# ── Dangerous database operations ───────────────────────────────────────
# Only inspect SQL when a database CLIENT is actually being invoked — otherwise
# `git grep "delete from"` or `echo "please truncate the log"` would hard-deny (this
# hook has no ask path). The keyword checks below stay case-insensitive and comment-
# stripped so real lowercase/quoted SQL run through a client is still caught.
# The client-name boundary includes '/' so an absolute path (`/usr/bin/psql`) is recognized.
if contains_icmd '(^|[;&|/[:space:]])(mysql|mariadb|psql|sqlite3?|mongosh?|clickhouse-client|cockroach|sqlcmd|usql)([[:space:]]|$)'; then
  # DROP TABLE|DATABASE|SCHEMA
  if contains_icmd 'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)[[:space:]]+'; then
    emit_deny "Blocked: DROP TABLE/DATABASE/SCHEMA detected. Run manually if intended."
  fi
  # DELETE FROM without a WHERE on the SAME statement, split on ';'. Uppercased (BSD awk
  # ignores gawk IGNORECASE). SQL comments are stripped from the PAYLOAD only: a `--`
  # line comment must be followed by whitespace/end (so a CLI option like `--command`
  # is NOT mistaken for a comment), plus `/* ... */` block comments. WHERE is matched as
  # a whole word so a `WHERE` inside a comment (already stripped) or a longer word
  # (`NOWHERE`) doesn't satisfy the guard.
  if printf '%s' "$COMMAND" | awk '
    BEGIN { RS=";" }
    { s = toupper($0);
      gsub(/\/\*.*\*\//, " ", s);            # /* block comments */ (greedy; fine for detection)
      gsub(/--[[:space:]][^\n]*/, " ", s);   # -- line comment: needs a space, so CLI --options are safe
      if (s ~ /DELETE[ \t\n]+FROM[ \t\n]/ && s !~ /(^|[^A-Z])WHERE([^A-Z]|$)/) { print "BAD"; exit } }
  ' | grep -q BAD; then
    emit_deny "Blocked: DELETE FROM without a WHERE clause. Add a WHERE or run manually."
  fi
  # TRUNCATE, with or without the optional TABLE keyword (Postgres/MySQL omit it).
  if contains_icmd 'TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[A-Za-z_`"]'; then
    emit_deny "Blocked: TRUNCATE detected. Run manually if intended."
  fi
fi

# ── Dangerous system commands ───────────────────────────────────────────
# chmod granting world/broad write: a numeric mode (3-4 octal digits) whose world
# digit has the write bit (2,3,6,7 → e.g. 777, 666, 1777, 0666), or a symbolic mode
# adding write for others/all (o+w, a+rwx, ugo+w). The old check was only exact 777/a+rwx.
if contains_cmd 'chmod([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[0-7]{2,3}[2367]([[:space:]]|$)' \
  || contains_cmd 'chmod([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[ugoa]*[oa][ugoa]*[+=][a-z]*w'; then
  emit_deny "Blocked: chmod granting world/broad write access. Use restrictive perms."
fi

# curl/wget piped to a shell
if contains_cmd '(curl|wget)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|ksh|fish|dash|csh)([[:space:]]|$)'; then
  emit_deny "Blocked: piping downloaded content directly to a shell is dangerous."
fi

# Disk / partition. Only REDIRECTIONS to a raw /dev/ node are destructive. Each
# redirect target is evaluated INDIVIDUALLY — a harmless `2>/dev/null` in the same
# command must not suppress a destructive `1>/dev/sda` elsewhere (the old single
# whole-command negative match did exactly that). An optional leading fd (`1>`,
# `&>`) is part of the match; the fd-null family is the only allowed target.
while IFS= read -r redir; do
  dev=${redir##*/dev/}
  case "$dev" in null|stdout|stderr|tty|zero|random|urandom) continue ;; esac
  emit_deny "Blocked: redirection into a raw device file can destroy data."
done < <(printf '%s' "$COMMAND" | grep -oE '[0-9]*&?>[[:space:]]*/dev/[a-zA-Z][a-zA-Z0-9]*')
if contains_cmd '(^|[;&|[:space:]])(mkfs|mkfs\.[a-z0-9]+)([[:space:]]|$)' \
  || contains_cmd '(^|[;&|[:space:]])dd[[:space:]]+[^|]*(if|of)=/dev/[a-zA-Z]' ; then
  emit_deny "Blocked: mkfs/dd against a device node. Irreversible data loss."
fi

# ── Destructive git ─────────────────────────────────────────────────────
if contains_cmd 'git[[:space:]]+reset[[:space:]]+--hard'; then
  emit_deny "Blocked: git reset --hard discards uncommitted changes permanently."
fi
if contains_cmd 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f'; then
  emit_deny "Blocked: git clean -f permanently deletes untracked files."
fi

# ── Accidental package publishing ───────────────────────────────────────
# Allow --dry-run variants (npm publish --dry-run is safe and common in CI).
publish_patterns=(
  '(npm|yarn|pnpm|bun)[[:space:]]+publish'
  'cargo[[:space:]]+publish'
  'gem[[:space:]]+push'
  'twine[[:space:]]+upload'
)
for pat in "${publish_patterns[@]}"; do
  if contains_cmd "$pat" && ! contains_cmd '(^|[[:space:]])(--dry-run|-n)([[:space:]=]|$)'; then
    emit_deny "Blocked: publishing packages should run in CI or manually, not via Claude."
  fi
done

exit 0
