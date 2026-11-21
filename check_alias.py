#!/usr/bin/env python3
"""Check for private aliases re-exported across cli modules.

For every `const X = @import("...").Y;` in src/cli/*.zig where Y is NOT pub
in its defining module, list the files that import X from this file.
Those imports fail to compile ('X is not marked pub').
"""
import re, os

def read(p):
    try:
        with open(p, errors="ignore") as f:
            return f.read()
    except OSError:
        return ""

mods = {}
for root, _, files in os.walk("src"):
    for f in files:
        if not f.endswith(".zig"):
            continue
        p = os.path.join(root, f)
        pub = set()
        for l in read(p).split("\n"):
            m = re.match(r"^pub\s+(?:const|fn|var)\s+([A-Za-z0-9_]+)", l)
            if m:
                pub.add(m.group(1))
        mods[p] = pub

def resolve(imp, frm):
    base = os.path.dirname(frm)
    if imp.endswith(".zig"):
        if imp.startswith("cli/"):
            return os.path.join("src", imp)
        return os.path.normpath(os.path.join(base, imp))
    return None

issues = []
for root, _, files in os.walk("src/cli"):
    for f in files:
        if not f.endswith(".zig"):
            continue
        p = os.path.join(root, f)
        for l in read(p).split("\n"):
            m = re.match(r"^(?:pub\s+)?const ([A-Za-z0-9_]+) = @import\(\"([^\"]+)\"\)\.([A-Za-z0-9_]+);", l)
            if not m:
                continue
            local, imp, name = m.group(1), m.group(2), m.group(3)
            target = resolve(imp, p)
            if target is None or target not in mods:
                continue
            if name not in mods[target]:
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
                    issues.append((p, local, target, name, sorted(set(users))))

for p, local, target, name, users in issues:
    print(f"{p}: alias {local} -> {target}.{name} NOT PUB; imported by: {users}")
print("total:", len(issues))
