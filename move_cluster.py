#!/usr/bin/env python3
"""Move one cluster (by index) from the dump_clusters.py output file.

Usage: move_cluster.py <src.zig> <dst.zig> <clusters.txt> <index>
  index: 0-based component index in the clusters file (sorted by size desc).
"""
import re, sys

src_path, dst_path, clusters_path, idx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
blocks = open(clusters_path).read().strip().split("\n\n")
header, names_line = blocks[idx].split("\n")
members = set(names_line.split())
print(f"cluster {idx}: {header} -> {len(members)} members")

# reuse move_prefixes logic by importing it as a script is awkward;
# implement inline with the same strip_code/find_end.
lines = open(src_path).read().split("\n")

def strip_code(line):
    out = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break
        if c == '"':
            i += 1
            while i < n and line[i] != '"':
                if line[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        if c == "'":
            i += 1
            while i < n and line[i] != "'":
                if line[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)

def find_end(s):
    first = strip_code(lines[s])
    if "{" not in first and first.rstrip().endswith(";"):
        return s
    depth = 0
    started = False
    for j in range(s, len(lines)):
        code = strip_code(lines[j])
        for ch in code:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
        # END-OF-LINE depth check: a `}` mid-line (e.g. closing an anonymous
        # struct in a fn return type) must not end the decl.
        if started and depth == 0:
            return j
    return len(lines) - 1

import os
rel_dst = os.path.relpath(dst_path, os.path.dirname(src_path))
decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")
targets = []
for i, l in enumerate(lines):
    if "@import(" in l:
        continue
    m = decl_re.match(l)
    if m and m.group(1) in members:
        targets.append((i, m.group(1)))
targets.sort(reverse=True)
print(f"found {len(targets)} of {len(members)} members in src")
missing = members - set(n for _, n in targets)
if missing:
    print("NOT FOUND in src:", sorted(missing))
moved = []
for start, name in targets:
    end = find_end(start)
    block = lines[start:end + 1]
    moved.append((start, name, block))
    lines[start:end + 1] = [f"pub const {name} = @import(\"{rel_dst}\").{name};"]
    print(f"  {name}: lines {start+1}..{end+1} ({end-start+1} lines)")
moved.sort(key=lambda x: x[0])
with open(dst_path, "w") as f:
    f.write('const std = @import("std");\n')
    for _, _, block in moved:
        f.write("\n" + "\n".join(block) + "\n")
open(src_path, "w").write("\n".join(lines))
print(f"{src_path} now {len(lines)} lines")
