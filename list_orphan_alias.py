#!/usr/bin/env python3
"""List alias lines in sa_std.zig that have preceding comment blocks,
with the target module and comment count."""
import re

lines = open("src/runtime/sa_std.zig").read().split("\n")
alias_re = re.compile(r'pub const ([A-Za-z0-9_]+) = @import\("([^"]+)"\)\.\1;')
for i, l in enumerate(lines):
    if "@import(" in l and "pub const " in l:
        m = alias_re.search(l)
        if m:
            j = i - 1
            cmt = 0
            while j >= 0 and (lines[j].strip().startswith("//") or lines[j].strip() == ""):
                if lines[j].strip().startswith("//"):
                    cmt += 1
                j -= 1
            if cmt > 0:
                print(f"line {i+1}: {m.group(1)} -> {m.group(2)} ({cmt} comment lines)")
