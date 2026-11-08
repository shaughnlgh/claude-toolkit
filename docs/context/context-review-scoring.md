---
title: Review scoring
summary: How the review panel scores, verifies, and routes findings, how the execute runner picks the panel and caps the fix loop, and the constraints a change to those rules must keep.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-11-06
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

The `review-mr` workflow scores each finding, verifies it in batches, and routes it by the verifier's verdict. The `execute-runner` workflow picks the panel by path and caps the fix loop at maxFixRounds. What the scripts take and return is in [workflows.md](../workflows.md). This page lists the rules and the constraints a change to them must keep. The cost rationale is in [context-economics.md](../context-economics.md).

## Scores and the threshold

- A reviewer gives each finding an impact, a likelihood, and a confidence from 0 to 1. The score is 0.5 impact + 0.3 likelihood + 0.2 confidence, each clamped to 0 to 1, rounded to two decimals so that test fixtures compare exactly.
- The threshold is 0.6, and it is the reproduction bar for a code finding. At or above it a reproduction is the trace of the code path or a fixture run with its output, and below it a reproduction is the cited line as the verifier read it and what it shows, and the fix prompt labels such a confirmed finding `cited line read` instead of `reproduced`. A doc finding, one whose file is under a `docs/` directory or ends in `.md`, has a bar of 0. The verdict, not the threshold, decides what is fixed: the threshold decides whether an unreproduced code finding becomes a question or a nit, and the runner reads it to count the open confirmed findings that trigger the step-back sentence. The Anthropic code-review plugin cuts a single 0 to 100 confidence at 80. This toolkit cuts a weighted composite at 0.6 instead, because a verifier reproduces each finding at or above it, so a lower cut costs a reproduction, not a false report.
- `scoreOf`, `clamp`, `round2`, `cited`, `THRESHOLD`, the `unit` schema, and the `TAG` enum are duplicated in `review-mr.js` and `execute-runner.js`, because workflow scripts share no module. A change to the weights, the threshold, or the tags means editing both files.
- `isDoc` and `barOf` live only in `review-mr.js`. The runner routes by bucket, `finalTag`, and `finalScore`, never by file, so it needs no copy.

## Batched verification

- Each dimension gets one `toolkit:verifier` per chunk of eight cited findings, so the verifier count is bounded by dimensions times chunks, not by findings. Eight findings against the verifier's 150-turn cap leave about eighteen turns per reproduction.
- The verifier returns one verdict per finding by the index its chunk shows. Indexes restart at 0 in each chunk. A verifier that renumbers routes verdicts to the wrong findings.
- A finding the verifier omits goes to `unverified` with the reason `no verdict`. A chunk whose verifier returns nothing puts the dimension in `verifierDead` and the chunk's findings in `unverified` with the reason `verifier died`. `verifierDead` names a dimension as `dead` does, a registry reviewer by its agent type and a custom dimension by its key. `execute-runner.js` blocks on a non-empty `verifierDead`, so a dead verifier never lets a slice finish with an unchecked dimension.
- The verifier owns `finalTag`, `finalScore`, and `reproduction`. For a code finding at 0.6 or above, `reproduction` holds the command or trace the verifier ran and the output it saw, and is empty when it ran nothing. The script derives `reproduced` from a non-empty `reproduction`, and the verdict schema carries no boolean for it, because a self-reported boolean cannot be checked.
- A verifier that raises a finding from below 0.6 to 0.6 or above must reproduce it first, and the verifier prompt allows a reproduction only by tracing the code or by running commands in a fresh fixture under the system temp directory outside `repoRoot`, which the verifier never modifies.
- For a doc finding, the reproduction quotes with its file:line the code line, rule line, or doc line that makes the doc wrong, at every score. The verifier refutes a doc finding only by quoting the line in the tree that makes the doc right, and a plan note line, an Assumption, a Risk, an approval, or an owner's acceptance is never that line. "The plan decided it", "settled at approval", "the owner accepted this", and a subjective preference are not refutations. A finding that cites a file under `rules/`, `doctrine/`, `CLAUDE.md`, `AGENTS.md`, or `.claude/rules` loses score only when the cited rule does not say what the finding claims, never on plan or design grounds.
- The verifier reads its brief and the runner's `SETTLED DECISIONS` sentence in one prompt, because the sentence travels in `contextBlock`. Both must carry the same rule, that an Assumption or Risk settles scope and coverage and never a rule breach or a doc line the tree contradicts. A change to one must change the other.
- The verifier brief in `review-mr.js` and the `SETTLED DECISIONS` sentence in `execute-runner.js` each list the rule-breach paths: `rules/`, `doctrine/`, `CLAUDE.md`, `AGENTS.md`, and `.claude/rules`. The two lists must match. The review-mr suite pins the verifier wording in its rules sentence case and its quoted-phrases case.

## Routing

