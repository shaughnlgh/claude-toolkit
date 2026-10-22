# Scripts

The toolkit ships a small set of scripts under `plugins/toolkit/scripts/`. Most are plain bash and stdlib-only Python with no dependencies. One is a vendored Node design-detector under `scripts/design-detector/` (the one piece of third-party code here — see below). Skills and the user invoke them directly rather than reimplementing the logic inline.

All of them are called through the installed plugin root, resolved once and reused:

```bash
PLUGIN_ROOT="$(jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json)"
bash "$PLUGIN_ROOT/scripts/<script>.sh" ...
```

Each entry below assumes `$PLUGIN_ROOT` is already resolved this way.

## The set

| Script | What it does | Guardrails |
|---|---|---|
| `vault-fs.sh` | Atomic vault file ops — `rm`, `mv` | Refuses absolute paths, `..` traversal, symlink escape from the vault (canonical containment), non-regular-file targets, missing sources, unknown subcommands |
| `git-ro.sh` | Read-only git in any directory — `status`, `diff`, `log`, `show` | Subcommand allowlist; refuses write options (`--output`/`-o`/`--ext-diff`); neutralizes pager, fsmonitor, ext-diff and textconv (the execute-on-read vectors) |
| `watch-mr.sh` | Waits on one GitLab MR or GitHub PR until its pipeline settles or a bot review lands, then prints one status line | Reads only, through `gh` and `glab`, which hold their own auth; never reads or prints a token; validates every argument; exits on a wall-clock bound |
| `override.sh` | Copy a plugin doctrine, rule, agent, or skill into `~/.claude/` to override it (drives `/override`) | Name only (no paths); refuses unknown/ambiguous names; won't clobber an existing override |
| `merge-conflict-overview.py` | Overview + side-by-side of git conflict markers | Read-only — never edits, stages, or commits |
| `validate-plan.py` | Validates a plan note against the plan-guide contract | Read-only — never edits the note; no network, no config, stdlib only |
| `topic-recall.py` | Lexical topic search over the vault index, with a frontmatter fallback and an optional repo `docs/` source | Read-only against the vault and the repo, stdlib only, skips symlinks and non-regular files, INDEX.md included, reads at most 64 KiB of each scanned note or doc, stops at a 3-second deadline |
| `obsidian-sync.json.template` | Vault config template `setup` instantiates to `~/.claude/obsidian-sync.json` | n/a — config, not an executable |
| `toolkit-models.json.template` | Per-agent model routing config template `setup` instantiates to `~/.claude/toolkit-models.json` | n/a, config, not an executable |
| `design-detector/` | Deterministic, no-LLM detector for AI-generated frontend anti-patterns (most of 46 rules) | Vendored from Impeccable (Apache-2.0, attributed); read-only; zero-dep by default |

## vault-fs.sh

Atomic file ops (`rm`, `mv`) scoped to the Obsidian vault, so skills like `plan-guide` and `handoff` never touch the filesystem with a raw shell command.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" rm <relpath>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" mv <relpath-src> <relpath-dst>
```

The vault root is resolved from `~/.claude/obsidian-sync.json` (`vault_path` + `root_folder` — see the template below). If that file is missing or the resolved root doesn't exist as a directory, the script refuses outright.

Guardrails — this is the point of the script:
- **Refuses absolute paths and traversal lexically.** Any path starting with `/` or containing `..` is rejected before it's joined to the vault root — relative vault paths only.
- **Canonical containment, symlinks included.** Every effective source and destination is resolved to its canonical path (a not-yet-existing destination via its existing parent) and must remain inside the canonical vault root, compared path-aware (`/vault-other` does not count as inside `/vault`). A symlinked directory inside the vault pointing outside it is refused; a symlink resolving to another location inside the vault is allowed. Fails closed with a `refused:` reason when containment cannot be established.
- **Regular files only.** Directory sources and destinations, non-regular files, dangling symlink destinations, and a missing source are all refused.
- **`mv` replaces an existing destination file by design.** Write-to-`.tmp.md` then `mv` is the toolkit's atomic-write mechanism — do not expect a no-clobber guard.
- **Unknown subcommands are refused**, not silently ignored.
- Every path refusal (traversal, containment, directory ops, missing source, missing destination directory, non-regular file, dangling symlink destination) names the resolved vault root and the expected relative form (`Projects/<repo>/...`). The unknown-subcommand refusal is the one exception; it carries no hint.

What it does NOT provide, deliberately: directory creation, locking or concurrency control, content/frontmatter validation, or a general filesystem sandbox beyond these two operations.

Tests: `bash plugins/toolkit/scripts/tests/vault-fs/run-tests.sh` (19 behavior cases in a temporary vault; also run by `verify.sh`).

## git-ro.sh

Read-only git access in any directory, without granting a general-purpose `git` call.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/git-ro.sh" <dir> status|diff|log|show [args]
```

