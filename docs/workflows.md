# Workflows

Workflows are multi-agent orchestrations the toolkit ships as scripts under `plugins/toolkit/workflows/`, run through the Workflow tool rather than a single agent turn. There are two: `review-mr`, driven by the `gitlab-mr-review` skill against fetched MR diffs and the `red-team` skill against local uncommitted slice diffs (passing `repoState`), and `plan-builder`, driven by the `plan-flow` skill to turn a brief into the body of a plan note. A workflow and a skill register in the same `toolkit:` namespace, so the script cannot share the skill's name.

## review-mr.js

Multi-dimension MR review. It runs two phases:

- **Review** — fans out the toolkit reviewer agents (`toolkit:code-reviewer`, `toolkit:security-reviewer`, `toolkit:silent-failure-hunter`, `toolkit:performance-reviewer`, `toolkit:pr-test-analyzer`, `toolkit:coupling-reviewer`) plus any MR-specific custom dimensions, each reading the saved diff and reporting findings against a shared schema (title, file, severity, detail, failure scenario). A dimension that can't answer something from the diff or repo returns it as an `open_questions` entry instead of guessing.
- **Verify** — every finding from every dimension is checked again by a separate `toolkit:verifier` agent instructed to try to refute it: does the code path really execute, is the failure scenario reachable, is it already handled elsewhere. The verifier defaults to refuted when a claim is unreachable or speculative.

The workflow then adjudicates its own results — splitting findings into `confirmed`, `refuted` (with reasoning), `unverified` (verifier died mid-run — the conductor must settle these), and `openQuestions` — and returns that structure. It does not produce a final report itself; that's the calling skill's job.

Reviews are run against the diff plus a local checkout at `repoRoot`, whose state the `repoState` argument declares — a target-branch checkout for `gitlab-mr-review`, the post-change working tree for `red-team` — so any claim about existing code, callers, or framework behavior is verified against that declared state.

Invoked by the `gitlab-mr-review` or `red-team` skill (or directly) with:

```
args: {diffPath, repoRoot, contextBlock, dimensions?, registryReviewers?, repoState?}
```

- `diffPath` (required) — absolute path to the saved unified diff.
- `repoRoot` (required) — absolute path to the local repo the review verifies claims against, whose state `repoState` declares: a target-branch checkout for `gitlab-mr-review`, the post-change working tree for `red-team`.
- `contextBlock` (required) — env facts, a summary of the change under review, and verification instructions, built by the conductor (the skill) before the workflow runs.
- `dimensions` (optional) — `[{key, prompt, cold?}]`, extra MR-specific review angles (contract impact, framework wiring, conventions, data/upgrade safety) the registry reviewers won't cover; `cold: true` omits the conductor's `contextBlock` from that dimension's prompt so it reads the diff without the author's framing.
- `registryReviewers` (optional) — override the default set of six reviewer agent types. Names must be fully qualified as the harness registers them (plugin agents are namespaced, e.g. `toolkit:code-reviewer`).
- `repoState` (optional) — sentence describing the state of the tree at `repoRoot`, substituted into the reviewer and verifier prompts; defaults to the current MR target-branch sentence.

## plan-builder.js

Plan flow. It turns a brief into every section of a plan note and runs five phases:

- **Discover**: a `toolkit:explorer` agent splits the brief into 2 to 5 investigation areas, each with one question and the paths to start from. One `toolkit:explorer` per area then answers its question with file:line facts, gaps, risks, and a reuse ladder result. If the scoping agent dies, the flow uses one whole-brief area.
- **Draft**: a `toolkit:planner` agent writes every plan section from the findings, plus a branch name and related topics.
- **Invert**: a `toolkit:plan-critic` agent runs a pre-mortem and returns a verdict of `proceed`, `revise`, or `stop`, with objections, tripwires, and walk-away checks. On `revise`, the planner resolves the material objections and the critic runs again, for at most `maxRounds` revisions.
- **Red team**: a second `toolkit:plan-critic` reads the plan cold, without the brief, the recall hits, or the evidence. If it raises material objections, the planner revises the plan once more.
- **Judge**: if `approveIf` is set, a `toolkit:verifier` agent judges whether every clause of the goal maps to an implementation step and a validation step that proves it. The judge defaults to false.

The script writes no files and runs no git. The `plan-flow` skill writes the returned sections to the plan note, validates the note, and sets `status` to `approved` only when `approveIf.meets` is true and `blocked`, `incomplete`, and `discovery.uncovered` are all empty.

Invoked by the `plan-flow` skill (or directly) with:

```
args: {brief, repoRoot, repoName, planName, recallHits, knownEvidence?, approveIf?, maxRounds?}
```

