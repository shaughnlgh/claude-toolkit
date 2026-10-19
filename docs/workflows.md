# Workflows

Workflows are multi-agent orchestrations the toolkit ships as scripts under `plugins/toolkit/workflows/`, run through the Workflow tool rather than a single agent turn. There are three: `review-mr`, driven by the `gitlab-mr-review` skill against fetched MR diffs and the `red-team` skill against local uncommitted slice diffs (passing `repoState`), `plan-builder`, driven by the `plan-flow` skill to turn a brief into the body of a plan note, and `execute-runner`, driven by the `execute-flow` skill to execute an approved plan note end to end. A workflow and a skill register in the same `toolkit:` namespace, so the script cannot share the skill's name.

Child workflows: a script runs another workflow as a child with `workflow(nameOrRef, args)`. The runtime runs the child inline and returns the child's return value. The call throws on an unknown name or a child failure, and returns null when the child is stopped. `agent()` likewise returns null for a stopped agent. `execute-runner` calls `toolkit:review-mr` as a child. `review-mr` and `plan-builder` call no child.

## review-mr.js

Multi-dimension MR review. It runs two phases:

- **Review** — fans out the toolkit reviewer agents (`toolkit:code-reviewer`, `toolkit:security-reviewer`, `toolkit:silent-failure-hunter`, `toolkit:performance-reviewer`, `toolkit:pr-test-analyzer`, `toolkit:coupling-reviewer`) plus any MR-specific custom dimensions, each reading the saved diff and reporting findings against a shared schema (title, file, severity, detail, failure scenario). A dimension that can't answer something from the diff or repo returns it as an `open_questions` entry instead of guessing.
- **Verify** — every finding from every dimension is checked again by a separate `toolkit:verifier` agent instructed to try to refute it: does the code path really execute, is the failure scenario reachable, is it already handled elsewhere. The verifier defaults to refuted when a claim is unreachable or speculative.

The workflow then adjudicates its own results — splitting findings into `confirmed`, `refuted` (with reasoning), `unverified` (verifier died mid-run — the conductor must settle these), and `openQuestions` — and returns that structure. It does not produce a final report itself; that's the calling skill's job.

The return also carries `dead`, the reviewers and dimensions whose agent returned nothing, and `ran`, the ones that returned. Both name a registry reviewer by its agent type, such as `toolkit:code-reviewer`, and a custom dimension by its key.

Reviews are run against the diff plus a local checkout at `repoRoot`, whose state the `repoState` argument declares — a target-branch checkout for `gitlab-mr-review`, the post-change working tree for `red-team` — so any claim about existing code, callers, or framework behavior is verified against that declared state.

Invoked by the `gitlab-mr-review` or `red-team` skill, as a child of `execute-runner`, or directly, with:

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

## execute-runner.js

Execute flow. It executes an approved plan note and runs eight phases in order. The script calls one agent at a time, except in the Red team phase, where the `review-mr` child fans out its panel, its cold dimensions, and their verifiers in parallel:

