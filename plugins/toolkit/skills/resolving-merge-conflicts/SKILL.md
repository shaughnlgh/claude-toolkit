---
name: resolving-merge-conflicts
description: >-
  Use when the user explicitly asks to resolve or help with a git merge or rebase
  conflict, or when the user is in a conflicted merge or rebase and asks for help
  moving past it. Produces an overview and side-by-side view of each conflict, works
  out each side's intent, and proposes a resolution that the human must confirm before
  any file is written. Do not fire automatically on every git operation or on a clean
  merge/rebase with no conflicts.
---

# Resolving Merge Conflicts

This skill helps resolve git merge or rebase conflicts by first showing what is
conflicted, then working out what each side was trying to do, then proposing a
resolution the human confirms before anything is written.

Scope, stated honestly: this gives an overview of the conflicts, a side-by-side (or
clearly labeled stacked) view of each hunk, and an intent-based proposed resolution.
It is NOT an interactive split-screen write-back GUI like IntelliJ's three-pane merge
tool. There is no live editing surface here, no drag-to-pick-a-side widget. If that
kind of tool is what's wanted, it is a separate local tool and out of scope for this
skill.

## 1. Run the overview first

Before touching any file, see the scope of the conflict. Resolve the current installed
plugin root the same way the toolkit's other scripts are invoked, then run the helper:

```
jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json
python3 <plugin-root>/scripts/merge-conflict-overview.py
```

With no path arguments the helper discovers conflicted files itself
(`git diff --name-only --diff-filter=U`). Pass specific paths if only some files matter
right now. Read the overview's file count and per-hunk line counts before going
further, this is what tells you (and the user) how big the job is.

## 2. Work out intent per hunk

For each hunk, read both sides (and the base, if diff3 markers are present) and state
in plain language what each side was trying to do before proposing anything. Do not
jump straight to a merged result. A short pattern to follow per hunk:

- Ours intent: <one line>
- Theirs intent: <one line>
- Proposed resolution: <what combines or picks between them, and why>

Ground the intent in the surrounding code, the commit messages on each side
(`git log`, read-only), and the file's own context, not guesswork from the fragment
alone.

## 3. Propose, then require explicit confirmation before writing

Present the proposed resolution per file, all hunks together, before writing anything.
Never auto-resolve silently and never pick a side blindly just because it's "ours" or
"theirs" by convention. Ask for explicit confirmation on each file's resolution before
writing it. Silence, a vague "looks fine", or moving on to the next file is not
confirmation.

## 4. Flag genuine ambiguity, hand it to the human

If a hunk's intent cannot be worked out confidently (both sides plausible, intent
unclear from the diff and surrounding code, or the two sides look like they're solving
different problems), say so plainly and describe the fork. Do not force a resolution
onto an ambiguous hunk. Let the human decide, and wait for their answer before
proposing that hunk's resolution.

## 5. Write, then verify no markers remain

Only after the human confirms a file's resolution: write the file with the conflict
markers removed and the agreed content in place. Then re-run the helper (or
`git status`) to confirm the file no longer shows as conflicted and no markers remain
in it.

## Boundary

This skill does not run `git add`, does not commit, and does not continue the merge or
rebase (`git merge --continue`, `git rebase --continue`). Those stay with the human,
matching the toolkit's git-safety doctrine (read-only git only: `status`, `diff`,
`log`, `show`). It also does not resolve a hunk without the explicit confirmation step
in section 3, even if the resolution looks obvious.
