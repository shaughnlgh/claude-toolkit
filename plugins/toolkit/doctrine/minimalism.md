# Minimalism

Be thorough about understanding the problem and minimal about the solution. The reading is never shortened, only the code is. This sharpens what the workflow produces; it does not loosen the process (planning, review, verification) around it.

## Reuse before you add

Before writing new code, walk this ladder and stop at the first rung that holds:

1. Does this need to exist at all? Drop unrequested scope.
2. Does the codebase already do it? Reuse or extend the existing thing rather than adding a parallel one.
3. Does the language's standard library do it?
4. Does the platform or framework already provide it? Use its own idiom, not a workaround.
5. Does an already-installed dependency do it? (A brand-new dependency is a separate decision — audit it first for maintenance state, known vulnerabilities, postinstall scripts, and typo-squatting before adding.)
6. Can it be a few lines in the right place?
7. Only then, write the minimum that works.

State the result of this check when you plan (see `plan-workflow`) so a reviewer can see why each new file or abstraction earns its place.

## Shape of the change

- Shortest working diff that satisfies the plan. Prefer deleting code to adding it.
- No unrequested abstractions: no interface with a single implementation, no factory for one product, no configuration knob for a value that never varies. Add the seam when the second caller actually arrives, not in anticipation of it. (`design.md` covers how to shape the abstractions you do keep.)
- Read before you change: trace the flow end to end and grep every caller before editing a shared function, so a local fix does not break a distant caller.
- Fix bugs at the root — the shared choke point every caller routes through — not per caller as a symptom.

## Mark deliberate shortcuts

When you deliberately stop short of the full solution, mark it with a greppable comment naming the ceiling and the upgrade path, in the same attributed form as other code markers (`TODO(author): <what it does not handle yet> (#issue)`). An unmarked shortcut is indistinguishable from a bug.

## What minimalism never touches

Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security controls, accessibility basics, or anything the user explicitly asked for. Minimalism removes speculative work, never protective work.
