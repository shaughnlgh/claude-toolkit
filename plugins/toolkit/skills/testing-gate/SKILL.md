---
name: testing-gate
description: >-
  Reads the tests run option from the plan note or the session cache, asking once only when neither has it, to determine whether tests are required or manual verification
  is sufficient. Use when starting a feature, bugfix, or refactor to decide upfront whether
  automated tests are needed.
---
# Testing Gate (Ask Once Per Task Session)

When this skill is active, before writing or editing code, read `tests`. When a plan note exists, read it per the reading rule in `plan-guide` § Run options (`../plan-guide/SKILL.md` from this skill's base directory): from the note, else from `<scratchpad>/flow-run-options` when that file's `plan:` line equals the note's `plan:` value. When no plan note exists, read the `tests:` line of `<scratchpad>/flow-run-options` only when that file's `plan:` line is blank. If the value is `required` or `manual`, do not ask. Otherwise ask exactly once:

> Do we require tests for this task, or is manual verification sufficient?

Present this question via the AskUserQuestion form per the communication doctrine, recommended answer first. When a plan note exists, record the answer as `tests: required` or `tests: manual` on the note. When no plan note exists, write `<scratchpad>/flow-run-options` as a blank `plan:` line followed by the `tests:` line and any `ticket:` and `ticket_work:` lines the file already held, so no plan flow reads that cache. The key and its values are defined in `plan-guide` § Run options.

## After the answer is known
- If tests are required: use the test setup that already exists in the repo, and follow the `test-first` skill for the red-green-refactor loop
- If manual verification is sufficient: proceed without adding tests, but do not ask again in this session

## Notes
- Do not invent a test framework or test pattern that is not already present in the repo
- If the repo has project-specific testing commands or tooling, use those
- For upgrade or migration work, manual verification plus smoke testing is often acceptable even without new automated tests
