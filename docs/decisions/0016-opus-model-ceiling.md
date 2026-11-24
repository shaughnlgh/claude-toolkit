---
title: Opus model ceiling
summary: Every agent a lead starts runs on Opus at most unless the user named a model, enforced by a refusal in each workflow runner of a launch with no models map, an Opus default for the planner, skills that stop when the resolver fails, and an agent-model.sh branch that sends an inheriting built-in Agent-tool spawn to Opus under a session model above it.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-24
---

# 0016. Opus model ceiling

Date: 2026-11-24

Status: Accepted

## Context

A workflow runner took `models` as an optional arg, and each skill fell back to a launch without it when `resolve-models.sh` failed, so a launch with no map ran every agent on the session model. The shipped template left the `planner` entry blank, so the planner inherited the session model too. Built-in Agent-tool types such as `general-purpose` and `Plan` also inherit the session model. Routing therefore depended on a session remembering a prose step: a review launch with no `models` under a session model above Opus ran every agent on that model and spent the usage limit within minutes.

## Decision

- The model ceiling is Opus. Every agent and worker session a lead starts runs on Opus at most, unless the user named a higher model. Only the user's own picks name a model: a model picked in a run option question on the plan note, or written in the user's own `~/.claude/toolkit-models.json`.
- Each runner, `review-mr.js`, `execute-runner.js`, `ship-runner.js` and `plan-builder.js`, refuses a launch whose `models` is missing or is not a map of agent names to `{model, effort}` objects, with an error that says it `requires models`.
- The shipped `toolkit-models.json.template` gives every agent Opus or Sonnet, the `planner` included, so no shipped entry inherits the session model.
- Every skill that launches a runner stops and reports the resolver's error when the resolver is missing or fails, and launches nothing.
- `hooks/agent-model.sh` sends an Agent-tool call with no type, or with the built-in inheriting type `general-purpose`, `Plan`, `Explore` or `claude`, to `opus` when the transcript's newest real assistant line names a session model outside the Opus, Sonnet and Haiku families. A `model` on the call, `CLAUDE_CODE_SUBAGENT_MODEL` for the types it applies to, a project or user agent file that shadows the name, and an entry under the built-in name in the user's own models file each win as the user's pick, and a value of `inherit` there keeps the session model.

Alternatives weighed and rejected: a clamp inside each runner that rewrites any model above Opus, because a runner cannot tell a user's pick from a default and would override the user; keeping the planner on the session model, because a lead on a model above Opus would plan on that model; and leaving the launch fallback in place, because the fallback is the defect.

## Consequences

jq 1.6 or later becomes a requirement of every plan, execute, ship, red-team and gitlab-mr-review launch, because the resolver needs it and those launches stop without it. Setup check 5 and `docs/prerequisites.md` name it, and the readiness verdict names installing it. A resumed run whose cached launch args lack `models` fails at launch once, and the flow relaunches with the resolver's map. The hook covers only the built-in types it names, so a new inheriting built-in type, or another plugin's agent whose frontmatter inherits the session model, is held to the ceiling only by the doctrine line that a lead passes `model: opus` on any other Agent call. A session model id with a new family name is treated as above Opus until the user names it. A user who wants a model above Opus names it in a run option or in their own models file.
