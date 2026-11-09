#!/usr/bin/env python3
# Prints one JSON index of a plan note for execute-runner.js. Usage: plan-index.py <path>.
import hashlib
import json
import re
import sys

# JavaScript's \s and String.prototype.trim whitespace set, not Python's, because the execute-runner harness cases pin splits on this set.
WS = "\t\n\x0b\x0c\r \xa0\u1680" + "".join(map(chr, range(0x2000, 0x200b))) + "\u2028\u2029\u202f\u205f\u3000\ufeff"
S = "[" + WS + "]"
FENCE = re.compile(r"[ \t]*(`{3,}|~{3,})[ \t]*([^" + WS + r"]*)[ \t]*\Z")
SECTION_HEADING = re.compile("##" + S)
SUBHEADING = re.compile("###" + S)
STEP_HEADING = re.compile("###" + S + "+[0-9]+[.)]")
NUMBERED = re.compile("[0-9]+[.)]" + S)
# [e2e] after the step number on a Validation Step's own heading line marks it end-to-end.
E2E_MARK = re.compile("(?:[0-9]+[.)]" + S + r"+)?\[e2e\]")
# [shots] directly after [e2e] marks an end-to-end step whose screenshots go to the evidence note.
SHOTS_MARK = re.compile("(?:[0-9]+[.)]" + S + r"+)?\[e2e\]" + S + r"*\[shots\]")
STEP_SECTIONS = (("Implementation Steps", "implementationSteps"), ("Validation Steps", "validationSteps"))
HEADING_MAX = 120


def trim(s):
    return s.strip(WS)


def blank(line):
    return not trim(line)


# Same fence rule as validate-plan.py strip_fences: 3+ backticks or tildes, closed only by the same char at least as long with no info string.
def outside_fence(lines):
    out, opened = [], None
    for line in lines:
        m = FENCE.match(line)
        if not m:
            out.append(opened is None)
            continue
        if opened is None:
            opened = m.group(1)
        elif m.group(1)[0] == opened[0] and len(m.group(1)) >= len(opened) and not m.group(2):
            opened = None
        out.append(False)
    return out


def number_of(line):
    return int(re.match("[0-9]+", line).group())


# The step rule docs/workflows.md states, on a trimmed section's lines -> [(heading, marker line)], 0-based, the first line when no marker splits it.
def items(lines):
    outside = outside_fence(lines)
    at = lambda rx: [i for i, line in enumerate(lines) if outside[i] and rx.match(line)]
    heads, nums = at(SUBHEADING), at(NUMBERED)
    before = lambda i: sum(1 for h in heads if h < i)
    one_list = bool(nums) and all(number_of(lines[i]) == k + 1 for k, i in enumerate(nums))
    crosses = one_list and before(nums[0]) != before(nums[-1])
    by_heading = len(heads) > 1 and all(i > heads[0] for i in nums) and not crosses
    rising = [i for k, i in enumerate(nums) if all(number_of(lines[j]) < number_of(lines[i]) for j in nums[:k])]
    starts = at(STEP_HEADING) or (heads if by_heading else rising)
    if not starts:
        return [(re.sub(r"\.\Z", "", trim(lines[0])), 0)]
    return [(re.sub("^###" + S + "+", "", trim(lines[s]), count=1), s) for s in starts]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: plan-index.py <plan note path>")
    raw = open(sys.argv[1], "rb").read()
    try:
        lines = raw.decode("utf-8").split("\n")
    except UnicodeDecodeError as e:
        sys.exit(f"plan-index: {sys.argv[1]} is not UTF-8: {e.reason} at byte {e.start}")
    outside = outside_fence(lines)
    # Every unfenced ## heading, so the runner ends each section at the next one.
    heads = [(i, trim(line[2:])) for i, line in enumerate(lines) if outside[i] and SECTION_HEADING.match(line)]
    index = {"sha256": hashlib.sha256(raw).hexdigest(), "sections": [{"name": name, "line": i + 1} for i, name in heads],
             "implementationSteps": [], "validationSteps": []}
    for name, key in STEP_SECTIONS:
        k = next((k for k, (_, n) in enumerate(heads) if n == name), None)
        if k is None:
            continue
        end = heads[k + 1][0] if k + 1 < len(heads) else len(lines)
        body = [i for i in range(heads[k][0] + 1, end) if not blank(lines[i])]
        if not body:
            continue
        for heading, at in items(trim("\n".join(lines[body[0]:body[-1] + 1])).split("\n")):
            step = {"heading": heading[:HEADING_MAX], "line": body[0] + at + 1}
            if key == "validationSteps":
                step["e2e"] = bool(E2E_MARK.match(heading))
                step["shots"] = bool(SHOTS_MARK.match(heading))
            index[key].append(step)
    print(json.dumps(index, ensure_ascii=False))


if __name__ == "__main__":
    main()
