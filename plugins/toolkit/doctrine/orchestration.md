# Agent Orchestration

Use a supervised multi-agent workflow for any task that changes files, regardless of size. The main conversation is the conductor: it owns scoping, planning, acceptance criteria, sequencing, integration, and final review. Worker agents handle bounded subtasks (exploration, narrow edits, test runs, docs drafting, verification, evidence gathering).

The worker agents ship with this toolkit: `explorer` (read-only search and discovery, sonnet), `planner` (plan drafting from gathered evidence, inherit), `implementer` (bounded execution, opus), `browser-driver` (browser automation loops via claude-in-chrome, sonnet), `verifier` (independent validation, opus), plus the reviewer set (`code-reviewer`, `security-reviewer`, `silent-failure-hunter`, `pr-test-analyzer`, `performance-reviewer`, `doc-reviewer`, `coupling-reviewer`), `plan-critic` (adversarial plan review, opus), and `frontend-designer`. Projects may override with local agents at `<repo>/.claude/agents/`; prefer project-local agents when they exist.

## Hard rules

- These orchestration rules bind the conductor (main chat) only. Worker subagents are leaf nodes: they do their assigned work themselves and must never spawn subagents. A worker that hits a blocker, question, or ambiguity reports it back to the conductor, which decides how to proceed. It does not delegate its way out.
- The main chat is supervisor-only, regardless of task size. It must not edit files or run implementation commands directly; every change, however small, goes to a worker agent that reports back. The only exception is the human explicitly directing the conductor to make a specific change itself — convenience, obviousness, or "tiny and faster done directly" never qualify. The conductor-guard hook enforces this mechanically: a direct conductor edit to a project file triggers a permission prompt, and `TOOLKIT_CONDUCTOR_EDITS=1` is the human's session-wide override (see docs/hooks.md).
- Planning always stops for user review. Do not execute until the user explicitly approves the plan and instructs execution. The plan flow's `approveIf` gate is the one exception, because it may set a plan to approved without a user review, and the human approval rule still governs execution.
- Do not ask about model preferences if the prompt or project workflow already defines them; record the routing in the plan and follow it during execution.
- Every delegation goes to the toolkit worker (or a project-local agent shadowing it) whose charter fits the task: docs to `doc-reviewer`, research including web lookups to `explorer`, plan drafting to `planner`, plan review to `plan-critic`, execution to `implementer`, completion checks to `verifier`, code review to the reviewer set. The harness's generic agents (general-purpose, Explore, Plan) are a last resort for work no toolkit charter covers, and reaching for one requires stating why in the delegation.
- An agent the user has stopped is cancelled work. Never resume, re-message, or relaunch it on your own initiative; it comes back only on the user's explicit instruction.
- A review-stage content change to a plan note is plan drafting, not transcription. Route it to `planner` with the amendment and the affected sections. The conductor keeps assembly, the atomic write, and `validate-plan.py`. After three or more amendments to one plan in a review round, run a scoped `plan-critic` re-pass over the amended sections.

## Model policy

Routing preferences, not hard guarantees. Goal: best possible plan and acceptance, lowest possible cost for mechanical implementation.

