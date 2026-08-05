# Conventions

## Project discovery

Before planning in a project, inspect applicable project-local instructions where present:

- CLAUDE.md
- AGENTS.md
- .claude/rules/
- .claude/README.md
- relevant docs/

Project-local rules take precedence when they are more specific and do not conflict with safety rules.

## Docs-first discipline

Before planning or implementing non-trivial tasks, read the relevant repository docs,
config, and existing patterns.

- Prefer the repository's actual state over stale docs.
- If docs conflict with code, surface the mismatch explicitly.
- If docs are missing or insufficient, flag the gap.
- Do not invent architecture when docs are silent.
- State which docs and config were read when presenting a plan.
- When writing new repo docs, resolve the location from `doctrine/repo-artifacts.md` instead of inventing a path.

Each project defines its own required docs and verification files in its
`01-project-core.md` or equivalent. Read those project-specific lists when they exist.

## Authorship

The developer delegates the typing, not the authorship. Write code as they would have
written it, not in your own idiom.

- Match the established pattern in the codebase. When a way of doing something already
  exists (a method, a service, a helper, a config approach), use it. Do not invent a
  parallel approach that then has to be maintained alongside the original.
- Follow the framework's own standards over clever shortcuts (e.g. in Magento, load CSS
  via layout XML, not injected hacks). Honor project-local conventions and rules over
  generic defaults.
- Prefer first-principles debugging into core systems over speculative or defensive
  patches. That is the expected depth here.
- When there is a genuine reason to deviate from an existing pattern or convention,
  flag it and ask first before proceeding. Do not silently introduce a new approach.

## Code comment style

Applies to all code written or edited in any project, on top of project-local
formatting rules.

- Inline comments are a single line or omitted entirely. Never write multi-line
  comment blocks explaining code.
- Default to no comment. Add one short line only when the WHY is non-obvious
  (hidden constraint, surprising behavior, workaround for a specific bug).
- Required structural docblocks (e.g. PHP method docblocks) stay, but keep their
  descriptions to a single line.
- Do not narrate the change, the task, or debugging history in comments.
  Temporary instrumentation must be clearly marked and removed before completion.
- Code markers use the form `TODO(author): description (#issue)` (same for
  `FIXME`/`HACK`) so they are greppable and attributed; never leave a bare `TODO`.
