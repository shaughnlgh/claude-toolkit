---
type: plan
date: 2026-11-20
created: 2026-11-20
updated: 2026-11-20
project: example
repo: example
plan: direct-route
status: in-progress
approved:
route: direct-chain
tool: Claude Code
branch: fix/direct-route
ticket: none
mr:
ceiling: merge
worker_model: opus
verifier_model: claude-opus-4-1[1m]
verifier_effort: xhigh
nits: fix
tests: required
e2e: skip
tag_merge: true
modules:
repos:
sessions:
  - date: 2026-11-20
    summary: "direct-route finished: build, tests, red team and check done, docs and remember skipped"
    id: aaa-111
tags:
related_topics:
---

## Objective
x

## Plain Language Summary
This section is for non-technical readers. The technical detail below it can be skipped.

x

## Current Context
x

## Assumptions
x

## Affected Files
x

## Implementation Steps

## Validation Steps
x

## Risks
x

## Rollback Notes
x

## Open Questions
x

## Plan Changes During Execution

Step done: build: 2 files changed
Changed path: src/app.py
Changed path: tests/test_app.py
Step done: tests: pytest, exit 0
Step done: red team: code, security, 1a2b3c4d5e6f, 0 fixed
Step done: check: "looks right"
Step skipped: docs: "skip the docs"
Step skipped: remember: "skip it"
Remember: skipped by the user: "skip it"

Shipping record:
Staging list: src/app.py, tests/test_app.py
Commit message: fix(app): handle an empty cart
Hash: 0123456789ab

## Related Topics

## Linked Artifacts
