---
name: red-team
description: >-
  Red-team finalization gate for a completed implementation slice. Use when the user
  signals satisfaction with implementation work done this session ("I'm happy with
  this", "looks good, let's continue", "that works, proceed") and uncommitted
  implementation changes exist: recommend the red team in ONE line and wait for
  explicit confirmation before running anything. Also use whenever the user
  explicitly asks to red team code or a diff, which counts as the confirmation.
  Runs the review-mr workflow's adversarial review over the local slice diff,
  delegates fixes for confirmed findings with scoped re-checks, runs the doc update
  pass once after fixes, and ends with a commit suggestion. Do NOT fire when
  "proceed" or "continue" advances to a next phase (approving a plan, starting
  execution, answering a gate, moving to the next task), when changes are still
  under active back-and-forth discussion, or when the working tree holds no
  implementation changes from this session. Never mutates git state.
---

# Red Team

Red-team runs an adversarial review over a completed implementation slice's uncommitted diff, reusing the `review-mr` workflow (shipped with this plugin at `../../workflows/review-mr.js` relative to this skill's base directory) that `gitlab-mr-review` drives against MR diffs — same reviewer agents, same adversarial verify pass, aimed at the local working tree instead of a fetched MR. The main chat is the conductor: it presents the recommendation, gates the run on explicit confirmation, builds the inputs, launches the workflow, adjudicates the result, delegates fixes and re-checks to worker agents per the orchestration doctrine, runs the doc pass once, and closes with a commit suggestion. The conductor never edits a file, fixes a finding, or touches git itself — that is worker and human territory respectively.

## 1. Trigger discipline

The recommendation is blocking; the run is not. The moment a closure signal fires (per the frontmatter description) with uncommitted implementation changes present, say so in one line — do not let the moment pass silently and do not run anything yet. Then gate the run via `AskUserQuestion` per the communication doctrine, recommended option first: run now (recommended — name the chosen panel and any reviewers deliberately omitted), not yet (re-recommend at the next closure signal, keep working), skip for this slice. An explicit user request to red-team code or a diff skips this gate entirely — the request itself is the confirmation. The gate exists because only the human knows a slice is truly closed; firing on a provisional stopping point burns a full panel that the very next fix invalidates, and that panel is then paid for twice.

## 2. Scope the slice diff

Capture the slice without mutating any git state:

- Run `git status` first. A clean tree means there is nothing to review — say so and stop.
- If the tree holds changes that are not this session's work (a checkout that was already dirty, or an earlier uncommitted slice), name those paths and ask the user whether to include them, exclude them by path-scoping the diff, or hold the red team — never silently review or stage foreign hunks.
- `git diff HEAD > <scratchpad>/slice.diff.tmp` captures staged and unstaged changes to tracked files.
- Enumerate untracked files individually — `git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do git diff --no-index /dev/null "$f" >> <scratchpad>/slice.diff.tmp; done` — rather than a bare `??` status line, which collapses a whole new directory into one entry and would silently omit its files; this form also handles unusual names. The diff command exits 1 on any difference — tolerate that exit code, it is not a failure.
- Hash the temp file (e.g. `shasum -a 256`) and take the first 12 characters as `<hash12>`; move it to `<scratchpad>/slice-<hash12>.diff`. This keys the slice's artifacts by its diff hash so slices never collide within a session, and the hash is the tree-state fingerprint used later to detect drift.
- If the user committed partway through the slice, ask which base to diff against, or use the merge base they name — do not silently assume `HEAD`.

## 3. Panel selection

The standing panel is always `toolkit:code-reviewer`, `toolkit:silent-failure-hunter`, `toolkit:pr-test-analyzer`. Scale it by what the diff actually touches: add `toolkit:security-reviewer` when it touches auth, input handling, queries, file paths, tokens, or crypto; add `toolkit:performance-reviewer` when it touches hot paths, DB queries, loops over collections, or rendering. Pass the chosen set via `registryReviewers` using fully qualified `toolkit:` names — the Workflow tool's agentType lookup is literal, not fuzzy. Whatever panel runs, the confirmation line in step 1 and the final report in step 5 both name it and name any reviewer deliberately left off, so a trimmed panel is never silent about what it skipped. Add 1 to 3 custom `dimensions: [{key, prompt}]` seeded from this session's context — concrete suspicions from your own read of the diff beat generic prompts. Always include one cold-read dimension among them, passed with `cold: true` so the workflow never shows it the `contextBlock` at all: it re-derives what the diff does from the diff alone and reads every instruction and embedded command literally and adversarially. A reviewer briefed by the author reads the diff through the author's intent and inherits the author's blind spots — ambiguity a briefed reviewer silently auto-corrects toward the intended meaning is exactly where defects hide, so one reviewer must read as a stranger.

## 4. Build the context block and run

