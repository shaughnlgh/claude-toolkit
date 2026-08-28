# Design

Structural design judgment: how code should be shaped and where the boundaries go. This applies whenever code is written or edited, on top of project-local rules. It is always-on write-time judgment, not a moment-triggered skill.

## Deep modules, narrow interfaces

- Prefer deep modules with simple interfaces: a module's interface should be much smaller than its implementation. Favor fewer, deeper units over many shallow pass-through ones.
- Hide complexity behind the interface. Callers should not need to know the internals.
- Design the interface from the caller's needs, not the implementation's convenience.

## Seams and abstraction

- Put boundaries where change is isolated, so a likely future change touches one place, not many. Distinguish committed from likely: an axis the roadmap or parent plan commits to gets its seam now. A merely likely one waits for its second caller (see minimalism.md).
- A new abstraction must earn its keep. Do not add a layer that only forwards calls. Removing a needless layer is as valid as adding one.

## vs. conventions.md

Conventions is how code should look and which existing patterns to follow. Design is how code should be shaped and where the boundaries go.
