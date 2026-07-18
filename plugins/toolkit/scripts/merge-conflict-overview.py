#!/usr/bin/env python3
# merge-conflict-overview.py — summarize and display git conflict markers, read-only
# usage: merge-conflict-overview.py [file ...]
#   no args: discovers conflicted files via `git diff --name-only --diff-filter=U`
import argparse
import shutil
import subprocess
import sys

OURS_START = "<<<<<<<"
BASE_START = "|||||||"
SEP = "======="
THEIRS_END = ">>>>>>>"


class Hunk:
    def __init__(self, ours_label, theirs_label):
        self.ours_label = ours_label
        self.theirs_label = theirs_label
        self.ours = []
        self.base = []
        self.theirs = []


def discover_conflicted_files():
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=U"],
            check=True, capture_output=True, text=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"error: could not run git diff ({e})", file=sys.stderr)
        sys.exit(1)
    return [line for line in out.splitlines() if line.strip()]


def read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="strict") as f:
            return f.readlines()
    except UnicodeDecodeError:
        return None  # binary, caller skips with a note
    except OSError as e:
        print(f"note: skipping {path} (unreadable: {e})", file=sys.stderr)
        return None


def parse_hunks(lines):
    """Split lines into (preamble ignored) list of Hunk objects. Lines outside
    markers are not conflict content, so only hunks are returned."""
    hunks = []
    cur = None
    section = None  # 'ours' | 'base' | 'theirs'
    for line in lines:
        stripped = line.rstrip("\n")
        if stripped.startswith(OURS_START):
            cur = Hunk(stripped[len(OURS_START):].strip(), "")
            section = "ours"
            continue
        if cur is None:
            continue
        if stripped.startswith(BASE_START):
            section = "base"
            continue
        if stripped.startswith(SEP) and not stripped.startswith(THEIRS_END):
            section = "theirs"
            continue
        if stripped.startswith(THEIRS_END):
            cur.theirs_label = stripped[len(THEIRS_END):].strip()
            hunks.append(cur)
            cur = None
            section = None
            continue
        if section == "ours":
            cur.ours.append(line.rstrip("\n"))
        elif section == "base":
            cur.base.append(line.rstrip("\n"))
        elif section == "theirs":
            cur.theirs.append(line.rstrip("\n"))
    return hunks


def print_overview(results):
    conflicted = [r for r in results if r["hunks"]]
    print("=" * 70)
    print("OVERVIEW")
    print("=" * 70)
    print(f"Conflicted files: {len(conflicted)}")
    for r in results:
        if not r["hunks"]:
            continue
        print(f"\n  {r['path']}")
        print(f"    hunks: {len(r['hunks'])}")
        for i, h in enumerate(r["hunks"], 1):
            base_note = f", base={len(h.base)}" if h.base else ""
            print(
                f"      hunk {i}: ours={len(h.ours)} lines"
                f"{base_note}, theirs={len(h.theirs)} lines"
            )
    print()


def side_by_side(left_lines, right_lines, left_label, right_label, width):
    col = max(20, (width - 3) // 2)
    print(f"{left_label:<{col}} | {right_label}")
    print(f"{'-' * col}-+-{'-' * col}")
    for i in range(max(len(left_lines), len(right_lines))):
        left = left_lines[i] if i < len(left_lines) else ""
        right = right_lines[i] if i < len(right_lines) else ""
        print(f"{left[:col]:<{col}} | {right[:col]}")


def stacked(label, block_lines):
    print(f"--- {label} ---")
    if not block_lines:
        print("(empty)")
    for line in block_lines:
        print(line)


def print_hunk(h, index, width):
    print(f"\n--- Hunk {index} ---")
    use_columns = width >= 50
    if h.base:
        # diff3 style: three sides, print stacked (columns get cramped past two sides)
        stacked("BASE", h.base)
        stacked(f"OURS ({h.ours_label})" if h.ours_label else "OURS", h.ours)
        stacked(f"THEIRS ({h.theirs_label})" if h.theirs_label else "THEIRS", h.theirs)
        return
    ours_label = f"OURS ({h.ours_label})" if h.ours_label else "OURS"
    theirs_label = f"THEIRS ({h.theirs_label})" if h.theirs_label else "THEIRS"
    if use_columns:
        side_by_side(h.ours, h.theirs, ours_label, theirs_label, width)
    else:
        stacked(ours_label, h.ours)
        stacked(theirs_label, h.theirs)


def main():
    parser = argparse.ArgumentParser(
        description="Overview and side-by-side view of git conflict markers."
    )
    parser.add_argument(
        "paths", nargs="*",
        help="conflicted files to inspect (default: discover via git diff --diff-filter=U)",
    )
    args = parser.parse_args()

    paths = args.paths if args.paths else discover_conflicted_files()

    if not paths:
        print("No conflicts found.")
        sys.exit(0)

    width = shutil.get_terminal_size(fallback=(100, 24)).columns

    results = []
    for path in paths:
        lines = read_lines(path)
        if lines is None:
            print(f"note: skipping {path} (binary or unreadable)", file=sys.stderr)
            results.append({"path": path, "hunks": []})
            continue
        hunks = parse_hunks(lines)
        if not hunks:
            print(f"note: {path} has no conflict markers, skipping", file=sys.stderr)
        results.append({"path": path, "hunks": hunks})

    if not any(r["hunks"] for r in results):
        print("No conflicts found.")
        sys.exit(0)

    print_overview(results)

    for r in results:
        if not r["hunks"]:
            continue
        print("=" * 70)
        print(f"FILE: {r['path']}")
        print("=" * 70)
        for i, h in enumerate(r["hunks"], 1):
            print_hunk(h, i, width)
        print()


if __name__ == "__main__":
    main()
