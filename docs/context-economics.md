# Context Economics

How context, cache reads, and cache writes drive Claude Code's cost, and what that means for how work is run in this toolkit. Read once, then let the practices below become habit. Pricing multipliers are Anthropic's published cache pricing as of writing and may change.

## Mechanics

Prompt caching is exact-prefix: the system prompt, tool schemas, injected context, and conversation history cache incrementally, each turn extending the cached prefix from the last. A cache hit re-reads at roughly 10% of base input price; a miss re-writes at 125% (5-minute TTL — a 1-hour TTL variant writes at 2x instead). Any byte changed earlier in the prefix invalidates everything after it, forcing a rewrite of the invalidated tail. The TTL refreshes on every hit, so an actively-used cache stays warm indefinitely; a gap longer than the TTL means the next request re-writes the full context from scratch, at the write rate.

## What this means per task shape

- **Long sessions.** Each post-gap turn re-writes the whole history, so cost grows with context length even when the session reads as "cached" throughout. A session whose turns arrive slower than the TTL pays the write rate on every turn instead of the read rate, and can end up writing several times more context than it ever reads back.
- **Subagents.** Each spawn is a fresh context, paying its own system-prompt-and-doctrine write once. Each resume replays the whole worker transcript instead — see `docs/decisions/0002-worker-resume-vs-fresh-spawn.md` for when that trade is and isn't worth it.
- **Always-injected content.** Session-start-injected rule bodies and pointer lines, MCP tool listings, and agent/skill description listings sit in every request; event-driven hook output and invoked agent bodies arrive only when triggered and then persist in that session's history. Cheap per-request while the cache stays warm, but re-written in full on every cache break. This is why the toolkit keeps write-time rules to eight small bodies with a 64KB per-rule cap, and keeps the design and frontend rules reference-only behind an index (`docs/rules.md`) instead of injecting the whole catalog. The same logic applies to MCP connectors: one that's rarely invoked still costs prefix space in every session, cached or not, so periodically audit actual usage (grep session transcripts for real invocations, not just configured connectors) and disconnect what isn't used.

## Practices

- `/clear` between unrelated tasks; don't carry one task's context into the next.
- `/compact` mid-task when a long session must continue past its natural end.
- End sessions when the work ships, rather than idling a warm cache into a cold one.
- Batch related asks within a warm window rather than trickling requests past the TTL.
- Resume vs. spawn fresh per `docs/decisions/0002-worker-resume-vs-fresh-spawn.md`.
- Delegate verbose output — test suites, file dumps, log trawls — to workers who return distilled results, so the raw output never lands in the conductor's own history.
- Prefer just-in-time context injection (the `design-rules-reminder.sh` hook pattern in `docs/hooks.md`) over always-on injection: surface a concern only when a file matching it is actually touched.
