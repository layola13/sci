#!/usr/bin/env python3
"""Move the sa_tree_sitter_tests wrapper to after the module doc comment block."""
path = "src/runtime/sa_tree_sitter.zig"
lines = open(path).read().split("\n")
wrapper = 'test "sa_tree_sitter_tests" { std.testing.refAllDecls(@import("sa_tree_sitter_test.zig")); }'
# remove the wrapper from line 2 (index 1)
assert lines[1] == wrapper, f"unexpected line 2: {lines[1]!r}"
del lines[1]
# find the end of the leading //! doc-comment block
i = 0
while i < len(lines) and lines[i].startswith("//!"):
    i += 1
# skip blank lines after the doc block
while i < len(lines) and lines[i].strip() == "":
    i += 1
lines.insert(i, wrapper)
lines.insert(i + 1, "")
open(path, "w").write("\n".join(lines))
print(f"wrapper moved to line {i + 1}")
