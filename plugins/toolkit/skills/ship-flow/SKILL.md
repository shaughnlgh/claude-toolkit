---
name: ship-flow
description: >-
  Ship flow: one run that carries a reviewed slice toward production. Use only when the
  user asks for the ship flow by name ("run the ship flow", "ship flow this plan"), after
  an execute-flow report or on an in-progress plan note whose branch exists. Never fires
  from crawl. Reads the run options from the plan note, derives the host, the tree state
  and where to resume, shows every external side effect at one confirmation gate, then launches
  the ship-runner workflow (commit, push, MR or PR, a pipeline watch pinned to the pushed
  commit with a bounded fix loop, bot review threads, merge of that exact commit, tag),
  waits in the background for a slow pipeline or a pending bot review and relaunches
  itself, stopping at the ceiling the note records. Records the result on the plan note and closes with a report. The
  conductor never runs git or a host command beyond its read-only background watcher. Do NOT fire on a plan note whose last session summary
  does not begin execute-flow finished:, ship-flow stopped: or ship-flow finished:, on a
  completed note or one whose PR or MR already merged unless only its tag remains, on
  an uncommitted slice no execute flow reviewed, or for working review threads by hand
  (review-threads owns that).
---

# Ship Flow

Ship-flow is the conductor side of the `ship-runner` workflow, shipped with this plugin at `../../workflows/ship-runner.js` relative to this skill's base directory. The script runs Prep, then Commit, Push, MR, the pipeline watch with its fix loop, the bot review threads, Merge, and Release, each up to the ceiling, and every git and host mutation runs inside its agents under a per-stage rule. The conductor reads the run options, reads the host and the tree through one verifier, plus a capture verifier before a commit, reads the staging list, runs the confirmation gate, launches the script, records the result on the plan note, starts the background watcher and relaunches the script when a run stopped only to wait, and closes with the report. The conductor writes only the vault note and scratchpad files.

## 1. Trigger

Fire only when the user asks for the ship flow by name. A `crawl` route never fires this skill. When the installed plugin does not carry this skill, the conductor reads `plugins/toolkit/skills/ship-flow/SKILL.md` from the toolkit checkout by path and follows it as written.

The plan note must exist. `planName` is its `plan` frontmatter value. `repoRoot` and `repoName` come from the note's `repo` frontmatter as execute-flow section 1 derives them (`../execute-flow/SKILL.md` from this skill's base directory), and `<plugin-root>` resolves the same way. Stop unless all three hold:

- the note is `status: in-progress`, or `status: completed` for the release-only run below.
- its `branch` value is not blank and that branch exists in the repo, which section 3 confirms.
- the summary of its last `sessions` entry begins `execute-flow finished:`, `ship-flow stopped:`, or `ship-flow finished:`.

`execute-flow finished:` marks a slice that has not shipped yet. `ship-flow stopped:` marks a run that ended below its ceiling or in a handoff. `ship-flow finished:` marks a run that reached its ceiling, which a `ceiling: mr` note sets at mr, so after the user raises the note's ceiling to `merge` a later run ships the same note on to merge. A `status: completed` note goes on only for the release-only run: its PR or MR is merged, its merge commit carries no tag, and the note carries `ceiling: merge` and `tag_merge: true`, which section 3 checks. Section 3 refuses any note whose PR or MR is merged unless the run only tags the merge commit. Any other summary means the slice is not ready to ship. A summary that begins `execute-flow blocked:` or `execute-flow adjudicating:`, or reads `execute-flow run started`, belongs to the execute flow, so stop and tell the user to finish it there. Any other status or summary: state it and stop. Where a run resumes is derived from observed state in section 3, never typed by the user.

## 2. Run options

Before anything else, read the run options per `plan-guide` § Run options (`../plan-guide/SKILL.md` from this skill's base directory): from the plan note, which an execute-flow run has already written, then from `<scratchpad>/flow-run-options` for the keys the note lacks when that file's `plan:` line names this plan, then ask only the questions for the keys still missing, and write the cache for this plan. Section 8 records every key the note lacked. The ship flow is the only flow that mutates git, and it does so only under `mr` or `merge`, through the runner's agents. Under `none` it runs Prep only and hands over the commit block. The `## Flows` section of the git-safety doctrine (`../../doctrine/git-safety.md` from this skill's base directory) defines what each ceiling permits.

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
5. Else the PR or MR is merged. `mergedSha` is its merge commit: `mergeCommit.oid` from `gh pr view` on GitHub, and on GitLab `merge_commit_sha`, else `squash_commit_sha`, else `sha`. When the note carries `ceiling: merge` and `tag_merge: true` and no `git ls-remote --tags origin` line carries `mergedSha`, `startAt` is `release`. Otherwise stop and say that the slice is already merged, with the merge commit.

