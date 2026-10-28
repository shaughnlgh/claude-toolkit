# Review rules

The execute runner reads the High-risk paths section as one path per bullet. Write paths plain.

## What failure looks like here

- A skill whose prose promises one thing and whose commands do another.
- A hook that blocks a safe command or passes a dangerous one.
- A workflow script that gates on the wrong field or reads a key the child does not return.
- A verify.sh check that passes when the thing it checks is gone.

## Evidence rule

- Every finding cites a file:line you read. A claim inferred from a name alone is not a finding.
- A command embedded in prose is code: run it against a scratch fixture before judging it.
- A finding on a path under Paths to skip is refuted with the reason skipped path.
- Below 0.6, a code finding's reproduction is the cited line as read, and the fix prompt labels it `cited line read`, not `reproduced`.

## Nit cap

- At most five unreproduced nits per review, ranked by score. The rest are dropped and counted. A doc finding is never a nit.

## Paths to skip

- plugins/toolkit/scripts/design-detector/
- THIRD-PARTY-NOTICES.md
- LICENSE

## High-risk paths

- plugins/toolkit/hooks/
- plugins/toolkit/scripts/
- plugins/toolkit/workflows/
- .github/
- verify.sh
- REVIEW.md

## Always check

- A new workflow script has a suite under plugins/toolkit/workflows/tests/<name>/ and a verify.sh block with its floor.
- A new skill is counted in verify.sh and listed in docs/skills.md.
- A defect the panel missed and a later review or a user found gets a harness case in the suite of the script it touched.

## Known false positives

- (one line per dimension, in the form <dimension>: <what to check before reporting this again>)
