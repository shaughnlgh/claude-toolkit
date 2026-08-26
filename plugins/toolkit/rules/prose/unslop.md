---
source: toolkit@shaughn-toolkit
tags: [writing]
---

# Unslop catalog (AI-tell patterns)

Open this file when rewriting or reviewing existing prose, not when writing new prose from scratch (rules/prose.md already covers that). Scan the draft against the groups below, fix what matches, then ask the self-audit question: what makes this text obviously AI-generated? Fix whatever answer that question turns up, even if it is not on this list.

## Content

- Puffery: "pivotal moment", "testament to", "evolving landscape", "indelible mark". State what happened instead.
- Name-dropping: listing outlets or sources with no context. Pick one, say what it said.
- Superficial -ing phrases: "highlighting...", "ensuring...", "showcasing...", "fostering...". Delete them, or expand with a real source.
- Promotional language: "nestled", "vibrant", "breathtaking", "groundbreaking", "must-visit". Use a neutral description.
- Vague attribution: "experts believe", "industry reports suggest". Name the source or delete the claim.
- Formulaic contrast: "despite challenges, X continues to thrive". Replace with the specific facts.

## Language

- AI vocabulary: additionally, crucial, delve, enduring, fostering, garner, interplay, intricate, landscape (abstract), pivotal, tapestry (abstract), testament, underscore, vibrant. Use a plain word.
- Fancy stand-ins for "is": "serves as", "stands as", "boasts", "features". Write "is" or "has".
- "Not just X, but Y": state the point directly.
- Rule of three: forcing ideas into groups of three for cadence. Use the number the content actually has.
- Synonym cycling: protagonist, main character, central figure, hero, all in one paragraph. Pick one term and repeat it.
- False ranges: "from X to Y" where X and Y sit on no real scale. List the topics directly instead.

## Style

- Em dash overuse: an em dash in new prose is always a tell. End the sentence or use a comma. Do not swap in parentheses or a semicolon instead, that trades one tell for another. This is forward-looking only, it governs prose written from here on and does not require a retroactive sweep of existing toolkit text.
- Colon overuse: a colon belongs before a list or an example, not as a mid-sentence connector. "If you're coming from traditional automation: instead of registering handlers, you describe conditions" adds nothing. Rewrite the sentence to stand on its own: "Describing when the scheduler fires works best as plain English."
- Boldface overuse: do not bold every proper noun or acronym.
- Inline-header lists: a bold label and colon that restates the line is a tell, "**Performance:** performance improved...". Convert it to prose. A bold lead-in that ends in a period and names the item, with genuinely new detail after it, is fine, not a tell: "**Schema in TypeScript.** Tables live in one file."
- Title case headings: use sentence case.
- Decorative emojis: remove them from headings and bullets.
- Curly quotes: use straight quotes.

## Communication artifacts

- Chatbot phrases: "I hope this helps!", "Let me know if...", "Certainly!", "Found the smoking gun!". Remove them.
- Cutoff disclaimers: "while specific details are limited...". Find the source or remove the sentence.
- Sycophantic tone: "Great question! You're absolutely right!". Respond to the content directly.

## Filler

- Filler phrases: "in order to" becomes "to". "Due to the fact that" becomes "because". Delete "it is important to note that" outright.
- Excessive hedging: "could potentially possibly be argued that it might" becomes "may", or the plain fact.
- Generic conclusions: "the future looks bright" states nothing. Give the specific plan or fact, or delete the sentence.

## Jargon

- Abstract metaphor nouns: substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame, north star, flywheel. Each has a plainer concrete word: "substrate" becomes "base", "wedge in" becomes "add", "vector" becomes "way" or "method", "gold-plating" becomes "more than the job needs", "evacuate" becomes "move out". Pick the concrete word.

## Plain speech

- Say the mechanism, not the feeling: "the database stays close at hand" names a feeling. "`.toSQL()` returns the exact string sent to the database" names a mechanism. Ask what the sentence tells the reader to do or know, then write that. If it cannot become a concrete instruction, fact, or number, cut it.
- Shorten or split dense sentences: if the reader has to backtrack to parse it, break it in two or drop a clause. One idea per sentence.
- Active voice: catch "is/are/was/were + past participle" and name the actor. "The file is parsed by the loader" becomes "the loader parses the file". Passive stays only when the actor is unknown or genuinely does not matter.
- Cut adverbs, or use a stronger verb: "runs quickly" becomes "is fast" or the number. "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the verb is wrong.
- Prefer the plain word: "utilize" becomes "use", "leverage" becomes "use", "facilitate" becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym is rarely clearer.

## Before and after

- Filler and hedging: "The migration has completed and the table is being rebuilt, which will hopefully improve query performance going forward." becomes "The migration completed. The database rebuilds the table."
- Colon-as-connector: "If you're coming from traditional automation: instead of registering event handlers, you describe conditions and the scheduler figures out when to run them." becomes "Describing when the scheduler fires works best as plain English, not as registered event handlers."
- Inline-header list: "**Performance:** Performance improved across the board. **Reliability:** Reliability also improved." becomes "Both performance and reliability improved. Give the measured numbers: the latency delta and the error-rate change."
- Abstract jargon: "We built a new primitive as the substrate for the deploy vector." becomes "We built a new deploy step as the base for the release process."

## Adding voice

This section applies only to conversational replies, narrative writing, and other human-voice text, never to repo docs, ADRs, runbooks, or any text covered by rules/writing.md, which stay timeless and neutral.

- Have opinions. React to a fact instead of neutrally listing pros and cons.
- Vary rhythm. Mix short sentences with longer ones that take their time.
- Acknowledge complexity. "Impressive but also kind of unsettling" says more than "impressive."
- Use "I" when it fits. First person is not unprofessional.
- Let some mess in. Perfect structure reads as machine-made.
- Be specific. Not "this is concerning" but "there's something unsettling about agents churning away at 3am."
