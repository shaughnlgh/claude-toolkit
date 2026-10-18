#!/usr/bin/env python3
"""Read-only validator for the canonical plan-note contract (plan-workflow skill).

Usage: validate-plan.py <path to "plan - <slug>.md">

Exit codes:
  0  valid
  1  contract violation(s) — each printed as "VIOLATION: ..."
  2  usage error, unreadable path, or malformed/unsupported frontmatter

Never writes. No network, no vault config, no third-party packages.

Parser scope (deliberate, documented): this is NOT a YAML parser. It parses
exactly the frontmatter subset the plan-workflow skill and Mission Control
scaffolds produce — top-level "key: value" scalars, bare "key:" (blank), lists
of scalars ("- item"), and lists of flat dicts ("- k: v" with indented "k: v"
continuations, one level deep). Anything else (block scalars, flow style on
structured keys, deeper nesting, tab indentation) is rejected with exit 2
rather than silently misparsed.
"""
import os
import re
import sys

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
FILENAME_RE = re.compile(r"^plan - (.+)\.md$")
KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(.*)$")
ITEM_KEY_RE = re.compile(r"^- (?:([A-Za-z_][A-Za-z0-9_-]*):(.*))?$")

# Contract, from plan-workflow SKILL.md (Required plan frontmatter / status lifecycle
# / Required plan sections). All 18 keys must be PRESENT; `modules` and `repos`
# are validly BLANK for single-repo plans ("leave blank", not "leave out").
REQUIRED_KEYS = [
    "type", "date", "created", "updated", "project", "repo", "plan", "status",
    "approved", "tool", "branch", "ticket", "mr", "modules", "repos",
    "sessions", "tags", "related_topics",
]
STATUSES = {"planning", "review", "approved", "in-progress", "completed",
            "blocked", "abandoned"}
REQUIRED_HEADINGS = [
    "Objective", "Current Context", "Assumptions", "Affected Files",
    "Implementation Steps", "Validation Steps", "Risks", "Rollback Notes",
    "Open Questions", "Plan Changes During Execution", "Related Topics",
    "Linked Artifacts",
]
# "Plain Language Summary" (immediately after Objective) joined the contract on
# 2026-08-26. It is checked separately, gated on frontmatter `created`, so plans
# written before the convention existed are not retroactively broken. A plan with
# no parseable `created` (e.g. a same-day skeleton mid-scaffold) is NOT grandfathered.
PLAIN_LANGUAGE_SUMMARY_HEADING = "Plain Language Summary"
PLAIN_LANGUAGE_SUMMARY_SINCE = "2026-08-26"
# The completed-plan Remember: line rule is gated on `created` the same way, from the
# date the remember pass joined the workflow.
REMEMBER_LINE_SINCE = "2026-10-18"
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
REMEMBER_LINE_RE = re.compile(r"^[ \t]*(?:- )?Remember:", re.M)
# Keys whose structure the validator actually checks. Anything else is unknown
# metadata (Mission Control adds e.g. worklogs, tracking, mockups): its indented
# block is consumed opaquely and tolerated, however it is shaped.
VALIDATED_KEYS = set(REQUIRED_KEYS) | {"parent"}


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def parse_frontmatter(lines):
    """Parse the narrow subset. Returns dict: key -> scalar str | list.
    List entries are str (scalar item) or dict (flat mapping)."""
    data = {}
    i, n = 0, len(lines)
    while i < n:
        raw = lines[i]
        if raw.strip() == "":
            i += 1
            continue
        if raw[0] in " \t":
            die(f"frontmatter line {i + 1}: unexpected indentation outside a list block")
        if "\t" in raw:
            die(f"frontmatter line {i + 1}: tab indentation is not supported")
        m = KEY_RE.match(raw)
        if not m:
            die(f"frontmatter line {i + 1}: not a 'key: value' line: {raw[:60]!r}")
        key, val = m.group(1), m.group(2).strip()
        if key not in VALIDATED_KEYS:
            # Unknown metadata: consume its indented block opaquely, tolerate any shape.
            j = i + 1
            while j < n and (lines[j].strip() == "" or lines[j][0] in " \t"):
                j += 1
            data[key] = unquote(val) if val and not val.startswith(("|", ">")) else "<opaque>"
            i = j
            continue
        if val.startswith(("|", ">")):
            die(f"frontmatter line {i + 1}: block scalars are not supported ('{key}')")
        if val != "":
            data[key] = unquote(val)
            i += 1
            continue
        # bare "key:" — blank scalar, or a following indented list block
        items, j = [], i + 1
        item_indent = None
        while j < n:
            ln = lines[j]
            if ln.strip() == "":
                j += 1
                continue
            indent = len(ln) - len(ln.lstrip(" "))
            if "\t" in ln[:indent + 1]:
                die(f"frontmatter line {j + 1}: tab indentation is not supported")
            if indent == 0:
                break
            stripped = ln.strip()
            if stripped.startswith("- "):
                if item_indent is None:
                    item_indent = indent
                if indent != item_indent:
                    die(f"frontmatter line {j + 1}: nested lists are not supported ('{key}')")
                im = ITEM_KEY_RE.match(stripped)
                if im and im.group(1):
                    v = im.group(2).strip()
                    if v.startswith(("|", ">")):
                        die(f"frontmatter line {j + 1}: block scalars are not supported ('{key}')")
                    items.append({im.group(1): unquote(v)})
                else:
                    items.append(unquote(stripped[2:]))
                j += 1
                continue
            # continuation "k: v" line belonging to the last dict item
            cm = KEY_RE.match(stripped)
            if cm and items and isinstance(items[-1], dict):
                if item_indent is not None and indent <= item_indent:
                    die(f"frontmatter line {j + 1}: unsupported structure under '{key}'")
                v = cm.group(2).strip()
                if v.startswith(("|", ">")):
                    die(f"frontmatter line {j + 1}: block scalars are not supported ('{key}')")
                items[-1][cm.group(1)] = unquote(v)
                j += 1
                continue
            die(f"frontmatter line {j + 1}: unsupported structure under '{key}': {stripped[:60]!r}")
        data[key] = items if items else ""
        i = j
    return data