- A real finding with `finalTag` `pre-existing` goes to `preExisting`, whatever its score. It is listed for a ticket and never fixed in the slice.
- Any other real finding goes to `confirmed` when its `reproduction` is not empty, at any `finalScore`.
- An unreproduced real code finding at 0.6 or above and an unreproduced real doc finding at any score go to `unverified` with the reason `not reproduced`. Such a finding never goes to the fix round and never to the floor. The `red-team` skill settles it with the user, and the execute flow records it as unreproduced.
- An unreproduced real code finding below 0.6 is a nit. The five with the highest `finalScore` go to `nits`, and the rest go to `dropped` with the reason `nit cap`. A doc finding is never a nit.
- A refuted code finding and a refuted doc finding with a reproduction go to `refuted`. A refuted doc finding with an empty reproduction goes to `unverified` with the reason `not reproduced`, because a doc refutation that cites no line is a question for the author.
- The `refuted` and `dropped` entries carry `reproduction`, so the report shows the line a refutation rested on. A `dropped` entry with the reason `no citation` never reached a verifier and has no `reproduction`.
- A finding with no citation goes to `dropped` with the reason `no citation` before any verifier sees it. `citation` stays out of the schema's required list, because a missing required field makes the runtime reject the whole reviewer return.
- The reviewer's tag is advisory. The verifier retags a nit with real impact as important, an important style finding as nit, and a pre-existing claim that the diff's removed and context lines do not carry as important.
- `openQuestions` entries are plain `{dimension, question}` objects, not findings, so they carry no score, citation, or `reproduction`.
- Four files state the `review-mr` result shape: [workflows.md](../workflows.md) and the `red-team`, `gitlab-mr-review`, and `execute-flow` skills. A change to the shape, or to which entries carry `reproduction`, must edit all four, and each must keep the exception that a `dropped` entry with the reason `no citation` has no `reproduction`. The report rule in the `gitlab-mr-review` skill is the only place that decides how refuted findings show in an MR review.

## Fix round and the loop cap

- The fix round takes the confirmed findings under `CONFIRMED FINDINGS:`. The class sentence, fix every instance of that class of defect in the slice, not one line, applies only to a confirmed finding tagged `important` at `finalScore` 0.6 or above. The fix brief confines a confirmed finding tagged `nit`, or any confirmed finding below 0.6, to its cited line, so a cited-line reproduction never widens the fix to the slice.
- The fix round's prompt also carries the plan's Validation Steps as a line range. The fix worker leaves a nit, or a confirmed finding below 0.6, unfixed when its fix would make a listed step fail, and returns its key and that step in `skipped`. The runner takes such an entry out of `open`, so it starts no later round, returns it in `review.keptForSteps`, and records a `Fix round R kept for a Validation Step:` line, and section 8 of the `execute-flow` skill settles it as intentional. A `skipped` key that names a confirmed finding at 0.6 or above changes nothing, so that finding stays open, is fixed or blocks, and `verify:final` stays the backstop. The `execute-flow` section 8 fix brief carries the same skip rule, and a finding its fix leaves unfixed fails its re-check and is held.
- A reproduced finding below 0.6 is confirmed and starts a round on its own. The unreproduced nits ride the same round under `NITS:`. They are fixed only at the cited line and only when the tree confirms them. The plan note's `nits` run option, which the runner takes as its `nits` arg, decides whether they ride. Under `nits: fix` they ride round 1 with or without a confirmed finding, so nits alone start round 1. On a seat run nits alone start no round under either value, because the worktree run already offered the slice's nits, and a nits-only round would edit the main checkout and start a `verify:final` whose fail blocks the seat run. A later round runs only while a confirmed finding stays open, so an open nit never buys a second round. Under `nits: skip` no nit rides any round, and the nits pass through to the user's To settle list.
- When confirmed findings at `finalScore` 0.6 or above stay open after `maxFixRounds`, the runner blocks with the step-back sentence, which tells the author to reconsider the approach rather than run another round. An open confirmed finding below 0.6 never blocks and passes through in `review.open` to the adjudication list. Open nits never block.
- The fix brief interpolates `THRESHOLD`, so a change to it moves the class-rule gate, the cited-line clause, and the step-back filter together. The loop condition reads no threshold: a round runs while any confirmed finding is open, at any score.

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

- The execute flow's adjudication list is every `review.unverified` entry, then every `review.open` entry with bucket `confirmed`, then every `coldResidual` entry, then every `review.keptForSteps` entry. An entry is settled when the plan note records it as fixed, intentional, did not matter, or unreproduced. The `execute-flow finished:` summary, which the ship flow accepts, waits until every entry is settled. [context-execute-flow-adjudication.md](context-execute-flow-adjudication.md) holds the section 8 rules.
- Each outcome line carries the finding's tag and scores, so the plan note measures noise by outcome.
- A real defect that the panel missed and a later review or a user found becomes a harness case in the suite of the script it touched.
- Every outcome line carries `[<tag>, score <score>, final <finalScore>]`: the `red-team` result lines, the `execute-flow` section 6 `Finding fixed:` lines, and the `execute-flow` section 8 lines. A panel entry fills the tag with the verifier's `finalTag`, which `red-team` writes as `<finalTag>` because all its entries are panel entries. A cold entry has no verifier score, so it carries the reviewer's `tag` and `score`, and final equals score.

## Source

- The tags, the verification of each finding, the no-repeats rule, the loop cap, and the four outcome words follow the post Solving code review at Anthropic on the Claude blog, and the cut at 80 follows the README of the `code-review` plugin in the `anthropics/claude-code` repo.
