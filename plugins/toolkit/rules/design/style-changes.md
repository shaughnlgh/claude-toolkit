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

# Style changes: source, verification, ownership

- Edit styles at their source. When the theme is owned, never stack overrides in a custom sheet and never hand-edit compiled CSS. Rebuild from source and commit source and output together.
- A devtools experiment is a diagnosis, not the fix. Carry the finding back to the source rule.
- Prefer deleting the obsolete source rule over layering an override that neutralizes it.
- Verify the rendered result on the element the user named. For a visible seam, check border, box-shadow, outline, pseudo-elements, and descendants before concluding.
- To verify a deleted CSS rule, replace the stylesheet link in place. Never clone the link, because both sheets then load and the deleted rule still applies from the old one.
- Shared frontend fabric (tokens, resets, utilities) lives in one baseline bundle that every page loads. Never duplicate it per bundle and never rely on load order to resolve conflicts.
