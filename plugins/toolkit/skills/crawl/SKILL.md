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

Run topic recall first, as `plan-guide` step 1 does: run `python3 <plugin-root>/scripts/topic-recall.py`, where `<plugin-root>` is `../..` from this skill's base directory resolved to an absolute path, over the vault topic notes and the repo's `docs/`, then search prior plan folders. This root takes precedence over a CLAUDE.md line that resolves the installed root. When `../../.claude-plugin/plugin.json` does not exist relative to this skill's base directory, as in a `/toolkit:override` copy under `~/.claude/skills/`, the plugin root is the installed root instead, the path that `jq -r '.plugins["toolkit@shaughn-toolkit"][0].installPath' ~/.claude/plugins/installed_plugins.json` prints, as the setup CLAUDE.md block resolves it. The crawl never re-derives what the vault or the repo already knows.

Then delegate an `explorer` fan-out scoped to the brief's specific claims, per the orchestration doctrine (model escalation for deep tracing; `verifier` instead when evidence needs commands run). The crawl asks two questions of every claim: is it true in the repo, and what does the brief not mention that this work will hit (adjacent modules, callers, migrations, config)?

Assemble, in conversation: verified facts with file:line refs, corrections (the brief says X, the repo says Y), gaps, and open questions only the user can answer.

## 3. Route — present, confirm, then invoke

Apply the rubric to the evidence, not to the brief:

- **wayfinder** — the evidence shows multiple independent workstreams: several subsystems or repos, an issue list rather than one issue, work that cannot be one branch and one plan.
- **plan-guide** — one coherent change with a single decision surface, however large.
- **no plan** — below the planning threshold: a trivial bounded change. Run `testing-gate` and do it.

Present to the user in one block: the evidence summary, the corrections to the brief, the open questions, and the recommended route with the one-line reason. Present the route confirmation itself via the AskUserQuestion form per the communication doctrine, recommended route first. Proceed only on explicit confirmation — except the no-plan route on trivial work, which writes nothing, so there is nothing to gate: state the one-line routing and proceed. A crawl route the user has confirmed counts as the explicit request that wayfinder's own trigger requires — the user said yes to the decomposition, so nothing fires automatically.

**Grill check.** On the wayfinder route only, once the route is confirmed and before the run options, load `grill` (`<plugin-root>/skills/grill/SKILL.md`) and run its loaded grill inline in this session on the section 2 evidence. Grill's Loaded grills paragraph defines the outcome line, the five triggers and what counts as settled. Print the outcome line first, as plain text in this turn, one line that starts `Outcome:` and states the outcome of the work as the grill understands it. It comes before the first question, or before the line that nothing needs an answer, and never goes inside a question form. The confirmed route counts as the explicit request that grill's trigger requires. When no trigger is present, the grill prints `Grill check: nothing in the evidence needs your answer.` and the crawl goes on to the run options. When any is present, state the findings only before the first question, in plain words, one item each, and say what each unconsidered module or caller does, for example: "The brief does not mention module X, which does A, B and C." Ask nothing in this summary, because the grill asks each fold-in-or-leave-out question one at a time. The crawl's corrections and unconsidered modules and callers come first, each as one fold-in-or-leave-out question with a recommended answer. The other items follow in grill's dependency order. Grill settles from the code whatever the code can answer and asks one question at a time. The grill writes nothing to the repo and shows no consent gate, and hands the answers, the agreed glossary terms and the decisions back as text under the line `Agreed in the grill check:`. When the grill ends, it hands back to this section. Each answer joins the evidence: a folded-in item becomes a fact or correction, a left-out item is recorded as out of scope, and an answered question is no longer open. Re-apply the route rubric to the updated evidence, and if the route changes, confirm the new route through the AskUserQuestion form before the run options. Then continue with the run options and section 4. Skip the grill check on the plan-guide route, because the plan's own planning grill asks about this evidence and re-checks the route, on the no-plan route, and when an `expedition` drives this session, because the expedition's own grill gate follows its crawl stage.

On the plan-guide and wayfinder routes, once the route is confirmed, ask the run options per `plan-guide` § Run options (`<plugin-root>/skills/plan-guide/SKILL.md`), at most two AskUserQuestion calls, and keep the answers for the hand off. On the plan-guide route the set also carries the ticket question under its Ticket subsection, and a ticket it creates exists before section 4 derives the plan name. On the wayfinder route ask no ticket question, because a wayfinder parent names no branch and each child's plan flow asks. On the no-plan route ask nothing beyond the testing-gate question, plus the ticket question when the git-safety branch check must create a branch, and each writes its own lines under a blank `plan:` line in `<scratchpad>/flow-run-options`.

## 4. Hand off with the evidence

