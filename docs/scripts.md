# Scripts

The toolkit ships a small set of scripts under `plugins/toolkit/scripts/`. Most are
plain bash and stdlib-only Python with no dependencies. One is a vendored Node
design-detector under `scripts/design-detector/` (the one piece of third-party code
here — see below). Skills and the user invoke them directly rather than
reimplementing the logic inline.

All of them are called through the installed plugin root, resolved once and reused:

```bash
PLUGIN_ROOT="$(jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json)"
bash "$PLUGIN_ROOT/scripts/<script>.sh" ...
```

Each entry below assumes `$PLUGIN_ROOT` is already resolved this way.

## The set

| Script | What it does | Guardrails |
|---|---|---|
| `vault-fs.sh` | Atomic vault file ops — `rm`, `mv` | Refuses absolute paths, `..` traversal, non-regular-file targets, missing sources, unknown subcommands |
| `git-ro.sh` | Read-only git in any directory — `status`, `diff`, `log`, `show` | Refuses any subcommand not on that allowlist |
| `override.sh` | Copy a plugin doctrine, rule, agent, or skill into `~/.claude/` to override it (drives `/override`) | Name only (no paths); refuses unknown/ambiguous names; won't clobber an existing override |
| `merge-conflict-overview.py` | Overview + side-by-side of git conflict markers | Read-only — never edits, stages, or commits |
| `validate-plan.py` | Validates a plan note against the plan-workflow contract | Read-only — never edits the note; no network, no config, stdlib only |
| `obsidian-sync.json.template` | Vault config template `toolkit-setup` instantiates to `~/.claude/obsidian-sync.json` | n/a — config, not an executable |
| `design-detector/` | Deterministic, no-LLM detector for AI-generated frontend anti-patterns (most of 46 rules) | Vendored from Impeccable (Apache-2.0, attributed); read-only; zero-dep by default |

## vault-fs.sh

Atomic file ops (`rm`, `mv`) scoped to the Obsidian vault, so skills like
`plan-workflow` and `handoff` never touch the filesystem with a raw shell command.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" rm <relpath>
bash "$PLUGIN_ROOT/scripts/vault-fs.sh" mv <relpath-src> <relpath-dst>
```

The vault root is resolved from `~/.claude/obsidian-sync.json` (`vault_path` +
`root_folder` — see the template below). If that file is missing or the resolved
root doesn't exist as a directory, the script refuses outright.

Guardrails — this is the point of the script:
- **Refuses absolute paths and traversal.** Any path starting with `/` or containing
  `..` is rejected before it's joined to the vault root — relative vault paths only.
- **`rm` only removes regular files.** Directories are rejected. The check is `[ -f ]`,
  which follows a symlink to a regular file, so it is not itself a symlink guard.
- **`mv` refuses a missing source.**
- **Unknown subcommands are refused**, not silently ignored.

## git-ro.sh

Read-only git access in any directory, without granting a general-purpose `git`
call.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/git-ro.sh" <dir> status|diff|log|show [args]
```

Guardrails — this is the point of the script: only `status`, `diff`, `log`, and
`show` are accepted as the subcommand. Anything else (`commit`, `push`, `reset`,
`checkout`, etc.) is refused before it ever reaches `git`. The target directory is
passed straight to `git -C`, so it works against any repo on disk, not just the
current project.

## override.sh

Backs the `/override` command. Copies a plugin **doctrine, rule, agent, or skill** into
`~/.claude/` so your copy overrides the plugin's for that concern.

Invoke:

```bash
bash "$PLUGIN_ROOT/scripts/override.sh" [type] [name]
```

