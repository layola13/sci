#!/usr/bin/env python3
"""Move MULTIPLE clusters (by index in a dump_clusters.py output file)
from a .zig file into one submodule, leaving pub aliases behind.
Usage: move_clusters.py <src.zig> <dst.zig> <clusters.txt> <idx1,idx2,...>
Skips alias/import lines (they contain @import().
"""
import re, sys, os

src_path, dst_path, clusters_path, idxs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
rel_dst = os.path.relpath(dst_path, os.path.dirname(src_path))
lines = open(src_path).read().split("\n")
blocks = open(clusters_path).read().strip().split("\n\n")
members = set()
for idx in idxs.split(","):
    idx = int(idx)
    header, names_line = blocks[idx].split("\n")
    members |= set(names_line.split())
    print(f"cluster {idx}: {header} -> {len(names_line.split())} members")
print(f"total members: {len(members)}")

decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:threadlocal\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")

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

targets = []
for i, l in enumerate(lines):
    if "@import(" in l:
        continue
    m = decl_re.match(l)
    if m and m.group(1) in members:
        targets.append((i, m.group(1)))
targets.sort(reverse=True)
print(f"found {len(targets)} of {len(members)} members in src")
missing = members - set(n for _, n in targets)
if missing:
    print("NOT FOUND in src:", sorted(missing))

moved_blocks = []
for start, name in targets:
    end = find_end(start)
    block = lines[start:end + 1]
    moved_blocks.append((start, name, block))
    alias = f"pub const {name} = @import(\"{rel_dst}\").{name};"
    lines[start:end + 1] = [alias]
    print(f"  {name}: lines {start+1}..{end+1} ({end-start+1} lines)")

moved_blocks.sort(key=lambda x: x[0])
header = "const std = @import(\"std\");\n"
with open(dst_path, "w") as f:
    f.write(header)
    for _, _, block in moved_blocks:
        f.write("\n" + "\n".join(block) + "\n")
open(src_path, "w").write("\n".join(lines))
print(f"{src_path} now {len(lines)} lines; {dst_path} has {len(moved_blocks)} decls")
