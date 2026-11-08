---
description: Check this machine's toolkit setup and walk through anything missing — safe to re-run, changes nothing without asking
---

# Toolkit Setup

Check this machine's toolkit setup and guide the user through anything missing. Safe to re-run anytime; it changes nothing without asking first.

## Usage

$ARGUMENTS

No arguments. Run the checks below in order, then print the readiness report.

## Checks

### 1. Plugin state

Report the toolkit's install location (this command's base directory) and content version (the version segment in the base directory path, or `git -C` describe if available; otherwise "unknown").

### 2. Vault config (needed by plan-guide and obsidian-topic only)

Check `~/.claude/obsidian-sync.json`:

- Missing entirely: tell the user the planning workflow is unconfigured. Offer to create the config from (the shipped template `scripts/obsidian-sync.json.template` at the plugin root). If they accept: ask for their vault path, verify that directory exists on disk, write the config with their values, then re-run this check.
- Present: validate it —
  - parses as JSON,
  - `vault_path` points at a directory that exists,
  - `root_folder` is set,
  - internal consistency: `plan_folder_template` is set and starts with `root_folder`. A mismatched template is a common hand-edit error; report the disagreement and offer the fix.
  - Tolerate unknown or legacy fields (a live config may carry extra fields for external consumers). Never rewrite or "clean" an existing config.
- Note: `<root_folder>/Projects/` does not need to pre-exist; it is created on first plan write.

### 3. GitLab tooling (needed by gitlab-mr-review only)

- `glab` installed? If yes, run `glab auth status` and report per-host state. NEVER print a token value, even partially. If unauthenticated, tell the user: `glab auth login`.

### 4. Jira tooling (needed by the jira skill only)

- `jira` (jira-cli) installed? If yes, run `jira me >/dev/null` and report whether the authenticated probe succeeds. NEVER print a token value, even partially. If it fails, tell the user: `brew install jira-cli` if missing, then `jira init` (one-time), and ensure `JIRA_API_TOKEN` is exported from the user's shell rc file (`~/.zshrc`, `~/.bashrc`, or equivalent).

### 5. Other tooling

- `gh` present? (Optional; the SSH-based install path and read-only GitHub checks use it.)
- `jq` present? (Required by the ship flow's `watch-mr.sh` watcher; other scripts prefer it and degrade without it.)
- `python3` present? (Required by the planning workflow's scripts.)

### 6. Permissions and environment (optional, consent-gated)

Six optional additions, shown verbatim, explained in one line, and applied only on an explicit yes. They span the user's `~/.claude/settings.json` (merge into the existing `permissions.allow` / `env` / `extraKnownMarketplaces` objects, never replacing them, always leaving valid JSON) and the global `~/.claude/CLAUDE.md`.

- **Prompt-free toolkit scripts.** The plugin's vault, git, and MR-watch scripts are invoked by its skills from the plugin cache. Offer these allow rules, written with the user's absolute home path (mid-path wildcards are supported and make the rules survive plugin updates):

      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/vault-fs.sh *)
      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/git-ro.sh *)
      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/watch-mr.sh *)

  Explain the trade honestly: without them, the first vault write per repo prompts once and the ship flow's background watcher prompts before it starts ("always allow" works but embeds the version hash, so it re-prompts after updates). The vault and git scripts are guard-railed (relative-path-only vault ops; read-only git) and reviewable in the plugin. `watch-mr.sh` only reads an MR or PR through `gh` or `glab` and exits with a status, so the ship flow can wait on a pipeline in the background without a prompt. When the rules are accepted, ALSO offer to append this usage block to the user's global `~/.claude/CLAUDE.md` (they are one unit, because the rules only match invocations written this way):

      ## Toolkit Scripts
      Invoke via the CURRENT installed plugin root: resolve it first, e.g.
      `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json`,
      then invoke with that literal absolute path (matches the allowlist rule).
      - `bash <plugin-root>/scripts/vault-fs.sh rm|mv ...` - vault file ops with
        guardrails; atomic writes: Write tool to a `.tmp.md` file beside the destination, then vault-fs.sh mv.
        Vault root resolves from `~/.claude/obsidian-sync.json`.
      - `bash <plugin-root>/scripts/git-ro.sh <dir> <status|diff|log|show>` -
        read-only git anywhere; mutation subcommands refused.
      - `bash <plugin-root>/scripts/watch-mr.sh <host> <remotePath> <number> pipeline|threads|review --sha <sha> [--bound <n>]` -
        waits on an MR or PR pipeline or bot review and exits with one status line. The ship flow starts it in the background.
