---
title: Workflow script authoring
summary: Constraints on writing and testing the toolkit's Workflow scripts, and the verify.sh conventions a new script or check must follow.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-10-19
source_refs:
  - plugins/toolkit/workflows/
  - plugins/toolkit/workflows/tests/plan-builder/
  - plugins/toolkit/workflows/tests/execute-runner/
  - plugins/toolkit/workflows/tests/review-mr/
  - verify.sh
  - plugins/toolkit/hooks/tests/fixtures/session-start/
---
<!-- managed-by: toolkit -->

# Workflow script authoring

The scripts under `plugins/toolkit/workflows/` run through the Workflow tool. What each script does and returns is in [workflows.md](../workflows.md). This page covers how a script must be written so that it parses and tests cleanly, and the `verify.sh` conventions a new script or check must follow.

## Naming a script

- A skill and a workflow script cannot share a name, because both register in the same `toolkit:` namespace and the workflow shadows the skill. The `plan-flow` skill therefore launches the `plan-builder` script, the `execute-flow` skill launches the `execute-runner` script, and the `ship-flow` skill launches the `ship-runner` script.

## Parsing a script

- `node --check` exits 0 on a workflow script that has syntax errors. A file that starts with `export const meta` parses as a module and reports nothing, and the script bodies use top-level `await` and `return`, which no plain parse mode accepts.
- The real check strips `export ` from `export const meta` and compiles the body with the AsyncFunction constructor, `Object.getPrototypeOf(async function () {}).constructor`. `verify.sh` does this in its `WF_PARSE` one-liner for every `workflows/*.js` file.

## Writing prompts

- A prompt is a template literal, so text inside it cannot contain an unescaped backtick. An unescaped backtick ends the string. Shared prompt text such as `RULES` in `plan-builder.js` leaves out code-style markup for that reason.
- If a prompt key names two things, the prompt must name each one separately. In `plan-builder.js`, `relatedTopics` is both a plan section and a top-level list. `RULES` says the section holds one wiki link per line and the list holds plain names. A rule that says only "relatedTopics are a few plain names" leads the planner to return the section as a comma list.
- `review-mr.js` drops `contextBlock` from the prompt of a cold dimension and gives every custom dimension no `agentType`. A rule that a cold reviewer must obey, such as read-only git in `repoRoot`, must be written inside the dimension prompt itself.
- `REVIEW.md` reaches the panel only inside `contextBlock`. `execute-runner.js` appends its `reviewRules` arg there, so the registry reviewers, the non-cold custom dimensions, and every verifier read it, and a cold dimension never does. `review-mr.js` takes no argument of its own for it.
- `review-mr.js` adds `contextBlock` to every batched verifier prompt, whatever the dimension. `cold: true` hides the context from the cold reviewer only, so text placed in `contextBlock`, such as the `SETTLED DECISIONS` block, still reaches the verifiers of a cold dimension's findings.
- `GIT_RULE`, `HOOK_RULE`, and `DOCTRINE` in `execute-runner.js` interpolate `repoRoot`, `scratchDir`, and `pluginRoot`. A copy of their text outside the runner, such as a briefing the `execute-flow` skill sends, must substitute those values.
- `runValidation` in `execute-runner.js` builds one prompt for `verify:validation`, `verify:revalidation`, and `verify:final`. That prompt carries `HOOK_RULE` and "Change no file" but not `HOOK_WRITE_RULE`, which only the prompts built on `SHARED` carry. A prompt sent to `toolkit:verifier` must not tell it to use the Write tool, because the verifier has no Write.
- `execute-runner.js` declares a top-level `strList` as a JSON schema fragment for the result schemas. An arg check that tests for an array of strings must use another name, as `isStrList` does. A new optional arg changes three places: the args list in the error text the script throws, the args signature in the `execute-runner` section of [workflows.md](../workflows.md), and a bullet in the arg list under that signature.

## Runtime behavior a script relies on

