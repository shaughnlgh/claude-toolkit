# claude-toolkit

Shaughn's Claude Code toolkit — agents, skills, and working doctrine — distributed
as a Claude Code plugin. Personally owned and maintained (see LICENSE), free for
anyone with access to use. Third-party components it vendors (currently the
design-detector, Apache-2.0) are attributed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

Under construction: components land one at a time, each tested through the plugin
before its source-of-truth moves here.

## Docs

Full transparency — what ships, what runs automatically, and why.

**The components**

- [`docs/skills.md`](docs/skills.md) — the skills, with short demos of each in action.
- [`docs/agents.md`](docs/agents.md) — the 12 worker agents and the conductor/leaf-worker model.
- [`docs/commands.md`](docs/commands.md) — the slash commands (`/toolkit-setup`, `/obsidian-topic`).
- [`docs/hooks.md`](docs/hooks.md) — the five hooks that run automatically once installed,
  with no opt-in, in full: what each blocks, what it only asks, env vars, and fail-safe
  behavior. Read it before trusting the toolkit with a repo.
- [`docs/rules.md`](docs/rules.md) — the write-time rules injected into every session.
- [`docs/scripts.md`](docs/scripts.md) — the shipped scripts and their safety guardrails.
- [`docs/workflows.md`](docs/workflows.md) — the multi-agent workflows (the MR-review engine).

**How it works**

- [`plugins/toolkit/README.md`](plugins/toolkit/README.md) — the conductor-and-workers
  model and the design decisions behind it.
- [`plugins/toolkit/CLAUDE.md`](plugins/toolkit/CLAUDE.md) — the working doctrine index,
  one concern per file under [`doctrine/`](plugins/toolkit/doctrine).
- [`docs/overrides.md`](docs/overrides.md) — how to override any default (doctrine, rules,
  agents, skills) with your own, and how `/override` works.
- [`VERIFY.md`](VERIFY.md) — the live-session verification checklist (the mechanical
  battery is `verify.sh`).

## Install

```
claude plugin marketplace add git@github.com:shaughnlgh/claude-toolkit.git
claude plugin install toolkit@shaughn-toolkit
```

Use the SSH URL as shown. HTTPS works for the initial install, but Claude Code's
background auto-update disables git credential helpers, so auto-update cannot
authenticate to a private repo over HTTPS — only SSH (with a loaded `ssh-agent` key)
survives the background pull.

## Setup

After installing, run `/toolkit-setup` in any Claude Code session — it checks
everything below, guides you through the vault config, and prints a readiness report.

- **glab** (GitLab CLI) — required by gitlab-mr-review for API auth.
  Install and authenticate once: `brew install glab && glab auth login`
- **jq** — optional; some scripts degrade gracefully without it.
- **python3** — required by the planning workflow's scripts (`vault-fs.sh` resolves
  the vault config with it; `validate-plan.py` and `merge-conflict-overview.py` are
  Python). Requires Python 3; no third-party packages are required.
- **Planning workflow** (optional; required only for plan-workflow / obsidian-topic):
  plan and topic notes are written into an Obsidian vault you control. `/toolkit-setup`
  creates `~/.claude/obsidian-sync.json` from the shipped template; all docs and
  scripts resolve your vault location and root folder from that file.

## Updating

New commits are new versions (there is no version field, by design). Pick them up
one of two ways.

### Auto-update

Enable auto-update on the marketplace so each session start background-pulls and
prompts you to `/reload-plugins` when a new version arrives — either via `/plugin` →
Marketplaces → enable auto-update, or in settings:

```json
"extraKnownMarketplaces": {
  "shaughn-toolkit": {
    "source": { "source": "git", "url": "git@github.com:shaughnlgh/claude-toolkit.git" },
    "autoUpdate": true
  }
}
```

### Manual update

Without auto-update, pull the latest when you want it:

```
claude plugin update toolkit@shaughn-toolkit
```

Either way, `/toolkit-setup` always reports the installed commit so you can see
whether you are current.

## Verifying

`bash verify.sh` runs the mechanical acceptance battery (structure, manifest, hook
fixtures, script guardrails, plan validator, resolver, leakage) — free and fast.
`bash functional-test.sh <mode>` adds live hermetic probes (real Claude calls,
each in a throwaway workspace; `self-test` mode tests the harness itself for
free) that prove rules injection, skill contract facts, and event-verified agent
spawns against seeded fixtures. `VERIFY.md` documents what each layer proves and
keeps the checklist for what only a real interactive session can show
(interview loops, consent gates, live leaf-worker behavior, doctrine adherence,
in-session hook enforcement).

## Uninstall

```
claude plugin uninstall toolkit
claude plugin marketplace remove shaughn-toolkit
rm -rf ~/.claude/plugins/cache/shaughn-toolkit
```

(The cache directory is not swept by uninstall.)