Guardrails — this is the point of the script: only `status`, `diff`, `log`, and `show` are accepted as the subcommand. Anything else (`commit`, `push`, `reset`, `checkout`, etc.) is refused before it ever reaches `git`. Within those subcommands the write/exec options `--output`/`-o` (write a file), `--ext-diff` (external diff command), and `--textconv` (textconv driver — refusing it also stops a caller overriding the forced `--no-textconv`) are refused. And because a target repo's own config can execute on a "read", the call forces `core.pager=cat`, `core.fsmonitor=false`, a null `core.hooksPath`, and `--no-ext-diff --no-textconv` on the diff-capable subcommands — so `git status`/`diff`/`log`/`show` cannot run a pager, fsmonitor, external-diff, or textconv command from the target repo. The target directory is passed straight to `git -C`, so it works against any repo on disk. Note: this makes the wrapper safe against a repo you do not fully trust for these four read operations — it is not a general git sandbox.

Tests: `bash plugins/toolkit/scripts/tests/git-ro/run-tests.sh` (12 behavior cases in a temporary repo whose config wires every execute-on-read vector to a marker script; also run by `verify.sh`).

## watch-mr.sh

Waits on one MR or PR until a terminal condition and prints one status line to stdout, once, at exit. Errors go to stderr.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/watch-mr.sh" <github|gitlab> <remotePath> <number> <pipeline|threads> --sha <sha> [--bound <n>] [--stuck <n>] [--interval <seconds>] [--bot <login>]...
```

- `remotePath` is `owner/repo` or `group/sub/repo`. The script URL-encodes the whole path once for the GitLab API. `glab` resolves the GitLab host from the git remote of the working directory, or uses its default host when run elsewhere, so run the script from the repo.
- `number` is the PR number on GitHub and the MR iid on GitLab.
- `--sha` is required in both modes. It names the commit the result must belong to. The script lowercases it. A short sha matches the head by prefix, and once the script sees the full head sha, later rounds and reads compare against that.
- `--bound` and `--stuck` take minutes, or seconds with a trailing `s` (`9`, `20s`). `--bound` defaults to 180 and `--stuck` to 10. `--stuck` applies to pipeline mode only.
- `--interval` is the number of seconds between polling rounds and defaults to 30, with a floor of 1. The first round runs at once.
- `--bot` names a login whose review or note counts and can repeat. With one or more `--bot` logins, only those logins count, compared with any trailing `[bot]` removed from both sides, so `coderabbitai` matches `coderabbitai[bot]`. Without `--bot`, GitHub threads mode counts an author whose `user.type` is `Bot`. GitLab threads mode requires `--bot`, because the GitLab notes API carries no bot flag on its basic user object.

| Exit | Line | Meaning |
|---|---|---|
| 0 | `GREEN <sha>` | pipeline mode: the pipeline for `<sha>` is `success` on GitLab, or every check passed or was skipped on GitHub |
| 0 | `LANDED <sha> <author>` | threads mode: on GitHub, a bot review whose commit is `<sha>`; on GitLab, a non-system note from a `--bot` login created at or after the anchor, which is the head pipeline's creation time or, without a pipeline, the commit date. A note with a `position.head_sha`, such as a diff note, counts only when that sha is the head. Issue comments on GitHub never count. |
| 10 | `RED <sha> <names>` | pipeline mode: a job failed, was cancelled, or timed out; `<names>` is the comma-joined list of those jobs |
| 11 | `STUCK <sha> <minutes>` | pipeline mode: for `--stuck`, at least one job exists and every job is terminal while the pipeline status is not. On GitHub the jobs are the Actions runs for `<sha>`, so a repo whose checks come only from another CI never reads as stuck. On GitLab the jobs are those outside the `external` stage, so an empty job list while the pipeline is being created never reads as stuck. |
| 12 | `BOUND <sha> <minutes>` | `--bound` elapsed in either mode |
| 13 | `NONE <sha>` | pipeline mode: no pipeline for `<sha>` exists at the bound, or the pipeline for `<sha>` is `skipped` |
| 14 | `MOVED <sha> <newHeadSha>` | the MR or PR head is no longer `<sha>`; exits on the first round that sees it |
| 2 | (stderr message) | usage error: missing arguments, unknown host, unknown mode, bad number, missing or bad `--sha`, bad remotePath, bad duration, bad interval, unknown option, missing option value, or GitLab threads mode without `--bot` |
| 3 | (stderr message) | tool error: `jq` is not on PATH, checked before any API call, or `gh` or `glab` failed five rounds in a row; the last error text goes to stderr |

Known limit: on GitLab, the first note from a listed login after the anchor lands, and that note can be the bot's in-progress note. A GitLab repo that needs the merge held for the review must wire the bot as an external pipeline job and let the pipeline wait cover it.

The script never exits 1. Codes 0 and 10 to 14 are outcomes, and codes 2 and 3 are failures of the script itself. `<minutes>` is the whole minutes elapsed: since the start for `BOUND`, and since the stuck condition first held for `STUCK`.

The ship-runner pipeline and threads verifiers run it as one blocking call with `--bound 9`, and the ship-flow conductor runs it as a background command with `--bound 180` to wait out a pending pipeline or review.

Tests: `bash plugins/toolkit/scripts/tests/watch-mr/run-tests.sh` (52 behavior cases against stub `gh` and `glab` executables that answer from per-round fixtures; also run by `verify.sh`).

## override.sh

Backs the `/override` command. Copies a plugin **doctrine, rule, agent, or skill** into `~/.claude/` so your copy overrides the plugin's for that concern.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/override.sh" [type] [name]
```

