#!/usr/bin/env python3
"""List real top-level decls in a file (skipping alias/import lines)."""
import re, sys

path = sys.argv[1]
lines = open(path).read().split("\n")
decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:threadlocal\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")
for i, l in enumerate(lines):
    if "@import(" in l:
        continue
    m = decl_re.match(l)
    if m:
        print(f"{i+1}: {m.group(1)}")
