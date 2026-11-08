---
title: Model routing
summary: How the toolkit resolves each agent's model and effort for Agent-tool spawns and Workflow agent() calls, and the couplings a change to the resolver, the hook, the session scratchpad library, or the launchers must keep.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-11-08
source_refs:
  - plugins/toolkit/scripts/resolve-models.sh
  - plugins/toolkit/scripts/toolkit-models.json.template
  - plugins/toolkit/hooks/agent-model.sh
  - plugins/toolkit/hooks/lib/session-scratchpad.sh
  - plugins/toolkit/hooks/tests/agent-model-options-check.sh
  - plugins/toolkit/hooks/tests/fixtures/agent-model/
  - plugins/toolkit/skills/plan-guide/SKILL.md
  - https://code.claude.com/docs/en/sub-agents
---
<!-- managed-by: toolkit -->

# Model routing

`scripts/resolve-models.sh` layers the shipped template, the user file, and the plan note's run options into one `{model, effort}` entry per agent. The `agent-model.sh` hook applies that map to Agent-tool spawns, and the runner scripts apply it to their `agent()` calls through the `models` arg. What each piece does is in [scripts.md](../scripts.md), [hooks.md](../hooks.md), and [workflows.md](../workflows.md). This page covers the couplings a change must keep. The runner side of the `models` arg is in [context-workflow-script-authoring.md](context-workflow-script-authoring.md).

## Limits of the Agent tool

- The Agent tool's `model` input takes only a model alias (`sonnet`, `opus`, `haiku`, `fable`), never a full model ID or `inherit`, per the [Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents). `inherit` exists only in agent definition frontmatter. No hook can therefore route an Agent-tool spawn to the parent session's model. The hook can only leave the field out, and the spawn then falls to the agent definition's model, a configured default subagent model, and the parent session's model, in that order.
- The resolver accepts a full model ID and an `[1m]` suffix, and the workflow runners pass either one unchanged. The hook sends such a value to the Agent tool as the one family alias it names (`opus`, `sonnet`, `haiku` or `fable`), adds no model when it names none or several, and names the original value in a `systemMessage` either way. The mapping lives in the hook, not the resolver, so the workflow path keeps the full value. Fixtures `12` and `15` in `fixtures/agent-model/` pin both outcomes.
- For that reason the resolver turns `inherit` into a blank field, the hook adds no blank field, and the template leaves `planner` blank.
- The shipped agent files pin no `model` or `effort`, so the template is the only default layer. The orchestration invariants check in `verify.sh` fails when an agent file's frontmatter carries a `model:` or `effort:` line.
- Check 8 in `commands/setup.md` is the only place that states the Claude Code version the hook's `effort` field was tested on. [commands.md](../commands.md) and [hooks.md](../hooks.md) point to it, so a newly tested version changes that one line.

## Resolver

- `TOOLKIT_MODELS_TEMPLATE` replaces the template path. It is the test seam that lets the hook fixtures and the resolver suite read a crafted default layer.
- `opt()` in `resolve-models.sh` reads a run options cache line the way `ro_line()` in `hooks/session-start.sh` does: leading spaces allowed, the value trimmed at both ends. A change to how one of them reads the cache must be made in the other.
- The `--agent` filter keys on the warning text. A warning about one agent's value starts with `[<agent>]` and ends with `; ignored`. `--agent <name>` prints the bracketed warnings for that name and every warning that has no bracket. A new value warning that leaves out the bracket prints for every agent, so the hook relays it on every Agent-tool spawn.
- The header comment on line 2 of `resolve-models.sh` lists every exit-2 case. A new error case adds itself there.
- The model and effort value checks mirror `MODEL_RE` and `EFFORTS` in `validate-plan.py`, as [context-plan-note-section-checks.md](context-plan-note-section-checks.md) states.

## Session scratchpad library

- `hooks/lib/session-scratchpad.sh` is the only file that holds the `/tmp/claude-<uid>/*/<session_id>/scratchpad` glob and the `flow-run-options` cache file name. `session_scratchpads` prints nothing for an id that is not a plain id, `session_scratch_file` picks the newest file across slug directories, and `session_run_options_file` names the cache. `agent-model.sh` and `session-start.sh` both source the file, so both hooks read the same cache.
- Both hooks source the library from their own directory. When the source fails, `agent-model.sh` adds nothing and says so in a `systemMessage`, and `session-start.sh` sets `SCRATCHPAD_LIB_MISSING`, which on a compaction adds a context line saying the handoff and the run options ceiling were not reinjected.
- `session-start.sh` reads the cache through `session_run_options_file` only when it found a session scratchpad, which sets `SCRATCH`. The `TOOLKIT_COMPACT_HANDOFF` path leaves `SCRATCH` empty, so a run on that path reads no cache.

## Launchers

- The resolver launch procedure lives once, in plan-guide § Run options. It covers one flag per non-blank value, the repo copy of the resolver when `repoRoot` holds one, stderr reported to the user on exit 0, and a launch without `models` when the resolver is missing or fails. Each flag value is single-quoted, because zsh reads an unquoted `[1m]` suffix as a glob and aborts the command with `no matches found`. `plan-flow`, `execute-flow`, and `ship-flow` point to that procedure.
- `gitlab-mr-review` and `red-team` read no run options, so they run the resolver with no flags and carry their own copy of the repo-copy, stderr, and fail-open sentences. A change to that part of the procedure must be made in plan-guide and in both skills.
- The `models` arg is named in five places: the plan-flow args sentence, the execute-flow and ship-flow args lists, the gitlab-mr-review args block, and the red-team launch sentence.

## Testing

- Every `agent-model` fixture except `08` and `11` sets `TOOLKIT_MODELS_TEMPLATE` to `fixtures/agent-model/aux/template.json`, and `11` is the empty-stdin case. Fixture `08` is therefore the only hook fixture that checks the shipped template's values, so a template edit changes its expectations and no other fixture's.
- Check 1 in `agent-model-options-check.sh` reads the shipped template's `implementer` effort instead of a literal, so a template edit does not break it.
- The resolver-failure check copies the hook, the resolver, and a broken template into a scratch plugin tree. The copy must include `hooks/lib/session-scratchpad.sh`. Without it the hook stops at the source with the library message, never runs the resolver, and the check fails for the wrong reason.
- The no-jq check runs the hook with a `PATH` that holds only a symlink to `cat`, because the hook reads stdin with `cat` before it tests for `jq`.
