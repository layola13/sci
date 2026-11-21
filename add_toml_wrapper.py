#!/usr/bin/env python3
"""Add a test wrapper registering sa_toml_test.zig in sa_toml.zig."""
path = "src/runtime/sa_toml.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_toml_tests" { std.testing.refAllDecls(@import("sa_toml_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
