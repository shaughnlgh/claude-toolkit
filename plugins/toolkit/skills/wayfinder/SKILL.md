---
name: wayfinder
description: >-
  Use when the user explicitly asks to map, scope, or break down a large multi-part
  investigation, incident, or migration before planning it (for example "map out this
  incident before we plan fixes", "scope this migration into tickets", "break this
  investigation down before we plan each piece"), or when the crawl skill routes here
  with a user-confirmed route and evidence in hand. Investigates to establish facts
  (or consumes the crawl's evidence), aligns with the user on outcome and success
  before decomposing, builds an issue register of classed issues each mapped to a
  prospective task, then writes a parent umbrella plan note plus child plan stubs
  using plan-guide's frontmatter and naming rules, one stub per task. Does not fire
  on an ordinary single-feature task, even a large one. Those go straight to
  plan-guide instead. Never automatic: only an explicit request, or a crawl route or
  plan-flow route check the user confirmed.
---

# Wayfinder

Wayfinder is the front-half discipline for a large, multi-session investigation, incident, or migration. It turns one big fuzzy thing into a mapped set of tickets before any of them gets planned in detail. It investigates, builds an issue register, and writes a parent umbrella plan note plus child plan stubs, one per prospective task, then hands each child off to `plan-guide` for its own planning, approval, and execution.

Wayfinder does not implement anything. It does not run `plan-critic`. It does not approve anything. It does not even fully plan the children, it stubs them and stops. For a single bounded task, use `plan-guide` directly. Wayfinder only earns its keep when the work is too big and too fuzzy to plan as one thing.

Because wayfinder creates plan notes (the parent and every child stub), `plan-guide` must be loaded before any of this runs. The routing rule forbids writing a plan note without `plan-guide` loaded, and wayfinder is not an exception.

## Trigger and scope

Fire only when the user explicitly asks to map, scope, or break down a large multi-part investigation, incident, or migration before planning it — or when the `crawl` skill routes here, which counts as explicit because crawl presents its evidence and recommended route and the user confirms it before wayfinder loads. A `plan-flow` route check the user confirmed counts as explicit the same way. Do not self-fire because a task looks big or touches many files. Size or fuzziness alone is not a trigger, only an explicit map, scope, or break-down request is. An ordinary single-feature task, even a large one, goes straight to `plan-guide`. If unsure whether the user wants decomposition or a single plan, ask rather than assume.

## 1. Investigate to establish facts

Before building the issue register, establish what is actually true.

When the `crawl` skill routed here, its evidence (verified facts, corrections to the brief, gaps, open questions) IS this step's output — consume it, spot-check anything load-bearing, and fill only the gaps it declared. Do not re-run the investigation crawl already did.

1. Recall first. Search the vault for topic notes and prior plan folders tied to the same incident, system, or migration, the same recall `plan-guide` runs before it explores. Read the hits.
2. Read code, config, logs, and prior notes for what recall did not already settle.
3. Delegate the gaps. Use the `explorer` agent for evidence gathering, scoped to specific gaps rather than re-deriving what recall already found — read-only search across code, config, and logs, with a per-invocation model escalation when a gap needs deep tracing (orchestration model policy). The `planner` agent gathers nothing here; it comes in later to draft plan material from the evidence.
4. Split the result into known facts and gaps. State a gap as a gap, do not paper over it with a guess. Gaps that stay open become Open Questions on the parent plan.

This step produces the raw material for the alignment session and the issue register below. Do not build either from assumption.

## 2. Align before decomposing

When a grill session already ran (an expedition's stage 3, or a standalone grill that stopped at alignment depth), its agreed outcome, success definition, and rough sequencing ARE this step — consume them, restate them in one block for a final confirm, and move on. Run the full checkpoint below only when no grill preceded this.

A lightweight agreement checkpoint with the user — a shared-understanding session, not grill's one-question-at-a-time depth. Present, in one block, confirm-or-correct style:

- **The lay of the land.** What the investigation (or crawl) established, in a few sentences: what exists, what is broken or missing, the corrections to the original brief.
- **The task as understood.** One paragraph stating what wayfinder believes the work actually is.
- **What a successful outcome looks like.** The observable end state — what is true when this whole effort is done. This becomes the umbrella plan's acceptance bar.
- **Rough sequencing.** The coarse order things must happen in (what unblocks what), without committing to task boundaries yet.

Proceed to the issue register only after the user agrees, corrects, or amends each point. Record the agreed outcome and success definition in the parent plan's Objective and Current Context, and let the agreed sequencing drive the Task Roadmap's initial order. If the user's corrections change the facts materially, go back to Investigate before registering.

This step exists because decomposing an effort nobody agrees on produces confidently wrong tickets. Two minutes of alignment beats re-stubbing the family.

## 3. Build the issue register

Enumerate every distinct issue the investigation surfaced. Group or class them (by root cause, by affected area, by severity, whatever grouping the investigation actually supports), and give each one a short code (for example `ISS-01`) so later sections can reference it without repeating the description.

Map every issue to exactly one prospective task, the child plan that will eventually close it. Some tasks close more than one issue, but every issue closes under some task. An issue with no task is a gap, not a register entry. Go back to Investigate.

This is the same shape as a real umbrella investigation register: classed issues, each pointing at the task that closes it. The register lives in the parent plan's body, not as a separate note.

## 4. Emit the parent umbrella plan

Write the parent plan note through `plan-guide`'s mechanics exactly. It is a normal plan note, `plan - <plan-name>.md`, in the canonical vault plan location, with the full required frontmatter and the full required sections (Objective, Plain Language Summary, Current Context, Assumptions, Affected Files, Implementation Steps, Validation Steps, Risks, Rollback Notes, Open Questions, Plan Changes During Execution, Related Topics, Linked Artifacts). Derive and check the plan name the same way `plan-guide` does (ticket prefix if one exists, kebab-case, vault-unique) — EXCEPT inside an expedition, where the name and directory were derived at ingestion: the parent takes that exact name and lands in that directory, or every child's `parent:` link fails the validator's directory-suffix check. When the caller hands over a pre-scaffolded root scaffold, a note whose directory name equals its plan name or ends in `-<plan name>`, write the parent plan into that note in place, so its name stands and its directory is the plan directory. Only a root scaffold can hold the parent, because the validator requires each child of a parent to sit in a directory whose name ends in the parent's name. When the scaffold's name does not match its directory's suffix, write the parent in the canonical location as usual, and record the scaffold as the first child stub in the parent's directory.

When a crawl handed off a brief and no `brief - <plan-name>.md` exists yet, write it beside the parent now (the verbatim brief plus its source reference) — this write belongs to wayfinder, not to the departed crawl session. When the expedition's work note carries Parked Items, drain them while emitting the stubs in step 5: move each item into the stub that owns it (Open Questions or Current Context) and clear it from the work note.

Add two sections to the body, placed after Current Context and before Implementation Steps:

- **Issue Register**: every issue from step 3, grouped and coded.
- **Task Roadmap**: a table, one row per prospective child task, with columns for task code, child plan slug, the issue codes it closes, and status (`not started` until the child stub exists).

The Brief itself (what happened, what is being investigated, why it matters) goes into Objective and Current Context, `plan-guide`'s existing sections. Do not invent a new section for it.

Implementation Steps on the parent describes the decomposition work itself (investigate, register, stub children, hand off), not the fix work. The fix work belongs to the children.

## 5. Emit child plan stubs

For every row in the Task Roadmap, write a child plan stub: `plan - <child-slug>.md`, in the same plan directory as the parent, with full plan frontmatter per `plan-guide` (its own `plan`, `status`, `branch`, `modules`, `sessions`), plus `parent: <parent-plan-name>`. Set `status: planning`. Child slugs are kebab-case and vault-unique, the same rule as any other plan name. Prefixing the child slug with the parent's plan name or a short investigation code keeps the family visually grouped in the vault, but `plan-guide` does not require it.

Children never inherit the parent's ticket. If a child has its own ticket, link it. If it does not, leave `ticket` blank, the same as `plan-guide` does for any plan without one.

Emit all 13 required plan-guide headings (so each stub passes the validator gate), filling the body only as far as scope is known: Objective (what this task closes), Current Context (the issue codes it addresses, and a pointer back to the parent), and Assumptions if any are obvious from the investigation. Leave the remaining required sections (Plain Language Summary, Affected Files, Implementation Steps, Validation Steps, Risks, Rollback Notes, Open Questions, Plan Changes During Execution, Related Topics, Linked Artifacts) present but empty. That detail belongs to the child's own planning session, not to wayfinder.

Update the parent's Task Roadmap row for each child once its stub exists (status becomes `stubbed`, slug filled in).

## 6. Hand off

Once the parent and every child stub exist, stop and hand off. Tell the user each child now flows through `plan-guide` on its own: its own topic recall, its own `planner` delegation if needed, its own `plan-critic` pass, its own approval, its own execution. Wayfinder does not pick which child gets planned first, that is the user's or conductor's call.

Recommend, per child, starting its session with a scoped deep grill (`/grill`, scoped to that child's issue codes) when the child's requirements are not already pinned — that is the down-in-the-dirt counterpart to step 2's lightweight alignment. Grill stays explicitly user-invoked; wayfinder recommends it in the handoff, it never fires it.

Name the parent and every child stub exactly, for example:

```
Handoff, one session per child (grill first where requirements are fuzzy, then plan-guide):
- Parent: plan - checkout-outage.md
- plan - checkout-outage-t1-payment-gateway.md (closes ISS-01, ISS-02) — grill recommended
- plan - checkout-outage-t2-inventory-lock.md (closes ISS-03)
```

Then stop. Wayfinder does not continue into planning a child in the same turn.

## Boundary

Wayfinder reuses `plan-guide`'s frontmatter, naming, and child-plan mechanics exactly. It never redefines them. There is no wayfinder-specific plan schema.

Wayfinder does not:

- Implement anything. No code, no config changes, ever.
- Run `plan-critic`. That happens per child, inside that child's own `plan-guide` session.
- Approve anything. Approval is the user's, per plan, same as always.
- Fully plan a child. It stubs each one and stops. The child's own planning session does the rest.

For a single bounded task, use `plan-guide` (`../plan-guide/SKILL.md` from this skill's base directory) directly. Wayfinder only earns its keep when one thing is actually many things.
