# Hooks

The toolkit ships twelve hook scripts that run automatically once the plugin is installed — no opt-in, no separate config. This page is the full accounting, in the spirit of transparency: exactly what each one checks, what it hard-blocks versus merely asks you to confirm, and every environment variable it honors. The README's Docs list links here in one line; this is the full version — the one to read before trusting the toolkit with a repo.

Two properties hold across all twelve:

- **Fails safe.** No hook can crash or hang your session. Where "safe" lands differs by hook: `protect-files.sh` and `block-dangerous-commands.sh` require `jq` to parse the tool call, so if `jq` is missing they hard-block that one write or command rather than let a security check that can't run pass silently. `scan-secrets.sh` degrades to a no-op without `jq` (it cannot parse the write, so it does not block). `notify.sh` always fires with its fixed message and only no-ops when no OS notifier is available. `session-start.sh` and `subagent-rules.sh` both fall back to plain-stdout context. `context-sentinel.sh` is a silent no-op without `jq` or a readable transcript, and never blocks anything regardless. `conductor-guard.sh` likewise fails open without `jq` and can only ever ask, never deny. Either way, the worst case is one blocked tool call or a slightly thinner context injection — never a broken session.
- **Reads no network** — with one narrow exception: `session-start.sh`'s verbose mode (`TOOLKIT_SESSION_VERBOSE=1`) calls `gh pr view` when the `gh` CLI is installed, which does reach GitHub's API for the current repo's PR status. Every other code path in every hook is local only: file reads, git plumbing, `jq`, and OS notification APIs.

## The set

| Script | Event | What it does |
|---|---|---|
| `protect-files.sh` | PreToolUse (`Edit\|Write`) | Hard-blocks `Edit`/`Write` calls to keys/certs/lockfiles/generated files, `.git/`, `secrets/`, and hook scripts; asks for confirmation on `.env*` and `.claude/settings*.json` |
| `scan-secrets.sh` | PreToolUse (`Edit\|Write`) | Asks for confirmation when written content looks like a credential — never a hard block |
| `block-dangerous-commands.sh` | PreToolUse (`Bash`) | Hard-blocks a fixed list of destructive command patterns — no "ask" path in this script at all |
| `session-start.sh` | SessionStart (`startup\|resume\|clear\|compact`) | Injects write-time rules, a doctrine pointer, a git briefing, and the current repo's vault topics (at most six rows, 4000 byte cap), and, when the repo has `docs/README.md`, a repo docs index line into context; prints a user-visible status line on startup only. Fires on compaction too, so a compacted session gets the rules and doctrine pointer re-injected instead of losing them with the summarized context |
| `subagent-rules.sh` | SubagentStart (no matcher) | Injects the same write-time rule bodies, a doctrine pointer, and the frontend/design pointer into every spawned worker's context at spawn, the subagent-side counterpart to `session-start.sh` |
| `notify.sh` | Notification (every notification) | Fires a native OS notification when Claude needs input |
| `md-wrap-check.sh` | PostToolUse (`Edit\|Write`) | Flags hard-wrapped prose in the content a `.md` write just produced and feeds the finding back to the model (doctrine: one line per paragraph) — warning only, never blocks, checks only the new content |
| `context-sentinel.sh` | PostToolUse (all tools) | Watches the conversation's context size via the session transcript; past 200k/400k/600k tokens it injects a model-visible nudge to delegate and plan a handoff (user-visible too from 400k) — advisory only, never blocks |
| `conductor-guard.sh` | PreToolUse (`Edit\|Write\|NotebookEdit`) | Prompts for confirmation when the main conversation (the conductor, not a subagent) edits a project file directly — doctrine delegates every change to a worker; `TOOLKIT_CONDUCTOR_EDITS=1` disables for a session |
| `design-rules-reminder.sh` | PreToolUse (`Edit\|Write\|NotebookEdit`) | When the target file matches a frontend pattern (extension or directory segment), injects a one-line pointer at the `rules/design.md` catalog into model context, once per session — advisory only, never blocks |
| `agent-model.sh` | PreToolUse (`Agent`) | Injects the model from `~/.claude/toolkit-models.json` into an Agent call when the config names that agent and the call carries no model. Advisory, fails open; warnings surface as a user-visible `systemMessage` |
| `remember-guard.sh` | Stop (every stop) | Warns the user, as a systemMessage, when a reply suggests a commit but the session's in-progress plan note has no Remember: line under Plan Changes During Execution. Warn-only, never blocks |

