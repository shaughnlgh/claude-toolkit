---
title: Worker resume vs fresh spawn
summary: Resume a worker only while its accumulated context is still earning its keep; otherwise spawn fresh.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-08-08
---

# 0002. Worker resume vs fresh spawn

Date: 2026-08-08

Status: Accepted

## Context

The orchestration doctrine lets a conductor resume a completed worker via SendMessage, replaying its full transcript so a follow-up keeps context instead of re-explaining itself. Unbounded reuse inverts the cost model: a transcript resumed through enough rounds to grow large, then asked for a one-line follow-up, pays the entire history just to answer it. Anthropic's prompt-cache economics drive this — a cache read costs roughly 10% of base input price, a cache write costs 125% (5-minute TTL), and a resume issued after the TTL has expired re-writes the whole transcript at that premium rate rather than reading it back cheaply; see `docs/context-economics.md` for the full mechanics. Two alternatives were considered and rejected. Always-fresh spawning was rejected because genuine multi-round work on the same files benefits from a warm, in-TTL transcript, and forcing every follow-up to re-state context already established trades one cost for a worse one. A hard turn or token cap on reuse was also rejected, because the variable that actually matters is whether the accumulated context is still load-bearing, not how large the transcript has grown.

## Decision

Resume a worker only while its accumulated context is earning its keep: successive rounds on the same files, within the same effort, minutes apart. A one-line fix to a long-lived or cold worker spawns a fresh agent instead — so does a new and unrelated ask — since the fix would pay for the worker's whole history just to answer it. Rule of thumb: if the delegation prompt would have to restate the context anyway, spawn fresh rather than resume. This is codified in the "Acceptance and re-delegation" section of `plugins/toolkit/doctrine/orchestration.md`.

## Consequences

Conductors write slightly longer delegation prompts when spawning fresh, since file paths and constraints must be restated instead of inherited from a resumed transcript. Genuinely iterative efforts keep warm-resume, so multi-round work on the same files continues to pay cache-read rates rather than premium rewrite rates. A fresh-spawn follow-up pays only a bounded system-prompt-and-context write, instead of a full transcript replay whose cost grows with every round the worker was resumed through. The rule is judgment-based — no token or turn threshold enforces it mechanically — so it is enforced by doctrine reading at delegation time, not by a hook; see `docs/context-economics.md` for the cache mechanics and per-task-shape cost breakdown behind this decision.