A `status: completed` note goes on only when rule 5 sets `startAt` to `release`. Any other rule stops it, and the conductor states the status.

For `merge` and `release`, keep the PR or MR `url` and `number` (the iid on GitLab) as `mr`.

`recordedSha` is the commit sha the plan note records under Plan Changes During Execution from an earlier ship-flow run, or an empty string.

The latest remote `vX.Y.Z` tag from `git ls-remote --tags origin` feeds the release suggestion: `tagName` is that tag with its patch number raised by one, or `v0.1.0` when no such tag exists, and `tagMessage` is the first line of the commit message. When the grep finds a tag trigger, keep the file and line for the gate with the sentence "A tag push starts the job at <file>:<line>."

## 4. Staging list and message

Take the staging list and the commit message from the execute-flow report in this session when one exists. Otherwise read the staging list and the commit message from the shipping record on the plan note, which execute-flow section 7 records on every unblocked run whose capture succeeds and an execute-flow section 8 fix replaces. If neither source has them, stop and say that the slice needs an execute-flow run first.

When `startAt` is `commit` and the note records a shipping record, spawn one `toolkit:verifier` briefed with the `CAPTURE_PROMPT` text from `execute-runner.js` (beside `ship-runner.js`), with `<repoRoot>` for `${a.repoRoot}` and the scratchpad path for `${S}`, and compare its `hash12` with the shipping record hash. If they differ, stop and say that the tree changed since review and that the slice needs an execute-flow run. After a commit the tree holds no slice diff, so no later `startAt` runs the capture.

`paths` is the staging list. `mrTitle` is the first line of the message. `mrBody` is the rest of the message after its first blank line, followed by a line `Plan: <planName>`.

## 5. Ceiling

The ladder is suggest, commit, push, mr, merge, release. The note's `ceiling` sets where the run stops: `none` stops at suggest, `mr` at mr, `merge` at merge, and `merge` with `tag_merge: true` at release. Say "The ceiling is <ceiling>, so the run stops at <stage>." No question is asked here. The user changes the ceiling by editing the note.

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
- the tag name and message when the stage is release, and every CI tag trigger sentence from section 3.
- when `startAt` is `merge` and Plan Changes During Execution records fix shas from earlier ship-flow runs, the heading `Fix commits to read before Go` with each of those shas on its own line, because the run merges over every fix sha the note records.

Then ask once through AskUserQuestion: "Ship <planName> from <branch> to <remotePath> on <host>, stopping at <stage>. Everything the run may send out is shown above. Go, edit, or stop?" with the options in this order:

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
- `ceiling`: the note's value from section 2. `tag`: the note's `tag_merge` value from section 2 as a boolean, `false` when the key is absent.
- `botAuthors`, `maxFixRounds`: from section 6.
- `tagName`, `tagMessage`: from section 3, only when `ceiling` is `merge` and `tag` is true.
- `knownShas`: the shipping record's commit sha (`recordedSha`) plus every fix sha that Plan Changes During Execution records from an earlier ship-flow run, or an empty list.
- `protectedPaths`: the repo-specific paths that a bot-thread fix must never touch, empty unless the plan note names them.
- `scratchDir`: the absolute scratchpad path. `pluginRoot`: `<plugin-root>`.

When `repoRoot` contains `plugins/toolkit/workflows/ship-runner.js`, launch `{scriptPath: "<repoRoot>/plugins/toolkit/workflows/ship-runner.js"}`, otherwise `{name: "toolkit:ship-runner"}`. If name resolution fails, launch `{scriptPath: "<this skill's base directory>/../../workflows/ship-runner.js"}` resolved to an absolute path. The script is named `ship-runner` because a workflow and a skill cannot share a name in the plugin registry. If the Workflow tool refuses a `scriptPath` as outside the working directory, copy the script byte-identical to `<scratchpad>/ship-runner.js`, take the first 12 characters of `shasum -a 256` for the source and for the copy, require the two to match, and launch `{scriptPath: "<scratchpad>/ship-runner.js"}`. A run that dies is not resumed: every stage is idempotent, so asking for the ship flow again derives `startAt` from the tree and the host. The section 7b relaunch is that same mechanism, driven by the watcher's exit instead of the user's ask.