def strip_fences(body):
    """Drop fenced code blocks with a small stateful scan (not a regex), so example
    headings inside a fence don't satisfy the required-section check. A fence opens on
    a line that is only ``` or ~~~ (3+, optionally indented, optional info string) and
    closes on a later line of the SAME fence char that is at least as long, with nothing
    but the fence. An unclosed fence consumes the rest of the body. Not a Markdown parser
    beyond this."""
    out, fence_char, fence_len = [], None, 0
    for line in body.split("\n"):
        m = re.match(r"^[ \t]*(`{3,}|~{3,})[ \t]*(\S*)[ \t]*$", line)
        if m:
            ch, ln = m.group(1)[0], len(m.group(1))
            if fence_char is None:
                fence_char, fence_len = ch, ln  # open (drop this line)
                continue
            if ch == fence_char and ln >= fence_len and m.group(2) == "":
                fence_char = None  # close (drop this line)
                continue
            # a fence-looking line inside a different/nonclosing fence: it's content, drop
            continue
        if fence_char is None:
            out.append(line)
    return "\n".join(out)


def section(body, heading):
    """Text of the `## <heading>` section up to the next `## ` heading, or None."""
    m = re.search(rf"^##\s+{re.escape(heading)}\s*$\n(.*?)(?=^##\s|\Z)", body, re.M | re.S)
    return m.group(1) if m else None


