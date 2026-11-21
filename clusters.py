#!/usr/bin/env python3
"""Find loosely-coupled clusters among the 'other' (unprefixed) decls of a file.

Builds the reference graph between top-level decls, then reports connected
components (undirected) of the 'other' group, with size in lines and the
number of refs each component makes to decls outside itself.
Usage: clusters.py <file.zig> [min_lines]
"""
import re, sys
from collections import defaultdict

path = sys.argv[1]
min_lines = int(sys.argv[2]) if len(sys.argv) > 2 else 50
lines = open(path).read().split("\n")

decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")
starts = []
for i, l in enumerate(lines):
    m = decl_re.match(l)
    if m and "@import(" not in l:
        starts.append((i, m.group(1)))
starts.append((len(lines), "<END>"))

def strip_code(line):
    """Remove // comment, string literals and char literals from a line."""
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

# decl name -> (start, end, body text)
decls = {}
for k in range(len(starts) - 1):
    s, name = starts[k]
    e = find_end(s)
    decls[name] = (s, e, "\n".join(lines[s:e + 1]))

# reference graph: name -> set of other decl names it references
idents_re = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
refs = {}
for name, (_, _, body) in decls.items():
    refs[name] = set(t for t in idents_re.findall(body) if t in decls and t != name)

# undirected connected components
parent = {n: n for n in decls}
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
    for r in rs:
        union(name, r)
comps = defaultdict(list)
for n in decls:
    comps[find(n)].append(n)

# report components with >= min_lines, sorted by lines desc
out = []
for root, members in comps.items():
    total_lines = sum(decls[m][1] - decls[m][0] + 1 for m in members)
    if total_lines < min_lines:
        continue
    # external refs: refs from members to decls outside the component
    ext = sum(1 for m in members for r in refs[m] if find(r) != root)
    out.append((total_lines, len(members), ext, sorted(members)))
out.sort(reverse=True)
print(f"components >= {min_lines} lines: {len(out)}")
for total_lines, ndecls, ext, members in out[:30]:
    print(f"\n--- {total_lines} lines, {ndecls} decls, {ext} external refs ---")
    print("  " + ", ".join(members[:25]))
    if len(members) > 25:
        print(f"  ... +{len(members) - 25} more")
