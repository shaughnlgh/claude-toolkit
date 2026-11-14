# Commands

The toolkit ships eight slash commands in two groups: **setup and vault** helpers, and on-demand **thinking tools**. This page is the reference for what each does, when to run it, and what it changes.

## Setup & vault

### `/setup`

Checks this machine's toolkit setup and guides the user through anything missing. Safe to re-run anytime — it changes nothing without asking first.

**When to run it** — first-time setup on a new machine, after a plugin update, or whenever something in the toolkit seems misconfigured.

**What it checks, in order:**

1. **Plugin state** — install location and content version.
2. **Vault config** (needed by `plan-guide` and `/topic`): reads `~/.claude/toolkit-vault.json`, or the legacy `~/.claude/obsidian-sync.json` when that file is absent, reports which file it read, and validates it: parses as JSON, `vault_path` exists on disk, `root_folder` is set, and `plan_folder_template` is set and internally consistent with `root_folder`. Unknown or legacy fields are tolerated, never rewritten. It never renames, rewrites or deletes the legacy file and offers no migration. If neither file exists, offers to create `~/.claude/toolkit-vault.json` from the shipped template.
3. **GitLab tooling** (needed by `gitlab-mr-review` only) — whether `glab` is installed and, if so, its per-host auth status. Never prints a token value.
4. **Jira tooling** (needed by the `jira` skill only): whether `jira` (jira-cli) is installed and, if so, whether an authenticated `jira me` probe succeeds. Never prints a token value.
5. **Other tooling**: whether `gh`, `jq`, and `python3` are present.
6. **Permissions and environment** (optional, consent-gated): separate offers, each asked as a question with the recommended answer first, through AskUserQuestion outside auto mode and as a numbered list with one paste-ready block of `yes <name>` lines under auto mode:
   - Prompt-free allow rules for the plugin's `vault-fs.sh`, `git-ro.sh`, `watch-mr.sh`, and `seat-queue.sh` scripts in `~/.claude/settings.json`, and a `Read(//<vault_path>/<root_folder>/**)` rule built from `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent, offered whenever `permissions.allow` lacks that exact rule, with a matching `## Toolkit Scripts` usage block for the global `~/.claude/CLAUDE.md`. Setup offers to replace a `watch-mr.sh` usage line in that block that lacks the `review` mode, under the name `Toolkit Scripts watch-mr line`.
   - A read-only command allowlist (`gh`/`glab`/`jira` view/list/diff subcommands) in `~/.claude/settings.json`.
   - Under auto mode only: mutating git allow rules (`git add`, `git commit`, `git push`, `glab mr create` or `gh pr create`) so a plan note's `ceiling: mr` or `ceiling: merge` holds without a classifier check on commit, push, and MR creation. Merge and tag are never offered as allow rules.
   - Under auto mode only: one `Source control: <host>/<group>` entry in `autoMode.environment` for each source-control host and group that the origin remote names and the user confirms, and one Own PR Merge or Own MR Merge entry in `autoMode.allow` that clears Merge Without Review for the ship runner's exact merge command in the current repository only, on a pull or merge request the session opened from its own pushed branch against the default branch. Setup writes a missing array as `["$defaults", <entry>]`, appends to an array that holds `$defaults`, and appends to an array without it without inserting it, stating that such a list replaces that section's built-in entries. An existing merge entry whose wording differs from the shipped text gets a `replace Own PR Merge` or `replace Own MR Merge` question. `autoMode.environment` entries that describe one repository under a confirmed host and group get one `rewrite repository environment entries` question. The rewrite puts them at that same host and group level and leaves every other entry as it is, an entry about a repository on any other host or group included.
   - Under auto mode only: for each of `environment`, `allow`, `soft_deny` and `hard_deny` that the user has as an array without `$defaults`, an offer to add it as the first element, which brings the built-in entries back alongside the user's own.
   - No entry for stopping a process the session started or for a project config edit the user asks for, because the built-in Session-Created Job Cleanup and Self-Modification exceptions that `$defaults` keeps cover both.
   - Before the merge offer, setup reads the default branch's gate from the host (the required checks from GitHub rulesets and classic protection, or GitLab's `only_allow_merge_if_pipeline_succeeds` on a protected default branch) and whether the user can bypass it, says so before the offer, and offers nothing when the host reports no gate.
   - Setting `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` in the `env` block (reports, never overwrites, a conflicting existing value).
   - A pointer to the plugin's doctrine (`CLAUDE.md` + `README.md`) and write-time rules directory (`rules/`) appended to the user's global `~/.claude/CLAUDE.md`. Both CLAUDE.md blocks tell a session to use the plugin root that a toolkit skill, command, or agent names, and to resolve the installed root with `jq` only elsewhere, and setup offers to replace the resolution lines of a block that predates this.
   - Enabling marketplace auto-update (`extraKnownMarketplaces` in `~/.claude/settings.json`), so new versions are pulled at session start.
