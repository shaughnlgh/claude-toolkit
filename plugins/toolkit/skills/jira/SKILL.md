---
name: jira
description: >-
  Jira ticket adapter. Use when a Jira issue key (like PROJ-123) or a Jira ticket URL
  needs fetching, typically from crawl's ingest step or an expedition's ingestion, or
  when the user asks to fetch one, and when plan-guide's ticket question reaches the
  user's yes to a drafted Jira ticket. Fetches the issue via the jira-cli CLI and returns
  a verbatim brief in conversation: metadata, full description, comments, and issue
  links, never paraphrased. Creates a ticket only on the user's yes to a draft it was
  shown, never transitions, comments on, or edits a ticket, and never writes vault or
  repo files. Do not fire for GitLab issues or MRs (glab handles those) or when the user
  has already pasted the ticket body.
---

# Jira

This skill turns a Jira ticket into a verbatim brief for the planning skills. It exists because briefs must carry the ticket's exact words: a paraphrase drops the requirement that triples the scope. The model never summarizes, reorders, or cleans up ticket content — it fetches, extracts, and presents it as written.

Transport is `jira-cli`, which reads `JIRA_API_TOKEN` from the environment per invocation with no stored credential. Reference the token by name only; never print it or copy it into any file. The Atlassian MCP connector and acli are fallbacks, not built — do not reach for them.

## 1. Fail fast on auth

Before any other work, run one cheap authenticated call: `jira me >/dev/null`. If it fails, stop immediately and give the user the exact remediation for the likely cause, in order:

- `jira` not installed: `brew install jira-cli`.
- Not configured: `jira init` (one-time; stores server and login in jira-cli's own config).
- Token missing or revoked: export `JIRA_API_TOKEN` from the user's shell rc file (`~/.zshrc`, `~/.bashrc`, or equivalent; create a token in Atlassian account settings → Security → API tokens), then start a fresh shell.

Do not retry, guess, or switch transports — a dead credential discovered mid-fetch wastes the work.

## 2. Resolve the key

Accept a bare key (`PROJ-123`) or a ticket URL. From a URL, take the key from a `/browse/<KEY>` path segment or a `selectedIssue=<KEY>` query parameter; keys match `[A-Z][A-Z0-9]*-[0-9]+`. If no key can be parsed (some portal and board URLs carry none), ask the user for the key instead of guessing.

## 3. Fetch

Run `jira issue view <KEY> --raw` — the CLI prints the API response byte-for-byte, making it the only faithful source. Never use `--plain` for content: it is a double-converted, 120-column hard-wrapped rendering, not verbatim. Redirect the payload to the scratchpad, read from the file, and delete it after extraction (ticket bodies can carry sensitive content). Extract: `key`, issue type, status, assignee, reporter, labels, parent or epic key (`fields.parent.key` when present), `fields.summary`, `fields.description`, `fields.comment` (author, created date, body), and `fields.issuelinks`.

On Jira Cloud the description and comment bodies arrive as ADF JSON trees (REST v3). Render the text out of the ADF tree yourself: preserve every word, the order, lists, tables, and code blocks; translate formatting marks to plain markdown; collapse nothing. State in the brief header that bodies were converted from ADF with wording and order preserved. On Server/DC installs the same fields arrive as wiki-markup strings and are quoted as-is.

The raw path returns only the API's default comment page. Reconcile `fields.comment.total` against the returned array; when total exceeds returned, say exactly that in the brief ("first N of M comments; remainder not fetched") — never silently truncate.

## 4. The brief

Return the brief in conversation. This skill writes no files anywhere — the caller (crawl, expedition) owns writing `brief - <plan-name>.md` per its own rules. Format:

- A frontmatter-style header: `key`, `type`, `status`, `assignee`, `reporter`, `labels`, `parent` (epic or parent key, blank if none), `url` (the browse URL), `fetched-at` (ISO timestamp), `body-format` (`converted from ADF` or `verbatim wiki-markup`).
- Body, in order: the summary as a heading; the full description; every fetched comment, each preceded by its author and date; then issue links as a list — key, link type, linked issue summary.

Verbatim means verbatim: no paraphrase, no reordering, no dropping of boilerplate. Judgment about the ticket — readiness, gaps, scope — belongs to crawl and grill, never to this skill.

## 5. Create, on a yes

Run only from the ticket question in plan-guide § Run options: the project read and the search when its create procedure reaches them, and the create after the user's Create it answer. Fail fast per section 1 first.

- Configured project: `awk '/^project:/{p=1;next} /^[^ ]/{p=0} p&&/^ +key:/{print $2; exit}' "${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"` prints jira-cli's configured project key, the project its board setting serves.
- Search: `jira issue list -p '<PROJECT>' -q 'statusCategory != Done AND text ~ "<words>"' --plain --no-headers --columns key,summary`. A key list is a search result, not ticket content, so `--plain` is allowed here. Fetch a ticket the user picks with `--raw` per section 3.
- Draft fields, filled before the draft is shown. The assignee is the login `jira me` prints when the project's rules default it to the reporter. When `<PROJECT>` equals the configured project, the sprint id comes from `jira sprint list --state active --table --plain --no-headers --columns id,name`, because jira-cli reads the board from its config. One row gives its id. Any other row count, or another project, asks the user for the sprint id or none.
- Create: `jira issue create --no-input -p '<PROJECT>' -t '<type>' -s '<summary>' -a '<login>' -l '<label>' --template '<scratchpad>/ticket-draft.md'`. `-p` always carries the project the draft showed. Pass one `-l` per label the rules require and none when they name none, and leave out `-a` when the rules name no assignee. The new key is the first match of `[A-Z][A-Z0-9]*-[0-9]+` in the output. When no key matches, report the output and ask the user for the key. A key the user gives must match `^[A-Z][A-Z0-9]*-[0-9]+$` before `jira sprint add` or any note write uses it, and a key that fails names the value and asks again.
- Sprint: `jira sprint add '<sprint id>' '<KEY>'` for the key the create just returned, when the draft names a sprint. When only the sprint add fails, keep the created key as the answer, report the sprint add's exact error, and never ask the ticket question again for that plan.
- Values: `<PROJECT>` matches `^[A-Z][A-Z0-9]*$`, the sprint id `^[0-9]+$`, each label `^[A-Za-z0-9_-]+$`, and the type, summary, and login carry no single quote. Check each value before every section 5 command that carries it, so `<PROJECT>` is checked before the search as well as the create. A value that fails stops that command and names the value.

## Errors

- Key not found or no permission: report the CLI's exact error and the key tried; suggest verifying the key and the account's project access. Do not iterate over guessed keys.
- Network errors: report them plainly and let the user decide (VPN, instance availability); do not retry in a loop or conclude the ticket does not exist.

## Boundary

Reads: `jira me`, `jira issue view`, the configured project read, and the section 5 search through `jira issue list` and `jira sprint list`. The one write is section 5 on the user's own yes to a shown draft: `jira issue create`, and `jira sprint add` for the key that create returned. Never transition, assign, label, comment on, or edit an existing ticket. No vault writes, no repo writes, no ticket-readiness judgment, no custom-field mapping. One ticket per invocation. If issue links look worth fetching, ask before fetching them.
