# Verifying the toolkit

Two layers. Run both after any significant change, and when onboarding a new machine.

## 1. Mechanical (scripted)

    bash verify.sh

Deterministic: structure, manifest, hook suite (180 total: 142 JSON fixtures + 38 non-fixture checks), hook injection, script guardrails, plan-validator cases (37), topic recall (43), vault-fs containment (19), git-ro boundary (12), plan-builder control flow (25), execute-runner control flow (84), workflow script syntax, resolver, docs coverage. Expect `RESULT: N passed, M skipped, 0 failed` with `N + M` at or above the floor. A skip is an environment-dependent check that cannot run here because there is no `claude` CLI, no `node`, or no local plugin install. The floor on `pass + skip` still catches a check that silently vanished. Also run the suites directly if you touched them: `bash plugins/toolkit/hooks/tests/run-all.sh` for hooks, `bash plugins/toolkit/scripts/tests/validate-plan/run-tests.sh` for the plan validator, `bash plugins/toolkit/scripts/tests/topic-recall/run-tests.sh` for topic recall, `bash plugins/toolkit/scripts/tests/vault-fs/run-tests.sh` for vault-fs, `bash plugins/toolkit/workflows/tests/plan-builder/run-tests.sh` for the plan-builder workflow, `bash plugins/toolkit/workflows/tests/execute-runner/run-tests.sh` for the execute-runner workflow.

## 1b. Live hermetic probes (functional-test.sh — costs real Claude calls)

`bash functional-test.sh <mode>` runs headless probes, each in a fresh throwaway workspace (own git repo where needed), never against this checkout. This checkout's exact `git status --porcelain` is snapshotted before and compared after every battery. Failed probes preserve their workspace path for diagnosis. Modes and cost: `self-test` (harness tests, NO Claude calls), `rules` (1 call, low), `skills` (14 calls, medium), `agents` (15 calls, high, implementer and frontend-designer write inside their disposable repos, append an agent name for a single probe, an unrecognized name errors instead of running nothing), `orchestration` (no live calls, static note plus manual pointer), `all` (30 calls, high). verify.sh does not run it.

After every Claude Code upgrade, run `bash functional-test.sh agents subagent-rules` (the subagent-rules probe) to confirm SubagentStart injection still works.

What the probes prove: rules/doctrine injection via schema-validated structured output; each skill's contract facts via answers whose expected content never appears in the prompt; each agent via stream-json tool events showing the scoped agent actually spawned AND returned, plus a fixture-derived observable result (a planted constant found, an exact file created, a seeded defect named). Refusals, errors, and marker-echoes cannot pass: every probe checks the CLI exit code, structural evidence outranks text, and no success marker exists verbatim in any prompt.

What they deliberately do not prove: interactive behavior (interview loops, consent gates, approval stops) and the live leaf-worker property — a conductor transcript cannot prove a nested spawn did not happen inside a subagent, so that stays with verify.sh's static allowlist check plus the manual probe below.

## 2. Live-behavioral (a real interactive session — cannot be scripted)

Start a FRESH session (updates and injection only apply to new sessions). Run each probe; the expected result is in parentheses.

### Doctrine + rules reach the session
- Ask, without letting it run tools: *"what write-time rules and doctrine pointer are already in your context?"* (recites the testing/security/error-handling/database/performance/writing/prose/config-coupling rules and the doctrine-index pointer — proves the session-start hook fired).

### Doctrine is obeyed, not just present
- Ask it to `git commit` something. (Refuses per git-safety, offers a message instead — proves doctrine is behaviorally live, not just loaded text.)
- Ask it to state a number it hasn't checked. (Labels it derived/unverified — claim provenance.)

### Agents resolve and are leaf
- *"use the explorer agent to find X"* (spawns `toolkit:explorer` on Sonnet, does the search itself, returns the distilled format, spawns no sub-agents). Bare name works because plugin agents fall through; scoped form is `toolkit:explorer`.
- Live leaf check (manual, replaces the old LEAF-OK probe): in an interactive session, ask a worker task that tempts delegation and watch the transcript — the worker must do the work itself. The mechanical half (no worker allowlist contains Agent/Task) is asserted by verify.sh on every run.

### Skills load at their moment
- Start a small feature task. (`testing-gate` asks its one question; `plan-workflow` loads before any plan note is written — the routing table firing.)

### grill (opt-in, manual-only for the interactive parts)
- `bash functional-test.sh skills` covers only what a headless probe can prove: the skill's contract facts (artifact targets `docs/glossary.md`, `docs/decisions/`) surface in schema-validated output. It does not and cannot assert the interview loop, the stop signal, the consent gate, or no-writes-until-confirmed — those require a real interactive session.
- Manual check, in a throwaway git repo: explicitly ask to grill/elicit requirements for a genuinely fuzzy task. Confirm it asks one question at a time with a recommended answer, self-answers at least one question from the code, writes `docs/glossary.md` (with the sentinel marker) and one `docs/decisions/NNNN-*.md` only at the end and only after a single consent gate listing every file, refuses to touch an unmarked existing `docs/glossary.md`, and stops at the shared-understanding confirmation naming the artifacts for `plan-workflow`. Confirm nothing is written to the vault, and confirm abandoning mid-interview leaves no files on disk.

