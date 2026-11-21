#!/usr/bin/env python3
"""Insert force-emit lines for a submodule's export fns into sa_std.zig's
comptime keep-alive block (after a given line number)."""
import re, sys

sub_path, parent_path, after_line = sys.argv[1], sys.argv[2], int(sys.argv[3])
mod = sub_path.split("src/runtime/")[-1]
names = re.findall(r"^pub export fn (sa_[A-Za-z0-9_]+)\(", open(sub_path).read(), re.M)
print(f"export fns in {sub_path}: {len(names)}")
lines = open(parent_path).read().split("\n")
ins = [f'    _ = &@import("{mod}").{n};' for n in names]
lines[after_line:after_line] = ins
open(parent_path, "w").write("\n".join(lines))
print(f"inserted {len(ins)} force-emit lines after line {after_line}; parent now {len(lines)} lines")
