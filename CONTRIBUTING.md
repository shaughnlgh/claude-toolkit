# Contributing

## Bug reports

Report a bug by opening an issue with the bug report template. Include the output of `/toolkit:setup`, your platform and your Claude Code version, because most problems trace back to a missing prerequisite or a vault config the toolkit cannot read.

Report a security vulnerability through [`SECURITY.md`](SECURITY.md), never in a public issue.

## Pull requests

Outside pull requests are by invitation. Before you write code, open an issue that describes the change and why it is needed. If the owner invites a pull request, link it to that issue.

## Checks

A change must pass `bash verify.sh`. The last line must read `RESULT:` with 0 failed. [`VERIFY.md`](VERIFY.md) explains what the script proves and lists the manual checks that only a live Claude Code session can show.

## Releases

The maintainer decides when to release, and a merge to `main` reaches no install until the next version. [Decision 0014](docs/decisions/0014-versioned-releases-on-the-maintainers-decision.md) sets out the versioning rules and what each part of the number means.

1. Change `version` in `plugins/toolkit/.claude-plugin/plugin.json`.
2. Add the version's entry to `site/release-notes.html`.
3. Open and merge the pull request.
4. Tag the merge commit `vX.Y.Z` and push the tag.
5. Create the GitHub release for that tag with `gh release create vX.Y.Z --title vX.Y.Z --notes-file <file>`, or with `--generate-notes` in place of `--notes-file <file>`.

A ship flow run with `tag_merge: true` must be given a tag that equals the manifest version.
