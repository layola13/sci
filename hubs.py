#!/usr/bin/env python3
"""Hub analysis: rank decls by in-degree (how many other decls reference them),
then show what connected components appear if the top-N hubs are treated as
external (removed from the graph).

Usage: hubs.py <file.zig> [top_n]
"""
import re, sys
from collections import defaultdict, Counter

path = sys.argv[1]
top_n = int(sys.argv[2]) if len(sys.argv) > 2 else 20
lines = open(path).read().split("\n")

decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")
starts = []
for i, l in enumerate(lines):
    m = decl_re.match(l)
    if m and "@import(" not in l:
        starts.append((i, m.group(1)))
starts.append((len(lines), "<END>"))

def strip_code(line):
    out = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break
        if c == '"':
            i += 1
            while i < n and line[i] != '"':
                if line[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        if c == "'":
            i += 1
            while i < n and line[i] != "'":
                if line[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)

def find_end(s):
    first = strip_code(lines[s])
    if "{" not in first and first.rstrip().endswith(";"):
        return s
    depth = 0
    started = False
    for j in range(s, len(lines)):
        code = strip_code(lines[j])
        for ch in code:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return j
    return len(lines) - 1

decls = {}
for k in range(len(starts) - 1):
    s, name = starts[k]
    e = find_end(s)
    decls[name] = (s, e, "\n".join(lines[s:e + 1]))

idents_re = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
refs = {}
for name, (_, _, body) in decls.items():
    refs[name] = set(t for t in idents_re.findall(body) if t in decls and t != name)

indeg = Counter()
for name, rs in refs.items():
    for r in rs:
        indeg[r] += 1
print("=== top hubs by in-degree ===")
for name, d in indeg.most_common(25):
    print(f"{d:4d} {name} ({decls[name][1]-decls[name][0]+1} lines)")

hubs = set(n for n, _ in indeg.most_common(top_n))
# rebuild components ignoring hubs
parent = {n: n for n in decls if n not in hubs}
def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[ra] = rb
for name, rs in refs.items():
    if name in hubs:
        continue
    for r in rs:
        if r in hubs:
            continue
        union(name, r)
comps = defaultdict(list)
for n in parent:
    comps[find(n)].append(n)
out = []
for root, members in comps.items():
    total = sum(decls[m][1] - decls[m][0] + 1 for m in members)
    if total >= 80:
        ext = sum(1 for m in members for r in refs[m] if r not in hubs and find(r) != root)
        out.append((total, len(members), ext, sorted(members)))
out.sort(reverse=True)
print(f"\n=== components >= 80 lines after removing top {top_n} hubs: {len(out)} ===")
for total, ndecls, ext, members in out[:20]:
    print(f"\n--- {total} lines, {ndecls} decls, {ext} ext refs ---")
    print("  " + ", ".join(members[:20]))
    if len(members) > 20:
        print(f"  ... +{len(members) - 20} more")
