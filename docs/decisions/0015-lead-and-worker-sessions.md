---
title: Lead and worker sessions
summary: The session the user starts is the lead, and on the user's typed yes it starts background worker sessions named worker-<type>-<key> with claude --bg, from the plugin's per-type templates, on the recorded worker session model and effort, with the run options ceiling as the user's permission given in advance, and it records, watches and stops them.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-18
---

# 0015. Lead and worker sessions

Date: 2026-11-18

Status: Accepted

## Context

A child session started from one command the parent handed the user, `claude -n 'child-<planName>'`, which the user pasted into a new terminal. Nothing watched the child, so the parent learned of a finished, stuck or waiting child only from a report message or from the user. Claude Code now offers `claude --bg`, which starts a background session with a first prompt, a name, a worktree, a permission mode, a model and an effort, and `claude agents --json`, which lists every session with its pid, state and `waitingFor`, beside cross-session messages and agent view. A probe found that auto mode treats an approval relayed by another session as untrusted, so a grant must sit in the background session's own first prompt.

## Decision

- Roles. The session the user starts is the lead. Crawl suggests an optional `/rename lead-<name>`, with a name for the whole job, and any session name that does not start `worker-` marks a lead. A worker reports to the lead's name, and when a send fails it reads the lead's current name from `claude agents --json` by the lead's session id and sends again.
- Spawn. The lead proposes a worker session in one plain-text line that names every flow it will run, and starts it only on the user's typed yes, with `scripts/worker-spawn.sh` and `claude --bg`, in the lead's permission mode, which a PreToolUse hook records, and on the lead's own plugin copy through `--plugin-dir` when the lead loaded the plugin by path.
- First prompt. `worker-spawn.sh` fills the first prompt from the plugin's `templates/worker-<type>.md`, and the lead never writes a first prompt by hand.
- Worker session model. The run option keys `session_model` and `session_effort` record the model and effort of the task's worker sessions. The question is always asked of the user, and a worker session never inherits its model or effort from the lead or from the machine default. `worker-spawn.sh` requires both.
- Naming and types. A worker session is named `worker-<type>-<key>`, and the types are `investigate`, `plan`, `execute`, `ship` and `chain`. A `chain` worker session runs a `direct-chain` route note, and only it resumes that chain.
- Ownership. The lead records each worker session in `<scratchpad>/workers`, one line per spawn, and reads only its own record.
- Watch. `scripts/worker-watch.sh` is a background watcher that exits on its first event. It treats a new worker session as pending until it first reads busy or waiting, reports `NOSTART` after its start grace, exits `NONE` once every owned worker session is settled or gone, skips a round on a failed agents read, and exits 3 only after three failed reads in a row. It holds through a usage limit that it reads from a worker session's transcript or the lead's own, and reports one `LIMIT` event per limit line once both reset times have passed plus a 60 second margin.
- Stop. The lead ends a worker session with `claude stop` and never `claude rm`. It stops a worker session on its own once its work is pushed or merged, asks no stop question, and otherwise leaves the worker session idle.
- Questions. A grill question and the ticket create confirmation go from the worker session to the user through AskUserQuestion, and no session relays a grill answer. Every other question goes to the lead by message. Plan approval happens in the lead.
- Grant. The ceiling the user picks in the run options is the user's permission, given in advance. The user's typed yes covers every flow the proposal names up to that ceiling, the worker's first prompt names those flows, and a lead's continue message only continues inside that grant. This answers the reason [0005](0005-approval-offers-the-execute-flow.md) gave for rejecting `claude --bg`, because the user's yes now comes before the spawn, in the lead.
- Refusal. When auto mode refuses a worker's step inside the grant, the lead runs the ship flow itself up to the recorded ceiling and says so in its final summary.
- Git. Every template carries one sentence that leaves each commit, push and pull request to the flows it names.
- Gate. The lead is the gate between phases, and no worker session waits on another. There is no worker cap and no queueing.
- No fallback. Without `claude --bg` the lead offers to run the flow in its own session and hands no command to paste.
- Session entry. A plan note session entry's `name` marks the role: `worker-` marks a worker session and any other name a lead. An older `parent-` name reads as a lead and a `child-` name as a worker session.
- Seat queue. `seat-queue.sh` takes `--lead` and prints `LEAD` with exit 15, and still accepts `--parent`.
- Fresh worktree base. A fresh execute run in a worktree whose branch carries commits that are not on `origin/<default>` stops before any change.
- Kept from [0008](0008-crawl-session-is-the-parent.md): the plan flow offer at the end of crawl's plan-guide route, the `brief - <plan>.md` marker, and the session entry `name` written as a double-quoted scalar.
- Forward only. Sessions already running under `parent-` and `child-` names finish under the plugin version they loaded.

Alternatives weighed and rejected: the pasted child command, tmux, agent teams, a Mission Control launcher, a grant carried by a later message, a fallback where the user types a flow command in a worker session, a stop question for unpushed work, a worker cap with queueing, a worker session that inherits the lead's model or the machine default, a first prompt the lead writes free-hand, a first prompt that runs the ship flow right after the execute flow with no continue, starting the execute worker without `-w` so execute-flow section 2a cuts the planned branch, and refusing `-w` unless the main checkout sits on the default branch.

## Consequences

Each worker session costs one typed yes. An execute worker's branch is `worktree-<planName>`, cut from origin's default branch under Claude Code's default `worktree.baseRef`, rather than the note's planned branch name, and a fresh run whose worktree carries other commits stops. A worker session starts only in a repo the user has trusted in Claude Code. A worker session leaves git to its flows, so Claude Code's finish-time commit, push and draft pull request for a background session does not run. An auto mode refusal inside the grant is a template defect, and the lead's own ship run covers it. On macOS a worker session needs Claude Code's background host granted access to a vault in a protected folder. Each watch event costs a lead turn. A push notification depends on the PushNotification tool. An idle worker session with unpushed work stays until that work is pushed or merged. Worker sessions outlive their lead and then show on another lead's unowned line.
