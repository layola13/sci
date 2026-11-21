#!/usr/bin/env python3
"""Add a test wrapper registering sa_tree_sitter_test.zig in sa_tree_sitter.zig."""
path = "src/runtime/sa_tree_sitter.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "sa_tree_sitter_tests" { std.testing.refAllDecls(@import("sa_tree_sitter_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
