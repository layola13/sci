#!/usr/bin/env python3
"""Make pub every top-level decl in parent that dst uses but that is not pub.

Usage: pub_all_used.py <dst.zig> <parent.zig>
Covers const/fn/var/extern decls. Prints what it changed.
"""
import re, sys

dst_path, parent_path = sys.argv[1], sys.argv[2]
dst = open(dst_path).read()
parent_lines = open(parent_path).read().split("\n")

decl_re = re.compile(r"^(pub\s+)?(?:export\s+)?(?:extern\s+)?(?:\"c\"\s+)?(const|fn|var)\s+([A-Za-z0-9_]+)")
parent_decls = {}
for i, l in enumerate(parent_lines):
    m = decl_re.match(l)
    if m:
        parent_decls[m.group(3)] = (i, bool(m.group(1)))

idents = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", dst))
# also names accessed via sa_std.<name>
idents |= set(re.findall(r"sa_std\.([A-Za-z0-9_]+)", dst))
need = sorted(n for n in idents if n in parent_decls and not parent_decls[n][1])
print("need pub:", len(need))
for name in need:
    i, _ = parent_decls[name]
    parent_lines[i] = "pub " + parent_lines[i]
    print("  pub", name, "line", i + 1)
open(parent_path, "w").write("\n".join(parent_lines))
print("done")
