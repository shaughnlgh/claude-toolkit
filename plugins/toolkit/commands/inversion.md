---
description: Pre-mortem a plan — assume it already failed and list every way it got there, worst first, before you commit
argument-hint: [plan or decision]
---

# Inversion

A pre-mortem: assume the plan has already failed completely, and lay out every way it got
there. Unsoftened, worst-case, so the real problems surface while they can still be
fixed. Invoke it on a plan or decision before committing to it.

## Usage

$ARGUMENTS

Arguments, if any, name the plan or decision to invert. With no arguments, use the plan
or direction under discussion.

## What to do

Do not hedge, and do not balance the picture with reassurance. The job is to find the
failure modes, not to be fair to the plan.

1. **The failure modes.** Every distinct way this fails: wrong assumptions, missing
   dependencies, things outside our control, second-order effects, the quiet ways it rots
   rather than crashes. Rank them by likelihood and by damage, worst first.
2. **The load-bearing risk.** The single failure that would hurt most, and the earliest
   signal that it is happening.
3. **The fixable core.** For the top risks, what a fix would actually target, so this
   turns into work rather than dread.

Be blunt. Do not pad with what might go right. If a risk is speculative, say so and rank
it below the concrete ones, but do not omit it. Do not inflate a negligible risk to
lengthen the list. A short pre-mortem of a genuinely robust plan is a fine result. This
is the worst-case version on purpose.

For a written plan inside the plan-workflow, the `plan-critic` agent does this as part of
planning. This command is the on-demand version for any plan or idea in conversation.
