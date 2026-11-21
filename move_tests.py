#!/usr/bin/env python3
"""Move all top-level `test "..." { ... }` blocks from a file to a dst file.

Usage: move_tests.py <src.zig> <dst.zig>
The src file gets the blocks removed (no alias needed for tests).
The dst file gets a `const std = @import("std");` header plus the blocks.
"""
import re, sys

src_path, dst_path = sys.argv[1], sys.argv[2]
lines = open(src_path).read().split("\n")

def strip_code(line):
    """Remove // comment, string literals and char literals from a line."""
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


def find_end(s, ls):
    depth = 0
    started = False
    for j in range(s, len(ls)):
        code = strip_code(ls[j])
        for ch in code:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return j
    return len(ls) - 1

targets = []
i = 0
while i < len(lines):
    if re.match(r"^test ", lines[i]):
        end = find_end(i, lines)
        targets.append((i, end))
        i = end + 1
    else:
        i += 1
print(f"found {len(targets)} test blocks")
moved = []
for start, end in sorted(targets, reverse=True):
    moved.append((start, lines[start:end + 1]))
    del lines[start:end + 1]
moved.sort(key=lambda x: x[0])
total = sum(len(b) for _, b in moved)
with open(dst_path, "w") as f:
    f.write('const std = @import("std");\n')
    for _, block in moved:
        f.write("\n" + "\n".join(block) + "\n")
open(src_path, "w").write("\n".join(lines))
print(f"moved {total} lines; {src_path} now {len(lines)} lines")
