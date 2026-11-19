# Sourced by seat-check.sh, worker-spawn.sh and worker-watch.sh: the one reader of `claude agents --json`.
# TOOLKIT_AGENTS_FILE replaces the CLI for tests. Extra args, such as --all, pass to the CLI.
agents_json() {
  if [ -n "${TOOLKIT_AGENTS_FILE:-}" ]; then cat "$TOOLKIT_AGENTS_FILE" 2>/dev/null; return; fi
  if command -v perl >/dev/null 2>&1; then
    # macOS ships no timeout binary, so perl kills a stalled claude call after 3 s.
    perl -e '$p = fork // exit 127; if (!$p) { exec @ARGV; exit 127 }
      $SIG{ALRM} = sub { kill 9, $p; exit 124 }; alarm 3; waitpid $p, 0; exit $? >> 8' claude agents --json "$@" 2>/dev/null
  else
    claude agents --json "$@" 2>/dev/null
  fi
}
