#!/usr/bin/env python3
"""Append test blocks from /tmp/tests_tcp.zig (skipping header/imports)
to tests_net.zig."""
misc = open("/tmp/tests_tcp.zig").read().split("\n")
start = next(i for i, l in enumerate(misc) if l.startswith('test "'))
blocks = "\n".join(misc[start:])
cur = open("src/runtime/sa_std/tests_net.zig").read()
open("src/runtime/sa_std/tests_net.zig", "w").write(cur.rstrip() + "\n\n" + blocks)
print("appended TCP/UDP tests to tests_net.zig")
