#!/usr/bin/env python3
"""Show top-level decl groups (excluding alias lines) in a Zig file."""
import re, sys
from collections import Counter

path = sys.argv[1]
lines = open(path).read().split("\n")
c = Counter()
for l in lines:
    m = re.match(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)", l)
    if m:
        name = m.group(1)
        if "@import(" in l:
            continue
        parts = name.split("_")
        key = "_".join(parts[:2]) if len(parts) > 1 else name
        c[key] += 1
for k, v in c.most_common(30):
    print(f"{v:4d} {k}")
print("alias lines:", sum(1 for l in lines if re.match(r"^pub const sa_\w+ = @import\(", l)))
print("total lines:", len(lines))
