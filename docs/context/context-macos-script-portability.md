---
title: macOS script portability
summary: Constraints that the macOS system Python and a piped stdin put on the toolkit's Python scripts and test suites.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-18
source_refs:
  - plugins/toolkit/scripts/topic-recall.py
  - plugins/toolkit/hooks/session-start.sh
  - plugins/toolkit/scripts/tests/git-ro/run-tests.sh
---
<!-- managed-by: toolkit -->

# macOS script portability

The toolkit's Python scripts run under whatever `python3` the PATH resolves first. On a stock Mac that is `/usr/bin/python3`, the system Python, which is older than 3.10. The facts below are the constraints that follow. The hook-side guards (the `xcode-select -p` check and the optional `timeout` wrapper) are described in [hooks.md](../hooks.md).

## Python scripts

- A script that uses `X | None` style annotations must start with `from __future__ import annotations`. Without it the system Python raises at import time. `topic-recall.py` carries this import for that reason.
- `session-start.sh` discards the stderr of `topic-recall.py`. An import crash on the system Python therefore drops the vault topic rows with no visible error. After a change to a script the hook calls, run it once with `/usr/bin/python3` before relying on the hook output.

## Test suites

- On macOS, `sys.executable` under `/usr/bin/python3` reports the Xcode developer path (`/Applications/Xcode.app/Contents/Developer/usr/bin/python3`), not `/usr/bin/python3`. A test that compares interpreter paths must allow for that.
- A test child started with only `HOME` and `PATH` in its environment runs in the C locale, and Python turns on UTF-8 mode in the C locale. Such a test does not reproduce a stdout encoding failure, so the encoding fallback in `topic-recall.py` needs a different way to exercise it.
- The git-ro suite (`plugins/toolkit/scripts/tests/git-ro/run-tests.sh`) hangs when stdin is a pipe that never closes, for example when the suite runs in the background. Its fixture `core.fsmonitor` driver ends in `exec cat`, and the setup's `git add -A` runs that driver, which then waits on stdin. When `verify.sh` runs in the background, redirect its stdin from `/dev/null`.

## Related docs

- [scripts.md](../scripts.md) for the `topic-recall.py` reference.
- [hooks.md](../hooks.md) for `session-start.sh` and its failure modes.
- [VERIFY.md](../../VERIFY.md) for running `verify.sh`.