The result is `{stoppedAt, stopStage, commitSha, headSha, pushed, mr, pipeline, threads, fixShas, merged, tag, handoff, blocked, incomplete}`:

- `pipeline` is `{state, sha, rounds, failingLines}` or null, where `state` is `green`, `red`, `pending`, or `none` and `sha` is the commit the state belongs to.
- `threads` is `{fixed, pushedBackNeeded, human, open}` or null.
- `fixShas` lists every fix commit this run pushed. `merged` is `{sha, kind}` or null, where `kind` is `merge`, `squash`, `fast-forward`, or `unknown`.
- `handoff` is `{stage, command}` when the permission system denied a command, else null.
- `blocked` lists one sentence per reason the run stopped, and `incomplete` lists the labels of the stages that died.

## 7b. Wait

The runner ends its run at its nine-minute watch bound, because a blocking call inside an agent is capped at ten minutes, so the conductor owns any longer wait. Wait only when the result has `handoff` null, `incomplete` empty, and `blocked` holding exactly one sentence, which is either the pending sentence `The pipeline for <sha> was still pending at the watch bound.` or the no-review sentence `No review from <bots> has landed on <url> for <sha> at the watch bound.` Every other result goes to sections 8 and 9.

Run section 8 for the returned result before starting the watcher, so the plan note is right if the session ends during the wait.

Start the watcher with the Bash tool and `run_in_background: true`. For the pending sentence, run `bash <plugin-root>/scripts/watch-mr.sh <host> <remotePath> <number> pipeline --sha <sha> --bound 180`. For the no-review sentence, run `bash <plugin-root>/scripts/watch-mr.sh <host> <remotePath> <number> threads --sha <sha> --bound 180` with one `--bot "<login>"` per `botAuthors` entry. `<number>` is `mr.number` and `<sha>` is the sha in the sentence. The watcher runs from the repo's working directory, which a ship-flow session already uses, and `glab` reads the GitLab host from the git remote there. Say in one chat line what the watcher waits for and that the run resumes on its own when the watcher exits, then end the turn. The harness wakes the conductor when the command exits. Never poll, never spawn an agent to wait, and never run the watcher in the foreground. Run one watcher at a time.

On the completion notification, read the exit code and the status line that `watch-mr.sh` prints:

- `GREEN` or `LANDED` (exit 0), or `RED` (exit 10): spawn the section 3 verifier again and derive `startAt` again. If `startAt` is `merge` and the branch, the MR url and number, and the gate's ceiling are unchanged, rebuild the args per section 7 with the same `paths`, `botAuthors`, and `protectedPaths`, with `ceiling` and `maxFixRounds` set by the two relaunch rules below, and with `knownShas` updated from the note. Then relaunch per section 7 without the section 6 gate, because the Go answer covered this run to the same ceiling and nothing the preview showed has changed. Any other `startAt` means the tree or the host changed during the wait, so report per section 9 and stop.
- `STUCK` (exit 11): report per section 9 with the line `The pipeline for <sha> is stuck: every job finished but the pipeline has not settled for <minutes> minutes.` and stop, because unsticking an external job is the user's call.
- `BOUND` (exit 12), `NONE` (exit 13), `MOVED` (exit 14), or exit 2 or 3: report the status line, or the stderr text for exit 2 or 3, per section 9 and stop.

If the run that stopped to wait, or any earlier run of this ship-flow ask, returned a non-empty `fixShas`, the relaunch passes `ceiling` as `mr`, because section 7 builds `knownShas` from the fix shas that section 8 records and the runner refuses a merge only for fix commits its own launch pushed. That relaunch watches the pipeline and works the bot threads but never merges, and section 9 hands the merge to the user.

The relaunch passes `maxFixRounds` as the gate's value minus the sum of `pipeline.rounds` across this ask's runs, never below zero, so all relaunches together push no more pipeline fix commits than the gate approved.

Start at most three watchers per ship-flow ask. When the third relaunch returns a result that would need a fourth watcher, report per section 9 and stop.

## 8. Record

Load `plan-guide`. When section 2 filled keys from the cache or asked for them, write those run option keys into the frontmatter in this write. Set the `mr` frontmatter from `mr.url` when it is not null. Under Plan Changes During Execution, record one line each for the commit sha, each `fixShas` entry with its reason, so a later run's `knownShas` holds every fix sha, the merge sha, the tag, the `threads` lists, and every `blocked` sentence and `incomplete` label.

