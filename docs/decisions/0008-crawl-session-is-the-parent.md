---
title: Crawl session is the parent
summary: The crawl session is the parent of the work it routes, so its plan-guide route ends with a plan flow offer, every session records its own name on its plan note entry, and after approval a session named parent- recommends a child session named child-<planName> and puts a bare yes on that line.
type: decision
status: deprecated
superseded_by: 0015-lead-and-worker-sessions
owner: Shaughn
last_reviewed: 2026-11-09
---

# 0008. Crawl session is the parent

Date: 2026-11-09

Status: Superseded

Superseded by [0015](0015-lead-and-worker-sessions.md).

## Context

The crawl is the front door for most new work. A crawl session's name starts `parent-` only when a launcher starts it with a `parent-` name, such as Mission Control's New work and Pick launches with `claude -n 'parent-<slug>'`, or when the user runs crawl's `/rename parent-<planName>` line. The crawl's plan-guide route ended at the scaffold with no flow offer, so the user had to ask for the plan flow in a separate message. A crawl started in a plain terminal had no parent name. Session entries on the plan note carried no name, so plan-tracking tooling could not tell a parent session from its children. The post-approval question recommended building in place and bound a bare `yes` to that line in every session, including a parent whose build belongs in a child.

## Decision

- Crawl's plan-guide route ends with the plan flow offer, one plain-text question after the scaffold. A typed `yes` or `run the plan flow` is the user's ask for the plan flow by name, and plan-flow section 3a keeps the route the user confirmed in crawl and asks no route question.
- A `brief - <plan>.md` file beside the note marks it as pre-scaffolded, beside `ticket` frontmatter and a Brief section, and the file stays the verbatim brief. Whenever the brief comes from that file, plan-flow passes the Current Context, Assumptions and Open Questions that crawl wrote to plan-builder in `knownEvidence`, under a lead line that says a crawl correction holds over the brief, on a run from the offer and on any by-name run.
- When the session's name does not start `parent-`, the offer puts a `/rename parent-<planName>` line above the question.
- A session entry carries an optional `name` key, read from the first line of ListAgents on each write of the entry and always written as a double-quoted YAML scalar. Session names hold spaces and colons, and a plain scalar can read as a number, a boolean or null. A session writes no `name` for a name that holds a double quote, a backslash or a control character, because the plan validator reads quoted values with no escape processing.
- The role prefixes are `parent-` and `child-`. `conductor-` and `worker-` were rejected, because the doctrine uses those words for the main session and its subagents.
- The crawl session is the parent of the work it routes. It may run the plan flow itself, and a child session for the build is the recommendation that `plan-guide` makes, not a rule.
- The post-approval question takes the child form, which recommends the child and puts `yes` on that line, when the session's name starts `parent-` or after the context-sentinel ~200k nudge, and the run-here form otherwise. A bare `yes` always takes the recommended line, and it is the ask for the execute flow only in the run-here form.
- The child launch command is `claude -n 'child-<planName>'`, which replaces the child command in [0005](0005-approval-offers-the-execute-flow.md). The refusals still treat `<planName>` as a child name, because tooling reads a session named after the plan as a child.
- A child's report names the child's own session name, read from ListAgents when the report is written, as the recipient of the parent's next dispatch, with `child-<planName>` when the read fails.

## Consequences

The by-hand planning route costs one extra typed reply. Building in a parent session takes the typed `run the execute flow here`, because a bare `yes` there hands the child command, and a session past the ~200k nudge gets the child form too. Each entry write, post-approval question and child report costs one ListAgents call. After a `/rename` the entry shows the old name until its next write. A headless or nameless session records no role, and neither does a session whose name holds a double quote, a backslash or a control character. Older children named after the plan still read as children and still receive dispatches when their ListAgents read succeeds, because their reports then name their own session. When that read fails, the report names `child-<planName>`, which no older child answers to.
