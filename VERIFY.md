# Verifying the toolkit

Two layers. Run both after any significant change, and when onboarding a new machine.

## 1. Mechanical (scripted)

    bash verify.sh

Deterministic: structure, manifest, hook fixtures (54), hook injection, script
guardrails, resolver, leakage. Expect `RESULT: N passed, 0 failed`. Also run the
hook fixture suite directly if you touched a hook: `bash plugins/toolkit/hooks/tests/run-all.sh`.

## 2. Live-behavioral (a real interactive session — cannot be scripted)

Start a FRESH session (updates and injection only apply to new sessions). Run each
probe; the expected result is in parentheses.

### Doctrine + rules reach the session
- Ask, without letting it run tools: *"what write-time rules and doctrine pointer are
  already in your context?"* (recites the testing/security/error-handling/database
  rules and the doctrine-index pointer — proves the session-start hook fired).

### Doctrine is obeyed, not just present
- Ask it to `git commit` something. (Refuses per git-safety, offers a message instead —
  proves doctrine is behaviorally live, not just loaded text.)
- Ask it to state a number it hasn't checked. (Labels it derived/unverified — claim
  provenance.)

### Agents resolve and are leaf
- *"use the explorer agent to find X"* (spawns `toolkit:explorer` on Sonnet, does the
  search itself, returns the distilled format, spawns no sub-agents). Bare name works
  because plugin agents fall through; scoped form is `toolkit:explorer`.

### Skills load at their moment
- Start a small feature task. (`testing-gate` asks its one question; `plan-workflow`
  loads before any plan note is written — the routing table firing.)

### grill (opt-in, manual-only for the interactive parts)
- `bash functional-test.sh skills` covers only what a headless probe can prove: the
  skill loads, states its first question, and names its artifact targets (`CONTEXT.md`,
  `docs/adr/`). It does not and cannot assert the interview loop, the stop signal, the
  consent gate, or no-writes-until-confirmed — those require a real interactive session.
- Manual check, in a throwaway git repo: explicitly ask to grill/elicit requirements
  for a genuinely fuzzy task. Confirm it asks one question at a time with a
  recommended answer, self-answers at least one question from the code, writes
  `CONTEXT.md` (with the sentinel marker) and one `docs/adr/NNNN-*.md` only at the end
  and only after a single consent gate listing every file, refuses to touch an
  unmarked existing `CONTEXT.md`, and stops at the shared-understanding confirmation
  naming the artifacts for `plan-workflow`. Confirm nothing is written to the vault,
  and confirm abandoning mid-interview leaves no files on disk.

### test-first, handoff, resolving-merge-conflicts, wayfinder (opt-in, manual-only)
Each fires only on explicit request. Manual check: `test-first` runs the red-green
loop only when `testing-gate` determined tests were required. `handoff` writes a
continuation note to the vault. `resolving-merge-conflicts` gives an overview plus
side-by-side and resolves by intent with confirmation, not a write-back GUI.
`wayfinder` emits a parent umbrella plan plus child plan stubs.

### Commands
- `/toolkit-setup` (reports readiness; changes nothing without a yes).
- `/company-rules` if a company rules plugin is also installed (a separate plugin, if your org ships one).

### Hooks enforce in-session
- Try to edit a `.env` file. (Prompts for confirmation.) Try `rm -rf` a real path.
  (Blocked.) These prove the hooks fire on live tool calls, not just in fixtures.

### End-to-end capstone
- Plan a tiny real feature start to finish. (Creates the plan dir itself, atomic
  writes via vault-fs, topic recall, plan-critic red-team, stops at `status: review`
  without implementing.) This is the whole methodology in one exercise.

## What "works like the old env" means

The old setup was files in `~/.claude/`. This is the same behavior delivered by the
plugin: same agents, same skills, same doctrine, same hooks, same rules — verified by
layer 1 (they exist and are wired) plus layer 2 (they behave). The one intentional
difference: rules load always-on via the session-start hook rather than the harness's
paths-triggered injection, because plugins cannot use that harness feature.
