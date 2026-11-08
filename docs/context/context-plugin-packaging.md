---
title: Plugin packaging
summary: What the installed toolkit plugin contains, why a file inside the plugin must not link to a file at the repo root, how a skill, command, or agent names the plugin root of the copy Claude Code loaded, and the length cap on a skill listing.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-08
source_refs:
  - .claude-plugin/marketplace.json
  - plugins/toolkit/
  - verify.sh
---
<!-- managed-by: toolkit -->

# Plugin packaging

The marketplace entry in `.claude-plugin/marketplace.json` sets the source of the `toolkit` plugin to `./plugins/toolkit`. Claude Code installs a copy of that directory alone, so no file at the repo root, such as `docs/`, `README.md`, `VERIFY.md`, or `verify.sh`, reaches an install.

## Links from plugin files

- A skill, command, doctrine, rule, or agent file must not link to a repo-root file. The link resolves in the repo and dangles in every install. Name the file in prose as a repo file that the plugin does not ship, as the `crawl` skill does for the brief template, or move the content under `plugins/toolkit/`.
- A plugin file reaches another plugin file by a path relative to its own location, such as `../plan-guide/SKILL.md` from a skill's base directory.
- Open item: `commands/setup.md` points at `docs/overrides.md`, and `doctrine/orchestration.md` points at `docs/hooks.md`.

## Plugin root

- A skill names its plugin root as `../..` from its base directory, the directory that holds its `SKILL.md`, because the base directory follows the copy Claude Code loaded, a `claude --plugin-dir` copy included. Each such sentence states that this root takes precedence over a CLAUDE.md line that resolves the installed root, because the global CLAUDE.md blocks that `/setup` writes resolve the installed root for calls outside the toolkit.
- A command or an agent names its root as `${CLAUDE_PLUGIN_ROOT}`, because Claude Code substitutes the loaded copy's root in command and agent bodies and gives neither a base directory. A Read of a command file substitutes nothing, so `commands/obsidian-topic.md`, which skills Read, defines the root for both cases.
- The CLAUDE.md blocks in `commands/setup.md` keep the `jq` resolution of the installed root and never carry `${CLAUDE_PLUGIN_ROOT}`, because the user's file would pin one version's path. A `verify.sh` check fails when any file under `skills/`, `agents/` or `commands/` other than `commands/setup.md` names `installed_plugins.json`.

## Skill listing

- Claude Code truncates a skill's `description` plus `when_to_use` at 1,536 characters in the skill listing, so a trigger phrase past that point never reaches the model. A `verify.sh` check counts the two folded frontmatter values of every `skills/*/SKILL.md` and fails when one skill exceeds the cap. A skill that needs more detail moves it into the body.

## Related docs

- [skills.md](../skills.md) for what each skill does.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the `toolkit:` namespace that skills and workflow scripts share.
