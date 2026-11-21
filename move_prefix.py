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
    # single-line decl (ends with ; and has no brace): the decl is one line
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
        # END-OF-LINE depth check: a `}` mid-line (e.g. closing an anonymous
        # struct in a fn return type) must not end the decl.
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
