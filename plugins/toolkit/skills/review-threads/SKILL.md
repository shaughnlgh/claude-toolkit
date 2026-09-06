---
name: review-threads
description: >-
  Review follow-up loop after a commit is pushed and a merge or pull request has review
  threads. Use when the user asks to go through, work through, address, or answer the
  review comments, threads, or bot findings (CodeRabbit, Copilot, human reviewers) on
  an MR or PR. Host-agnostic: glab for GitLab, gh for GitHub. Lists open threads and,
  for each, either pushes back by replying in that thread with reasoning or delegates a
  fix, never both. Never comments on a thread a fix resolves, because the bot re-reviews
  and resolves it. Reports thread state after and states the merge gate: all threads
  resolved and pipeline green, otherwise no merge recommendation. Never mutates git
  state and never posts without the user's request in this session. Do not fire for
  reviewing an MR from scratch (gitlab-mr-review) or for an uncommitted local diff
  (red-team).
---

# Review threads

Work the reviewer threads on a pushed branch's MR or PR: list them, decide fix or push back per thread, report the state, and state the merge gate. The main chat is the conductor. Fixes go to `implementer`. The human commits and pushes. Replies post only on the user's request in this session.

## 1. Locate the MR or PR

Derive the host from `git remote get-url origin`. On GitLab, fail fast with `glab api user >/dev/null`, then `glab mr view -R "<project-path>"` from the current branch, or the IID the user gives. Fetch threads with `glab api --paginate "projects/<url-encoded-path>/merge_requests/<iid>/discussions"`. On GitHub, fail fast with `gh auth status`, then `gh pr view --json number,url,headRefName,reviewDecision`. Fetch threads with `gh api graphql` over `pullRequest.reviewThreads` (fields `id`, `isResolved`, `path`, `line`, `comments(first:50){nodes{databaseId,body,author{login}}}`, plus `pageInfo { hasNextPage endCursor }`). Repeat the query with `after: <endCursor>` until `hasNextPage` is false. Never print a token.

## 2. List open threads

Present a table: thread id, author (bot name or human), `file:line`, one-line summary, state. Skip resolved threads and system notes.

## 3. Triage each thread

For each open thread decide one of two outcomes and say which.

Fix: delegate to `implementer` per the orchestration doctrine. The human commits and pushes per git-safety. Do not reply in the thread. The bot re-reviews the new push and resolves the thread itself, and a human reviewer resolves theirs on confirmation. The user says when a thread needs a manual close.

Push back: reply in that thread with the reasoning and the evidence (`file:line`, a test, a doc). Post only after the user asks to post in this session. GitLab: `glab api --method POST "projects/<path>/merge_requests/<iid>/discussions/<id>/notes" --field body=@<file>`. GitHub: `gh api --method POST "repos/<owner>/<repo>/pulls/<n>/comments/<comment-id>/replies" -F body=@<file>`, where `<comment-id>` is the comment's `databaseId` from the thread fetch, not the GraphQL node id. Show the reply text before posting. Never resolve a thread on the reviewer's behalf.

## 4. Report thread state

After the round, re-fetch and report three lists: fixed (awaiting re-review), pushed back (awaiting the reviewer), open (not addressed, with the reason). Report the pipeline state: GitLab `glab mr checks <iid>`, GitHub `gh pr checks <number>`, both using the PR or MR number resolved in step 1, never the current-branch default.

## 5. Merge gate

Recommend merge only when every thread is resolved and the pipeline is green. Otherwise name the failing condition and stop. Never run a merge.

## Boundary

`gitlab-mr-review` reviews an MR from scratch. `red-team` reviews the local uncommitted slice. This skill runs after push and works the reviewer's threads. It never stages, commits, pushes, or merges. Posting a reply is an external side effect and follows the execution guardrails: preview, then post only on the user's request.
