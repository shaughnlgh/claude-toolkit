# Docs index

Every page under `docs/`, with what each covers. The root [`README.md`](../README.md) covers install, setup and updating.

## The components

- [`prerequisites.md`](prerequisites.md): the CLI prerequisites, what each is for, and the install and auth commands.
- [`skills.md`](skills.md): the skills, what each does and when it fires.
- [`brief-template.md`](brief-template.md): the shape of the brief that opens a piece of work.
- [`agents.md`](agents.md): the 14 worker agents and the conductor and leaf-worker model.
- [`commands.md`](commands.md): the eight slash commands, among them `/setup`, `/topic`, `/override` and the thinking tools.
- [`hooks.md`](hooks.md): the twelve hooks that run once the plugin is installed, with no opt-in: what each blocks, what it only asks, its environment variables, and how it fails safe.
- [`rules.md`](rules.md): the write-time rules injected into every session and every worker.
- [`scripts.md`](scripts.md): the shipped scripts and their guardrails.
- [`workflows.md`](workflows.md): the multi-agent workflows, which are the review engine, the plan flow, the execute flow and the ship flow.

## How it works

- [`../plugins/toolkit/README.md`](../plugins/toolkit/README.md): the conductor-and-workers model and the design decisions behind it.
- [`../plugins/toolkit/CLAUDE.md`](../plugins/toolkit/CLAUDE.md): the doctrine index, one concern per file under [`doctrine/`](../plugins/toolkit/doctrine).
- [`overrides.md`](overrides.md): how to replace any doctrine file, rule, agent or skill with your own copy, and how `/override` works.
- [`context-economics.md`](context-economics.md): how prompt-cache mechanics drive cost, and the practices and doctrine that follow from it.
- [`../VERIFY.md`](../VERIFY.md): the live-session verification checklist. The mechanical battery is `verify.sh`.
- [`../REVIEW.md`](../REVIEW.md): the review rules the review panel reads from the default branch, and the high-risk paths that pick the full six-reviewer panel.

## Glossary

- [`glossary.md`](glossary.md): the terms the docs, skills and doctrine use with one fixed meaning.

## Decision records

- [`0001`](decisions/0001-jira-transport-jira-cli-over-acli.md): Jira transport, community jira-cli over official acli.
- [`0002`](decisions/0002-worker-resume-vs-fresh-spawn.md): Worker resume vs fresh spawn.
- [`0003`](decisions/0003-run-options-on-the-plan-note.md): Run options on the plan note.
- [`0004`](decisions/0004-execute-flow-asks-nothing-after-approval.md): Execute flow asks nothing after approval.
- [`0005`](decisions/0005-approval-offers-the-execute-flow.md): Approval offers the execute flow.
- [`0006`](decisions/0006-ship-flow-merges-unattended.md): Ship flow merges unattended.
- [`0007`](decisions/0007-ticket-question-and-creation-on-yes.md): Ticket question and ticket creation on the user's yes.
- [`0008`](decisions/0008-crawl-session-is-the-parent.md): Crawl session is the parent.
- [`0009`](decisions/0009-seat-queue-in-the-git-common-dir.md): Seat queue in the git common dir.
- [`0010`](decisions/0010-plans-span-several-repos.md): Plans span several repos.
- [`0011`](decisions/0011-execute-flow-caps-runs-per-plan.md): Execute flow caps runs per plan.
- [`0012`](decisions/0012-grill-is-a-fixed-step-of-planning.md): Grill is a fixed step of planning.
- [`0013`](decisions/0013-rewrite-history-in-place-before-going-public.md): Rewrite history in place before going public.

## Context notes

- [`context-execute-flow-adjudication.md`](context/context-execute-flow-adjudication.md): Execute flow adjudication.
- [`context-git-tree-state-capture.md`](context/context-git-tree-state-capture.md): Git tree state capture.
- [`context-macos-script-portability.md`](context/context-macos-script-portability.md): macOS script portability.
- [`context-model-routing.md`](context/context-model-routing.md): Model routing.
- [`context-plan-note-section-checks.md`](context/context-plan-note-section-checks.md): Plan note section checks.
- [`context-plugin-packaging.md`](context/context-plugin-packaging.md): Plugin packaging.
- [`context-review-scoring.md`](context/context-review-scoring.md): Review scoring.
- [`context-ship-flow-constraints.md`](context/context-ship-flow-constraints.md): Ship flow constraints.
- [`context-watch-mr.md`](context/context-watch-mr.md): Watch MR script.
- [`context-workflow-script-authoring.md`](context/context-workflow-script-authoring.md): Workflow script authoring.
- [`context-worktree-seat.md`](context/context-worktree-seat.md): Worktree seat.

## Outside tools the docs name

- Mission Control: the maintainer's separate session dashboard. Some docs name it because it launches sessions or reads plan notes, and nothing in the toolkit requires it.
- Warden: an open source Docker environment for Magento. The execute flow detects it and runs the Composer install inside its `php-fpm` container.
