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

# Color & Gradients

- A gradient between RGB-complementary hues (blue→yellow, red→cyan) interpolated in sRGB averages to a desaturated gray at the midpoint — the gray dead zone; either pick endpoint hues that are neighbors on the wheel, or interpolate in OKLCH (`linear-gradient(in oklch, …)`) so the midpoint stays chromatic.
- Dark theme surfaces are near-black (#121212–#1E1E1E territory), not #000 — elevation is signaled by lightening surfaces, and pure black leaves no headroom; pure white text on pure black also halates for astigmatic users. Deliberate #000 for OLED battery is the one legitimate exception — make it a decision, not a default.
- Maximum contrast is not a WCAG violation — near-black text on off-white is a comfort refinement, never an excuse to drop below 4.5:1.
- Destructive actions use the danger/red token plus a non-color signal (verb label, icon, position) — red alone excludes colorblind users, and in a destructive confirm the safe action gets the default/prominent treatment, not the destructive one.
