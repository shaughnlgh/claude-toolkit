---
source: toolkit@shaughn-toolkit
tags: [writing]
---

# Writing (docs, comments, ADRs)

- Write for a stranger reading in a year. Test every line: does it make sense with no access to this session, this machine, this ticket, this conversation? If not, cut it or generalize it.
- Documentation states what is, never what happened. No "we observed", no session numbers, no machine names, no ticket/PR IDs cited as context, no timelines. If it reads like a diary entry, it is one.
- The best comment is none: make the code say it. A comment earns its line only by stating what code cannot — a constraint, an invariant, an external quirk. One line. Never a book, never a narration of the change.
- ADRs record context an outsider needs, the decision, and its consequences — a screenful, not a chapter. Evidence gets one sentence and a pointer, not a reproduction.
- Prose ladder before writing any line: does it need to exist? Is it already said elsewhere (link it)? Can a paragraph be a sentence? Only then write the minimum that serves the reader.
- Deletion over addition applies to prose. When updating a doc, remove what's stale before appending what's new.
- Journal material's homes are work notes, commit messages, and PR bodies. The one exception a repo doc gets: an ADR's single compressed evidence sentence with a pointer — never a reproduction.
