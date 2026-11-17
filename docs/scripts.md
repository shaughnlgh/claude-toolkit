# Scripts

The toolkit ships a small set of scripts under `plugins/toolkit/scripts/`. Most are plain bash and stdlib-only Python with no dependencies. One is a vendored Node design-detector under `scripts/design-detector/` (the one piece of third-party code here — see below). Skills and the user invoke them directly rather than reimplementing the logic inline.

All of them are called through the plugin root, resolved once and reused. A skill, command, or agent names the root of the copy Claude Code loaded, so a `claude --plugin-dir` session runs that copy's scripts. A `/toolkit:override` copy of a skill or agent sits outside the plugin, so it runs the installed root's scripts. A shell outside them resolves the installed root:

```bash
PLUGIN_ROOT="$(jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json)"
bash "$PLUGIN_ROOT/scripts/<script>.sh" ...
```

Each entry below assumes `$PLUGIN_ROOT` is already resolved.

## The set

| Script | What it does | Guardrails |
|---|---|---|
| `vault-fs.sh` | Vault file ops `rm`, `mv` and `cp`, image attachments `attach`, vault reads `sha256` and `index`, and the topic index write `topic-index` | Refuses absolute paths, `..` traversal, symlink escape from the vault (canonical containment), non-regular-file targets, missing sources, unknown subcommands; attach: PNG or JPEG of at most 10 MiB from inside a git checkout, never over an existing file |
| `git-ro.sh` | Read-only git in any directory — `status`, `diff`, `log`, `show` | Subcommand allowlist; refuses write options (`--output`/`-o`/`--ext-diff`); neutralizes pager, fsmonitor, ext-diff and textconv (the execute-on-read vectors) |
| `seat-check.sh` | Reports which live Claude sessions hold a repo's main checkout, with its branch and dirty count | Read-only; never writes a file; reads sessions through `claude agents --json`; needs only `jq` and `git` |
| `seat-queue.sh` | Keeps the queue of sessions that wait for a repo's main checkout, and waits for a session's turn | Writes only `toolkit-seat-queue/` in the git common dir: one file per joined session, empty while the session waits and holding `seated` once its turn came, one `.miss-<sessionId>` marker per session that one read missed, the `.grant` lock directory while a grant step or a leave runs, and `.grant.break` while a contender removes a stale lock; removes only its own entry and the entries of sessions that two reads missed; reads liveness and the seat through `seat-check.sh`; needs `git`, `stat`, and the `jq` that `seat-check.sh` needs |
| `watch-mr.sh` | Waits on one GitLab MR or GitHub PR until its pipeline settles, a bot review lands, or a bot review in progress ends, then prints one status line | Reads only, through `gh` and `glab`, which hold their own auth; never reads or prints a token; validates every argument; exits on a wall-clock bound |
| `override.sh` | Copy a plugin doctrine, rule, agent, or skill into `~/.claude/` to override it (drives `/toolkit:override`) | Name only (no paths); refuses unknown/ambiguous names; won't clobber an existing override |
| `merge-conflict-overview.py` | Overview + side-by-side of git conflict markers | Read-only — never edits, stages, or commits |
| `validate-plan.py` | Validates a plan note against the plan-guide contract | Read-only — never edits the note; no network, no config, stdlib only |
| `plan-index.py` | Indexes a plan note for the execute runner: its sha256, the line of every section heading, and each step's heading and start line | Read-only, stdlib only, prints one JSON object with no section text, exits 1 on a file that is not UTF-8 |
| `run-checkpoint.py` | Prints an execute-runner Workflow run's checkpoint from its journal, and with `--replay` writes a runner copy that replays the recorded results | Reads only the run folders it is given and their run summaries, refuses a folder that is not a run folder under `~/.claude/projects`, stdlib only, writes only the `--replay` copy, and refuses a replay of a run that may still be live, died inside a stage that edits the tree, whose run summary lacks the args or the `const REPLAY = null` line, whose recorded `pluginRoot` is gone, or that another plan or checkout recorded, and with `--tree-hash` refuses a tree that changed since the run blocked |
| `slice-capture.py` | Captures the uncommitted diff of one or several repo roots into one file and prints its hash, its paths, and one part hash per repo | Runs only read-only git, writes only `slice-<hash12>.diff` under `--scratch`, refuses a repo outside `--root`, stdlib only |
| `topic-recall.py` | Lexical topic search over the vault index, with a frontmatter fallback and an optional repo `docs/` source | Read-only against the vault and the repo, stdlib only, skips symlinks and non-regular files, INDEX.md included, reads at most 64 KiB of each scanned note or doc, stops at a 3-second deadline |
| `vault-index.py` | Writes the topic index `INDEX.md` at the vault root from the `type: topic` notes, run through `vault-fs.sh topic-index` | Stdlib only, reuses the scan and row parser of `topic-recall.py`, writes only `INDEX.md` through a temporary file and a rename, refuses an `INDEX.md` that is not a regular file, and leaves an `INDEX.md` without its marker line untouched |
| `toolkit-vault.json.template` | Vault config template `setup` instantiates to `~/.claude/toolkit-vault.json` | n/a — config, not an executable |
| `resolve-models.sh` | Resolves each shipped agent's model and effort from the template, the user file, and the plan note's run options, and prints one JSON map, or one line per agent with `--list` | Read-only; never writes a file; refuses Haiku and invalid values with a stderr warning; needs only `jq` |
| `toolkit-models.json.template` | Default layer of per-agent model and effort routing for Agent-tool spawns and Workflow `agent()` calls | n/a, config, not an executable |
| `design-detector/` | Deterministic, no-LLM detector for AI-generated frontend anti-patterns (most of 46 rules) | Vendored from Impeccable (Apache-2.0, attributed); read-only; zero-dep by default |

## vault-fs.sh

Atomic file ops (`rm`, `mv`, `cp`), image attachments (`attach`) and the topic index write (`topic-index`) scoped to the vault, so skills like `plan-guide` and `handoff` never touch the filesystem with a raw shell command.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" rm <relpath>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" mv <relpath-src> <relpath-dst>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" sha256 <relpath>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" index <relpath>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" cp <relpath-src> <relpath-dst>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" attach <checkout> <src-relpath> <dst-relpath>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" topic-index
```

`vault-fs.sh sha256` prints the sha256 of a vault file, and `vault-fs.sh index` runs `plan-index.py` on a vault plan note and prints the index the execute runner reads ([workflows.md](workflows.md#execute-runnerjs)). Both take one vault-relative path and apply the containment and regular-file checks that `rm` applies. `vault-fs.sh topic-index` takes no argument and runs `vault-index.py` on the resolved vault root.

The vault root is resolved from `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent (`vault_path` + `root_folder`, see the template below). If neither file exists or the resolved root doesn't exist as a directory, the script refuses outright.

