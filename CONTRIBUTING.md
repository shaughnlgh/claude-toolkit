# Contributing

## Bug reports

Report a bug by opening an issue with the bug report template. Include the output of `/setup`, your platform and your Claude Code version, because most problems trace back to a missing prerequisite or a vault config the toolkit cannot read.

Report a security vulnerability through [`SECURITY.md`](SECURITY.md), never in a public issue.

## Pull requests

Outside pull requests are by invitation. Before you write code, open an issue that describes the change and why it is needed. If the owner invites a pull request, link it to that issue.

## Checks

A change must pass `bash verify.sh`. The last line must read `RESULT:` with 0 failed. [`VERIFY.md`](VERIFY.md) explains what the script proves and lists the manual checks that only a live Claude Code session can show.
