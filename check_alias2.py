#!/usr/bin/env python3
"""Check for PRIVATE aliases imported across files.

For every private `const X = @import("...").Y;` in src/cli/*.zig, list files
that import X from this file via @import("...<thisfile>").X — those fail
with 'X is not marked pub'. The fix is either `pub const` on the alias or
re-pointing the importer at the defining module.
"""
import re, os

def read(p):
    try:
        with open(p, errors="ignore") as f:
            return f.read()
    except OSError:
        return ""

issues = []
for root, _, files in os.walk("src/cli"):
    for f in files:
        if not f.endswith(".zig"):
            continue
        p = os.path.join(root, f)
        for l in read(p).split("\n"):
            m = re.match(r"^const ([A-Za-z0-9_]+) = @import\(\"([^\"]+)\"\)\.([A-Za-z0-9_]+);", l)
            if not m:
                continue
            local, imp, name = m.group(1), m.group(2), m.group(3)
            users = []
            for r2, _, fs2 in os.walk("src"):
                for f2 in fs2:
                    if not f2.endswith(".zig"):
                        continue
                    p2 = os.path.join(r2, f2)
                    if p2 == p:
                        continue
                    txt = read(p2)
                    if re.search(r"@import\(\"[^\"]*" + re.escape(os.path.basename(p)) + r"\"\)\." + re.escape(local) + r"\b", txt):
                        users.append(p2)
            if users:
                issues.append((p, local, imp, name, sorted(set(users))))

for p, local, imp, name, users in issues:
    print(f"{p}: private alias {local} (->{imp}.{name}); imported by: {users}")
print("total:", len(issues))
