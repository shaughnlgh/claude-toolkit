# Hooks

The toolkit ships five hook scripts that run automatically once the plugin is
installed — no opt-in, no separate config. This page is the full accounting, in the
spirit of transparency: exactly what each one checks, what it hard-blocks versus merely
asks you to confirm, and every environment variable it honors. The README's Docs list
links here in one line; this is the full version — the one to read before trusting the
toolkit with a repo.

Two properties hold across all five:

- **Fails safe.** No hook can crash or hang your session. Where "safe" lands differs by
  hook: `protect-files.sh` and `block-dangerous-commands.sh` require `jq` to parse the
  tool call, so if `jq` is missing they hard-block that one write or command rather than
  let a security check that can't run pass silently. `scan-secrets.sh` degrades to a
  no-op without `jq` (it cannot parse the write, so it does not block). `notify.sh` still
  fires with a default message when `jq` is missing, and only no-ops when no OS notifier
  is available. `session-start.sh` falls back to plain-stdout context. Either way, the worst case is one blocked tool call or a
  slightly thinner context injection — never a broken session.
- **Reads no network** — with one narrow exception: `session-start.sh`'s verbose mode
  (`TOOLKIT_SESSION_VERBOSE=1`) calls `gh pr view` when the `gh` CLI is installed, which
  does reach GitHub's API for the current repo's PR status. Every other code path in
  every hook is local only: file reads, git plumbing, `jq`, and OS notification APIs.

## The set

| Script | Event | What it does |
|---|---|---|
| `protect-files.sh` | PreToolUse (`Edit\|Write`) | Hard-blocks `Edit`/`Write` calls to keys/certs/lockfiles/generated files, `.git/`, `secrets/`, and hook scripts; asks for confirmation on `.env*` and `.claude/settings*.json` |
| `scan-secrets.sh` | PreToolUse (`Edit\|Write`) | Asks for confirmation when written content looks like a credential — never a hard block |
| `block-dangerous-commands.sh` | PreToolUse (`Bash`) | Hard-blocks a fixed list of destructive command patterns — no "ask" path in this script at all |
| `session-start.sh` | SessionStart (`startup\|resume\|clear`) | Injects write-time rules, a doctrine pointer, and a git briefing into context; prints a user-visible status line on startup only |
| `notify.sh` | Notification (every notification) | Fires a native OS notification when Claude needs input |

## The boundary model — what enforces what

Three distinct layers, in decreasing strength:

1. **Permission-system enforcement.** Claude Code's own permission prompts govern
   every tool call, including every `Bash` command. That is the actual outer boundary
   for arbitrary subprocess activity — not these hooks.
2. **Matcher-scoped hard pattern blocks.** `protect-files.sh` hard-denies within its
   `Edit|Write` matcher, and `block-dangerous-commands.sh` hard-denies the specific
   command patterns listed below within its `Bash` matcher. Within those scopes the
   deny is absolute (exit 2, no override). Outside them the hook is never consulted.
3. **Advisory warnings.** `scan-secrets.sh` only ever asks, never denies.

The honest consequence of layer 2's scoping: a subprocess started through `Bash` —
`echo > file`, `sed -i`, a Python one-liner, a package manager's postinstall script —
can write a file that `protect-files.sh` would have denied, unless the permission
system stops the Bash call or the command happens to match a
`block-dangerous-commands.sh` pattern. Detecting every possible Bash-based write
would be an incomplete pattern-matching arms race (there are unbounded ways to spell
"write a file" in shell), so it is intentionally out of scope. These hooks are
defense-in-depth against the common, likely mistakes — they are not a sandbox.

## protect-files.sh

**Event:** `PreToolUse`, matcher `Edit|Write`.

Reads the tool call's `file_path`, compares its basename and full path
(case-insensitively) against a fixed list, and decides before the write happens.

**Hard blocks (exit 2, no override — within the `Edit|Write` matcher; Bash-based
writes are governed by the permission system, see the boundary model above):**
- Key/cert material: `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`, `id_rsa`, `id_ed25519`
- `credentials.json`, `.npmrc`, `.pypirc`
- Lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- Generated/minified output: `*.gen.ts`, `*.generated.*`, `*.min.js`, `*.min.css`
- Anything under `.git/` or `secrets/`
- Any hook script under `.claude/hooks/`

**Confirm-prompts (exit 0 with an `ask` decision — you can proceed):**
- `.env` / `.env.*`
- `.claude/settings.json` / `.claude/settings.local.json`

**Env vars:** none.

**Failure mode:** requires `jq` to parse the tool call; if `jq` is missing, it
hard-blocks the write rather than skip the check silently.

## scan-secrets.sh

**Event:** `PreToolUse`, matcher `Edit|Write`.

Pulls the content being written (`content` for `Write`, `new_string` for `Edit`) and
greps it for secret-shaped strings. Every match is an `ask`, never a `deny` — the
script's own comment notes matches could be test fixtures, so it warns and lets you
override rather than blocking outright.

**Patterns checked:**
- AWS access key IDs (`AKIA...`) and AWS secret keys
- GitHub tokens (`ghp_`, `gho_`, `ghs_`, `ghr_`, `github_pat_`)
- OpenAI/Anthropic/Stripe-style `sk-...` keys
- Slack tokens (`xox[bpras]-...`)
- PEM/OpenSSH private-key blocks (`-----BEGIN ... PRIVATE KEY-----`)
- Connection strings with embedded credentials (`mongodb://`, `postgres://`, `mysql://`,
  `redis://`, `amqp://`, `smtp://` with a `user:pass@`)
