#!/usr/bin/env python3
"""Collapse 2+ consecutive blank lines into 1 (zig fmt behavior) and
strip leading/trailing blank lines in a file. Reports lines saved."""
import sys

path = sys.argv[1]
lines = open(path).read().split("\n")
out = []
prev_blank = False
for l in lines:
    if l.strip() == "":
        if prev_blank:
            continue
        prev_blank = True
        out.append(l)
    else:
        prev_blank = False
        out.append(l)
# strip leading/trailing blanks
while out and out[0].strip() == "":
    out.pop(0)
while out and out[-1].strip() == "":
    out.pop()
open(path, "w").write("\n".join(out) + "\n")
print(f"{path}: {len(lines)} -> {len(out)} lines (saved {len(lines)-len(out)})")
