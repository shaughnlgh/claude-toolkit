#!/usr/bin/env python3
# Captures the uncommitted diff of one or several repo roots into one file and prints it as JSON. Usage: slice-capture.py --scratch <dir> --base <HEAD|sha> --root <dir> [--repo <dir>]...
# Exit 2: a bad argument or a failed git call, with one "slice-capture: <reason>" line on stderr.
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

BASE = re.compile(r"(HEAD|[0-9a-f]{7,40})\Z")
# Claude Code creates linked worktrees here, and git lists each as one untracked directory that git diff --no-index cannot read.
OWN_WORKTREES = ":(exclude,top).claude/worktrees/"
NUL = bytes(1)


def fail(reason):
    print("slice-capture: " + reason, file=sys.stderr)
    sys.exit(2)


def parse(argv):
    opts = {"--scratch": None, "--base": None, "--root": None}
    repos = []
    i = 0
    while i < len(argv):
        flag = argv[i]
        if flag not in opts and flag != "--repo":
            fail("unknown argument " + repr(flag))
        if i + 1 >= len(argv):
            fail(flag + " needs a value")
        value = argv[i + 1]
        if flag == "--repo":
            repos.append(value)
        elif opts[flag] is not None:
            fail(flag + " given twice")
        else:
            opts[flag] = value
        i += 2
    for flag, value in opts.items():
        if value is None:
            fail(flag + " is required")
    if not BASE.match(opts["--base"]):
        fail("--base must be HEAD or a 7 to 40 character lowercase hex sha, got " + repr(opts["--base"]))
    if not os.path.isabs(opts["--scratch"]):
        fail("--scratch must be an absolute path, got " + repr(opts["--scratch"]))
    for flag, value in [("--root", opts["--root"])] + [("--repo", r) for r in repos]:
        if not os.path.isabs(value) or not os.path.isdir(value):
            fail(flag + " must be an absolute existing directory, got " + repr(value))
    root = os.path.normpath(opts["--root"])
    repos = [os.path.normpath(r) for r in repos]
    for r in repos:
        if os.path.commonpath([root, r]) != root:
            fail("--repo " + repr(r) + " is not --root or under it")
        if repos.count(r) > 1:
            fail("--repo " + repr(r) + " is given twice")
    return opts["--scratch"], opts["--base"], root, repos


def git(repo, *args, ok=(0,)):
    try:
        done = subprocess.run(["git", *args], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        fail("git could not start in " + repo + ": " + str(e))
    if done.returncode not in ok:
        lines = done.stderr.decode("utf-8", "replace").strip().splitlines()
        fail("git " + " ".join(a if isinstance(a, str) else a.decode("utf-8", "replace") for a in args) + " exited " + str(done.returncode) + " in " + repo + (": " + lines[0] if lines else ""))
    return done.stdout


def listed(out, prefix):
    names = []
    for line in out.decode("utf-8", "surrogateescape").split("\n"):
        if line:
            names.append('"' + prefix + line[1:] if line.startswith('"') else prefix + line)
    return names


def main():
    scratch, base, root, given = parse(sys.argv[1:])
    multi = bool(given)
    repos = []
    for repo in given or [root]:
        rel = os.path.relpath(repo, root)
        prefix = "" if rel == "." else rel + "/"
        nested = [os.path.relpath(o, repo) for o in given if o != repo and os.path.commonpath([repo, o]) == repo]
        repos.append((repo, prefix, nested))
    os.makedirs(scratch, exist_ok=True)
    out = bytearray()
    paths = []
    parts = []
    for repo, prefix, nested in repos:
        flags = ["--src-prefix=a/" + prefix, "--dst-prefix=b/" + prefix] if multi else []
        spec = [OWN_WORKTREES] + [":(exclude,top)" + n + "/" for n in nested]
        tracked = ["--", "."] + spec[1:] if multi else []
        seg = git(repo, "diff", *flags, base, *tracked)
        for f in git(repo, "ls-files", "--others", "--exclude-standard", "-z", "--", *spec).split(NUL):
            if f:
                seg += git(repo, "diff", "--no-index", *flags, "--", "/dev/null", f, ok=(0, 1))
        out += seg
        paths += listed(git(repo, "-c", "core.quotePath=false", "diff", base, "--name-only", *tracked), prefix)
        paths += listed(git(repo, "-c", "core.quotePath=false", "ls-files", "--others", "--exclude-standard", "--", *spec), prefix)
        parts.append({"root": repo, "hash12": hashlib.sha256(seg).hexdigest()[:12], "empty": not seg})
    hash12 = hashlib.sha256(out).hexdigest()[:12]
    try:
        fd, tmp = tempfile.mkstemp(prefix="slice.", suffix=".tmp", dir=scratch)
        with os.fdopen(fd, "wb") as fh:
            fh.write(out)
        diff_path = os.path.join(scratch, "slice-" + hash12 + ".diff")
        os.replace(tmp, diff_path)
    except OSError as e:
        fail("could not write the diff under " + scratch + ": " + str(e))
    result = {"diffPath": diff_path, "hash12": hash12, "empty": not out, "paths": paths}
    if multi:
        result["parts"] = parts
    sys.stdout.buffer.write(json.dumps(result, ensure_ascii=False).encode("utf-8", "surrogateescape") + b"\n")


if __name__ == "__main__":
    main()
