#!/usr/bin/env python3
"""Add a test wrapper registering line_classifier_test.zig in line_classifier.zig."""
path = "src/flattener/line_classifier.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'test "line_classifier_tests" { std.testing.refAllDecls(@import("line_classifier_test.zig")); }')
open(path, "w").write("\n".join(lines))
print("wrapper added")
