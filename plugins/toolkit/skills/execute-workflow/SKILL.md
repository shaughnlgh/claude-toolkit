---
name: execute-workflow
description: >-
  MANDATORY companion for execution work. Invoke when starting to execute an approved
  plan, and when debugging runtime/integration issues or finishing implementation work.
  Contains the execution workflow steps, progress report format, the doc update pass
  (run before declaring any task done), and the runtime-evidence debugging method.
  Also invoke plan-workflow at execution start for the plan note spec, status
  lifecycle, and session recording rules.
---

# Execute Workflow

This skill holds the execution-time mechanics. The always-loaded invariants (orchestration rules, execution guardrails, git safety, validation honesty) live in the toolkit's CLAUDE.md doctrine and your global config. The plan note spec, status lifecycle, session recording, and session closure live in the `plan-workflow` skill — invoke that too at execution start.

## Execution Workflow

After plan approval and explicit user instruction to execute:

1. Read the approved plan from the Obsidian plan directory.
2. Re-read the relevant docs and project rules.
3. Main chat acts as supervisor only. Delegate all implementation and verification to worker agents. Do not edit implementation files or run implementation commands directly.
4. Prefer the `implementer` subagent for execution work and the `verifier` for completion checks.
5. Break work into bounded delegated tasks that map back to the plan.
6. Inspect worker results against the plan.
7. Check for knock-on impact in the project's high-risk areas.
8. Have workers run relevant verification.
9. If the actual worker model differs from the requested model and that is visible, report it.
10. Report progress and residual risk.
11. When execution surfaces an idea, requirement, or risk that belongs to a different phase of a multi-part effort, write it into the child plan stub that owns it (Open Questions or Current Context) at the moment it surfaces, and say so. Deferred ideas that live only in conversation get lost. Stub edits go through plan-workflow's mechanics: atomic vault write, then validate-plan.py on the edited stub.

### Build minimal

The plan says what to build; build the least that satisfies it. The subagent-rules hook injects the write-time rules at spawn, but doctrine itself still does not travel on its own, so pass task-relevant doctrine sections down in every implementation delegation, following the handoff template in `../../doctrine/orchestration.md` from this skill's base directory: shortest working diff, no unrequested abstractions, reuse before adding, and trace and grep the callers before changing a shared function. Prefer deleting code to adding it. Mark any deliberate shortcut with a greppable `TODO(author):` comment naming the ceiling and the upgrade path. See `../../doctrine/minimalism.md` from this skill's base directory.

### Progress format

```
### Current step
`<step number and purpose>`

### Files inspected
- `<path>`

### Files changed
- `<path>` — `<what changed>`

### Checks performed
- `<what was verified>`

### Notes
- `<risk, follow-up, or constraint>`
```

## Slice Finalization

When the user signals a completed implementation slice, the `red-team` skill (`../red-team/SKILL.md` from this skill's base directory) owns finalization: it recommends the adversarial review, runs it on confirmation, and ends with a commit suggestion. It invokes this skill's Doc Update Pass once, after its fixes.

## Doc Update Pass

Treat docs as part of the change, not an afterthought. When implementation changes architecture, conventions, contracts, workflow, OR the set of files / modules / commands / options that a doc enumerates, update the affected docs in the same changeset.

Concrete triggers — if you do any of these, find and update the doc that describes it (this list is illustrative, not exhaustive):

- Add, remove, or rename a file, module, class, or function that appears in a documented file tree, module inventory, or API list.
- Change a command, flag, config key, env var, or default that a doc records.
- Change a public contract, schema, route, event, or naming convention a doc describes.

Catch drift reliably — before declaring a task done:

- Grep the `docs/` tree (and `README`, plus repo-local `CLAUDE.md` / `AGENTS.md` / `.claude/rules/` where present) for the names of the files, symbols, commands, or options you added, removed, or renamed. If a doc references the area you touched, update it in the same changeset.
- If the invalidated doc lives in a distributed rules slice (a config plugin) rather than in this repo, it cannot ride this changeset: raise the change against the config repo in the same working session, and say so in your report — never let a distributed doc drift silently.
- Identify affected docs explicitly; do not assume "code-only" until you have checked.
- If a doc update is genuinely deferred, state the debt explicitly rather than leaving it silent.
- Do not let docs drift behind implementation.

Each project defines its commonly impacted docs and any project-specific doc-update triggers in its `01-project-core.md` / `01-project-details.md` or equivalent. Honor those in addition to the triggers above.

## Runtime-Evidence Debugging

When debugging runtime, integration, adapter, or boundary issues, use runtime evidence before fixing.

1. Write 3-5 concrete hypotheses first.
2. Instrument minimally (2-6 logs at decision points).
3. Gather one clean reproduction where possible.
4. Classify hypotheses as confirmed, rejected, or inconclusive.
5. Fix only what the evidence supports, at the root cause rather than per-caller symptom (see the toolkit's minimalism doctrine).
6. Verify the fix with runtime evidence.
7. Remove temporary instrumentation after confirmation.

Do not log secrets or private data. Prefer narrow evidence over speculative defensive code.
