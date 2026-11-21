#!/usr/bin/env python3
"""Measure sa_std.zig composition."""
import re

lines = open("src/runtime/sa_std.zig").read().split("\n")
print("total:", len(lines))
in_re = False
re_lines = 0
for l in lines:
    if l.startswith("// Re-exports:"):
        in_re = True
    if in_re:
        re_lines += 1
        if re_lines > 5 and l.strip() == "" and re_lines > 200:
            break
print("re-exports section (approx):", re_lines)
loop_lines = sum(1 for l in lines if "force-emit all fns" in l or "std.meta.declarations" in l or l.strip() in ("_ = &@field(m, decl_name);", "for (std.meta.declarations(m)) |decl_name| {") or "const m = @import(" in l)
print("loop-related lines:", loop_lines)
print("comptime { lines:", sum(1 for l in lines if l.strip() == "comptime {"))
print("lines with sa_std/ import:", sum(1 for l in lines if '@import("sa_std/' in l))
print("lines with sa_*.zig import:", sum(1 for l in lines if re.search(r'@import\("sa_[a-z_]+\.zig"\)', l)))
print("blank lines:", sum(1 for l in lines if l.strip() == ""))
print("comment lines:", sum(1 for l in lines if l.strip().startswith("//")))
decl_re = re.compile(r"^(?:pub\s+)?(?:export\s+)?(?:threadlocal\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)")
real = 0
for l in lines:
    if "@import(" in l:
        continue
    if decl_re.match(l):
        real += 1
print("real top-level decls:", real)
