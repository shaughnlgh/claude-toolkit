#!/usr/bin/env python3
# Prints an execute-runner Workflow run's checkpoint from its journal. Usage: run-checkpoint.py <folder>... [--replay <out.js>], run folders oldest first.
# Exit 1: --replay refused. Exit 2: an unreadable journal or summary, or an entry missing a field read here. Exit 3: the newest run may still be live.
import argparse
import hashlib
import json
import os
import re
import sys

# execute-runner.js holds this exact line, and --replay replaces it in the copy.
REPLAY_LINE = "const REPLAY = null"
# The Workflow runtime records a child workflow's agents under the phase "▸ <child name>".
CHILD = "▸ "
# A stage that edits the tree. A run that died inside one left partial edits with no record, so it is not continued.
WRITER = re.compile(r"(implement:[0-9]+|fix:.+|doc:pass)\Z")


def fail(reason, code):
    print("refused: " + reason, file=sys.stderr)
    sys.exit(code)


def run_id(folder):
    return os.path.basename(os.path.normpath(folder))


def entries(folder):
    path = os.path.join(folder, "journal.jsonl")
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except (OSError, UnicodeDecodeError) as e:
        fail("cannot read %s: %s" % (path, e), 2)
    rows = []
    for n, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            e = json.loads(line)
        except ValueError:
            fail("%s line %d is not JSON" % (path, n), 2)
        need = {"started": ("agentId", "label", "phase"), "result": ("agentId", "result"), "failed": ("agentId",)}.get(e.get("type") if isinstance(e, dict) else None, ())
        if not isinstance(e, dict) or "type" not in e or any(k not in e for k in need) or any(not isinstance(e[k], str) for k in need if k != "result"):
            fail("%s line %d lacks a field this script reads" % (path, n), 2)
        rows.append(e)
    return rows


def summary_of(folder):
    # The runtime writes <session>/workflows/<runId>.json when a run ends.
    run = os.path.normpath(folder)
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(run))), "workflows", os.path.basename(run) + ".json")
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            summary = json.load(f)
    except (OSError, ValueError) as e:
        fail("cannot parse the run summary %s: %s" % (path, e), 2)
    if not isinstance(summary, dict):
        fail("the run summary %s is not a JSON object" % path, 2)
    return summary


def stages_of(folders):
    stages, count = [], {}
    for k, folder in enumerate(folders):
        rows = entries(folder)
        # A failed agent returned nothing and the run carried on, so the stage is done and replays as null.
        done = {e["agentId"]: e["result"] if e["type"] == "result" else None for e in rows if e["type"] in ("result", "failed")}
        for e in (e for e in rows if e["type"] == "started"):
            # An older run's open stage ran again in the run that continued it.
            if e["agentId"] not in done and k < len(folders) - 1:
                continue
            child = e["phase"].startswith(CHILD)
            count[child, e["label"]] = count.get((child, e["label"]), 0) + 1
            stages.append({"run": run_id(folder), "label": e["label"], "occurrence": count[child, e["label"]], "phase": e["phase"],
                           "state": "done" if e["agentId"] in done else "open", "child": child, "result": done.get(e["agentId"])})
    return stages


def is_capture(s):
    r = s["result"]
    return not s["child"] and isinstance(r, dict) and isinstance(r.get("diffPath"), str) and isinstance(r.get("paths"), list)


def replay_copy(folders, stages, dest):
    newest = summary_of(folders[-1])
    if newest is None or newest.get("status") == "running":
        fail("run %s has %s, so it may still be live" % (run_id(folders[-1]), "no summary" if newest is None else "status running"), 3)
    first = summary_of(folders[0]) or {}
    script, args = first.get("script"), first.get("args")
    if not isinstance(script, str) or script.split("\n").count(REPLAY_LINE) != 1 or not isinstance(args, dict):
        fail("the first run's summary holds no args or no script with the line %r once" % REPLAY_LINE, 1)
    writer = [s["label"] for s in stages if s["state"] == "open" and not s["child"] and WRITER.match(s["label"])]
    if writer:
        fail("the run died inside the writer stage %s, whose partial edits have no record" % writer[0], 1)
    done = [s for s in stages if s["state"] == "done"]
    index = [s["result"] for s in done if not s["child"] and s["label"] == "plan:index" and isinstance(s["result"], dict)]
    if not index:
        fail("no run recorded a plan:index result", 1)
    gone = [s["result"]["diffPath"] for s in done if is_capture(s) and not os.path.isfile(s["result"]["diffPath"])]
    if gone:
        fail("the recorded capture diff %s is gone" % gone[0], 1)
    rec = {"args": args, "index": index[-1], "runner": {}, "child": {}}
    for s in done:
        if s["child"] or s["label"] != "plan:index":
            rec["child" if s["child"] else "runner"].setdefault(s["label"], []).append(s["result"])
    lines = script.split("\n")
    lines[lines.index(REPLAY_LINE)] = "const REPLAY = " + json.dumps(rec, ensure_ascii=True)
    data = "\n".join(lines).encode("utf-8")
    os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(data)
    return {"path": dest, "sha256": hashlib.sha256(data).hexdigest()[:12],
            "runnerResults": sum(map(len, rec["runner"].values())), "childResults": sum(map(len, rec["child"].values()))}


def main():
    p = argparse.ArgumentParser(prog="run-checkpoint.py")
    p.add_argument("folders", nargs="+")
    p.add_argument("--replay")
    opts = p.parse_args()
    stages = stages_of(opts.folders)
    runs = [{"run": run_id(f), "status": (summary_of(f) or {}).get("status")} for f in opts.folders]
    changed = []
    for s in stages:
        r = s["result"]
        if s["state"] == "done" and not s["child"] and isinstance(r, dict) and isinstance(r.get("changedPaths"), list):
            changed += [x for x in r["changedPaths"] if x not in changed]
    captures = [s for s in stages if s["state"] == "done" and is_capture(s)]
    capture = {"label": captures[-1]["label"], "hash12": captures[-1]["result"].get("hash12"), "paths": captures[-1]["result"]["paths"]} if captures else None
    replay = replay_copy(opts.folders, stages, opts.replay) if opts.replay else None
    out = {"runs": runs, "done": sum(s["state"] == "done" for s in stages), "open": [s["label"] for s in stages if s["state"] == "open"],
           "stages": [{k: s[k] for k in ("run", "label", "occurrence", "phase", "state")} for s in stages],
           "changedPaths": changed, "capture": capture, "replay": replay}
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
