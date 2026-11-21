#!/usr/bin/env python3
"""Move all top-level decls whose name starts with a given prefix from a
.zig file to a new submodule file, leaving pub aliases behind.
Usage: move_prefix.py <src.zig> <dst.zig> <prefix> [extra test-name prefix]
"""
import re, sys, os

src_path, dst_path, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
test_prefix = sys.argv[4] if len(sys.argv) > 4 else None
rel_dst = os.path.relpath(dst_path, os.path.dirname(src_path))
lines = open(src_path).read().split("\n")

decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")
test_re = re.compile(r"^test\s+\"([^\"]+)\"")

def find_end(s):
    depth = 0
    started = False
    for j in range(s, len(lines)):
        code = lines[j].split("//")[0]
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

# collect decls to move (scan from bottom so line numbers stay valid)
targets = []
for i, l in enumerate(lines):
    m = decl_re.match(l)
    if m and m.group(1).startswith(prefix):
        targets.append((i, m.group(1), "decl"))
    elif test_prefix:
        t = test_re.match(l)
        if t and t.group(1).startswith(test_prefix):
            targets.append((i, t.group(1), "test"))

targets.sort(reverse=True)
print(f"found {len(targets)} decls with prefix {prefix!r}" + (f" + tests {test_prefix!r}" if test_prefix else ""))

moved_blocks = []
for start, name, kind in targets:
    end = find_end(start)
    block = lines[start:end + 1]
    moved_blocks.append((start, name, block))
    # replace with alias (decls only; tests have no alias)
    if kind == "decl":
        alias = f"pub const {name} = @import(\"{rel_dst}\").{name};"
        lines[start:end + 1] = [alias]
    else:
        del lines[start:end + 1]
    print(f"  {kind} {name}: lines {start+1}..{end+1} ({end-start+1} lines)")

# write dst: header + moved blocks in original order
moved_blocks.sort(key=lambda x: x[0])
header = "const std = @import(\"std\");\n"
with open(dst_path, "w") as f:
    f.write(header)
    for _, _, block in moved_blocks:
        f.write("\n" + "\n".join(block) + "\n")

open(src_path, "w").write("\n".join(lines))
print(f"{src_path} now {len(lines)} lines; {dst_path} has {len(moved_blocks)} decls")
