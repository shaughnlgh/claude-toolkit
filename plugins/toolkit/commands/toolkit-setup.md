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

## Readiness report

End with a table:

| Capability | Status | Needs |
|---|---|---|
| Agents (12) | always ready | — |
| Review skills (code review, testing gate) | always ready | — |
| gitlab-mr-review | ready / not ready | glab auth |
| Planning workflow (plan-workflow, obsidian-topic) | ready / not ready | vault config |

One line of verdict at the end: fully ready, or the single next action to get there.

## Rules

- Never print secrets or token values.
- Do not create or modify any file without the user's explicit yes in this session.
- Do not modify the plugin's own files under any circumstances.
