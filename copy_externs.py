#!/usr/bin/env python3
"""Copy extern fn declarations from parent into a submodule.

Usage: copy_externs.py <dst.zig> <parent.zig> <name1> <name2> ...
Finds `extern fn <name>(...) ...;` in parent and inserts copies into dst.
Also imports any non-std types the signatures reference (if defined in parent).
"""
import re, sys

dst_path, parent_path, names = sys.argv[1], sys.argv[2], sys.argv[3:]
parent = open(parent_path).read().split("\n")
dst = open(dst_path).read().split("\n")

# find extern fn decls (may span lines; assume single-line here)
decls = {}
for i, l in enumerate(parent):
    m = re.match(r"^extern fn (" + "|".join(map(re.escape, names)) + r")\(.*;", l)
    if m:
        decls[m.group(1)] = l
print("found extern decls:", sorted(decls))
missing_names = [n for n in names if n not in decls]
if missing_names:
    print("NOT FOUND in parent:", missing_names)

# types referenced in the signatures (capitalized identifiers)
parent_decls = {}
for i, l in enumerate(parent):
    m = re.match(r"^(pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)", l)
    if m:
        parent_decls[m.group(2)] = i
have = set(re.findall(r"^const ([A-Za-z0-9_]+) =", "\n".join(dst), re.M))
imports = []
for name, decl in decls.items():
    for tok in re.findall(r"\b[A-Z][A-Za-z0-9_]*\b", decl):
        if tok in parent_decls and tok not in have and tok != "C":
            imports.append(tok)
            have.add(tok)
imports = sorted(set(imports))
print("type imports needed:", imports)

insert_at = 0
for i, l in enumerate(dst[:80]):
    if re.match(r"^const \w+ = @import\(", l):
        insert_at = i + 1
for tok in imports:
    dst.insert(insert_at, f'const {tok} = @import("../sa_std.zig").{tok};')
    insert_at += 1
for name in sorted(decls):
    dst.insert(insert_at, decls[name])
    insert_at += 1
open(dst_path, "w").write("\n".join(dst))
print("done")