- **Read-only command allowlist.** The workflows lean on read-only `gh`/`glab`/`jira` calls that otherwise prompt on every new machine. Offer these `permissions.allow` rules (all inherently read-only subcommands — never offer mutating ones like `gh api -X`, `gh pr merge`, or `glab mr merge`, which must keep prompting):

      Bash(gh pr view:*)
      Bash(gh pr list:*)
      Bash(gh pr checks:*)
      Bash(gh pr diff:*)
      Bash(gh run list:*)
      Bash(gh run view:*)
      Bash(glab mr view:*)
      Bash(glab mr list:*)
      Bash(glab mr diff:*)
      Bash(glab auth status:*)
      Bash(jira me:*)

  Skip any rule already present. Mention that `/fewer-permission-prompts` extends the allowlist from this machine's actual usage history when prompt fatigue persists.

- **Auto mode git rules (only when `permissions.defaultMode` is `auto`).** Under auto mode every command no allow rule matches goes to the permission classifier. The classifier reads the user's typed messages, tool calls, and CLAUDE.md, never a tool result, so the plan note's recorded ceiling is invisible to it and an `mr` ceiling does not stop denials of commit, push, or MR creation. Offer these `permissions.allow` rules, with the create rule for the host the user works on (`gh pr create` for GitHub, `glab mr create` for GitLab, both when they use both):

      Bash(git add:*)
      Bash(git commit:*)
      Bash(git push:*)
      Bash(glab mr create:*)
      Bash(gh pr create:*)

  Explain the trade: these rules let a plan note's `ceiling: mr` or `ceiling: merge` hold without a classifier check on every commit, push, and MR. Merge and tag are never offered, so the merge and the tag under `ceiling: merge` stay under the classifier and the `block-dangerous-commands` hook still guards protected branches. Skip when the mode is not `auto`, and skip any rule already present. Then check `autoMode.environment`: when that array exists and no line names the hosts the user pushes to (read `git remote get-url origin` in the current repo for one), explain that the block was generated for one repo and the classifier treats every other remote as a foreign system, and offer to append one line naming the user's hosts and project groups, for example `- **Trusted repos (all projects)**: every remote on <host> under <group> is the user's own; commit, push, and MR creation there is routine once the user asked for the fix`. `autoMode` is read from `~/.claude/settings.json` only, never from a project settings file.

- **Orchestration environment.** The toolkit's orchestration doctrine routes every worker question or blocker to the conductor; the built-in advisor tool is a side-channel around that. Offer:

      "env": { "CLAUDE_CODE_DISABLE_ADVISOR_TOOL": "1" }

  If the key is already set to "1", report it as current. If set to something else, report the conflict and let the user decide — do not overwrite silently.

- **Doctrine and rules pointer.** The toolkit's working doctrine ships at the plugin root (`CLAUDE.md` index + `doctrine/` files + design `README.md`) and its write-time rules ship under `rules/`, but sessions and especially subagents only find either via the user's global `~/.claude/CLAUDE.md`. Check that file contains a pointer to the plugin's CLAUDE.md, README.md, and rules/ directory. If absent, offer to append this block (or create a minimal global CLAUDE.md holding just it, if none exists):

      ## Toolkit Doctrine
      The binding doctrine lives in the toolkit plugin. Resolve the current install
      root first, e.g. `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath'
      ~/.claude/plugins/installed_plugins.json`, then read the index at
      `<plugin-root>/CLAUDE.md`. Design rationale: `<plugin-root>/README.md`.
      Personal overrides: state one inline below, or drop a same-named file in
      ~/.claude/doctrine/ (auto-detected each session, no pointer needed).
      Write-time rules: before writing code, tests, queries, error handling, or
      documentation/comments, read the matching file under `<plugin-root>/rules/`
      (testing.md, security.md, error-handling.md, database.md, performance.md,
      writing.md, frontend.md, prose.md).

