# Commands

The toolkit ships two slash commands: `/toolkit-setup` and `/obsidian-topic`. This
page is the reference for what each one does, when to run it, and what it changes.

## `/toolkit-setup`

Checks this machine's toolkit setup and guides the user through anything missing.
Safe to re-run anytime — it changes nothing without asking first.

**When to run it** — first-time setup on a new machine, after a plugin update, or
whenever something in the toolkit seems misconfigured.

**What it checks, in order:**

1. **Plugin state** — install location and content version.
2. **Vault config** (needed by `plan-workflow` and `/obsidian-topic`) — validates
   `~/.claude/obsidian-sync.json`: parses as JSON, `vault_path` exists on disk,
   `root_folder` is set, and `plan_folder_template` /
   `project_discovery.target_folder_template` are internally consistent with
   `root_folder`. If the file is missing, offers to create it from the shipped
   template.
3. **GitLab tooling** (needed by `gitlab-mr-review` only) — whether `glab` is
   installed and, if so, its per-host auth status. Never prints a token value.
4. **Optional tooling** — whether `jq` is present.
5. **Permissions and environment** (optional, consent-gated) — three separate
   offers, each applied only on an explicit yes:
   - Prompt-free allow rules for the plugin's `vault-fs.sh` and `git-ro.sh` scripts
     in `~/.claude/settings.json`.
   - Setting `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` in the `env` block (reports,
     never overwrites, a conflicting existing value).
   - A pointer to the plugin's doctrine (`CLAUDE.md` + `README.md`) appended to the
     user's global `~/.claude/CLAUDE.md`.
6. **Local copies that conflict with the plugin** (migration check) — detects
   leftover copy-pasted versions of the setup that now shadow or double-fire
   against the plugin: hook registrations, agents, skills/commands, the
   `review-mr.js` workflow script, and rules. Diffs each local copy against the
   plugin's version before offering removal, and calls out modified copies as
   individual keep-or-discard decisions rather than bundling them with identical
   ones.

Ends with a readiness report table (one row per capability, its status, and what it
still needs) and a one-line verdict.

**What it changes** — nothing, ever, without an explicit yes in that session. Every
offer above is consent-gated, and declined offers are never re-nagged on later runs
(only current state is reported, and only what is still absent is offered). It never
modifies the plugin's own files.

## `/obsidian-topic`

Creates or updates a single topic note in the Obsidian vault — the vault's distilled,
cross-plan knowledge layer for stable concepts (a payment provider, a subsystem, a
recurring pattern). This file is the single source of truth for topic notes; the
`plan-workflow` skill and CLAUDE.md point here rather than duplicating the rules.

**Usage** — `/obsidian-topic <Topic Name> [repo]`. Errors with a usage message if no
topic name is given.

**When to run it** — ad hoc, any time a topic note needs creating or refreshing
outside the normal planning/execution flow. In the normal flow, `plan-workflow` calls
the same process automatically: on every plan, topic recall runs first and every
topic in the plan's Related Topics either resolves to an existing note or gets a stub
created; during execution, durable facts surfaced by the work get folded into the
touched topic notes as part of the work itself, not a finalize step.

**Location** — resolved from `~/.claude/obsidian-sync.json`. New topic notes start in
the current project's directory, `Projects/{repo_name}/<Topic>.md`. A topic gets
promoted to `<root_folder>/Docs/` once a second project links it. Claude never writes
outside `<root_folder>/`.

**Freshness validation** — a topic note is a claim about the world as of its
`updated` timestamp. Before relying on one, at least one `source_refs` entry is
spot-checked against current code. If reality disagrees, the code wins: the note is
corrected and `updated` is bumped, or the disagreement is flagged in the plan — never
silently trusted.

**What it changes** — only files under `<root_folder>/` in the vault (writes go
through an atomic Write-then-`vault-fs.sh mv`). It never touches project source code
or git state, and never invents facts, ticket references, or test data.
