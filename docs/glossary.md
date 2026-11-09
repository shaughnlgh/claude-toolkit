<!-- managed-by: toolkit/grill -->
# Context

## Glossary

### Brief

The verbatim planning input: the user's words plus any ticket content, captured exactly and never paraphrased. Every piece of new work enters the planning workflow as a brief, whatever its source.

### Ticket Adapter

A skill that turns an external ticket reference into a brief. Fetching and recording is the adapter's job. It creates a ticket only on the user's yes to a draft it showed, and never judges or changes an existing ticket.

### Ticket question

The one question, asked before any branch or plan name is derived for work with no ticket, whether to use an existing ticket, create one, or go without. The answer is recorded once, on the plan note's `ticket` key or in the session cache beside the work it answers, so it is never asked twice for the same work.

### Topic recall

The lookup `scripts/topic-recall.py` runs over the vault's topic notes and, when given `--repo-root`, the repo's `docs/` folder. It ranks hits by the query words found in each title and summary. The session-start hook injects the top hits for the current repo. `plan-guide`, `execution-guide`, and `crawl` run it with the task words before they read code.

### Remember pass

The once-per-slice step that routes the durable facts a slice surfaced. One `implementer` stages shareable facts about the repo as proposed `docs/context/` content behind the conductor's consent gate, and folds every other fact into vault topic notes. `red-team` step 7b runs it after the doc pass, or `plan-guide` Session Closure runs it if red-team has not. A `Remember:` line records that it ran. The Doc Update Pass keeps existing docs accurate about what changed. The remember pass records what the slice learned.

### Remember guard

The `remember-guard.sh` Stop hook. It warns the user when a reply has a line that begins `Suggested commit` while the session's in-progress plan note has no `Remember:` line under Plan Changes During Execution. It only warns and never blocks. `validate-plan.py` enforces the line at completion: it rejects a plan at status completed, created on or after 2026-10-18, that has no `Remember:` line there.

### Flow

A skill whose name ends in `-flow`, driven by a Workflow script under `plugins/toolkit/workflows/`. A flow reads its run options, the ceiling first, from the plan note, else from the session cache when the cache names the same plan, and asks only for the keys neither has. The `## Flows` section of `doctrine/git-safety.md` defines what each ceiling permits. The toolkit ships three flows. `plan-flow` runs no git under any ceiling. `execute-flow` asks nothing after it reads the run options. It mutates git only to open a worktree on a held or dirty seat, or on a free, clean seat whose main checkout sits on its default branch on a run from approved or start-work, through EnterWorktree under any ceiling, or through `git fetch` and `git worktree add` for an existing branch only under `mr` or `merge` and as paste-ready commands under `none`, or through `git worktree add -b` for the note's branch when it exists nowhere only under `mr` or `merge`, and for the seat run's switches, fix commit, and restore under `mr` or `merge`. Otherwise its agents run in the target repo only the read-only git commands that section lists. Apart from those commands, `ship-flow` is the only flow that mutates git, only under `mr` or `merge`, and its agents run each stage's commands under a rule that names only that stage's commands.

### Guide

A skill whose name ends in `-guide`, the manual a session follows by hand. `plan-guide` holds the plan note contract: artifact locations, naming, frontmatter and sections, the planning steps, the status lifecycle, session recording, and session closure. `execution-guide` holds the execution steps, the progress report format, the Doc Update Pass, and the runtime-evidence debugging method. The flows run the same work for you, and `plan-flow` and `execute-flow` read these guides where they need the contract.

### Ceiling

The `ceiling` run option on a plan note: `none`, `mr`, or `merge`. It is the stage the ship flow stops at and the limit on what any flow may do in git. `merge` with `tag_merge: true` adds the tag stage, which the ship runner calls `release` internally. `merge` also runs the ship runner's cleanup after the merge, which removes the plan's worktree, returns the main checkout to the default branch, and deletes the merged branch. Defined in `skills/plan-guide/SKILL.md` § Run options.

### flow-run-options

The file at `<scratchpad>/flow-run-options` that caches a plan note's run option keys for the session. Its first line is `plan: <slug>`, naming the plan it serves, and a flow reads it only for that plan. One `key: value` line follows per key. A missing file means unasked. A missing, empty, or unrecognised `ceiling` line reads as `none`. On work with no plan note, the file holds a blank `plan:` line followed by the testing gate's `tests:` line, the ticket question's `ticket:` and `ticket_work:` lines, or both, and no plan flow reads it. A resumed session keeps its scratchpad and so keeps the cache. A new session reads the plan note.

### Seat run

Section 11 of the `execute-flow` skill. It runs the Validation Steps that a worktree run deferred, against the running local stack, from a session in the main checkout, which a session inside the plan's worktree reaches by leaving it with ExitWorktree keep while no other session holds the main checkout. It checks the committed plan branch out in a free and clean main checkout, runs the steps through the execute runner's fix round, panel, and cold read with the worktree run's baseline, commits its own fixes under `mr` or `merge`, and restores the branch the main checkout was on. A pass records `Seat run passed:` with the plan branch tip, which lifts the ship flow's cap at `mr`. An `[e2e]` step is a Validation Step that carries `[e2e]` directly after its number, which marks it as needing the running local stack. A worktree run defers it, and the `e2e` run option and the seat run read the same marker.
