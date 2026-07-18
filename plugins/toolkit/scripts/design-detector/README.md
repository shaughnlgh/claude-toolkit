# design-detector

A deterministic, no-LLM static design anti-pattern detector. It scans HTML/CSS/JSX/
TSX-style source for most of Impeccable's 46 "AI slop" and design-quality
anti-patterns (overused fonts, gradient text, cream/beige palettes, cramped padding,
low-contrast text, em-dash overuse, marketing buzzwords, and more) — no browser,
no screenshots, no LLM call. A few layout rules (`text-overflow`, `line-length`,
`body-text-viewport-edge`) need a real browser and do not fire in this static engine.

This is vendored (Path A: reuse + attribute) from
[Impeccable](https://github.com/pbakaus/impeccable) by Paul Bakaus, Apache-2.0
licensed. See `NOTICE` and `LICENSE` in this directory, and the repo-root
`THIRD-PARTY-NOTICES.md`, for the full attribution and the (minimal — header
comments only) modifications made.

## Running it

```
node detect.mjs <file> [file ...]
```

Prints findings grouped by file (rule id, rule name, line number where available,
one-line description), then a total count. Always exits 0.

## Zero-dependency by default

Out of the box, with nothing installed, `detect.mjs` runs in **regex mode**: it
reads each file as text and runs the pattern-based checks (`vendor/engines/regex/detect-text.mjs`).
This covers `.css`, `.jsx`, `.tsx`, and similar source files, and is what the test
in this directory's history exercised — no `npm install` required.

## Optional: HTML-aware mode

For `.html` / `.htm` files, `detect.mjs` calls into `vendor/engines/static-html/detect-html.mjs`,
which *can* parse the file into a real DOM and resolve the CSS cascade (inline
styles, `<style>` blocks, computed values) for higher-fidelity element- and
page-level checks. That tier needs four optional packages:

- `htmlparser2`
- `css-select`
- `css-tree`
- `domutils`

These are declared in `package.json` under `optionalDependencies` only — nothing
is installed automatically, and no `node_modules` ships in this directory. Audit
each package first (per house rule: check for vulnerabilities, postinstall
scripts, and typo-squatting) before running `npm install` here. If those
packages aren't present, HTML files still get scanned — `detect-html.mjs` falls
back to the same regex engine used for non-HTML files, so you still get
findings, just without the DOM/cascade-aware element checks.

## Layout

```
design-detector/
├── detect.mjs        toolkit CLI entry (MIT, this repo's license)
├── package.json       optional deps only, no install performed
├── LICENSE            Apache-2.0 (Impeccable's license, verbatim)
├── NOTICE             what was vendored + modifications (Apache-2.0 §4)
└── vendor/            vendored Impeccable engine, unmodified except source headers
```
