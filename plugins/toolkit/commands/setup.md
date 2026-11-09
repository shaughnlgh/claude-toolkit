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

Report the toolkit's install location, `${CLAUDE_PLUGIN_ROOT}`, and its content version: `git -C <root> describe --always --dirty` when the root sits in a git checkout, as under `claude --plugin-dir`, else the last path segment of the root when it sits under `~/.claude/plugins/cache/`, otherwise "unknown".

### 2. Vault config (needed by plan-guide and obsidian-topic only)

Check `~/.claude/obsidian-sync.json`:

- Missing entirely: tell the user the planning workflow is unconfigured. Offer to create the config from the shipped template `${CLAUDE_PLUGIN_ROOT}/scripts/obsidian-sync.json.template`. If they accept: ask for their vault path, verify that directory exists on disk, write the config with their values, then re-run this check.
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

Optional additions, each shown verbatim, explained in one line, and applied only on the typed reply the Rules section describes. They write `permissions.allow`, `env`, `extraKnownMarketplaces`, `autoMode.environment` and `autoMode.allow` in the user's `~/.claude/settings.json`, `autoMode.soft_deny` and `autoMode.hard_deny` there only to add `"$defaults"`, and the global `~/.claude/CLAUDE.md`. Merge into the existing objects and arrays, never replace them, and always leave valid JSON.

