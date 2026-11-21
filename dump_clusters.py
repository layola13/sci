#!/usr/bin/env python3
"""Dump connected components (after removing top-N hubs) with FULL member lists.

Usage: dump_clusters.py <file.zig> <top_n> <out.txt>
Writes one component per block: header line + space-separated member names.
"""
import re, sys
from collections import defaultdict, Counter

path, top_n, out_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
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
hubs = set(n for n, _ in indeg.most_common(top_n))

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
    out.append((total, sorted(members)))
out.sort(reverse=True)
with open(out_path, "w") as f:
    for total, members in out:
        f.write(f"## {total} lines, {len(members)} decls\n")
        f.write(" ".join(members) + "\n\n")
print(f"wrote {len(out)} components to {out_path}")
