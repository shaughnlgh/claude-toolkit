# Agents

The toolkit ships 14 agents. The main chat is the **conductor**: it plans, delegates, and accepts. Every change is delegated, no matter how small. The conductor edits nothing itself, and the only override is the human setting `TOOLKIT_CONDUCTOR_EDITS=1` for the session. Agents are **leaf workers** — each carries an explicit tool allowlist and none of them get the Agent tool, so none can spawn sub-agents. A worker that hits a blocker, a question, or an ambiguity reports it back to the conductor instead of delegating around it; the conductor decides how to proceed and remains the only role that decides "done". No agent runs on Haiku. Returns are distilled — file paths and one-line findings, never pasted file contents.

Tools and model are set in each agent's own frontmatter. A per-machine `~/.claude/toolkit-models.json`, set up by `/setup`, can re-route an individual agent's model without touching that frontmatter; see [`overrides.md`](overrides.md). `verify.sh` statically proves the leaf property for all 14: no agent's tool allowlist includes `Agent` or `Task`, none omits an allowlist, and none is routed to Haiku.

Invoke by scoped name (`toolkit:<name>`) so the plugin copy resolves rather than a same-named project-local agent. Projects may override with local agents at `<repo>/.claude/agents/`; project-local agents win when they exist.

Every worker's first step is to confirm the write-time rules `subagent-rules.sh` injected at spawn (see `docs/hooks.md`), so it writes against them without waiting for the conductor to paste them into the delegation prompt.

## Workflow agents

The plan-then-build pipeline: explore, plan, red-team the plan, implement, verify.

| Agent | What it does | When to use |
|---|---|---|
| `toolkit:explorer` | Read-only exploration: codebase search, file discovery, pattern analysis, investigation questions, evidence gathering — including discovery during planning. Never edits. | Proactively, for codebase search, investigation, or evidence gathering without touching files. |
| `toolkit:planner` | Drafts a reviewable implementation plan from evidence fed to it (recall facts, explorer findings), reading further only to close gaps. Never edits or implements. | For non-trivial tasks once discovery evidence is in hand, before any code changes. Not for discovery-only investigation — that is the explorer's job. |
| `toolkit:implementer` | Bounded file changes and focused command runs from an approved plan. | After plan approval, for minimal-scope execution. |
| `toolkit:verifier` | Validates claimed work against real checks and real data (not fixtures alone), reports gaps. Never edits. | Proactively after implementation, to validate before a task is marked complete. |
| `toolkit:plan-critic` | Adversarially red-teams the plan itself, flawed assumptions, missing risks, scope creep, unconsidered alternatives, untestable validation. Reviews the plan, not code. Runs the inversion pre-mortem: the Autopsy in reasoning, then returns the Verdict, objections, Tripwires block, and Walk-away checks block, under 60 lines. Conductor-gated. | After the planner drafts a plan and before human approval, on non-trivial plans. |

## Review agents

Post-hoc quality review of a diff, each via `git diff --name-only`, each with a terse/verbose output mode and an internal ≥80-confidence filter on findings.

| Agent | What it does | When to use |
|---|---|---|
| `toolkit:code-reviewer` | Catches real bugs — off-by-ones, null derefs, logic inversions, race conditions, swallowed errors, complexity. Skips style nitpicks. | After any code change, before committing, or when a PR/diff needs review. |
| `toolkit:security-reviewer` | OWASP-style static analysis — injection, authz flaws, data exposure, weak crypto. Severity-ranked with attack vector and fix. | After changes to auth, input handling, queries, file paths, tokens, or crypto — before deploying any of those. |
| `toolkit:performance-reviewer` | Finds measurable bottlenecks — N+1 queries, memory leaks, blocking I/O, re-renders — not theoretical micro-optimizations. | After changes to hot paths, API endpoints, DB queries, loops over collections, or rendering code. |
| `toolkit:doc-reviewer` | Cross-references docs against actual source: stale references, wrong signatures, missing params, broken examples. | After `.md`, docstring, JSDoc, or API-doc changes — or when code changes may have invalidated existing docs. |
| `toolkit:silent-failure-hunter` | Finds code that fails silently — swallowed errors, failures masked as success, fallbacks that hide breakage. | After any change touching error handling, catch blocks, fallbacks, retries, or async flows — and on every PR review. |
| `toolkit:pr-test-analyzer` | Judges whether tests actually verify the change — assertion-free tests, mock theater, tests that can't fail, weakened or deleted tests. | When a diff adds or changes tests, or changes behavior without touching tests. |
| `toolkit:coupling-reviewer` | Hunts hardcoded account, tenant, or platform identifiers and missing extensibility seams, but only where a second value is already committed in the roadmap, plan, or an existing config surface, never for a speculative axis. Opus. | After changes to config files, tenant or platform wiring, routes, or environment plumbing, and whenever a diff hardcodes an account, tenant, or platform identifier. |

## Browser

| Agent | What it does | When to use |
|---|---|---|
| `toolkit:browser-driver` | Drives Chrome via claude-in-chrome for multi-step journeys: reproduction runs, checkout/login-gated flows, UI verification, dashboard and log-viewer trawls. Prefers text extraction over screenshots, surfaces login walls as blockers (never enters credentials), returns a distilled run report. | Any browser loop longer than a handful of steps. Keeps computer-use steps and screenshots out of the conductor's context — the single most expensive known usage pattern (see `doctrine/orchestration.md`, Context budget). |

## Design

| Agent | What it does | When to use |
|---|---|---|
| `toolkit:frontend-designer` | Designs tokens-first UI with a deliberate design principle, avoids generic AI aesthetics, enforces accessibility, and self-checks its output with the design detector before delivering. States its plan before writing files. | Building or restyling any web UI — pages, dashboards, components. |

## Example invocations

Most of these you never invoke by hand — the conductor spawns them for you. The plan-then-build pipeline (`explorer` → `planner` → `plan-critic` → `implementer` → `verifier`) runs through `plan-guide` / `execution-guide`, and the review agents fire when there is a diff to check. You can also call any of them directly by scoped name:

- **Build or restyle UI** (the one you will reach for most):

      Use the frontend-designer agent to build a pricing card component.

  It states a plan, builds tokens-first, then runs the design detector on its own output and delivers either a clean pass or a justified exception (see [`scripts.md`](scripts.md) for the detector).

- **Review a change before committing:**

      Use the toolkit:code-reviewer on my staged diff.
      Use the toolkit:security-reviewer on the auth changes.

- **Explore without touching anything:**

      Use the toolkit:explorer to find every place we resolve the vault path.

The workflow agents (`planner`, `implementer`, `verifier`, `plan-critic`) are normally driven by the plan and execute skills rather than invoked by hand: `plan-guide` and `execution-guide` when a session follows the steps itself, or `plan-flow` and `execute-flow` when a flow runs them. Start a planning or execution session and they spawn at the right step.

## Why leaf-only

The toolkit's own history is the argument: recursive agent trees (workers spawning workers) burned tokens until they died. Capping workers as leaf nodes — no Agent tool, blockers bubble up — closed that failure mode. See `plugins/toolkit/README.md` for the full design rationale and `plugins/toolkit/doctrine/orchestration.md` for the binding model.