Guardrails — this is the point of the script:
- **Refuses absolute paths and traversal lexically.** Any path starting with `/` or containing `..` is rejected before it's joined to the vault root — relative vault paths only. `attach` takes its checkout as an absolute path and its source relative to that checkout, and refuses a source with `..`.
- **Canonical containment, symlinks included.** Every effective source and destination is resolved to its canonical path (a not-yet-existing destination via its existing parent) and must remain inside the canonical vault root, compared path-aware (`/vault-other` does not count as inside `/vault`). A symlinked directory inside the vault pointing outside it is refused; a symlink resolving to another location inside the vault is allowed. Fails closed with a `refused:` reason when containment cannot be established.
- **Regular files only.** Directory sources and destinations, non-regular files, dangling symlink destinations, and a missing source are all refused.
- **`mv` replaces an existing destination file by design.** Write-to-`.tmp.md` then `mv` is the toolkit's atomic-write mechanism — do not expect a no-clobber guard.
- **`cp` replaces an existing destination like `mv`.**
- **`attach` is the one operation that reads outside the vault, and only an image inside a git checkout.** The checkout root must hold `.git` and must not be the home directory or one of its parents, the source must resolve inside it and open with PNG or JPEG bytes, it must be at most 10 MiB, the destination extension must match the image type, and an existing destination is refused.
- **Unknown subcommands are refused**, not silently ignored.
- Every path refusal (traversal, containment, directory ops, missing source, missing destination directory, non-regular file, dangling symlink destination) names the resolved vault root and the expected relative form (`Projects/<repo>/...`). The unknown-subcommand refusal is the one exception; it carries no hint.

What it does NOT provide, deliberately: directory creation, locking or concurrency control, content/frontmatter validation, or a general filesystem sandbox beyond these operations.

Tests: `bash plugins/toolkit/scripts/tests/vault-fs/run-tests.sh` (47 behavior cases in a temporary vault; also run by `verify.sh`).

## git-ro.sh

Read-only git access in any directory, without granting a general-purpose `git` call.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/git-ro.sh" <dir> status|diff|log|show [args]
```

Guardrails — this is the point of the script: only `status`, `diff`, `log`, and `show` are accepted as the subcommand. Anything else (`commit`, `push`, `reset`, `checkout`, etc.) is refused before it ever reaches `git`. Within those subcommands the write/exec options `--output`/`-o` (write a file), `--ext-diff` (external diff command), and `--textconv` (textconv driver — refusing it also stops a caller overriding the forced `--no-textconv`) are refused. And because a target repo's own config can execute on a "read", the call forces `core.pager=cat`, `core.fsmonitor=false`, a null `core.hooksPath`, and `--no-ext-diff --no-textconv` on the diff-capable subcommands — so `git status`/`diff`/`log`/`show` cannot run a pager, fsmonitor, external-diff, or textconv command from the target repo. The target directory is passed straight to `git -C`, so it works against any repo on disk. Note: this makes the wrapper safe against a repo you do not fully trust for these four read operations — it is not a general git sandbox.

Tests: `bash plugins/toolkit/scripts/tests/git-ro/run-tests.sh` (12 behavior cases in a temporary repo whose config wires every execute-on-read vector to a marker script; also run by `verify.sh`).

## seat-check.sh

Reports which live Claude sessions hold a repo's seat, the main checkout. The session-start hook and the execute flow call it, so the holder rule lives in one place.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/seat-check.sh" <repo path> [--self <sessionId>] [--worktree <path>] [--live]
```

The repo path can be the main checkout, a directory under it, or a linked worktree of it. The script resolves the main checkout through the git common dir and resolves every path with `pwd -P`, so a symlinked path matches its target.

The holder rule: a session from `claude agents --json` holds the seat when it has a non-null `pid` that `kill -0` accepts, a `sessionId` other than the `--self` value, and a `cwd` that is the main checkout or a directory under it but not under `<main>/.claude/worktrees/`. A session in a linked worktree holds no seat. The script prints `status` and `kind` and never tests them.

`--worktree <path>` lists the live sessions that work in that worktree. A session is an occupant when it passes the same `pid` and `--self` tests and its `cwd` is that path or a directory under it. A session whose `cwd` is the main checkout is a holder and not an occupant. A path that is not a directory is an error. The execute flow reads it before section 1 re-enters or adopts a worktree, before section 2a enters one that `test -d` found, before the seat run detaches the plan's worktree, and before the release returns to the worktree it left. The ship flow's cleanup reads it before it removes the worktree.

`--live` lists every live session, the `--self` session included. A session is live when its `pid` is numeric and `kill -0` accepts it, whatever its `cwd`, so a session with `pid: null` gets no line. The flag changes no other line and not the exit code. `seat-queue.sh` reads liveness from it, and the execute flow's seat run reads it to find the session id of its parent.

Output, one line each, in this order:

- `seat: free` or `seat: held`
- `main: <main checkout path>`
- `branch: <branch>`, or `branch: detached`
- `dirty: <count of git status --porcelain -uall lines in the main checkout outside .claude/worktrees/>`, read with the pathspec `':(exclude,top).claude/worktrees/'`, so a linked worktree there never counts, with or without an ignore entry
- one `holder: <name>\t<status>\t<kind>\t<sessionId>\t<cwd>` line per holder, tab separated because a session name can hold spaces
- with `--worktree`, one `occupant: <name>\t<status>\t<kind>\t<sessionId>\t<cwd>` line for each live session other than `--self` whose `cwd` is that path or under it
- with `--live`, one `live: <name>\t<status>\t<kind>\t<sessionId>\t<cwd>` line for each live session

Exit codes: 0 free, 10 held, 2 error. An error prints one `error:` line to stderr. The script errors on a path that is not a git repo, a missing `jq`, and a session source that is not a JSON array, which covers a missing or failing `claude` binary. Where `perl` exists, the script kills a `claude agents --json` call that runs past 3 seconds, which then counts as a failing binary.

A caller inside a worktree session must invoke the script by a path and arguments that contain no `git` token. The harness guard reads the command text and refuses a command that names `git`, but it does not read the script, so the script's own `git -C <main>` calls run.

`TOOLKIT_AGENTS_FILE` names a JSON file the script reads instead of running `claude agents --json`. It is the test seam.

Tests: `bash plugins/toolkit/scripts/tests/seat-check/run-tests.sh` (20 behavior cases in a temporary repo with one linked worktree and no ignore entry for it; also run by `verify.sh`).

