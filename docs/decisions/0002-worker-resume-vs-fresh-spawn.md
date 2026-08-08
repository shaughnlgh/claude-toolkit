# 0002. Worker resume vs fresh spawn

Date: 2026-08-08

Status: Accepted

## Context

The orchestration doctrine lets a conductor resume a completed worker via SendMessage, replaying its full transcript so a follow-up keeps context instead of re-explaining itself. Unbounded reuse was observed to invert the cost model: on the design-rules-catalog effort (PR #8, 2026-08-07), one implementer was resumed through six rounds to a ~190k-token transcript, then received a one-line content fix — paying the entire history for the fix. Usage telemetry attributed 11% of that week's tokens to that one agent lineage. Anthropic's prompt-cache economics drive this (mechanics detailed in `docs/context-economics.md`): a cache read costs roughly 10% of base input price, a cache write costs 125% (5-minute TTL), and a resume issued after the TTL has expired re-writes the whole transcript at that premium rate rather than reading it back cheaply. Two alternatives were considered and rejected. Always-fresh spawning was rejected because genuine multi-round work on the same files benefits from a warm, in-TTL transcript, and forcing every follow-up to re-state context already established trades one cost for a worse one. A hard turn or token cap on reuse was also rejected, because the variable that actually matters is whether the accumulated context is still load-bearing, not how large the transcript has grown.

## Decision

Resume a worker only while its accumulated context is earning its keep: successive rounds on the same files, within the same effort, minutes apart. Anything self-contained — a one-line fix, a new and unrelated ask — spawns a fresh agent instead. Rule of thumb: if the delegation prompt would have to restate the context anyway, spawn fresh rather than resume. This is the paragraph added to the "Acceptance and re-delegation" section of `plugins/toolkit/doctrine/orchestration.md` in this branch.

## Consequences

Conductors write slightly longer delegation prompts when spawning fresh, since file paths and constraints must be restated instead of inherited from a resumed transcript. Genuinely iterative efforts keep warm-resume, so multi-round work on the same files continues to pay cache-read rates rather than premium rewrite rates. The expected saving profile mirrors a comparable follow-up observed at ~23k fresh-agent tokens against the ~190k a full replay would have cost. The rule is judgment-based — no token or turn threshold enforces it mechanically — so it is enforced by doctrine reading at delegation time, not by a hook; see `docs/context-economics.md` for the cache mechanics and per-task-shape cost breakdown behind this decision.
