---
name: testing-gate
description: >-
  Prompt once per task session to determine whether tests are required or manual verification
  is sufficient. Use when starting a feature, bugfix, or refactor to decide upfront whether
  automated tests are needed.
---
# Testing Gate (Ask Once Per Task Session)

When this skill is active, before writing or editing code, ask exactly once:

> Do we require tests for this task, or is manual verification sufficient?

## After User Reply
- If tests are required: use the test setup that already exists in the repo
- If manual verification is sufficient: proceed without adding tests, but do not ask again in this session

## Notes
- Do not invent a test framework or test pattern that is not already present in the repo
- If the repo has project-specific testing commands or tooling, use those
- For upgrade or migration work, manual verification plus smoke testing is often acceptable even without new automated tests
