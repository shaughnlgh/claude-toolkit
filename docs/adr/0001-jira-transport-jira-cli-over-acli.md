# 0001. Jira transport: community jira-cli over official acli

Date: 2026-07-22

Status: Accepted

## Context

The toolkit's Jira adapter skill needs a CLI transport for fetching tickets headlessly. Two candidates were audited (2026-07-22): ankitpokhrel/jira-cli (community, Go, homebrew-core, MIT) and Atlassian's official acli (vendor tap, closed source, prebuilt binary). The toolkit's credential convention is env vars exported from ~/.zshrc, referenced by name only, and its dependency doctrine requires auditable maintenance state, install surface, and typo-squatting posture.

## Decision

Adopt jira-cli as the sole v1 transport. It reads JIRA_API_TOKEN from the environment per invocation with no stored credential, matching the toolkit's convention exactly. Its `issue view KEY --raw` returns the complete API JSON in one call. It installs from homebrew-core, built from source by Homebrew CI, MIT licensed and auditable. acli is the designated fallback CLI, and the Atlassian MCP connector the designated fallback transport, both documented but not built.

## Consequences

Setup on each machine needs `brew install jira-cli`, a one-time `jira init`, and JIRA_API_TOKEN in ~/.zshrc. We accept a bus factor of one and a slowed release cadence (roughly one per year, though commits continued into 2026 and Atlassian sponsors the project). If the project goes unmaintained, the swap is contained inside the jira skill, at the cost of redoing setup docs, allowlist entries, and the toolkit-setup check. Choosing the community tool over the vendor's official CLI trades vendor support for open provenance, stateless env-var auth, and a clean homebrew-core install surface with no tap and no confusable commercial namesakes.