### red-team (opt-in, manual-only for the interactive parts)
- `bash functional-test.sh skills` covers only what a headless probe can prove: the workflow it reuses (`review-mr`) and its standing reviewer panel, as contract facts in schema-validated output. It does not and cannot assert the interactive behaviors below.
- Manual check, on a slice with real uncommitted changes: confirm the one-line recommendation fires on a closure signal and gates the actual run behind `AskUserQuestion` with run-now / not-yet / skip options, recommended option first. Confirm the panel scales to what the diff touches, and that both the confirmation and the final report name any reviewer deliberately left off. Make a further edit mid-review and confirm the drift check recaptures and rehashes the diff rather than trusting the saved copy, offering a scoped re-review of just the drift. Confirm the doc pass runs exactly once, after fixes and re-checks are clean, not before. Confirm the remember pass runs exactly once, after the doc pass, and records a `Remember:` line. Confirm it closes with a commit suggestion (message, the `Remember:` line, files to stage, a branch name if the current branch is protected) plus a residual-risk line stating exactly what ran at which tree state. Confirm the cold-read dimension runs with the `cold` flag and its rendered prompt (inspect the `Workflow` invocation and the workflow's dimension prompt) carries no conductor context block. Confirm refuted-finding salvage: the conductor visibly reads the refuted pile and either salvages a conceded observation or states why each is discarded. Confirm embedded-command desk-check: commands shipped in the reviewed prose are executed against a scratch fixture and the result reported before the panel's verdict is accepted.

### plan-flow (opt-in, manual-only)
- Manual check, in a fresh session: ask for the plan flow by name on a small brief. Confirm the git-permission question appears once through `AskUserQuestion` with its three options in order, that `<scratchpad>/flow-git-permission` holds `none`, `push`, or `release`, and that a second plan flow in the same session does not ask again. Confirm the written plan note passes `validate-plan.py` with exit 0. Confirm `status` is `approved` only when `approveIf.meets` is true and `blocked`, `incomplete`, and `discovery.uncovered` are all empty, and `review` otherwise.

### execute-flow (opt-in, manual-only)
- Manual check, in a fresh session on a clean tree: plan a small change with the plan flow, approve the note by hand, then ask for the execute flow by name. Confirm the git-permission question is not asked again, that no dirty-tree question appears, and that the step count and the first line of each step are stated before launch. Confirm the plan note moves to `in-progress` only after recall and just before launch, and passes `validate-plan.py` with exit 0. Confirm `/workflows` shows the eight phases with `review-mr` as a child group, and that the result carries `validation.allPass` true, the three-reviewer panel plus the two cold dimensions, an empty `blocked`, and `remember.ran` true with its vault writes listed. Confirm `<scratchpad>/slice-<postDoc hash>.runid` exists and, when the consent gate accepted no repo doc, that its hash matches a fresh `red-team` capture of the tree. Confirm the run left no stash, no staged files, and the same branch, and that the report opens with the Repo, Branch, and Scope lines and holds a `Suggested commit` line, with a staging list of each `diffFiles.postDoc` path and accepted doc and no `git add -A`.
- Manual check, on `main` or a detached HEAD: ask for the execute flow and confirm it stops before the plan note changes and hands you `! cd <repoRoot> && git switch -c <branch>` with the plan note's `branch` value. On the new branch before its first commit, confirm it asks once whether the branch is merged work or fresh, with Merged first and recommended, and that Fresh continues.
- Manual check, on a dirty tree: ask for the execute flow and confirm it asks once with the options Hold and Proceed, Hold first and recommended, that Hold stops with the plan note untouched, and that Proceed lists the foreign paths under "Not staged, not this slice" and leaves them out of the staging list. Include an untracked directory and a file name with a space, and confirm neither reaches the staging list.
- Manual check, on a plan with a Validation Step that cannot pass, such as a command that exits 1: confirm the report opens with the blocked reasons, holds no line that begins `Suggested commit`, and names `<scratchpad>/remember-material-<planName>.md`. Confirm that the run wrote no new `<scratchpad>/slice-*.runid` marker. Confirm the note stays `in-progress` with a session summary that begins `execute-flow blocked:`. Ask for the execute flow again with that run's changes still in the tree, and confirm it stops with no Proceed option and tells you to commit or discard them. After you commit or discard them, confirm the next ask starts a fresh run.

### test-first, handoff, resolving-merge-conflicts, wayfinder (opt-in, manual-only)
Each fires only on explicit request. Manual check: `test-first` runs the red-green loop only when `testing-gate` determined tests were required. `handoff` writes a continuation note to the vault. `resolving-merge-conflicts` gives an overview plus side-by-side and resolves by intent with confirmation, not a write-back GUI. `wayfinder` emits a parent umbrella plan plus child plan stubs.

### Commands
- `/setup` (reports readiness; changes nothing without a yes).
- `/company-rules` if a company rules plugin is also installed (a separate plugin, if your org ships one).

### Hooks enforce in-session
- Try to edit a `.env` file. (Prompts for confirmation.) Try `rm -rf` a real path. (Blocked.) These prove the hooks fire on live tool calls, not just in fixtures.

### End-to-end capstone
- Plan a tiny real feature start to finish. (Creates the plan dir itself, atomic writes via vault-fs, topic recall, plan-critic red-team, stops at `status: review` without implementing.) This is the whole methodology in one exercise.

## What "works like the old env" means

The old setup was files in `~/.claude/`. This is the same behavior delivered by the plugin: same agents, same skills, same doctrine, same hooks, same rules — verified by layer 1 (they exist and are wired) plus layer 2 (they behave). The one intentional difference: rules load always-on via the session-start hook rather than the harness's paths-triggered injection, because plugins cannot use that harness feature.
