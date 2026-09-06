---
name: incident-investigate
description: >-
  Root-cause investigation for a production incident. Use only on explicit request:
  "investigate this incident", "/incident-investigate", or a pasted production alert
  with "find the cause". Input is an incident description, a ticket key, or a list of
  named items (record ids, request ids, transaction ids). Fences scope to the question asked,
  checks evidence-source readiness before spawning anything, gathers evidence in
  parallel with one worker per source and a citation per finding, adjudicates to one
  root-cause verdict with a provenance label, writes a technical incident note and a
  plain-language stakeholder summary behind the vault consent list, and hands a
  needed fix to crawl. Never fires on its own, never implements a fix, never mutates
  production. Do not fire for debugging a local runtime issue (execute-workflow owns
  that) or for reviewing a diff.
---

# Incident investigate

Answer the question the user asked about the items the user named, with evidence, then write it up twice: once for engineers, once for stakeholders. The main chat is the conductor. Workers gather evidence. The conductor adjudicates. Nothing here changes production or the repo.

## 0. Scope fence

Restate the question asked and the named items in one line, and commit to answering that first. Adjacent findings go to an "Outside scope" list at the end of the report as one-line suggestions. Never investigate or write up an adjacent finding unasked. This is the execution guardrails' investigation scope fence.

## 1. Topic recall and preflight

Recall vault topic notes and repo docs for the subsystem (plan-workflow's topic recall step). Then, before spawning any worker, list the evidence sources the project documents for this subsystem: log search, database, third-party service, metrics. Read them from the project's docs or company slice. This skill names no source itself. For each source, check that its credentials are exported in the session (`[ -n "${NAME:-}" ] && echo set || echo missing`, which never prints the value) and that the network path is up (read the reachability probe from the user's global instructions when one exists, otherwise ask). Report a missing source and ask the user to export or connect. Never work around a missing source. If the project documents no evidence source, stop before spawning anything, name the source classes this skill needs (log search, database, third-party service, metrics), ask the user to name the project's sources or point at the doc, and wait. Never infer a source from the codebase.

## 2. Parallel evidence gathering

Launch one worker per evidence source in a single message. `explorer` handles read-only code and doc tracing. `verifier` handles anything that runs a query or a command. Scope each worker to its source and to the named items. Each worker returns findings with one concrete citation per finding: a table and key, a log source and timestamp, or a code path and line, a non-sensitive locator only, never the raw row or log content, so no customer data enters a worker return. The redaction step in Artifacts stays as the second net at write time. Where nothing was found, the worker returns an explicit "no evidence" for that source and item. A worker whose command was refused or stalled returns `blocked: <command>` with the refusal text, never "no evidence". Speculation is not a finding. Against production, workers read only: SELECT statements only, GROUP BY-safe SQL, no writes of any kind. Every query binds or escapes each user-supplied item id; never interpolate an item id into SQL or shell text.

## 3. Adjudication

The conductor reconciles conflicting findings against the cited evidence. Produce one root-cause verdict labelled per the claim-provenance doctrine (verified, derived, or judgment) and the chain of events in order, each event with its citation. An unresolved conflict stays in the verdict as an open point, never silently dropped. A `blocked:` return is an evidence gap named in the verdict, never a negative finding.

## 4. Artifacts

Derive the incident name per plan-workflow's name derivation (ticket key first). Write into that name's plan directory with the atomic write, subject to plan-workflow's "Do not write if" list, whose exception names the incident note:

- `incident - <name>.md`: the technical writeup. Scope fence, evidence sources checked, findings per source with citations, verdict and provenance, chain of events, outside-scope list. Redact customer PII before writing. Keep item ids, timestamps, and error codes. Where a finding cannot be written without PII, cite its location (table and key, log source and timestamp) instead of quoting it.
- The stakeholder summary, as a section at the top of the same note under "Summary for stakeholders": plain language, short, Slack-ready, domain nouns kept, uncertainty stated directly with the verdict's provenance label (verified, derived, or judgment), never softened or padded with filler.

Durable facts about the subsystem go to the topic note per obsidian-topic.

## 5. Handoff

If a fix is needed, route to `crawl` with the incident note as the brief. This skill never implements a fix and never mutates production.

## Boundary

Fan-out here is the orchestration doctrine's single-message parallel spawn, not a Workflow script: sources vary per project, the panel is small, and adjudication stays with the conductor. A project that runs the same incident shape repeatedly is the trigger to add a Workflow script.
