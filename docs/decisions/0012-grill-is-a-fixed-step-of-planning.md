---
title: Grill is a fixed step of planning
summary: Every first-draft planning flow runs the planning grill once, after discovery and before the draft, takes only the user's own answer, and on the wayfinder route reads the crawl grill check's answers from the parent note.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-12
---

# 0012. Grill is a fixed step of planning

Date: 2026-11-12

Status: Accepted

Amended by [0015](0015-lead-and-worker-sessions.md), which replaces the relay sentences from "A parent session may relay it." to the end of the bullet that opens "A planning grill question takes only the user's own answer" and the Consequences text on a parent session that relays the user's answer, so a worker session's planning grill reaches the user through AskUserQuestion and no session relays an answer.

## Context

The grill fired only on an explicit request or from the crawl, so a plan that reached planning by another route was never grilled. Plans drafted from parent-written stubs reached review with their gaps as Open Questions and critic objections, nine on one plan.

Three alternatives were weighed and rejected. Keeping the grill crawl-only was rejected, because developers do not remember to ask and most routes skip the crawl. Grilling before discovery was rejected, because the grill then has no evidence to ask from. Dropping the crawl's grill check entirely was rejected, because a missed module can change the wayfinder split.

## Decision

- The new step is the planning grill. It runs once on every first-draft planning flow, in the plan flow and in plan-guide's hand-run planning, after discovery and before the draft.
- The crawl keeps its section 3 grill check on the wayfinder route only. On the plan-guide route the plan's own planning grill runs instead. The rule that the first Task Roadmap child writes the grill check's agreed glossary terms and decisions stays for the wayfinder route.
- The planning grill and the grill check share five triggers: a correction to the brief, a module or caller the brief missed, an open question only the user can answer, a gap or risk discovery found that the brief leaves out, and a point where the code shows more than one reasonable reading of the brief.
- Both always show the outcome line and ask no fixed opening question. With no trigger, they show the outcome line plus one line that nothing needs an answer, and planning goes on.
- Anything the brief, the plan note, `docs/glossary.md`, a decision record under `docs/decisions/`, or an earlier grill answers is settled and never asked again.
- Discovery is skipped only when the plan flow starts from the crawl's plan flow offer in the same session. A later by-name run on a crawl-scaffolded note runs discovery, narrowed by what the note settles, then grills.
- A changed plan gets no grill, except that new scope gets discovery and a grill on the added part only. A note whose Current Context carries the line `Agreed in the grill:` counts as grilled.
- An expedition's stage 3 answers count as settled in each plan's planning grill.
- The planning grill writes nothing to the repo and shows no consent gate.
- A planning grill question takes only the user's own answer: a pick from the question form or a typed reply, given in the session that runs the grill. A parent session may relay it. The child sends its planning grill question to the parent, the parent shows it to the user, and the parent passes the user's answer back word for word, marked as the user's own answer. The parent never answers on its own, and a message that is not marked as the user's own answer never counts.
- On the wayfinder route the grill check's answers live once, in the parent note's Current Context under the marker `Agreed in the grill check:`. Every child's planning grill reads them from the parent note that the child's `parent` value names. The stub of the first Task Roadmap child carries one line that points to that block, and that child keeps the duty to write the glossary and decision record files.
- A finding is not an answer. A correction to the brief, a module or caller the brief missed, and an Open Questions entry that a crawl or another scaffold wrote into a note are evidence the planning grill asks about.
- The `plan-builder` workflow runs in two launches joined by `resumeFromRunId`, with the planning grill between them in the conversation.

## Consequences

Every plan flow pauses for the user after discovery unless nothing needs an answer. The plan-builder runs in two launches on a route without crawl evidence, and the second launch resumes the first, so the code is read once. The explicit-request rule for grill in the routing doctrine gains a planning carve-out. A finding a crawl wrote into a scaffold is evidence the planning grill asks about, not an answer.

A planning grill takes only the user's own answer, a pick from the question form or a typed reply in the session that runs it, so on the wayfinder route each child's planning needs the user in that child's session or a parent session that relays the user's answer word for word. No hook enforces the relay, so the rule rests on the parent session following it.

The grill check's answers live once in the parent note, so each child's planning grill depends on reading that note, and the first Task Roadmap child writes the block's glossary terms and decisions as files. A planning grill whose answers turn the work into several workstreams leads to the wayfinder question before the draft. On the crawl route the gate's `discovery.uncovered` is empty by construction, because the crawl's explorers did the reading.

Each child of a split can agree its own terms and decisions, so sibling branches can conflict on the glossary, and a plan names a new decision record by title and takes its number when it writes the file.
