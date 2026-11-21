#!/usr/bin/env python3
"""Re-add the sa_tree_sitter_tests wrapper after the module doc comment."""
path = "src/runtime/sa_tree_sitter.zig"
lines = open(path).read().split("\n")
wrapper = 'test "sa_tree_sitter_tests" { std.testing.refAllDecls(@import("sa_tree_sitter_test.zig")); }'
i = 0
while i < len(lines) and lines[i].startswith("//!"):
    i += 1
while i < len(lines) and lines[i].strip() == "":
    i += 1
lines.insert(i, wrapper)
lines.insert(i + 1, "")
open(path, "w").write("\n".join(lines))
print("wrapper re-added at line", i + 1)
