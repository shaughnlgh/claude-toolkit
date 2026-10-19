---
name: ship-flow
description: >-
  Ship flow: one run that carries a reviewed slice toward production. Use only when the
  user asks for the ship flow by name ("run the ship flow", "ship flow this plan"), after
  an execute-flow report or on an in-progress plan note whose branch exists. Never fires
  from crawl. Asks the git-permission question unless an earlier flow in the session
  recorded the answer, derives the host, the tree state and where to resume, asks once
  where to stop, shows every external side effect at one confirmation gate, then launches
  the ship-runner workflow (commit, push, MR or PR, a pipeline watch pinned to the pushed
  commit with a bounded fix loop, bot review threads, merge of that exact commit, tag),
  stopping at the ceiling, the lower of the chosen stage and the cap the session
  permission allows. Records the result on the plan note and closes with a report. The
  conductor never runs git or a host command. Do NOT fire on a plan note whose last session summary
  does not begin execute-flow finished:, ship-flow stopped: or ship-flow finished:, on a
  completed note or one whose PR or MR already merged unless only its tag remains, on
  an uncommitted slice no execute flow reviewed, or for working review threads by hand
  (review-threads owns that).
---

# Ship Flow

Ship-flow is the conductor side of the `ship-runner` workflow, shipped with this plugin at `../../workflows/ship-runner.js` relative to this skill's base directory. The script runs Prep, then Commit, Push, MR, the pipeline watch with its fix loop, the bot review threads, Merge, and Release, each up to the ceiling, and every git and host mutation runs inside its agents under a per-stage rule. The conductor asks the git-permission question, reads the host and the tree through one verifier, plus a capture verifier before a commit, reads the staging list, asks where to stop, runs the confirmation gate, launches the script, records the result on the plan note, and closes with the report. The conductor writes only the vault note and scratchpad files.

## 1. Trigger

Fire only when the user asks for the ship flow by name. A `crawl` route never fires this skill. When the installed plugin does not carry this skill, the conductor reads `plugins/toolkit/skills/ship-flow/SKILL.md` from the toolkit checkout by path and follows it as written.

The plan note must exist. `planName` is its `plan` frontmatter value. `repoRoot` and `repoName` come from the note's `repo` frontmatter as execute-flow section 1 derives them (`../execute-flow/SKILL.md` from this skill's base directory), and `<plugin-root>` resolves the same way. Stop unless all three hold:

- the note is `status: in-progress`, or `status: completed` for the release-only run below.
- its `branch` value is not blank and that branch exists in the repo, which section 3 confirms.
- the summary of its last `sessions` entry begins `execute-flow finished:`, `ship-flow stopped:`, or `ship-flow finished:`.

`execute-flow finished:` marks a slice that has not shipped yet. `ship-flow stopped:` marks a run that ended below its ceiling or in a handoff. `ship-flow finished:` marks a run that reached its ceiling, which the permission can cap below the merge (for example `mr` under `push`), so a later session with `release` permission ships the same note on to merge. A `status: completed` note goes on only for the release-only run: its PR or MR is merged, its merge commit carries no tag, and the session permission is `release`, which section 3 checks. Section 3 refuses any note whose PR or MR is merged unless the run only tags the merge commit. Any other summary means the slice is not ready to ship. A summary that begins `execute-flow blocked:` or `execute-flow adjudicating:`, or reads `execute-flow run started`, belongs to the execute flow, so stop and tell the user to finish it there. Any other status or summary: state it and stop. Where a run resumes is derived from observed state in section 3, never typed by the user.

## 2. Git permission

Before anything else, check `<scratchpad>/flow-git-permission`. If the file exists, an earlier flow in this session recorded the answer, so read it and do not ask. If the file does not exist, this flow is the first in the session, so ask once through AskUserQuestion: "Do I have permission to run git commands on your behalf for every flow in this session?" with the options in this order:

1. "No, suggest only (Recommended for a work repo)", with the description "Every flow in this session suggests git commands and runs none.", writes `none`.
2. "Yes, commit, branch, push and open the MR or PR, never merge", with the description "Covers every flow in this session, including a later flow in this session that runs git, without asking again.", writes `push`.
3. "Yes, through merge and tag", with the description "Covers every flow in this session, including a later flow in this session that runs git, without asking again.", writes `release`.

Write the answer to `<scratchpad>/flow-git-permission` as `none`, `push`, or `release`. A missing, empty, or unrecognised file reads as `none`, so until the question is answered no flow has git permission. The answer holds for every flow run in this session, so a later flow in the same session reads the file and never re-asks. The ship flow is the only flow that mutates git, and it does so only under `push` or `release`, through the runner's agents. Under `none` it runs Prep only and hands over the commit block, and the `## Flows` section of the git-safety doctrine (`../../doctrine/git-safety.md` from this skill's base directory) defines what each answer unlocks.

