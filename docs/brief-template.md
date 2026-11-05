# Brief template

A brief is the note that opens a piece of work. The `crawl` skill ingests it, and on the plan-guide route crawl writes it beside the plan note as `brief - <plan-name>.md`. On the wayfinder route wayfinder writes it beside the parent plan. Copy the block below, keep every heading, and write each paragraph as one line.

```markdown
---
type: brief
repo: <repo name>
status: draft
created: <YYYY-MM-DD>
---

# Brief: <one line naming the outcome>

## Goal

<One sentence: the outcome, for whom, and the limit the work must respect.>

## Context already decided

- <One decision per bullet that the work builds on and must not reopen.>

## Pieces

1. **<Piece name>.** <What it does, in two or three sentences.>

## Constraints

- <One constraint per bullet: doctrine, platform, audience, or deadline.>

## Open questions

- <One question per bullet that only the author can answer. Write "None" when there are none.>

## Route expectation

<One line: single plan, or multi-part with the pieces that go first, and why.>
```

- `status`: `draft` while the author writes it, `ready` when the author hands it over. Crawl does not read this field.
- Goal: the sentence the plan's Objective is checked against. A goal with two outcomes is two briefs.
- Context already decided: the decisions the author does not want reopened. Crawl still verifies each one against the repo like any other claim in the brief.
- Pieces: a single-plan brief has one piece. A multi-part brief numbers each piece, so the decomposition can start from them.
- Constraints: what every piece must respect. A constraint that only one piece needs belongs in that piece.
- Open questions: the questions the author knows only they can answer. Crawl lists them with the open questions it finds.
- Route expectation: the author's guess. Crawl routes on the evidence it gathers, not on this line.
