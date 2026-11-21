#!/usr/bin/env python3
"""Retarget force-emit lines in sa_std.zig from json.zig to json_io.zig
for the scanner/stream/writer fns that moved."""
import re

moved = re.findall(
    r"^pub export fn (sa_json_(?:scanner|stream|writer)_[A-Za-z0-9_]+)\(",
    open("src/runtime/sa_std/json_io.zig").read(),
    re.M,
)
print("moved fns:", len(moved))
lines = open("src/runtime/sa_std.zig").read().split("\n")
n = 0
for i, l in enumerate(lines):
    for name in moved:
        if l.strip() == '_ = &@import("sa_std/json.zig").' + name + ";":
            lines[i] = '    _ = &@import("sa_std/json_io.zig").' + name + ";"
            n += 1
            break
open("src/runtime/sa_std.zig", "w").write("\n".join(lines))
print("updated force-emit lines:", n)