## The boundary model — what enforces what

Three distinct layers, in decreasing strength:

1. **Permission-system enforcement.** Claude Code's own permission prompts govern every tool call, including every `Bash` command. That is the actual outer boundary for arbitrary subprocess activity — not these hooks.
2. **Matcher-scoped hard pattern blocks.** `protect-files.sh` hard-denies within its `Edit|Write` matcher, and `block-dangerous-commands.sh` hard-denies the specific command patterns listed below within its `Bash` matcher. Within those scopes the deny is absolute (exit 2, no override). Outside them the hook is never consulted.
3. **Advisory warnings.** `scan-secrets.sh` only ever asks, never denies.

The honest consequence of layer 2's scoping: a subprocess started through `Bash` — `echo > file`, `sed -i`, a Python one-liner, a package manager's postinstall script — can write a file that `protect-files.sh` would have denied, unless the permission system stops the Bash call or the command happens to match a `block-dangerous-commands.sh` pattern. Detecting every possible Bash-based write would be an incomplete pattern-matching arms race (there are unbounded ways to spell "write a file" in shell), so it is intentionally out of scope. These hooks are defense-in-depth against the common, likely mistakes — they are not a sandbox.

## protect-files.sh

**Event:** `PreToolUse`, matcher `Edit|Write`.

Reads the tool call's `file_path`, compares its basename and full path (case-insensitively) against a fixed list, and decides before the write happens.

**Hard blocks (exit 2, no override — within the `Edit|Write` matcher; Bash-based writes are governed by the permission system, see the boundary model above):**
- Key/cert material: `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`, `id_rsa`, `id_ed25519`
- `credentials.json`, `.npmrc`, `.pypirc`
- Lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- Generated/minified output: `*.gen.ts`, `*.generated.*`, `*.min.js`, `*.min.css`
- Anything under `.git/` or `secrets/`
- Any hook script under `.claude/hooks/` or an installed plugin's `.claude/plugins/*/hooks/`

**Confirm-prompts (exit 0 with an `ask` decision — you can proceed):**
- `.env` / `.env.*`
- `.claude/settings.json` / `.claude/settings.local.json`

**Env vars:** none.

**Failure mode:** requires `jq` to parse the tool call; if `jq` is missing, it hard-blocks the write rather than skip the check silently.

## scan-secrets.sh

**Event:** `PreToolUse`, matcher `Edit|Write`.

Pulls the content being written (`content` for `Write`, `new_string` for `Edit`) and greps it for secret-shaped strings. Every match is an `ask`, never a `deny` — the script's own comment notes matches could be test fixtures, so it warns and lets you override rather than blocking outright.

**Patterns checked:**
- AWS access key IDs (`AKIA...`) and AWS secret keys
- GitHub tokens (`ghp_`, `gho_`, `ghs_`, `ghr_`, `github_pat_`)
- OpenAI/Anthropic/Stripe-style `sk-...` keys
- Slack tokens (`xox[bpras]-...`)
- PEM/OpenSSH private-key blocks (`-----BEGIN ... PRIVATE KEY-----`)
- Connection strings with embedded credentials (`mongodb://`, `postgres://`, `mysql://`, `redis://`, `amqp://`, `smtp://` with a `user:pass@`)
- Generic hardcoded credential assignments with a **quoted** literal value, over a broadened name set (`password`, `passwd`, `secret`, `secret_key`, `token`, `access_token`, `api_key`, `api_secret`, `client_secret`, `credential`, `creds`, `bearer`, `auth_token`, `private_key`, `db_pass*`) — excluding env references (`process.env`, `os.environ`, `getenv`, `env(...)`, `ENV[...]`, and a double-quoted `"$VAR"`). Unquoted values are deliberately not flagged here (too low-signal for an advisory hook); unquoted secrets with distinctive shapes are caught by the rules above.

Content is read for `Write`, `Edit`, `MultiEdit` (all `edits[]`), and `NotebookEdit` (`new_source`).

**Env vars:** none.

**Failure mode:** requires `jq`; if missing, it allows the write with no scan performed (fails open — this hook is advisory, not a security boundary).

## block-dangerous-commands.sh

**Event:** `PreToolUse`, matcher `Bash`.

