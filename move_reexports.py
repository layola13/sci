#!/usr/bin/env python3
"""Move the re-exports section out of sa_std.zig into sa_std/api.zig,
replacing it in sa_std.zig with a single `pub usingnamespace` line.

The section starts at the "// Re-exports:" comment line and ends just
before the first line after it that is NOT a // comment, an alias
statement, or blank. Alias statements are lines containing
'pub const NAME = @import(' (possibly several per line).
"""
import re

sa_path = "src/runtime/sa_std.zig"
api_path = "src/runtime/sa_std/api.zig"
lines = open(sa_path).read().split("\n")

start = next(i for i, l in enumerate(lines) if l.startswith("// Re-exports:"))
# the section is contiguous: // comments, alias lines, blanks
end = start
while end < len(lines):
    l = lines[end]
    if l.strip().startswith("//") or "pub const " in l and "@import(" in l or l.strip() == "":
        end += 1
    else:
        break
section = lines[start:end]
print(f"re-exports section: lines {start+1}..{end} ({len(section)} lines)")
# sanity: count alias statements in the section
n_alias = sum(len(re.findall(r'pub const [A-Za-z0-9_]+ = @import\("[^"]+"\)\.[A-Za-z0-9_]+;', l)) for l in section)
print(f"alias statements in section: {n_alias}")

with open(api_path, "w") as f:
    f.write('const std = @import("std");\n')
    f.write("\n".join(section).rstrip() + "\n")
rest = lines[:start] + ['pub usingnamespace @import("sa_std/api.zig");'] + lines[end:]
open(sa_path, "w").write("\n".join(rest))
print(f"sa_std.zig now {len(rest)} lines")
