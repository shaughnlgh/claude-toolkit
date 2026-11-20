---
title: Ticket question and ticket creation on the user's yes
summary: Before a plan name or branch is derived for work with no ticket, the agent asks once whether to use an existing ticket, create one, or go without, records the answer, and creates a ticket only on the user's explicit yes to a shown draft.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-08
---

# 0007. Ticket question and ticket creation on the user's yes

Date: 2026-11-08

Status: Accepted

Amended by [0015](0015-lead-and-worker-sessions.md), which replaces the bullet "A parent session may answer the ticket question but never the create confirmation", so the lead answers a worker session's ticket question by message and the create confirmation goes from the worker session to the user through AskUserQuestion.

Amended when crawl replaced its route without a plan note by two direct routes, which record a plan note and ask the ticket question with the run options as the plan-guide route does. The first Decision bullet now names the two direct routes beside the plan-guide route, and the third Decision bullet now names work with no plan note where it named that former crawl route.

## Context

The git-safety doctrine suggested branch names with no condition, and on the default branch it fell back to `<type>/<slug>` when there was no ticket without asking whether one existed, so a side fix found on a feature branch or a small fix on main got a branch with no ticket question. The plan-guide skill derived the plan name from the task alone when no ticket was given and left `ticket` blank, so blank meant both "never asked" and "chose none". The plan builder told the planner that the branch is `<type>/<slug>`, and the plan flow accepted a branch with no ticket. The jira skill was read-only, so a ticket for new work had to be created outside the session. A company's ticket rules, such as key prefixes, labels, and sprint links, live in that company's own plugin and reach the session only as injected project rules, so the toolkit cannot name a company host or tracker.

## Decision

- The ticket question joins the run options set and is asked before a plan name or branch is derived. Crawl asks it with the run options on the plan-guide route and on the two direct routes, the plan flow asks it in its own call once its route is settled, the expedition skill asks it at ingestion, and git-safety asks it before it suggests any branch for such work, wherever HEAD is.
- A wayfinder parent names no branch and is never asked, and each wayfinder child is asked. The execute and ship flows and incident-investigate never ask.
- The answer is recorded once as a key, `issue-<n>`, or `none` on the note's `ticket` key, or on work with no plan note as `ticket:` and `ticket_work:` lines in the run options cache, and it is reused only for the same work.
- The tracker follows the origin remote. An entry in `~/.claude/toolkit-trackers.json` wins. Otherwise github.com is GitHub issues, another host is Jira when the session's loaded project rules name ticket key prefixes and jira-cli is configured, and anything else has no tracker.
- A ticket is created only on the user's explicit yes to a shown draft that names its repo or project, after a same-area search. Using a same-area ticket records its key, and the user adds the problem to that ticket by hand.
- A parent session may answer the ticket question but never the create confirmation, which always goes to the user, as plan approval does.
- The plan flow inserts the recorded ticket after the branch's type prefix.
- The jira skill creates with `jira issue create`, carrying the fields the project's rules require, and links the new key with `jira sprint add`. It never transitions, assigns, labels, comments on, or edits an existing ticket. This replaces the jira skill's Boundary clause "never transition, assign, label, comment, or create" for creation only, and the transport choice in [0001](0001-jira-transport-jira-cli-over-acli.md) stands.
- The run options take at most two AskUserQuestion calls with up to five run option questions, plus the ticket question when crawl asks it, and every other asker puts the ticket question in its own call. This replaces the [0003](0003-run-options-on-the-plan-note.md) sentence that a flow asks up to five questions in all. The create procedure's own questions follow a Create a ticket answer and sit outside that cap.

## Consequences

New work with no ticket gets one more question, once per piece of work, and each wayfinder child gets one. The plan flow on a ticket-less brief makes one more AskUserQuestion call. A note records `none`, so a tool that reads the `ticket` key must read `none` as no ticket. Creation is not a git mutation, so it runs under any ceiling, gated by the user's yes and the permission prompt, and a classifier denial ends in a handoff. An unattended session that reaches the create confirmation waits for the user. A work repo whose session lacks the project's ticket rules or jira-cli is offered no Jira ticket unless an override names `jira`. A repo whose tracker differs from these defaults needs an override.