## seat-queue.sh

Keeps the order in which sessions wait for a repo's main checkout, and waits in the background for a session's turn. The execute flow's seat run calls it, so the queue rule lives in one place.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/seat-queue.sh" join <repo path> --self <sessionId> [--parent <sessionId>]
bash "$PLUGIN_ROOT/scripts/seat-queue.sh" wait <repo path> --self <sessionId> [--parent <sessionId>] [--bound <n>] [--interval <seconds>]
bash "$PLUGIN_ROOT/scripts/seat-queue.sh" leave <repo path> --self <sessionId>
bash "$PLUGIN_ROOT/scripts/seat-queue.sh" list <repo path>
```

The queue is the directory `<git common dir>/toolkit-seat-queue/`, which every linked worktree resolves to the same path. Each joined session has one entry named `<join epoch seconds>-<sessionId>`, sorted by name, so an earlier join second comes first, and joins in the same second go in session id order. An entry is empty while its session waits. The queue writes `seated` into it when the session gets its turn, and the entry stays seated until the leave removes it. A join on a session that already has an entry keeps that entry and its place.

Liveness and the seat come from one `seat-check.sh <repo> --live` read per verdict, taken without `--self`, so the session's own `holder:` line tells the queue that the session sits in the main checkout. A seat check that exits anything but 0 or 10 counts as failed, so the queue never reads the empty output of a killed or missing seat check as every session gone. A seated entry counts as a holder for every other session, beside the `holder:` lines, whatever `cwd` the agents list reports for its session.

The grant step. `join` and every `wait` round take one verdict. A verdict lists the entries, reads the seat, then takes the lock, a `mkdir` of `.grant` in the queue directory, which either creates the directory or fails. Under the lock it applies the miss rule, reads each entry's state once, and writes at most one mark. A contender retries once a second for 15 tries, and removes a lock older than 10 seconds, because it belongs to a killed process. Only the contender that creates `.grant.break` removes it, after it reads the age again, so no contender removes a fresh lock. `leave` takes the same lock, and exits 0 at once when the queue directory does not exist. `wait` prints `LEFT` and exits 13 at once when the queue directory does not exist. A join creates its own empty entry without the lock, because a later verdict decides it. `list` only reads.

The miss rule. A verdict considers only the entries in the listing it took before its seat read. The first read that misses an entry's session writes `.miss-<sessionId>`. A read that finds the session live removes the marker. A miss that finds a marker 5 seconds to 10 minutes old removes the entry and the marker, and a marker older than 10 minutes counts as a first miss again. A missed entry keeps its state and its place until the removal, so a missed seated entry keeps holding the seat. A `wait` round whose read misses its own session waits a round instead of taking the turn. A `join` that creates its entry and finds no live row for its own session waits 5 seconds, writes the entry again, and reads once more. When that second read also misses its own row, it exits 2 and keeps no entry, so a session with `pid: null`, such as a background session, cannot join. A `join` that already had an entry keeps it and waits a round, as a `wait` round does.

The turn rule. A session outside the main checkout gets its turn when no waiting entry is ahead of it, no other session holds the main checkout or a seated entry, and its own session read live. A session already in the main checkout ignores order, because it holds the seat for every other session by its `cwd`, and waits only for the other holders. A `WAIT` verdict empties the session's own mark, so a run that lost a free seat to a session that never joined stops holding it.

An unqueued holder is a session in the main checkout with no entry, other than the caller. `--parent <sessionId>` names the caller's parent session. When that session is an unqueued holder, the queue removes the caller's entry under the lock and prints `PARENT <sessionId>`, because a parent stays until its user ends it. The execute flow's seat run then starts no watcher and stops, so the parent runs the seat run itself or moves into a linked worktree and dispatches it again. A parent that holds a queue entry is waited for like any other holder.

Status lines and exit codes:

| Line | Exit | Meaning |
|---|---|---|
| `TURN` | 0 | the session's turn, with its entry seated and a clean main checkout |
| `WAIT <ahead> <holders> <unqueued> <dirty>` | 10 | not yet: the waiting entries ahead, the other holders, the unqueued holders, and the dirty count (`join` only) |
| `DEADLOCK <sessionId>` | 11 | the caller sits in the main checkout beside a session whose entry waits, so each waits for the other |
| `BOUND <minutes> <ahead> <holders> <unqueued> <dirty>` | 12 | the bound ran out, with the counts of the last `WAIT`, or `unknown` for each count when no round read `WAIT` (`wait` only) |
| `LEFT` | 13 | the caller's entry is gone (`wait` only) |
| `DIRTY <dirty>` | 14 | the session's turn, with its entry seated, on a main checkout whose dirty count is above 0, which waiting does not clear |
| `PARENT <sessionId>` | 15 | the `--parent` session is an unqueued holder, and the caller's entry is removed |
| none | 3 | the seat check or the lock failed five `wait` rounds in a row: the queue's own `error:` line, last on stderr, names the last round's cause, after the seat check's `error:` line, when one exists, from each round whose seat check failed |
| none | 2 | error: the queue's own `error:` line, last on stderr, after the seat check's `error:` line when one exists, for a bad argument, a path that is not a git repo, a failed seat check on `join` or `list`, a lock that stayed taken on `join` or `leave`, a write that failed, a `join` whose session has no live row on two reads, or a `join` whose existing entry a leave or a sweep removed before its verdict read it |

`leave` exits 0 once the caller's entry and miss marker are gone. `list` exits 0 and prints one line per entry whose session is live, in queue order, as the `live:` fields of seat-check behind `seated: ` or `waiter: `, then one `unqueued: <name>\t<status>\t<kind>\t<sessionId>\t<cwd>` line for each holder with no entry.

`--bound` takes minutes, or seconds with a trailing `s`, default 180. `--interval` takes seconds between rounds, default 30, floor 1. A `wait` exits on `TURN`, `DEADLOCK`, `LEFT`, `DIRTY` or `PARENT`, and on the bound.

`TOOLKIT_AGENTS_FILE` reaches seat-check through the environment, so it fixes the session list for every round. It is the test seam.

`/toolkit:setup` check 6 offers a prompt-free allow rule for the script, because the seat run calls `join`, `list` and `leave` in the foreground and `wait` in the background.

Tests: `bash plugins/toolkit/scripts/tests/seat-queue/run-tests.sh` (54 behavior cases against its own repo with two linked worktrees, with a stub `claude` on the `PATH` for the cases whose session list changes between rounds; also run by `verify.sh`).

## resolve-models.sh

Resolves the model and effort of every shipped agent, so the `agent-model.sh` hook and the workflow launchers apply one map.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/resolve-models.sh" [--agent <name>] [--options <file>] [--worker-model <m>] [--verifier-model <m>] [--verifier-effort <e>] [--alias] [--list]
```