- Generic hardcoded `password`/`secret`/`token`/`api_key`/`apikey`/`api_secret`
  assignments — this one explicitly excludes values that reference `process.env`,
  `os.environ`, `getenv(...)`, `env(...)`, `${...}`, or `ENV[...]`, so env-var references don't
  false-positive

**Env vars:** none.

**Failure mode:** requires `jq`; if missing, it allows the write with no scan performed
(fails open — this hook is advisory, not a security boundary).

## block-dangerous-commands.sh

**Event:** `PreToolUse`, matcher `Bash`.

Greps the raw shell command string against a fixed set of destructive patterns before
the command runs. Every match is a hard block (exit 2) — this script has no "ask" path.
It blocks exactly the patterns listed below and nothing else; it is not a general
guard on what Bash may write (see the boundary model above).

**Hard blocks:**
- `git push` (bare, or with an explicit refspec) to a protected branch, or with
  `--force`/`-f` (`--force-with-lease` is explicitly allowed)
- `rm -rf` (or any `-r...f...` flag combination) targeting `/`, `~`, `$HOME`, any
  unresolved `$VAR`, `../..`, or a system directory (`/usr`, `/etc`, `/var`, `/bin`,
  `/sbin`, `/lib`, `/opt`, `/root`, `/boot`)
- `DROP TABLE|DATABASE|SCHEMA`, `TRUNCATE TABLE`, and `DELETE FROM ...` without a
  `WHERE` on the same statement (checked per `;`-delimited statement, so multi-statement
  input is inspected one statement at a time)
- `chmod 777` / `chmod a+rwx`
- `curl`/`wget` piped to a shell (`| bash`, `| sh`, etc.), with or without `sudo`
- Shell redirection into a raw `/dev/*` device (excludes the harmless
  `/dev/null|stdout|stderr|tty|zero|random|urandom`)
- `mkfs*` and `dd if=/of=/dev/*`
- `git reset --hard` and `git clean -f`
- Package publish commands (`npm|yarn|pnpm|bun publish`, `cargo publish`, `gem push`,
  `twine upload`) unless run with `--dry-run`/`-n`

**Env vars:** `CLAUDE_PROTECTED_BRANCHES` — comma-separated branch list. When set, it
**replaces** the default (`main,master`, plus the repo's `git config
init.defaultBranch` if any) rather than adding to it. Note the naming: unlike the other
two configurable hooks, this variable is `CLAUDE_*`, not `TOOLKIT_*`.

**Failure mode:** requires `jq`; if missing, it hard-blocks the command (fails closed,
consistent with its role as a matcher-scoped hard pattern block: a command it cannot
inspect must not pass).

## session-start.sh

**Event:** `SessionStart`, matcher `startup|resume|clear`.

Produces two separate outputs:

- **`additionalContext`** (model-visible, every trigger): the write-time rules'
  bodies — testing, security, error-handling, database, frontmatter stripped — read
  live from the plugin's `rules/` directory, or from `~/.claude/rules/<name>.md` when
  you have overridden one (see [overrides](overrides.md)); a one-line pointer to the
  toolkit doctrine index; a git briefing (current branch, or the short SHA if HEAD is
  detached, plus a `dirty` flag when the tree has uncommitted changes); and, when any are
  present, a one-line announcement of the active doctrine / rule / agent / skill
  overrides.
- **`systemMessage`** (user-visible, `startup` only — suppressed on `resume`/`clear` so
  it doesn't repeat): a one-line `toolkit active — N agents, M skills, planning ready`
  status, or a `planning not configured: run /toolkit-setup` variant if
  `~/.claude/obsidian-sync.json` doesn't exist.

**Env vars:** `TOOLKIT_SESSION_VERBOSE=1` extends the git briefing with the last commit
line, a count of changed files, a `staged` flag, the stash count, and — only if the
`gh` CLI is installed — the current PR via `gh pr view`. That last call is the one
network read in the entire hook set.

**Failure mode:** needs `jq` to emit JSON with a `systemMessage`; if missing, it falls
back to plain-stdout `additionalContext` with no `systemMessage` at all — degrades,
never blocks.

## notify.sh

**Event:** `Notification` — fires on every notification, no matcher filter.

Reads `.message` from the hook payload (default text "Claude Code needs your
attention" if `jq` is missing or the field is empty) and fires a native OS
notification: `osascript` on macOS, `notify-send` on Linux, a PowerShell toast on WSL.
Silent no-op if none of those are available.

**Hard blocks / asks:** none. This hook only reads input and fires a notification; it
never returns a permission decision, so it cannot affect whether a tool call proceeds.

**Env vars:** `TOOLKIT_NOTIFY_DRYRUN=1` — prints `notify: <title>: <message>` to stdout
instead of calling a real OS notifier. Used by the fixture tests below so they don't
spam a real notification on every run.

## Testing

The fixture suite lives at `hooks/tests/fixtures/<hook>/*.json` — one JSON file per
case, each declaring the stdin payload, the expected exit code, and optional
stdout/stderr substring checks (format documented in the header comment of
`run-all.sh`). Run it directly:

```
bash plugins/toolkit/hooks/tests/run-all.sh
```

`verify.sh` runs this same suite as part of its checks, and separately spot-confirms
`session-start.sh`'s two injections (a write-time rule and the doctrine pointer) by
invoking it directly with empty stdin.
