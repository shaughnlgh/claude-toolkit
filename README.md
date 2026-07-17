# claude-toolkit

Shaughn's Claude Code toolkit — agents, skills, and working doctrine — distributed
as a Claude Code plugin. Personally owned and maintained (see LICENSE), free for
anyone with access to use.

Under construction: components land one at a time, each tested through the plugin
before its source-of-truth moves here.

## Setup

After installing, run `/toolkit-setup` in any Claude Code session — it checks
everything below, guides you through the vault config, and prints a readiness report.

- **glab** (GitLab CLI) — required by gitlab-mr-review for API auth.
  Install and authenticate once: `brew install glab && glab auth login`
- **jq** — optional; some scripts degrade gracefully without it.
- **Planning workflow** (optional; required only for plan-workflow / obsidian-topic):
  plan and topic notes are written into an Obsidian vault you control. `/toolkit-setup`
  creates `~/.claude/obsidian-sync.json` from the shipped template; all docs and
  scripts resolve your vault location and root folder from that file.

## Install

```
claude plugin marketplace add git@github.com:shaughnlgh/claude-toolkit.git
claude plugin install toolkit@shaughn-toolkit
```

SSH is required for background auto-update on private repos (HTTPS credential
helpers are disabled for background pulls).

## Uninstall

```
claude plugin uninstall toolkit
claude plugin marketplace remove shaughn-toolkit
rm -rf ~/.claude/plugins/cache/shaughn-toolkit
```

(The cache directory is not swept by uninstall.)
