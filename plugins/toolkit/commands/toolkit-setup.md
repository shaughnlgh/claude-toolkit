---
description: Check this machine's toolkit setup and walk through anything missing — safe to re-run, changes nothing without asking
---

# Toolkit Setup

Check this machine's toolkit setup and guide the user through anything missing.
Safe to re-run anytime; it changes nothing without asking first.

## Usage

$ARGUMENTS

No arguments. Run the checks below in order, then print the readiness report.

## Checks

### 1. Plugin state

Report the toolkit's install location (this command's base directory) and content
version (the version segment in the base directory path, or `git -C` describe if
available; otherwise "unknown").

### 2. Vault config (needed by plan-workflow and obsidian-topic only)

Check `~/.claude/obsidian-sync.json`:

- Missing entirely: tell the user the planning workflow is unconfigured. Offer to
  create the config from (the shipped template `scripts/obsidian-sync.json.template`
  at the plugin root). If they accept: ask for their vault
  path, verify that directory exists on disk, write the config with their values,
  then re-run this check.
- Present: validate it —
  - parses as JSON,
  - `vault_path` points at a directory that exists,
  - `root_folder` is set,
  - internal consistency: `plan_folder_template` is set and starts with
    `root_folder`. A mismatched template is a common hand-edit error; report the
    disagreement and offer the fix.
  - Tolerate unknown or legacy fields (a live config may carry extra fields for
    external consumers). Never rewrite or "clean" an existing config.
- Note: `<root_folder>/Projects/` does not need to pre-exist; it is created on
  first plan write.

### 3. GitLab tooling (needed by gitlab-mr-review only)

- `glab` installed? If yes, run `glab auth status` and report per-host state.
  NEVER print a token value, even partially. If unauthenticated, tell the user:
  `glab auth login`.

### 4. Jira tooling (needed by the jira skill only)

- `jira` (jira-cli) installed? If yes, run `jira me >/dev/null` and report whether the
  authenticated probe succeeds. NEVER print a token value, even partially. If it fails,
  tell the user: `brew install jira-cli` if missing, then `jira init` (one-time), and
  ensure `JIRA_API_TOKEN` is exported from the user's shell rc file (`~/.zshrc`, `~/.bashrc`, or equivalent).

### 5. Other tooling

- `gh` present? (Optional; the SSH-based install path and read-only GitHub checks use it.)
- `jq` present? (Optional; some scripts prefer it and degrade without it.)
- `python3` present? (Required by the planning workflow's scripts.)

### 6. Permissions and environment (optional, consent-gated)

Three optional additions, shown verbatim, explained in one line, and applied only on an
explicit yes. They span the user's `~/.claude/settings.json` (merge into the existing
`permissions.allow` / `env` objects, never replacing them, always leaving valid JSON)
and the global `~/.claude/CLAUDE.md`.

- **Prompt-free toolkit scripts.** The plugin's vault and git scripts are invoked by
  its skills from the plugin cache. Offer these allow rules, written with the user's
  absolute home path (mid-path wildcards are supported and make the rules survive
  plugin updates):

      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/vault-fs.sh *)
      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/git-ro.sh *)

  Explain the trade honestly: without them, the first vault write per repo prompts
  once ("always allow" works but embeds the version hash, so it re-prompts after
  updates). Both scripts are guard-railed (relative-path-only vault ops; read-only
  git) and reviewable in the plugin. When the rules are accepted, ALSO offer to
  append this usage block to the user's global `~/.claude/CLAUDE.md` (they are one
  unit — the rules only match invocations written this way):

      ## Toolkit Scripts
      Invoke via the CURRENT installed plugin root: resolve it first, e.g.
      `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json`,
      then invoke with that literal absolute path (matches the allowlist rule).
      - `bash <plugin-root>/scripts/vault-fs.sh rm|mv ...` - vault file ops with
        guardrails; atomic writes: Write tool to a `.tmp` file, then vault-fs.sh mv.
        Vault root resolves from `~/.claude/obsidian-sync.json`.
      - `bash <plugin-root>/scripts/git-ro.sh <dir> <status|diff|log|show>` -
        read-only git anywhere; mutation subcommands refused.
- **Read-only command allowlist.** The workflows lean on read-only `gh`/`glab`/`jira` calls
  that otherwise prompt on every new machine. Offer these `permissions.allow` rules
  (all inherently read-only subcommands — never offer mutating ones like `gh api -X`,
  `gh pr merge`, or `glab mr merge`, which must keep prompting):

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

  Skip any rule already present. Mention that `/fewer-permission-prompts` extends the
  allowlist from this machine's actual usage history when prompt fatigue persists.

