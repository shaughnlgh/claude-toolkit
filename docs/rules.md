# Rules

The toolkit ships six write-time rule files under `plugins/toolkit/rules/` — plain
checklists that shape code as Claude writes it, not after the fact. Five reach every
session automatically: `session-start.sh` reads `testing.md`, `security.md`,
`error-handling.md`, `database.md`, and `performance.md` straight out of the plugin, strips their
frontmatter, and injects the bodies verbatim into session context (roughly 780 tokens
combined). They're current by construction — no local copies to drift, nothing to sync.
The sixth, `frontend.md`, never gets injected. It's reference-only: its content is
duplicated inside the `frontend-designer` agent, and the injected context ends with a
pointer to it instead of its body — "Frontend work: use the frontend-designer agent, or
read rules/frontend.md in this plugin."

## The set

| Rule | Injected at session start? | What it enforces |
|---|---|---|
| `testing.md` | Yes | Behavior over implementation, real code over mocks except at system boundaries, one assertion per test, fix or delete flaky tests — never retry them. |
| `security.md` | Yes | Validate input at the boundary, parameterized queries only, output sanitization, short-lived tokens, no secrets or PII in logs, rate-limited auth endpoints. |
| `error-handling.md` | Yes | Typed errors with codes, no swallowed errors or floating promises, a consistent HTTP error shape, no leaked stack traces, backoff only on transient failures. |
| `database.md` | Yes | Never edit a migration that already ran — add a new one, both directions must work and be tested, no raw SQL where the ORM has a method, indexes get their own migration. |
| `performance.md` | Yes | Single round-trip over sequential queries on prod paths, no queries in loops (N+1), no blocking I/O in request handlers, paginate unbounded lists, index what you filter and sort on. |
| `frontend.md` | No — reference only | Design tokens before raw values, one design principle per surface, match the project's existing component/animation/icon stack, non-negotiable accessibility (contrast, focus, keyboard, `alt` text). |

Don't paste rule bodies into a prompt or plan — they're long, and five of the six are
already in context by the time you'd need them. Read `plugins/toolkit/rules/` for the
verbatim text.

## Rules vs. reviewer agents

Rules are write-time law: they shape the diff as the model produces it. Reviewer
agents (see `docs/agents.md`) enforce the same concerns at review time, after the code
exists. Complementary, not redundant — one guides the writing, the other catches what
slipped through.
