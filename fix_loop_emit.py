#!/usr/bin/env python3
"""Replace the broken json loop block (inline for + @typeInfo decls)
with the std.meta.declarations version."""
import re

lines = open("src/runtime/sa_std.zig").read().split("\n")
# find the loop block start
start = next(i for i, l in enumerate(lines) if "force-emit all fns of sa_std/json.zig" in l)
# the block is: comment + { + 7 lines + } = 10 lines (start..start+9)
assert lines[start + 1].strip() == "{", lines[start + 1]
assert lines[start + 9].strip() == "}", lines[start + 9]
new = [
    "    // force-emit all fns of sa_std/json.zig (loop over decls)",
    "    {",
    '        const m = @import("sa_std/json.zig");',
    "        for (std.meta.declarations(m)) |decl_name| {",
    "            _ = &@field(m, decl_name);",
    "        }",
    "    }",
]
lines[start:start + 10] = new
open("src/runtime/sa_std.zig", "w").write("\n".join(lines))
print(f"replaced json loop block at line {start+1}")
