#!/usr/bin/env python3
"""Writes <vault root>/INDEX.md, the topic index that topic-recall.py reads.

Usage: vault-index.py <vault root>, run through `vault-fs.sh topic-index`.
Exit codes: 0 wrote or refreshed the file, or left the frontmatter scan in charge (a note cannot be
written as a row, two notes share a title, or another tool writes the file). 1 refused: INDEX.md is not
a regular file, or the write failed.
"""
from __future__ import annotations

import importlib.util
import os
import sys

_spec = importlib.util.spec_from_file_location(
    "topic_recall", os.path.join(os.path.dirname(os.path.realpath(__file__)), "topic-recall.py"))
tr = importlib.util.module_from_spec(_spec)
sys.modules["topic_recall"] = tr
_spec.loader.exec_module(tr)


def render_row(c) -> str:
    meta = "; ".join(p for p in (", ".join(c.repos), c.verified) if p)
    summary = " ".join(c.summary.split())
    return f"- [[{c.title}]]" + (f" — {summary}" if summary else "") + f" ({meta})"


def round_trips(c) -> bool:
    row = tr.parse_row(render_row(c))
    return row is not None and (row.title, row.summary, row.repos, row.verified) == (c.title, " ".join(c.summary.split()), c.repos, c.verified)


def render(rows) -> str:
    lines = [render_row(c) for c in sorted(rows, key=lambda c: c.title.lower())]
    return f"# Vault index\n\n{tr.GENERATED_MARKER}\n\n{tr.TOPICS_HEADING}\n\n" + "\n".join(lines) + "\n"


def unindexable(rows) -> list[str]:
    """One entry per note that would make the index leave a note out or resolve two notes to one path."""
    by_title: dict[str, list[str]] = {}
    for c in rows:
        by_title.setdefault(c.title, []).append(c.path)
    bad = [f"{c.path} (title or repos cannot be written as a row)" for c in rows if not round_trips(c)]
    bad += [f"{path} (shares its title)" for paths in by_title.values() if len(paths) > 1 for path in paths]
    return bad


def main(root: str) -> int:
    rows = tr.scan_topics(root)
    index_path = os.path.join(root, tr.INDEX_NAME)
    current = None
    if os.path.lexists(index_path):
        if not tr.regular_file(index_path):
            print(f"refused: {index_path} is not a regular file", file=sys.stderr)
            return 1
        with open(index_path, encoding="utf-8", errors="replace") as fh:
            current = fh.read()
        if tr.GENERATED_MARKER not in current.splitlines():
            print("skipped: INDEX.md is written by another tool")
            return 0
    bad = unindexable(rows)
    if bad:
        print("vault-index: wrote nothing and the frontmatter scan stays in use, because these notes cannot be indexed: "
              + ", ".join(bad), file=sys.stderr)
        return 0
    text = render(rows)
    try:
        if text != current:
            tmp = index_path + ".tmp"
            if os.path.lexists(tmp):
                os.unlink(tmp)
            with open(tmp, "x", encoding="utf-8") as fh:
                fh.write(text)
            os.replace(tmp, index_path)
        # The replace makes the root folder newer than the file; index_is_current needs the index at or after it.
        os.utime(index_path)
    except OSError as exc:
        print(f"vault-index: cannot write {index_path}: {exc.strerror}", file=sys.stderr)
        return 1
    print(f"wrote: {index_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: vault-index.py <vault root>", file=sys.stderr)
        sys.exit(1)
    sys.exit(main(sys.argv[1]))
