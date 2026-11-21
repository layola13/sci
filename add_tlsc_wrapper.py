#!/usr/bin/env python3
"""Add a test wrapper registering sa_tls_client_test.zig in sa_tls_client.zig."""
path = "src/runtime/sa_tls_client.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_tls_client_tests" { std.testing.refAllDecls(@import("sa_tls_client_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