The script reads three layers in order:

- `toolkit-models.json.template` beside the script, the default layer, or the file `TOOLKIT_MODELS_TEMPLATE` names, the path override the hook fixtures use
- the user file `~/.claude/toolkit-models.json`, or the file `TOOLKIT_MODELS_FILE` names
- the plan note's run options: `--worker-model` sets the implementer model, `--verifier-model` and `--verifier-effort` set the verifier entry

`--options <file>` names the plan-guide run options cache. The script reads its `worker_model`, `verifier_model` and `verifier_effort` lines and ignores its `plan:` line, and a flag wins over a line. With no flag and no options file, the script resolves the template and the user file only.

The per-field rule: the script picks `model` and `effort` separately for each agent, and a later layer wins over an earlier one. A blank value never overrides. `inherit` overrides the layers below and prints blank. A blank field is not passed on, so a Workflow `agent()` call inherits the session value, and an Agent-tool spawn with no model uses the agent definition's model, then a configured default subagent model, then the parent session's model. A user value can be a `{model, effort}` object or a bare string, which sets the model only. A model that contains `haiku`, a model that fails the model ID pattern, an effort outside `low`, `medium`, `high`, `xhigh`, `max`, a field that is not a string, and a value that is neither a string nor an object are each ignored with a warning, so the field keeps what the earlier layers set, and the field is blank when the template holds that value. A user key that is not a template agent is dropped with a warning. A key other than `model` and `effort` inside a user object is ignored with a warning.

Output: one line on stdout, `{"agents":{"<name>":{"model":"...","effort":"..."},...}}`, with one entry per template agent in template order.

`--alias` turns each resolved model that is not an Agent-tool alias (`sonnet`, `opus`, `haiku`, `fable`) into the one family alias it names, or blank when it names none or several, and warns with the agent in square brackets. `agent-model.sh` runs the resolver with it. The workflow launchers do not, so the runners keep the full value. `--list` implies `--alias` and prints one line per agent in place of the JSON, such as `toolkit:implementer: model opus, effort high`, with `omit model` or `omit effort` for a blank field. `session-start.sh` adds that list to the session's context.

Warnings go to stderr, one `toolkit resolve-models:` line each. A warning about a value names its agent in square brackets, and `--agent <name>` prints only that agent's value warnings. A warning about a whole file or about a user agent name that matches no template agent names no agent and always prints. `--agent` filters warnings only: stdout still lists every agent. The script warns on a refused or invalid value, an unknown key inside a user object, a user agent name that matches no template agent, a malformed user file, a user file with no `agents` object, and a missing options file, and still exits 0 with the layers it could read.

Exit codes: 0 resolved, 2 error. An error prints one `error:` line to stderr. The script errors on an unknown option, a missing `jq`, and a missing or invalid template or one with no `agents` object.

Tests: `bash plugins/toolkit/scripts/tests/resolve-models/run-tests.sh` (34 behavior cases with per-case user files and crafted templates in a temporary directory; also run by `verify.sh`).

## watch-mr.sh

Waits on one MR or PR until a terminal condition and prints one status line to stdout, once, at exit. Errors go to stderr.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/watch-mr.sh" <github|gitlab> <remotePath> <number> <pipeline|threads|review> --sha <sha> [--bound <n>] [--stuck <n>] [--settle <n>] [--none <n>] [--interval <seconds>] [--bot <login>]...
```

- `remotePath` is `owner/repo` or `group/sub/repo`. The script URL-encodes the whole path once for the GitLab API. `glab` resolves the GitLab host from the git remote of the working directory, or uses its default host when run elsewhere, so run the script from the repo.
- `number` is the PR number on GitHub and the MR iid on GitLab.
- `--sha` is required in every mode. It names the commit the result must belong to. The script lowercases it. A short sha matches the head by prefix, and once the script sees the full head sha, later rounds and reads compare against that.
- `--bound`, `--stuck`, `--settle` and `--none` take minutes, or seconds with a trailing `s` (`9`, `20s`). `--bound` defaults to 180, `--stuck` to 10 and `--settle` to 2, and `--none` has no default. `--stuck` and `--none` apply to pipeline mode only and `--settle` to review mode only.
- `--none` ends a pipeline watch early. Once it elapses while the last read showed no check or pipeline for `<sha>`, the script exits 13 `NONE` without waiting out `--bound`. A check or pipeline in the last read keeps the wait polling to `--bound`.
- `--interval` is the number of seconds between polling rounds and defaults to 30, with a floor of 1. The first round runs at once.
- `--bot` names a login whose review or note counts and can repeat. With one or more `--bot` logins, only those logins count, compared with any trailing `[bot]` removed from both sides, so `coderabbitai` matches `coderabbitai[bot]`. Without `--bot`, GitHub threads and review modes count an author whose `user.type` is `Bot`. GitLab threads mode requires `--bot`, because the GitLab notes API carries no bot flag on its basic user object. GitLab review mode without `--bot` counts the in-progress marker from any author and never reads `LANDED`, so the ship runner passes its `botAuthors` as `--bot` to review mode.
- Review mode is busy while a comment carries the marker `review in progress by coderabbit.ai`: on GitHub an issue comment by a bot, and on GitLab a non-system note, from a `--bot` login when any are given. Issue comments count only in review mode.

| Exit | Line | Meaning |
|---|---|---|
| 0 | `GREEN <sha>` | pipeline mode: the pipeline for `<sha>` is `success` on GitLab, or every check passed or was skipped on GitHub |
| 0 | `LANDED <sha> <author>` | threads mode, and review mode while no comment carries the marker: on GitHub, the first bot review whose commit is `<sha>` and whose body does not say it did not review; on GitLab, a non-system note from a `--bot` login created at or after the anchor, which is the head pipeline's creation time or, without a pipeline, the commit date. A note with a `position.head_sha`, such as a diff note, counts only when that sha is the head, and a note that carries the marker never counts. In review mode on GitLab only a `--bot` login lands. |
| 10 | `RED <sha> <names>` | pipeline mode: a job failed, was cancelled, or timed out; `<names>` is the comma-joined list of those jobs |
| 11 | `STUCK <sha> <minutes>` | pipeline mode: for `--stuck`, at least one job exists and every job is terminal while the pipeline status is not. On GitHub the jobs are the Actions runs for `<sha>`, so a repo whose checks come only from another CI never reads as stuck. On GitLab the jobs are those outside the `external` stage, so an empty job list while the pipeline is being created never reads as stuck. |
| 12 | `BOUND <sha> <minutes>` | `--bound` elapsed in any mode, unless the last read showed no pipeline for `<sha>` (13) or a refusal on `<sha>` with no review in progress (16) |
| 13 | `NONE <sha>` | pipeline mode: the last read showed no pipeline for `<sha>` when `--none` elapsed or at the bound, or the pipeline for `<sha>` is `skipped` |
| 14 | `MOVED <sha> <newHeadSha>` | the MR or PR head is no longer `<sha>`; exits on the first round that sees it |
| 15 | `QUIET <sha> <minutes>` | review mode: for the whole `--settle` window no comment carried the marker, no review landed, and no bot review on `<sha>` said it did not review |
| 16 | `UNREVIEWED <sha> <author> <text>` | threads and review modes: no bot review on `<sha>` landed and one said it did not review, on GitHub a Copilot refusal review and on GitLab a listed bot's note that carries CodeRabbit's `rate limited by coderabbit.ai` marker. Threads mode exits on the round that reads a refusal from every `--bot` login, else at the bound. Review mode exits when the settle window ends, or at the bound after a round with no marker. `<author>` is the first refusing bot and `<text>` its refusal sentence: for Copilot the sentence that opens its body, with whitespace joined to single spaces, cut at the first period after `this pull request`, and for CodeRabbit the sentence that holds `has exceeded the limit for the number of commits or files that can be reviewed`. |
| 2 | (stderr message) | usage error: missing arguments, unknown host, unknown mode, bad number, missing or bad `--sha`, bad remotePath, bad duration, bad interval, unknown option, missing option value, `--none` outside pipeline mode, or GitLab threads mode without `--bot` |
| 3 | (stderr message) | tool error: `jq` is not on PATH, checked before any API call, or `gh` or `glab` failed five rounds in a row; the last error text goes to stderr |

The script never exits 1. Codes 0 and 10 to 16 are outcomes, and codes 2 and 3 are failures of the script itself. `<minutes>` is the whole minutes elapsed: since the start for `BOUND`, since the stuck condition first held for `STUCK`, and for `QUIET` since the first round with no marker, counted again after any round that sees one.

The ship-runner pipeline and threads verifiers run it as one blocking call with `--bound 9`, plus `--none 2` on the pipeline watch when the repo carries no CI configuration, and the ship-flow conductor runs it as a background command with `--bound 180` to wait out a pending pipeline or review.

Tests: `bash plugins/toolkit/scripts/tests/watch-mr/run-tests.sh` (95 behavior cases against stub `gh` and `glab` executables that answer from per-round fixtures; also run by `verify.sh`).

## override.sh

Backs the `/toolkit:override` command. Copies a plugin **doctrine, rule, agent, or skill** into `~/.claude/` so your copy overrides the plugin's for that concern.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/override.sh" [type] [name]
```

