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
  create the config from the shipped template (`../scripts/obsidian-sync.json.template`
  relative to this command's base directory). If they accept: ask for their vault
  path, verify that directory exists on disk, write the config with their values,
  then re-run this check.
- Present: validate it —
  - parses as JSON,
  - `vault_path` points at a directory that exists,
  - `root_folder` is set,
  - internal consistency: `plan_folder_template` and
    `project_discovery.target_folder_template` (when present) start with
    `root_folder`. Mismatched templates are a common hand-edit error; report the
    exact fields that disagree and offer the fix.
- Note: `<root_folder>/Projects/` does not need to pre-exist; it is created on
  first plan write.

### 3. GitLab tooling (needed by gitlab-mr-review only)

- `glab` installed? If yes, run `glab auth status` and report per-host state.
  NEVER print a token value, even partially. If unauthenticated, tell the user:
  `glab auth login`.

### 4. Optional tooling

- `jq` present? (Some scripts prefer it and degrade without it.)

### 5. Local copies that conflict with the plugin (migration check)

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
  rule names (testing, security, error-handling, database, frontend) or carrying
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
| Agents (12) | always ready | — |
| Review skills (code review, testing gate) | always ready | — |
| gitlab-mr-review | ready / not ready | glab auth |
| Planning workflow (plan-workflow, obsidian-topic) | ready / not ready | vault config |
| Write-time rules | injected at session start | — |
| Local conflicts | none / N found | migration (check 5) |

One line of verdict at the end: fully ready, or the single next action to get there.

## Rules

- Never print secrets or token values.
- Do not create or modify any file without the user's explicit yes in this session.
- Do not modify the plugin's own files under any circumstances.