- **Prep**: a `toolkit:verifier` (`prep:baseline`) records the branch, the `git status --porcelain` lines, and a baseline run of the repo's verify or test command with the names of the checks that fail. It runs `verifyCommand` when that arg is set, and otherwise finds the command in AGENTS.md, CLAUDE.md, VERIFY.md, or the package manifest. It runs any verify or test suite, such as `bash verify.sh`, with stdin from `/dev/null`, because a suite that reads stdin hangs when stdin is a pipe. The validation verifiers carry the same stdin rule. If it finds no verify command, it runs none and returns `command` as `none`, `exitCode` as -1, and `failing` as the one sentence `No verify command was found`.
- **Implement**: one `toolkit:implementer` per Implementation Step, labelled `implement:<n>`, in plan order. Each prompt carries the full plan, the worker's own step, and the paths that earlier steps changed. Each worker returns `changedPaths`, `deviations`, `checksRun`, `result`, `blockers`, and `topicMaterial`.
- **Verify**: the script splits the Validation Steps with the Implementation Steps rule below and hands them to the verifier as numbered `STEP <n>:` blocks, asking for exactly that many results in order. A `toolkit:verifier` (`verify:validation`) runs each STEP it can run here and reports it as `pass` or `fail` with evidence, `manual` with the reason for a step that needs a human or another session, or `pre-existing` for a step that fails only on a check the baseline already lists as failing. If a step fails, one `toolkit:implementer` (`fix:validation`) fixes only what makes the failing steps pass, and `verify:revalidation` runs the steps again. Manual and pre-existing steps never trigger the fix and never block. A run whose steps are all manual does not block, and `validation.allPass` is false. After every validation run, including `verify:final`, the script compares the number of results with the number of Validation Steps. On a mismatch it blocks. After `verify:validation`, a mismatch also adds one sentence per `fail` result and stops the run the way a step still failing after revalidation does: no fix round, no child, and no later phase.
- **Red team**: a `toolkit:verifier` (`diff:red-team`) runs exactly the capture commands from `repoRoot` and nothing else, writes the slice diff into `scratchDir`, and returns `diffPath`, `hash12`, `empty`, and `paths`. `paths` holds the repo-relative paths the capture covers: the output of `git -c core.quotePath=false diff HEAD --name-only` plus `git -c core.quotePath=false ls-files --others --exclude-standard`. The `core.quotePath=false` setting keeps a non-ASCII filename as written, because git otherwise prints it in quoted octal form. Each untracked file is diffed with `git diff --no-index -- /dev/null "$f"`, where `--` stops a filename that starts with a dash from reading as a git option. The script then calls the `toolkit:review-mr` child workflow with that diff, a context block, the `red-team` repoState sentence, the panel `toolkit:code-reviewer`, `toolkit:silent-failure-hunter`, and `toolkit:pr-test-analyzer`, and the two cold dimensions `cold-read` and `external-reviewer`. The context block carries the plan Objective, the paths changed so far, the repo rules note, and the `red-team` instruction to run embedded commands against a scratch fixture. If the child's `dead` list is not empty, the script blocks and still runs the fix loop on the confirmed findings. If the child returns no `dead` array, as a `review-mr` that predates the field does, the script also blocks.
- **Fix**: for each round up to `maxFixRounds` while confirmed findings stay open, a `toolkit:implementer` (`fix:<round>`) fixes every open finding, and a `toolkit:verifier` (`recheck:<round>`) returns one result per finding. A finding is resolved when a recheck result with the same file and title reports `resolved: true`. Two findings with the same file and title resolve together, because `review-mr` returns no finding id. A `fix:<round>` that returns blockers ends the fix loop, so no recheck and no later round runs.
- **Cold read**: a `toolkit:verifier` (`diff:final`) captures the diff again. If that capture is empty, the script blocks and skips the cold read. Otherwise one `toolkit:code-reviewer` (`cold:read`) reads it with the repoState sentence, the `external-reviewer` prompt, and no context block. The reader treats comments and doc sentences as claims and marks a finding verified only when the tree confirms it. A verified finding blocks. A finding with `verified: false` is returned in `coldUnverified` and does not block. The script runs no cold fix.
- **Doc pass**: only when `blocked` is still empty, a `toolkit:implementer` (`doc:pass`) applies the Doc Update Pass from `skills/execute-workflow/SKILL.md` under `pluginRoot` to the slice. If a fix round ran or the doc pass changed files, `verify:final` runs the Validation Steps once more with no fix round. `diff:post-doc` then captures the tree the user commits. If that capture is empty, the script blocks and sets the `postDoc` hash, path, and paths to null. A blocked slice skips `doc:pass`, `verify:final`, and `diff:post-doc`, adds no new `blocked` sentence, and defers the doc pass to the conductor, the same as the remember pass.
- **Remember**: only when `blocked` is still empty, a `toolkit:implementer` (`remember:pass`) runs the remember brief from the obsidian-topic command with its values filled in and returns `proposals` (each with `path`, `action`, `scratch`, and `factsFrom`), `topicsUpdated`, `rememberLine`, and `blockers`. The prompt carries the plan's Related Topics section under `RELATED TOPICS`, so the worker can stub a topic the plan names. A remember worker that returns blockers blocks the run and sets `remember.ran` to false.

Every agent prompt except the remember pass carries the git rule: in `repoRoot`, git is read-only, limited to `git status`, `git diff`, `git log`, `git ls-files`, `git branch --show-current`, `git remote get-url`, `git symbolic-ref` with one ref argument, and `git merge-base --is-ancestor`, and mutating git is allowed only inside a fresh fixture under `scratchDir`. A `-c core.quotePath=false` prefix on one of these commands keeps it read-only. The remember prompt says to run no git command. The scratch-only rule, that embedded commands run only against scratch fixtures under `scratchDir` and never against `repoRoot`, goes only to the review panel context block, both cold dimension prompts, and `cold:read`. The implementers and the validation verifiers run the plan's own commands in `repoRoot`, so they get the git rule alone. The implement, fix, doc pass, and remember prompts carry the blocker rule: a worker that meets a denied or impossible step, command, or tool call records it as one `blockers` sentence and stops instead of working around it.

