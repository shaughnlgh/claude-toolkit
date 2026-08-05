---
name: expedition
description: >-
  The overarching pipeline for a big, deliberately-committed scope of work: guides the
  conductor from ticket ingestion through crawl, grill, split decision, planning,
  execution, and review, all the way to a manually-confirmed complete — with the stage
  persisted in a vault work note so the effort survives across days and sessions. Use
  ONLY when the user explicitly invokes it ("/expedition", "run the expedition on
  this", "take this through the full workflow") or asks to resume one ("where is the
  expedition on X?"). Never fires automatically, never fires on task size or fuzziness
  alone — committing to this workflow is the human's decision. Small work (a diagnosed
  bug, a bounded change) never comes here; it goes through the normal crawl or
  plan-workflow paths.
---

# Expedition

Expedition is a state machine with a dispatcher, not a mega-skill. It owns exactly three things: the stage sequence below, the gates between stages (recommend, then the user confirms, skips, or redirects), and persistence in the vault so a fresh session days later knows exactly where the effort stands and what the next gate is. Every stage's actual work is delegated to the skill that owns it — crawl, grill, wayfinder, plan-workflow, execute-workflow, gitlab-mr-review. Expedition never absorbs or re-implements them, and each stays independently invokable outside any expedition.

Load `plan-workflow` before creating any vault artifact here; its canonical layout, naming, and frontmatter rules govern the expedition's directory exactly as they govern any plan's.

## Trigger and scope

Explicit invocation only. The human decides that a scope of work is big enough to commit to this guided workflow — that judgment is deliberately NOT delegated to the model. Do not self-fire on size, fuzziness, multi-repo scope, or anything else the model detects.

Resume: when a session opens with a reference to an existing work note (`work - <name>.md`), or the user asks where an expedition stands, read the work note — then reconcile it against observable reality before trusting it (child plan `status` fields, whether plan notes exist, MR state via a cheap `glab` read where relevant). When the note and reality disagree, reality wins: log a correcting Stage Log entry, say so, and continue from the corrected stage. Never re-run a gate the artifacts prove was passed.

