#!/usr/bin/env bash
# Exercises notify.sh's non-dry-run path with a malicious hook-supplied message
# against each notifier probe (osascript, notify-send, powershell.exe) in turn, plus
# the no-notifier-reachable fallback. Sourced by run-all.sh, which supplies ROOT and
# the PASS/FAIL/FAILED_NAMES counters these add to.

# Alphanumeric-only: no quotes/dashes/spaces for a sanitiser to strip or mangle away.
NOTIFY_SENTINEL="ZZINJECTSENTINEL9174"
NOTIFY_TITLE="Claude Code"
NOTIFY_MESSAGE="Claude Code needs your attention"
NOTIFY_BASH_BIN="$(command -v bash)"

_notify_pass() {
  printf '  PASS  notify :: %s\n' "$1"
  PASS=$((PASS+1))
}

_notify_fail() {
  printf '  FAIL  notify :: %s\n' "$1"
  FAIL=$((FAIL+1))
  FAILED_NAMES+=("notify::$1")
}

# Shebang is the resolved absolute bash path: the stub's own PATH has no "bash" on it.
_notify_write_stub() {
  local name="$1" dir="$2"
  { printf '#!%s\n' "$NOTIFY_BASH_BIN"
    cat <<'STUB'
i=0
for a in "$@"; do
  i=$((i+1))
  printf '%s' "$a" > "$ARGV_DIR/arg$i"
done
echo "$#" > "$ARGV_DIR/count"
STUB
  } >"$dir/$name"
  chmod +x "$dir/$name"
}

# PATH holds only real cat/jq (notify.sh's plumbing) plus one notifier stub, so the other two notifier names stay absent and the probe order actually reaches this branch.
check_notify_stub() {
  local notifier="$1" hook_path="$ROOT/notify.sh"
  local stub_dir argv_dir
  stub_dir="$(mktemp -d)"
  argv_dir="$(mktemp -d)"
  ln -s "$(command -v cat)" "$stub_dir/cat"
  ln -s "$(command -v jq)" "$stub_dir/jq"
  _notify_write_stub "$notifier" "$stub_dir"

  local stdin
  stdin="$(jq -n --arg m "$NOTIFY_SENTINEL" '{message:$m}')"
  printf '%s' "$stdin" \
    | env -u TOOLKIT_NOTIFY_DRYRUN PATH="$stub_dir" ARGV_DIR="$argv_dir" \
      "$NOTIFY_BASH_BIN" "$hook_path" >/dev/null 2>&1

  local count blob i content args
  count="$(cat "$argv_dir/count" 2>/dev/null || echo 0)"
  blob=""
  args=()
  i=1
  while [[ $i -le $count ]]; do
    content="$(cat "$argv_dir/arg$i" 2>/dev/null)"
    args+=("$content")
    blob+="$content"$'\n'
    i=$((i+1))
  done
  rm -rf "$stub_dir" "$argv_dir"

  if [[ "$count" -eq 0 ]]; then
    _notify_fail "$notifier :: stub was never invoked (PATH setup is not exercising this branch)"
    return
  fi
  if [[ "$blob" == *"$NOTIFY_SENTINEL"* ]]; then
    _notify_fail "$notifier :: hook-supplied payload leaked into argv"
    return
  fi

  # Per-slot checks below, not substring-on-blob: NOTIFY_MESSAGE contains NOTIFY_TITLE as
  # a prefix, so a blob substring match would pass even with the title dropped entirely
  # or with title/message swapped between the notifier's title and body positions.
  case "$notifier" in
  osascript|notify-send)
    local title_idx=-1 msg_idx=-1 first second
    for i in "${!args[@]}"; do
      [[ $title_idx -lt 0 && "${args[$i]}" == "$NOTIFY_TITLE" ]] && title_idx=$i
      [[ $msg_idx -lt 0 && "${args[$i]}" == "$NOTIFY_MESSAGE" ]] && msg_idx=$i
    done
    # osascript's `on run {msg, ttl}` binds positionally: message argv slot precedes
    # title. notify-send's `-- "$TITLE" "$MESSAGE"` is the other way round.
    if [[ "$notifier" == "osascript" ]]; then first=$msg_idx; second=$title_idx
    else first=$title_idx; second=$msg_idx; fi
    if [[ $title_idx -lt 0 || $msg_idx -lt 0 ]]; then
      _notify_fail "$notifier :: title/message not present as exact argv elements"
    elif [[ $first -ge $second ]]; then
      _notify_fail "$notifier :: title/message argv elements out of relative order"
    else
      _notify_pass "$notifier :: hook-supplied payload excluded, title/message present as exact argv elements in order"
    fi
    ;;
  powershell.exe)
    local cmd prefix
    cmd="${args[$((count-1))]}"
    prefix="${cmd%%"$NOTIFY_MESSAGE"*}"
    if [[ "$cmd" != *"$NOTIFY_MESSAGE"* ]]; then
      _notify_fail "$notifier :: message missing from -Command argument"
    elif [[ "$prefix" != *"$NOTIFY_TITLE"* ]]; then
      _notify_fail "$notifier :: title missing before message in -Command argument"
    else
      _notify_pass "$notifier :: hook-supplied payload excluded, title precedes message in -Command argument"
    fi
    ;;
  esac
}

# A Notification hook must never obstruct the session: no notifier reachable still exits 0, silent.
check_notify_no_notifier_fallback() {
  local hook_path="$ROOT/notify.sh"
  local empty_dir out exit_code
  empty_dir="$(mktemp -d)"
  out="$(env -u TOOLKIT_NOTIFY_DRYRUN PATH="$empty_dir" "$NOTIFY_BASH_BIN" "$hook_path" </dev/null 2>/dev/null)"
  exit_code=$?
  rm -rf "$empty_dir"

  if [[ $exit_code -eq 0 && -z "$out" ]]; then
    _notify_pass "no notifier reachable :: exits 0 with empty stdout"
  else
    _notify_fail "no notifier reachable :: exits 0 with empty stdout (got exit=$exit_code, stdout=$out)"
  fi
}

run_notify_checks() {
  local notifier
  for notifier in osascript notify-send powershell.exe; do
    check_notify_stub "$notifier"
  done
  check_notify_no_notifier_fallback
}