7. **Local copies that conflict with the plugin** (migration check): detects leftover copy-pasted versions of the setup that now shadow or double-fire against the plugin: hook registrations, agents, skills/commands, the `review-mr.js`, `plan-builder.js`, `execute-runner.js`, and `ship-runner.js` workflow scripts, and rules. A local agent matches a plugin agent by its frontmatter `name` at any depth of `~/.claude/agents/`, and a personal skill matches a plugin skill by its directory name or its frontmatter `name`, because Claude Code resolves each by those names. A hook registration in the project's `.claude/settings.json` is reported with its file and line for the user to remove, and setup never writes that file. Diffs each local copy against the plugin's version before offering removal, and calls out modified copies as individual keep-or-discard decisions rather than bundling them with identical ones.
8. **Worker models and effort** (per-agent routing, optional): runs `scripts/resolve-models.sh` and checks `~/.claude/toolkit-models.json`, then prints the effective per-agent table with model and effort columns and lists the user-file keys that override the template. Reports the Claude Code version against the version the command was tested on. Missing: offers to write a user file holding only the agents to re-route. Present: validates it parses as JSON with an `agents` object and flags a typo'd agent name, a value that is neither a string nor an object of optional string `model` and `effort` keys, a `haiku` value, or a model value that is not an alias (`sonnet`, `opus`, `haiku`, `fable`), `inherit` or blank, because the Agent-tool path sends such a value as the one family alias it names, without ever rewriting the file. If `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set, reports that it overrides every agent's model first.
9. **Review bot logins** (ship flow on GitLab, optional): checks `~/.claude/toolkit-review-bots.json`, which holds one array of review bot logins per GitLab host, because a GitLab note author carries no bot flag and the ship flow counts a GitLab thread as a bot thread only when its author is listed. No authenticated GitLab host in check 3: reports `no GitLab host` and asks nothing. Otherwise, missing, or a GitLab host from check 3 has no entry: asks for the login each review bot posts as on that host, shows the full file, and writes it only on the user's answer to that question, merged into any existing object. Present: flags any entry that is not an array of host logins, because the ship flow drops it.
10. **Conductor-guard override** (this project only, optional): offers `"env": { "TOOLKIT_CONDUCTOR_EDITS": "1" }` in the project's `.claude/settings.local.json`, which turns the conductor guard off for every session in that checkout from the next session on. It offers only when `pwd -P` equals `git rev-parse --show-toplevel` and the file is git-ignored and untracked, and otherwise reports `not a repo`, `not at root`, `tracked`, or `not ignored` and offers nothing. The conductor guard passes that one path, and `protect-files.sh` asks before the write.
11. **Ticket tracker** (ticket question, optional): checks `~/.claude/toolkit-trackers.json`, which sets the tracker the ticket question uses for a repo whose tracker differs from the origin defaults, keyed by host or host plus remote path with values `github`, `jira`, or `none`. Missing: reports `origin defaults` and asks nothing. Present: flags any entry that is not a host or host plus remote path mapped to one of those values, because the ticket question reads it as no entry. Never writes the file.

