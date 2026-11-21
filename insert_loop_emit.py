#!/usr/bin/env python3
"""Insert a comptime-loop force-emit block for a module into sa_std.zig's
keep-alive comptime block (after the sa_pg_execute line)."""
import sys

mod_rel = sys.argv[1]
lines = open("src/runtime/sa_std.zig").read().split("\n")
# anchor: the linux-if line inside the keep-alive comptime block
idx = next(i for i, l in enumerate(lines) if l.strip() == "if (builtin.os.tag == .linux) {" and i > 200 and i < 2000)
loop = [
    f"    // force-emit all fns of sa_std/{mod_rel} (loop over decls)",
    "    {",
    f'        const m = @import("sa_std/{mod_rel}");',
    "        for (std.meta.declarations(m)) |decl_name| {",
    "            _ = &@field(m, decl_name);",
    "        }",
    "    }",
]
lines[idx:idx] = loop
open("src/runtime/sa_std.zig", "w").write("\n".join(lines))
print(f"inserted {mod_rel} loop block before line {idx+1}")
