---
title: Rewrite history in place before going public
summary: The history is rewritten once inside this repo and force-pushed to main, and the earlier commits that GitHub keeps under the pull request refs stay visible, with no request to GitHub Support.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-13
---

# 0013. Rewrite history in place before going public

Date: 2026-11-13

Status: Accepted

## Context

The repo goes public. GitHub keeps a read-only `refs/pull/<n>/head` ref for every pull request, and a force push does not move those refs.

## Decision

The history is rewritten once inside this repo and force-pushed to `main`.

## Consequences

The repo's creation date, pull request timeline and install address stay, so the project's age stays provable and no installed copy changes its address. Every commit id changes and every commit is signed again.

The earlier commits stay on GitHub under the pull request refs. Each pull request's Commits and Files changed tabs, the commit pages and the patch views show them to any visitor, and the earlier LFS objects stay in the store. The maintainer accepted this, and no request to remove them goes to GitHub Support.

## Alternatives weighed

- A new repo with the rewritten history. It removes the earlier commits and their pull request pages, but it shows a new creation date and moves every install.
- A request to GitHub Support to dereference the pull requests and purge the LFS objects. The maintainer judged it not worth it for what the earlier history holds.
