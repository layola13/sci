#!/usr/bin/env python3
"""List import lines in a file whose imported name is never used in the body.
Usage: unused_imports2.py <file.zig> [--delete]
"""
import re, sys

path = sys.argv[1]
delete = "--delete" in sys.argv
lines = open(path).read().split("\n")
imports = {}
for i, l in enumerate(lines):
    m = re.match(r"^const ([A-Za-z0-9_]+) = @import\(", l)
    if m:
        imports[m.group(1)] = i
    m = re.match(r"^pub const ([A-Za-z0-9_]+) = @import\(", l)
    if m:
        imports[m.group(1)] = i
body = "\n".join(lines)
unused = []
for name, i in imports.items():
    # count uses outside the import line itself
    uses = len(re.findall(r"\b" + re.escape(name) + r"\b", body))
    if uses <= 1:
        unused.append((i, name))
print(f"imports: {len(imports)}, unused: {len(unused)}")
for i, name in unused:
    print(f"  line {i+1}: {name}")
if delete and unused:
    drop = set(i for i, _ in unused)
    lines = [l for j, l in enumerate(lines) if j not in drop]
    open(path, "w").write("\n".join(lines))
    print(f"deleted {len(unused)} unused imports; file now {len(lines)} lines")