The script reads each section of `planContent` from its `## <name>` heading to the next `## ` heading outside a fenced code block, so a fenced line that starts with `## ` stays inside the section. A fence opens on a line of 3 or more backticks or tildes with an optional info string, and it closes only on a line of the same character at least as long with nothing else on it. This is the rule `scripts/validate-plan.py` applies. Inside Implementation Steps, if at least one `### ` line outside a fence starts with a number followed by `.` or `)`, those numbered `### ` headings split the steps and every other `### ` line stays inside its step. Otherwise a line outside a fence that opens with a number followed by `.` or `)` and a space starts a step. Text before the first step joins step 1. A section with no step marker is one step. The script splits the Validation Steps with the same rule. With numbered Validation Steps, a trailing paragraph such as a Tripwires block joins the last STEP. With bullets or prose, the whole section is one STEP and gets one result.

The script writes no file itself, and no worker runs mutating git in `repoRoot`. Its verifiers write the diff captures under `scratchDir`, and on a clean run the remember worker writes vault notes and `remember-*.md` scratch files. The `execute-flow` skill records the result on the plan note, runs the consent gate, writes the slice marker, and suggests the commit.

Invoked by the `execute-flow` skill (or directly) with:

```
args: {planName, repoRoot, repoName, planContent, recallHits, scratchDir, pluginRoot, vaultRoot, knownEvidence?, verifyCommand?, maxFixRounds?}
```

- `planName` (required): the plan note name.
- `repoRoot` (required): absolute path to the checkout the workers change.
- `repoName` (required): the repo name every prompt carries.
- `planContent` (required): the full text of the approved plan note.
- `recallHits` (required): the text output of `topic-recall.py` for the plan's key terms.
- `scratchDir` (required): absolute path to the session scratchpad, where the captures and fixtures go.
- `pluginRoot` (required): absolute path to the installed plugin root, which the doc pass and the remember pass read from.
- `vaultRoot` (required): the vault root folder, `<vault_path>/<root_folder>` from `~/.claude/obsidian-sync.json`.
- `knownEvidence` (optional): facts the conductor already holds.
- `verifyCommand` (optional): the command the baseline verifier runs.
- `maxFixRounds` (optional): a non-negative integer that caps the fix rounds after the panel. Default 1 when absent or null. Any other value that is not a non-negative integer makes the script throw an Error that names the value.

The script throws if any required arg is missing or is not a non-empty string, and throws `execute-runner: the plan has no Implementation Steps` when that section is empty.

It returns `{baseline, steps, validation, review, coldResidual, coldUnverified, docPass, remember, changedPaths, planChanges, diffHashes, diffPaths, diffFiles, blocked, incomplete}`:

- `baseline`: `{branch, status, verify: {command, exitCode, failing}}` from the Prep phase.
- `steps`: one entry per Implementation Step worker that returned, in plan order. The fix, doc pass, and remember workers are not in it.
- `validation`: `{results, runs, allPass, manualChecks, preExisting}`, where `results` holds one `{step, status, evidence}` per result the verifier returned and `runs` counts the validation runs. `allPass` is true only when there is at least one result and every result is `pass`. `manualChecks` and `preExisting` hold one `<step>: <evidence>` line per `manual` or `pre-existing` result, where `<step>` is the first line of the result's `step` field without a trailing period. Null when the build stopped before `verify:validation` returned, including when that verifier died. When the run stopped after it returned, it holds the latest results. For a plan with no Validation Steps, it is `{results: [], runs: 0, allPass: false, manualChecks: [], preExisting: []}`, and `blocked` carries the no-Validation-Steps sentence.
- `review`: `{panel, dimensions, confirmed, fixed, open, refuted, unverified, openQuestions, dead, rounds}`, or null when the child did not run or did not return. `panel` names the reviewers the script asked for. `dead` is the child's `dead` list: the reviewers and dimensions whose agent returned nothing. It is an empty array when the child returned no `dead` array.
- `coldResidual`: the cold read's findings with `verified: true`, or null when the cold read did not run or returned nothing.
- `coldUnverified`: the cold read's findings with `verified: false`, or null when the cold read did not run or returned nothing.
- `docPass`: `{docsUpdated, deferred, distributed, changedPaths, blockers, topicMaterial}`, or null when the doc pass did not run, including when the slice was already blocked, or returned nothing.
- `remember`: `{ran, material, proposals, topicsUpdated, rememberLine}`. When anything blocked or the pass died, `ran` is false, `proposals` and `topicsUpdated` are empty, `rememberLine` is empty, and `material` still carries the topic material. When the remember worker returns blockers, `ran` is false, `proposals` and `rememberLine` are empty, and `topicsUpdated` keeps the notes the worker reports it touched.
- `changedPaths`: the union of the step, fix, and doc pass paths.
- `planChanges`: lines in the forms `Step N: <deviation>`, `Validation fix: <result>`, `Validation fix deviation: <deviation>`, `Fix round R: <deviation>`, `Fix round R resolved: <keys>`, and `Doc debt: <deferred>`.
- `diffHashes`, `diffPaths`, and `diffFiles`: `{redTeam, final, postDoc}` from the three captures, holding the `hash12`, the `diffPath`, and the `paths` list of each capture, with null for a capture that failed or did not run. `postDoc` is also null when the post-doc capture is empty.
- `blocked`: one plain sentence per reason the slice is not done, or an empty array.
- `incomplete`: the labels of the stages that died.

