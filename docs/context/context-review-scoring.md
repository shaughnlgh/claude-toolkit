---
title: Review scoring
summary: How the review panel scores, verifies, and routes findings, how the execute runner picks the panel and caps the fix loop, and the constraints a change to those rules must keep.
type: context
status: active
owner: Shaughn
last_reviewed: 2026-10-19
source_refs:
  - plugins/toolkit/workflows/review-mr.js
  - plugins/toolkit/workflows/execute-runner.js
  - plugins/toolkit/workflows/tests/review-mr/
  - plugins/toolkit/workflows/tests/execute-runner/
  - plugins/toolkit/skills/execute-flow/SKILL.md
  - plugins/toolkit/skills/red-team/SKILL.md
  - REVIEW.md
  - verify.sh
---
<!-- managed-by: toolkit -->

# Review scoring

The `review-mr` workflow scores each finding, verifies it in batches, and routes it by the verifier's verdict. The `execute-runner` workflow picks the panel by path and caps the fix loop at one round. What the scripts take and return is in [workflows.md](../workflows.md). This page lists the rules and the constraints a change to them must keep. The cost rationale is in [context-economics.md](../context-economics.md).

## Scores and the threshold

- A reviewer gives each finding an impact, a likelihood, and a confidence from 0 to 1. The score is 0.5 impact + 0.3 likelihood + 0.2 confidence, each clamped to 0 to 1, rounded to two decimals so that test fixtures compare exactly.
- The threshold is 0.6. The Anthropic code-review plugin cuts a single 0 to 100 confidence at 80. This toolkit cuts a weighted composite at 0.6 instead, because a verifier reproduces each finding at or above it, so a lower cut costs a reproduction, not a false report.
- `scoreOf`, `clamp`, `round2`, `cited`, the `unit` schema, and the `TAG` enum are duplicated in `review-mr.js` and `execute-runner.js`, because workflow scripts share no module. A change to the weights or the tags means editing both files.

## Batched verification

- Each dimension gets one `toolkit:verifier` per chunk of eight cited findings, so the verifier count is bounded by dimensions times chunks, not by findings. Eight findings against the verifier's 150-turn cap leave about eighteen turns per reproduction.
- The verifier returns one verdict per finding by the index its chunk shows. Indexes restart at 0 in each chunk. A verifier that renumbers routes verdicts to the wrong findings.
- A finding the verifier omits goes to `unverified` with the reason `no verdict`. A chunk whose verifier returns nothing puts the dimension in `verifierDead` and the chunk's findings in `unverified` with the reason `verifier died`. `verifierDead` names a dimension as `dead` does, a registry reviewer by its agent type and a custom dimension by its key. `execute-runner.js` blocks on a non-empty `verifierDead`, so a dead verifier never lets a slice finish with an unchecked dimension.
- The verifier owns `finalTag`, `finalScore`, and `reproduction`. `reproduction` holds the command or trace the verifier ran and the output it saw, and is empty when it ran nothing. The script derives `reproduced` from a non-empty `reproduction`, and the verdict schema carries no boolean for it, because a self-reported boolean cannot be checked.
- A verifier that raises a finding from below 0.6 to 0.6 or above must reproduce it first, and the verifier prompt allows a reproduction only by tracing the code or by running commands in a fresh fixture under the system temp directory outside `repoRoot`, which the verifier never modifies.

## Routing

- A real finding with `finalTag` `pre-existing` goes to `preExisting`, whatever its score. It is listed for a ticket and never fixed in the slice.
- Any other real finding at `finalScore` 0.6 or above goes to `confirmed` when its `reproduction` is not empty, and to `unverified` with the reason `not reproduced` otherwise. An unreproduced finding goes to the user as a question, never to the fix round and never to the floor.
- Any other real finding below 0.6 is a nit. The five with the highest `finalScore` go to `nits`, and the rest go to `dropped` with the reason `nit cap`.
- A finding with no citation goes to `dropped` with the reason `no citation` before any verifier sees it. `citation` stays out of the schema's required list, because a missing required field makes the runtime reject the whole reviewer return.
- The reviewer's tag is advisory. The verifier retags a nit with real impact as important, an important style finding as nit, and a pre-existing claim that the diff's removed and context lines do not carry as important.

## Fix round and the loop cap

- The fix round takes the confirmed findings under `CONFIRMED FINDINGS:` with the class sentence: fix every instance of that class of defect in the slice, not one line.
- The nits ride the same round under `NITS:`, each entry marked `reproduced` or `not reproduced`, because a nit below 0.6 may carry a reproduction. They are fixed only at the cited line and only when the tree confirms them. They ride only when `confirmed` is not empty, because the round, its recheck, and `verify:final` then run anyway. A later round runs only while a confirmed finding stays open, so open nits alone never start one. When `confirmed` is empty, the nits pass through to the user's To settle list and no round is spent.
- When confirmed findings stay open after `maxFixRounds`, the runner blocks with the step-back sentence, which tells the author to reconsider the approach rather than run another round. Open nits never block.

## Panel by path