With no arguments it lists everything overridable, grouped by type. With a name it auto-detects the type and copies it (doctrine/rules/agents as a single `.md`, a skill as its whole directory); with a `<type> <name>` pair it forces the type for an ambiguous name (`security` is both a doctrine and a rule). How each takes effect: doctrine and rules are picked up by the session-start hook (doctrine announced, a rule's body injected in place of the plugin's); agents and skills are resolved natively by Claude Code for the bare name. Guardrails: name only (no paths or `..`), refuses unknown or ambiguous names, and never clobbers an existing override. Self-locating, so it needs no config.

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

Tests: `bash plugins/toolkit/scripts/tests/validate-plan/run-tests.sh` (37 behavior cases over 36 fixtures plus a direct nonexistent-path case; also run by `verify.sh`).

## topic-recall.py

Lexical search over the vault's topic notes and, when asked, a repo's `docs/` folder. Session start, plan-guide, crawl, and execution-guide run it to recall what earlier sessions recorded about a repo or a task.

Invoke:

```bash
python3 "$PLUGIN_ROOT/scripts/topic-recall.py" [--repo <name>] [--repo-root <path>] [--top N] [--format text|json] [--version] [query words...]
```

Defaults are `--top 10` and `--format text`. The vault root comes from `~/.claude/obsidian-sync.json` (`vault_path` plus `root_folder`).

`--version` prints the toolkit content version to stdout and exits 0 before the script reads any config. The script resolves symlinks in its own path and treats the directory above `scripts/` as the plugin root. If the parent of that root is named `toolkit`, as in the plugin cache, the script prints the name of the root directory, which is the install version. Otherwise it prints `git rev-parse --short=12 HEAD` of the root, or `unknown` if git is missing or finds no commit.

Source: the script reads `<vault_path>/<root_folder>/INDEX.md`, which Mission Control writes. The toolkit never writes it. Only rows under `## Topics by domain` count, up to the next level-2 heading, so the plan links under `## Projects` stay out. The script reads the parenthesized meta of each row by content, not by position. A segment that starts with `verified` or `unverified` is the verified state, a segment that equals `stale` after the script strips the `⚠` sign and whitespace marks the row stale, and any other segment is the comma-separated repo list. Mission Control omits the repo segment when a topic has no repos, so rows ending in `(unverified)` or `(verified 2026-08-10; ⚠ stale)` parse with no repos. The script reads a regular INDEX.md whole. If INDEX.md is missing, unreadable, a symlink, not a regular file, or has no topic rows, the script walks the root folder instead and keeps files whose frontmatter says `type: topic`. If INDEX.md exists but is a symlink, is not a regular file, or cannot be read, the script prints one line naming the path to stderr before it falls back. Text output from the fallback starts with `source: frontmatter scan (INDEX.md unavailable)`, and every fallback row reports `stale` as false.

File reads: the frontmatter fallback walk and the repo docs walk skip symlinked files, symlinked directories, and any entry that is not a regular file, such as a FIFO or a device. The script reads at most 64 KiB of each file, drops a leading UTF-8 byte order mark, and keeps at most the first 120 lines of that. It ignores frontmatter that does not close within those lines. Frontmatter values can be plain scalars, `[a, b]` lists, `- item` lists, or YAML block scalars (`>`, `>-`, `>+`, `|`, `|-`, `|+`). The script joins the indented lines of a block scalar with spaces.

