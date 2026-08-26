---
source: toolkit@shaughn-toolkit
tags: [writing]
---

# Simple English catalog (instructional-text discipline)

This is a pragmatic adaptation of the structure behind ASD-STE100 Simplified Technical English, not the standard itself and not a compliance claim. Domain vocabulary stays: words like "webhook", "idempotent", or "commit" are legal technical terms and this file does not police them. Marketing and brand copy are out of scope, STE deletes persuasion by design.

Open this file for runbooks, error messages, procedures, and instructions given to an AI agent. rules/prose.md already covers general prose. This file adds the structural discipline that applies specifically to instructional and reference text.

## Classify before writing

Every other rule depends on this split. Do not mix the two in one passage.

| | Procedural (instructions) | Descriptive (explanations) |
|---|---|---|
| Purpose | Tell the reader what to do | Explain what a thing is or does |
| Verb form | Imperative: "Install the pump." | Simple present, past, or future |
| Unit | One instruction per sentence | One topic per paragraph |

A "Getting started" section is procedural. An "Architecture" section is descriptive. A note inside a procedure is descriptive, it explains, it does not instruct.

## Sentence-length calibration

STE caps instructions at 20 words and descriptions at 25. Treat those numbers as calibration for what "short" means, not as a counting exercise to run on every sentence. Do not count words. Instead, split any sentence that carries two ideas, and read each sentence once to check it survives that one read.

## Simple tenses and active voice

Use only infinitive, imperative, simple present, simple past, simple future, and the past participle as an adjective ("the cached response"). Drop present perfect ("has completed" becomes "completed") and drop "-ing" forms used as verbs ("making it easy" becomes a new sentence). Use active voice. Keep passive only in descriptive text when the actor is genuinely unknown, and prefer "you" or the product name as the subject before falling back to passive.

Before: "The migration has completed and the table is being rebuilt."
After: "The migration completed. The database rebuilds the table."

## The modal ladder

| You wrote | Write instead |
|---|---|
| `should` (requirement) | must |
| `should` (recommendation) | Delete it, or state it as fact |
| `should` (inverted: "`should` a failure occur") | if: "if a failure occurs" |
| may / might / could (possibility) | can |
| may (permission) | can |
| would (hypothetical) | can, or restructure as "if X occurs, Y occurs" |

Before: "The flag can be set in the config file, making restarts unnecessary."
After: "You can set the flag in the config file. Then a restart is not necessary."

## Condition before command

Put a required condition before the command, joined by a comma: "If the build fails, read the log." A trailing condition is easy for a reader, and a model, to drop.

## Anti-terseness

Short does not mean telegraphed. Keep complete grammar: keep articles, keep "that", no contractions in docs.

Wrong shortening: "Ensure file exists before running."
Correct: "Make sure that the file exists before you run the command."

## One word, one meaning

Pick one term per concept for the whole document and do not rotate synonyms.

- config / configuration / settings / options: pick one.
- check / verify / confirm / ensure: pick one, or route by intent, "make sure that" for a state, "examine" for a fault search, "measure" for a value.

## Break long noun chains

Break a noun chain longer than three words with a preposition (of, on, in, for).

Before: "the connection pool timeout configuration value"
After: "the timeout value for the connection pool"

## Warnings: command or condition first, risk second

Never bury the instruction after the explanation.

Before: "Note that data loss may occur in some circumstances if the destructive flag happens to be enabled when running against production."
After: "Do not use the `--force` flag against production. The flag deletes rows that do not match the source."

## Slop-to-simple word swaps

| Slop | Write instead |
|---|---|
| leverage, utilize | use |
| in order to | to |
| prior to | before |
| ensure | make sure that |
| it is worth noting that | delete it |
| it's important to, crucially | delete it, state the fact |
| simply, just, easily, seamlessly, effortlessly | delete it |
| robust, powerful, comprehensive, performant | delete it, or give the measurable property |
| functionality | function, feature |
| enables you to, allows you to | you can |
| is designed to, aims to | say what it does |
| facilitate | help, make possible |
| dive into, delve into | read, examine |
| when it comes to | for |
| in the event that | if |
| due to the fact that | because |
| as needed, as necessary | state the condition |
| and/or | pick one, or write "X, or Y, or both" |
| e.g. / i.e. / etc. | for example / that is / name the items |
| gracefully handles | say what it does, "retries three times, then stops" |
| out of the box | by default |
| under the hood | internally |
| blazingly fast, state-of-the-art | fast, give the number, or delete it |
| streamline | make simpler, make faster |
| plethora, myriad | many |
| addresses the issue, tackles | corrects the fault, removes the error |

## Untouchables

Leave these exact, even when they break every rule above: code blocks, inline code, identifiers, CLI commands, flags, file paths, quoted error messages and log lines, product names, API endpoint names, config keys, and UI labels. Facts are untouchable too. Rewrite the style, never the content. When the source gives no number, no cause, or no exact term, keep the general statement, do not invent specifics to look concrete.

## By text type

- Error messages: state what happened in simple past, state the cause if known, give the command or condition to fix it. When the cause is known, name it. Never invent one. Before: "Oops! Something went wrong while attempting to establish a connection. Please ensure your credentials are properly configured and try again." After: "The connection failed. Make sure that the credentials in the configuration are correct. Then connect again."
- Runbooks and procedures: every step imperative, one instruction per step, condition before command, warnings before the step with the command first and the risk second.
- Incident reports: simple past only, never present perfect. Present perfect hides when things happened, and hedges like "may have impacted" hide what is actually known. Before: "We have identified an issue that may have impacted some users' ability to access the service." After: "Some requests to the service failed. The affected fraction is not yet measured. The cause is under investigation." State the unknown as "unknown" rather than hedging around it. When the numbers are measured, give them.
- Commit messages: imperative subject line, plain past-tense facts in the body, no "this PR aims to".
- Instructions for AI agents: one instruction per sentence, so each rule is independently quotable. One word, one meaning, so the model does not treat "check", "verify", and "validate" as three different operations. Condition before command, a trailing condition is often dropped. Never write `should`, a model reads it as optional. Write "must" or delete the rule.

## Self-check

Run this scan on a draft before delivery.

- Search for `'ll`, `'re`, `'ve`, `n't`, `it's`: a contraction. Expand it.
- Search for `has been`, `have been`, `had been`, or "has"/"have" plus a past participle: present or past perfect. Rewrite in simple past or simple present.
- Search for `should`, `would`, `may`, `might`, `could`, `shall`: an unapproved modal. Apply the modal ladder above.
- Search for `, making`, `, allowing`, `, enabling`, `, ensuring`: an "-ing" clause standing in for a verb. Start a new sentence with a real subject.
- Search for `;`: a semicolon. Write two sentences.
- Search for `e.g.`, `i.e.`, `etc.`: a Latin abbreviation. Write "for example", "that is", or name the items.
- Split any sentence that carries two ideas, using the calibration above, not a word count.
- Collapse synonym rotation to the one term you picked for each concept.
