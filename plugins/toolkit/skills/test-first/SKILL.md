---
name: test-first
description: >-
  Use when writing or editing code on a task where testing-gate has already determined
  tests are required. Runs the red-green-refactor loop: write a failing test, watch it
  fail for the right reason, write the minimum code to pass it, confirm green, then
  refactor with the test green. Does not fire on manual-verification tasks (testing-gate
  decided no tests needed) and does not fire on plain Q&A or read-only work. This skill
  never decides whether to test, it only runs the loop once testing-gate says yes.
---

# Test First

This skill is the red-green-refactor loop that runs after `testing-gate` has decided tests are required for the task. Testing-gate is the yes/no decision. Test-first is the how. They chain: testing-gate answers "do we test this", test-first answers "how do we write the code once the answer is yes". Test-first does not make the yes/no call itself and does nothing on tasks where testing-gate concluded manual verification is sufficient.

## The loop

Work in small steps, one test or a small batch at a time. Never write a large upfront test suite before any code exists.

1. Write a failing test that states the intended behavior.
2. Run it and confirm it fails for the right reason (the behavior is missing), not because of a setup error, import error, or typo. If it fails for the wrong reason, fix the test or the setup before writing any implementation code.
3. Write the minimum code needed to make the test pass. Do not add behavior the test does not require yet.
4. Run the test and confirm it passes.
5. Refactor with the test green: clean up the code, then re-run the test to confirm it is still green. If it turns red, fix the refactor before moving on.

Repeat from step 1 for the next small piece of behavior.

## Rules

- Use the repo's existing test setup, framework, and commands. This is inherited directly from testing-gate: never invent a test framework or test pattern that is not already present in the repo.
- If the repo has project-specific testing commands or tooling, use those.
- If the repo has no test setup at all, stop and surface that rather than inventing one. Setting up a test framework from scratch is a decision for the user or conductor, not something this skill does on its own.

## Boundary

- Test-first does not decide whether tests are required. That is testing-gate's job, asked once per task session before this skill engages.
- Test-first does not apply on manual-verification tasks. If testing-gate concluded manual verification is sufficient, this skill stays inactive for the rest of the session.
