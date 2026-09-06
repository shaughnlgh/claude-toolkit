# claude-toolkit

[![verify](https://github.com/shaughnlgh/claude-toolkit/actions/workflows/verify.yml/badge.svg)](https://github.com/shaughnlgh/claude-toolkit/actions/workflows/verify.yml)

Shaughn's Claude Code toolkit — agents, skills, and working doctrine — distributed as a Claude Code plugin. Personally owned and maintained (see LICENSE), free for anyone with access to use. Third-party components it vendors or adapts are attributed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

Under construction: components land one at a time, each tested through the plugin before its source-of-truth moves here.

## Docs

Full transparency — what ships, what runs automatically, and why.

**The components**

- [`docs/prerequisites.md`](docs/prerequisites.md) — the CLI prerequisites: what each is for, install, and auth.
- [`docs/skills.md`](docs/skills.md) — the skills, with short demos of each in action.
- [`docs/agents.md`](docs/agents.md) — the 14 worker agents and the conductor/leaf-worker model.
- [`docs/commands.md`](docs/commands.md) — all seven slash commands (`/setup`, `/obsidian-topic`, `/override`, and the thinking tools).
- [`docs/hooks.md`](docs/hooks.md) — the ten hooks that run automatically once installed, with no opt-in, in full: what each blocks, what it only asks, env vars, and fail-safe behavior. Read it before trusting the toolkit with a repo.
- [`docs/rules.md`](docs/rules.md) — the write-time rules injected into every session.
- [`docs/scripts.md`](docs/scripts.md) — the shipped scripts and their safety guardrails.
- [`docs/workflows.md`](docs/workflows.md) — the multi-agent workflows (the MR-review engine).

**How it works**

- [`plugins/toolkit/README.md`](plugins/toolkit/README.md) — the conductor-and-workers model and the design decisions behind it.
- [`plugins/toolkit/CLAUDE.md`](plugins/toolkit/CLAUDE.md) — the working doctrine index, one concern per file under [`doctrine/`](plugins/toolkit/doctrine).
- [`docs/overrides.md`](docs/overrides.md) — how to override any default (doctrine, rules, agents, skills) with your own, and how `/override` works.
- [`docs/context-economics.md`](docs/context-economics.md) — how prompt-cache mechanics drive cost, and the practices (and doctrine) that follow from it.
- [`VERIFY.md`](VERIFY.md) — the live-session verification checklist (the mechanical battery is `verify.sh`).

## Prerequisites

The toolkit shells out to a few CLIs rather than holding any credentials of its own: gh, glab, jira-cli, jq, and python3. What each is for, plus the install and auth commands (including the jira token flow), lives in [`docs/prerequisites.md`](docs/prerequisites.md). The Install step below needs gh's SSH setup first; after installing, `/setup` checks every prerequisite and reports exactly what is missing.

## Install

```
claude plugin marketplace add git@github.com:shaughnlgh/claude-toolkit.git
claude plugin install toolkit@shaughn-toolkit
```

Use the SSH URL as shown. HTTPS works for the initial install, but Claude Code's background auto-update disables git credential helpers, so auto-update cannot authenticate to a private repo over HTTPS — only SSH (with a loaded `ssh-agent` key) survives the background pull.

### Install troubleshooting

The marketplace clone runs non-interactively, so it needs GitHub SSH access that works without any prompt: the host key already trusted, and a key loaded in `ssh-agent`. First time using SSH with GitHub on this machine? The easiest path:

```
gh auth login            # choose SSH, let it generate and upload a key
ssh -T git@github.com    # accept the fingerprint once; expect "Hi <username>!"
```

Then the errors, in the order a fresh machine hits them:

- **`Host key verification failed`** — github.com isn't in `~/.ssh/known_hosts` yet. Run `ssh -T git@github.com` once and accept the fingerprint (verify it against [GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)), then re-run the install commands.
- **`Permission denied (publickey)`** — no usable key reached GitHub. If `ssh -T git@github.com` also fails, no key is registered: `gh ssh-key list` shows what GitHub has; fix with `gh auth login` (SSH option) or `gh ssh-key add ~/.ssh/id_ed25519.pub --type authentication`. If `ssh -T` *works* but the install still fails, the key isn't in the agent — interactive ssh can prompt for the passphrase, the clone can't. `ssh-add -l` will say "The agent has no identities"; fix with `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` (use your key's name; plain `ssh-add` on Linux), and make it survive reboots with this in `~/.ssh/config`:

  ```
  Host github.com
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519
  ```

  `UseKeychain` is macOS-only — on Linux it makes ssh reject the whole config file, so omit that line there.

- **`Repository not found`** — SSH auth worked, but your GitHub account has no access to this (private) repo. Ask to be added.
- **`Plugin "toolkit" not found in marketplace "shaughn-toolkit"`** — fallout from a failed `marketplace add`: there is nothing local to install from. Fix the clone error above, re-run the add (or `claude plugin marketplace update shaughn-toolkit` if the marketplace half-exists), then install.

## Setup

After installing, run `/setup` in any Claude Code session — it checks everything below, guides you through the vault config, and prints a readiness report.

- **CLI tooling** — gh, glab, jira, jq, python3: see [`docs/prerequisites.md`](docs/prerequisites.md) for what each is for and the install and auth commands. `/setup` reports the readiness of each.
- **Planning workflow** (optional; required only for plan-workflow / obsidian-topic): plan and topic notes are written into an Obsidian vault you control. If you don't have Obsidian yet, download it from [obsidian.md](https://obsidian.md/), open it, and follow its prompts to create a vault (any name and location work — you'll point the toolkit at it next). `/setup` then creates `~/.claude/obsidian-sync.json` from the shipped template; all docs and scripts resolve your vault location and root folder from that file.

## Updating

New commits are new versions (there is no version field, by design). Pick them up one of two ways.

### Auto-update

Enable auto-update on the marketplace so each session start background-pulls and prompts you to `/reload-plugins` when a new version arrives — either via `/plugin` → Marketplaces → enable auto-update, or in settings:

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

After any update — auto or manual — run `/setup` to confirm you are current: it reports the installed commit and re-checks that every capability is still ready.

## Verifying

`bash verify.sh` runs the mechanical acceptance battery (structure, manifest, hook fixtures, script guardrails, plan validator, vault-fs containment, resolver, docs coverage) — free and fast. `bash functional-test.sh <mode>` adds live hermetic probes (real Claude calls, each in a throwaway workspace; `self-test` mode tests the harness itself for free) that prove rules injection, skill contract facts, and event-verified agent spawns against seeded fixtures. `VERIFY.md` documents what each layer proves and keeps the checklist for what only a real interactive session can show (interview loops, consent gates, live leaf-worker behavior, doctrine adherence, in-session hook enforcement).

## Uninstall

```
claude plugin uninstall toolkit
claude plugin marketplace remove shaughn-toolkit
rm -rf ~/.claude/plugins/cache/shaughn-toolkit
```

(The cache directory is not swept by uninstall.)
