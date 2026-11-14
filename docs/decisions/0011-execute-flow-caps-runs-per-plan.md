---
title: Execute flow caps runs per plan
summary: A plan gets three fresh execute runs, three journal resumes and three fix rounds, a finding the fix cap stops goes to the PR for one tested fix commit in the ship run, every run records its baseline, and a blocked run resumes from its journal only over a tree unchanged since it blocked.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-10
---

# 0011. Execute flow caps runs per plan

Date: 2026-11-10

Status: Accepted

## Context

The execute flow reran a blocked plan with no limit, and each fresh run ran every implementer, validation and panel again. The runner bounded fix rounds per run, never per plan. A blocked run had no path but a full rerun: a completed blocked run replayed whole returns the same blocked list, and a `resumeFromRunId` resume replays the cached `plan:index` with its old sha256, so a note write between runs stops every resumed worker on the plan note sha check.

## Decision

- A plan gets three fresh runs, counted from the `Launch:` lines whose script is not the replay copy, three journal resumes, counted from the `Resume from journal:` lines, and three fix rounds, summed from the `Fix rounds used:` lines. Each `Execute cap raised: <reason>` line, which only the user or the parent records, raises each cap by one. A dead-run continuation counts toward no cap, because its run recorded no outcome.
- The runner takes `fixBudget`, the fix rounds the plan has left, spends one per live fix round, and returns the count as `fixRounds`. A replayed round costs nothing.
- A seat run counts toward no run cap, because its reruns wait on the seat queue, the switch and the restore, not on code. It spends from the same fix round cap.
- Cap split. Once no fix round is left, section 8 records a finding whose bucket or final tag is `nit`, or whose final score is below 0.6, as `Finding did not matter:` with `(fix cap reached)`, and every other finding as `Finding for the PR:`, a settled outcome.
- The ship run fixes every `Finding for the PR:` finding in one commit after the PR or MR opens. A verifier rechecks each finding at the pushed head and runs the execute run's verify command, read from its `Baseline:` line. The commit may add or change test files under the directories that suite runs, so the fix carries its own regression test. A repo with no CI configuration and no recorded verify command does not merge a carried fix unattended. Every execute run therefore records its `Baseline:` line.
- A blocked run resumes through the continuation copy that `run-checkpoint.py --from <label> --tree-hash <hash12>` writes, cut at the stage where it blocked, and never through `resumeFromRunId`. The copy runs `plan:index` live, so a settle line written between runs never stops a resumed worker. The runner returns that stage as `blockedAt`, and a blocked run outside a seat run captures its tree once more as `blockedTree`. The resume needs a live capture with that hash.
- A `resumeFromRunId` resume in the launching session reads the note's sha256 first, and continues through the replay copy when the note changed after the launch.

## Consequences

The counts come from note lines a person can edit, so the caps hold only while the note keeps its own record. The split reads the tag and the score as a proxy for polish against a real bug: a wording finding tagged important at 0.6 or above rides the carried fix, and a real bug tagged nit is recorded as did not matter. The report lists both kinds, and an `Execute cap raised:` line gives one more round. At the fix cap a failing Validation Step blocks the run, because the PR cannot carry it, and after a worktree run spent every round, a deferred step that fails in the seat run blocks with no fix. A settle that changes any file under a root starts a fresh run, because a replayed validation or review result would report checks that never ran on the changed tree. A run whose blocked-tree capture died records `No blocked tree:` and needs a fresh run. A journal resume keeps the recorded args apart from `scratchDir` and `fixBudget`, so a settle that needs another arg, such as `verifyCommand`, needs a fresh run. A cut at `review` reruns only the child agents that recorded no result, so a verifier result that the settle made stale replays unless the resume line names its label with `from review:<label>`. The carried verify command comes from the `Baseline:` line text, which the ship flow cuts before its last ` exit `, so a failing check name that holds ` exit ` splits the line at the wrong place, and the recheck then fails and blocks the merge. On a several-repos note the ship flow also splits the command into parts at ` ; `, so a command that holds ` ; ` also gives a wrong verify command.