- `brief` (required): the task description the plan answers.
- `repoRoot` (required): absolute path to the repo the explorers, planner, and critics read as ground truth.
- `repoName` (required): the repo name every prompt carries.
- `planName` (required): the plan note name.
- `recallHits` (required): the text output of `topic-recall.py` for the brief's key terms.
- `knownEvidence` (optional): facts the conductor already holds. The scoping agent skips areas these settle.
- `approveIf` (optional): a goal sentence. The Judge phase runs only when it is set.
- `maxRounds` (optional): a non-negative integer that caps the revise rounds in the Invert phase. Default 2 when absent or null. Any other value that is not a non-negative integer, such as the string "0", -1, or 1.5, makes the script throw an Error that names the value.

The script throws if any required arg is missing or is not a non-empty string.

It returns `{plan, branch, relatedTopics, discovery, rounds, tripwires, walkAway, coldObjections, coldVerdict, finalVerdict, openObjections, critiqueStale, blocked, approveIf, incomplete}`:

- `plan`: the 11 section bodies without heading lines, keyed `objective`, `plainLanguageSummary`, `currentContext`, `assumptions`, `affectedFiles`, `implementationSteps`, `validationSteps`, `risks`, `rollbackNotes`, `openQuestions`, `relatedTopics`.
- `branch` and `relatedTopics`: the planner's branch name and topic names for the note frontmatter.
- `discovery`: `{areas, uncovered}`, the area names and the areas whose explorer died.
- `rounds`: one `{verdict, materialCount}` per Invert critique, with `verdict: incomplete` for a critique that died.
- `tripwires` and `walkAway`: from the last Invert critique that returned, or empty arrays when none returned.
- `coldObjections`: the cold critic's objections, or `null` if it died.
- `coldVerdict`: the cold critic's verdict, or `null` if it died.
- `finalVerdict`: `proceed`, `revise`, or `stop` from the last Invert critique that returned, or `incomplete` when none returned.
- `openObjections`: the material objections, each `{section, claim, evidence, fix, material}`, that no revise applied. These are the last Invert critique's material objections when no successful revise came after it, whatever its verdict, plus the cold critic's material objections when `revise:cold` died or returned the plan unchanged.
- `critiqueStale`: `true` when the returned plan differs from the draft the last returned Invert critique saw. A successful revise followed by a dead critique, or a successful cold revise, sets it. In that case `tripwires` and `walkAway` describe an earlier draft.
- `blocked`: one plain sentence per reason the plan must not be auto-approved, or an empty array.
- `approveIf`: `{meets, reasons, unmetGoals}`, or `null` when no goal was set.
- `incomplete`: the labels of the stages that died.

`blocked` gets a sentence for each of these: a `stop` final verdict, a `proceed` final verdict that still carries material objections, a `revise` final verdict left open after `maxRounds` revisions, a `revise` final verdict with `maxRounds` 0, a dead `invert:0`, a dead `red-team:cold`, a `stop` cold verdict, a cold revise that returned the plan unchanged, each dead `revise:N` or `revise:cold`, and `critiqueStale` true. The judge prompt carries `finalVerdict` and `openObjections`, and the judge must return `meets: false` while a material objection stays open or the final verdict is `stop`.

A dead stage never fails the run. Its label (`discover:scope`, `invert:N`, `revise:N`, `red-team:cold`, `revise:cold`, `judge`) lands in `incomplete`, and a dead judge also yields `meets: false`. A dead area explorer lands in `discovery.uncovered`. The one exception is the draft: if the planner returns nothing, the script throws, because no plan exists to return.

Tests: `bash plugins/toolkit/workflows/tests/plan-builder/run-tests.sh` runs 25 control-flow cases that drive the script with a scripted agent stub: dead stages, each verdict path, the cold revise paths, the stale-critique cases, and the judge prompt. The suite needs `node`, and `verify.sh` also runs it.

## post_mr_comments.py

Lives at `plugins/toolkit/skills/gitlab-mr-review/scripts/` — skill-local, not a general toolkit script. Posts review findings as positioned discussions on the GitLab MR: reads a `comments.json` (host, project, MR IID, the head sha the diff was reviewed at, the diff path, and a list of `{path, anchor, body}` comments plus an optional summary note), resolves each comment's `anchor` against the added lines in the diff (exact match first, then substring) to find a line number, then posts a positioned discussion per comment — falling back to an unpositioned discussion, prefixed with file:line, if GitLab rejects the position. It aborts up front if the MR's head sha has moved since the diff was fetched, since anchors may be stale. `--dry-run` prints what would be posted without posting.

This is a separate, explicit step — never automatic. The skill only runs it when the user asks, in that same session, to post the review to the MR; producing the review itself never triggers it.

Tests: `bash plugins/toolkit/scripts/tests/post-mr-comments/run-tests.sh` (5 behavior cases over the `GITLAB_TOKEN` guard: unset, empty, whitespace-padded, embedded-newline, and a well-formed fake that must pass through; also run by `verify.sh`).
