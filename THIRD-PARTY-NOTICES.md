# Third-Party Notices

This toolkit is MIT licensed (see `LICENSE`). It also includes and adapts third-party
work, used under that work's original license and attributed here as those licenses
require.

## Impeccable — design anti-pattern detector and design guidance

- **Upstream:** https://github.com/pbakaus/impeccable
- **Author / copyright:** Paul Bakaus
- **License:** Apache License 2.0
- **Pinned at commit:** `8967edc988ee146823bca3c51fcf51296e9dec18` (2026-07-17)

Two things here are derived from Impeccable:

1. **Static design anti-pattern detector.** The engine under
   `plugins/toolkit/scripts/design-detector/vendor/` is vendored from Impeccable's
   `cli/engine/` — the regex and static-HTML detection tiers plus their shared
   helpers — adapted to run standalone, outside Impeccable's own CLI and runtime. A
   copy of the Apache 2.0 license text and a `NOTICE` recording the exact
   modifications live in `plugins/toolkit/scripts/design-detector/`, and each vendored
   file carries a source header.

2. **Design guidance.** The anti-slop and quality guidance in the `frontend-designer`
   agent and the `frontend` rule is adapted from Impeccable's anti-pattern catalog
   (`cli/engine/registry/antipatterns.mjs`) and its product / brand / interaction-design
   reference material, rewritten in this toolkit's voice.

**Modifications:** extracted a dependency-light subset of the engine, added a
standalone CLI entry point, removed Impeccable-runtime and config-file coupling, and
rephrased the guidance for this toolkit's agent and rule.

**Not included:** Impeccable's `skill/reference/ios.md` and `android.md` (which
Impeccable itself derives from ehmo's MIT-licensed `platform-design-skills`) are
deliberately not used here, so no further attribution chain applies.

The full Apache License 2.0 text is at
`plugins/toolkit/scripts/design-detector/LICENSE`.

## Unslop — AI-writing pattern catalog

- **Upstream:** https://github.com/cursor/plugins (path `pstack/skills/unslop/SKILL.md`)
- **Author / copyright:** Lauren Tan
- **License:** MIT
- **Pinned at commit:** `bdf7aa355337897f167153e05069aca505dae17c` (2026-08-24)

Derived: the AI-tell pattern catalog in `plugins/toolkit/rules/prose/unslop.md` and part of the distilled `plugins/toolkit/rules/prose.md`, rewritten in this toolkit's voice.

## SimpleEnglish — ASD-STE100 agent skill

- **Upstream:** https://github.com/AminBlg/SimpleEnglish
- **Author / copyright:** AminBlg
- **License:** MIT
- **Pinned at commit:** `8e8a008a13e4b478f9ccc20ca16e79aef66c0739` (2026-08-21)

Derived: the instructional-prose discipline in `plugins/toolkit/rules/prose/simple-english.md` (word-swap table, modal ladder, structural rules) and part of `plugins/toolkit/rules/prose.md`, a pragmatic adaptation of the skill's rendering of ASD-STE100 structure. The ASD-STE100 standard itself is published by ASD, and no dictionary content is reproduced here.
