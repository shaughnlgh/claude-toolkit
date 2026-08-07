---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/*.css"
  - "**/*.scss"
  - "**/*.html"
  - "**/components/**"
  - "**/pages/**"
  - "**/views/**"
  - "**/layouts/**"
  - "**/styles/**"
source: toolkit@shaughn-toolkit
tags: [design, frontend]
---

# Form Semantics

- Every input gets the correct `type=` and, where the type alone misleads, `inputmode=` — `type="email"`, `type="tel"`, `type="url"` so mobile keyboards match the field.
- Numeric codes (OTP, card numbers, postal codes) are `type="text" inputmode="numeric"`, never `type="number"` — number inputs add spinners, increment on scroll, and strip leading zeros.
- Set `autocomplete` deliberately: `name`, `email`, `tel`, `current-password`/`new-password`, `one-time-code` for OTP fields — missing or wrong values break password managers and SMS-code autofill.
- Never block paste on any field (password, email-confirm, codes) — it defeats password managers and is an accessibility failure.
- Every input has a real `<label for>` (or wrapping label); placeholder-as-label is always wrong — it vanishes on input and fails screen readers and contrast.
- Set `enterkeyhint` when the mobile return key's default action would mislead (e.g. `enterkeyhint="search"`).
