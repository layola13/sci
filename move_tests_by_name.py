#!/usr/bin/env python3
"""Move test blocks whose names contain any of the given substrings.

Usage: move_tests_by_name.py <src.zig> <dst.zig> <substr1> [substr2 ...]
The dst file gets a `const std` header + the moved blocks + the parent's
import lines (copied, so fix_split can work from them).
"""
import re, sys

src_path, dst_path, substrs = sys.argv[1], sys.argv[2], sys.argv[3:]
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
        # END-OF-LINE depth check
        if started and depth == 0:
            return j
    return len(lines) - 1

targets = []
i = 0
while i < len(lines):
    m = re.match(r'^test "([^"]+)"', lines[i])
    if m and any(s in m.group(1) for s in substrs):
        end = find_end(i)
        targets.append((i, end, m.group(1)))
        i = end + 1
    else:
        i += 1
print(f"found {len(targets)} test blocks matching {substrs}")
moved = []
for start, end, name in sorted(targets, reverse=True):
    moved.append((start, lines[start:end + 1]))
    del lines[start:end + 1]
    print(f"  {name} ({end-start+1} lines)")
moved.sort(key=lambda x: x[0])
# copy the src's import lines to dst so fix_split has a base;
# if dst already exists, APPEND the blocks (never overwrite).
import os
if os.path.exists(dst_path):
    existing = open(dst_path).read()
    with open(dst_path, "w") as f:
        f.write(existing.rstrip() + "\n")
        for _, block in moved:
            f.write("\n" + "\n".join(block) + "\n")
else:
    imports = [l for l in lines[:80] if re.match(r"^const \w+ = @import\(", l)]
    with open(dst_path, "w") as f:
        f.write('const std = @import("std");\n')
        for imp in imports:
            if imp != 'const std = @import("std");':
                f.write(imp + "\n")
        for _, block in moved:
            f.write("\n" + "\n".join(block) + "\n")
open(src_path, "w").write("\n".join(lines))
print(f"{src_path} now {len(lines)} lines")
