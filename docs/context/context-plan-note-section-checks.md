---
title: Plan note section checks
summary: How the toolkit's validator and hooks find a line inside a plan note section, gate new content rules on the plan's created date, and test those rules.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-18
source_refs:
  - plugins/toolkit/scripts/validate-plan.py
  - plugins/toolkit/hooks/remember-guard.sh
  - plugins/toolkit/scripts/tests/validate-plan/
  - plugins/toolkit/hooks/tests/remember-guard-check.sh
---
<!-- managed-by: toolkit -->

# Plan note section checks

`validate-plan.py` and the `remember-guard.sh` Stop hook both look for a line under a named `## ` section of a plan note. The rules each one enforces are in [scripts.md](../scripts.md) and [hooks.md](../hooks.md). This page covers how they read a section, how a new content rule avoids breaking older plans, and how the tests for such a rule are built.

## Reading a section

- A scan for a section line is fence-aware in both directions. A line inside a fenced code block never counts as the line, and a `## ` line inside a fence never ends the section.
- `validate-plan.py` gets this by stripping fences first. `section(body, heading)` receives the body with fenced code removed and returns the text after the first `## <heading>` line, up to the next `## ` heading.
- A `### ` subheading does not end a section.
- `section()` reads only the first unfenced heading with that name.
- `remember-guard.sh` cannot call the Python helper, so its `has_remember_line` awk applies the same fence rule as `strip_fences`. A fence opens on three or more backticks or tildes plus an optional info word. It closes on a bare run of the same character that is at least as long.
- The awk scan checks every `## Plan Changes During Execution` heading in the note, not only the first. A plan with that heading twice and the line only under the second one passes the hook but fails the validator.

## Gating a new content rule

- Every validate-plan content rule added after plans already exist is gated on the frontmatter `created` date through a `*_SINCE` constant, such as `PLAIN_LANGUAGE_SUMMARY_SINCE` and `REMEMBER_LINE_SINCE`.
- A plan is exempt only when `created` is a parseable `YYYY-MM-DD` date earlier than the constant. A blank, missing, or malformed `created` is not exempt.
- Without the gate, a new rule fails every plan written before the convention existed.

## Testing a section rule

- A fixture set for a "line in a section" rule needs a positive case, a grandfathered case, and three shapes that target one code path each: the line under the wrong section, the line only inside a fence, and the bare form beside the bullet form.
- Each shape must be the only case that fails under the mutation it targets. For example, removing the fence handling must fail the fenced case and no other case.
- When a hook check sets up a negative case to prove one guard, build it so only that guard can stop it. `remember-guard-check.sh` names its non-repo directory after the test repo, so the vault folder check passes and only the git check blocks.