With no arguments it lists everything overridable, grouped by type. With a name it auto-detects the type and copies it (doctrine/rules/agents as a single `.md`, a skill as its whole directory); with a `<type> <name>` pair it forces the type for an ambiguous name (`security` is both a doctrine and a rule). How each takes effect: doctrine and rules are picked up by the session-start hook (doctrine announced, a rule's body injected in place of the plugin's); agents and skills are resolved natively by Claude Code for the bare name. Guardrails: name only (no paths or `..`), refuses unknown or ambiguous names, and never clobbers an existing override. It also refuses an agent copy when a user agent under another file name already carries that frontmatter `name`, and a skill copy when a personal skill under another directory name already carries it, because Claude Code resolves each by that name. Self-locating, so it needs no config.

## merge-conflict-overview.py

The merge-conflict overview helper the `resolving-merge-conflicts` skill drives before it resolves anything. It parses `<<<<<<<` / `|||||||` / `=======` / `>>>>>>>` markers and prints two things: a summary (conflicted file count, hunks per file, line counts per side) and a per-hunk view — side-by-side for a two-way conflict, stacked for a three-way (`diff3`) conflict or a narrow terminal.

Invoke:

```bash
python3 "$PLUGIN_ROOT/scripts/merge-conflict-overview.py" [file ...]
```

With no arguments it discovers conflicted files itself via `git diff --name-only --diff-filter=U`. Pass explicit paths to inspect a subset.

Notes:
- **Stdlib only** — `argparse`, `shutil`, `subprocess`, `sys`. No dependencies to install or vet.
- **Read-only.** It only reads and prints; it never edits a file, runs `git add`, or commits. Resolution and confirmation stay with the skill and the human.
- Binary or unreadable files are skipped with a note on stderr; files with no conflict markers are skipped the same way.

## validate-plan.py

Read-only validator for the canonical plan-note contract defined by the `plan-guide` skill. Takes exactly one plan-note path; never writes; needs no network, vault config, or packages (python3 standard library only).

    python3 <plugin-root>/scripts/validate-plan.py "<vault>/.../plan - my-slug.md"

Exit codes: `0` valid, `1` contract violation(s) (each printed as `VIOLATION: ...`), `2` usage error, unreadable path, or malformed frontmatter.

**What it proves (mechanical contract only):** filename matches `plan - <slug>.md` with a kebab-case slug; a non-blank `plan:` matches the filename; `type: plan`; all 18 required frontmatter keys are present (`modules`/`repos` are validly blank for single-repo plans, but the keys must exist); `status` is a lifecycle value (`planning`, `review`, `approved`, `in-progress`, `completed`, `blocked`, `abandoned`); a `parent:` child sits in its parent's directory beside the parent note; session entries carry a date and summary with unique non-blank ids (blank ids allowed, never counted as duplicates); the twelve required headings exist; a thirteenth heading, Plain Language Summary, is also required, but only for plans whose frontmatter `created` date is on or after 2026-08-26 (the date the convention was adopted), so plans written before it are not retroactively broken; a plan at status completed carries a Remember: line (bullet or bare) under Plan Changes During Execution, outside a fenced block, but only for plans whose frontmatter `created` date is on or after 2026-10-18 (the date the remember pass joined the workflow), so plans written before it are not retroactively broken; and nothing links the retired `mr-description` artifact. Unknown frontmatter keys (Mission Control's `worklogs`, `tracking`, `mockups`, …) are tolerated whatever their shape.

**What it deliberately does not judge:** prose quality, whether Implementation Steps show real code, plan completeness, topic-link resolution, or status-transition ordering — those remain human and model judgment (plan-critic and the approval gate).

**Parser note:** the frontmatter parser is deliberately narrow — the exact subset the toolkit and Mission Control produce (top-level scalars, lists of scalars, lists of flat mappings). Unsupported structure under a *validated* key fails loudly with exit 2 instead of being silently misparsed.

