#!/usr/bin/env python3
"""Add a test wrapper registering sa_ssh_test.zig in sa_ssh.zig (after line 1)."""
path = "src/runtime/sa_ssh.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_ssh_tests" { std.testing.refAllDecls(@import("sa_ssh_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
