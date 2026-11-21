#!/usr/bin/env python3
"""Append test blocks from a misc file (skipping its header/imports)
to the current sa_std_tests.zig."""
misc = open("/tmp/tests_misc.zig").read().split("\n")
start = next(i for i, l in enumerate(misc) if l.startswith('test "'))
blocks = "\n".join(misc[start:])
cur = open("src/runtime/sa_std/sa_std_tests.zig").read()
open("src/runtime/sa_std/sa_std_tests.zig", "w").write(cur.rstrip() + "\n\n" + blocks)
print("appended misc tests; file now", len(cur.rstrip().split("\n")) + len(blocks.split("\n")) + 1, "lines")
