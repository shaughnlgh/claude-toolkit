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

## Hooks (transparency)

This plugin ships hooks — scripts that run automatically once installed. Exactly what
runs, and when:

| Event | Script | What it does |
|---|---|---|
| Before Edit/Write | `protect-files.sh` | Hard-blocks writes to keys/certs/lockfiles/generated files; asks for confirmation on `.env*` and `settings.json` |
| Before Edit/Write | `scan-secrets.sh` | Asks for confirmation on writes that embed credentials (API keys, tokens, private keys, connection-string passwords) — overridable, not a hard block |
| Before Bash | `block-dangerous-commands.sh` | Blocks destructive commands (`rm -rf /`, force-push to main, `chmod 777`, unguarded SQL DELETE, curl-pipe-sudo, …) |
| Session start | `session-start.sh` | Into context: the write-time rules verbatim (testing, security, error-handling, database; ~680 tokens), a doctrine pointer, and a one-line git briefing (verbose via `TOOLKIT_SESSION_VERBOSE=1`). To the user (startup only): a one-line "toolkit active" status via `systemMessage`. Emits JSON when `jq` is present; falls back to plain-stdout context otherwise |
| Notification | `notify.sh` | Native OS notification when Claude needs input (macOS/Linux/WSL, silent elsewhere) |

All hooks fail safe (never block a session on their own errors), read no network, and
are covered by the test suite in `hooks/tests/` (`bash run-all.sh`).

## Install

```
claude plugin marketplace add git@github.com:shaughnlgh/claude-toolkit.git
claude plugin install toolkit@shaughn-toolkit
```

Use the SSH URL as shown. HTTPS works for the initial install, but Claude Code's
background auto-update disables git credential helpers, so auto-update cannot
authenticate to a private repo over HTTPS — only SSH (with a loaded `ssh-agent` key)
survives the background pull.

### Staying current

New commits are new versions (there is no version field, by design). To pick them
up automatically, enable auto-update on the marketplace so each session start
background-pulls and prompts you to `/reload-plugins` when a new version arrives —
either via `/plugin` → Marketplaces → enable auto-update, or in settings:

```json
"extraKnownMarketplaces": {
  "shaughn-toolkit": {
    "source": { "source": "git", "url": "git@github.com:shaughnlgh/claude-toolkit.git" },
    "autoUpdate": true
  }
}
```

Without it, update by hand when you want the latest: `claude plugin update
toolkit@shaughn-toolkit`. Either way, `/toolkit-setup` always reports the installed
commit so you can see whether you are current.

## Verifying

`bash verify.sh` runs the mechanical acceptance battery (structure, manifest, hook
fixtures, script guardrails, resolver, leakage). `VERIFY.md` adds the live-session
checklist for behavior that can't be scripted (agent spawns, skill prompts, doctrine
adherence, in-session hook enforcement).

## Uninstall

```
claude plugin uninstall toolkit
claude plugin marketplace remove shaughn-toolkit
rm -rf ~/.claude/plugins/cache/shaughn-toolkit
```

(The cache directory is not swept by uninstall.)
