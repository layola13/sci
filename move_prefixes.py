#!/usr/bin/env python3
"""Move several prefixes from src to dst (appending to dst across prefixes)."""
import re, sys, os

src_path, dst_path = sys.argv[1], sys.argv[2]
prefixes = sys.argv[3:]
lines = open(src_path).read().split("\n")
rel_dst = os.path.relpath(dst_path, os.path.dirname(src_path))

decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")

def find_end(s, ls):
    depth = 0
    started = False
    for j in range(s, len(ls)):
        code = ls[j].split("//")[0]
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
    return len(ls) - 1

targets = []
for i, l in enumerate(lines):
    m = decl_re.match(l)
    if m and any(m.group(1).startswith(p) for p in prefixes):
        targets.append((i, m.group(1)))
targets.sort(reverse=True)
print(f"found {len(targets)} decls for prefixes {prefixes}")

moved = []
for start, name in targets:
    end = find_end(start, lines)
    block = lines[start:end + 1]
    moved.append((start, name, block))
    lines[start:end + 1] = [f"pub const {name} = @import(\"{rel_dst}\").{name};"]
    print(f"  {name}: lines {start+1}..{end+1} ({end-start+1} lines)")

moved.sort(key=lambda x: x[0])
mode = "a" if os.path.exists(dst_path) else "w"
with open(dst_path, mode) as f:
    if mode == "w":
        f.write("const std = @import(\"std\");\n")
    for _, _, block in moved:
        f.write("\n" + "\n".join(block) + "\n")
open(src_path, "w").write("\n".join(lines))
print(f"{src_path} now {len(lines)} lines")
