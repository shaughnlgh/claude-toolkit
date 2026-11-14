---
title: Versioned releases on the maintainer's decision
summary: The plugin carries a semantic version in its manifest only, the maintainer raises it when a release is due rather than on every merge, and each release gets a vX.Y.Z tag and a GitHub release.
type: decision
status: active
owner: Shaughn
last_reviewed: 2026-11-14
---

# 0014. Versioned releases on the maintainer's decision

Date: 2026-11-14

Status: Accepted

## Context

Claude Code computes an installed plugin's version from the `version` in `plugin.json`, else the `version` in the marketplace entry, else the commit of the installed directory for a relative-path plugin in a git-hosted marketplace. An install receives a new copy only when that computed version differs from the one it holds. Without a version field every merge to `main` reached every install, and nothing named a release that a user could read about or pin. When both files carry a version, Claude Code uses the `plugin.json` value without a warning. Claude Code does not read GitHub releases, and it reads git tags only when another plugin declares a version range on this one.

## Decision

- The plugin carries a `version` in `plugins/toolkit/.claude-plugin/plugin.json` only. The marketplace entry in `.claude-plugin/marketplace.json` carries none.
- The version follows semantic versioning, `MAJOR.MINOR.PATCH`. The major number rises for a change that breaks an existing setup or needs the user to act: a removed or renamed skill, command, agent or hook, a changed plan note contract, or a changed config key. The minor number rises for a new capability that leaves existing setups working. The patch number rises for fixes and doc changes.
- The maintainer raises the version when a release is due, not on every merge.
- Each release is tagged `vX.Y.Z` on the merge commit of its release pull request and gets a GitHub release with notes. The release notes page on the project site lists each release.
- `verify.sh` checks that the version is three dot-separated numbers, that the marketplace entry carries no version, and that the release notes page holds an entry for the current version.

[`CONTRIBUTING.md`](../../CONTRIBUTING.md#releases) lists the release steps.

## Consequences

A merge to `main` reaches no install until the next version is released. This includes the maintainer's own machine when it installs from the GitHub marketplace. A change merged without a version change reaches nobody, so a release that forgets to raise the version ships nothing. The tag and the GitHub release are for people reading the history, not for Claude Code, so a missing tag delays no install and a tag alone releases nothing. A ship flow run with `tag_merge: true` must be given the tag that equals the manifest version, because the tag it suggests comes from the latest remote tag and not from the manifest.