- **Auto-update.** New commits are new versions. Offer to enable marketplace auto-update by merging into `~/.claude/settings.json` (top-level `extraKnownMarketplaces`, merged into any existing object, never replacing it):

      "extraKnownMarketplaces": {
        "shaughn-toolkit": {
          "source": { "source": "git", "url": "git@github.com:shaughnlgh/claude-toolkit.git" },
          "autoUpdate": true
        }
      }

  Explain the trade: with it on, each session start background-pulls and prompts `/reload-plugins` when a new version arrives — this needs the SSH marketplace remote (see the root README's Install), as the background pull cannot authenticate over HTTPS. If `shaughn-toolkit` is already present with `"autoUpdate": true`, report it as current. If present but `autoUpdate` is false or absent, offer to set only that field, leaving the existing `source` untouched. Applied only on an explicit yes.

Do not offer to pre-create override directories — `/override` creates whatever it needs when a doctrine, rule, agent, or skill override is actually made, and an empty directory has no effect. In the readiness report, mention once that overrides for all four types are available via `/override` (see `docs/overrides.md`; safety sections may be tightened, not loosened).

If any offer is declined, note the practical effects (occasional permission prompts; advisor available to workers; doctrine unreachable by subagents; updates must be pulled manually) and move on. Never re-nag on later runs: report current state, offer only what is absent.

### 7. Local copies that conflict with the plugin (migration check)

If this machine previously ran a copy-pasted version of this setup, local copies now conflict with the plugin. Detect each class and explain its exact effect:

- **Hooks (double-fire):** in `~/.claude/settings.json` (and the project's `.claude/settings.json` if present), find hook registrations whose script names match plugin-shipped hooks (session-start, notify, protect-files, scan-secrets, block-dangerous-commands). Effect: both copies run on every event. Offer to remove the local registrations, and afterwards the `~/.claude/hooks/` scripts they point at.
- **Agents (silent shadowing):** files in `~/.claude/agents/` whose names match plugin agents. Effect: the LOCAL copy wins (user scope outranks plugins), so plugin updates never take effect, with no visible symptom. Offer to remove matching local agents.
- **Skills and commands (shadowing/duplication):** directories in `~/.claude/skills/` and files in `~/.claude/commands/` matching plugin skill/command names. Same effect as agents. Offer removal.
- **Workflow scripts:** `~/.claude/workflows/review-mr.js`, `~/.claude/workflows/plan-builder.js`, `~/.claude/workflows/execute-runner.js`, or `~/.claude/workflows/ship-runner.js` duplicating the plugin's bundled copy.
- **Rules (duplication with injection):** files in `~/.claude/rules/` matching plugin rule names (testing, security, error-handling, database, performance, writing, frontend, prose) or carrying `source: toolkit@shaughn-toolkit` frontmatter. The plugin now injects these rules live at session start, so local copies mean the content lands twice. Offer removal; the user's own unrelated rules are never touched.

Before offering ANY removal, diff each local copy against the plugin's version (`diff -q`, then summarize real differences). If a local copy differs, say so plainly and show what differs — the user may have customized it, and that customization must be a conscious keep-or-discard decision, never collateral damage. Identical copies can be described as safe to remove.

Present all findings as one table (component, local path, effect, identical-or-modified), then ask ONE question: remove the identical ones now? Modified ones are individual decisions. Removal of hook registrations must leave `~/.claude/settings.json` valid JSON (mind trailing commas when deleting the last entry of an object).

### 8. Worker models and effort (per-agent routing, optional)

Run `bash <plugin-root>/scripts/resolve-models.sh` and read `~/.claude/toolkit-models.json`. If `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set in the environment, report first that it overrides every agent's model, including this config. Report the Claude Code version from `claude --version` against Claude Code 2.1.312, the version the toolkit's `effort` routing was tested on. The hook adds `effort` to Agent-tool spawns, and whether an older Agent tool accepts that field is untested, so on an older version say so and suggest an update.

- Missing: every agent runs on the template defaults (`scripts/toolkit-models.json.template` at the plugin root), which the resolver output shows. Print the effective table (agent, model, effort). Ask which agents to re-route, to which model and effort, and offer to write a user file holding only those agents as `{"model": ..., "effort": ...}` objects; apply only on an explicit yes. Never copy the template whole, because a full copy pins every agent and later template defaults never reach this machine.
- Present: validate it parses as JSON with an `agents` object. Flag any key that is not a shipped agent name (likely a typo; the resolver drops it with a warning), any value that is neither a string nor an object whose only keys are `model` and `effort`, each optional and holding a string, and any value containing `haiku` (refused by the model policy, so the resolver ignores it with a warning). Print the effective table (agent, model, effort) from the resolver output and list the user-file keys that override the template. The table shows no plan layer. A plan note's `worker_model`, `verifier_model` and `verifier_effort` reach the implementer and verifier through the session's run options cache, which a flow writes, so after a flow in this session an Agent-tool spawn of either agent can differ from the table. Never rewrite the file; offer fixes only.

The resolver output routes both spawn paths: the `agent-model.sh` hook on Agent-tool spawns and the `models` arg of the workflow runner scripts. Copying an agent under `~/.claude/agents/` is not needed for a model change, and doing so would freeze that agent's future updates instead.

### 9. Review bot logins (ship flow on GitLab, optional)

GitLab's note author carries no bot flag, so the ship flow counts a GitLab thread as a bot thread only when the host lists its author. The file is `~/.claude/toolkit-review-bots.json`, one array of logins per GitLab host. The ship flow looks an entry up by the host name in a repo's `origin` remote URL, after any user part and before any `:<port>`, so key each entry by that name. It matches the glab host from check 3 unless the remote uses an SSH config alias, and then the alias is the key:

    {
      "gitlab.example.com": ["review-bot"]
    }

- No authenticated GitLab host in check 3: report `no GitLab host` and ask nothing.
- Otherwise, missing, or a GitLab host from check 3 has no entry: say that the ship flow treats every review thread on that host as a human thread and refuses the merge while one is open. Ask for the login each review bot posts as on that host, which is the author username on any note the bot left on an MR. Show the full file and write it only on an explicit yes, merged into any existing object.
- Present: check that it parses as a JSON object whose values are arrays of logins matching `^[A-Za-z0-9][A-Za-z0-9._-]*(\[bot\])?$`. Flag any other entry, because the ship flow drops it.

## Readiness report

End with a table:

| Capability | Status | Needs |
|---|---|---|
| Agents (13) | always ready | — |
| Review capability (reviewer agents, testing-gate skill) | always ready | — |
| gitlab-mr-review | ready / not ready | glab auth |
| jira skill (ticket to brief) | ready / not ready | jira-cli + JIRA_API_TOKEN |
| Planning workflow (plan-guide, obsidian-topic) | ready / not ready | vault config |
| Write-time rules | main: always ready (session start); subagents: configured / offered / declined | subagents only: check 6 |
| Prompt-free scripts + orchestration env | configured / offered / declined | check 6 |
| Auto-update | on / offered / declined | check 6 |
| Auto mode git rules + trusted repos | not auto / configured / offered / declined | check 6 |
| Local conflicts | none / N found | migration (check 7) |
| Worker model routing | default (template) / configured / needs fix | check 8 |
| Ship flow bot threads on GitLab | configured / not configured / no GitLab host | check 9 |

One line of verdict at the end: fully ready, or the single next action to get there.

## Rules

- Never print secrets or token values.
- Do not create or modify any file without the user's explicit yes in this session.
- Do not modify the plugin's own files under any circumstances.