## 3. Host, tree and observed state

Spawn one `toolkit:verifier` that runs these commands in `<repoRoot>` and nothing else: `git remote get-url origin`, `git symbolic-ref --short refs/remotes/origin/HEAD`, `git branch --show-current`, `git rev-parse HEAD`, `git ls-remote origin refs/heads/<branch>`, `git ls-remote --tags origin`, and `git -c core.quotePath=false status --porcelain -uall`. On GitHub it also runs `gh pr view <branch> --json number,url,state,mergeCommit`, and on GitLab `glab mr list --source-branch <branch> --all -F json`. It greps `.github/workflows/*.yml` and `.gitlab-ci.yml` for `tags` and `CI_COMMIT_TAG`, tolerating a missing file. It returns each output verbatim, with the error text for a command that fails. A PR or MR lookup that finds nothing is not a failure. `<branch>` is the plan note's `branch` value.

Read the outputs:

- Host is `github` for a `github.com` remote URL, else `gitlab`.
- Before building `remotePath` or the `Repo:` header line, strip any user or token segment from the remote URL: in a URL with a scheme, the text between `://` and an `@`, with that `@`. In an ssh form such as `git@host:owner/repo.git`, the text before the `@`, with that `@`. Never print the raw remote URL.
- The `Repo:` header line is the stripped URL with the scheme and `.git` removed, and the scp `:` turned into `/`. `remotePath` is that line without its leading host segment, such as `owner/repo` or `group/sub/repo`, because the runner builds the API paths from it.
- The default branch is the symbolic-ref output after `origin/`. If the command fails, ask the user for it.
- If the current branch differs from the note's `branch`, HEAD is detached, or the branch is `main`, `master`, or the default branch, stop and hand the user the switch command: `! cd <repoRoot> && git switch <branch>`.

Derive `startAt` once section 4 has the staging list, for every summary prefix section 1 accepts. The rules are exclusive and ordered, and the first match wins:

1. When a staging-list path is dirty in the status output, `startAt` is `commit`.
2. Else, when the `ls-remote` sha for `origin/<branch>` differs from HEAD or is absent, `startAt` is `push`. When the remote branch is gone (`ls-remote` prints nothing for it) and a merged PR or MR exists, rule 5 applies before this rule, so a merged slice whose branch the host deleted does not start at push.
3. Else, when no PR or MR for the branch is open or merged, `startAt` is `mr`.
4. Else, when a PR or MR for the branch is open, `startAt` is `merge`.
5. Else the PR or MR is merged. `mergedSha` is its merge commit: `mergeCommit.oid` from `gh pr view` on GitHub, and on GitLab `merge_commit_sha`, else `squash_commit_sha`, else `sha`. When the session permission is `release` and no `git ls-remote --tags origin` line carries `mergedSha`, `startAt` is `release`, and the run goes on only when section 5 records `stopAt` as `release`. Otherwise, or when section 5 records a lower `stopAt`, stop and say that the slice is already merged, with the merge commit.

A `status: completed` note goes on only when rule 5 sets `startAt` to `release`. Any other rule stops it, and the conductor states the status.

For `merge` and `release`, keep the PR or MR `url` and `number` (the iid on GitLab) as `mr`.

`recordedSha` is the commit sha the plan note records under Plan Changes During Execution from an earlier ship-flow run, or an empty string.

The latest remote `vX.Y.Z` tag from `git ls-remote --tags origin` feeds the release suggestion: `tagName` is that tag with its patch number raised by one, or `v0.1.0` when no such tag exists, and `tagMessage` is the first line of the commit message. When the grep finds a tag trigger, keep the file and line for the gate with the sentence "A tag push starts the job at <file>:<line>."

## 4. Staging list and message

Take the staging list and the commit message from the execute-flow report in this session when one exists. Otherwise read the staging list and the commit message from the shipping record on the plan note, which execute-flow section 7 records on every unblocked run whose capture succeeds and an execute-flow section 8 fix replaces. If neither source has them, stop and say that the slice needs an execute-flow run first.

When `startAt` is `commit` and the note records a shipping record, spawn one `toolkit:verifier` briefed with the `CAPTURE_PROMPT` text from `execute-runner.js` (beside `ship-runner.js`), with `<repoRoot>` for `${a.repoRoot}` and the scratchpad path for `${S}`, and compare its `hash12` with the shipping record hash. If they differ, stop and say that the tree changed since review and that the slice needs an execute-flow run. After a commit the tree holds no slice diff, so no later `startAt` runs the capture.

`paths` is the staging list. `mrTitle` is the first line of the message. `mrBody` is the rest of the message after its first blank line, followed by a line `Plan: <planName>`.

## 5. Ceiling and stopAt