Record this session's entry per the plan-guide session rules, which reuse the entry when execute-flow ran in this session. A section 7b relaunch reuses the entry the first launch in this session wrote. The summary begins `ship-flow stopped: at <stoppedAt>` when `blocked` or `incomplete` is not empty, when `handoff` is not null, or when `stoppedAt` is below the ceiling. It begins `ship-flow finished: <ceiling>` only on a clean run that reached the ceiling. In this section the ceiling is the stage section 5 mapped the note's run options to (`suggest`, `mr`, `merge`, or `release`), never the note's `ceiling` value, so a `ceiling: merge` and `tag_merge: true` run that stops at `merge` records `ship-flow stopped: at merge`. The summary compares `stoppedAt` with the ceiling the section 6 gate approved, not the `stopStage` a section 7b relaunch returns, so a relaunch that section 7b capped at `mr` records `ship-flow stopped: at mr`. A `ship-flow finished:` summary keeps `status: in-progress` unless the merge rule below sets `status: completed`, so section 1 accepts the note again for a later run after the user raises the note's ceiling. When `merged.sha` is set, a `Remember:` line under Plan Changes During Execution still sets `status: completed`, and section 1 accepts that note again for the release-only run. Without that line, keep `status: in-progress` and tell the user that the remember pass has not run. A release-only run on a `status: completed` note leaves the status as it is.

Write the change atomically: Write the note to a `.tmp.md` file beside it, then move it into place with `vault-fs.sh mv`. Then run `python3 <plugin-root>/scripts/validate-plan.py "<plan note path>"` and require exit 0. If the validator fails, report its output and stop. Never patch a failure silently.

## 9. Report

Open with the Repo, Branch, and Scope header lines from the git-safety Commit handoff section. Then report:

- each stage that ran with its output: the commit sha, the push, the PR or MR url, the pipeline state and its sha, the threads, the merge sha, and the tag.
- when `pipeline.state` is `none`, that no pipeline was found for the pushed commit, and that asking for the ship flow again after the host registers the pipeline rewatches it.
- `stoppedAt` and why: the ceiling or the first `blocked` sentence.
- when `handoff` is not null, the handoff block from the git-safety Commit handoff section, with `cd "<repoRoot>"` on its own line and `handoff.command` on the next.
- when any run of this ship-flow ask returned a non-empty `fixShas` and `merged` is null, each of those fix shas, that the user must read them before asking for the ship flow again, and the merge command (`gh pr merge <number> --merge --match-head-commit <headSha>` on GitHub, `glab mr merge <number> --sha <headSha> --auto-merge=false --yes` on GitLab), and that asking for the ship flow again after reading the fixes merges them.
- when a `blocked` sentence refuses the merge for commits no run recorded, each of those commits, and that the user must read them and then ask for the ship flow again.
- each `pushedBackNeeded` thread with the review-threads push-back recipe (`../review-threads/SKILL.md` section 3), and each `human` thread for the user to settle.
- after a merge, the undo command for `merged.kind`: `git revert -m 1 <mergeSha>` for `merge`, `git revert <mergeSha>` for `squash`, and `git revert <base>..<mergeSha>` for `fast-forward`, where `<base>` is the default branch tip before the merge, the parent of the first commit in the range, because a fast-forward may carry several commits. For `unknown`, tell the user to check the parent count with `git cat-file -p <mergeSha>` before choosing between the two.
- after a tag, the undo command `git push origin :refs/tags/<tag>`.
- when the watcher exits `STUCK`, the stuck line from section 7b, and that the user settles the external job and then asks for the ship flow again.
- when a wait ends without a relaunch, the watcher's status line or stderr text and the user's next step: after `BOUND` or `NONE`, ask for the ship flow again once the host shows a result for the commit. After `MOVED`, read the new head commit and then ask again. After exit 2 or 3, fix the cause the stderr text names and then ask again. After a changed `startAt`, ask again to resume from it.
- when any section 7b relaunch ran, how many ran.

At ceiling `suggest`, the report is the git-safety commit handoff: the three header lines, then a line that begins `Suggested commit`, then the paste-ready block with each path in `paths` named. Never suggest `git add -A`.

## Boundary

The conductor never runs git or a host command beyond the read-only `watch-mr.sh` watcher in section 7b. Every mutation runs in the runner's agents, no stage runs above the ceiling, and no merge happens over a fix commit this run pushed. The conductor never fixes, replies to, or resolves a human reviewer's thread. Not for a slice no execute flow reviewed (`execute-flow` owns that) and not for working review threads outside a ship run (`review-threads` owns that).