When it runs: the `plan-guide` skill requires a passing validation after every plan-note write, before presenting a plan for approval, before starting execution, and at session closure.

Tests: `bash plugins/toolkit/scripts/tests/validate-plan/run-tests.sh` (48 behavior cases over 46 fixtures plus a direct nonexistent-path case; also run by `verify.sh`).

## topic-recall.py

Lexical search over the vault's topic notes and, when asked, a repo's `docs/` folder. Session start, plan-guide, crawl, and execution-guide run it to recall what earlier sessions recorded about a repo or a task.

Invoke:

```bash
python3 "$PLUGIN_ROOT/scripts/topic-recall.py" [--repo <name>] [--repo-root <path>] [--top N] [--format text|json] [--version] [query words...]
```

Defaults are `--top 10` and `--format text`. The vault root comes from `~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent (`vault_path` plus `root_folder`).

`--version` prints the toolkit content version to stdout and exits 0 before the script reads any config. The script resolves symlinks in its own path and treats the directory above `scripts/` as the plugin root. If the parent of that root is named `toolkit`, as in the plugin cache, the script prints the name of the root directory, which is the install version. Otherwise it prints `git rev-parse --short=12 HEAD` of the root, or `unknown` if git is missing or finds no commit.

Source: the script reads `<vault_path>/<root_folder>/INDEX.md`. Three facts govern it. First, `vault-fs.sh topic-index` (see `vault-index.py` below) or another tool writes the index, and the script reads both kinds the same way. Second, a toolkit-written index, one that holds the generator's marker line, is used only while no folder and no `.md` file under the root folder has a newer modification time than the index. Otherwise the script treats it as out of date and scans the frontmatter instead, so a note added, edited, moved or deleted by hand after the last index write is never hidden. An index without the marker is used whenever it has topic rows. Third, the generator writes nothing while a topic note cannot be written as a row or while two topic notes share a name, so recall stays on the frontmatter scan in those states. Only rows under `## Topics by domain` count, up to the next level-2 heading, so sections such as `## Projects` that another tool may add stay out. The script reads the parenthesized meta of each row by content, not by position. A segment that starts with `verified` or `unverified` is the verified state, a segment that equals `stale` after the script strips the `⚠` sign and whitespace marks the row stale, and any other segment is the comma-separated repo list. A row with no repos omits the repo segment, so rows ending in `(unverified)` or `(verified 2026-08-10; ⚠ stale)` parse with no repos. The script reads a regular INDEX.md whole. If INDEX.md is missing, unreadable, a symlink, not a regular file, has no topic rows, or is an out-of-date toolkit-written index, the script walks the root folder instead and keeps files whose frontmatter says `type: topic`. If INDEX.md exists but is a symlink, is not a regular file, or cannot be read, the script prints one line naming the path to stderr before it falls back. Text output from the fallback starts with `source: frontmatter scan (INDEX.md unavailable or out of date)`, and every fallback row reports `stale` as false.

File reads: the frontmatter fallback walk and the repo docs walk skip symlinked files, symlinked directories, and any entry that is not a regular file, such as a FIFO or a device. The script reads at most 64 KiB of each file, drops a leading UTF-8 byte order mark, and keeps at most the first 120 lines of that. It ignores frontmatter that does not close within those lines. Frontmatter values can be plain scalars, `[a, b]` lists, `- item` lists, or YAML block scalars (`>`, `>-`, `>+`, `|`, `|-`, `|+`). The script joins the indented lines of a block scalar with spaces.

Repo source: if `--repo-root <path>` is given, the script adds the Markdown files under `<path>/docs` to the vault rows before ranking. The script makes the path absolute first, so `--repo-root .` names the repo of the current directory. If `--repo` is not passed, it defaults to the basename of that absolute path. The walk visits directories and files in sorted order, skips directories that start with `.` or are named `node_modules`, keeps files at most 4 path components below `docs/` (the files `find -maxdepth 4` lists), and skips `.md` files that start with `.`. The walk lists the files of a directory before it enters its subdirectories, and the 400-file cap applies in that order, so the files directly under `docs/` count first. A missing `docs/` adds nothing. The title is the frontmatter `title`, else the first `# ` heading after the frontmatter, else the file name without `.md`. The summary is the frontmatter `summary`, else the first paragraph after the frontmatter that does not start with `#` or `<!--`. The script joins the lines of that paragraph with spaces up to the first blank line. Either summary is cut at 200 characters. A doc whose frontmatter does not close within the first 120 lines gets the file name as its title and an empty summary. Each repo row lists the repo basename as its only repo, reports `verified` as `repo`, and carries `source: repo`. Vault rows carry `source: vault`.

Scoring: the script lower-cases the query, splits it on `[a-z0-9]+`, and drops tokens shorter than 3 characters. Each distinct query token found in a title adds 8, and each distinct query token found in a summary adds 3. For a vault row, a `--repo` value listed in the row's repos adds 6 once. A repo row gets no repo bonus, because every repo row lists the repo. The repo row for `<repo-root>/docs/README.md` adds 2 if it has at least one token hit, so the docs index leads its folder on equal hits. With no query words, every repo row scores 0. Rows that score 0 are dropped. Hits sort by score, highest first, then by title. A stale or unverified row scores the same as a verified one.

Output: text prints three lines per hit. The first line is the title, the repos in brackets, then `[vault]` and the verified state for a vault row, or `[repo]` for a repo row, and it ends with `(score N)`. The summary and the absolute note path follow. JSON prints a list of objects with `title`, `summary`, `repos`, `verified`, `stale`, `path`, `source`, and `score`. The path is blank in JSON, and `(no local file)` in text, when no `<Title>.md` exists under the root folder, for example when a sync client has evicted the note. The script writes stdout as UTF-8 whatever the locale, and replaces any character it cannot encode.

Exit codes: `0` with hits or with none, or after `--version`, `2` if the vault config (`~/.claude/toolkit-vault.json`, or `~/.claude/obsidian-sync.json` when that file is absent) is missing or unreadable, or the vault root is not a directory, and `3` if the run passes its internal 3-second deadline. The script sets that deadline with `SIGALRM`, so a platform without `SIGALRM` has no exit 3. On exit 2 or 3 the reason goes to stderr and nothing goes to stdout.

Embedding seam: `rank()` is the only function an embedding backend replaces. It receives the candidates, the query words, the repo name, and the docs index path. Loading, path resolution, and rendering stay as they are, so the CLI and its output do not change.