- **Orchestration environment.** The toolkit's orchestration doctrine routes every
  worker question or blocker to the conductor; the built-in advisor tool is a
  side-channel around that. Offer:

      "env": { "CLAUDE_CODE_DISABLE_ADVISOR_TOOL": "1" }

  If the key is already set to "1", report it as current. If set to something else,
  report the conflict and let the user decide — do not overwrite silently.

- **Doctrine pointer.** The toolkit's working doctrine ships at the plugin root
  (`CLAUDE.md` index + `doctrine/` files + design `README.md`), but sessions and
  especially subagents only find it via the user's global `~/.claude/CLAUDE.md`.
  Check that file contains a pointer to the plugin's CLAUDE.md and README.md. If
  absent, offer to append this block (or create a minimal global CLAUDE.md holding
  just it, if none exists):

      ## Toolkit Doctrine
      The binding doctrine lives in the toolkit plugin — read its index at
      ~/.claude/plugins/cache/shaughn-toolkit/toolkit/*/CLAUDE.md (glob resolves the
      current version). Design rationale: README.md at the same plugin root.
      Personal overrides: state one inline below, or drop a same-named file in
      ~/.claude/doctrine/ (auto-detected each session, no pointer needed).

Do not offer to pre-create override directories — `/override` creates whatever it
needs when a doctrine, rule, agent, or skill override is actually made, and an empty
directory has no effect. In the readiness report, mention once that overrides for
all four types are available via `/override` (see `docs/overrides.md`; safety
sections may be tightened, not loosened).

If any offer is declined, note the practical effects (occasional permission prompts;
advisor available to workers; doctrine unreachable by subagents) and move on. Never
re-nag on later runs: report current state, offer only what is absent.

### 7. Local copies that conflict with the plugin (migration check)

If this machine previously ran a copy-pasted version of this setup, local copies now
conflict with the plugin. Detect each class and explain its exact effect:

- **Hooks (double-fire):** in `~/.claude/settings.json` (and the project's
  `.claude/settings.json` if present), find hook registrations whose script names match
  plugin-shipped hooks (session-start, notify, protect-files, scan-secrets,
  block-dangerous-commands). Effect: both copies run on every event. Offer to remove
  the local registrations, and afterwards the `~/.claude/hooks/` scripts they point at.
- **Agents (silent shadowing):** files in `~/.claude/agents/` whose names match plugin
  agents. Effect: the LOCAL copy wins (user scope outranks plugins), so plugin updates
  never take effect, with no visible symptom. Offer to remove matching local agents.
- **Skills and commands (shadowing/duplication):** directories in `~/.claude/skills/`
  and files in `~/.claude/commands/` matching plugin skill/command names. Same effect
  as agents. Offer removal.
- **Workflow scripts:** `~/.claude/workflows/review-mr.js` duplicating the plugin's
  bundled copy.
- **Rules (duplication with injection):** files in `~/.claude/rules/` matching plugin
  rule names (testing, security, error-handling, database, performance, frontend) or carrying
  `source: toolkit@shaughn-toolkit` frontmatter. The plugin now injects these rules
  live at session start, so local copies mean the content lands twice. Offer removal;
  the user's own unrelated rules are never touched.

Before offering ANY removal, diff each local copy against the plugin's version
(`diff -q`, then summarize real differences). If a local copy differs, say so plainly
and show what differs — the user may have customized it, and that customization must
be a conscious keep-or-discard decision, never collateral damage. Identical copies can
be described as safe to remove.

Present all findings as one table (component, local path, effect, identical-or-modified),
then ask ONE question: remove the identical ones now? Modified ones are individual
decisions. Removal of hook registrations must leave `~/.claude/settings.json` valid
JSON (mind trailing commas when deleting the last entry of an object).

## Readiness report

End with a table:

| Capability | Status | Needs |
|---|---|---|
| Agents (13) | always ready | — |
| Review capability (reviewer agents, testing-gate skill) | always ready | — |
| gitlab-mr-review | ready / not ready | glab auth |
| jira skill (ticket to brief) | ready / not ready | jira-cli + JIRA_API_TOKEN |
| Planning workflow (plan-workflow, obsidian-topic) | ready / not ready | vault config |
| Write-time rules | injected at session start | — |
| Prompt-free scripts + orchestration env | configured / offered / declined | check 6 |
| Local conflicts | none / N found | migration (check 7) |

One line of verdict at the end: fully ready, or the single next action to get there.

## Rules

- Never print secrets or token values.
- Do not create or modify any file without the user's explicit yes in this session.
- Do not modify the plugin's own files under any circumstances.
