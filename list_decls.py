#!/usr/bin/env python3
"""List all top-level decl names matching a substring (case-insensitive)."""
import re, sys

path, substr = sys.argv[1], sys.argv[2].lower()
names = set()
for l in open(path).read().split("\n"):
    m = re.match(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)", l)
    if m and substr in m.group(1).lower():
        names.add(m.group(1))
print(" ".join(sorted(names)))
