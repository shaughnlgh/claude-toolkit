# Context Economics

How context, cache reads, and cache writes drive Claude Code's cost, and what that means for how work is run in this toolkit. This is a reference doc for conductors — read it once, then let the practices below become habit; the observed numbers are one machine's telemetry, illustrating the shape of the effect, not universal constants, and the pricing multipliers are Anthropic's published cache pricing as of writing and may change.

## Mechanics

Prompt caching is exact-prefix: the system prompt, tool schemas, injected context, and conversation history cache incrementally, each turn extending the cached prefix from the last. A cache hit re-reads at roughly 10% of base input price; a miss re-writes at 125% (5-minute TTL — a 1-hour TTL variant writes at 2x instead). Any byte changed earlier in the prefix invalidates everything after it, forcing a rewrite of the invalidated tail. The TTL refreshes on every hit, so an actively-used cache stays warm indefinitely; a gap longer than the TTL means the next request re-writes the full context from scratch, at the write rate.

## What this means per task shape

- **Long sessions.** Each post-gap turn re-writes the whole history, so cost grows with context length even when the session reads as "cached" throughout. Observed: 71% of a week's usage sat at >150k tokens of context. A Q&A-only session showed 156k tokens cache-written against only 47k read — an inverted ratio, meaning turns were arriving slower than the TTL and paying the write rate repeatedly instead of the read rate.
- **Subagents.** Each spawn is a fresh context, paying its own system-prompt-and-doctrine write once. Each resume replays the whole worker transcript instead — see `docs/decisions/0002-worker-resume-vs-fresh-spawn.md` for when that trade is and isn't worth it.
- **Always-injected content.** Session-start rules, MCP tool listings, and plugin hooks/agents sit in every request of every session. Cheap per-request while the cache stays warm, but re-written in full on every cache break. This is why the toolkit keeps write-time rules to five small bodies with a 64KB per-rule cap, keeps the design and frontend rules reference-only behind an index (`docs/rules.md`) instead of injecting the whole catalog, and why unused MCP connectors are worth disconnecting — an audit on this machine found only 3 of roughly 22 connected servers had any invocations in the trailing 30 days.

## Practices

- `/clear` between unrelated tasks; don't carry one task's context into the next.
- `/compact` mid-task when a long session must continue past its natural end.
- End sessions when the work ships, rather than idling a warm cache into a cold one.
- Batch related asks within a warm window rather than trickling requests past the TTL.
- Resume vs. spawn fresh per `docs/decisions/0002-worker-resume-vs-fresh-spawn.md`.
- Delegate verbose output — test suites, file dumps, log trawls — to workers who return distilled results, so the raw output never lands in the conductor's own history.
- Prefer just-in-time context injection (the `design-rules-reminder.sh` hook pattern in `docs/hooks.md`) over always-on injection: surface a concern only when a file matching it is actually touched.