- The runner picks the panel from the capture paths plus the implementers' changed paths. A high-risk path picks all six reviewers. A non-empty path list where every path is under `docs/` or is a top-level `.md` file, such as `README.md`, picks `toolkit:code-reviewer` alone. Any other `.md` path, such as a `SKILL.md` or an agent file, is not docs only, because it carries commands or frontmatter. Anything else picks the standing three. High risk wins over docs only.
- The built-in high-risk prefixes are `plugins/toolkit/hooks/`, `plugins/toolkit/scripts/`, `plugins/toolkit/workflows/`, and `.github/`. They name this repo's paths, so the rule is inert in a repo without them, and that repo's `REVIEW.md` is its seam.
- Each bullet under `## High-risk paths` in `REVIEW.md` adds its first token, with backticks, quotes, and trailing punctuation stripped. Two parsers read that bullet form: `bullets()` in `execute-runner.js` and the awk line in `verify.sh`, which fails when `REVIEW.md` is missing, when the section is missing or holds no bullet, or when a listed path does not exist. A change to the bullet form means editing both.
- This repo's list holds the enforcement surfaces only: the four built-ins plus `verify.sh` and `REVIEW.md`. A slice that touches only skill, agent, command, or doctrine prose runs the standing three, because reviewers are the expensive agents. Add a path when a live run shows that its tier was too thin.
- Both parsers need the exact heading `## High-risk paths`. They differ in two ways. `sectionIn()` in `execute-runner.js` trims whitespace, so it accepts trailing spaces after the heading and indented bullets, and it skips headings inside a code fence. The awk line in `verify.sh` does neither, so it fails on a heading with trailing spaces and ignores an indented bullet.
- When the runner finds no `## High-risk paths` section, or the section holds no bullet, it uses the built-in list and adds no `blocked` sentence. The `verify.sh` check is the only guard against a renamed or emptied section.

## REVIEW.md

- The `execute-flow`, `red-team`, and `gitlab-mr-review` skills read `REVIEW.md` with `git show origin/<default>:REVIEW.md`, never from the working tree, so a slice cannot rewrite the rules it is reviewed against. The execute flow runs no fetch, so a stale `origin/<default>` gives the last fetched copy.
- The skills read `REVIEW.md` only when the show exits 0. Any other exit, including 128 for a file that exists in the working tree but not on the default branch, makes the file absent, and the error text goes to the report, never into the review rules. The runner then uses the built-in high-risk list only, and the context block carries no review rules.
- The text travels inside `contextBlock`, so the registry reviewers, the non-cold custom dimensions, and every verifier read it, and a cold dimension never does. The runner parses only the `## High-risk paths` section. The other sections are prose for the reviewers.
- `doctrine/git-safety.md` lists `git show` with one `<ref>:<path>` argument among the read-only git commands the execute flow's agents may run. A change to how the skills read `REVIEW.md` must stay inside that list. The `gitlab-mr-review` skill runs the same read with `git -C <module-dir>` in the module checkout.

## Child ref

- `execute-runner.js` calls the child through its `reviewMr` arg, a workflow name or `{scriptPath}`, and defaults to `toolkit:review-mr`. The `execute-flow` skill passes `{scriptPath}` when `repoRoot` holds `plugins/toolkit/workflows/review-mr.js`, the rule the `red-team` skill uses for its own launch, so the toolkit repo runs its working-tree child.
- A refused ref lands in `blocked` through the runner's try/catch as `The review-mr child workflow failed: <message>.`, never as a silent fallback to the installed child.

## No repeats

- The cold read gets the `<file>: <title>` keys of the panel's `confirmed`, `nits`, and `preExisting` entries, and does not report those again.
- Refuted, dropped, and unverified entries never join the list. One verifier's refusal is not proof, and a real defect wrapped in an overstated failure scenario dies with the scenario, so the cold read stays free to raise it again.

## Settled outcomes

- The execute flow's adjudication list is every `review.unverified` entry followed by every `coldResidual` entry. An entry is settled when the plan note records it as fixed, wrong, intentional, or did not matter. The `execute-flow finished:` summary, which the ship flow accepts, waits until every entry is settled. [context-execute-flow-adjudication.md](context-execute-flow-adjudication.md) holds the section 8 options.
- Each outcome line carries the finding's tag and scores, so the plan note measures noise by outcome. A wrong finding also records a `Reviewer prompt (<dimension>):` line for the user to add under Known false positives in `REVIEW.md`.
- A real defect that the panel missed and a later review or a user found becomes a harness case in the suite of the script it touched.
- Every outcome line carries `[<tag>, score <score>, final <finalScore>]`: the `red-team` result lines, the `execute-flow` section 6 `Finding fixed:` lines, and the `execute-flow` section 8 lines. A panel entry fills the tag with the verifier's `finalTag`, which `red-team` writes as `<finalTag>` because all its entries are panel entries. A cold entry has no verifier score, so it carries the reviewer's `tag` and `score`, and final equals score.

## Source

- The tags, the verification of each finding, the no-repeats rule, the loop cap, and the four outcome words follow the post Solving code review at Anthropic on the Claude blog, and the cut at 80 follows the README of the `code-review` plugin in the `anthropics/claude-code` repo.
