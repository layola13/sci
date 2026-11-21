#!/usr/bin/env python3
"""Count comment/blank lines per 200-line block in a file."""
import sys

lines = open(sys.argv[1]).read().split("\n")
for start in range(0, len(lines), 200):
    blk = lines[start:start + 200]
    c = sum(1 for l in blk if l.strip().startswith("//"))
    b = sum(1 for l in blk if l.strip() == "")
    print(f"{start+1:5d}-{min(start+200, len(lines)):5d}: comments={c:3d} blanks={b:3d}")
