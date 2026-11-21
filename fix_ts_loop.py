#!/usr/bin/env python3
"""Make the sa_tree_sitter.zig force-emit loop skip setTsDir (test-only
helper whose body imports build_options, unavailable in the sa_std lib
module)."""
path = "src/runtime/sa_std.zig"
lines = open(path).read().split("\n")
old = '    { const m = @import("sa_tree_sitter.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }'
new = '    { const m = @import("sa_tree_sitter.zig"); for (std.meta.declarations(m)) |n| { if (!std.mem.eql(u8, n, "setTsDir")) _ = &@field(m, n); } }'
count = 0
for i, l in enumerate(lines):
    if l == old:
        lines[i] = new
        count += 1
assert count == 1, f"expected 1 replacement, got {count}"
open(path, "w").write("\n".join(lines))
print("loop updated to skip setTsDir")
