---
title: Plans span several repos
summary: A plan note whose repo set holds two or more repos runs from a session started in the projects root, with one worktree per top-level repo, one runner run and one combined capture, each repo's rule files passed to every worker by path, and a ship flow that opens every repo's PR or MR and merges them in ship order only once every one was ready.
type: decision
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-11-10
---

# 0010. Plans span several repos

Date: 2026-11-10

Status: Accepted

## Context

`plan-guide` lets a plan note list sibling top-level repos under `repos:` and nested vendor modules under `modules:`, but the execute and ship flows read one repo: one `repoRoot`, one capture, one shipping hash, and one PR or MR. A session isolated in a worktree cannot run git against another repo, because the harness guard refuses a command that targets git outside the worktree. A session loads `.claude/settings.json` hooks and `.claude/rules/` only for the directory it starts in. Composer installs a module under an ignored `vendor/`, and it installs the dist archive when the source clone fails, so a worktree install can leave no module git checkout.

## Decision

- `plan-guide` § Repos and modules defines the repo set, the module path, the branch default, and the ship order: the `repos:` list order, with each repo's modules directly before it.
- A several-repos note runs from a session started in the projects root. Section 2b of the `execute-flow` skill opens one worktree per top-level repo with `git fetch` and `git worktree add` and never calls EnterWorktree, so the worktree guard never applies.
- The runner's first stage, `edit:check`, has one implementer per top-level root write and remove one file through the same Workflow agent path as the real edits.
- Section 2b reads each repo's `CLAUDE.md`, `AGENTS.md` and `.claude/rules/*.md` from its main checkout and passes their paths in the runner's `repos` arg, so every worker and reviewer reads the rules of each root it touches. A repo that registers hooks stops the run until its `CLAUDE.md` carries a `Several-repos hooks:` line that says how its checks are covered.
- The doc pass and the remember pass keep each repo's docs under that repo's root, and the runner blocks on a doc path under no root.
- A nested module checkout comes from `composer reinstall --prefer-source` in the project worktree, then a switch to the module's branch, and the flow reads `.git` after the install, never its exit code. A project whose `CLAUDE.md` carries a `Module checkout path:` line gets a worktree of each module's existing checkout under the projects root instead. The flow never clones a module.
- One runner run implements, validates and reviews every repo, and one combined capture from `slice-capture.py` feeds one panel, so a contract break across repos is one finding. Every path is relative to the run root, the deepest directory that holds every root. The shipping record keeps one hash per repo, from the capture's part hashes.
- The ship flow's first pass takes every repo to an open PR or MR through the pipeline watch and the thread stage, and reads whether each one would merge. Its second pass merges in ship order only when every repo was ready. A project with modules stops at mr, because the owner releases each module and moves the project's constraint by hand.
- The seat run stays single-repo. A several-repos note's steps that need the running local stack stay deferred, and the user accepts each one by hand.

## Consequences

A several-repos run starts from the projects root, and the ship flow's note lines carry a `<repo>: ` prefix. A repo's own hooks do not run during the edits, and the flow does not verify the `Several-repos hooks:` line. When the harness refuses the first edit, the run stops at `edit:check`. The classifier judges every later write again, so a later refusal blocks the run at that stage, and a journal resume continues it once the refusal is settled ([0011](0011-execute-flow-caps-runs-per-plan.md)). A module install that falls back to the dist archive, and a project hook that refuses edits under a module path, each stop the run by name. The second pass merges one repo at a time, so when a later merge fails, an earlier repo stays merged, and the report names the Revert action on its PR or MR, because an automatic revert would push to a default branch with no review. A repo whose pipeline needs an earlier repo merged first goes red in the first pass, so nothing merges and the owner merges that pair by hand. No seat run covers such a note, so the user runs its stack steps and records each one as accepted. The several-repos path is proven by the several-repos and slice-capture fixture suites and the runner suites, and has not yet run live in a session.
