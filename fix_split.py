#!/usr/bin/env python3
"""Fix a split submodule's missing identifiers by importing them from the
parent file, making the parent's decls pub as needed.
Usage: fix_split.py <dst.zig> <parent.zig> <parent import path from dst>
E.g.: fix_split.py src/runtime/sa_std/json.zig src/runtime/sa_std.zig ../sa_std.zig
"""
import re, sys

dst_path, parent_path, parent_import = sys.argv[1], sys.argv[2], sys.argv[3]
dst = open(dst_path).read()
parent_lines = open(parent_path).read().split("\n")

# top-level decls in parent: name -> (line index, is_pub, kind)
decl_re = re.compile(r"^(pub\s+)?(?:export\s+)?(const|fn|var)\s+([A-Za-z0-9_]+)")
parent_decls = {}
for i, l in enumerate(parent_lines):
    m = decl_re.match(l)
    if m:
        parent_decls[m.group(3)] = (i, bool(m.group(1)), m.group(2))

have = set(re.findall(r"^const ([A-Za-z0-9_]+) =", dst, re.M))
have |= set(re.findall(r"^pub const ([A-Za-z0-9_]+) =", dst, re.M))
# names defined in dst itself
for i, l in enumerate(dst.split("\n")):
    m = decl_re.match(l)
    if m:
        have.add(m.group(3))
idents = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", dst))
missing = sorted(n for n in (idents - have) if n in parent_decls)
print(f"missing idents defined in parent: {len(missing)}")
# parent `var` decls cannot be const-imported (not comptime-known):
# use the module alias instead and rewrite uses to sa_std.<name>.
var_names = [n for n in missing if parent_decls[n][2] == "var"]
missing = [n for n in missing if parent_decls[n][2] != "var"]
if var_names:
    print(f"var decls -> module alias: {var_names}")

# make parent decls pub (in reverse line order to keep indices valid)
for name in missing:
    i, is_pub, _kind = parent_decls[name]
    if not is_pub:
        l = parent_lines[i]
        parent_lines[i] = "pub " + l
        print(f"made pub in parent: {name} (line {i+1})")
# vars accessed via the module alias also need to be pub
for name in var_names:
    i, is_pub, _kind = parent_decls[name]
    if not is_pub:
        l = parent_lines[i]
        parent_lines[i] = "pub " + l
        print(f"made pub var in parent: {name} (line {i+1})")

open(parent_path, "w").write("\n".join(parent_lines))

# add imports to dst (after last import line near top)
lines = dst.split("\n")
insert_at = 0
for i, l in enumerate(lines[:80]):
    if re.match(r"^const \w+ = @import\(", l):
        insert_at = i + 1
if var_names:
    if not any(l.startswith("const sa_std = @import(") for l in lines):
        lines.insert(insert_at, f'const sa_std = @import("{parent_import}");')
        insert_at += 1
        print("add module alias import to dst: sa_std")
    lines = [re.sub(r"(?<!sa_std\.)\b(" + "|".join(map(re.escape, var_names)) + r")\.", r"sa_std.\1.", l) for l in lines]
    print(f"rewrote {var_names} uses to sa_std.<name>.")
for name in missing:
    lines.insert(insert_at, f"const {name} = @import(\"{parent_import}\").{name};")
    insert_at += 1
    print(f"add import to dst: {name}")
open(dst_path, "w").write("\n".join(lines))
print("done")
