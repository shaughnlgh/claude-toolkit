---
name: execute-flow
description: >-
  Execute flow: one run that executes an approved plan note end to end. Use only when
  the user asks for the execute flow by name ("run the execute flow", "execute flow
  this plan"). Never fires from crawl. Asks the git-permission question unless an
  earlier flow in the session recorded the answer, checks the tree and the branch, runs
  topic recall, moves the plan note to in-progress, launches the execute-runner workflow
  (one implementer per Implementation Step, the plan's Validation Steps with one fix
  round, the review-mr panel with a bounded fix loop, a cold read whose verified findings
  do not block, and the Doc Update Pass and the remember pass when nothing blocked), records
  the result on the plan note, asks the user to dismiss, fix, or hold each verified
  cold-read finding, and closes with a report that carries a commit suggestion only when
  nothing blocked and every such finding is dismissed or fixed. Never
  mutates git state and runs read-only git only through its agents. Do NOT fire when no
  plan note exists for the work (plan-flow or plan-workflow owns that), when the plan
  note's status is neither approved nor an in-progress state this flow resumes or
  reruns, or on a slice already under execute-workflow by hand.
---

# Execute Flow

Execute-flow is the conductor side of the `execute-runner` workflow, shipped with this plugin at `../../workflows/execute-runner.js` relative to this skill's base directory. The script runs a baseline check, one implementer per Implementation Step in order, the plan's Validation Steps with one fix round, a diff capture, the `review-mr` child workflow as the panel, a bounded fix loop, a second capture, a cold read, and, only when nothing blocked, the Doc Update Pass, a final validation, a post-doc capture, and the remember pass. A verified cold-read finding does not block those passes. The conductor asks the git-permission question, checks the tree and the branch, runs recall, moves the plan note to in-progress, launches the script, records the result, runs the consent gate, adjudicates the verified cold-read findings with the user, writes the slice marker, and closes with the report. The script writes no vault note and runs no mutating git command. The conductor writes only the vault note and scratchpad files.

## 1. Trigger

Fire only when the user asks for the execute flow by name. A `crawl` route never fires this skill. If the slice is already under `execute-workflow` by hand, do not fire. When the installed plugin does not carry this skill, the conductor reads `plugins/toolkit/skills/execute-flow/SKILL.md` from the toolkit checkout by path and follows it as written.

The plan note must exist. `planName` is its `plan` frontmatter value. Read its `status` and the summary of its last `sessions` entry, then pick the run:

- `status: approved` starts a fresh run.
- `status: in-progress` with a last entry summary that begins `execute-flow blocked:` starts a fresh run. A blocked run keeps the note at in-progress, so this is how the user reruns the slice after settling the blocked reasons. A rerun needs the earlier run's changes committed or discarded first (section 3).
- `status: in-progress` with a last entry summary that begins `execute-flow adjudicating:` resumes at section 8 from the findings, hashes, and report inputs that sections 6 and 7 recorded on the note, with no new run and no recall. Section 8 checks the tree by capture before it asks. Sections 2 to 7 do not run, and sections 8 to 10 read the run's result from the note. The `<scratchpad>/execute-flow-<planName>.runid` file still names the run for the marker. If that file is gone, section 9 skips the marker and the report says so.
- `status: in-progress` with a last entry summary of `execute-flow run started` under another session id starts a fresh run, because that run died before section 6 or section 7 recorded its outcome.
- `status: in-progress` with a last entry summary of `execute-flow run started` under this session's id resumes that run with `resumeFromRunId` when `<scratchpad>/execute-flow-<planName>.runid` exists, and completed agents replay from cache. Section 5 writes that file only after the Workflow tool returned a `runId` and deletes it before each fresh launch, so it always names the latest run. Without that file, the launch never happened, so it starts a fresh run.

If the note matches none of these, state the status and stop.

`repoRoot` is the absolute path of the checkout that the plan note's `repo` frontmatter names, and `repoName` is its basename. If the session does not know that path, ask the user for it. `<plugin-root>` is the installed plugin root, resolved with `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json`.

## 2. Git permission

Before anything else, check `<scratchpad>/flow-git-permission`. If the file exists, an earlier flow in this session recorded the answer, so read it and do not ask. If the file does not exist, this flow is the first in the session, so ask once through AskUserQuestion: "Do I have permission to run git commands on your behalf for every flow in this session?" with the options in this order:

1. "No, suggest only (Recommended for a work repo)", with the description "Every flow in this session suggests git commands and runs none.", writes `none`.
2. "Yes, commit, branch, push and open the MR or PR, never merge", with the description "Covers every flow in this session, including a later flow in this session that runs git, without asking again.", writes `push`.
3. "Yes, through merge and tag", with the description "Covers every flow in this session, including a later flow in this session that runs git, without asking again.", writes `release`.

Write the answer to `<scratchpad>/flow-git-permission` as `none`, `push`, or `release`. A missing, empty, or unrecognised file reads as `none`, so until the question is answered no flow has git permission. The answer holds for every flow run in this session, so a later flow in the same session reads the file and never re-asks. The execute flow never mutates git state under any answer, and its agents run only read-only git in the repo. The `## Flows` section of the git-safety doctrine (`../../doctrine/git-safety.md` from this skill's base directory) defines what each answer unlocks.

## 3. Tree state

Before any status change, spawn one `toolkit:verifier` that runs `git -c core.quotePath=false status --porcelain -uall`, `git branch --show-current`, `git remote get-url origin`, and `git symbolic-ref --short refs/remotes/origin/HEAD` in `<repoRoot>`. When the branch output is not empty and the symbolic-ref output is `origin/<default>`, it also runs `git merge-base --is-ancestor <branch> origin/<default>` and returns its exit code. It runs no other command and returns each output verbatim, with the error text for a command that fails. Keep the branch and the remote URL for the report. The remote URL feeds the `Repo:` header line. If the repo has no `origin` remote, the `Repo:` line names `repoRoot`.

Check the branch first, as the git-safety Branch check section says. The default branch is the part of the symbolic-ref output after `origin/`, never a guessed name. If the symbolic-ref command fails, ask the user for the default branch name and skip the merged check. An empty branch output means a detached HEAD. If the branch is `main`, `master`, or the default branch, or if HEAD is detached, stop before any status change. If the merged check exits 0, the branch tip is already in the default branch. A branch the user has just cut and not yet committed on gives the same exit code, so ask once through AskUserQuestion: "Branch <branch> has no commits beyond origin/<default>. Is it merged work, or a fresh branch for this slice?" with the options "Merged, stop (Recommended)" and "Fresh branch for this slice, continue". On Merged, stop before any status change. The execute flow never mutates git under any answer, so on every stop hand the user the branch command to run, with the plan note's `branch` value as the name, or `feat/<planName>` when that value is blank:

    ! cd <repoRoot> && git switch -c <branch>

Then tell the user to ask for the execute flow again on the new branch.

On a resume, skip the dirty-tree question, because the tree holds the run's own changes. If the status output is empty, continue. If it is not empty, take the foreign paths from it: on each line, the text after the two status characters and the one space that follows them, with the surrounding double quotes removed from a quoted name that holds no backslash, and both paths of a rename. Git quotes such a name for a space alone, and the capture lists it unquoted. A name git still quotes and escapes, one containing a backslash, a double quote, or a control character, is compared verbatim on both sides, quotes and escapes included, because the capture lists paths with the same quoting. Split a rename at the ` -> ` that sits outside double quotes. A name that contains ` -> ` holds a space, so git quotes it, and the separator is the only ` -> ` outside quotes. The `-uall` flag lists each untracked file, so an untracked directory never collapses to one `dir/` entry. On a rerun from `status: in-progress` (section 1), offer no Proceed: stop with the plan note untouched, and tell the user to commit or discard these paths, which the previous run's record on the plan note names, before asking for the execute flow again. Otherwise ask once through AskUserQuestion: "The tree holds changes that are not this slice: <paths>. Hold the run, or proceed and leave them out of the staging list?" with the options in this order:

1. "Hold (Recommended)", with the description "Workers are guarded by prompt text only, so the run would expose these changes to them. Settle the changes yourself, then ask for the execute flow again."
2. "Proceed, the foreign paths are named in the report and left out of the staging list", with the description "The diff captures the whole tree, so the panel and the cold read review these paths with the slice. The report names them and never stages them."

If the answer is Hold, stop with the plan note untouched. If the answer is Proceed, keep the foreign paths for section 10.

## 4. Recall

Before any status change, run recall as `plan-flow` section 3 describes (`../plan-flow/SKILL.md` from this skill's base directory), with each key term from the plan name and the Objective passed as its own quoted argument: `python3 <plugin-root>/scripts/topic-recall.py --repo <repoName> --repo-root <repoRoot> "<term one>" "<term two>"`. Read the exit code as that section says. On `0`, pass the output as `recallHits`, or `none` when the output is empty. On `2` or `3`, stop with the plan note untouched and report the exit code and stderr.

## 5. Status and launch

Before launch, count the steps the way the script parses them. A fence opens on a line of 3 or more backticks or tildes with an optional info string, and it closes only on a line of the same character at least as long with nothing else on it. Inside Implementation Steps, if at least one `### ` line outside a fence starts with a number followed by `.` or `)`, those numbered `### ` headings split the steps and every other `### ` line stays inside its step. Otherwise a line outside a fence that opens with a number followed by `.` or `)` and a space starts a step. Text before the first step joins step 1. A section with no step marker is one step for one implementer. Tell the user the step count, the first line of each step, and that a permission prompt pauses the run until the user answers it.

On a fresh run, first delete any `<scratchpad>/execute-flow-<planName>.runid` left by an earlier run, so a later resume can only pick up the latest run. Move the status only when the launch is about to happen. Load `plan-workflow`. On a fresh run, set `status: in-progress` if the note is not already there, and record this session's entry per its session rules with the summary `execute-flow run started`, with the id taken from the scratchpad path. On a resume, leave the status and the entry as they are. Write the change atomically: Write the note to a `.tmp.md` file beside it, then move it into place with `vault-fs.sh mv`. Then run `python3 <plugin-root>/scripts/validate-plan.py "<plan note path>"` and require exit 0. If the validator fails, report its output and stop. Never patch a failure silently.

Build the args:

- `planName`: from section 1.
- `repoRoot` and `repoName`: from section 1.
- `planContent`: the full text of the plan note as the status change wrote it.
- `recallHits`: from section 4.
- `scratchDir`: the absolute scratchpad path.
- `pluginRoot`: `<plugin-root>` from section 1.
- `vaultRoot`: `<vault_path>/<root_folder>`, both read from `~/.claude/obsidian-sync.json`.
- `knownEvidence` (optional): facts this session already verified, each with its file:line.
- `verifyCommand` (optional): the repo's verify or test command, when the session knows it. Without it, the baseline verifier finds the command itself.
- `maxFixRounds` (optional): the fix rounds after the panel, a non-negative integer, default 1.

When `repoRoot` contains `plugins/toolkit/workflows/execute-runner.js`, launch `{scriptPath: "<repoRoot>/plugins/toolkit/workflows/execute-runner.js"}`, otherwise `{name: "toolkit:execute-runner"}` with the `scriptPath` fallback `red-team` uses. That fallback is `{scriptPath: "<this skill's base directory>/../../workflows/execute-runner.js"}` resolved to an absolute path, used if name resolution fails. The script is named `execute-runner` because a workflow and a skill cannot share a name in the plugin registry. If the Workflow tool refuses the `scriptPath` as outside the working directory, copy the script byte-identical to `<scratchpad>/execute-runner.js`, take the first 12 characters of `shasum -a 256` for the source and for the copy, require the two to match, and launch `{scriptPath: "<scratchpad>/execute-runner.js"}`.

Write `<scratchpad>/execute-flow-<planName>.runid` only after the Workflow tool has returned a `runId`, and at once, before reading the result. It holds the `runId`, the script path, and the two sha256 prefixes when the copy rule applied. A dead run resumes with `resumeFromRunId` and the script path from that file. Completed agents return cached, so never relaunch a fresh run when a resume is possible.

The result is `{baseline, steps, validation, review, coldResidual, coldUnverified, docPass, remember, changedPaths, planChanges, diffHashes, diffPaths, diffFiles, blocked, incomplete}`:

- `steps` holds one entry per Implementation Step implementer that returned, each with `changedPaths`, `deviations`, `checksRun`, `result`, `blockers`, and `topicMaterial`.
- `validation` is `{results, runs, allPass, manualChecks, preExisting}`. It is null when the build stopped before `verify:validation` returned, including when that verifier died. When the run stopped after it returned, it holds the latest results. For a plan with no Validation Steps, it is `{results: [], runs: 0, allPass: false, manualChecks: [], preExisting: []}`, and `blocked` carries the no-Validation-Steps sentence.
- `review` is `{panel, dimensions, dead, confirmed, fixed, open, refuted, unverified, openQuestions, rounds}`, or null when the child workflow did not run or did not return. `dead` lists the reviewer names and dimension keys that died, and the script blocks when it is not empty.
- `coldResidual` lists the cold read's verified findings, which section 8 adjudicates with the user, and `coldUnverified` lists the findings the cold read could not verify. Both are null when the cold read did not run or returned nothing.
- `docPass` is the Doc Update Pass return, or null when it did not run, including when the slice was already blocked.
- `remember` is `{ran, material, proposals, topicsUpdated, rememberLine}`.
- `diffHashes` and `diffPaths` are `{redTeam, final, postDoc}`, with null for a capture that failed or did not run. `diffFiles` has the same keys, each the repo-relative paths that capture holds, or null.
- `blocked` lists one plain sentence per reason the slice is not done, and is empty when nothing blocks.
- `incomplete` lists the labels of the stages that died.

A run is blocked when `blocked` or `incomplete` is not empty. A `coldResidual` entry is never a blocked reason.

## 6. Record

Record the result under the plan note's Plan Changes During Execution, one line each:

- every `planChanges` line, including the fix-round lines.
- every `blocked` reason, every `incomplete` label, and every step blocker from `steps`. A validation result count that differs from the plan's Validation Steps count arrives as a `blocked` reason, so it is recorded here.
- every `validation.manualChecks` entry, under a line that reads "Manual checks for you".
- every `validation.preExisting` entry.
- every `review.dead` entry, as a reviewer or dimension the panel lost.
- every `review.open`, `review.unverified`, and `review.openQuestions` entry and every `coldResidual` and `coldUnverified` finding, for the user to settle. Section 8 adds each `coldResidual` outcome.
- on an unblocked run whose `coldResidual` is not empty, the section 3 branch and remote URL, the section 3 foreign paths, every `diffFiles.postDoc` path, and every `docPass.changedPaths` entry, so a resume at section 8 builds the report from the note.
- the three `diffHashes`, with "none" for a null hash.

Update this session's entry summary to the run's one-line outcome, except on an unblocked run whose `coldResidual` is not empty, where section 7 writes the summary. On a blocked run, the summary begins `execute-flow blocked:` followed by the first blocked reason, and the status stays in-progress, so section 1 starts a fresh run when the user asks again. When the slice is already blocked at the doc pass phase, the runner skips the doc pass, the final validation, and the post-doc capture, so `docPass` and `diffHashes.postDoc` are null and the record shows "none" for that hash. On an unblocked run whose `coldResidual` is null or empty, the summary begins `execute-flow finished:`. Write the change atomically and run `validate-plan.py` again, requiring exit 0. Never set `status: completed`.

## 7. Remember

If `remember.ran` is false, write each `remember.material` entry as one line to `<scratchpad>/remember-material-<planName>.md`, or the single line `none` when the material is empty. Record a line under Plan Changes During Execution that names that path, so session closure can run the pass from it. Write the note atomically and run `validate-plan.py` again, requiring exit 0. Tell the user that the remember pass did not run, that its material is in that file, and that session closure runs the pass once the blocked reasons are settled. If `remember.ran` is true, run the gate and record steps of the obsidian-topic command's Remember pass (`../../commands/obsidian-topic.md` from this skill's base directory) on `remember.proposals`, starting from `remember.rememberLine`. If a proposal's path is also in `docPass.changedPaths`, name it at the gate. Record the resulting `Remember:` line and each repo doc accepted at the gate under Plan Changes During Execution, write the note atomically, and run `validate-plan.py` again, requiring exit 0.

On an unblocked run whose `coldResidual` is not empty, update this session's entry summary only after the `Remember:` line is recorded. The summary is `execute-flow adjudicating: N verified cold-read findings`, with N the entry count, and section 8 rewrites it to begin `execute-flow finished:` only once every entry is dismissed or fixed and no Validation Step is held. Write the note atomically and run `validate-plan.py` again, requiring exit 0. The `Remember:` line and the accepted docs that this section records count as recorded report inputs, so a resume at section 8 reads them from the note.

## 8. Adjudicate the cold read

Skip this section on a blocked run (section 5) and when `coldResidual` is null or empty. A briefing in this section that names a runner constant carries that constant's text from the `execute-runner.js` that section 5 resolves. The constants are template literals, so substitute `<repoRoot>` for `${a.repoRoot}`, the scratchpad path for `${S}`, and `<plugin-root>` for `${a.pluginRoot}` in the text. The capture is one `toolkit:verifier` briefed with the runner's `CAPTURE_PROMPT`, including its step 4 path listing with `core.quotePath=false`, so a non-ASCII path matches the section 3 foreign-path comparison. It returns the `hash12` and the paths that step 4 printed. The validation verifier is one `toolkit:verifier` that runs the plan's Validation Steps on the tree, as the runner's final validation does, with the runner's `STDIN_RULE`, `HOOK_RULE`, and `GIT_RULE` text, and returns one result per step: pass or fail with evidence, or manual with a reason. A manual result joins the "Manual checks for you" list.

On a resume from section 1, run the capture first and compare its `hash12` with the last recorded hash: the section 8 capture hash when the note records one, otherwise `diffHashes.postDoc`. If the hashes differ, or the note records neither hash, stop. Rewrite the summary to `execute-flow blocked: the tree changed since the run`, write the note atomically, run `validate-plan.py` again, requiring exit 0, and tell the user that the tree changed since the run and that the slice needs a rerun. If the hashes match and the note records a held Validation Step, run the validation verifier, and record one line per held step that now passes, which clears its hold.

Ask one question per `coldResidual` entry through AskUserQuestion, in the cold read's order, then one question per held Validation Step that still fails, in batches of up to four questions per call. A batch in one call counts as one gate. On a resume from section 1, ask only about the entries the note does not record as dismissed or fixed. Each finding question reads "The cold read verified a finding in <file>: <issue>. Its fix: <fix>. Dismiss it, fix it now, or hold the run?" with the finding's file, issue, and fix quoted, and with the options in this order:

1. "Dismiss", with " (Recommended)" appended when the finding maps to one of the plan's Assumptions or Risks, which the question then names. Its description is "Records the finding on the plan note with the settled decision it restates, or no mapped decision."
2. "Fix now", with the description "One implementer applies every Fix now finding and one verifier re-checks them, once for the whole list."
3. "Hold", with the description "Ends the flow in the blocked report shape with no commit suggestion."

When the finding maps to no Assumption or Risk, append " (Recommended)" to "Fix now" instead and list it first, because the recommended option comes first.

Each held Validation Step question reads "Validation Step <step> failed after the section 8 fix: <evidence>. Fix it again or hold the run?" with the options in this order:

1. "Fix again (Recommended)", with the description "The step and its evidence join the fix round below."
2. "Hold", with the description "Ends the flow in the blocked report shape with no commit suggestion."

Ask every batch before acting on any answer. For each Dismiss, record one line under Plan Changes During Execution with the finding's file and issue and the Assumption or Risk it maps to, or `no mapped decision` when it maps to none.

If any answer is Hold, run no fix. Record each held finding and each held Validation Step under Plan Changes During Execution and keep the `execute-flow adjudicating:` summary, so asking for the execute flow again resumes this section on the same tree through section 1. Close in the blocked report shape (section 10) with no commit suggestion. Write no marker.

If no answer is Hold and at least one is Fix now or Fix again, run one fix round for the whole list, never a second in one pass through this section. Delegate one `toolkit:implementer` with every Fix now finding (file, issue, and fix), every Fix again Validation Step with its evidence, the plan's Objective, and the runner's `DOCTRINE`, `GIT_RULE`, `BLOCKER_RULE`, `HOOK_RULE`, and `HOOK_WRITE_RULE` text, the rules the runner's `SHARED` constant joins. Then delegate one `toolkit:verifier` that re-checks each Fix now finding over the implementer's `changedPaths` and returns one `resolved` result per finding. Then run the validation verifier on the fixed tree. Then run the capture. Record one line under Plan Changes During Execution per fixed finding, with the implementer's `changedPaths`, the re-check result, and the validation results. Record the capture `hash12` and its paths on one line that names them the replacements for `diffHashes.postDoc` and `diffFiles.postDoc`, so the report and a later resume read them from the note. The doc pass does not run again for the fix. If the implementer returns blockers or a re-check result is not resolved, treat each unresolved finding as held, as above. Record each failing Validation Step as a held entry under Plan Changes During Execution, and close as above. If the capture fails, record that and hold the run whatever the re-check results, with every Fix now finding held. Section 8 ran a fix when the note records any section 8 fix for this run, from this pass or an earlier one, so a resume after a partial fix still writes no marker and still reports that no panel reviewed the fix.

Once every `coldResidual` entry is dismissed or fixed and no Validation Step is held, rewrite the `execute-flow adjudicating:` summary to begin `execute-flow finished:` followed by the run's one-line outcome. Write every change to the plan note atomically and run `validate-plan.py` again, requiring exit 0. The marker and the commit suggestion wait until every `coldResidual` entry is dismissed or fixed and no Validation Step is held. `coldUnverified` entries are not adjudicated here and stay under "To settle".

## 9. Slice marker

Write the marker only when `review` is not null, `review.dead` is empty, `diffHashes.postDoc` is not null, `blocked` is empty, section 8 left every `coldResidual` entry dismissed or fixed and no Validation Step held, and section 8 ran no fix. A blocked run writes no marker. A run with a section 8 fix writes no marker, because no panel reviewed the fix. On a resume from section 1, the `runId` comes from `<scratchpad>/execute-flow-<planName>.runid`, and without that file no marker is written. The marker is `<scratchpad>/slice-<diffHashes.postDoc>.runid`, holding the `runId`, the panel hash `diffHashes.redTeam`, and the cold read hash `diffHashes.final`. The `red-team` skill keys its runid file the same way, so a later red team on the tree at the marker hash finds the marker and runs no second full panel. Repo docs accepted at the section 7 consent gate land after that hash. After an accepted doc, a later red-team capture therefore hashes differently, and red-team's rule that a runid file with another hash never suppresses a panel applies. If any condition fails, write no marker and tell the user which one.

## 10. Report

Close in the shape of `red-team` section 8 (`../red-team/SKILL.md` from this skill's base directory). The shape depends on whether the run is blocked (section 5). A run held in section 8 takes the blocked shape.

On a blocked run:

- Open with every `blocked` reason and every `incomplete` label, one per line. After a Hold in section 8, open with each held finding and each held Validation Step instead.
- Then state what the user settles: each of those reasons, and every `review.dead`, `review.open`, `review.unverified`, `review.openQuestions`, `coldResidual`, `coldUnverified`, and `validation.manualChecks` entry.
- If `docPass` is null, say that the doc pass is deferred until the blocked reasons are settled. If `docPass` is not null, say that the doc pass ran and list each `docPass.changedPaths` entry on its own line.
- If `remember.ran` is false, say that the remember pass is deferred until the blocked reasons are settled, that session closure or the `red-team` skill runs the deferred passes, and that the commit suggestion comes after they have run. Name the remember material file from section 7.
- After a Hold in section 8, say that the remember pass ran, that the commit suggestion waits until the held findings and held Validation Steps are settled, and that asking for the execute flow again resumes the adjudication on the same tree.
- Write no header lines, no commit message, no `Remember:` line, and no staging list. Never begin a line with the words `Suggested commit` in any case, with or without a leading `#` heading marker or a `*` or `**` bold or emphasis marker, because the remember-guard Stop hook matches any such line and a blocked run offers no commit.

On an unblocked run:

- Open with the Repo, Branch, and Scope header lines from the git-safety Commit handoff section. `Repo:` is the remote path from the section 3 remote URL, `Branch:` is the section 3 branch, and `Scope:` names the slice and the count of files to stage.
- Put a line that begins `Suggested commit` directly after those three lines, because the remember-guard Stop hook keys on that line. Write the message in the repo's observed convention.
- Add the `Remember:` line from section 7.
- List each file to stage on its own line: every path in `diffFiles.postDoc`, which is the reviewed diff, or in the section 8 capture paths that the note records when section 8 ran a fix, plus every repo doc accepted at the gate, minus the foreign paths from section 3. Remove a path when it equals a foreign path or starts with a foreign path that ends in `/`. Mark each accepted doc as written after review. Then give the paste-ready block from the git-safety Commit handoff section with each path named. Never suggest `git add -A`.
- Under a line that reads "To settle", list every `validation.manualChecks`, `review.unverified`, `review.openQuestions`, and `coldUnverified` entry, one per line, or "none" when all four are empty.
- If section 8 ran a fix, say that it ran after the doc pass, list its changed paths and the validation results, and say whether it touched a public surface that the doc pass did not see. Say that a later red team on this tree runs a full panel, because no panel reviewed the fix.

In both shapes:

- If the user chose Proceed in section 3, list the foreign paths under a line that reads "Not staged, not this slice", and state that the reviewed diff included them. A foreign path that also appears in a step's `changedPaths` stays off the staging list, and the report names it as changed by the run too.
- End with a residual-risk line that names the panel and the hashes: the panel and the two cold dimensions at `diffHashes.redTeam`, every `review.dead` entry, the fix rounds, the cold read at `diffHashes.final` before the doc edits, and the slice marker at `diffHashes.postDoc`, or that no marker was written and why. On an unblocked run, follow the residual-risk line with one line per `coldResidual` finding dismissed in section 8, naming its file and the decision it restates, or `no mapped decision`.

The flow never runs the suggested commands. The user runs git.

## Boundary

The conductor never edits repo files, never mutates git state, and never sets `status: completed`. Repo writes come only from the script's workers, from the implementer that the consent gate delegates, and from the section 8 fix implementer. Not for a plan note that section 1 does not accept (`plan-workflow` owns that) and not for a standalone review of an uncommitted slice (`red-team` owns that). A clean run never marks the plan complete. The human approval rule in `plan-workflow` still governs: the flow runs only on a note that section 1 accepts and on the user's ask, and completion stays the user's word.