def main():
    if len(sys.argv) != 2:
        print("usage: validate-plan.py <path to 'plan - <slug>.md'>", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    if not os.path.isfile(path):
        die(f"not an existing regular file: {path}")
    if not path.endswith(".md"):
        die(f"not a Markdown file: {path}")
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        die(f"cannot read {path}: {e}")

    fm_match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not fm_match:
        die("no frontmatter block found (expected '---' ... '---' at the top)")
    fm = parse_frontmatter(fm_match.group(1).split("\n"))
    body = text[fm_match.end():]

    violations = []
    basename = os.path.basename(path)
    dirname = os.path.basename(os.path.dirname(os.path.abspath(path)))

    # -- file and identity --
    fmatch = FILENAME_RE.match(basename)
    if not fmatch:
        violations.append(f"filename must match 'plan - <slug>.md', got {basename!r}")
        slug = None
    else:
        slug = fmatch.group(1)
        if not SLUG_RE.match(slug):
            violations.append(f"slug {slug!r} must match ^[a-z0-9][a-z0-9-]*$")
        plan_key = fm.get("plan")
        if isinstance(plan_key, str) and plan_key and plan_key != slug:
            violations.append(f"frontmatter plan: {plan_key!r} does not match filename slug {slug!r}")
    if fm.get("type") != "plan":
        violations.append(f"type: must be 'plan', got {fm.get('type')!r}")

    # -- required keys (unknown extras are tolerated by design) --
    for k in REQUIRED_KEYS:
        if k not in fm:
            violations.append(f"missing required frontmatter key: {k}")

    # -- status enum --
    status = fm.get("status")
    if "status" in fm:
        if not isinstance(status, str):
            violations.append("status: must be a single lifecycle value, not a list")
        elif status == "":
            violations.append("status: must not be blank")
        elif status not in STATUSES:
            violations.append(
                f"status {status!r} is not a lifecycle value ({', '.join(sorted(STATUSES))})")

    # -- parent/child directory relationship (only when parent: is present) --
    parent = fm.get("parent")
    if isinstance(parent, str) and parent:
        if not (dirname == parent or dirname.endswith("-" + parent)):
            violations.append(
                f"parent: {parent!r} does not match the plan directory suffix ({dirname!r})")
        else:
            parent_note = os.path.join(os.path.dirname(os.path.abspath(path)),
                                       f"plan - {parent}.md")
            if not os.path.isfile(parent_note):
                violations.append(f"parent plan note not found beside this one: plan - {parent}.md")

    # -- sessions --
    sessions = fm.get("sessions")
    if isinstance(sessions, list):
        seen_ids = set()
        for idx, entry in enumerate(sessions, 1):
            if not isinstance(entry, dict):
                violations.append(f"sessions entry {idx} is not a date/summary mapping")
                continue
            if not entry.get("date"):
                violations.append(f"sessions entry {idx}: missing date")
            if not entry.get("summary"):
                violations.append(f"sessions entry {idx}: missing summary")
            sid = entry.get("id", "")
            if sid:  # blank ids are fine and never duplicates
                if sid in seen_ids:
                    violations.append(f"sessions entry {idx}: duplicate session id {sid!r}")
                seen_ids.add(sid)

    # -- modules / repos (validated only when present) --
    modules = fm.get("modules")
    if isinstance(modules, list):
        for idx, entry in enumerate(modules, 1):
            if not isinstance(entry, dict) or not entry.get("name"):
                violations.append(f"modules entry {idx}: missing name")
    repos = fm.get("repos")
    if isinstance(repos, list):
        for idx, entry in enumerate(repos, 1):
            if not isinstance(entry, dict) or not entry.get("repo"):
                violations.append(f"repos entry {idx}: missing repo")

    # -- required headings (presence only; prose quality is out of scope) --
    # Fenced code blocks are removed first (stateful scan) so example headings inside a
    # fence don't satisfy the real-section check.
    body_nocode = strip_fences(body)
    for h in REQUIRED_HEADINGS:
        if not re.search(rf"^##\s+{re.escape(h)}\s*$", body_nocode, re.M):
            violations.append(f"missing required heading: ## {h}")

    # -- Plain Language Summary (gated on `created`; see PLAIN_LANGUAGE_SUMMARY_SINCE) --
    created = fm.get("created")
    created_date = created if isinstance(created, str) and DATE_RE.match(created) else None
    grandfathered = created_date is not None and created_date < PLAIN_LANGUAGE_SUMMARY_SINCE
    if not grandfathered:
        if not re.search(rf"^##\s+{re.escape(PLAIN_LANGUAGE_SUMMARY_HEADING)}\s*$", body_nocode, re.M):
            violations.append(f"missing required heading: ## {PLAIN_LANGUAGE_SUMMARY_HEADING}")

    # -- completed plans carry the remember pass's record (gated on `created`; see
    # REMEMBER_LINE_SINCE) --
    remember_exempt = created_date is not None and created_date < REMEMBER_LINE_SINCE
    if status == "completed" and not remember_exempt:
        changes = section(body_nocode, "Plan Changes During Execution") or ""
        if not REMEMBER_LINE_RE.search(changes):
            violations.append("status completed requires a Remember: line under "
                              "## Plan Changes During Execution (remember pass not recorded)")

    # -- retired artifacts -- (tolerate whitespace; require a link-close/alias/space
    # boundary so a distinct artifact like `mr-description-notes` is not caught).
    if re.search(r"\[\[\s*mr-description(\s|\]|\|)", body):
        violations.append("links the retired mr-description artifact (removed from the contract)")

    if violations:
        for v in violations:
            print(f"VIOLATION: {v}")
        sys.exit(1)
    print(f"OK: {basename}")
    sys.exit(0)


if __name__ == "__main__":
    main()
