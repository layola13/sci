#!/usr/bin/env python3
"""Find comment blocks in sa_std.zig that immediately precede an alias
line (pub const X = @import(...).X;). Those comments document a moved fn
and belong in the submodule, not in the parent. Reports counts and the
alias target module for each block.
"""
import re

lines = open("src/runtime/sa_std.zig").read().split("\n")
alias_re = re.compile(r'pub const ([A-Za-z0-9_]+) = @import\("([^"]+)"\)\.\1;')
total_comment_lines = 0
blocks = 0
for i, l in enumerate(lines):
    if "@import(" in l and "pub const " in l:
        # walk back over preceding comment lines (/// or //) and blanks
        j = i - 1
        cmt = 0
        while j >= 0 and (lines[j].strip().startswith("//") or lines[j].strip() == ""):
            if lines[j].strip().startswith("//"):
                cmt += 1
            j -= 1
        if cmt > 0:
            # find the module of the first alias on this line
            m = alias_re.search(l)
            mod = m.group(2) if m else "?"
            blocks += 1
            total_comment_lines += cmt
print(f"alias lines with preceding comments: {blocks} blocks, {total_comment_lines} comment lines")
