#!/usr/bin/env python3
"""Analyze top-level declaration dependencies in a big .zig file.

Prints, for each name-prefix group, how many references its declarations
make to declarations in other groups (cross-group coupling).
Usage: dep_analyze.py <file.zig>
"""
import re, sys
from collections import defaultdict

path = sys.argv[1]
lines = open(path).read().split("\n")

# find top-level decl starts: lines starting at col 0 with const/fn/var/test/pub...
decl_re = re.compile(r"^(pub )?(export )?(const|fn|var|test)\s+([A-Za-z0-9_]+)")
# fallback for `pub export fn name(` etc: handled by the same regex
starts = []
for i, l in enumerate(lines):
    m = decl_re.match(l)
    if m:
        starts.append((i, m.group(4)))
# also catch `pub export fn` (regex above matches "pub " then "export" as group2)
starts = []
for i, l in enumerate(lines):
    m = re.match(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var|test)\s+([A-Za-z0-9_\"]+)", l)
    if m:
        starts.append((i, m.group(1).strip('"')))
print(f"decls: {len(starts)}")

def find_end(start_idx):
    # brace counting from the decl start line
    depth = 0
    started = False
    for j in range(start_idx, len(lines)):
        l = lines[j]
        # strip string literals crudely (keep it simple: count braces outside // comments)
        code = l.split("//")[0]
        for ch in code:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return j
        if started and depth == 0:
            return j
    return len(lines) - 1

decls = []  # (name, start, end)
for k, (s, name) in enumerate(starts):
    e = find_end(s)
    decls.append((name, s, e))

# group by prefix: sa_<word>_ or first component
def group_of(name):
    m = re.match(r"^sa_([a-z]+)", name)
    if m:
        return "sa_" + m.group(1)
    if name.startswith("sa_"):
        return "sa_other"
    return "other"

names = set(n for n, _, _ in decls)
# reference counts per group pair
cross = defaultdict(lambda: defaultdict(int))
internal = defaultdict(int)
for name, s, e in decls:
    body = "\n".join(lines[s:e + 1])
    # identifiers in body
    idents = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", body))
    g = group_of(name)
    for ident in idents:
        if ident == name or ident not in names:
            continue
        g2 = group_of(ident)
        if g2 == g:
            internal[g] += 1
        else:
            cross[g][g2] += 1

print("\n=== groups (decls, internal refs) ===")
groups = defaultdict(int)
for n, _, _ in decls:
    groups[group_of(n)] += 1
for g in sorted(groups, key=lambda x: -groups[x]):
    print(f"{g}: {groups[g]} decls, internal refs {internal[g]}")

print("\n=== cross-group references (from -> to : count) ===")
pairs = []
for g, tos in cross.items():
    for g2, c in tos.items():
        pairs.append((c, g, g2))
for c, g, g2 in sorted(pairs, reverse=True)[:40]:
    print(f"{g} -> {g2}: {c}")
