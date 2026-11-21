#!/usr/bin/env python3
"""Add a test wrapper registering sa_http2_test.zig in sa_http2.zig."""
path = "src/runtime/sa_http2.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_http2_tests" { std.testing.refAllDecls(@import("sa_http2_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
