# Brief template

A brief is the note that opens a piece of work. The `crawl` skill ingests it, and on the plan-guide route and the two direct routes crawl writes it beside the plan note as `brief - <plan-name>.md`. On the wayfinder route wayfinder writes it beside the parent plan. Copy the block below and write each paragraph as one line. Mission Control's New work prompt carries a copy of this block, so the two change together.

```markdown
# <What you want, in one line>

## Goal
<What should be true when this is done, and who it's for.>

## Background
<What you know: the ticket, the problem, an example, anything already decided.>

## Pieces (if you can see them)
1. <A part of the work and what it does.>

## Limits (if any)
- <A deadline, a platform, something not to touch.>

## What I don't know
- <Anything you want the agent to find out, like how two modules connect.>
```

- Goal: the one section a brief needs. The plan's Objective is checked against it, and a goal with two outcomes is two briefs.
- Background: what the author already knows. Crawl verifies each claim in it against the repo, and a decision written here stays settled.
- Pieces: a single-plan brief can leave this out. A multi-part brief numbers each piece, so the decomposition can start from them.
- Limits: what every piece must respect.
- What I don't know: what the author wants the agent to find out. Crawl answers what the repo can answer and lists the rest as open questions.

Leave out any section you have nothing for. The agent asks about what it needs, and crawl recommends the route from the evidence it gathers.
