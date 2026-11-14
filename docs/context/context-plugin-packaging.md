---
title: Plugin packaging
summary: What the installed toolkit plugin contains, why a file inside the plugin must not link to a file at the repo root, how a skill, command, or agent names the plugin root of the copy Claude Code loaded, and the length cap on a skill listing.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-11-09
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
- A skill reaches another plugin file through its plugin root, such as `<plugin-root>/skills/plan-guide/SKILL.md` or `<plugin-root>/workflows/<name>.js`, and never by a bare `../..` or `../<name>/` path, because a `/override` copy under `~/.claude/skills/<name>/` resolves such a path inside `~/.claude/`. A `verify.sh` check fails when a skill line outside its plugin-root sentence carries such a path.
- Open item: `commands/setup.md` points at `docs/overrides.md`, and `doctrine/orchestration.md` points at `docs/hooks.md`.

## Plugin root

- A skill names its plugin root as `../..` from its base directory, the directory that holds its `SKILL.md`, because the base directory follows the copy Claude Code loaded, a `claude --plugin-dir` copy included. Each such sentence states that this root takes precedence over a CLAUDE.md line that resolves the installed root, because the global CLAUDE.md blocks that `/setup` writes resolve the installed root for calls outside the toolkit. Each such sentence then says that when `../../.claude-plugin/plugin.json` does not exist, the plugin root is the installed root, resolved from `~/.claude/plugins/installed_plugins.json` as the setup CLAUDE.md blocks resolve it, because a `/override` copy under `~/.claude/skills/<name>/` resolves `../..` as `~/.claude`. Every plugin copy, the installed one, a `--plugin-dir` copy and the repo's `plugins/toolkit`, carries that manifest, and a user's `~/.claude/` can hold a `scripts/` directory of its own, so the test names the manifest. A `verify.sh` check fails when a skill's plugin-root sentence lacks the precedence sentence or the fallback with the setup block's `jq` expression.
- A command or an agent names its root as `${CLAUDE_PLUGIN_ROOT}`, because Claude Code substitutes the loaded copy's root in command and agent bodies and gives neither a base directory. A Read of a command file substitutes nothing, so `commands/topic.md`, which skills Read, defines the root for both cases. An agent copy under `~/.claude/agents/` gets no substitution, so an agent that runs a plugin script tests `$PLUGIN_ROOT/.claude-plugin/plugin.json` and falls back to the installed root the same way, as `agents/frontend-designer.md` does, and a `verify.sh` check holds that block to it.
- The CLAUDE.md blocks in `commands/setup.md` keep the `jq` resolution of the installed root and never carry `${CLAUDE_PLUGIN_ROOT}`, because the user's file would pin one version's path. A `verify.sh` check fails when a file under `skills/`, `agents/` or `commands/` other than `commands/setup.md` names `installed_plugins.json`, with two allowances. A skill's or an agent's plugin manifest fallback is the one allowed read of the toolkit root. A line whose only plugin read is `.plugins[][0].installPath` passes, because it lists every plugin's root to find a file in another plugin.

## Skill listing

- Claude Code truncates a skill's `description` plus `when_to_use` at 1,536 characters in the skill listing, so a trigger phrase past that point never reaches the model. A `verify.sh` check counts the two folded frontmatter values of every `skills/*/SKILL.md` and fails when one skill exceeds the cap. A skill that needs more detail moves it into the body.

## Related docs

- [skills.md](../skills.md) for what each skill does.
- [context-workflow-script-authoring.md](context-workflow-script-authoring.md) for the `toolkit:` namespace that skills and workflow scripts share.