Greps the raw shell command string against a fixed set of destructive patterns before the command runs. Every match is a hard block (exit 2) — this script has no "ask" path. It targets the **common, likely-accidental** forms below; it is not a general guard on what Bash may write, and a deliberately evasive spelling (unusual quoting, obscure flags, a command built at runtime) can get past it — the permission system, not this hook, is the boundary (see the boundary model above).

**Hard blocks:**
- `git push` affecting a protected branch — the branch named bare (`origin main`), as a refspec target (`:main`, `HEAD:refs/heads/main`, `+main`), or a bare/`-u` push while the current branch is protected; and any force push (`--force`/`-f`, but `--force-with-lease` is allowed). The clause is token-parsed, so `git push main <br>` (main as the remote) and `feature/main` (a branch merely named so) are not blocked.
- `rm` with BOTH recursive (`-r`/`-R`/`--recursive`) and force (`-f`/`--force`), in any flag arrangement, targeting `/`, `~`, an unresolved `$VAR`, `.`, `..`, `*`, or a system directory (`/usr`, `/etc`, `/var`, `/bin`, `/sbin`, `/lib`, `/opt`, `/root`, `/boot`). Quotes are stripped and `/bin/rm`/`\rm` prefixes are inspected.
- SQL run through a database **client** (`mysql`, `psql`, `sqlite3`, `mongosh`, …): `DROP TABLE|DATABASE|SCHEMA`, `TRUNCATE` (with or without `TABLE`), and `DELETE FROM` without a `WHERE` (per `;`-delimited statement, case-insensitive, SQL comments stripped). Gated on a client so `git grep "delete from"` is not blocked.
- `chmod` granting world/broad write: a numeric mode whose world digit has the write bit (`777`, `666`, `1777`, `0666`, …) or a symbolic `o`/`a` write (`o+w`, `a+rwx`, `ugo+w`)
- `curl`/`wget` piped to a shell (`| bash`, `| sh`, etc.), with or without `sudo`
- Shell redirection into a raw `/dev/*` device — including with a leading fd (`1>/dev/sda`, `&>/dev/sdb`); excludes the harmless `/dev/null|stdout|stderr|tty|zero|random|urandom`
- `mkfs*` and `dd if=/of=/dev/*`
- `git reset --hard` and `git clean -f`
- Package publish commands (`npm|yarn|pnpm|bun publish`, `cargo publish`, `gem push`, `twine upload`) unless run with `--dry-run`/`-n`

