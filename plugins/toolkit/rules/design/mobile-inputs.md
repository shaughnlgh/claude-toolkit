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

# Mobile Inputs & Viewport

- `input`, `select`, `textarea`: `font-size` must be >= 16px (1rem). Anything under 16px makes iOS Safari auto-zoom the page on focus.
- Never suppress that zoom with `maximum-scale=1` or `user-scalable=no` in the viewport meta — it disables pinch-zoom (an accessibility failure, and Android honors it fully). Fix the font size instead.
- Touch targets >= 44x44px. Pad the hit area (padding on the interactive element), don't enlarge the glyph.
- Hover-only affordances are invisible on touch — anything revealed by `:hover` needs a focus/active or explicit-control equivalent.
- Full-viewport heights: use `100dvh` (or `100svh` for always-visible content) instead of `100vh`, which overflows behind mobile browser chrome.
- Fixed headers/footers on notched devices: respect `env(safe-area-inset-*)`.