With no arguments it lists everything overridable, grouped by type. With a name it
auto-detects the type and copies it (doctrine/rules/agents as a single `.md`, a skill as
its whole directory); with a `<type> <name>` pair it forces the type for an ambiguous
name (`security` is both a doctrine and a rule). How each takes effect: doctrine and
rules are picked up by the session-start hook (doctrine announced, a rule's body injected
in place of the plugin's); agents and skills are resolved natively by Claude Code for the
bare name. Guardrails: name only (no paths or `..`), refuses unknown or ambiguous names,
and never clobbers an existing override. Self-locating, so it needs no config.

## merge-conflict-overview.py

The merge-conflict overview helper the `resolving-merge-conflicts` skill drives
before it resolves anything. It parses `<<<<<<<` / `|||||||` / `=======` / `>>>>>>>`
markers and prints two things: a summary (conflicted file count, hunks per file,
line counts per side) and a per-hunk view — side-by-side for a two-way conflict,
stacked for a three-way (`diff3`) conflict or a narrow terminal.

Invoke:

```bash
python3 "$PLUGIN_ROOT/scripts/merge-conflict-overview.py" [file ...]
```

With no arguments it discovers conflicted files itself via
`git diff --name-only --diff-filter=U`. Pass explicit paths to inspect a subset.

Notes:
- **Stdlib only** — `argparse`, `shutil`, `subprocess`, `sys`. No dependencies to
  install or vet.
- **Read-only.** It only reads and prints; it never edits a file, runs `git add`, or
  commits. Resolution and confirmation stay with the skill and the human.
- Binary or unreadable files are skipped with a note on stderr; files with no
  conflict markers are skipped the same way.

## validate-plan.py

Read-only validator for the canonical plan-note contract defined by the
`plan-workflow` skill. Takes exactly one plan-note path; never writes; needs no
network, vault config, or packages (python3 standard library only).

    python3 <plugin-root>/scripts/validate-plan.py "<vault>/.../plan - my-slug.md"

Exit codes: `0` valid, `1` contract violation(s) (each printed as
`VIOLATION: ...`), `2` usage error, unreadable path, or malformed frontmatter.

**What it proves (mechanical contract only):** filename matches
`plan - <slug>.md` with a kebab-case slug; `plan:` matches the filename;
`type: plan`; all 18 required frontmatter keys are present (`modules`/`repos`
are validly blank for single-repo plans, but the keys must exist);
`status` is a lifecycle value (`planning`, `review`, `approved`, `in-progress`,
`completed`, `blocked`, `abandoned`); a `parent:` child sits in its parent's
directory beside the parent note; session entries carry a date and summary with
unique non-blank ids (blank ids allowed, never counted as duplicates); the
twelve required headings exist; and nothing links the retired `mr-description`
artifact. Unknown frontmatter keys (Mission Control's `worklogs`, `tracking`,
`mockups`, …) are tolerated whatever their shape.

**What it deliberately does not judge:** prose quality, whether Implementation
Steps show real code, plan completeness, topic-link resolution, or
status-transition ordering — those remain human and model judgment (plan-critic
and the approval gate).

**Parser note:** the frontmatter parser is deliberately narrow — the exact
subset the toolkit and Mission Control produce (top-level scalars, lists of
scalars, lists of flat mappings). Unsupported structure under a *validated* key
fails loudly with exit 2 instead of being silently misparsed.

When it runs: the `plan-workflow` skill requires a passing validation after
every plan-note write, before presenting a plan for approval, before starting
execution, and at session closure.

Tests: `bash plugins/toolkit/scripts/tests/validate-plan/run-tests.sh`
(18 behavior fixtures; also run by `verify.sh`).

## obsidian-sync.json.template

The source template `toolkit-setup` copies to `~/.claude/obsidian-sync.json` on
first setup. It is config, not an executable — this is what `vault-fs.sh` (and the
vault-writing skills) read `vault_path` and `root_folder` from to resolve the vault
root.

Fields, by what each observably does: `vault_path` (per-machine, set during
setup — the physical vault root), `root_folder` (the toolkit-owned subtree
inside the vault; everything the toolkit writes lives under it),
`plan_folder_template` (the canonical plan-directory layout the planning
workflow creates and consumers like mc-catchup enumerate), and `_readme`
(human guidance only, read by nothing). A live config may carry additional
legacy or external-consumer fields; the toolkit ignores them and never
rewrites the file.

## design-detector/

A deterministic, no-LLM detector for AI-generated frontend anti-patterns — most of
Impeccable's 46 rules, covering AI-slop tells, accessibility, and quality. It complements the `frontend-designer` agent: build with the agent, then run
the detector over the output to catch what slipped through, no API call required.

Invoke it with `node` (not `bash`):

```bash
node "$PLUGIN_ROOT/scripts/design-detector/detect.mjs" <file ...>
```

- **Zero-dependency by default.** Source files (CSS / JS / TSX / Vue / Svelte /
  HTML-as-text) are scanned in regex mode with nothing to install.
- **Optional HTML-aware mode.** Passing `.html` files uses a fuller CSS-cascade tier if
  four optional packages (`htmlparser2`, `css-select`, `css-tree`, `domutils`) are
  installed in `scripts/design-detector/`; without them it falls back to regex mode.
  Audit those before installing, per the dependency rule.
- **Third-party.** This engine is vendored from Impeccable (Paul Bakaus, Apache-2.0) and
  attributed — see `scripts/design-detector/LICENSE`, its `NOTICE`, and the repo-root
  `THIRD-PARTY-NOTICES.md`. It is the one script here that is not first-party toolkit code.
- **Static limits.** It reads authored HTML/CSS, not a rendered page, so it cannot see
  JS/SPA-injected content, and a few layout rules (`text-overflow`, `line-length`,
  `body-text-viewport-edge`) need a real browser and do not fire in this static engine.