Adoption: when the user invokes expedition on work that already has a plain plan note, do not create a new directory (the name would collide with plan-workflow's vault-unique rule anyway). Create the work note inside the existing plan directory, backfill the Stage Log from the plan's status history in one entry ("adopted at stage X"), and continue from there.

## The work note

One `work - <name>.md` per expedition, created at ingestion, in the expedition's plan directory. Derive `<name>` at ingestion exactly as plan-workflow derives plan names (ticket prefix if a ticket exists, kebab-case, vault-unique) — this name IS the future plan name: the single plan, or the wayfinder umbrella, takes this same name and lands in this same directory, so every artifact filename embeds it per plan-workflow's naming contract and the validator's parent/child directory checks hold. The umbrella plan, child stubs, and brief all land in this directory as they appear. The work note is the single place that answers "where is this effort and what happens next."

Frontmatter: `work` (the name), `stage` (see sequence below), `ticket` (or blank), `created`, `updated`. Body: a **Stage Log** (one line per transition: date, stage entered, the gate decision that caused it), **Parked Items** (ideas, requirements, and risks surfaced before child stubs exist — see the deferred-ideas section), and **Links** (brief, umbrella plan, child plans, MR URLs — added as they come into existence).

Update the work note at every stage transition, through the vault's atomic-write mechanics. A transition without a log line did not happen.

## Stage sequence and gates

`ingested → crawled → grilled → split-decided → planned → approved → implementing → in-review → merged → complete`

At each transition: state the recommendation and the one-line reason, ask, record the answer in the Stage Log. Present each gate via the AskUserQuestion form per the communication doctrine, recommended answer first. Gate answers mean:

- **Yes** — advance to the stage.
- **Skip** — advance without running the stage's work, reason recorded. Valid at the crawl and grill gates only; the split gate is a fork, not a pass-through — it needs an answer (one plan or several), and "skip" is not one.
- **No** — hold: the expedition stays at its current stage, the answer is logged, and nothing advances until the user redirects or returns. A plan rejected at approval holds at `planned` and loops through plan-workflow's revision cycle as normal.
- **Abandon** — terminal, user-declared at any stage: set `stage: abandoned` with the reason logged. A dead expedition must be representable, not just silent.

The approval gate is the standing exception: it is plan-workflow's human approval, and it can never be skipped or recommended away.

1. **Ingest.** Capture the brief verbatim (ticket via the crawl skill's ingest mechanics), create the plan directory and the work note, write `brief - <name>.md`. Stage: `ingested`.
2. **Crawl.** Delegate to the `crawl` skill: recall + explorer validation of the brief. Its evidence report lands in the conversation and its corrections get a line in the Stage Log. Stage: `crawled`.
3. **Grill.** Recommend a grill (default yes for expedition-sized work) and run the `grill` skill. It starts at the alignment layer — outcome, success definition, rough sequencing come first in dependency order anyway. Stage: `grilled`.
4. **Split decision.** Once the alignment layer is agreed, put the split question: one plan or several phases, with a recommendation from the crawl and grill evidence. Several → `wayfinder` decomposes (consuming the alignment instead of re-running it); one → the same grill session continues to full depth and feeds a single plan. Stage: `split-decided`.
5. **Plan.** Each plan (the single one, or each wayfinder child when its turn comes) goes through `plan-workflow`, children preceded by their own scoped deep grill where requirements are not pinned. Stage: `planned` when the first plan note is complete; the work note's Links section tracks per-child status via the umbrella's Task Roadmap rather than duplicating it.
6. **Approve.** plan-workflow's human approval, per plan. Stage: `approved`.
7. **Implement and verify.** `execute-workflow` per approved plan. Stage: `implementing`.
8. **Review.** MR raised; `gitlab-mr-review` when asked. Stage: `in-review`, then `merged` when the MR lands.
9. **Complete.** Manual, always: the user says the work is done (deployed, verified in production, whatever "done" means for this effort — the toolkit has no reliable way to observe deploys, so it never pretends to). Record who said so and when. Stage: `complete`.

For a multi-phase expedition, stages 5–8 repeat per child; the work note's stage reflects the TRAILING edge — the furthest stage that every non-abandoned child has reached — because resume goes to the least-advanced work, and a note that says `merged` while most children are unplanned answers "where is this effort" wrongly. Add a one-line progress marker to the work note body ("3 of 7 children merged") and record per-child transitions in the Stage Log. The umbrella plan's Task Roadmap remains the per-child truth; the work note points at it rather than duplicating it.

## Deferred ideas never get lost

An idea, requirement, or risk that surfaces in one phase but belongs to another gets written immediately into the child stub that owns it (Open Questions or Current Context) — the stub is where that phase's future planning session will look first. A central parking lot is where ideas go to be forgotten. Before stubs exist (stages 1–4: crawl, alignment grill, split decision — exactly the highest-yield stages for these items), the target is the work note's **Parked Items** section; wayfinder drains it when it emits the stubs, moving each item into the stub that owns it. When a deferred item changes the sequencing itself, also update the umbrella's Task Roadmap row with a one-line pointer. Repo-owned artifacts (glossary terms, ADRs, /docs) stay repo-global per the location contract in `doctrine/repo-artifacts.md`, which grill's own rules follow.

## Session boundaries

A stage gate is also a session boundary. The work note exists so the effort survives session changes — use that, don't ride one conversation across stages: a long session re-pays its entire context on every request, and the expedition's cost driver is conductor context, not stage work. When a gate closes a stage (crawled, grilled, split-decided, each plan's approval, each child's merged), update the work note, then recommend ending the session and resuming fresh at the next stage — resume already knows how to pick up from the note. Within a stage, if the context sentinel fires or the session compacts twice, same move: stable point, note updated, fresh session. Never let continuity live in the conversation when the note can carry it.

## Boundary

Expedition does not plan, grill, decompose, implement, review, or approve — the owning skills do, with their own rules intact. It does not create ADRs or glossary entries (grill's job). It never advances a stage without the gate's answer recorded, never skips the human plan approval, and never marks `complete` on its own inference — merged is observable, done is the human's word.
