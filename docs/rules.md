# Rules

The toolkit ships seven write-time rule files under `plugins/toolkit/rules/` — plain checklists that shape code as Claude writes it, not after the fact. Five reach every session automatically: `session-start.sh` reads `testing.md`, `security.md`, `error-handling.md`, `database.md`, and `performance.md` straight out of the plugin, strips their frontmatter, and injects the bodies verbatim into session context (roughly 780 tokens combined). They're current by construction — no local copies to drift, nothing to sync. The other two never get injected; both are reference-only. `frontend.md`'s content is duplicated inside the `frontend-designer` agent, and the injected context ends with a pointer to it instead of its body. `design.md` is a thin index over a separate catalog — `plugins/toolkit/rules/design/` — of per-concern platform-gotcha rule files; see `rules/design.md` for the current concern files. The pointer directs the reader to open only the concern files the current task touches, not the whole catalog: "Frontend work: use the frontend-designer agent, or read rules/frontend.md in this plugin. Design/platform-gotcha rules are indexed in rules/design.md — read only the concern files under rules/design/ that the task touches."

The `rules/design/` catalog exists because platform gotchas are numerous, narrow, and mostly independent of each other — bundling them into one file would force every frontend task to load rules for concerns it doesn't touch. Each concern gets its own small file; `design.md` lists them with a one-line trigger for when each applies, and is the authoritative current list — don't enumerate the concern files here, they change as the catalog grows. New concerns get new files under `rules/design/`, listed in `design.md`; concern files stay small and single-topic. `design-rules-reminder.sh` (see `docs/hooks.md`) makes the catalog surface automatically: it injects a one-line pointer at `design.md` whenever an `Edit`/`Write`/`NotebookEdit` targets a file matching the frontend pattern list, once per session, so reaching for the catalog doesn't depend on the model or the frontend-designer agent remembering to.

Session-start injection reaches only the main conversation — subagents never fire SessionStart. `/setup` extends the global doctrine pointer in `~/.claude/CLAUDE.md` to also name this plugin's `rules/` directory, so a worker can read the relevant file on demand instead of depending on the conductor to paste it into every delegation prompt.

## The set

| Rule | Injected at session start? | What it enforces |
|---|---|---|
| `testing.md` | Yes | Behavior over implementation, real code over mocks except at system boundaries, one assertion per test, fix or delete flaky tests — never retry them. |
| `security.md` | Yes | Validate input at the boundary, parameterized queries only, output sanitization, short-lived tokens, no secrets or PII in logs, rate-limited auth endpoints. |
| `error-handling.md` | Yes | Typed errors with codes, no swallowed errors or floating promises, a consistent HTTP error shape, no leaked stack traces, backoff only on transient failures. |
| `database.md` | Yes | Never edit a migration that already ran — add a new one, both directions must work and be tested, no raw SQL where the ORM has a method, indexes get their own migration. |
| `performance.md` | Yes | Single round-trip over sequential queries on prod paths, no queries in loops (N+1), no blocking I/O in request handlers, paginate unbounded lists, index what you filter and sort on. |
| `frontend.md` | No — reference only | Design tokens before raw values, one design principle per surface, match the project's existing component/animation/icon stack, non-negotiable accessibility (contrast, focus, keyboard, `alt` text). |
| `design.md` | No — reference-only index | Points at the per-concern catalog in `rules/design/` — see `rules/design.md` for the current concern files. Read the concern files, not this index, for the actual rules. |

Don't paste rule bodies into a prompt or plan — they're long, and five of the seven are already in context by the time you'd need them. Read `plugins/toolkit/rules/` for the verbatim text.

## Rules vs. reviewer agents

Rules are write-time law: they shape the diff as the model produces it. Reviewer agents (see `docs/agents.md`) enforce the same concerns at review time, after the code exists. Complementary, not redundant — one guides the writing, the other catches what slipped through.