The ladder is suggest, commit, push, mr, merge, release. The session permission sets the cap: `none` caps at suggest, `push` caps at mr, and `release` caps at release. Say "The session permission is <permission>, so the cap is <cap>."

Under `none`, every option resolves to suggest, so skip the question below and set `stopAt` to `suggest`. Under `push` or `release`, ask once through AskUserQuestion: "Where does the ship flow stop?" Under `push`, the four options in this order are "Suggest only", "Commit", "Push", "MR or PR". Under `release` they are "Push", "MR or PR", "Merge", "Release". The label of the option equal to the cap ends with " (Cap under <permission>)". The descriptions:

- Suggest only: "Runs nothing. Hands you the commit block."
- Commit: "Stages the listed paths and commits on <branch>."
- Push: "Commit, then git push -u origin <branch>."
- MR or PR: "Commit, push, open the merge request or pull request, watch the pipeline, and fix bot threads."
- Merge: "Through MR, then merge only when green on the pushed commit, no open thread, and no fix commit this run. The merge is refused on a CHANGES_REQUESTED review or a GitLab status that is not mergeable."
- Release: "Through merge, then tag the merge commit <tagName> and push the tag."

A free-text answer that names another stage counts. `stopAt` is `suggest`, `commit`, `push`, `mr`, `merge`, or `release` for the answer. The ceiling is the lower of `stopAt` and the cap, and an answer above the cap runs no higher than the cap.

## 6. Confirmation gate

Print the preview in chat:

- the commit message, the MR title, and the MR body.
- each path in `paths` on its own line.
- the ceiling and `startAt`.
- the `botAuthors` list, empty unless the user names bot logins. GitHub app authors and GitLab bot users count as bots without the list.
- when the ceiling is `mr` or higher, the fix templates:
  - the pipeline fix message template `fix(ci): <failing check> (ship-flow)`, bounded at `maxFixRounds` commits, default 1.
  - the review fix message template `fix(review): <thread summary> (ship-flow)`, bounded at one commit per fixable bot thread.
  - the reply template `Fixed in <short sha>: <what changed>`, one reply and one resolve per fixed bot thread.
- that no commit carries a Co-Authored-By trailer and that human threads are never touched.
- the tag name and message when the ceiling is release, and every CI tag trigger sentence from section 3.

Then ask once through AskUserQuestion: "Ship <planName> from <branch> to <remotePath> on <host>, ceiling <ceiling>. Everything the run may send out is shown above. Go, edit, or stop?" with the options in this order:

1. "Go", with the description "Runs every stage up to the ceiling. A merge still stops if the run pushed a fix."
2. "Edit", with the description "Tell me what to change. The preview and this question come back."
3. "Stop", with the description "Nothing runs. The plan note stays in-progress."

When the ceiling is `mr` or higher, the question carries the sentence "That includes up to <maxFixRounds> pipeline fix commits and one fix, reply and resolve per fixable bot thread." before "Go, edit, or stop?". Under `none`, the preview holds only the commit message, the MR title and body, each path in `paths`, the ceiling, and `startAt`. The gate still runs before the handoff.

This gate is the execution-guardrails preview for the whole run. On Edit, apply the change, print the preview again, and ask again. On Stop, end with the plan note untouched.

## 7. Launch

Build the args:

- `planName`, `repoRoot`, `repoName`: from section 1.
- `host`, `remotePath`, `defaultBranch`, `branch`, `startAt`, `recordedSha`, `mr`, `mergedSha`: from section 3. Pass `mr` only when `startAt` is `merge` or `release`, and `mergedSha` only when `startAt` is `release`.
- `commitMessage`, `mrTitle`, `mrBody`, `paths`: from section 4.
- `stopAt`: from section 5. `permission`: from section 2.
- `botAuthors`, `maxFixRounds`: from section 6.
- `tagName`, `tagMessage`: from section 3, only when `stopAt` is `release`.
- `knownShas`: the shipping record's commit sha (`recordedSha`) plus every fix sha that Plan Changes During Execution records from an earlier ship-flow run, or an empty list.
- `protectedPaths`: the repo-specific paths that a bot-thread fix must never touch, empty unless the plan note names them.
- `scratchDir`: the absolute scratchpad path. `pluginRoot`: `<plugin-root>`.

When `repoRoot` contains `plugins/toolkit/workflows/ship-runner.js`, launch `{scriptPath: "<repoRoot>/plugins/toolkit/workflows/ship-runner.js"}`, otherwise `{name: "toolkit:ship-runner"}`. If name resolution fails, launch `{scriptPath: "<this skill's base directory>/../../workflows/ship-runner.js"}` resolved to an absolute path. The script is named `ship-runner` because a workflow and a skill cannot share a name in the plugin registry. If the Workflow tool refuses a `scriptPath` as outside the working directory, copy the script byte-identical to `<scratchpad>/ship-runner.js`, take the first 12 characters of `shasum -a 256` for the source and for the copy, require the two to match, and launch `{scriptPath: "<scratchpad>/ship-runner.js"}`. A run that dies is not resumed: every stage is idempotent, so asking for the ship flow again derives `startAt` from the tree and the host.

