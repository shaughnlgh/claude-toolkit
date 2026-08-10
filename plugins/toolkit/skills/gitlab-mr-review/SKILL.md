---
name: gitlab-mr-review
description: >-
  Multi-dimension review of a GitLab MR using the review-mr workflow: fan out the toolkit
  reviewer agents plus MR-specific dimensions, adversarially verify every finding against the
  local target-branch checkout, adjudicate, and report. Use when asked to review a GitLab merge
  request URL. Posting comments to the MR is a separate, explicit step — never automatic.
---

# GitLab MR Review

Review a GitLab MR with the `review-mr` workflow (shipped with this plugin at `../../workflows/review-mr.js` relative to this skill's base directory), which merges the toolkit reviewer agents (`toolkit:code-reviewer`, `toolkit:security-reviewer`, `toolkit:silent-failure-hunter`, `toolkit:performance-reviewer`, `toolkit:pr-test-analyzer`) with MR-specific custom dimensions and an adversarial verify pass run by the `toolkit:verifier` agent. All workers run on sonnet. The main chat is the conductor: it prepares inputs, launches the workflow, adjudicates, and owns the final report.

## 1. Fetch the MR

- Fail fast on auth, before any other work: run `glab api user >/dev/null` (one cheap authenticated call). If it fails, stop immediately and tell the user to re-auth (`glab auth login`) — a revoked token discovered mid-review wastes the whole fan-out.
- Token: `glab auth token` (requires `glab` authenticated once via `glab auth login`; never print the token). Export `GITLAB_HOST` for the instance (e.g. `gitlab.example.com`), or derive it from the repo's git remote.
- Parse the MR URL into project path + IID. Fetch metadata via `glab api "projects/<url-encoded-path>/merge_requests/<iid>"`: record `title`, `description`, `source_branch`, `target_branch`, `sha` (head), and `diff_refs`.
- Save the diff to the scratchpad: `glab mr diff <iid> -R "<project-path>" > <scratchpad>/<slug>.diff`.
- Fetch existing MR notes briefly to avoid duplicating feedback already given (skip system notes).

## 2. Locate local target-branch code

Reviewers verify claims against real code, so find where the MR's target branch lives locally:

- If the MR project is a top-level repo, it is usually `~/projects/<repo>`.
- If it is a nested vendor module (e.g. `acme/magento-modules/subscription`), find its checkout inside the host project (`find <repo> -name .git -path "*<module>*"`) and use `git -C <module-dir> log --oneline -1 <base_sha>` (read-only) to confirm the MR base commit exists in the local history. Local checkout slightly ahead of the base is fine — say so in the context block. If the base is NOT present locally, note that verification is degraded (agents can still read pre-change code via the diff context lines and `glab api` raw file fetches).
- The MR branch itself is never checked out. All MR content comes from the saved diff.

## 3. Read the diff and build the context block

Read the full diff yourself before delegating. Then write a `contextBlock` string containing:

- One paragraph: what the MR does (title, branch -> target, module/repo).
- Environment facts: repo root, module checkout path and its relation to the MR base, platform (Magento 1/2, PHP version if relevant), where related modules / framework core live, any symlink or dual-path quirks.
- A short file-by-file summary of the diff.
- Any project rules that matter (from the repo's CLAUDE.md / AGENTS.md / .claude/rules).

## 4. Choose custom dimensions

The five registry reviewers are always included by the workflow. Add 1–3 MR-specific `dimensions: [{key, prompt}]` that the generic reviewers will not cover, for example:

- Contract impact (GraphQL schema, API response shapes, downstream consumers such as a mobile app or a PWA).
- Framework wiring correctness (plugin/preference/observer targets, DI, rewrites, renderer dispatch — verify target classes and signatures in local code).
- Conventions vs this repo's written rules AND actual practice (flag only when both are violated).
- Data/upgrade safety (setup scripts, schema changes, config defaults vs values already in the DB).

Seed the prompts with any specific suspicions from your own read of the diff — named methods, questionable math, config gotchas. Reviewers do better chasing concrete leads.

## 5. Run the workflow

Invoke the Workflow tool: when `repoRoot` is the toolkit plugin source itself (the tree contains `plugins/toolkit/workflows/review-mr.js`), invoke with `{scriptPath: "<repoRoot>/plugins/toolkit/workflows/review-mr.js"}` so uncommitted workflow edits are exercised; otherwise invoke `{name: "toolkit:review-mr"}` (the name the harness registers for the installed plugin), falling back to `{scriptPath: "<this skill's base directory>/../../workflows/review-mr.js"}` (resolved to an absolute path) if name resolution fails, and:

```
args: {
  diffPath: "<scratchpad>/<slug>.diff",
  repoRoot: "/Users/.../projects/<repo>",
  contextBlock: "<built in step 3>",
  dimensions: [ {key, prompt}, ... ]
}
```

The moment the Workflow tool returns its `runId`, save it to `<scratchpad>/<slug>.runid` together with the script file path the launch result reports (it reports one for both name and scriptPath launches, and resuming needs scriptPath). Runs die for reasons outside anyone's control — API overload, a VPN drop, a session restart — and with the runId on disk the review resumes (`resumeFromRunId`: completed agents return cached, only dead work re-runs) instead of being relaunched from scratch. Never relaunch when a resume is possible.

The result is `{confirmed, refuted, unverified, openQuestions}`.

## 6. Adjudicate (conductor duty — do not skip)

- `openQuestions` are things a reviewer could not answer from the diff/repo (MR intent, business rules, environment facts). The conductor answers them itself from its session context (MR description, ticket, plan note, prior discussion) or asks the user. Never hand an open question to a fresh subagent — it has less context than the reviewer that raised it.
- Any `unverified` findings (verifier died) and any finding where verdicts conflict across runs must be settled by targeted follow-up: direct reads for small checks, or a bounded `explorer` agent for mechanical evidence-gathering — with the relevant context (finding, paths, what to confirm) passed down in the prompt. Do not report a finding whose evidence you have not seen hold up.
- If a review agent died mid-run, resume the workflow (`resumeFromRunId`) — completed agents return cached; only the dead one re-runs.
- Watch for findings that are true-but-morphed: a wrong mechanism can hide a real adjacent defect (verify what IS true, not just whether the claim as stated is false).

## 7. Report

Write the full report to a file (`<scratchpad>/<slug>-review.md`, or the plan directory if the review belongs to a plan) as you produce it, and print inline only the verdict plus the severity-ordered findings summary. A long report streamed inline can hit the output-token ceiling and take the whole session's work with it; a file cannot.

Lead with the verdict (merge-ready / needs work) in one sentence, then findings ordered by severity: what, where (file:line), why it is real, concrete failure scenario, suggested fix. Include a "checked and fine" section so the author does not re-litigate cleared concerns, and a validation-honesty note (static review only; nothing executed). Note refuted-finding counts briefly. Do not post anything to GitLab in this step.

## 8. Posting comments (only on explicit request)

When the user asks to post the review to the MR:

1. Build a `comments.json` per the schema documented in `scripts/post_mr_comments.py` under this skill's base directory (invoke as `GITLAB_TOKEN="$(glab auth token)" python3 <base>/scripts/post_mr_comments.py`): one entry per finding with `path`, an `anchor` (exact added-line content from the diff — unique within the file), and a markdown `body` (severity-tagged title + 2–4 sentences), plus a `summary` note.
2. Set `expected_head_sha` to the head sha the diff was fetched at. If the script aborts because the head moved, refetch the diff, compare content (`diff old new`); if identical, update the sha and proceed — if not, re-review the changed files first.
3. Run with `--dry-run` and confirm every anchor resolves to a line.
4. Run for real; report the discussion URLs/count back.

## Guardrails

- Never print the token. Never post without an explicit user request in this session.
- Workers are sonnet; never haiku (global model policy).
- Findings without evidence do not get reported, at any severity.
- Validation honesty: this is static review; say so.
