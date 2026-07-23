# Toolkit Design

Why this toolkit is shaped the way it is. Install and setup instructions live in the
repository root README; the working doctrine lives in `CLAUDE.md` + `doctrine/` beside
this file.

## The model in one paragraph

The main chat is a **conductor** that plans, delegates, and accepts; **worker agents**
(explorer, planner, implementer, verifier, the reviewers) do bounded work and report
back in a distilled format. Instructions are split by loading cost: small always-on
essences (the doctrine index, the injected write-time rules) versus on-demand depth
(skills load at their workflow moment, doctrine files are read when their concern is
live). This is progressive disclosure: pay context for what the moment needs, keep the
always-on layer lean.

## Design decisions worth knowing

- **Workers are leaf nodes.** They carry explicit tool allowlists without the Agent
  tool, so they cannot spawn sub-agents; blockers bubble up to the conductor. This
  killed a real failure mode: recursive agent trees that burned tokens until they died.
- **Contracts over tools.** The planning workflow defines an artifact contract (plan
  note frontmatter, naming, lifecycle). Any tooling that visualizes or automates plans
  consumes that contract; the workflow never depends on the tooling.
- **Rules are write-time law; reviewer agents are review-time enforcement** of the
  same sins. Complementary, not redundant.
- **Everything consent-gated.** `/setup` changes nothing without an explicit
  yes; hooks are listed transparently in the root README; the plugin never
  self-privileges (no permission self-grants, no prompt-skipping hooks — the one
  documented lever for that was deliberately rejected).
- **Overridable by design.** Closest scope wins: personal global config overrides
  doctrine; repo-local rules override distributed rules. Disagreement is solved by
  overriding locally or proposing a change upstream — never by forking silently.

## Verification culture

The toolkit's own history is its argument: fixtures approved broken code three times
during its construction; live verification caught every one. Hence the verifier's
prime directive (verify against real data, never fixtures alone), claim provenance as
doctrine, and plan-critic red-teaming plans before humans approve them.
