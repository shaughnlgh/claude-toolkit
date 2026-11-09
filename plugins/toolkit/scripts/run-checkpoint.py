#!/usr/bin/env python3
# Prints an execute-runner Workflow run's checkpoint from its journal. Usage: run-checkpoint.py [--replay <out.js> --plan <planName> --repo-root <path>] -- <folder>..., absolute run folders oldest first.
# Exit 1: --replay refused, or a folder that is not <slug>/<session id>/subagents/workflows/<runId> under ~/.claude/projects. Exit 2: --replay without --plan and --repo-root, an unreadable journal or summary, a non-JSON line before the last, or an entry missing a field read here. Exit 3: the newest run may still be live.
import argparse
import datetime
import hashlib
import json
import os
import re
import sys

# execute-runner.js holds this exact line, and --replay replaces it in the copy.
REPLAY_LINE = "const REPLAY = null"
# The Workflow runtime records a child workflow's agents under the phase "▸ <child name>".
CHILD = "▸ "
# Every journal line begins {"type":, so a torn line with this prefix lost only part of a result whose started entry is intact.
TORN_RESULT = '{"type":"result"'
# A stage that edits the tree. A run that died inside one left partial edits with no record, so it is not continued.
# These labels never change once a runner with a REPLAY line has shipped: a renamed writer stage keeps its old label here.
WRITER = re.compile(r"(implement:[0-9]+|fix:.+|doc:pass)\Z")


def fail(reason, code):
    print("refused: " + reason, file=sys.stderr)
    sys.exit(code)


def run_id(folder):
    return os.path.basename(os.path.normpath(folder))


def checked(folder):
    if not folder.startswith("/"):
        fail("%s is not an absolute run folder path" % folder, 1)
    root = os.path.realpath(os.path.expanduser("~/.claude/projects"))
    real = os.path.realpath(folder)
    parts = os.path.relpath(real, root).split(os.sep)
    if len(parts) != 5 or parts[2:4] != ["subagents", "workflows"] or any(x in ("", ".", "..") for x in parts):
        fail("%s is not a run folder <slug>/<session id>/subagents/workflows/<runId> under %s" % (folder, root), 1)
    return real


def entries(folder):
    path = os.path.join(folder, "journal.jsonl")
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except (OSError, UnicodeDecodeError) as e:
        fail("cannot read %s: %s" % (path, e), 2)
    last = max((n for n, line in enumerate(lines, 1) if line.strip()), default=0)
    rows, torn = [], None
    for n, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            e = json.loads(line)
        except ValueError:
            # A session that died mid-write leaves a torn last line, whose stage stays open.
            if n == last:
                torn = line
                break
            fail("%s line %d is not JSON" % (path, n), 2)
        need = {"started": ("agentId", "label", "phase"), "result": ("agentId", "result"), "failed": ("agentId",)}.get(e.get("type") if isinstance(e, dict) else None, ())
        if not isinstance(e, dict) or "type" not in e or any(k not in e for k in need) or any(not isinstance(e[k], str) for k in need if k != "result"):
            fail("%s line %d lacks a field this script reads" % (path, n), 2)
        rows.append(e)
    return rows, torn


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
    stages, count, torn = [], {}, []
    for k, folder in enumerate(folders):
        rows, cut = entries(folder)
        if cut is not None and not cut.startswith(TORN_RESULT):
            torn.append(run_id(folder))
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
    return stages, torn


def is_capture(s):
    r = s["result"]
    return not s["child"] and isinstance(r, dict) and isinstance(r.get("diffPath"), str) and isinstance(r.get("paths"), list)


def ended_at(summary):
    try:
        return datetime.datetime.fromisoformat(summary["timestamp"].replace("Z", "+00:00")).timestamp()
    except (KeyError, AttributeError, TypeError, ValueError):
        return None


def live_reason(folder):
    newest = summary_of(folder)
    if newest is None:
        return "no summary"
    if newest.get("status") == "running":
        return "status running"
    end = ended_at(newest)
    if end is None:
        return "a summary with no timestamp"
    # A live resume writes behind the old summary. The 1 s margin covers a timestamp cut to the millisecond.
    if os.path.getmtime(os.path.join(folder, "journal.jsonl")) > end + 1:
        return "a journal written after its summary's timestamp"
    return None


def recorded_args(summary):
    # A continuation launches with scratchDir alone, so its plan args sit in its script's REPLAY record.
    script = summary.get("script")
    for line in script.split("\n") if isinstance(script, str) else ():
        if line.startswith("const REPLAY = ") and line != REPLAY_LINE:
            try:
                rec = json.loads(line[len("const REPLAY = "):])
            except ValueError:
                return None
            return rec.get("args") if isinstance(rec, dict) else None
    return summary.get("args")


def replay_copy(folders, stages, torn, dest, plan, repo_root):
    live = live_reason(folders[-1])
    if live:
        fail("run %s has %s, so it may still be live" % (run_id(folders[-1]), live), 3)
    first = summary_of(folders[0]) or {}
    script, args = first.get("script"), first.get("args")
    if not isinstance(script, str) or script.split("\n").count(REPLAY_LINE) != 1 or not isinstance(args, dict):
        fail("the first run's summary holds no args or no script with the line %r once" % REPLAY_LINE, 1)
    for folder in folders:
        own = recorded_args(summary_of(folder) or {})
        if not isinstance(own, dict):
            fail("run %s has no recorded args" % run_id(folder), 1)
        if own.get("planName") != plan:
            fail("run %s recorded planName %r, not %r" % (run_id(folder), own.get("planName"), plan), 1)
        if not isinstance(own.get("repoRoot"), str) or os.path.realpath(own["repoRoot"]) != os.path.realpath(repo_root):
            fail("run %s recorded repoRoot %r, not %r" % (run_id(folder), own.get("repoRoot"), repo_root), 1)
    root = args.get("pluginRoot")
    if not isinstance(root, str) or not os.path.isfile(os.path.join(root, "scripts", "vault-fs.sh")):
        fail("the recorded pluginRoot %r or its scripts/vault-fs.sh is gone" % root, 1)
    if torn:
        fail("the journal of run %s ends in a torn line that is not a result, which may hide an open writer stage" % torn[0], 1)
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
    p.add_argument("--plan")
    p.add_argument("--repo-root")
    opts = p.parse_args()
    if opts.replay and (opts.plan is None or opts.repo_root is None):
        p.error("--replay needs --plan and --repo-root")
    opts.folders = [checked(f) for f in opts.folders]
    stages, torn = stages_of(opts.folders)
    runs = [{"run": run_id(f), "status": (summary_of(f) or {}).get("status")} for f in opts.folders]
    changed = []
    for s in stages:
        r = s["result"]
        if s["state"] == "done" and not s["child"] and isinstance(r, dict) and isinstance(r.get("changedPaths"), list):
            changed += [x for x in r["changedPaths"] if x not in changed]
    captures = [s for s in stages if s["state"] == "done" and is_capture(s)]
    capture = {"label": captures[-1]["label"], "hash12": captures[-1]["result"].get("hash12"), "paths": captures[-1]["result"]["paths"]} if captures else None
    replay = replay_copy(opts.folders, stages, torn, opts.replay, opts.plan, opts.repo_root) if opts.replay else None
    out = {"runs": runs, "done": sum(s["state"] == "done" for s in stages), "open": [s["label"] for s in stages if s["state"] == "open"],
           "stages": [{k: s[k] for k in ("run", "label", "occurrence", "phase", "state")} for s in stages],
           "changedPaths": changed, "capture": capture, "replay": replay}
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
