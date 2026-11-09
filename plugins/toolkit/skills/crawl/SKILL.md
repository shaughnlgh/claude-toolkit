---
name: crawl
description: >-
  Front door for new work. Use when a session opens with a new piece of work — a
  brief, a ticket reference, or a stated task — and no plan note exists for it yet.
  Ingests the brief, validates it against the codebase (topic recall + explorer
  fan-out), then recommends a route: wayfinder for genuinely multi-part efforts,
  plan-guide for a single coherent change, or no plan at all below the planning
  threshold. On routes that write artifacts, the user confirms the route first; the
  trivial no-plan route states its routing in one sentence and proceeds. Fires on new
  work whether it arrives at session start or mid-session. Crawl runs BEFORE
  testing-gate when both match — route first, then the gate decides testing on the
  chosen route. Do not fire when a plan note (including a pre-scaffolded one) already
  exists for the work (that is plan-guide, or plan-flow when the user asks for the
  plan flow by name), when the user explicitly invokes any skill by name (grill,
  wayfinder, plan-guide, expedition, gitlab-mr-review, handoff, or any other), or
  on trivial Q&A and explanation-only sessions.
---

# Crawl

Crawl validates a brief against repository reality before any planning starts, then routes the work to the right depth of process. It exists because briefs are optimistic: they name the wrong module, assume code that does not exist, and omit the migration that triples the scope. The hidden gaps are exactly what determines whether the work is one plan or many, so the routing decision is an output of investigation, never of how the request was phrased.

Crawl is read-only against the repo. It writes nothing anywhere until the user confirms the route, and then only vault artifacts through the routed skill's own mechanics.

## Trigger and scope

Fire when new work arrives — a brief, a ticket link, a dictated task — at session start or mid-session, and no plan note exists for it. Do not fire when the prompt points at an existing or pre-scaffolded plan note (that is `plan-guide`, or `plan-flow` when the user asks for the plan flow by name), when the user explicitly invokes any skill by name — grill, wayfinder, plan-guide, expedition, gitlab-mr-review, handoff, or any other (their explicit trigger wins) — or on Q&A that plainly needs no plan. When both crawl and `testing-gate` match a prompt, crawl runs first: route, then gate testing on the chosen route.

Thin-crawl skip: when the brief already names exact files and functions and those facts are verified (a bug the user already diagnosed), or topic recall shows a prior crawl or plan covering the same ground, skip the investigation, say why, and route directly. Skipping requires a stated reason, the same discipline as every other gate in this toolkit.

Stay cheap on small work. "Here's an error, go fix it" must never grow ceremony: the thin-skip plus the no-plan route collapse to a single sentence ("brief checks out against the repo, below planning threshold — handing off to implementer for a direct fix") with no confirmation gate. The full present-and-confirm routing block is for work where the route is genuinely in question. The `expedition` skill uses crawl as its stage 2; that changes nothing about how crawl behaves standalone.

## 1. Ingest

Capture the brief verbatim — the user's words, plus the ticket content when a reference is given. For GitLab issues or MRs, fetch via `glab` (read-only). For Jira keys or ticket URLs, load the `jira` skill (`<plugin-root>/skills/jira/SKILL.md`) and use the verbatim brief it returns as the ticket content. Merge everything into one brief without paraphrasing requirements away. Hold it in conversation; nothing is written yet.

Crawl needs no particular brief shape. A brief written from the toolkit repo's brief template, which the plugin does not ship, goes through every step below like any other brief.

## 2. Investigate

Run topic recall first, as `plan-guide` step 1 does: run `python3 <plugin-root>/scripts/topic-recall.py`, where `<plugin-root>` is `../..` from this skill's base directory resolved to an absolute path, over the vault topic notes and the repo's `docs/`, then search prior plan folders. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. The crawl never re-derives what the vault or the repo already knows.

Then delegate an `explorer` fan-out scoped to the brief's specific claims, per the orchestration doctrine (model escalation for deep tracing; `verifier` instead when evidence needs commands run). The crawl asks two questions of every claim: is it true in the repo, and what does the brief not mention that this work will hit (adjacent modules, callers, migrations, config)?

Assemble, in conversation: verified facts with file:line refs, corrections (the brief says X, the repo says Y), gaps, and open questions only the user can answer.

## 3. Route — present, confirm, then invoke

Apply the rubric to the evidence, not to the brief:

- **wayfinder** — the evidence shows multiple independent workstreams: several subsystems or repos, an issue list rather than one issue, work that cannot be one branch and one plan.
- **plan-guide** — one coherent change with a single decision surface, however large.
- **no plan** — below the planning threshold: a trivial bounded change. Run `testing-gate` and do it.

