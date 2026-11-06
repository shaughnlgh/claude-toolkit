# Overrides

The toolkit ships opinionated defaults — doctrine, rules, agents, skills. They are defaults, not law. Your own config wins when it disagrees, so you bend the toolkit to how you and your team work instead of forking it.

## The rule

Most specific wins: project config beats your global config beats the plugin's defaults. Safety sections (git-safety, security) may be tightened, never loosened.

## What you can override, and how each takes effect

You override by placing a same-named copy under your global `~/.claude/`. The `/override` command does the copy for you (below), or you can drop the file in by hand.

| Type | Put your copy at | How it wins |
|---|---|---|
| **doctrine** | `~/.claude/doctrine/<name>.md` | The session-start hook detects it and announces it; the model reads your copy for that concern instead of the plugin's. |
| **rules** | `~/.claude/rules/<name>.md` | The session-start hook injects your body in place of the plugin's rule (keep the file's frontmatter). |
| **agents** | `~/.claude/agents/<name>.md` | Claude Code resolves your agent over the plugin's — for the **bare name**. Invoke it as `<name>`, not `toolkit:<name>` (the scoped name pins to the plugin). |
| **skills** | `~/.claude/skills/<name>/` | Same as agents — resolved for the bare name. Copied as a whole directory. |

Doctrine and rules are picked up because the hook loads them fresh each session. Agents and skills are resolved natively by Claude Code, so they work with no hook involvement, but only when invoked by their bare name.

Two rules are exceptions: `frontend` and `design` are reference-only (never injected), so there is nothing for a rule override to replace. `frontend`'s content lives in the `frontend-designer` agent — override that instead. `design` is just an index over the `rules/design/` catalog, with no equivalent component to override. `/override` will tell you this if you try.

## Agent models without an override

To change only an agent's model or effort, do not copy the agent file. Set it in `~/.claude/toolkit-models.json` as a `{"model": ..., "effort": ...}` object instead, offered by `/setup`, and both the `agent-model.sh` hook on Agent-tool spawns and the workflow runner scripts apply it. A copied agent under `~/.claude/agents/` freezes that agent's future updates, so it is the wrong tool for a model-only change. The shipped agent files pin no model or effort, and the hook adds nothing to a bare name that a copy shadows, so a copy runs on the default subagent model or the session model until you add `model:` and `effort:` lines to its frontmatter.

## The `/override` command

`/override [type] [name]`:

- **no argument** — lists everything overridable, grouped by type.
- **a name** (`/override conventions`) — auto-detects the type and copies it.
- **a type and name** (`/override rules security`) — needed only for an ambiguous name (`security` is both a doctrine and a rule).

It refuses unknown or ambiguous names, and never overwrites an override you have already created (edit that one directly). Under the hood it runs `scripts/override.sh`, which is self-locating and needs no config.

## What you see each session

When an override is active the session-start hook announces it, so it is never a silent change:

- *Doctrine overrides active … `conventions`* — read your global copy for that concern.
- *Rule overrides active …* — your rule body was injected instead of the plugin's.
- *Rule override(s) empty or unreadable, plugin default used instead …* — your override file exists but has no usable body, so the hook fell back to the plugin's copy; fix or remove the override.
- *Rule file(s) unreadable, no override and no usable plugin default …* — named explicitly: neither your override nor the plugin's copy could supply a body for that rule.
- *Agent/skill overrides active …* — your version resolves for the bare name.

## Tightening safety

The safety sections — the git-safety and security doctrine, and the security rule — can be made stricter in your override, never looser. This is stated discipline, not hook-enforced — a hook cannot tell a tighten from a loosen — so it rests on you keeping to it, the same as the rest of the doctrine.