The result is `{stoppedAt, ceiling, commitSha, headSha, pushed, mr, pipeline, threads, fixShas, merged, tag, handoff, blocked, incomplete}`:

- `pipeline` is `{state, sha, rounds, failingLines}` or null, where `state` is `green`, `red`, `pending`, or `none` and `sha` is the commit the state belongs to.
- `threads` is `{fixed, pushedBackNeeded, human, open}` or null.
- `fixShas` lists every fix commit this run pushed. `merged` is `{sha, kind}` or null, where `kind` is `merge`, `squash`, `fast-forward`, or `unknown`.
- `handoff` is `{stage, command}` when the permission system denied a command, else null.
- `blocked` lists one sentence per reason the run stopped, and `incomplete` lists the labels of the stages that died.

## 8. Record

Load `plan-workflow`. Set the `mr` frontmatter from `mr.url` when it is not null. Under Plan Changes During Execution, record one line each for the commit sha, each `fixShas` entry with its reason, so a later run's `knownShas` holds every fix sha, the merge sha, the tag, the `threads` lists, and every `blocked` sentence and `incomplete` label.

Record this session's entry per the plan-workflow session rules, which reuse the entry when execute-flow ran in this session. The summary begins `ship-flow stopped: at <stoppedAt>` when `blocked` or `incomplete` is not empty, when `handoff` is not null, or when `stoppedAt` is below the ceiling. It begins `ship-flow finished: <ceiling>` only on a clean run that reached the ceiling. A `ship-flow finished:` summary keeps `status: in-progress` unless the merge rule below sets `status: completed`, so section 1 accepts the note again for a run above a capped ceiling. When `merged.sha` is set, a `Remember:` line under Plan Changes During Execution still sets `status: completed`, and section 1 accepts that note again for the release-only run. Without that line, keep `status: in-progress` and tell the user that the remember pass has not run. A release-only run on a `status: completed` note leaves the status as it is.

Write the change atomically: Write the note to a `.tmp.md` file beside it, then move it into place with `vault-fs.sh mv`. Then run `python3 <plugin-root>/scripts/validate-plan.py "<plan note path>"` and require exit 0. If the validator fails, report its output and stop. Never patch a failure silently.

## 9. Report

Open with the Repo, Branch, and Scope header lines from the git-safety Commit handoff section. Then report:

- each stage that ran with its output: the commit sha, the push, the PR or MR url, the pipeline state and its sha, the threads, the merge sha, and the tag.
- when `pipeline.state` is `none`, that no pipeline was found for the pushed commit, and that asking for the ship flow again after the host registers the pipeline rewatches it.
- `stoppedAt` and why: the ceiling, the chosen stop, or the first `blocked` sentence.
- when `handoff` is not null, the handoff block from the git-safety Commit handoff section, with `cd "<repoRoot>"` on its own line and `handoff.command` on the next.
- when `fixShas` refused the merge, each fix sha and the merge command from the refusal sentence (`gh pr merge <number> --merge --match-head-commit <headSha>` on GitHub, `glab mr merge <number> --sha <headSha> --auto-merge=false --yes` on GitLab), and that asking for the ship flow again after reading the fixes merges them.
- when a `blocked` sentence refuses the merge for commits no run recorded, each of those commits, and that the user must read them and then ask for the ship flow again.
- each `pushedBackNeeded` thread with the review-threads push-back recipe (`../review-threads/SKILL.md` section 3), and each `human` thread for the user to settle.
- when the permission capped the ceiling below `stopAt`, the next command for the user to run.
- after a merge, the undo command for `merged.kind`: `git revert -m 1 <mergeSha>` for `merge`, `git revert <mergeSha>` for `squash`, and `git revert <base>..<mergeSha>` for `fast-forward`, where `<base>` is the default branch tip before the merge, the parent of the first commit in the range, because a fast-forward may carry several commits. For `unknown`, tell the user to check the parent count with `git cat-file -p <mergeSha>` before choosing between the two.
- after a tag, the undo command `git push origin :refs/tags/<tag>`.

At ceiling `suggest`, the report is the git-safety commit handoff: the three header lines, then a line that begins `Suggested commit`, then the paste-ready block with each path in `paths` named. Never suggest `git add -A`.

## Boundary

The conductor never runs git or a host command. Every mutation runs in the runner's agents, no stage runs above the ceiling, and no merge happens over a fix commit this run pushed. The conductor never fixes, replies to, or resolves a human reviewer's thread. Not for a slice no execute flow reviewed (`execute-flow` owns that) and not for working review threads outside a ship run (`review-threads` owns that).
