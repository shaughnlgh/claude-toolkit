# claude-toolkit

Shaughn's Claude Code toolkit — agents, skills, and working doctrine — distributed
as a Claude Code plugin. Personally owned and maintained (see LICENSE), free for
anyone with access to use.

Under construction: components land one at a time, each tested through the plugin
before its source-of-truth moves here.

## Install

```
claude plugin marketplace add git@github.com:shaughnlgh/claude-toolkit.git
claude plugin install toolkit@shaughn-toolkit
```

SSH is required for background auto-update on private repos (HTTPS credential
helpers are disabled for background pulls).

## Uninstall

```
claude plugin uninstall toolkit
claude plugin marketplace remove shaughn-toolkit
rm -rf ~/.claude/plugins/cache/shaughn-toolkit
```

(The cache directory is not swept by uninstall.)
