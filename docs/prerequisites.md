# Prerequisites

The toolkit shells out to a few CLIs rather than holding any credentials of its own. Each is a one-time install and auth on your machine; after installing the plugin, `/setup` checks every one of these and reports exactly what is missing.

### gh (GitHub CLI)

The official GitHub CLI. The install below pulls this plugin from a private GitHub repo over SSH, and `gh auth login` is the easiest way to generate and upload an SSH key the first time. Sessions also use it for read-only PR and CI checks on GitHub-hosted repos. The ship flow uses it to open a PR, watch its checks, reply to and resolve bot review threads, and merge.

Install:

```sh
brew install gh
```

Authenticate (one-time, interactive; choose SSH and let it set up a key):

```sh
gh auth login
```

### glab (GitLab CLI)

The official GitLab CLI. The gitlab-mr-review skill fetches MR metadata and diffs through it and posts review comments with its token, so review sessions never handle raw GitLab credentials. The ship flow uses it to open an MR, watch its pipeline, reply to and resolve bot review threads, and merge.

Install:

```sh
brew install glab
```

Authenticate (one-time, interactive; stores the token in glab's own config):

```sh
glab auth login
```

### jira (jira-cli)

A community Jira CLI (ankitpokhrel/jira-cli, chosen over Atlassian's official acli — see `docs/decisions/0001` for the trade-offs). The jira skill fetches tickets through it and turns them into verbatim planning briefs, so a pasted ticket URL becomes a plan input with no copy-paste. Unlike gh and glab it has no login flow: it only consumes a pre-provisioned API token from your environment, which is exactly why it was picked — no stored credential, stateless per invocation.

Auth is token-first: `jira init` itself makes authenticated API calls, so the token must exist before init runs.

**1. Install:**

```sh
brew install jira-cli
```

**2. Create an API token** in [Atlassian account settings → Security → API tokens](https://id.atlassian.com/manage-profile/security/api-tokens).

**3. Check your shell.** Steps 4 and 5 use `~/.zshrc`, which is correct for zsh, the macOS default. Run this to confirm that's you:

```sh
echo $SHELL
```

If it prints something else, use the same steps with the filename swapped: bash on macOS → `~/.bash_profile` (Terminal starts login shells, which never read `~/.bashrc`), bash on Linux → `~/.bashrc`, fish → `~/.config/fish/config.fish` (and write the export as `set -x JIRA_API_TOKEN "<your token>"`).

**4. Open the file in an editor** — deliberately an editor, never `echo` a token on a command line, it lands in shell history:

```sh
${EDITOR:-nano} ~/.zshrc
```

Add this line, with your token pasted in:

```sh
export JIRA_API_TOKEN="<your token>"
```

**5. Reload the file** so the export is live in this session:

```sh
source ~/.zshrc
```

**6. Run the one-time config** (asks for server URL, login email, default project and board):

```sh
jira init
```

Never commit or print the token; the toolkit references it by name only.

### jq

Required by `watch-mr.sh`, the ship flow's pipeline and review watcher. Some hooks and other scripts prefer it and degrade gracefully without it.

```sh
brew install jq
```

### python3

Required by the planning workflow's scripts (vault config resolution, the plan validator, and topic recall, which the session-start hook also runs); no third-party packages are needed. macOS ships a python3 with the developer tools; the Homebrew one works too:

```sh
brew install python3
```

