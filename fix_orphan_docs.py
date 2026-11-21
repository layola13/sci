#!/usr/bin/env python3
"""Convert orphaned /// doc comments (left behind when their alias line
was moved to the re-exports section) into regular // comments.

A /// block is orphaned if the next non-blank, non-/// line is NOT a
declaration (pub const/fn/var/test/struct/enum/union/extern fn...).
"""
import re

sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")
decl_pat = re.compile(r"^(pub\s+)?(const|fn|var|test|extern\s+fn|threadlocal\s+var)\b|^(pub\s+)?(const|var)\s+[A-Za-z0-9_]+\s*[:=]")

out = []
i = 0
converted = 0
while i < len(lines):
    if lines[i].startswith("///"):
        # collect the /// block
        j = i
        while j < len(lines) and lines[j].startswith("///"):
            j += 1
        # find next non-blank line
        k = j
        while k < len(lines) and lines[k].strip() == "":
            k += 1
        nxt = lines[k] if k < len(lines) else ""
        if not decl_pat.match(nxt):
            # orphaned: convert to //
            for t in range(i, j):
                out.append("//" + lines[t][3:])
                converted += 1
            i = j
            continue
        else:
            out.extend(lines[i:j])
            i = j
            continue
    out.append(lines[i])
    i += 1
print(f"converted {converted} orphaned /// lines to //")
open(sa_path, "w").write("\n".join(out))
