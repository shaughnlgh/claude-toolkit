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

# Scrolling

- Scrollable overlays (modals, drawers, side panels) get `overscroll-behavior: contain` so reaching the end doesn't chain scroll to the page behind.
- Anchor/skip-link targets under a sticky or fixed header get `scroll-margin-top` matching the header height, or the heading lands hidden behind it.
- Locking body scroll behind a modal: `overflow: hidden` on `body` alone can still let the background scroll or the page jump position on iOS Safari — use the `position: fixed` plus stored scroll-offset technique, and restore the scroll position on close.
- `scroll-behavior: smooth` (and any JS smooth scrolling) goes behind `@media (prefers-reduced-motion: no-preference)`.
- Never hijack wheel/touch scroll with JS (scroll-jacking); for snap points use CSS `scroll-snap-type`/`scroll-snap-align`.
