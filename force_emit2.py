#!/usr/bin/env python3
"""Add force-emit lines for a moved domain module into sa_std.zig's
comptime keep-alive block (before the if(.linux) line).

Usage: python3 force_emit2.py <dst_module> <import_path_from_sa_std>
  e.g. python3 force_emit2.py src/runtime/sa_std/fs.zig sa_std/fs.zig
"""
import re, sys

dst_path, import_path = sys.argv[1], sys.argv[2]
names = re.findall(r"^pub export fn ([A-Za-z0-9_]+)\(", open(dst_path).read(), re.M)
print("export fns in", dst_path, ":", len(names))
p = "src/runtime/sa_std.zig"
lines = open(p).read().split("\n")
# skip fns already covered by a force-emit line
existing = set(re.findall(r"_ = &@import\([^)]+\)\.([A-Za-z0-9_]+);", "\n".join(lines)))
new = [n for n in names if n not in existing]
print("already covered:", len(names) - len(new), "new:", len(new))
if_idx = next(i for i, l in enumerate(lines) if "if (builtin.os.tag == .linux) {" in l)
emit = ["    _ = &@import(\"" + import_path + "\")." + n + ";" for n in new]
lines[if_idx:if_idx] = emit
open(p, "w").write("\n".join(lines))
print("inserted", len(emit), "force-emit lines before line", if_idx + 1)
