#!/usr/bin/env python3
"""Make all methods pub on named structs in a file."""
import re, sys

path = sys.argv[1]
struct_names = sys.argv[2:]
lines = open(path).read().split("\n")
# find struct spans
spans = []
for i, l in enumerate(lines):
    for name in struct_names:
        if re.match(r"^(pub )?const " + re.escape(name) + r" = struct", l):
            # find end via brace counting
            depth = 0
            started = False
            for j in range(i, len(lines)):
                code = lines[j].split("//")[0]
                for ch in code:
                    if ch == "{":
                        depth += 1
                        started = True
                    elif ch == "}":
                        depth -= 1
                        if started and depth == 0:
                            spans.append((i, j, name))
                            break
                if spans and spans[-1][0] == i:
                    break
            break
for start, end, name in spans:
    n = 0
    for i in range(start + 1, end):
        m = re.match(r"^(\s+)fn (\w+)\(", lines[i])
        if m:
            lines[i] = m.group(1) + "pub " + lines[i][m.end(1):]
            n += 1
    print(f"{name}: lines {start+1}..{end+1}, made {n} methods pub")
open(path, "w").write("\n".join(lines))
