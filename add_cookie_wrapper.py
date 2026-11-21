#!/usr/bin/env python3
"""Add a test wrapper registering sa_cookie_test.zig in sa_cookie.zig."""
path = "src/runtime/sa_cookie.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_cookie_tests" { std.testing.refAllDecls(@import("sa_cookie_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
