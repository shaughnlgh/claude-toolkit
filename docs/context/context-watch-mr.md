---
title: Watch MR script
summary: The host API behavior `watch-mr.sh` works around and the head, pipeline, and suite rules a change to the script must keep.
type: context
status: active
owner: Shaughn Le Grange - Hatlen
last_reviewed: 2026-11-07
source_refs:
  - plugins/toolkit/scripts/watch-mr.sh
  - plugins/toolkit/scripts/tests/watch-mr/
---
<!-- managed-by: toolkit -->

# Watch MR script

`scripts/watch-mr.sh` waits on one GitLab MR or GitHub PR until its pipeline settles, a bot review lands, or a bot review in progress ends. Its arguments, status lines, and exit codes are in [scripts.md](../scripts.md). This page lists the host behavior the script works around and the rules a change to the script or its suite must keep.

## Host API behavior

- `gh pr checks --json` prints JSON and exits 0 whatever state the checks are in. Exit code 8 for pending checks applies only without `--json`, so the script reads the `bucket` field of each check, never the exit code.
- With no checks at all, `gh pr checks` exits 1 and prints `no checks reported on the '<branch>' branch`. The script treats that message as an empty check list and any other failure as a failed round.
- GitLab timestamps carry a UTC offset, such as `+02:00` on `committed_date`, so the script orders them by a parsed epoch, never by a string compare. jq's `fromdateiso8601` accepts neither fractional seconds nor an offset, so the `ts` helper in the script's jq prelude parses both itself.
- The GitHub REST reviews endpoint returns a bot login with a `[bot]` suffix, such as `coderabbitai[bot]`, and GraphQL returns the bare login. The `isbot` helper strips a trailing `[bot]` from both the author login and each `--bot` value before it compares them.
- With `--bot` logins given, they are an allowlist on either host and the host's own bot flag is ignored. The GitLab notes API's basic user object carries no `bot` field, so GitLab threads mode requires `--bot`.
- CodeRabbit edits one summary issue comment in place. That comment carries `<!-- This is an auto-generated comment: review in progress by coderabbit.ai -->` only while a review runs, and other markers, such as `summarize`, at other times, so review mode reads the marker text, never the comment's presence.
- A finished CodeRabbit review on GitHub is a PR review whose `commit_id` is the head commit, so review mode lands it the way threads mode does.
- GitLab threads mode never lands a note that carries the in-progress marker, because the first bot note after the anchor can be the in-progress note.
- CodeRabbit posts on GitLab as the user that owns its token, a service account the installer names or a group access token bot with a generated username, and the note's author object says neither. GitLab review mode without `--bot` therefore counts the marker from any author, and a plain note that quotes the marker holds every wait busy until the bound. A GitLab ship run that uses CodeRabbit names its login through the ask's `botAuthors` or through the host's entry in `~/.claude/toolkit-review-bots.json`, which the ship flow passes as `botLogins`.
- `glab` resolves the GitLab host from the git remote of the working directory, else from its default host, so a caller runs the script from the repo.

## Head matching

- `same_head` matches the head by prefix on the first round, then stores the full head and matches it exactly on every later round. A short `--sha` therefore works, and a second commit that shares the prefix mid-wait reads `MOVED`.
- A head that does not match `^[0-9a-f]{40,64}$` counts as a failed round, the same as a failed `gh` or `glab` call, never as a match.

## Pipeline states

- On GitLab only pipeline status `success` reads `GREEN`. `skipped` reads `NONE` at once, and `failed` or `canceled` reads `RED`. Every other status, `manual` included, keeps the wait polling, because a blocking manual job holds the later stages.
- The stuck check counts a job whose status is `manual` as settled, so a pipeline that waits only on a blocking manual job reads `STUCK` once the stuck window passes.
- `STUCK` needs a non-empty job list in which every job is settled: on GitHub the Actions runs for the commit, read with `gh run list --commit <sha> --limit 100`, and on GitLab the jobs outside the `external` stage. An empty list never reads as stuck.

## Testing the script

- `tests/watch-mr/run-tests.sh` cleans its temp directory with a `trap 'rm -rf "$W"' EXIT` line. The toolkit's `block-dangerous-commands.sh` hook refuses any Bash command whose text holds a recursive force `rm` aimed at a `$VAR` expansion, heredoc bodies included. An agent must therefore write or edit a suite file that holds that line with the Write or Edit tool, never through a Bash heredoc.

## Related docs

- [scripts.md](../scripts.md) for the arguments, status lines, exit codes, landing rules, and the test command.
- [context-ship-flow-constraints.md](context-ship-flow-constraints.md) for how the ship runner and the ship-flow conductor call the script.
- [hooks.md](../hooks.md) for what `block-dangerous-commands.sh` refuses.