Tests: `bash plugins/toolkit/scripts/tests/topic-recall/run-tests.sh` (62 behavior cases in temporary vaults and repos with an overridden HOME, the index generator's cases included). `verify.sh` also runs it.

## run-checkpoint.py

Reads the checkpoint of an execute-runner Workflow run from the runtime's own records, so a run that died with its session continues from a new session. The execute-flow skill runs it before a continuation.

Invoke:

```bash
python3 "$PLUGIN_ROOT/scripts/run-checkpoint.py" [--from <label>] [--tree-hash <hash12>] [--replay <out.js> --plan <planName> --repo-root <path>] -- <run-folder>...
```

Each run folder is `~/.claude/projects/<project slug>/<session id>/subagents/workflows/<runId>/`, oldest first when one run continued another. Each folder argument must be an absolute path, and the execute-flow skill passes the folders after `--`, so a folder value that begins with `-` is never read as an option. The script resolves `~` from `HOME` and refuses, with exit 1, a folder argument that does not begin with `/`, or a folder whose real path is not exactly that layout under the real path of `~/.claude/projects`, so a symlink inside it that resolves elsewhere is refused too. The script reads the folder's `journal.jsonl` and the run summary `<session id>/workflows/<runId>.json`, which the runtime writes when a run ends and rewrites when a resumed run ends. The summary's `timestamp`, an ISO 8601 UTC time, is the time the run ended.

A stage is one agent call: a `started` journal entry with its label and phase. Its state is `done` when a `result` entry carries the same agent id, or a `failed` entry does, because the agent returned nothing and the run carried on, so the stage replays as null. Otherwise it is `open`. A last journal line that is not JSON is a write torn by a dying session, so the script ignores it and its stage stays open. Every journal line begins `{"type":`, so a torn line that begins `{"type":"result"` lost only part of a result whose `started` entry is intact. A line that is not JSON anywhere else exits 2. A stage whose phase begins `▸ ` belongs to a child workflow, which the runtime records under the phase `▸ <child name>`. An open stage of an older run is dropped, because the run that continued it ran that stage again. When a later run's `REPLAY` record holds a `from` label, that run was a journal resume, so the stages before it are cut at that label as `--from` cuts them, and only its own live stages follow.

Output: one JSON object with `runs` (each run id with its summary `status`, null when no summary exists), `done` (the count of done stages), `open` (the labels of open stages), `stages` (run, label, occurrence, phase and state of each), `changedPaths` (the union, in first-seen order, of every done runner stage's `changedPaths`), `capture` (the label, `hash12` and `paths` of the newest done capture, a runner result that carries `diffPath` and `paths`, or null), `replay` (null without `--replay`), `from` (the `--from` label or null), and `blockedTree` (the `hash12` of the newest run's done `diff:blocked` capture, or null).

`--from <label>` cuts the recorded stages for a journal resume of a blocked run. The label must match `^[a-z][a-z0-9-]*(:[a-z0-9-]+)*$`. A runner label keeps every stage before its first runner occurrence, so that stage and every later one runs live. `review` keeps the runner stages before the `review-mr` child and every child result that recorded one, so only the child agents that died run again, and `review:<label>` does the same and also drops that child label, so a verifier result a settle made stale runs again. A reviewer's own label begins `review:`, so `review:<label>` with no child of the stripped label names the child whose label is the whole value, as the `stages` output prints it. `plan:index` and a label with no recorded stage exit 1.

`--tree-hash <hash12>` takes the `hash12` of a live capture of the tree and exits 1 unless it equals `blockedTree`, so a resume never replays validation or review results over a tree that changed since the run blocked. A run with no `blockedTree` exits 1 too. `--replay` with `--from` needs `--tree-hash`.

`--replay <out.js>` needs `--plan` and `--repo-root`, the plan and checkout the continuation is for, and writes a copy of the first run's own script, taken byte for byte from its run summary, with the line `const REPLAY = null` replaced by the recorded run: the first run's args, the newest `plan:index` result as `index`, each runner and child label's done results in call order, and the `--from` label as `from` when one was given. The runner continues on those args with the launch's own `scratchDir`, runs `plan:index` live, and blocks when the step headings differ from the recorded index. Each call takes the next recorded result for its label until the first label with none left, then calls agents from there on. The child `review-mr` gets the child results as its `replay` arg. The `replay` field reports the copy's `path`, its 12-character `sha256` prefix, and the `runnerResults` and `childResults` counts.

Before it writes the copy, `--replay` checks that:

- the newest run has a summary whose status is not `running`, whose `timestamp` parses, and whose run folder's `journal.jsonl` was last modified no more than 1 second after that `timestamp`, which the runtime cuts to the millisecond, else the run may still be live, because a resume keeps the runId and writes into the same folder behind the summary of the run it resumed
- the first run's summary holds `args` and a `script` with the `const REPLAY = null` line exactly once
- in every run folder, the recorded `args.planName` equals `--plan`, and the real path of `args.repoRoot` equals the real path of `--repo-root`, so a run folder that another plan or checkout recorded is never replayed. A continuation launches with `scratchDir` alone, so for a run whose script holds a non-null `REPLAY` record, the script reads the args from that record alone and refuses when the record holds none
- the recorded `pluginRoot` still holds `scripts/vault-fs.sh`, because the copy runs on the recorded args and the plugin cache keeps no old versioned directory, so the execute-flow skill falls back to a fresh rerun
- no journal ends in a torn line that does not begin `{"type":"result"`, because such a line can be the `started` entry of a writer stage
- no open runner stage is `implement:<n>`, `fix:<round>`, `fix:validation` or `doc:pass`, whose partial edits have no record
- some run recorded a `plan:index` result
- every recorded capture's diff file still exists

`WRITER` holds `edit:check`, `implement:<n>`, `fix:<round>`, `fix:validation` and `doc:pass`. The writer-stage labels in it never change once a runner with a `REPLAY` line has shipped, because that runner's journals carry them. A renamed writer stage keeps its old label in `WRITER`.

Exit codes: `0` on success, `1` when `--replay` refuses, a `--from` label has no recorded stage, `--tree-hash` does not match the run's blocked tree, or a run folder is not `<slug>/<session id>/subagents/workflows/<runId>` under `~/.claude/projects`, `2` on a `--replay` without `--plan` and `--repo-root`, a `--replay` with `--from` but no `--tree-hash`, a malformed `--from` or `--tree-hash`, an unreadable journal or summary, a non-JSON summary, a non-JSON journal line other than the last, or a journal entry that lacks a field the script reads, and `3` when `--replay` finds that the newest run may still be live. Every refusal goes to stderr as a `refused:` line.

Tests: `bash plugins/toolkit/scripts/tests/run-checkpoint/run-tests.sh` (71 behavior cases over synthetic journals and summaries). `verify.sh` also runs it.

## slice-capture.py

Captures the uncommitted diff of one or several repo roots into one file, so the execute runner's captures, execute-flow section 8 and ship-flow section 4 compare the same bytes. The runner's capture prompt runs it, and both skills brief a verifier with that prompt.

Invoke:

```bash
python3 "$PLUGIN_ROOT/scripts/slice-capture.py" --scratch <dir> --base <HEAD|sha> --root <dir> [--repo <dir>]...
```

- `--scratch` is an absolute directory, created when missing, that receives `slice-<hash12>.diff`.
- `--base` is `HEAD` or a 7 to 40 character lowercase hex sha, the commit each root's tracked diff starts from.
- `--root` is the run root, an existing absolute directory. With no `--repo`, it is the one repo captured, and the capture is `git diff <base>` plus one `git diff --no-index -- /dev/null <file>` per untracked file, with `.claude/worktrees/` excluded.
- Each `--repo` is an existing absolute directory equal to `--root` or under it, given once. With one or more, the script captures each in the order given, prefixes each diff header and each listed path with the repo's path relative to `--root`, and excludes from each repo every other `--repo` nested inside it, so a nested module is captured once.

Output: one JSON line with `diffPath`, `hash12` (the first 12 hex characters of the sha256 of the whole capture), `empty`, and `paths` (each changed and untracked path, relative to `--root`, read with `core.quotePath=false`). With `--repo`, it adds `parts`: one `{root, hash12, empty}` per repo for the bytes that repo added, so a change in one repo leaves the other parts' hashes unchanged. Exit `2` with one `slice-capture: <reason>` line on stderr for a bad argument, a failed git call, or a failed write. [context-git-tree-state-capture.md](context/context-git-tree-state-capture.md) lists the git quirks it handles.

Tests: `bash plugins/toolkit/scripts/tests/slice-capture/run-tests.sh` (18 behavior cases over fixture repos: one root byte for byte as the single-repo capture, sibling and nested roots, odd file names, part hashes, and bad arguments). `bash plugins/toolkit/scripts/tests/several-repos/run-tests.sh` (18 cases) runs the execute-flow section 2b command forms, each checked verbatim against the skill, on fixture repos with no network, and ends with a five-root capture. `verify.sh` runs both.

## vault-index.py

Writes `<vault_path>/<root_folder>/INDEX.md`, the topic index that `topic-recall.py` reads. The `/toolkit:topic` command and the remember pass run it after they create, update, move or remove a topic note.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" topic-index
```

The script scans the `type: topic` notes under the root folder with the scan `topic-recall.py` uses, and writes one row per note under `## Topics by domain`, sorted by title, after a `# Vault index` heading and the marker line `Generated by the toolkit (vault-fs.sh topic-index). Do not edit.` It writes through a temporary file and a rename, then sets the file's modification time, so the index reads as current until a folder or `.md` file under the root folder changes.

It writes nothing, and recall stays on the frontmatter scan, when a note's title or repo list cannot be written as a row that parses back to the same values, or when two topic notes share a title, because an index row carries a title and no path. It names each such note on stderr. It leaves an `INDEX.md` that lacks the marker line untouched, because another tool writes that file.

Exit codes: `0` when it wrote or refreshed the file, or wrote nothing for one of the reasons above. `1` when `INDEX.md` is not a regular file or the write failed.

Tests: the topic-recall suite and the vault-fs suite cover it.

## toolkit-vault.json.template

The source template `setup` copies to `~/.claude/toolkit-vault.json` on first setup. Every reader takes the legacy `~/.claude/obsidian-sync.json` when `~/.claude/toolkit-vault.json` is absent. It is config, not an executable — this is what `vault-fs.sh` (and the vault-writing skills) read `vault_path` and `root_folder` from to resolve the vault root.

Fields, by what each observably does: `vault_path` (per-machine, set during setup — the physical vault root), `root_folder` (the toolkit-owned subtree inside the vault; everything the toolkit writes lives under it), `plan_folder_template` (the canonical plan-directory layout the planning workflow creates and other tools can enumerate), and `_readme` (human guidance only, read by nothing). A live config may carry additional legacy or external-consumer fields; the toolkit ignores them and never rewrites the file.

## toolkit-models.json.template

The default layer of per-agent model and effort routing. It is config, not an executable. `resolve-models.sh` reads it first, then the user file `~/.claude/toolkit-models.json`, then the plan note's run options. The result routes Agent-tool spawns through the `agent-model.sh` PreToolUse hook (see `docs/hooks.md`) and Workflow `agent()` calls through the runner scripts, without shadowing the agent files. The user file lists only the agents it re-routes, in the same shape, so later template defaults still reach every other agent.

Fields: `agents` (one key per shipped agent name, each value a `{"model": ..., "effort": ...}` object; model is any Claude Code model alias or full model ID, and the Agent-tool path sends a full ID as the one family alias it names, effort is `low`, `medium`, `high`, `xhigh` or `max`; an empty string leaves the layers below in place; `haiku` is refused) and `_readme` (human guidance only, read by nothing). A user file value can also be a bare string, which sets the model only. An explicit per-call model or effort, or `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, wins over every layer.

## design-detector/

A deterministic, no-LLM detector for AI-generated frontend anti-patterns — most of Impeccable's 46 rules, covering AI-slop tells, accessibility, and quality. It complements the `frontend-designer` agent: build with the agent, then run the detector over the output to catch what slipped through, no API call required.

Invoke it with `node` (not `bash`):

```bash
node "$PLUGIN_ROOT/scripts/design-detector/detect.mjs" <file ...>
```

- **Zero-dependency by default.** Source files (CSS / JS / TSX / Vue / Svelte / HTML-as-text) are scanned in regex mode with nothing to install.
- **Optional HTML-aware mode.** Passing `.html` files uses a fuller CSS-cascade tier if four optional packages (`htmlparser2`, `css-select`, `css-tree`, `domutils`) are installed in `scripts/design-detector/`; without them it falls back to regex mode. Audit those before installing, per the dependency rule.
- **Third-party.** This engine is vendored from Impeccable (Paul Bakaus, Apache-2.0) and attributed — see `scripts/design-detector/LICENSE`, its `NOTICE`, and the repo-root `THIRD-PARTY-NOTICES.md`. It is the one script here that is not first-party toolkit code.
- **Static limits.** It reads authored HTML/CSS, not a rendered page, so it cannot see JS/SPA-injected content, and a few layout rules (`text-overflow`, `line-length`, `body-text-viewport-edge`) need a real browser and do not fire in this static engine.
