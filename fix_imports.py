import re, sys, os
# usage: fix_imports.py <dst_file> <lookup_file>
# Adds to dst every identifier it uses that is defined by an import in lookup_file.
# Skips imports that point back at the dst file itself (self-aliases).
dst_path, lookup_path = sys.argv[1], sys.argv[2]
dst_base = os.path.basename(dst_path)
dst = open(dst_path).read()
lookup = open(lookup_path).read()
table = {}
for l in lookup.split("\n"):
    m = re.match(r"^(pub )?const ([A-Za-z0-9_]+) = @import\(\"([^\"]+)\"\)(\.([A-Za-z0-9_]+))?;$", l.strip())
    if m:
        if os.path.basename(m.group(3)) == dst_base:
            continue
        table[m.group(2)] = l.strip()
have = set(re.findall(r"^const ([A-Za-z0-9_]+) =", dst, re.M))
idents = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", dst))
lines = dst.split("\n")
insert_at = 0
for i, l in enumerate(lines[:80]):
    if re.match(r"^const \w+ = @import\(", l):
        insert_at = i + 1
added = 0
for name in sorted(idents - have):
    if name in table:
        lines.insert(insert_at, table[name])
        insert_at += 1
        added += 1
        print("add:", table[name])
open(dst_path, "w").write("\n".join(lines))
print("added", added, "imports")
