#!/usr/bin/env python3
"""Move the sa_cookie_tests wrapper to after the module doc comment block."""
path = "src/runtime/sa_cookie.zig"
lines = open(path).read().split("\n")
wrapper = 'test "sa_cookie_tests" { std.testing.refAllDecls(@import("sa_cookie_test.zig")); }'
assert lines[1] == wrapper, f"unexpected line 2: {lines[1]!r}"
del lines[1]
i = 0
while i < len(lines) and lines[i].startswith("//!"):
    i += 1
while i < len(lines) and lines[i].strip() == "":
    i += 1
lines.insert(i, wrapper)
lines.insert(i + 1, "")
open(path, "w").write("\n".join(lines))
print(f"wrapper moved to line {i + 1}")
