#!/usr/bin/env python3
"""Compress each 7-line force-emit loop block in sa_std.zig into a single
line (same inline semantics, just formatted compactly):
    { const m = @import("sa_std/X.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
"""
import re

sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")
pat = re.compile(r'^\s*// force-emit all fns of (\S+) \((?:\d+ fns, )?loop over decls\)$')
out = []
i = 0
n = 0
while i < len(lines):
    m = pat.match(lines[i])
    if m:
        mod = m.group(1)
        # verify the 7-line block shape
        assert lines[i + 1].strip() == "{", lines[i + 1]
        assert "const m = @import" in lines[i + 2], lines[i + 2]
        assert "std.meta.declarations" in lines[i + 3], lines[i + 3]
        assert "_ = &@field" in lines[i + 4], lines[i + 4]
        assert lines[i + 5].strip() == "}", lines[i + 5]
        assert lines[i + 6].strip() == "}", lines[i + 6]
        out.append(f'    {{ const m = @import("{mod}"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }}')
        n += 1
        i += 7
        continue
    out.append(lines[i])
    i += 1
print(f"compressed {n} loop blocks")
open(sa_path, "w").write("\n".join(out))
print(f"sa_std.zig now {len(out)} lines (saved {len(lines)-len(out)})")
