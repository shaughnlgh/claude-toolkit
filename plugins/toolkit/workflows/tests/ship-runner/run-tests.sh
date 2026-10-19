#!/usr/bin/env bash
# Control-flow suite for workflows/ship-runner.js, driven by harness.mjs with scripted agent stubs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "FATAL: node not found" >&2; exit 2; }
# SHIP_RUNNER_SCRIPT points the suite at another copy of the script, for a mutant run.
node "$HERE/harness.mjs" "${SHIP_RUNNER_SCRIPT:-$HERE/../../ship-runner.js}"
