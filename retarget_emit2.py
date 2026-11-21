#!/usr/bin/env python3
"""Retarget force-emit lines in sa_std.zig from an old module to a new one.

Usage: python3 retarget_emit2.py <dst_module> <old_import> <new_import>
  e.g. python3 retarget_emit2.py src/runtime/sa_std/fs_meta.zig sa_std/fs.zig sa_std/fs_meta.zig
"""
import re, sys

dst_path, old_import, new_import = sys.argv[1], sys.argv[2], sys.argv[3]
names = re.findall(r"^pub export fn ([A-Za-z0-9_]+)\(", open(dst_path).read(), re.M)
print("export fns in", dst_path, ":", len(names))
lines = open("src/runtime/sa_std.zig").read().split("\n")
n = 0
for i, l in enumerate(lines):
    for name in names:
        if l.strip() == '_ = &@import("' + old_import + '").' + name + ";":
            lines[i] = '    _ = &@import("' + new_import + '").' + name + ";"
            n += 1
            break
open("src/runtime/sa_std.zig", "w").write("\n".join(lines))
print("retargeted force-emit lines:", n)