- `pipeline()` returns one entry per input item, in input order. A stage that throws turns that item's entry into `null` and keeps its position. `plan-builder.js` relies on `findings[i]` matching `areas[i]`.
- `plan-builder.js` sets `critiqueStale` by comparing the rendered plan text with the text the last returned Invert critique saw, not by object identity. A cold revise that returns identical text therefore leaves `critiqueStale` false.
- `plan-builder.js` checks that case separately. If the cold revise returns text identical to the draft, the script counts it as unapplied, keeps the cold material objections open, and adds a `blocked` reason.
- The exhausted-rounds check in `plan-builder.js` must ignore `revise:cold` when it reads the dead-revise list, because the cold revise is not an Invert round.
- `workflow(nameOrRef, args)` throws on an unknown name or a child failure and returns null when the child is stopped. `execute-runner.js` wraps its `review-mr` call in try/catch and turns both outcomes into a `blocked` sentence, so a failed child never ends the parent run.
- `review-mr` drops a dead reviewer or dimension silently unless the caller reads the `dead` list it returns, so `execute-runner.js` blocks when that list is not empty. It also blocks when the `verifierDead` list is not empty, because `review-mr` routes the findings of a chunk whose verifier returned nothing to `unverified` without failing, and the slice would otherwise finish with that dimension unchecked. The scratch-only rule in `execute-runner.js`, `SCRATCH_ONLY`, reaches only the panel context block, the two cold dimensions, and `cold:read`, because a worker whose job is to run commands in the repo cannot also obey a rule to run commands only against scratch fixtures.
- `execute-runner.js` captures the diff three times: `diff:red-team` for the panel, `diff:final` for the cold read, and `diff:post-doc` after the doc pass for the remember brief and the slice marker. Only the post-doc hash matches a later `red-team` capture of the tree the user commits, and only when the consent gate accepted no repo doc and the `execute-flow` skill ran no cold-read fix. If the red-team and final hashes differ while no fix round ran, something other than a fix worker changed the tree, and the script blocks. That check reads `fixAttempts`, the count of launched fix rounds, not the recorded `rounds`, because a fix worker that died or reported blockers may still have edited the tree. A fix round enters `rounds` as soon as its `fix:<n>` agent returns a result, before its recheck, so a round whose recheck died still counts. `toolkit:verifier` has Read, Grep, Glob, Bash, WebFetch, and WebSearch, and no Write or Edit, so the capture prompt writes the diff through a shell redirect into `scratchDir`. The captures run read-only git only, because the git-safety `## Flows` section lets the execute flow's agents run read-only git and never lets the flow mutate git state.
- `execute-runner.js` also blocks when the child returns no `dead` array. Without a `reviewMr` arg it resolves the child by the registered name `toolkit:review-mr`, so a runner that is newer than the installed `review-mr` blocks every run until the plugin updates. The `execute-flow` skill passes `reviewMr` as `{scriptPath}` when `repoRoot` holds `plugins/toolkit/workflows/review-mr.js`, which is how the toolkit repo runs its working-tree child. A refused ref lands in `blocked` as `The review-mr child workflow failed: <message>.` Open item: the `red-team` skill does not read `dead` yet, so a dead reviewer in its runs goes unreported.

## Reading plan content

- `execute-runner.js` reads a section from its `## <name>` heading to the next line outside a fenced block that starts with `##` and a space or tab. A fence opens on a line of 3 or more backticks or tildes with an optional info string, and it closes only on a line of the same character at least as long with nothing else on it, the rule `scripts/validate-plan.py` applies. A split that ignores fences ends a step early at a fenced `## ` line.
- Inside Implementation Steps, `execute-runner.js` splits on numbered `###` headings, else on unnumbered `###` headings, else on numbered lines, under the conditions the execute-runner section of `docs/workflows.md` states. The `execute-flow` skill counts steps by the same rule before launch, so the stated count matches the implementers the script spawns.
- `execute-runner.js` splits Validation Steps by the same step rule and sends them to the verifier as numbered `STEP <n>:` blocks, with an instruction to return exactly that many results. The count check and the verifier therefore agree whatever list style the plan uses. A bulleted list under fewer than two `###` headings has no step marker, so it becomes one `STEP 1:` block and gets one result.