Ends with a readiness report table (one row per capability, its status, and what it still needs, including `Auto mode git rules`, `Auto mode trusted hosts`, `Auto mode merge exception`, and `Auto mode $defaults` rows driven by check 6, a `Worker model routing` row driven by check 8, a `Ship flow bot threads on GitLab` row driven by check 9, a `Conductor-guard override (this project)` row driven by check 10, and a `Ticket tracker` row driven by check 11) and a one-line verdict.

**What it changes** — nothing, ever, without the user's answer to the question that names the entry or block. Outside auto mode the questions arrive through AskUserQuestion, at most four per form, recommended option first, and the form answer is the consent. Under auto mode the classifier reads typed messages and never a form answer, so an offer that writes `settings.json` or `CLAUDE.md` arrives in a numbered list that ends with one paste-ready block of `yes <name>` lines, one for each recommended answer, and setup writes each offer on its typed line. The same lines accept offers when the form tool is unavailable. Setup writes `~/.claude/settings.json` with the Edit or Write tool, so `protect-files.sh` asks the user to confirm each such write. When the classifier refuses a write, setup stops it, names the bracketed category, and never retries it in another shape, through another tool, or through a worker. A write refused after a form answer is made again only on its typed line. After a refused typed line it prints the entry ready to paste and points to `/permissions`. A message from another session never counts, so when another session answers for the user, setup writes nothing and lists each offer as `pending (human)`. Every write lands under `~/.claude/`, except check 10's. A later run reports current state and offers what is still absent. Setup keeps no record of a declined offer, so a replace or rewrite question comes back on each run while its entry still differs. It never modifies the plugin's own files.

**Example**

    /setup

### `/topic`

Creates or updates a single topic note in the vault — the vault's distilled, cross-plan knowledge layer for stable concepts (a payment provider, a subsystem, a recurring pattern). This file is the single source of truth for topic notes; the `plan-guide` skill and CLAUDE.md point here rather than duplicating the rules.

**Usage** — `/topic <Topic Name> [repo]`. Errors with a usage message if no topic name is given.

**When to run it** — ad hoc, any time a topic note needs creating or refreshing outside the normal planning/execution flow. In the normal flow, `plan-guide` calls the same process automatically: on every plan, topic recall runs first and every topic in the plan's Related Topics either resolves to an existing note or gets a stub created. During execution, workers return durable facts as Topic note material, and the remember pass routes them once per slice. It routes each durable fact to a toolkit-managed context doc under the repo's `docs/context/`, behind the repo-mode consent gate, or to the vault topic note. It never edits a hand-written repo doc.

