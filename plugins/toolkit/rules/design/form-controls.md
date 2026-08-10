---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/*.css"
  - "**/*.scss"
  - "**/*.sass"
  - "**/*.less"
  - "**/*.html"
  - "**/*.phtml"
  - "**/components/**"
  - "**/pages/**"
  - "**/views/**"
  - "**/layouts/**"
  - "**/styles/**"
  - "**/templates/**"
source: toolkit@shaughn-toolkit
tags: [design, frontend]
---

# Form Controls & Interaction

- Options ≤5: render them all visibly as radios/checkboxes, never a dropdown — users open short dropdowns just to see what's in them, and a select hides the answer space.
- Radios for single choice, checkboxes for multiple; a `<select>` is a last resort, not a default.
- Long uncategorized lists (countries, currencies): combobox that filters as you type AND scrolls, never a bare 200-item select. ARIA combobox semantics are inconsistent across screen readers — test with one, don't assume. First ask whether the long list can be designed away (narrowing question, curated shortlist).
- OTP/verification codes: one real input (`inputmode="numeric"`, `autocomplete="one-time-code"`) — if the segmented-boxes look is wanted, render segments with CSS over that single input; N separate inputs break SMS autofill, paste, mid-code editing, and screen readers (see forms.md for the attribute rules).
- Input masks that live-format as the user types (phone, card, date) reduce errors — but only when localized to the user's regional format; a mask that rejects a valid local format is worse than no mask. A static format hint in placeholder text is not a mask: it vanishes on first keystroke.
- Validate on blur or after plausible completion, never per keystroke — flagging a half-typed value as wrong is a false error. Live per-keystroke feedback is right only for password-requirement checklists, where the user expects a running score.
- On submit, field-level errors are paired with a focusable error summary at the top of the form — inline-only errors are easy for screen-reader users to miss.
- Text fields are bordered or filled boxes with a static label above the field — underline-only fields read as dividers, and floating labels trade label visibility for no gain.
- One column, labels above fields. Side-placed labels force zig-zag scanning; multi-column forms slow completion.
- Long forms: cut fields first — field count drives abandonment, not step count. What remains long gets split into logical steps with a progress indicator. Never split a short form into steps.
- Memorable dates (date of birth, card expiry): separate labeled text fields per date part — day/month/year, month/year for card expiry — each with its own `autocomplete` token. Calendar and wheel pickers are for near-term scheduling only — scrolling decades to a birth year is the anti-pattern.
- A search input may use its placeholder as a scope hint ("Artists, Albums, Songs…") backed by an `aria-label` — this is the one placeholder exception; placeholder-as-label stays banned (forms.md).