- **plan-guide route:** load `plan-guide` (`<plugin-root>/skills/plan-guide/SKILL.md`), create the plan directory per its canonical layout, write `brief - <plan-name>.md` beside the plan note (the verbatim brief plus its source reference, ticket URL or "dictated"), and scaffold the plan note with the crawl's evidence pre-filled into Current Context, Assumptions, and Open Questions, `status: planning`. The plan's planning grill runs on this evidence, in the plan flow or under `plan-guide`, and asks about the corrections, missed modules and open questions the scaffold holds. When the grill check ran and the route re-check after it moved the work to the plan-guide route, scaffold the grill check's answers, glossary terms and decisions into Current Context under the line `Agreed in the grill check:`, followed by one line that the plan's Implementation Steps write the terms and decisions as glossary and ADR files on the plan branch, at the locations `doctrine/repo-artifacts.md` defines. Those answers are settled, so the planning grill asks only what they leave open. Write the run option keys from section 3 into the scaffolded note's frontmatter, write the ticket the brief names, else the expedition work note's `ticket` inside an expedition, else section 3's ticket answer, to its `ticket` key, and write `<scratchpad>/flow-run-options` with `plan: <plan-name>` as its first line followed by the run option keys. Then end the reply with the plan flow offer below.
- **wayfinder route:** load `wayfinder` (`<plugin-root>/skills/wayfinder/SKILL.md`) and hand it the brief, the full evidence, the grill check's answers, glossary terms and decisions under the line `Agreed in the grill check:`, and the run option answers, which wayfinder writes into the parent note and copies into every child stub. Wayfinder writes the grill check block once, into the parent note's Current Context, and every child's planning grill reads the block from the parent note and treats it as settled. The first child in the Task Roadmap writes the agreed glossary terms and decisions as glossary and ADR files on its branch in its Implementation Steps, at the locations `doctrine/repo-artifacts.md` defines, and the other children only read them. Wayfinder's alignment step presents the lay of the land from this evidence instead of re-investigating, and wayfinder itself writes the `brief - <plan-name>.md` file beside the parent plan when it emits it (that write is wayfinder's, per its step 4).
- **no-plan route:** no artifacts. Proceed directly under `testing-gate`.

Plan flow offer: on the plan-guide route, after the scaffold, end the reply with one question in plain text and end the turn. Never ask it through AskUserQuestion, because the permission classifier reads the user's typed messages, as `plan-guide` § After approval states. Skip it when an `expedition` drives this session, because the expedition's gates sequence planning.

Lead rename line: after the route is confirmed, on the plan-guide and wayfinder routes, read this session's own name from the first line of ListAgents, which loads through ToolSearch with `select:ListAgents` when it is deferred. The own name is the session name on that line, without the bracketed short id after it. When ListAgents is absent, prints no own-name line, or prints a name that does not start `lead-`, put this one line on the plan-guide route directly above the plan flow offer, and on the wayfinder route at the end of the reply that hands off to wayfinder:

    Optional: run `/rename lead-<name>`, with a name for the whole job this session leads, so session lists show this session as the lead. Skipping it changes nothing.

The plan flow offer takes the worker form when the ListAgents read printed an own-name line, verbatim, where `<key>` is the scaffolded plan note's `ticket` in lowercase when it holds a tracker key or `issue-<n>`, else its `plan` value:

    The plan note is scaffolded. Start worker-plan-<key> to plan it?
    - `start the worker` or `yes`: starts worker-plan-<key> in the background to run the plan flow on the note with the crawl's evidence, and to stop for your approval here (recommended). I tell you here when it needs you or finishes.
    - `run the plan flow here`: plans the note in this session with the plan-builder workflow and stops for your approval.
    - `plan by hand` or `no`: planning continues in this session under plan-guide.

When ListAgents is absent or printed no own-name line, the offer takes the two-option form, because a worker session could not report to this session, verbatim:

    The plan note is scaffolded. Run the plan flow on it now?
    - `run the plan flow` or `yes`: plans the note in this session with the plan-builder workflow and stops for your approval (recommended).
    - `plan by hand` or `no`: planning continues in this session under plan-guide.

The user's next typed message answers it. A slash command such as `/rename` answers nothing.

- `start the worker`, or a bare `yes` in the worker form, starts a worker session. Write the one-line task `Plan the scaffolded plan note.` to `<scratchpad>/worker-task.md` with the Write tool, then run, as its own call with the command first, `bash <plugin-root>/scripts/worker-spawn.sh --scratchpad '<scratchpad>' --type plan --key '<key>' --plan '<planName>' --note '<plan note path>' --lead-name '<own name>' --model '<session_model>' --effort '<session_effort>' --cwd '<main>' --task-file '<scratchpad>/worker-task.md'`, with `<session_model>` and `<session_effort>` the values that section 3's run options recorded and `<main>` the main checkout of the repo the note names. Apply the single-quote rule of `plan-guide` § After approval and handle each outcome as that subsection does, with `run the plan flow here` as the offered fallback.
- `run the plan flow here`, a bare `yes` in the two-option form, or another reply that asks to run the plan flow, such as `run the plan flow`, is the user asking for the plan flow by name. Load `plan-flow` (`<plugin-root>/skills/plan-flow/SKILL.md`) and follow it from section 1 on the scaffolded note. Pass it as `knownEvidence` the crawl's verified facts, each with its file:line, and the Current Context, Assumptions and Open Questions that this section wrote into the note, which hold the crawl's corrections to the brief and its open questions, as plan-flow section 4 defines. The crawl's evidence is the plan flow's discovery, so `plan-flow` section 4 runs no discovery launch and runs the planning grill on it. Leave the brief file as the verbatim brief.
- Any other reply starts no flow. Planning continues under plan-guide as normal, treating the crawl-filled sections as verified evidence rather than re-deriving them, and its Planning Workflow runs the planning grill on the crawl's evidence.

## Boundary

Crawl does not plan (plan-guide's job), does not decompose (wayfinder's job), does not interview requirements (interviewing is grill's job, which the crawl loads and runs inline under the section 3 grill check on the wayfinder route and never imitates itself), does not run `plan-critic`, and does not implement anything. It reads the repo, builds evidence, and routes.
