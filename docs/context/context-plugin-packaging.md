---
title: Plugin packaging
summary: What the installed toolkit plugin contains, and why a file inside the plugin must not link to a file at the repo root.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-05
source_refs:
  - .claude-plugin/marketplace.json
  - plugins/toolkit/
---
<!-- managed-by: toolkit -->

# Plugin packaging

The marketplace entry in `.claude-plugin/marketplace.json` sets the source of the `toolkit` plugin to `./plugins/toolkit`. Claude Code installs a copy of that directory alone, so no file at the repo root, such as `docs/`, `README.md`, `VERIFY.md`, or `verify.sh`, reaches an install.

## Links from plugin files

- A skill, command, doctrine, rule, or agent file must not link to a repo-root file. The link resolves in the repo and dangles in every install. Name the file in prose as a repo file that the plugin does not ship, as the `crawl` skill does for the brief template, or move the content under `plugins/toolkit/`.
- A plugin file reaches another plugin file by a path relative to its own location, such as `../plan-guide/SKILL.md` from a skill's base directory.
- Open item: `commands/setup.md` points at `docs/overrides.md`, and `doctrine/orchestration.md` points at `docs/hooks.md`.

## Related docs

- [skills.md](../skills.md) for what each skill does.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the `toolkit:` namespace that skills and workflow scripts share.
