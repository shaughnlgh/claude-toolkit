---
source: toolkit@shaughn-toolkit
tags: [config-coupling]
---

# Config coupling

- A hardcoded account, tenant, or platform identifier in code or committed config is a write-time defect when changing it requires a code edit.
- A literal standing in for an axis the project has committed to varying (a second tenant, platform, or environment named in the roadmap, the parent plan, or an existing config surface) is a defect even while only one value exists. Absent that commitment, one value stays one literal.
- A route or path string used in more than one place gets one definition.
- When the roadmap or parent plan has committed to an axis, add its seam now: a committed second caller counts as already announced.
- Speculative axes still get nothing. This rule extends minimalism, never repeals it.