`blocked` gets these sentences:

- `The plan has no Validation Steps, so nothing proves the slice.`
- `The <who> <label> returned nothing.` for each dead stage, which also lands in `incomplete`.
- `The <who> <label> reported blockers: <sentences>` for each worker that returned blockers, including the step, fix, doc pass, and remember workers.
- `Validation returned N results for M steps.` for each validation run whose result count differs from the number of Validation Steps.
- `Validation step failed: <first line>.` for each `fail` result of a `verify:validation` run whose result count differs from the number of Validation Steps.
- `Validation step failed after one fix: <first line>.` for each step still failing after `verify:revalidation`.
- `The diff after implementation is empty.`
- `The review-mr child workflow returned nothing.` when the child returns null.
- `The review-mr child workflow failed: <message>.` when the child throws.
- `The review panel did not report which reviewers ran.` when the child returns no `dead` array.
- `The review panel lost N reviewers: <names>.` when the child's `dead` list is not empty, with the names joined by a comma and a space.
- `Fix rounds are exhausted at maxFixRounds M with N confirmed findings open.`
- `The diff hash changed from <a> to <b> with no fix round.` when the `diff:red-team` and `diff:final` hashes differ and no fix round was launched. A launched `fix:<round>` counts even when it returned nothing.
- `The diff before the cold read is empty.`
- `The diff after the doc pass is empty.`
- `The cold read left N verified findings open.`
- `Validation step failed after the doc pass: <first line>.` for each step that fails in `verify:final`.

In the validation sentences, `<first line>` is the first line of the result's `step` field, such as `STEP 1: Run the unit tests`, without a trailing period.

A dead stage never throws. A dead `prep:baseline` lets the run continue. A dead implementer or a step with blockers stops the build: every later phase is skipped, `review`, `validation`, `coldResidual`, `coldUnverified`, and `docPass` are null, and `remember.ran` is false with the material kept. A dead `verify:validation`, `fix:validation`, or `verify:revalidation`, a `verify:validation` result count mismatch, or a step still failing after revalidation, stops the run the same way, except that `validation` keeps the latest results when `verify:validation` returned. A null or empty `diff:red-team` capture skips the child and the fix loop. A dead `fix:<round>` or `recheck:<round>`, or a `fix:<round>` with blockers, ends the fix loop without the exhausted sentence. With `maxFixRounds` 0, no fix round runs and any confirmed finding blocks with the exhausted sentence. A null or empty `diff:final` capture blocks and skips the cold read, so the doc pass does not run either. A null capture leaves its `diffHashes` entry null. A dead `doc:pass` or a `doc:pass` with blockers blocks, so the remember pass does not run, while `verify:final` and `diff:post-doc` still run under their own conditions. A null or empty `diff:post-doc` capture blocks, leaves `diffHashes.postDoc` null, and skips the remember pass, so the skill writes no slice marker.

Tests: `bash plugins/toolkit/workflows/tests/execute-runner/run-tests.sh` runs 84 control-flow cases that drive the script with a scripted agent stub, which records each call's agentType, phase, and schema, and a `workflow()` stub that records the child call's args. The suite needs `node`, and `verify.sh` also runs it.

## post_mr_comments.py

Lives at `plugins/toolkit/skills/gitlab-mr-review/scripts/` — skill-local, not a general toolkit script. Posts review findings as positioned discussions on the GitLab MR: reads a `comments.json` (host, project, MR IID, the head sha the diff was reviewed at, the diff path, and a list of `{path, anchor, body}` comments plus an optional summary note), resolves each comment's `anchor` against the added lines in the diff (exact match first, then substring) to find a line number, then posts a positioned discussion per comment — falling back to an unpositioned discussion, prefixed with file:line, if GitLab rejects the position. It aborts up front if the MR's head sha has moved since the diff was fetched, since anchors may be stale. `--dry-run` prints what would be posted without posting.

This is a separate, explicit step — never automatic. The skill only runs it when the user asks, in that same session, to post the review to the MR; producing the review itself never triggers it.

Tests: `bash plugins/toolkit/scripts/tests/post-mr-comments/run-tests.sh` (5 behavior cases over the `GITLAB_TOKEN` guard: unset, empty, whitespace-padded, embedded-newline, and a well-formed fake that must pass through; also run by `verify.sh`).
