#!/usr/bin/env bash
# Exercises notify.sh's non-dry-run osascript path with a malicious hook-supplied
# message and asserts none of that payload ever reaches the stubbed osascript's argv —
# the property the fixed-message design guarantees. Sourced by run-all.sh, which
# supplies ROOT and the PASS/FAIL/FAILED_NAMES counters this adds to.

check_notify_osascript_argv() {
  local hook_path="$ROOT/notify.sh"
  local stub_dir argv_dir
  stub_dir="$(mktemp -d)"
  argv_dir="$(mktemp -d)"

  cat >"$stub_dir/osascript" <<'STUB'
#!/usr/bin/env bash
i=0
for a in "$@"; do
  i=$((i+1))
  printf '%s' "$a" > "$ARGV_DIR/arg$i"
done
echo "$#" > "$ARGV_DIR/count"
STUB
  chmod +x "$stub_dir/osascript"

  local payload stdin
  payload='-eproperty p : (do shell script "touch /tmp/notify-argv-check-marker")'
  stdin="$(jq -n --arg m "$payload" '{message:$m}')"

  printf '%s' "$stdin" \
    | env -u TOOLKIT_NOTIFY_DRYRUN PATH="$stub_dir:$PATH" ARGV_DIR="$argv_dir" bash "$hook_path" >/dev/null 2>&1

  local count blob i content
  count="$(cat "$argv_dir/count" 2>/dev/null || echo 0)"
  blob=""
  i=1
  while [[ $i -le $count ]]; do
    content="$(cat "$argv_dir/arg$i" 2>/dev/null)"
    blob+="$content"$'\n'
    i=$((i+1))
  done

  rm -rf "$stub_dir" "$argv_dir"

  if [[ "$count" -gt 0 && "$blob" != *"$payload"* ]]; then
    printf '  PASS  notify :: hook-supplied message never reaches osascript argv\n'
    PASS=$((PASS+1))
  else
    printf '  FAIL  notify :: hook-supplied message never reaches osascript argv (stub invoked=%s)\n' \
      "$([[ "$count" -gt 0 ]] && echo yes || echo no)"
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("notify::hook-supplied message never reaches osascript argv")
  fi
}
