# Commands

The toolkit ships eight slash commands in two groups: **setup and vault** helpers, and
on-demand **thinking tools**. This page is the reference for what each does, when to run
it, and what it changes.

## Setup & vault

### `/toolkit-setup`

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

**Example**

    /toolkit-setup

### `/obsidian-topic`

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

**Examples**

    /obsidian-topic "Payment Gateway" my-repo
    /obsidian-topic "Caching Strategy"

### `/override`

Copies a toolkit component — doctrine, rule, agent, or skill — into your global
`~/.claude/` so your version wins for that concern, without editing the plugin.

**Usage** — `/override [type] [name]`. With a name (e.g. `/override conventions`,
`/override code-reviewer`) it auto-detects the type and copies it; with no argument it
lists everything overridable and asks which; with `<type> <name>` (e.g. `/override rules
security`) it forces the type for an ambiguous name.

**What it does** — copies the plugin's version into `~/.claude/<type>/` (a skill is copied
as its whole directory), refusing unknown or ambiguous names and never clobbering an
existing override, then you edit your copy. Doctrine and rules are picked up by the
session-start hook (doctrine announced, a rule's body injected in place of the plugin's);
agents and skills are resolved natively by Claude Code for the bare name (invoke bare, not
`toolkit:<name>`). Safety sections (git-safety, security) may be tightened, not loosened.

**What it changes** — writes into `~/.claude/`. Nothing in the plugin, nothing in git.

**Examples**

    /override
    /override conventions
    /override rules security
    /override code-reviewer

## Thinking tools

On-demand reflection and red-team commands. Each leans into the communication doctrine
(honest over agreeable), and none of them take an action — they audit, reframe, or
question, they do not change files or git state. `/mentor` is a persistent mode; the
rest are one-shot.

### `/glass-box`

An on-demand provenance audit of the last answer, or the one about to be given. It is
the deep, explicit version of the `claim-provenance` doctrine (see the doctrine index):
rather than narrating reasoning, it surfaces only what can actually be checked.

**When to run it** — when an answer feels too confident, an action is hard to undo, or
you want the load-bearing assumption surfaced before you act.

**Usage** — `/glass-box [what to audit]`. With no arguments it audits the most recent
substantive answer in the session; an argument names the specific answer or decision.

**What it surfaces** — exactly three things, nothing more:

1. the load-bearing fact the answer rests on, tagged verified or derived;
2. the unchecked assumption, naming the specific place not looked;
3. the offer to verify a derived fact now, or the answer restated with the assumption
   stated inline.

No confidence scores, no reasoning tableau. If the load-bearing fact is already verified
and nothing rides on an unchecked assumption, it says so in one line and stops.

**What it changes** — nothing. It audits an answer, it does not take an action.

**Examples**

    /glass-box
    /glass-box the migration estimate you just gave

### `/mentor`

Switches on a Socratic learning mode: after each answer it asks one question that pushes
you to think deeper, and keeps going until you understand a concept rather than memorize
it. Unlike the one-shot tools here, this is a persistent mode for the rest of the session.

**When to run it** — when you want to genuinely learn a concept, not just get the answer,
or to work something through with a junior who is missing large parts of the picture.

**Usage** — `/mentor [topic]`. With no argument it applies to the current thread; an
argument names the topic to learn.

**How it behaves** — explains plainly first, then after each step asks one deeper question
(apply it, why it works, what breaks if a condition changes, never bare recall). It will
not advance until you explain it back in your own words, drops to simpler terms when you
are stuck, and asks one question at a time. It runs until you say stop.

**What it changes** — nothing. It is a conversation mode, not an action.

**Example**

    /mentor
    /mentor how database indexes actually work

### `/cold-read`

Reads back the unstated assumptions behind how you have been talking in the conversation
— the blind-spot check. It works only from what you actually said, and surfaces the
premise you are treating as fact, the frame that is hiding options, and the tell you
would not endorse out loud.

**When to run it** — when a direction feels obvious, or before committing to one, to
catch the premises you never examined.

**Usage** — `/cold-read [decision or thread]`. With no argument it reads the whole
conversation so far.

**What it changes** — nothing.

**Example**

    /cold-read
    /cold-read the way I've scoped this migration

### `/mirror-test`

Reads your last message back the way a stranger would hear it, honest not kind — no
benefit of the doubt. Surfaces how it lands, where intent and wording come apart, and the
one change that closes the gap.

**When to run it** — before sending something that matters (a review comment, a message
to a colleague, a ticket) to hear how it actually reads.

**Usage** — `/mirror-test [message or text]`. With no argument it reads your most recent
message.

**What it changes** — nothing.

**Example**

    /mirror-test
    /mirror-test the PR review I just drafted

### `/inversion`

A pre-mortem: assume the plan already failed completely and lay out every way it got
there, unsoftened and worst-case, so the real problems surface while they can still be
fixed. Ranks the failure modes, names the load-bearing risk, and points each top risk at
a concrete fix.

**When to run it** — on a plan or decision before committing to it.

**Usage** — `/inversion [plan or decision]`. With no argument it uses the plan under
discussion.

**Related** — inside the plan-workflow, the `plan-critic` agent red-teams a written plan
as part of planning; `/inversion` is the on-demand version for any plan or idea in
conversation.

**What it changes** — nothing.

**Example**

    /inversion
    /inversion rolling this migration out in one deploy