**Env vars:** `CLAUDE_PROTECTED_BRANCHES` — comma-separated branch list. When set, it **replaces** the default (`main,master`, plus the repo's `git config init.defaultBranch` if any) rather than adding to it. Note the naming: unlike the other two configurable hooks, this variable is `CLAUDE_*`, not `TOOLKIT_*`.

**Failure mode:** requires `jq`; if missing, it hard-blocks the command (fails closed, consistent with its role as a matcher-scoped hard pattern block: a command it cannot inspect must not pass).

## session-start.sh

**Event:** `SessionStart`, matcher `startup|resume|clear|compact`.

Produces two separate outputs:

- **`additionalContext`** (model-visible, every trigger): the write-time rules' bodies — testing, security, error-handling, database, performance, writing, prose, config-coupling, frontmatter stripped — read live from the plugin's `rules/` directory, or from `~/.claude/rules/<name>.md` when you have overridden one (see [overrides](overrides.md)); the banner names how many of the eight actually loaded (`N/8 loaded`), and an override that turns out empty or unreadable falls back to the plugin's own copy of that rule and is announced as a fallback rather than counted as your override, so the model is never told a rule body is present when it isn't; each rule body is capped at 64KB (it is re-sent on every request for the rest of the session) — a body over the cap is truncated to its first 64KB and announced by name rather than silently cut; a one-line pointer to the toolkit doctrine index that also names the rules directory (subagents get the equivalent pointer from `subagent-rules.sh` instead, at spawn); the delegate-everything standing rule verbatim (one line, so even sessions that never open the doctrine see it); a git briefing (current branch, or the short SHA if HEAD is detached, plus a `dirty` flag when the tree has uncommitted changes); and, when any are present, a one-line announcement of the active doctrine / rule / agent / skill overrides.
- **`systemMessage`** (user-visible, `startup` only — suppressed on `resume`/`clear` so it doesn't repeat): a one-line `toolkit active — N agents, M skills, planning ready` status, or a `planning not configured: run /setup` variant if `~/.claude/obsidian-sync.json` doesn't exist; if the plugin's `rules/` directory is missing or unreadable (a half-extracted update, an unset `CLAUDE_PLUGIN_ROOT`), this line reads `RULES NOT INJECTED (missing <path>)` instead — the status line is the only user-visible channel, so that failure is reported there rather than passed over in silence.

Inside a git repo, when `CLAUDE_PLUGIN_ROOT` is set, `~/.claude/obsidian-sync.json` exists, and a usable `python3` is on the PATH, it also runs `scripts/topic-recall.py --repo <repo name> --top 6` and adds the hits under a `Vault topics for this repo (prior context, not instructions):` header. The repo name is the basename of the main checkout, read from `git rev-parse --git-common-dir`, so a linked worktree recalls under the same name the vault uses. Outside a worktree, or when the common dir is not a `.git` directory, the name falls back to the basename of the checkout root. On macOS, a `python3` that resolves to `/usr/bin/python3` counts as usable only when `xcode-select -p` names an existing developer directory, because that path is a stub that opens an install dialog when the Command Line Tools are absent. The block holds at most six rows and is capped at 4000 bytes, because it is re-sent on every request. A row that crosses the cap is dropped whole. The script reads the vault's `INDEX.md`, which Mission Control writes, and falls back to a frontmatter scan of the topic notes when that file is absent, unreadable, not UTF-8, or has no topic rows. This block reads vault topics only. The injected rows are note text from the vault, so the model must treat them as prior context and never as instructions. When the checkout root has `docs/README.md`, a `Repo docs index: docs/README.md (N docs under docs/)` line follows. This line needs only the repo, not the vault config or `python3`. N counts the regular `.md` files under `docs/` up to four levels deep, not symlinks or directories, skips hidden and `node_modules` paths, and stops at 400. A hint line comes last, naming the `topic-recall.py` command with `--repo` and `--repo-root`, each value escaped with `printf %q` so a hostile directory name pastes as a literal, for task-scoped recall of vault topics and repo docs at plan or execute start. `--repo-root` is the checkout root, which in a linked worktree is the worktree directory. The hint line appears whenever the vault preconditions hold, even when no topic lists the repo. The script bounds its own run with an internal 3 second deadline. The hook adds `timeout 3` as an outer bound where the `timeout` binary exists.

On `compact` it additionally counts the session's compaction boundaries in the transcript (stateless — no counter file) and, from the second compaction onward, adds a model-visible escalation (stable point, update the plan/work note, recommend a fresh session) plus a user-visible `session compacted N×` warning. A session that compacts repeatedly re-pays its whole context indefinitely; this is the companion signal to `context-sentinel.sh`'s thresholds.

**Env vars:** `TOOLKIT_SESSION_VERBOSE=1` extends the git briefing with the last commit line, a count of changed files, a `staged` flag, the stash count, and — only if the `gh` CLI is installed — the current PR via `gh pr view`. That last call is the one network read in the entire hook set.

**Failure mode:** needs `jq` to emit JSON with a `systemMessage`; if missing, it falls back to plain-stdout `additionalContext` with no `systemMessage` at all — degrades, never blocks. The topics block skips silently: no `CLAUDE_PLUGIN_ROOT`, no vault config, or no usable `python3` leaves out the topic rows and the hint line, and the docs index line still prints. Outside a repo, nothing in the block prints. If the script fails or times out, the docs index and hint lines still print and only the topic rows are left out. The script's stderr is discarded.

## subagent-rules.sh

**Event:** `SubagentStart`, no matcher. Fires once per spawned worker, before it does anything else.

Injects the same rule bodies `session-start.sh` reads (testing, security, error-handling, database, performance, writing, prose, config-coupling), frontmatter stripped, into the worker's `additionalContext`. Each body is capped at 64KB like `session-start.sh`. A body over the cap is truncated to its first 64KB and announced by name. An override at `~/.claude/rules/<name>.md` that turns out empty or unreadable falls back to the plugin's own copy of that rule and is announced as a fallback rather than counted as an override, mirroring `session-start.sh`'s own tracking, and the same holds for a rule file that is missing on both sides.

When at least one rule loads, the hook adds framing lines beyond the rule bodies. A reminder that these are write-time rules for the worker's own output, not review dimensions to report as findings unless the task says otherwise. A pointer to the toolkit doctrine index at `${CLAUDE_PLUGIN_ROOT}/CLAUDE.md`, emitted only when that file exists, naming `doctrine/minimalism.md` and `doctrine/design.md` to read before writing code. A frontend and design pointer naming `rules/frontend.md` and `rules/design.md`. A one-line announcement of any active rule overrides, fallbacks, missing rule files, or truncations. A closing instruction to apply the rules to every artifact the worker writes in the task, so the rule bodies read as binding on the work at hand instead of as background text. When zero rules load, the hook skips all of this and injects one diagnostic line instead. It states how many of the total loaded (`0/N`) and names the unreadable rules path, so a half-extracted plugin update stays visible to the worker and to anyone reading its transcript. The apply-these-rules directive and the other framing lines are never emitted over zero rule content. This is the mechanism that reaches every spawned worker, both Agent-tool and Workflow-tool spawns, verified live on Claude Code 2.1.231. Subagents never fire `SessionStart`, so without this hook a worker would see none of the write-time rules.

**Env vars:** none.

**Failure mode:** fails open. No plugin root or no readable `rules/` directory means no context and no output at all (exit 0). Zero rules loaded is a distinct case: it still emits the one-line diagnostic described above, so it is not silent. Mirrors `session-start.sh`'s `jq` handling: emits JSON via `jq` when available, falls back to plain-stdout `additionalContext` when it is not, so the pipeline never depends on `jq` to reach a worker.

## conductor-guard.sh

**Event:** `PreToolUse`, matcher `Edit|Write|NotebookEdit`.

The delegation guard. The orchestration doctrine delegates every change, however small, to a worker agent; the only override is the human saying otherwise. This hook makes that mechanical: when the MAIN conversation (payload has no `agent_id` — subagent tool calls carry one) is about to `Edit`/`Write` a file inside the project (`cwd`), it returns an `ask` decision — "wait, you are the conductor; delegate unless the human directed this" — so the human's approval IS the override, per edit. Subagent edits, and conductor writes outside the project (vault plan/work notes, memory, scratchpad — conductor-owned artifacts, not implementation), pass untouched.

**Hard blocks / asks:** only ever `ask`, never `deny` — the human can always approve the edit through the prompt.

**Env vars:** `TOOLKIT_CONDUCTOR_EDITS=1` disables the guard for the whole session — the standing form of "I said do it yourself". If worker (subagent) edits ever start prompting, the payload signal changed with a Claude Code update — update the plugin rather than living with `TOOLKIT_CONDUCTOR_EDITS=1`; reaching for that flag routinely is itself the signal that the conductor is doing worker-work.

**Failure mode:** fails open — silent no-op without `jq`, on an empty payload, or when the target path can't be determined. A workflow guard, not a security boundary.

The guard is matcher-scoped to `Edit`/`Write`/`NotebookEdit`, so a conductor write spelled as `Bash` (`sed -i`, `echo >`, `git apply`) never consults it, for the same unbounded-ways-to-spell-a-write reason given in the boundary model above — that half of the doctrine is discipline, not enforcement.

The outside-`cwd` exemption assumes the standard project-checkout-plus-external-vault layout; a session whose `cwd` IS the vault or `~/.claude`, or multi-repo edits via absolute sibling paths, will be misclassified — advisory hook, not a boundary.

## agent-model.sh

**Event:** `PreToolUse`, matcher `Agent`.

Reads `~/.claude/toolkit-models.json` (or `$TOOLKIT_MODELS_FILE`, see below) and, when the config names a model for the agent an `Agent` tool call is about to spawn, adds that model to the call. It never shadows the agent file itself. The agent's prompt, tools, and every other field on the call pass through untouched, only the model changes.

The agent name comes from `tool_input.subagent_type`, with a leading `toolkit:` scope stripped, so both `toolkit:implementer` and a bare `implementer` resolve to the same config key. A value of `""` in the config means "use the agent file's own default" and is treated the same as the agent being absent from the config.

Claude Code's `PreToolUse` contract replaces `tool_input` wholesale with whatever `updatedInput` the hook returns, so a partial object like `{"model": "opus"}` would drop every other field on the call and fail schema validation. This hook always emits the full original `tool_input` plus the added `model` key, never a partial object.

An explicit per-call model on the tool call itself always wins over this hook; the hook only fills in a model when the call didn't already carry one. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, when Claude Code has it set, wins over both the per-call model and this hook.

This hook only reaches `Agent`-tool spawns. Workflow-script `agent()` calls (the `review-mr`, `plan-builder`, `execute-runner`, and `ship-runner` workflows) are not confirmed to pass through `PreToolUse`, so they keep whatever model the workflow script itself sets, unaffected by this config.

A configured model value containing `haiku` (case-insensitive) is refused, because the toolkit model policy runs no worker on Haiku, and the call proceeds with no model added, the same as an unlisted agent.

**Hard blocks / asks:** none. This hook never blocks or asks; it only adds a `model` field to a call the permission system was already going to process.

**Env vars:** `TOOLKIT_MODELS_FILE` overrides the config path in place of `~/.claude/toolkit-models.json` (used by the fixture tests below to point at a fixture config without touching a real one).

**Failure mode:** fails open. No `jq`, empty stdin, or a missing config file all exit silently with no model added. A malformed config (invalid JSON, or `agents` not an object) is announced once per call as a user-visible `systemMessage` and then ignored, the same as an unlisted agent or an invalid model value.

## design-rules-reminder.sh

**Event:** `PreToolUse`, matcher `Edit|Write|NotebookEdit`.

The design catalog (`rules/design.md` and its per-concern files under `rules/design/`) is reference-only — it never reaches session context via `session-start.sh`. This hook is the other way it surfaces: when the target file's extension or directory segment matches the frontend pattern list (an operational copy of `rules/design.md`'s `paths:` frontmatter, kept in sync by a `verify.sh` check), it injects a one-line `additionalContext` pointer at the catalog — no `permissionDecision`, so the edit is never delayed or blocked. Fires once per session; the marker lives at `$TMPDIR/toolkit-design-reminder-<session_id>`, the same idiom `context-sentinel.sh` uses for its once-per-crossing state.

**Limitation:** this hook does not reach worker models. `PreToolUse` `additionalContext` inside a subagent is broken upstream (Claude Code issue 19432), so a worker editing a frontend file never sees this reminder. `subagent-rules.sh`'s spawn injection carries the frontend/design pointer instead, so a worker still gets it, just from the other hook.

**Hard blocks / asks:** none — advisory only, exits 0 always.

**Env vars:** `TOOLKIT_DESIGN_REMINDER_STATELESS=1` skips the once-per-session dedup (used by the fixture tests, not meant for real sessions).

**Failure mode:** fails open — silent no-op without `jq`, on malformed or empty stdin, or when the marker directory is unwritable.

## context-sentinel.sh

**Event:** `PostToolUse`, no matcher — fires after every tool call.

The fuel gauge. Reads the session transcript (`transcript_path` from the hook payload), takes the last main-loop assistant message's usage, and computes the context the next request will re-send (`input + cache_read + cache_creation` tokens; sidechain/subagent entries are excluded — their contexts are separate and small). Crossing a threshold emits, once per crossing:

- **≥ 200k tokens:** a model-visible `additionalContext` nudge — delegate remaining mechanical work (searches, browser loops, log trawls, test runs) to workers and plan a wrap-up point.
- **≥ 400k:** a stronger nudge plus a user-visible `systemMessage` — reach a stable point, update the plan/work note, continue in a fresh session.
- **≥ 600k:** wrap up now; do not start new work in this session.

Why it exists: past ~200k tokens of context, every tool step costs several times a fresh session's, and near the window limit roughly thirty times — the dominant real-world burn pattern is a long session quietly re-paying its own history on every request. The binding guidance lives in `doctrine/orchestration.md` (Context budget); this hook is what makes it fire at the moment it matters.

Each threshold fires once per crossing: the announced tier is remembered in a per-session temp file (`$TMPDIR/toolkit-ctx-sentinel-<session_id>`) and re-arms when context shrinks again after `/compact` or `/clear`.

**Env vars:** `TOOLKIT_CTX_SENTINEL=0` disables the hook entirely. `TOOLKIT_SENTINEL_STATELESS=1` skips the once-per-crossing dedup (used by the fixture tests, not meant for real sessions).

**Hard blocks / asks:** none — advisory only, exits 0 always.

**Failure mode:** silent no-op without `jq`, without a readable transcript, or on any parse failure. It can only ever add context, never stop a tool call.

## remember-guard.sh

**Event:** `Stop`, no matcher. It fires each time Claude finishes a reply.

The check for the remember pass that red-team step 7b and plan-workflow Session Closure run once per slice. The pass records a `Remember:` line in the plan note, and this hook tells the user when a reply suggests a commit before that line exists. It prints a one-line user-visible `systemMessage` only when every condition holds:

- (a) `stop_hook_active` is false, so a Stop that follows a stop-hook continuation never warns.
- (e) The payload's `last_assistant_message` has a line that begins `Suggested commit`, matched case-insensitively, after an optional `#`, `*`, or `**` markdown prefix. The line can appear anywhere in the message, not only first. Red-team step 8 puts it directly after the Repo, Branch, and Scope header lines of its commit suggestion. The phrase in the middle of a line does not count.
- (b) The payload's `cwd` is inside a git repo. The repo name comes from the main checkout, so a linked worktree resolves to the same name, as in `session-start.sh`.
- (c) `~/.claude/obsidian-sync.json` resolves `<vault_path>/<root_folder>/Projects/<repo>` to an existing folder.
- (d) At least one plan note in that folder has `status: in-progress` and lists this session's id under `sessions:` in its frontmatter.
- (f) None of the plans matched in (d) has a line that starts with `Remember:` or `- Remember:` under `## Plan Changes During Execution`. Lines inside a fenced code block, fenced with backticks or tildes, never count, and a `## ` line inside a fence does not end the section.

The hook checks the conditions in the order listed, cheapest first. It never reads the session transcript. The marker lives at `$TMPDIR/toolkit-remember-guard-<session_id>`, the same idiom `context-sentinel.sh` uses. The hook warns once per session when the marker directory is writable. If the marker write fails, it warns on every Stop that meets the conditions. If the marker path is a symlink, the hook exits silently and writes nothing. Open item: the hook warns only until the plan's first Remember: line exists, so it does not catch a later slice on the same plan, and keying the check per slice is a later change.

**Env vars:** `TOOLKIT_REMEMBER_GUARD=0` disables the hook entirely.

**Hard blocks / asks:** none. It never returns `decision: block` and exits 0 always.

**Failure mode:** silent exit 0 without `jq`, without the vault config, or outside a git repo. A session id with characters outside `[A-Za-z0-9_-]` also exits silently. The hook writes nothing to stderr.

## notify.sh

**Event:** `Notification` — fires on every notification, no matcher filter.

Always fires the same fixed title ("Claude Code") and message ("Claude Code needs your attention") as a native OS notification: `osascript` on macOS, `notify-send` on Linux, a PowerShell toast on WSL. Silent no-op if none of those are available. It never reads `.message` from the hook payload — the hook's stdin is untrusted, and a generic attention signal is worth more than a detailed one that carries an injection path into a notifier command.

**Hard blocks / asks:** none. This hook only reads input and fires a notification; it never returns a permission decision, so it cannot affect whether a tool call proceeds.

**Env vars:** `TOOLKIT_NOTIFY_DRYRUN=1` — prints `notify: <title>: <message>` to stdout instead of calling a real OS notifier. Used by the fixture tests below so they don't spam a real notification on every run.

**Known limitations, stated honestly:**
- **Clicking the notification does not return you to your session.** On macOS, `osascript` posts under Script Editor's bundle identity, so a click opens Script Editor rather than your terminal — this is a macOS platform rule (Apple's UserNotifications APIs require an app-bundle identity, which a bare CLI process doesn't have: [Apple Developer Forums](https://developer.apple.com/forums/thread/724249)), not a fixable bug here, and it matches the normal contract for shell-based CLI notifiers generally. Treat the notification as an attention signal — "look at your terminal" — not as a way to navigate back to it.
- **A green exit does not mean a notification was delivered.** Every branch exits 0, including the final fallback when no notifier is available at all; the osascript/notify-send/powershell branches additionally send stderr to `/dev/null`, and macOS returns success from `osascript` even when the OS silently drops the notification for want of permission. This is deliberate — a `Notification` hook must never obstruct the session — but it means the hook's exit code cannot distinguish "not permitted" from "no method available" from "working fine". If notifications aren't appearing, check the OS notification permissions rather than assume the hook failed.

## Testing

The fixture suite lives at `hooks/tests/fixtures/<hook>/*.json` — one JSON file per case, each declaring the stdin payload, the expected exit code, and optional stdout/stderr substring checks (format documented in the header comment of `run-all.sh`). Run it directly:

```
bash plugins/toolkit/hooks/tests/run-all.sh
```

`verify.sh` runs this same suite as part of its checks, and separately spot-confirms `session-start.sh`'s two injections (a write-time rule and the doctrine pointer) by invoking it directly with empty stdin.
