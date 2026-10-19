#!/usr/bin/env bash
# Control-flow suite for workflows/execute-runner.js, driven by harness.mjs with scripted agent and workflow stubs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "FATAL: node not found" >&2; exit 2; }
node "$HERE/harness.mjs" "$HERE/../../execute-runner.js"