Repo source: if `--repo-root <path>` is given, the script adds the Markdown files under `<path>/docs` to the vault rows before ranking. The script makes the path absolute first, so `--repo-root .` names the repo of the current directory. If `--repo` is not passed, it defaults to the basename of that absolute path. The walk visits directories and files in sorted order, skips directories that start with `.` or are named `node_modules`, keeps files at most 4 path components below `docs/` (the files `find -maxdepth 4` lists), and skips `.md` files that start with `.`. The walk lists the files of a directory before it enters its subdirectories, and the 400-file cap applies in that order, so the files directly under `docs/` count first. A missing `docs/` adds nothing. The title is the frontmatter `title`, else the first `# ` heading after the frontmatter, else the file name without `.md`. The summary is the frontmatter `summary`, else the first paragraph after the frontmatter that does not start with `#` or `<!--`. The script joins the lines of that paragraph with spaces up to the first blank line. Either summary is cut at 200 characters. A doc whose frontmatter does not close within the first 120 lines gets the file name as its title and an empty summary. Each repo row lists the repo basename as its only repo, reports `verified` as `repo`, and carries `source: repo`. Vault rows carry `source: vault`.

Scoring: the script lower-cases the query, splits it on `[a-z0-9]+`, and drops tokens shorter than 3 characters. Each distinct query token found in a title adds 8, and each distinct query token found in a summary adds 3. For a vault row, a `--repo` value listed in the row's repos adds 6 once. A repo row gets no repo bonus, because every repo row lists the repo. The repo row for `<repo-root>/docs/README.md` adds 2 if it has at least one token hit, so the docs index leads its folder on equal hits. With no query words, every repo row scores 0. Rows that score 0 are dropped. Hits sort by score, highest first, then by title. A stale or unverified row scores the same as a verified one.

Output: text prints three lines per hit. The first line is the title, the repos in brackets, then `[vault]` and the verified state for a vault row, or `[repo]` for a repo row, and it ends with `(score N)`. The summary and the absolute note path follow. JSON prints a list of objects with `title`, `summary`, `repos`, `verified`, `stale`, `path`, `source`, and `score`. The path is blank in JSON, and `(no local file)` in text, when no `<Title>.md` exists under the root folder, for example when iCloud has evicted the note. The script writes stdout as UTF-8 whatever the locale, and replaces any character it cannot encode.

Exit codes: `0` with hits or with none, or after `--version`, `2` if `~/.claude/obsidian-sync.json` is missing or unreadable, or the vault root is not a directory, and `3` if the run passes its internal 3-second deadline. The script sets that deadline with `SIGALRM`, so a platform without `SIGALRM` has no exit 3. On exit 2 or 3 the reason goes to stderr and nothing goes to stdout.

Embedding seam: `rank()` is the only function an embedding backend replaces. It receives the candidates, the query words, the repo name, and the docs index path. Loading, path resolution, and rendering stay as they are, so the CLI and its output do not change.

Tests: `bash plugins/toolkit/scripts/tests/topic-recall/run-tests.sh` (45 behavior cases in temporary vaults and repos with an overridden HOME). `verify.sh` also runs it.

## obsidian-sync.json.template

The source template `setup` copies to `~/.claude/obsidian-sync.json` on first setup. It is config, not an executable — this is what `vault-fs.sh` (and the vault-writing skills) read `vault_path` and `root_folder` from to resolve the vault root.

Fields, by what each observably does: `vault_path` (per-machine, set during setup — the physical vault root), `root_folder` (the toolkit-owned subtree inside the vault; everything the toolkit writes lives under it), `plan_folder_template` (the canonical plan-directory layout the planning workflow creates and consumers like mc-catchup enumerate), and `_readme` (human guidance only, read by nothing). A live config may carry additional legacy or external-consumer fields; the toolkit ignores them and never rewrites the file.

## toolkit-models.json.template

The source template `setup` copies to `~/.claude/toolkit-models.json`. It is config, not an executable. The `agent-model.sh` PreToolUse hook (see `docs/hooks.md`) reads it to re-route a named agent's model on an Agent-tool spawn, without shadowing the agent file itself.

Fields: `agents` (one key per shipped agent name; an empty string keeps the model set in that agent's own frontmatter; any Claude Code model alias or full model ID is accepted; `haiku` is refused) and `_readme` (human guidance only, read by nothing). An explicit per-call model, or `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, wins over this file. It applies to Agent-tool spawns only, not Workflow scripts.

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
