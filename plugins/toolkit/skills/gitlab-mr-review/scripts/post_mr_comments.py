#!/usr/bin/env python3
"""Post review findings as positioned discussions on a GitLab MR.

Usage:
  GITLAB_TOKEN=... post_mr_comments.py <comments.json> [--dry-run]

comments.json schema:
{
  "host": "https://gitlab.example.com",
  "project": "group/subgroup/repo",
  "mr_iid": 57,
  "expected_head_sha": "<sha the diff was reviewed at>",
  "diff_path": "/abs/path/to/saved.diff",
  "comments": [
    {"path": "app/code/.../File.php", "anchor": "<exact or substring of an added line>", "body": "markdown"}
  ],
  "summary": "markdown for a top-level summary note (optional)"
}

Behavior:
- Aborts if the MR head sha differs from expected_head_sha (anchors may be stale).
  Refetch the diff, confirm content is unchanged (or re-review), update the sha, retry.
- Anchors resolve against ADDED lines in the diff; exact match first, then substring.
- Positioned discussion per comment; falls back to an unpositioned discussion
  (prefixed with file:line) if GitLab rejects the position.
- Always run --dry-run first and check every anchor resolves.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def api(host, token, method, path, data=None):
    url = f"{host}/api/v4/{path}"
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("PRIVATE-TOKEN", token)
    if body:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def build_line_index(diff_path):
    """Map (new_path, added-line-content) -> new-file line number."""
    index = {}
    path = None
    new_line = 0
    with open(diff_path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("+++ "):
                path = line[4:].strip()
                if path.startswith("b/"):
                    path = path[2:]
                continue
            if line.startswith("--- ") or line.startswith("diff ") or line.startswith("index "):
                continue
            if line.startswith("@@"):
                seg = line.split("+")[1].split(" ")[0]
                new_line = int(seg.split(",")[0])
                continue
            if path is None:
                continue
            if line.startswith("+"):
                index[(path, line[1:].strip())] = new_line
                new_line += 1
            elif line.startswith("-"):
                pass
            else:
                new_line += 1
    return index


def main():
    cfg = json.load(open(sys.argv[1]))
    dry_run = "--dry-run" in sys.argv
    token = os.environ["GITLAB_TOKEN"]
    host = cfg["host"].rstrip("/")
    project = urllib.parse.quote(cfg["project"], safe="")
    iid = cfg["mr_iid"]

    mr = api(host, token, "GET", f"projects/{project}/merge_requests/{iid}")
    refs = mr["diff_refs"]
    print(f"MR head: {mr['sha']}  refs: base={refs['base_sha'][:8]} head={refs['head_sha'][:8]}")
    if mr["sha"] != cfg["expected_head_sha"]:
        print("ABORT: MR head changed since review — refetch the diff, confirm content, update expected_head_sha.")
        sys.exit(1)

    index = build_line_index(cfg["diff_path"])
    resolved = []
    unresolved = 0
    for c in cfg["comments"]:
        key = (c["path"], c["anchor"].strip())
        line = index.get(key)
        if line is None:
            line = next((v for (p, content), v in index.items()
                         if p == c["path"] and c["anchor"].strip() in content), None)
        if line is None:
            unresolved += 1
            print(f"UNRESOLVED anchor for {c['path']}: {c['anchor'][:70]}")
        resolved.append((c, line))

    if dry_run:
        for c, line in resolved:
            print(f"{c['path']}:{line}  -> {c['body'].splitlines()[0][:80]}")
        sys.exit(1 if unresolved else 0)

    for c, line in resolved:
        payload = {"body": c["body"]}
        if line is not None:
            payload["position"] = {
                "position_type": "text",
                "base_sha": refs["base_sha"],
                "start_sha": refs["start_sha"],
                "head_sha": refs["head_sha"],
                "new_path": c["path"],
                "new_line": line,
            }
        else:
            payload["body"] = f"**`{c['path']}`**\n\n" + c["body"]
        try:
            d = api(host, token, "POST", f"projects/{project}/merge_requests/{iid}/discussions", payload)
            print(f"OK  {c['path']}:{line}  discussion {d['id'][:8]}")
        except urllib.error.HTTPError as e:
            print(f"POSITION FAILED ({e.code}) for {c['path']}:{line} — retrying unpositioned. {e.read().decode()[:200]}")
            fallback = {"body": f"**`{c['path']}`" + (f" line {line}**" if line else "**") + "\n\n" + c["body"]}
            d = api(host, token, "POST", f"projects/{project}/merge_requests/{iid}/discussions", fallback)
            print(f"OK (unpositioned)  {c['path']}  discussion {d['id'][:8]}")

    if cfg.get("summary"):
        s = api(host, token, "POST", f"projects/{project}/merge_requests/{iid}/notes", {"body": cfg["summary"]})
        print(f"OK  summary note id {s['id']}")


main()
