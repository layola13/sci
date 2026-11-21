#!/usr/bin/env python3
"""Compress the per-module force-emit loop blocks in sa_std.zig into a
single comptime helper + one call line per module.

Before (7 lines per module):
    // force-emit all fns of sa_std/json.zig (33 fns, loop over decls)
    {
        const m = @import("sa_std/json.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
After (1 line per module + 3-line helper):
    forceEmitAll(@import("sa_std/json.zig"));
"""
import re

sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")

# find all loop blocks: comment line + { + const m + for + _ = + } + }
pat = re.compile(r'^\s*// force-emit all fns of (\S+) \(\d+ fns, loop over decls\)$')
mods = []
out = []
i = 0
while i < len(lines):
    m = pat.match(lines[i])
    if m:
        mods.append(m.group(1))
        # skip the 7-line block (comment + 6 lines)
        # verify the shape
        assert lines[i + 1].strip() == "{", lines[i + 1]
        assert "const m = @import" in lines[i + 2], lines[i + 2]
        assert "std.meta.declarations" in lines[i + 3], lines[i + 3]
        assert "_ = &@field" in lines[i + 4], lines[i + 4]
        assert lines[i + 5].strip() == "}", lines[i + 5]
        assert lines[i + 6].strip() == "}", lines[i + 6]
        i += 7
        continue
    out.append(lines[i])
    i += 1
print(f"found {len(mods)} loop blocks")
if not mods:
    raise SystemExit("no loop blocks found")

# insert the helper + one call per module right after the
# @setEvalBranchQuota line in the keep-alive comptime block
helper = [
    "    // Force-emit every fn of a submodule into libsa_std.a (Zig lazy",
    "    // analysis does not emit a child module's pub export fn unless",
    "    // something takes its address). One call per module.",
    "    const forceEmitAll = struct {",
    "        fn run(comptime m: type) void {",
    "            for (std.meta.declarations(m)) |n| _ = &@field(m, n);",
    "        }",
    "    }.run;",
]
calls = [f'    forceEmitAll(@import("{mod}"));' for mod in mods]
# find the @setEvalBranchQuota line
qi = next(i for i, l in enumerate(out) if "@setEvalBranchQuota" in l)
out[qi + 1:qi + 1] = helper + calls
open(sa_path, "w").write("\n".join(out))
print(f"sa_std.zig now {len(out)} lines (saved {len(lines)-len(out)})")
