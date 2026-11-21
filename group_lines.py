#!/usr/bin/env python3
"""Count lines per name-prefix group in a .zig file."""
import re, sys
from collections import defaultdict

path = sys.argv[1]
lines = open(path).read().split("\n")
decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var|test)\s+([A-Za-z0-9_\"]+)")
starts = []
for i, l in enumerate(lines):
    m = decl_re.match(l)
    if m:
        starts.append((i, m.group(1).strip('"')))

def find_end(s):
    depth = 0
    started = False
    for j in range(s, len(lines)):
        code = lines[j].split("//")[0]
        for ch in code:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return j
        if started and depth == 0:
            return j
    return len(lines) - 1

def group_of(name):
    m = re.match(r"^sa_([a-z]+)", name)
    return ("sa_" + m.group(1)) if m else "other"

glines = defaultdict(int)
gcount = defaultdict(int)
for s, name in starts:
    e = find_end(s)
    g = group_of(name)
    glines[g] += e - s + 1
    gcount[g] += 1
for g in sorted(glines, key=lambda x: -glines[x]):
    print(f"{g}: {gcount[g]} decls, {glines[g]} lines")
print("total decl lines:", sum(glines.values()), "file lines:", len(lines))