- **Prompt-free toolkit scripts.** The plugin's vault, git, and MR-watch scripts are invoked by its skills from the plugin cache. Offer these allow rules, written with the user's absolute home path (mid-path wildcards are supported and make the rules survive plugin updates):

      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/vault-fs.sh *)
      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/git-ro.sh *)
      Bash(bash <home>/.claude/plugins/cache/shaughn-toolkit/toolkit/*/scripts/watch-mr.sh *)

  Explain the trade honestly: without them, the first vault write per repo prompts once and the ship flow's background watcher prompts before it starts ("always allow" works but embeds the version hash, so it re-prompts after updates). The vault and git scripts are guard-railed (relative-path-only vault ops; read-only git) and reviewable in the plugin. `watch-mr.sh` only reads an MR or PR through `gh` or `glab` and exits with a status, so the ship flow can wait on a pipeline in the background without a prompt. When the rules are accepted, ALSO offer to append this usage block to the user's global `~/.claude/CLAUDE.md` (they are one unit, because the rules only match invocations written this way):

      ## Toolkit Scripts
      Inside a toolkit skill, command, or agent, use the plugin root it names.
      Elsewhere, resolve the installed root first, e.g.
      `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json`,
      then invoke with that literal absolute path (matches the allowlist rule).
      - `bash <plugin-root>/scripts/vault-fs.sh rm|mv ...` - vault file ops with
        guardrails; atomic writes: Write tool to a `.tmp.md` file beside the destination, then vault-fs.sh mv.
        Vault root resolves from `~/.claude/obsidian-sync.json`.
      - `bash <plugin-root>/scripts/git-ro.sh <dir> <status|diff|log|show>` -
        read-only git anywhere; mutation subcommands refused.
      - `bash <plugin-root>/scripts/watch-mr.sh <host> <remotePath> <number> pipeline|threads|review --sha <sha> [--bound <n>]` -
        waits on an MR or PR pipeline or bot review and exits with one status line. The ship flow starts it in the background.

  When the global CLAUDE.md already holds this block and the block lacks `use the plugin root it names`, show its resolution lines beside the new ones and offer to replace only those lines. Never write this command's own substituted plugin root into the block, because the user's file would then pin one version's path.
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

  Explain the trade: these rules let a plan note's `ceiling: mr` or `ceiling: merge` hold without a classifier check on every commit, push, and MR. Merge and tag are never offered, so the merge and the tag under `ceiling: merge` stay under the classifier and the `block-dangerous-commands` hook still guards protected branches. Skip when the mode is not `auto`, and skip any rule already present.

- **Auto mode `$defaults` (only when `permissions.defaultMode` is `auto` or the user says they switch to auto mode).** The classifier reads `autoMode` from `~/.claude/settings.json`, managed settings and `--settings` only, never from a project settings file. Each of its arrays `environment`, `allow`, `soft_deny` and `hard_deny` takes `"$defaults"`, which splices that section's built-in entries in at its position, and an array without it replaces that section's built-ins. Apply this rule to every autoMode write in this check:
  - Absent array: write `["$defaults", <entry>]` and say that `"$defaults"` keeps the built-in entries, Git Push Destination and Session-Created Job Cleanup among the allow exceptions, and their future updates.
  - Array with `"$defaults"`: append the entry.
  - Array without `"$defaults"`: append the entry without inserting `"$defaults"`, and say that the list replaces the built-ins for that section and that `claude auto-mode defaults` prints them.

  Never insert `"$defaults"` silently. For each of `environment`, `allow`, `soft_deny` and `hard_deny` that the user has as an array without `"$defaults"`, offer the insert as its own entry: name the array, show `"$defaults"` as its new first element, say in one sentence that the built-in entries come back alongside the user's own, and end with `Reply "yes $defaults <section>" to add it.`, for example `Reply "yes $defaults environment" to add it.` After any autoMode write, run `claude auto-mode config` and confirm that each new entry appears. Mention `claude auto-mode critique` as an optional review that makes a model call.

- **Auto mode trusted hosts (same condition).** The classifier treats a remote it cannot place as a foreign system. Read the host and path from `git remote get-url origin` the way check 9 reads the host, and take the group as the path without its last segment. Add any other host from check 3 or `gh auth status` that the user names. Ask the user to confirm or correct each host and group, because an SSH config alias is not the host. For each host with no `autoMode.environment` entry naming it, show and offer:

      Source control: <host>/<group> and every repository under it belong to the user. Commit, push, branch creation, and MR or PR creation there are routine work, not writes to a foreign system.

  End the offer with `Reply "yes Source control <host>/<group>" to add it.` and write it under the `$defaults` rule. For a full environment draft, point to `/auto-mode-setup`, and say that its draft writes the list without `"$defaults"`.

- **Auto mode merge exception (same condition).** Offer it only inside a repository whose origin is on github.com or on a GitLab host from check 3, and only after the merge gate read below finds a gate. Show the entry for the host, filled with the repository's host and path, write it under the `$defaults` rule, and end with `Reply "yes Own PR Merge" to add it.` or `Reply "yes Own MR Merge" to add it.`

      Own PR Merge: Merging a pull request on <host>/<owner>/<repo> with gh pr merge <number> --merge --match-head-commit <sha> is allowed when this session opened the pull request from a branch it pushed to that repository and its base is the default branch <default>. This clears Merge Without Review for that repository only. The user named the repository as their own, its default branch requires status checks, and gh pr merge without --admin refuses a pull request that GitHub reports blocked, so this command merges only after the required checks pass. It does not cover a pull request from a fork, by another author, or to any other base, --admin, --auto, a merge through gh api or any other REST or GraphQL call, any other flag that bypasses review or checks, or any other repository.

      Own MR Merge: Merging a merge request on <host>/<path> with glab mr merge <number> --sha <sha> --auto-merge=false --yes is allowed when this session opened the merge request from a branch it pushed to that project and its target is the default branch <default>. This clears Merge Without Review for that repository only. The user named the repository as their own, and the host refuses a merge to <default> until the required pipeline passes. It does not cover a merge request from a fork, by another author, or to any other target, a merge through glab api or any other raw API call, any flag that bypasses review or the pipeline, or any other repository.

  State that an allow entry clears a soft rule only, and never Data Exfiltration or any other hard rule. State that setup offers no entry for stopping a process the session started or for a project config edit the user asks for, because the built-in Session-Created Job Cleanup and Self-Modification texts that `"$defaults"` keeps cover both, and point to the stop shape in the git-safety doctrine.

  Merge gate read. Before the merge offer, read the default branch's gate and the user's bypass from the host, and show what came back. Fill `<owner>/<repo>` from the origin path the entry names, never from gh's `{owner}/{repo}` placeholders, which gh fills from its base repository, an `upstream` remote first:

      # GitHub: the required checks are the union of the ruleset list and the classic list
      gh api 'repos/<owner>/<repo>' --jq '{default_branch, admin: .permissions.admin}'
      gh api 'repos/<owner>/<repo>/rules/branches/<default>' --jq '[.[] | select(.type == "required_status_checks") | {ruleset_id, checks: [.parameters.required_status_checks[].context]}]'
      gh api 'repos/<owner>/<repo>/rulesets/<ruleset_id>' --jq '.current_user_can_bypass'   # once per ruleset_id above
      gh api 'repos/<owner>/<repo>/branches/<default>' --jq 'if (.protection.required_status_checks.enforcement_level // "off") == "off" then [] else (.protection.required_status_checks.contexts // []) end'
      gh api 'repos/<owner>/<repo>/branches/<default>/protection/enforce_admins' --jq '.enabled'   # only when the classic list is not empty and admin is true
      # GitLab: read default_branch, only_allow_merge_if_pipeline_succeeds and allow_merge_on_skipped_pipeline, then confirm the default branch is protected (branch name URL-encoded)
      glab api projects/:id
      glab api 'projects/:id/protected_branches/<default>'

  Offer the entry only when the GitHub union names at least one check, or when the GitLab default branch is protected, `only_allow_merge_if_pipeline_succeeds` is true and `allow_merge_on_skipped_pipeline` is not true. Otherwise say which condition failed and offer nothing. If a gate read fails, show its error line and offer nothing. On GitHub the user can bypass when any listed ruleset returns a `current_user_can_bypass` other than `never`, or when the classic list is not empty, `admin` is true and `enforce_admins` is false. When the user can bypass, or a bypass read fails or lacks the field, say before the offer that the host does not refuse a merge by this user, and that the stop the entry rests on is `gh pr merge` refusing, without `--admin`, a pull request GitHub reports BLOCKED, as GitHub does for a bypass actor while a required check is pending.

  An existing `autoMode.allow` entry that names `<host>/<path>` and a merge counts as present. Show it beside the shipped text and the gate and bypass read, and point to `/permissions` to change its wording. When the read for that repository shows no required check, say that the entry rests on a gate the host does not enforce, and point to `/permissions` to remove it.

- **Orchestration environment.** The toolkit's orchestration doctrine routes every worker question or blocker to the conductor; the built-in advisor tool is a side-channel around that. Offer:

      "env": { "CLAUDE_CODE_DISABLE_ADVISOR_TOOL": "1" }

  If the key is already set to "1", report it as current. If set to something else, report the conflict and let the user decide — do not overwrite silently.

- **Doctrine and rules pointer.** The toolkit's working doctrine ships at the plugin root (`CLAUDE.md` index + `doctrine/` files + design `README.md`) and its write-time rules ship under `rules/`, but sessions and especially subagents only find either via the user's global `~/.claude/CLAUDE.md`. Check that file contains a pointer to the plugin's CLAUDE.md, README.md, and rules/ directory. If absent, offer to append this block (or create a minimal global CLAUDE.md holding just it, if none exists):

      ## Toolkit Doctrine
      The binding doctrine lives in the toolkit plugin.
      Inside a toolkit skill, command, or agent, use the plugin root it names.
      Elsewhere, resolve the installed root first, e.g.
      `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json`,
      then read the index at
      `<plugin-root>/CLAUDE.md`. Design rationale: `<plugin-root>/README.md`.
      Personal overrides: state one inline below, or drop a same-named file in
      ~/.claude/doctrine/ (auto-detected each session, no pointer needed).
      Write-time rules: before writing code, tests, queries, error handling, or
      documentation/comments, read the matching file under `<plugin-root>/rules/`
      (testing.md, security.md, error-handling.md, database.md, performance.md,
      writing.md, frontend.md, prose.md).

  When the global CLAUDE.md already holds this block and the block lacks `use the plugin root it names`, show its resolution lines beside the new ones and offer to replace only those lines. Never write this command's own substituted plugin root into the block, because the user's file would then pin one version's path.

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

- **Hooks (double-fire):** in `~/.claude/settings.json` (and the project's `.claude/settings.json` if present), find hook registrations whose script names match plugin-shipped hooks (session-start, notify, protect-files, scan-secrets, block-dangerous-commands). Effect: both copies run on every event. Offer to remove the registrations in `~/.claude/settings.json`, and afterwards the `~/.claude/hooks/` scripts they point at. Report a registration in the project's `.claude/settings.json` with its file and line for the user to remove, and never write that file.
- **Agents (silent shadowing):** agent files at any depth of `~/.claude/agents/` whose frontmatter `name` matches a plugin agent's, because Claude Code keys an agent by that name and never by its file name. Effect: the LOCAL copy wins (user scope outranks plugins), so plugin updates never take effect, with no visible symptom. The diff below pairs each one with the plugin agent of that name. Offer to remove matching local agents.
- **Skills and commands (shadowing/duplication):** a personal skill under `~/.claude/skills/` whose directory name or its frontmatter `name` equals a plugin skill's name, because Claude Code invokes a personal skill by both, and files in `~/.claude/commands/` whose file name matches a plugin command's, because Claude Code names a command file by its file name. Same effect as agents. Offer removal.
- **Workflow scripts:** `~/.claude/workflows/review-mr.js`, `~/.claude/workflows/plan-builder.js`, `~/.claude/workflows/execute-runner.js`, or `~/.claude/workflows/ship-runner.js` duplicating the plugin's bundled copy.
- **Rules (duplication with injection):** files in `~/.claude/rules/` matching plugin rule names (testing, security, error-handling, database, performance, writing, frontend, prose) or carrying `source: toolkit@shaughn-toolkit` frontmatter. The plugin now injects these rules live at session start, so local copies mean the content lands twice. Offer removal; the user's own unrelated rules are never touched.

Before offering ANY removal, diff each local copy against the plugin's version (`diff -q`, then summarize real differences). If a local copy differs, say so plainly and show what differs — the user may have customized it, and that customization must be a conscious keep-or-discard decision, never collateral damage. Identical copies can be described as safe to remove.

Present all findings as one table (component, local path, effect, identical-or-modified), then ask ONE question: remove the identical ones now? Modified ones are individual decisions. Removal of hook registrations must leave `~/.claude/settings.json` valid JSON (mind trailing commas when deleting the last entry of an object).

### 8. Worker models and effort (per-agent routing, optional)

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-models.sh"` and read `~/.claude/toolkit-models.json`. If `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set in the environment, report first that it overrides every agent's model, including this config. Report the Claude Code version from `claude --version` against Claude Code 2.1.312, the version the toolkit's `effort` routing was tested on. The hook adds `effort` to Agent-tool spawns, and whether an older Agent tool accepts that field is untested, so on an older version say so and suggest an update.

- Missing: every agent runs on the template defaults (`scripts/toolkit-models.json.template` at the plugin root), which the resolver output shows. Print the effective table (agent, model, effort). Ask which agents to re-route, to which model and effort, and offer to write a user file holding only those agents as `{"model": ..., "effort": ...}` objects, and end with `Reply "yes Worker models" to add it.` Never copy the template whole, because a full copy pins every agent and later template defaults never reach this machine.
- Present: validate it parses as JSON with an `agents` object. Flag any key that is not a shipped agent name (likely a typo; the resolver drops it with a warning), any value that is neither a string nor an object whose only keys are `model` and `effort`, each optional and holding a string, and any value containing `haiku` (refused by the model policy, so the resolver ignores it with a warning). Flag any model value that is not `sonnet`, `opus`, `haiku`, `fable`, `inherit` or blank. The workflow runners pass such a value unchanged, but the Agent tool takes only an alias, so the `agent-model.sh` hook sends the one family alias the value names, such as `opus` for `claude-opus-5-5[1m]`, or no model when it names none or several. Suggest the alias when the user wants both paths to match. Print the effective table (agent, model, effort) from the resolver output and list the user-file keys that override the template. The table shows no plan layer. A plan note's `worker_model`, `verifier_model` and `verifier_effort` reach the implementer and verifier through the session's run options cache, which a flow writes, so after a flow in this session an Agent-tool spawn of either agent can differ from the table. Never rewrite the file; offer fixes only.

The resolver output routes both spawn paths: the `agent-model.sh` hook on Agent-tool spawns and the `models` arg of the workflow runner scripts. Copying an agent under `~/.claude/agents/` is not needed for a model change, and doing so would freeze that agent's future updates instead.

### 9. Review bot logins (ship flow on GitLab, optional)

GitLab's note author carries no bot flag, so the ship flow counts a GitLab thread as a bot thread only when the host lists its author. The file is `~/.claude/toolkit-review-bots.json`, one array of logins per GitLab host. The ship flow looks an entry up by the host name in a repo's `origin` remote URL, after any user part and before any `:<port>`, so key each entry by that name. It matches the glab host from check 3 unless the remote uses an SSH config alias, and then the alias is the key:

    {
      "gitlab.example.com": ["review-bot"]
    }

- No authenticated GitLab host in check 3: report `no GitLab host` and ask nothing.
- Otherwise, missing, or a GitLab host from check 3 has no entry: say that the ship flow treats every review thread on that host as a human thread and refuses the merge while one is open. Ask for the login each review bot posts as on that host, which is the author username on any note the bot left on an MR. Show the full file, end with `Reply "yes Review bot logins" to add it.`, and on that reply write it merged into any existing object.
- Present: check that it parses as a JSON object whose values are arrays of logins matching `^[A-Za-z0-9][A-Za-z0-9._-]*(\[bot\])?$`. Flag any other entry, because the ship flow drops it.

### 10. Conductor-guard override (this project only, optional)

The conductor guard denies the main session's edits inside the project unless `TOOLKIT_CONDUCTOR_EDITS` is `1`. Run `git rev-parse --show-toplevel` and `pwd -P`, then report the first state that applies:

- `git rev-parse` fails: report `not a repo`.
- The top level differs from `pwd -P`: report `not at root`, say that check 10 runs only from the repository root, and offer nothing.
- `git ls-files --error-unmatch .claude/settings.local.json` succeeds: report `tracked`, say that the override would reach every clone, and offer nothing.
- `git check-ignore -q .claude/settings.local.json` fails: report `not ignored`, name `.git/info/exclude` or the global gitignore as the place to ignore the file, and offer nothing.
- `env.TOOLKIT_CONDUCTOR_EDITS` in that file is `"1"`: report `on`.
- It holds another value: report the conflict and leave it.
- Otherwise explain that with the override on, the main session edits this project's files itself in every session in this checkout, and the delegation rule binds only by doctrine, so the override suits a project the user edits beside the session. Show the entry and end with `Reply "yes conductor override" to add it.`

      "env": { "TOOLKIT_CONDUCTOR_EDITS": "1" }

On that reply, write the entry into the existing object of `<top level>/.claude/settings.local.json` with the Edit or Write tool, and create the file when it is absent. The conductor guard passes that one path, and `protect-files.sh` asks the user to confirm the write. The override takes effect from the next session.

### 11. Ticket tracker (ticket question, optional)

The ticket question in the `plan-guide` skill's Run options section picks a repo's tracker from its `origin` remote, and `~/.claude/toolkit-trackers.json` overrides that pick for a repo whose tracker differs. The skill's Ticket subsection defines the file: each key is a host, or a host plus the remote path without `.git`, read from the `origin` URL after any user part and without any `:<port>`, and each value is `github`, `jira`, or `none`. A host plus path entry wins over a host entry:

    {
      "gitlab.example.com/someone/side-project": "none"
    }

- Missing: report `origin defaults` and ask nothing. The ticket question then uses GitHub issues for a github.com origin, Jira for another host when the session's project rules name ticket key prefixes and jira-cli is configured, and no tracker otherwise.
- Present: check that it parses as a JSON object whose keys match `^[A-Za-z0-9.-]+(/[A-Za-z0-9._-]+)*$`, a host or a host plus remote path, and whose values are `github`, `jira`, or `none`. Flag any other entry and report `needs fix`, because the ticket question reads it as no entry. A file that does not parse also reports `needs fix`, because the ticket question then uses the origin defaults for every repo. Report `configured` when every entry passes.
- Never write or rewrite the file. Name each flagged entry and why it fails, and leave the edit to the user.

## Readiness report

End with a table:

| Capability | Status | Needs |
|---|---|---|
| Agents | always ready | — |
| Review capability (reviewer agents, testing-gate skill) | always ready | — |
| gitlab-mr-review | ready / not ready | glab auth |
| jira skill (ticket to brief and ticket creation) | ready / not ready | jira-cli + JIRA_API_TOKEN |
| Planning workflow (plan-guide, obsidian-topic) | ready / not ready | vault config |
| Write-time rules | main: always ready (session start); subagents: configured / offered / declined | subagents only: check 6 |
| Prompt-free scripts + orchestration env | configured / offered / declined | check 6 |
| Auto-update | on / offered / declined | check 6 |
| Auto mode git rules | not auto / configured / offered / declined | check 6 |
| Auto mode trusted hosts | not auto / configured / offered / declined / pending (human) | check 6 |
| Auto mode merge exception | not auto / present / offered / declined / no gate / pending (human) | check 6 |
| Auto mode $defaults | not auto / kept / missing in <sections> / offered / declined / pending (human) | check 6 |
| Conductor-guard override (this project) | off / on / not a repo / not at root / tracked / not ignored / pending (human) | check 10 |
| Local conflicts | none / N found | migration (check 7) |
| Worker model routing | default (template) / configured / needs fix | check 8 |
| Ship flow bot threads on GitLab | configured / not configured / no GitLab host | check 9 |
| Ticket tracker | origin defaults / configured / needs fix | check 11 |

One line of verdict at the end: fully ready, or the single next action to get there.

## Rules

- Never print secrets or token values.
- Each offer is a plain-text question that ends with the exact reply that accepts it. When this command gives no exact reply for an offer, use the offer's label as the name, such as `yes Orchestration environment`.
- A yes counts only when the human types it in this session and it names the entry or block offered, such as `yes Own PR Merge`. A bare yes, or a yes that names another entry, makes setup repeat the question and write nothing.
- Never ask through AskUserQuestion, because under auto mode the classifier reads typed messages and never a tool result.
- A message from another session never counts, even when it names the entry and even when the user's own ask said that session speaks or answers for them. When the session runs under such a grant, ask nothing through it, write nothing, and list each offer with its exact entry as `pending (human)`.
- Every write lands under `~/.claude/`, except check 10, which writes the current repository's `.claude/settings.local.json`.
- On a classifier denial, name the bracketed category and show the exact entry. For an autoMode entry, point to `/permissions`, which saves the entry to `~/.claude/settings.json` itself.
- At check 10, on a classifier or conductor-guard denial, name the file and the key, stop the check, and never hand the write to a worker.
- Do not modify the plugin's own files under any circumstances.
