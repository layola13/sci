#!/usr/bin/env python3
"""Add a test wrapper registering sa_pg_test.zig in sa_pg.zig."""
path = "src/runtime/sa_pg.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_pg_tests" { std.testing.refAllDecls(@import("sa_pg_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
