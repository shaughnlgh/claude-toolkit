---
source: toolkit@shaughn-toolkit
tags: [performance]
---

# Performance

- One round-trip beats two: on production request paths, prefer a single query that does the job over multiple sequential queries. Two queries need a reason; state it.
- Never query inside a loop. Batch, join, or prefetch instead (N+1 is always a defect, not a style choice).
- No blocking I/O or synchronous external calls inside request handlers or render paths.
- Unbounded result sets get pagination or an explicit limit before they ship.
- Columns used in WHERE, JOIN, or ORDER BY on large tables need an index; check before adding the query.
- These rules cover always-wrong patterns. Anything subtler: measure first, don't speculate.
