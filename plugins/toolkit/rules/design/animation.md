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

# Animation

- Presentational effects (typewriter, marquee, reveals, spinners) are CSS animations, not JS loops or libraries. Example — typewriter with no JS: `animation: type 2.5s steps(22) forwards` on an `overflow: hidden; white-space: nowrap` element, `steps()` count = character count (widths in `ch` are only reliable in monospace). Reach for JS only when the effect depends on runtime state or data.
- Default to compositor-only properties: animate `transform` and `opacity`. Contained text effects (typewriter's width/clip) are the exception — keep them inside a fixed-size wrapper so surrounding layout never reflows.
- Never animate layout properties (`top`/`left`/`width`/`height`) on page-level containers; use transforms.
- Gate non-essential motion behind `@media (prefers-reduced-motion: reduce)` — disable or reduce it there.
