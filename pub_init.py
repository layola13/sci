#!/usr/bin/env python3
lines = open("src/runtime/sa_std.zig").read().split("\n")
for ln in (1429, 1443, 1479, 1513):
    i = ln - 1
    assert lines[i].strip().startswith("fn init"), (ln, lines[i])
    lines[i] = lines[i].replace("    fn init", "    pub fn init", 1)
    print("pub init at line", ln)
open("src/runtime/sa_std.zig", "w").write("\n".join(lines))