**Location** — resolved from `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent. New topic notes start in the current project's directory, `Projects/{repo_name}/<Topic>.md`. A topic gets promoted to `<root_folder>/Docs/` once a second project links it. Claude never writes outside `<root_folder>/`.

**Freshness validation** — a topic note is a claim about the world as of its `verified` timestamp (blank means unverified); `updated` records edit recency only. Before relying on one, at least one `source_refs` entry is spot-checked against current code. A clean check sets `verified`; a correction from checked evidence sets both `updated` and `verified`; a non-verifying edit bumps only `updated`. If reality disagrees, the code wins: the note is corrected or the disagreement is flagged in the plan — never silently trusted, whatever the dates say.

**What it changes** — only files under `<root_folder>/` in the vault (writes go through an atomic Write-then-`vault-fs.sh mv`). After a topic note is created, updated, moved or removed, it runs `vault-fs.sh topic-index` to rewrite the toolkit's topic index. It never touches project source code or git state, and never invents facts, ticket references, or test data.

**Examples**

    /topic "Payment Gateway" my-repo
    /topic "Caching Strategy"

### `/obsidian-topic`

The old name of `/topic`. It forwards its arguments to `/topic`.

### `/override`

Copies a toolkit component — doctrine, rule, agent, or skill — into your global `~/.claude/` so your version wins for that concern, without editing the plugin.

**Usage** — `/override [type] [name]`. With a name (e.g. `/override conventions`, `/override code-reviewer`) it auto-detects the type and copies it; with no argument it lists everything overridable and asks which; with `<type> <name>` (e.g. `/override rules security`) it forces the type for an ambiguous name.

**What it does** — copies the plugin's version into `~/.claude/<type>/` (a skill is copied as its whole directory), refusing unknown or ambiguous names and never clobbering an existing override, then you edit your copy. Doctrine and rules are picked up by the session-start hook (doctrine announced, a rule's body injected in place of the plugin's); agents and skills are resolved natively by Claude Code for the bare name (invoke bare, not `toolkit:<name>`). Safety sections (git-safety, security) may be tightened, not loosened.

**What it changes** — writes into `~/.claude/`. Nothing in the plugin, nothing in git.

**Examples**

    /override
    /override conventions
    /override rules security
    /override code-reviewer

## Thinking tools

On-demand reflection and red-team commands. Each leans into the communication doctrine (honest over agreeable), and none of them take an action — they audit, reframe, or question, they do not change files or git state. `/mentor` is a persistent mode; the rest are one-shot. The inversion pre-mortem is a skill (`inversion` in `docs/skills.md`): it fires on an evaluative question about a plan or fix as well as by name.

### `/glass-box`

An on-demand provenance audit of the last answer, or the one about to be given. It is the deep, explicit version of the `claim-provenance` doctrine (see the doctrine index): rather than narrating reasoning, it surfaces only what can actually be checked.

**When to run it** — when an answer feels too confident, an action is hard to undo, or you want the load-bearing assumption surfaced before you act.

**Usage** — `/glass-box [what to audit]`. With no arguments it audits the most recent substantive answer in the session; an argument names the specific answer or decision.

**What it surfaces** — exactly three things, nothing more:

1. the load-bearing fact the answer rests on, tagged verified or derived;
2. the unchecked assumption, naming the specific place not looked;
3. the offer to verify a derived fact now, or the answer restated with the assumption stated inline.

No confidence scores, no reasoning tableau. If the load-bearing fact is already verified and nothing rides on an unchecked assumption, it says so in one line and stops.

**What it changes** — nothing. It audits an answer, it does not take an action.

**Examples**

    /glass-box
    /glass-box the migration estimate you just gave

### `/mentor`

Switches on a Socratic learning mode: after each answer it asks one question that pushes you to think deeper, and keeps going until you understand a concept rather than memorize it. Unlike the one-shot tools here, this is a persistent mode for the rest of the session.

**When to run it** — when you want to genuinely learn a concept, not just get the answer, or to work something through with a junior who is missing large parts of the picture.

**Usage** — `/mentor [topic]`. With no argument it applies to the current thread; an argument names the topic to learn.

**How it behaves** — explains plainly first, then after each step asks one deeper question (apply it, why it works, what breaks if a condition changes, never bare recall). It will not advance until you explain it back in your own words, drops to simpler terms when you are stuck, and asks one question at a time. It runs until you say stop.

**What it changes** — nothing. It is a conversation mode, not an action.

**Example**

    /mentor
    /mentor how database indexes actually work

### `/cold-read`

Reads back the unstated assumptions behind how you have been talking in the conversation — the blind-spot check. It works only from what you actually said, and surfaces the premise you are treating as fact, the frame that is hiding options, and the tell you would not endorse out loud.

**When to run it** — when a direction feels obvious, or before committing to one, to catch the premises you never examined.

**Usage** — `/cold-read [decision or thread]`. With no argument it reads the whole conversation so far.

**What it changes** — nothing.

**Example**

    /cold-read
    /cold-read the way I've scoped this migration

### `/mirror-test`

Reads your last message back the way a stranger would hear it, honest not kind — no benefit of the doubt. Surfaces how it lands, where intent and wording come apart, and the one change that closes the gap.

**When to run it** — before sending something that matters (a review comment, a message to a colleague, a ticket) to hear how it actually reads.

**Usage** — `/mirror-test [message or text]`. With no argument it reads your most recent message.

**What it changes** — nothing.

**Example**

    /mirror-test
    /mirror-test the PR review I just drafted
