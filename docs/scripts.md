# Scripts

The toolkit ships a small set of scripts under `plugins/toolkit/scripts/` — plain
bash and stdlib-only Python, no external dependencies. Skills and the user invoke them
directly rather than reimplementing the logic inline.

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
| `merge-conflict-overview.py` | Overview + side-by-side of git conflict markers | Read-only — never edits, stages, or commits |
| `obsidian-sync.json.template` | Vault config template `toolkit-setup` instantiates to `~/.claude/obsidian-sync.json` | n/a — config, not an executable |

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

## obsidian-sync.json.template

The source template `toolkit-setup` copies to `~/.claude/obsidian-sync.json` on
first setup. It is config, not an executable — this is what `vault-fs.sh` (and the
vault-writing skills) read `vault_path` and `root_folder` from to resolve the vault
root.

Fields: `vault_path` (per-machine, set during setup), `vault_name`, `root_folder`,
`mode`, `plan_folder_template`, `artifact_name_template`, `allowed_artifacts`, and a
`safety` block (`atomic_writes`, `icloud_safe`, `dry_run_default`).