## Gating on a script result

- A gate that reads one signal while the script produces several approves results it must reject. A gate on `approveIf.meets` alone can approve a plan that has a `stop` verdict, exhausted rounds, a dead critic, or a stale critique.
- A script whose result feeds an approval gate returns an explicit `blocked` list with one sentence per reason, and the gate requires that list to be empty. The `plan-flow` skill reads `blocked` this way.
- A non-null worker result is not a success. Each `execute-runner.js` worker prompt tells the worker to record a denied or impossible step as one `blockers` sentence and stop instead of working around it, and the script treats non-empty `blockers` as a failure: it adds a `blocked` sentence. An implement or `fix:validation` worker with blockers stops the build, a `fix:<round>` with blockers ends the fix loop, blockers from `doc:pass` skip the remember pass, and blockers from `remember:pass` set `remember.ran` to false.
- A validation failure the slice did not cause must not send a fix worker. `execute-runner.js` records the checks that fail before any change in `prep:baseline`, and the validation verifier reports a step that fails only on one of those as `pre-existing`, which never triggers the fix and never blocks.
- A stage that writes to the repo or the vault runs only after every check it depends on passed. If `blocked` holds a sentence when the doc pass starts, `execute-runner.js` skips the doc pass, the final validation, and the post-doc capture. If `blocked` holds a sentence when the remember pass starts, the script skips that pass too and returns the topic material with `remember.ran` false for the conductor. An empty post-doc capture adds a `blocked` sentence and is set to null, so no slice marker keys to the hash of an empty diff. A verified cold-read finding and an unverified panel finding add no `blocked` sentence. The script returns them in `coldResidual` and `review.unverified`, so the doc pass and the remember pass still run, and the `execute-flow` skill holds the slice marker and the commit suggestion until the user settles each one.
- If the first validation returns a result count that differs from the step count, the script adds the count sentence and one sentence per failing result, and returns before the red-team capture.
- One cause yields one `blocked` sentence. When a fix or recheck stage dies, or a fix worker reports blockers, the script skips the exhausted-rounds sentence, because the dead-stage or blockers sentence already names the cause.
- The `verifierDead` check in `execute-runner.js` is its own `if` after the `dead` checks, not another branch of them. A run that lost both a reviewer and a verifier reports both sentences, because they are two causes.

## Testing a script

- `workflows/tests/plan-builder/harness.mjs` compiles the script with the same AsyncFunction method and passes in stub `args`, `agent`, `pipeline`, `phase`, and `log`. `workflows/tests/execute-runner/harness.mjs` passes no `pipeline` stub. Its parameters are `args`, `agent`, `workflow`, `phase`, and `log`, in that order, and the `workflow` stub records each child call's ref and args, and returns or throws the value scripted under the `workflow:review-mr` label. `workflows/tests/review-mr/harness.mjs` passes `args`, `agent`, `pipeline`, `phase`, and `log`, and its `pipeline` stub calls the second stage with the first stage's result and the item, as the runtime does, because `review-mr.js` reads the dimension from that second argument. The plan-builder stub calls each stage with one argument, so it cannot drive `review-mr.js`.
- The stub `agent` returns the scripted result for the call's `label`, or `null`, so a case kills a stage by leaving its label out. The plan-builder stub `pipeline` follows the runtime rule above: a stage that throws leaves `null` in that item's position.
- A fence tracker that only toggles on each fence line passes a nested-fence case whenever the fence lines come in even pairs. The nested case must put the `## ` heading inside the inner block, as the execute-runner suite's four-backtick case does.
- The execute-runner harness's `run()` returns the child workflow calls in `calls`, so a case reads the panel context block at `calls[0].args.contextBlock`. The default `run()` reaches only `implement:1`, `implement:2`, `implement:3`, `doc:pass`, and `remember:pass` among the implementer labels. The `FULL_RUN` fixture in `harness.mjs` also reaches `fix:validation` and `fix:1`, so a case that claims to cover every implementer prompt must run `FULL_RUN`. The default `implement:3` returns `src/c.js`, so a default run's `changedPaths` is `src/a.js`, `src/b.js`, and `src/c.js`.
- `execute-runner.js` picks the panel from the `diff:red-team` paths joined with every implementer's `changedPaths`. The execute-runner harness's `onPaths(paths)` helper therefore scripts every implementer with no changed paths, so a panel-rule case sees only the capture paths it names. `rulesOf(bullet)` builds a minimal `REVIEW.md` with one High-risk paths bullet for the `reviewRules` cases, and `STEP_BACK(n, rounds)` builds the exact step-back sentence.
- The review-mr harness's `finding`, `verdict`, and `verdictsOf` helpers build a cited finding and its verdict. The default finding scores 0.68 and cites `src/a.js:4`. The case `a second-chunk verdict at index 0 routes to the ninth finding` pins the chunk-local verdict index, so a change that numbers verdicts across chunks fails it.

