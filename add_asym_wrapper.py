#!/usr/bin/env python3
"""Add a test wrapper registering sa_crypto_asym_test.zig in sa_crypto_asym.zig."""
path = "src/runtime/sa_crypto_asym.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_crypto_asym_tests" { std.testing.refAllDecls(@import("sa_crypto_asym_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
