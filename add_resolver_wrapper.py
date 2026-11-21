#!/usr/bin/env python3
"""Add a test wrapper registering resolver_test.zig in resolver.zig."""
path = "src/pkg/resolver.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "resolver_tests" { std.testing.refAllDecls(@import("resolver_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
