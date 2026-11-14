# claude-toolkit

[![verify](https://github.com/shaughnlgh/claude-toolkit/actions/workflows/verify.yml/badge.svg)](https://github.com/shaughnlgh/claude-toolkit/actions/workflows/verify.yml)

A Claude Code plugin that runs a plan-first workflow: a brief becomes a plan note that you approve, worker agents build it step by step, a review panel checks the result, and a ship flow opens and merges the pull request under the git permissions the plan note records. It ships 14 worker agents, 20 skills, 8 slash commands, 12 hooks, 4 workflows, write-time rules and the doctrine that ties them together. It is for any Claude Code user who wants planned, reviewed changes instead of one long unplanned session. Shaughn owns and maintains it under the MIT license, and the third-party components it vendors or adapts are attributed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## What switches on at install

Installing the plugin switches on twelve hooks in every Claude Code session, with no opt-in and no separate config. They hard-block writes to keys, lockfiles and `.git/`, hard-block a fixed list of destructive shell commands, ask before a write that looks like a credential, inject the write-time rules and a git briefing at session start, and refuse a direct file edit by the main conversation so that a worker agent makes it. [`docs/hooks.md`](docs/hooks.md) lists what each hook blocks, what it only asks, and every environment variable it honors. Read it before you trust the toolkit with a repo.

The override flags are environment variables. `TOOLKIT_CONDUCTOR_EDITS=1` lets the main conversation edit project files for one session, or for one project through `/setup` check 10. `TOOLKIT_CTX_SENTINEL=0` turns off the context-size nudges, and `TOOLKIT_REMEMBER_GUARD=0` turns off the remember-pass warning. [`docs/overrides.md`](docs/overrides.md) explains how to replace any doctrine file, rule, agent or skill with your own copy.

## Quick start

1. Install the plugin with the two commands under [Install](#install).
2. Start a new Claude Code session and run `/setup`. It checks the CLI prerequisites, creates the vault config, and prints a readiness report.
3. In a repo, describe a piece of work. The `crawl` skill reads it, checks it against the codebase, and recommends a route.
4. Ask for the plan flow. It writes a plan note into your vault and stops for your approval.
5. Approve the plan, then ask for the execute flow, and after it the ship flow.

## Supported platforms

- macOS: supported and tested.
- Linux: untested.
- Windows: through WSL, untested.

## Docs

- [`docs/README.md`](docs/README.md) is the index of every page under `docs/`: the components, the glossary, the decision records and the context notes.
- [https://shaughnlgh.github.io/claude-toolkit/](https://shaughnlgh.github.io/claude-toolkit/) is the toolkit site, with walkthroughs of the plan, execute and ship flows.

## Prerequisites

The toolkit shells out to a few CLIs rather than holding any credentials of its own: gh, glab, jira-cli, jq, and python3. [`docs/prerequisites.md`](docs/prerequisites.md) says what each is for and gives the install and auth commands, including the jira token flow. After installing, `/setup` checks every prerequisite and reports what is missing.

## Install

```
claude plugin marketplace add https://github.com/shaughnlgh/claude-toolkit.git
claude plugin install toolkit@shaughn-toolkit
```

If the install reports `Plugin "toolkit" not found in marketplace "shaughn-toolkit"`, the `marketplace add` failed and there is nothing local to install from. Fix the error the add printed, re-run it, or run `claude plugin marketplace update shaughn-toolkit` if the marketplace half-exists, then install.

## Setup

After installing, run `/setup` in any Claude Code session. It checks everything below, guides you through the vault config, and prints a readiness report.

- **CLI tooling**: gh, glab, jira, jq, python3. See [`docs/prerequisites.md`](docs/prerequisites.md) for what each is for and the install and auth commands. `/setup` reports the readiness of each.
- **Planning workflow** (optional, needed only by `plan-guide` and `/topic`): plan notes and topic notes are written into a vault you control. Any folder of markdown works, and no note-taking app is required. If you have none yet, create an empty folder in any location. `/setup` then creates `~/.claude/toolkit-vault.json` from the shipped template, and every script and skill resolves your vault location and root folder from that file. An install that already holds `~/.claude/obsidian-sync.json` keeps working, because every reader falls back to it when `~/.claude/toolkit-vault.json` is absent.

## Updating

New commits are new versions, and there is no version field by design. Pick them up one of two ways.

### Auto-update

Enable auto-update on the marketplace so each session start pulls in the background and prompts you to `/reload-plugins` when a new version arrives. Turn it on through `/plugin`, then Marketplaces, then enable auto-update, or in settings:

```json
"extraKnownMarketplaces": {
  "shaughn-toolkit": {
    "source": { "source": "git", "url": "https://github.com/shaughnlgh/claude-toolkit.git" },
    "autoUpdate": true
  }
}
```

### Manual update

Without auto-update, pull the latest when you want it:

```
claude plugin update toolkit@shaughn-toolkit
```

After any update, auto or manual, run `/setup` to confirm you are current. It reports the installed commit and re-checks that every capability is still ready.

## Verifying

`bash verify.sh` runs the mechanical acceptance battery (structure, manifest, hook fixtures, script guardrails, plan validator, topic recall, vault-fs containment, resolver, docs coverage), free and fast. `bash functional-test.sh <mode>` adds live hermetic probes: real Claude calls, each in a throwaway workspace, with a `self-test` mode that tests the harness itself for free. They prove rules injection, skill contract facts, and event-verified agent spawns against seeded fixtures. [`VERIFY.md`](VERIFY.md) documents what each layer proves and keeps the checklist for what only a real interactive session can show (interview loops, consent gates, live leaf-worker behavior, doctrine adherence, in-session hook enforcement).

### Testing a branch

`claude --plugin-dir <checkout>/plugins/toolkit` replaces the installed toolkit for that session, and hooks, skills, commands, and agents each resolve the plugin root from that copy. The global CLAUDE.md lines that `/setup` writes resolve the installed root only for calls outside a toolkit skill, command, or agent, and `/setup` offers the current lines to a user whose block predates them. The script allow rules match only the installed cache path, so a script call in such a session asks or goes to the classifier.

## Contributing and security

The repo takes bug reports and security reports. Outside pull requests are by invitation. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for bug reports and pull requests, and [`SECURITY.md`](SECURITY.md) for how to report a security issue.

## Uninstall

```
claude plugin uninstall toolkit
claude plugin marketplace remove shaughn-toolkit
rm -rf ~/.claude/plugins/cache/shaughn-toolkit
```

Uninstall does not sweep the cache directory, so the third command removes it.

## License

MIT, see [`LICENSE`](LICENSE). Third-party components are attributed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