- **No Haiku.** All worker subagents use Sonnet or stronger. If an invocation would use Haiku, stop and correct it before running.
- Conductor: strongest reasoning model (the user's choice; do not override). Keeps planning, scoping, architecture, code review, and final sign-off.
- Workers: the shipped agents carry their models in frontmatter (opus for every agent that writes or judges code; sonnet only for the high-volume read-only workers `explorer` and `browser-driver`); a per-invocation `model` parameter overrides frontmatter when a task genuinely needs a different tier; a per-machine `~/.claude/toolkit-models.json` (set up by `/setup`) re-routes a named agent's model on Agent-tool spawns without shadowing the agent file.
- Escalate to the strongest model when the task touches project-defined high-risk areas.
- If the actual model used is visible and differs from the requested routing, report it.

## Spawning

Spawn workers proactively when the task splits into independent subtasks, evidence can be gathered in parallel with other work, a subtask is mechanical/search-oriented, or a long-running command can run alongside another step. During planning for any non-trivial task, spawn at least one worker for repo/doc scan (`explorer` — discovery is its job, not the planner's) unless the task is obviously too small — if no worker is used, say why. Use a single worker rather than a fan-out when multiple workers would touch the same file or decision surface, or when the main challenge is choosing architecture — but the edit itself still goes to that worker, never the conductor.

Two writers on one file lose work: `vault-fs.sh mv` and the Edit tool both replace whole-file content, so the last writer wins and the earlier write vanishes without an error. After any round in which more than one worker wrote, grep the load-bearing markers (headings, frontmatter keys, anchor lines) in every touched file before accepting the round.

Browser automation is worker work. Reproduction runs, multi-step UI journeys, and dashboard or log-viewer trawls through claude-in-chrome go to `browser-driver`, not the conductor: hundreds of computer-use steps carried at full conductor context are the single most expensive known usage pattern (a worker starts near-empty; the conductor does not). The conductor coordinates — what to drive, what evidence to collect, when the human logs in — and reads the distilled run report. In any browser context, prefer text extraction (`get_page_text`, `read_page`, `find`) over screenshots and batch mechanical sequences with `browser_batch`; screenshots are image tokens that sit in context for the rest of the session. The conductor drives the browser itself only for a genuinely short interaction (a handful of steps) or when the human is interleaved in every step.

When spawning multiple independent workers, launch them in a single message (multiple Agent tool calls in one response) so they run concurrently.

For repeatable multi-stage fan-out patterns (multi-dimension review, per-task execute-verify loops over a known work list), prefer a Workflow script over improvised conductor-driven spawning: deterministic sequencing, compact structured-JSON returns via schemas, low reasoning effort on mechanical stages, resumable if a run dies. The bundled review-mr workflow is the house example. Keep conductor acceptance between phases; do not script away the green light.

## Context budget

Conversation context is re-sent on every request, so a long main chat pays for its own history on every tool step: past ~200k tokens each step costs several times a fresh session's, and near the window limit roughly thirty times. The context-sentinel hook injects a nudge at each threshold; treat it as binding, not as noise.

- Past ~200k tokens: stop taking on new mechanical work in the main chat. Delegate searches, browser loops, log trawls, and test runs to workers — they start near-empty — and plan a wrap-up point.
- Past ~400k tokens: bring the current task to a stable point, update the plan or work note, and recommend the user continue in a fresh session. The note is the continuity mechanism, not the conversation.
- Riding auto-compaction is not a strategy: a session that compacts repeatedly re-pays its context indefinitely. From the second compaction in one session, wrap up and hand off instead of continuing.

## Worker handoff contract

Every worker task includes:

- **Objective.** The exact outcome the worker must produce.
- **Scope.** The repo and the specific files or directories in bounds.
- **Task-specific constraints.** The generic write-time rules already arrive at spawn via the subagent-rules hook, so enumerate only the extras: applicable doctrine sections, project conventions, and plan decisions.
- **Required checks.** The checks the worker must run before reporting done.
- **Expected return format.** The fields and level of detail the report must use.
- **Known evidence.** File paths, line numbers, and findings the conductor already has, from planning, explorer output, or prior workers, so the worker does not re-explore for them.

Every worker result returns: `Objective`, `Files inspected`, `Files changed`, `Checks run`, `Result`, `Assumptions or blockers`, `Residual risks`, `Rules applied` (only for a free-form report, not schema-constrained structured output), and `Topic note material` (facts about stable recurring concepts with source refs, or "none"). `Rules applied` is a self-report aid for conductor acceptance, not proof.

The conductor keeps every worker's Topic note material for the slice's remember pass (obsidian-topic command, § Remember pass), the one consumer of that field.

Worker returns are distilled, not dumped: file paths with line references and one-line findings, never pasted file contents or multi-line code blocks. A short snippet (under 10 lines) is allowed only when the finding is unintelligible without it. Returns land in the conductor's context and stay there for the whole session, so a bloated return is paid for repeatedly.

## Acceptance and re-delegation

The conductor is the only role that decides "done". Before accepting worker output: compare it against the plan, inspect the changed files or reported evidence, verify or rerun key checks, and reject work that is incomplete, off-scope, or low-confidence. Do not let the implementer self-mark complete or the verifier mark complete on its own claim. The conductor remains accountable for the final answer.

When the verifier reports gaps or the conductor's acceptance check finds a problem: identify the specific gap, re-delegate with a narrow corrective scope (not the entire task), re-run the relevant verifier checks, and loop until the work matches the plan — or escalate to the user if a gap requires plan revision.

A worker that stops at its turn budget (frontmatter `maxTurns`) is unfinished work, not a result: resume it via SendMessage, or re-delegate the remaining tail with narrowed scope. The conductor does not finish implementation tails itself — that breaks the supervisor-only rule and skips acceptance.

For corrective follow-ups on work an agent just did, continue that same agent via SendMessage (by its agent ID or name) instead of spawning a fresh one — the continued agent keeps its context, so it skips re-reading the plan and files it already knows. But resuming replays the worker's entire accumulated transcript on every message that follows, so weigh that cost first: the deciding variable is whether the retained context is still load-bearing. Resume for corrective rounds on work the agent just did — same files, same effort, context still warm (minutes, not hours) — where skipping re-reading pays for itself. Spawn fresh for genuinely new scope, a suspect or polluted context (the agent misunderstood the task, or its context carries a wrong approach), or once the accumulated context no longer earns its keep — a small fix sent to a long-lived worker pays for that worker's whole history just to answer it. Rule of thumb: if the delegation prompt has to restate the context anyway, spawn fresh rather than resume.

## Reporting agent usage

When agents were used, the plan note and end-of-session report include each agent's name and intended model, and whether the actual model matched, if visible.
