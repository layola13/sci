#!/usr/bin/env python3
"""Make pub, in a submodule, every top-level decl that the parent file
still uses (outside alias lines). Usage: make_used_pub.py <dst.zig> <parent.zig>
Skips `std` and other import lines.
"""
import re, sys

dst_path, parent_path = sys.argv[1], sys.argv[2]
dst = open(dst_path).read()
parent = open(parent_path).read()
defs = set(re.findall(r"^(?:pub\s+)?fn ([A-Za-z0-9_]+)\s*\(", dst, re.M))
defs |= set(re.findall(r"^(?:pub\s+)?const ([A-Za-z0-9_]+)\s*(?:=|:)", dst, re.M))
defs |= set(re.findall(r"^(?:pub\s+)?var ([A-Za-z0-9_]+)\s*(?:=|:)", dst, re.M))
defs -= {"std"}
used = set()
for name in defs:
    for l in parent.split("\n"):
        if "@import(" in l:
            continue
        if re.search(r"\b" + re.escape(name) + r"\b", l):
            used.add(name)
            break
lines = dst.split("\n")
n = 0
for i, l in enumerate(lines):
    for kind in ("fn", "const", "var"):
        m = re.match(rf"^{kind} ([A-Za-z0-9_]+)\s*(?:\(|=|:)", l)
        if m and m.group(1) in used:
            lines[i] = "pub " + l
            n += 1
            break
    # struct/enum/union type decls
    m = re.match(r"^const ([A-Z][A-Za-z0-9_]*) = (?:struct|enum|union)", l)
    if m and m.group(1) in used:
        lines[i] = "pub " + l
        n += 1
open(dst_path, "w").write("\n".join(lines))
print(f"made pub in {dst_path}: {sorted(used)} ({n} lines)")
