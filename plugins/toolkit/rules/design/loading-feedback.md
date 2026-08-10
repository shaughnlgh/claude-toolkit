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

# Loading Feedback

- Under ~1s: no indicator at all — a flash of spinner/skeleton is more disruptive than the wait.
- Short waits in an isolated component (button submit, small panel): spinner.
- Full-page or large-region loads from ~1s up to ~10s: skeleton screen that mirrors the final layout — content-shaped placeholders, never an empty frame, which reads as broken.
- The skeleton must occupy the same dimensions as the content it stands in for, so nothing shifts when data arrives (see media-loading.md for the CLS rules).
- Beyond ~10s: determinate progress bar, with a time estimate when one exists.
- Skeletons are not a blanket upgrade over spinners — match the indicator to duration and scope; a skeleton on a sub-second load or a spinner on a 10s load are both wrong.