Build the `contextBlock` on the same contract `gitlab-mr-review` uses: one paragraph on what the slice does, environment facts, a file-by-file summary of the diff, and any project rules that apply (from the repo's CLAUDE.md / AGENTS.md / .claude/rules). Add the `repoState` argument, verbatim:

> The tree at repoRoot is the POST-change state this diff produces. There is no pre-change checkout. Reconstruct the pre-change state from the diff's context and removed lines. A defect the diff introduces is in scope even though it is present in the tree.

When the diff under review ships executable commands embedded in prose — a skill, a workflow script's prompts, a doc — include an instruction in the `contextBlock` that the panel or the verifier must execute those exact commands against a scratch fixture covering the awkward cases (clean tree, dirty tree, untracked directories, unusual filenames) rather than judge them by reading: prose that embeds commands is code, and reading a command finds fewer defects than running it.

Invoke the Workflow tool: when `repoRoot` is the toolkit plugin source itself (the tree contains `plugins/toolkit/workflows/review-mr.js`), invoke with `{scriptPath: "<repoRoot>/plugins/toolkit/workflows/review-mr.js"}` so uncommitted workflow edits are exercised; otherwise invoke `{name: "toolkit:review-mr"}` (the name the harness registers for the installed plugin), falling back to `{scriptPath: "<this skill's base directory>/../../workflows/review-mr.js"}` resolved to an absolute path if name resolution fails. Pass `diffPath: "<scratchpad>/slice-<hash12>.diff"`, `repoRoot`, `contextBlock`, `repoState`, `dimensions`, and `registryReviewers`. The moment the tool returns a `runId`, persist it (together with the script file path the launch result reports — resuming needs `scriptPath`) to `<scratchpad>/slice-<hash12>.runid` immediately — before adjudicating anything, keyed by the same hash as the diff. That file is the resume handle if the run dies mid-flight (`resumeFromRunId`: completed agents return cached, only dead work re-runs — never relaunch a fresh panel when a resume is possible), and it doubles as the marker that this slice's full panel has already run once, which step 5's "one full panel per slice" rule checks against by hash — a runid file whose hash doesn't match the current capture belongs to a different slice and never suppresses a new panel.

## 5. Adjudicate and fix

The result is `{confirmed, refuted, unverified, openQuestions}`. The conductor adjudicates the full result, not just the `confirmed` findings: `confirmed` findings are presented to the user, and `unverified` findings and `openQuestions` are each settled too — verified against session context, answered, or dismissed with a stated reason — never silently dropped from the report. Read the refuted findings before discarding them, too — when a refutation itself concedes the underlying observation is accurate and only the attached severity or failure scenario failed, salvage the observation and adjudicate it on its own terms. Adversarial verification optimizes precision at the cost of recall — a real defect wrapped in an overstated scenario dies with the scenario unless the conductor recovers it. This is conductor duty, not something to skip or delegate away. Fixes for accepted findings are delegated to `implementer` workers per the orchestration doctrine; the conductor scopes each fix, reviews the result, and never edits the files itself. After fixes land, run scoped re-checks only: the `toolkit:verifier` agent plus the specific reviewer dimension that raised each finding, over the files that changed for the fix — not a fresh full panel. A full second panel runs only on the user's explicit request. At report time, recapture a fresh diff by the same method as step 2 and hash it — rehashing the saved diff file detects nothing, since that file never changes. If the fresh hash differs from the recorded one, say so plainly and offer a scoped re-review of just the drift rather than silently reporting against a tree that no longer exists.

## 6. Doc pass

Run `execute-workflow`'s Doc Update Pass (`../execute-workflow/SKILL.md` from this skill's base directory) exactly once, after fixes are in and re-checks are clean, before moving to the commit suggestion. Do not run it earlier — findings from the panel may still change what needs documenting.

## 7. Commit suggestion

Close with a suggested commit message written in the repo's observed convention (read recent `git log` for tense, structure, and prefix style), the specific files to stage, and — when the current branch is a default or protected branch — a suggested branch name to use instead. Add a residual-risk line stating exactly what ran at which tree state (e.g. "full panel at hash `<a>`, scoped re-checks after the fixes"), so the human knows what is and is not covered. Per the git-safety doctrine, the human runs git: this skill never stages, commits, creates a branch, or pushes, under any circumstance.

## Boundary

Not for reviewing a GitLab MR (`gitlab-mr-review` owns that) and not for reviewing a plan (`plan-critic` owns that). At most one full panel runs per confirmed slice end — the persisted `runId` file from step 4, keyed by the diff hash, is the marker that stops a redundant second full run within the same slice; a runid file whose hash doesn't match the current capture is a different slice and never suppresses a new panel, and a full re-run still requires the user's explicit request. Passing the gate and getting a clean report never marks the overall task or plan complete — that stays the human's word, not this skill's.
