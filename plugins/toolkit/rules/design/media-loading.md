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

# Media Loading

- The LCP image (hero, above-the-fold banner) gets `fetchpriority="high"` and must never have `loading="lazy"` — lazy-loading the LCP image is always wrong.
- Everything below the fold: `loading="lazy" decoding="async"`.
- `fetchpriority="high"` on at most one or two resources per page — it's a relative hint; spraying it everywhere makes it meaningless.
- Every `img` gets `width`/`height` attributes (or CSS `aspect-ratio`) so the browser reserves space — missing dimensions are a CLS defect.
- LCP image as a CSS background: preload it (`<link rel="preload" as="image" fetchpriority="high">`) — the preload scanner can't see CSS backgrounds.