## verify.sh conventions

- The run passes only when `pass + skip` reaches the floor on the last line of `verify.sh`. A check gated on `node` must emit exactly one `skip` for each `ok` it replaces, or a run without `node` falls below the floor.
- `verify.sh` runs the hook fixture suite as one check, so a fixture failure costs one pass, not one per fixture.
- The agent and skill counts are hardcoded in two places: the Structure checks in `verify.sh` and the expected welcome line in `hooks/tests/fixtures/session-start/06-startup-welcome.json`. [agents.md](../agents.md) states the agent count too. Adding or removing an agent or a skill means updating all of them.
- Three files state the case count of each behavior suite. `verify.sh` passes it to `suite_ok` as the minimum passed count, section 1 of `VERIFY.md` gives it after the suite name, and the suite's Tests line in [scripts.md](../scripts.md) or [workflows.md](../workflows.md) gives it too. Adding or removing a case means updating all three.
- A check that two files carry the same sentence must extract the sentence from both files and compare them, not hardcode it. The git-permission checks grep `Do I have permission[^?]*?` from `doctrine/git-safety.md` and from each of `skills/plan-flow/SKILL.md`, `skills/execute-flow/SKILL.md`, and `skills/ship-flow/SKILL.md`, and require each skill match to equal the doctrine match and be non-empty. The option checks grep the numbered option lines that end in writes `none`, `push`, or `release` from the three skills, and require `plan-flow` to carry exactly three such lines, `execute-flow` to carry the same three, and `ship-flow` to carry the same three as `execute-flow`.
- Every doctrine index line in `plugins/toolkit/CLAUDE.md` opens with a bold file name followed by an em dash. Any edit to such a line puts that existing em dash on an added line of the diff. A check for "no em dash on added lines" must compare each added line with the line it replaced.
- To exercise a run without `node` on a machine that has it, build a scratch directory of symlinks to every PATH tool except `node`, and run `verify.sh` with that directory as PATH. Build the directory under `/bin/bash -c`, because zsh does not word-split an unquoted `$PATH` expansion, so a loop written for bash sees one word.
- The `REVIEW.md` check strips backticks and quotes with `tr -d '\140\042\047'`, octal escapes, because a literal backtick inside the `$(...)` substitution breaks it.
- A check greps `review-mr.js` for the literal `toolkit:coupling-reviewer`, so the `REVIEWERS` array must keep that full string. A refactor that builds the agent names from short keys fails the check.

## Related docs

- [workflows.md](../workflows.md) for what `review-mr.js`, `plan-builder.js`, `execute-runner.js`, and `ship-runner.js` take and return.
- [VERIFY.md](../../VERIFY.md) for running `verify.sh` and the suites.
- [context-plan-note-section-checks.md](context-plan-note-section-checks.md) for how the validator and hooks read plan note sections.
- [context-git-tree-state-capture.md](context-git-tree-state-capture.md) for the git output quirks the diff captures handle.
- [context-ship-flow-constraints.md](context-ship-flow-constraints.md) for the invariants `ship-runner.js` and its suite keep.
- [context-review-scoring.md](context-review-scoring.md) for the scoring, routing, and panel rules `review-mr.js` and `execute-runner.js` share.
