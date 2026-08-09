# Workflows

Workflows are multi-agent orchestrations the toolkit ships as scripts under `plugins/toolkit/workflows/`, run through the Workflow tool rather than a single agent turn. There is currently one: `review-mr`, driven by the `gitlab-mr-review` skill against fetched MR diffs and the `red-team` skill against local uncommitted slice diffs (passing `repoState`).

## review-mr.js

Multi-dimension MR review. It runs two phases:

- **Review** — fans out the toolkit reviewer agents (`toolkit:code-reviewer`, `toolkit:security-reviewer`, `toolkit:silent-failure-hunter`, `toolkit:performance-reviewer`, `toolkit:pr-test-analyzer`) plus any MR-specific custom dimensions, each reading the saved diff and reporting findings against a shared schema (title, file, severity, detail, failure scenario). A dimension that can't answer something from the diff or repo returns it as an `open_questions` entry instead of guessing.
- **Verify** — every finding from every dimension is checked again by a separate `toolkit:verifier` agent instructed to try to refute it: does the code path really execute, is the failure scenario reachable, is it already handled elsewhere. The verifier defaults to refuted when a claim is unreachable or speculative.

The workflow then adjudicates its own results — splitting findings into `confirmed`, `refuted` (with reasoning), `unverified` (verifier died mid-run — the conductor must settle these), and `openQuestions` — and returns that structure. It does not produce a final report itself; that's the calling skill's job.

Reviews are run against the diff plus a local checkout at `repoRoot`, whose state the `repoState` argument declares — a target-branch checkout for `gitlab-mr-review`, the post-change working tree for `red-team` — so any claim about existing code, callers, or framework behavior is verified against that declared state.

Invoked by the `gitlab-mr-review` or `red-team` skill (or directly) with:

```
args: {diffPath, repoRoot, contextBlock, dimensions?, registryReviewers?, repoState?}
```

- `diffPath` (required) — absolute path to the saved unified diff.
- `repoRoot` (required) — absolute path to the local repo the review verifies claims against, whose state `repoState` declares: a target-branch checkout for `gitlab-mr-review`, the post-change working tree for `red-team`.
- `contextBlock` (required) — env facts, a summary of the change under review, and verification instructions, built by the conductor (the skill) before the workflow runs.
- `dimensions` (optional) — `[{key, prompt, cold?}]`, extra MR-specific review angles (contract impact, framework wiring, conventions, data/upgrade safety) the registry reviewers won't cover; `cold: true` omits the conductor's `contextBlock` from that dimension's prompt so it reads the diff without the author's framing.
- `registryReviewers` (optional) — override the default set of five reviewer agent types. Names must be fully qualified as the harness registers them (plugin agents are namespaced, e.g. `toolkit:code-reviewer`).
- `repoState` (optional) — sentence describing the state of the tree at `repoRoot`, substituted into the reviewer and verifier prompts; defaults to the current MR target-branch sentence.

## post_mr_comments.py

Lives at `plugins/toolkit/skills/gitlab-mr-review/scripts/` — skill-local, not a general toolkit script. Posts review findings as positioned discussions on the GitLab MR: reads a `comments.json` (host, project, MR IID, the head sha the diff was reviewed at, the diff path, and a list of `{path, anchor, body}` comments plus an optional summary note), resolves each comment's `anchor` against the added lines in the diff (exact match first, then substring) to find a line number, then posts a positioned discussion per comment — falling back to an unpositioned discussion, prefixed with file:line, if GitLab rejects the position. It aborts up front if the MR's head sha has moved since the diff was fetched, since anchors may be stale. `--dry-run` prints what would be posted without posting.

This is a separate, explicit step — never automatic. The skill only runs it when the user asks, in that same session, to post the review to the MR; producing the review itself never triggers it.
