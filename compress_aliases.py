#!/usr/bin/env python3
"""Compress consecutive alias lines in sa_std.zig: group by module and emit
up to N alias statements per line (semicolon-separated). Functionally
identical; only formatting changes.

Usage: compress_aliases.py [N]  (default 8)
Only touches lines matching: ^pub const NAME = @import("PATH").NAME;$
"""
import re, sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")
pat = re.compile(r'^pub const ([A-Za-z0-9_]+) = @import\("([^"]+)"\)\.\1;$')

out = []
i = 0
groups = 0
saved = 0
while i < len(lines):
    m = pat.match(lines[i])
    if not m:
        out.append(lines[i])
        i += 1
        continue
    # collect a run of alias lines for the SAME module
    mod = m.group(2)
    run = []
    while i < len(lines):
        m2 = pat.match(lines[i])
        if not m2 or m2.group(2) != mod:
            break
        run.append(lines[i])
        i += 1
    # emit in chunks of N per line
    for j in range(0, len(run), N):
        chunk = run[j:j + N]
        out.append(" ".join(chunk))
    groups += 1
    saved += len(run) - ((len(run) + N - 1) // N)
print(f"compressed {groups} alias groups, saved {saved} lines")
open(sa_path, "w").write("\n".join(out))
print(f"sa_std.zig now {len(out)} lines")