Present to the user in one block: the evidence summary, the corrections to the brief, the open questions, and the recommended route with the one-line reason. Present the route confirmation itself via the AskUserQuestion form per the communication doctrine, recommended route first. Proceed only on explicit confirmation — except the no-plan route on trivial work, which writes nothing, so there is nothing to gate: state the one-line routing and proceed. A crawl route the user has confirmed counts as the explicit request that wayfinder's own trigger requires — the user said yes to the decomposition, so nothing fires automatically.

On the plan-guide and wayfinder routes, once the route is confirmed, ask the run options per `plan-guide` § Run options (`<plugin-root>/skills/plan-guide/SKILL.md`), at most two AskUserQuestion calls, and keep the answers for the hand off. On the plan-guide route the set also carries the ticket question under its Ticket subsection, and a ticket it creates exists before section 4 derives the plan name. On the wayfinder route ask no ticket question, because a wayfinder parent names no branch and each child's plan flow asks. On the no-plan route ask nothing beyond the testing-gate question, plus the ticket question when the git-safety branch check must suggest a branch, and each writes its own lines under a blank `plan:` line in `<scratchpad>/flow-run-options`.

## 4. Hand off with the evidence

- **plan-guide route:** load `plan-guide` (`<plugin-root>/skills/plan-guide/SKILL.md`), create the plan directory per its canonical layout, write `brief - <plan-name>.md` beside the plan note (the verbatim brief plus its source reference, ticket URL or "dictated"), and scaffold the plan note with the crawl's evidence pre-filled into Current Context, Assumptions, and Open Questions, `status: planning`. Write the run option keys from section 3 into the scaffolded note's frontmatter, write the ticket the brief names, else the expedition work note's `ticket` inside an expedition, else section 3's ticket answer, to its `ticket` key, and write `<scratchpad>/flow-run-options` with `plan: <plan-name>` as its first line followed by the run option keys. Then end the reply with the plan flow offer below.
- **wayfinder route:** load `wayfinder` (`<plugin-root>/skills/wayfinder/SKILL.md`) and hand it the brief and the full evidence and the run option answers, which wayfinder writes into the parent note and copies into every child stub. Wayfinder's alignment step presents the lay of the land from this evidence instead of re-investigating, and wayfinder itself writes the `brief - <plan-name>.md` file beside the parent plan when it emits it (that write is wayfinder's, per its step 4).
- **no-plan route:** no artifacts. Proceed directly under `testing-gate`.

Plan flow offer: on the plan-guide route, after the scaffold, end the reply with one question in plain text and end the turn. Never ask it through AskUserQuestion, because the permission classifier reads the user's typed messages, as `plan-guide` § After approval states. Skip it when an `expedition` drives this session, because the expedition's gates sequence planning.

Before the question, read this session's own name from the first line of ListAgents, which loads through ToolSearch with `select:ListAgents` when it is deferred. The own name is the session name on that line, without the bracketed short id after it. When ListAgents is absent, prints no own-name line, or prints a name that does not start `parent-`, put this line directly above the question, with `<planName>` set to the scaffolded note's `plan` value:

    To mark this session as the plan's parent, run `/rename parent-<planName>` before you answer.

The question, verbatim:

    The plan note is scaffolded. Run the plan flow on it now?
    - `run the plan flow` or `yes`: plans the note in this session with the plan-builder workflow and stops for your approval (recommended).
    - `plan by hand` or `no`: planning continues in this session under plan-guide.

The user's next typed message answers it. A slash command such as `/rename` answers nothing.

- `yes`, or a reply that asks to run the plan flow, such as `run the plan flow`, is the user asking for the plan flow by name. Load `plan-flow` (`<plugin-root>/skills/plan-flow/SKILL.md`) and follow it from section 1 on the scaffolded note. Pass it as `knownEvidence` the crawl's verified facts, each with its file:line, and the Current Context, Assumptions and Open Questions that this section wrote into the note, which hold the crawl's corrections to the brief and its open questions, as plan-flow section 4 defines. Leave the brief file as the verbatim brief.
- Any other reply starts no flow. Planning continues under plan-guide as normal, treating the crawl-filled sections as this session's ground truth rather than re-deriving them.

## Boundary

Crawl does not plan (plan-guide's job), does not decompose (wayfinder's job), does not interview requirements (grill's job — crawl surfaces open questions but never runs the one-question-at-a-time elicitation; when the open questions need real elicitation, recommend a grill and stop), does not run `plan-critic`, and does not implement anything. It reads the repo, builds evidence, and routes.
