#!/usr/bin/env python3
"""Find every identifier used in dst that is an `extern fn` (or `extern "c" fn`)
in parent, and copy those declarations into dst.

Usage: copy_all_externs.py <dst.zig> <parent.zig>
"""
import re, sys

dst_path, parent_path = sys.argv[1], sys.argv[2]
parent_lines = open(parent_path).read().split("\n")
dst = open(dst_path).read()

# parent extern fns: name -> decl line
externs = {}
for l in parent_lines:
    m = re.match(r"^extern (?:\"c\" )?fn ([A-Za-z0-9_]+)\(.*;", l)
    if m:
        externs[m.group(1)] = l
# also extern vars
for l in parent_lines:
    m = re.match(r"^extern (?:\"c\" )?var ([A-Za-z0-9_]+)\b.*;", l)
    if m:
        externs[m.group(1)] = l

have = set(re.findall(r"^extern (?:\"c\" )?fn ([A-Za-z0-9_]+)\(", dst, re.M))
have |= set(re.findall(r"^extern (?:\"c\" )?var ([A-Za-z0-9_]+)\b", dst, re.M))
idents = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", dst))
need = sorted(n for n in (idents - have) if n in externs)
print("externs needed:", need)
if not need:
    print("none")
    sys.exit(0)

lines = dst.split("\n")
insert_at = 0
for i, l in enumerate(lines[:80]):
    if re.match(r"^const \w+ = @import\(", l):
        insert_at = i + 1
    if re.match(r"^extern ", l):
        insert_at = i + 1
for name in need:
    lines.insert(insert_at, externs[name])
    insert_at += 1
    print("copied:", externs[name][:80])
open(dst_path, "w").write("\n".join(lines))
print("done")
