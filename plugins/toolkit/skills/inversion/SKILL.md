---
name: inversion
description: >-
  Pre-mortem for a plan, decision, or completed fix. Use when the user invokes it by name
  ("inversion", "pre-mortem", "invert this") and whenever the user asks whether a plan, a
  decision with named alternatives, or a completed fix will hold or succeed:
  "is this a good plan", "is this ready to ship", "any holes in this". The subject must be
  a written plan, a decision with named alternatives, or a completed fix. Assumes total
  failure at a horizon that fits the subject and works backward to up to seven ranked
  causes, a verdict, a rebuilt plan with walk-away checks, an adversary's view, and one
  tripwire per failure mode. Never reassures and gives no generic advice. Do not fire on a
  single command, a screenshot, a plan note already under plan-critic review in this
  session (plan-critic carries the same structure), a question about style or naming, a
  request for an explanation rather than a judgment, a request to review, check, or
  sanity-check code, a diff, a query result, or a value for correctness, or when the
  utterance is a closure signal for an implementation slice with uncommitted changes, in
  which case the red-team recommendation takes precedence. Writes nothing outside the
  scratchpad and touches no git state.
---

# Inversion

Assume the subject has already failed completely, then work backward. The horizon fits the subject: six months after approval for a plan or decision, three weeks after deploy for a code fix. If the user names a horizon, use it. When the subject is a change under about ten lines, or a single decision with no alternatives, say in one line that a pre-mortem adds nothing here and stop. Do the Autopsy below in your own reasoning; return only the Verdict, Rebuild, Adversary, and Tripwires sections, each under its heading. The plan-critic agent applies this same pre-mortem structure but returns its own subset: Verdict, objections derived from the Autopsy, a Tripwires block, and a Walk-away checks block, per `agents/plan-critic.md`.

## Autopsy

List up to seven causes of the failure, ranked worst first by damage and then by likelihood. For each cause give four lines: what killed it, how it unfolded over time, the assumption that allowed it, and the first warning sign. Every cause traces to a specific detail in the plan or fix, quoted or pointed to. Cut any cause that cannot be traced to a detail. Never pad to seven with generic causes.

## Verdict

Name the most likely failure and the most dangerous failure. When they differ, say why. Name the single biggest hidden assumption. When a fatal flaw exists, write the words "fatal flaw".

## Rebuild

Rewrite the plan or fix with each Autopsy failure closed. For each failure, show what changed and why. List three to five pre-launch checks. For each check, state the result that means walk away.

## Adversary

Name who benefits from this failing (a competitor, an attacker, an internal team, a vendor). State where they attack, their week-one move, and the move nobody sees coming.

## Tripwires

Give one measurable signal per Autopsy failure mode and the moment to check it (an offset from launch, a deploy count, a traffic threshold). A tripwire without a number is not a tripwire.

## Rules

No generic advice. Every sentence names a detail of this subject. Never reassure and never balance the picture with what might go right. When the output runs past a page, write it to the session scratchpad only, never the vault or the repo, per the communication doctrine, and summarize in chat. Inside plan-guide, the `plan-critic` agent runs this structure on the plan note, and plan-guide copies the Tripwires and the walk-away checks into the plan's Validation Steps and Risks.
