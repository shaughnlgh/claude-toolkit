---
name: review-threads
description: >-
  Review follow-up loop after a commit is pushed and a merge or pull request has review
  threads. Use when the user asks to go through, work through, address, or answer the
  review comments, threads, or bot findings (CodeRabbit, Copilot, human reviewers) on
  an MR or PR. Host-agnostic: glab for GitLab, gh for GitHub. Lists open threads and,
  for each, either pushes back by replying in that thread with reasoning or delegates a
  fix, never both. On GitHub, after the fix commit is pushed, reply on the thread and
  resolve it via GraphQL, because Copilot never resolves a thread itself. On GitLab,
  wait for the bot's re-review, then reply and resolve only the threads it left open.
  Reports thread state after and states the merge gate: all threads
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

Fix: before delegating, confirm the local checkout is on the PR or MR head branch: `git rev-parse --abbrev-ref HEAD` must equal the head ref resolved in step 1. If it does not match, stop and tell the user which branch to check out. Otherwise delegate to `implementer` per the orchestration doctrine. The human commits and pushes per git-safety.

On GitHub, once the fix commit is pushed, reply on the thread with one line, `Fixed in <short sha>: <what changed>`, then resolve the thread. Copilot never resolves a thread on its own, so leave it open forever otherwise.

`gh api graphql -f query='mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{id}}}' -f id=<thread-node-id> -f body='Fixed in <short-sha>: <what-changed>'`

`gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id=<thread-node-id>`

On GitLab, wait for the bot's re-review of the new push. It resolves the threads its own fix satisfies. Re-fetch discussions and reply plus resolve only the threads it left open, using the notes and discussions-resolve endpoints from step 1. A human reviewer's threads resolve on their own confirmation, never on the skill's behalf.

Push back: reply in that thread with the reasoning and the evidence (`file:line`, a test, a doc). Post only after the user asks to post in this session, on both hosts. GitLab: `glab api --method POST "projects/<path>/merge_requests/<iid>/discussions/<id>/notes" --field body=@<file>`. GitHub: `gh api --method POST "repos/<owner>/<repo>/pulls/<n>/comments/<comment-id>/replies" -F body=@<file>`, where `<comment-id>` is the comment's `databaseId` from the thread fetch, not the GraphQL node id. Show the reply text before posting. Never resolve a pushed-back thread on the reviewer's behalf.

## 4. Report thread state

After the round, re-fetch and report three lists: fixed (awaiting re-review), pushed back (awaiting the reviewer), open (not addressed, with the reason). Report the pipeline state: GitLab `glab ci status --branch <source branch of the MR>`, GitHub `gh pr checks <number>`, using the MR's source branch or the PR number resolved in step 1, never the current-branch default.

## 5. Merge gate

Recommend merge only when every thread is resolved and the pipeline is green. Otherwise name the failing condition and stop. Never run a merge.

## Boundary

`gitlab-mr-review` reviews an MR from scratch. `red-team` reviews the local uncommitted slice. This skill runs after push and works the reviewer's threads. It never stages, commits, pushes, or merges. Posting a reply is an external side effect and follows the execution guardrails: preview, then post only on the user's request.
