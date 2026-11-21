#!/usr/bin/env python3
"""Retarget sa_std.zig aliases for a prefix group to the files that actually
define the fns, and drop the intermediate alias lines from the old hub file.

Usage: retarget_aliases.py <hub.zig> <file1.zig> [file2.zig ...]
  hub = the file whose alias lines are being removed (e.g. std_net.zig)
  files = the files that now define the fns (hub included for the remainder)
The sa_std.zig alias for each fn is rewritten to import from its real file.
"""
import re, sys

hub_path = sys.argv[1]
real_files = sys.argv[2:]
# map fn name -> import path (relative to src/runtime/sa_std.zig)
owner = {}
for f in real_files:
    names = re.findall(r"^pub export fn ([A-Za-z0-9_]+)\(", open(f).read(), re.M)
    imp = "sa_std/" + f.split("/")[-1]
    for n in names:
        owner[n] = imp
print("fns mapped:", len(owner))

# rewrite sa_std.zig aliases
p = "src/runtime/sa_std.zig"
lines = open(p).read().split("\n")
hub_base = hub_path.split("/")[-1]
hub_imp = "sa_std/" + hub_base
n = 0
for i, l in enumerate(lines):
    m = re.match(r"^pub const ([A-Za-z0-9_]+) = @import\(\"" + re.escape(hub_imp) + r"\"\)\.([A-Za-z0-9_]+);$", l)
    if m and m.group(1) in owner and owner[m.group(1)] != hub_imp:
        lines[i] = f'pub const {m.group(1)} = @import("{owner[m.group(1)]}").{m.group(1)};'
        n += 1
open(p, "w").write("\n".join(lines))
print("retargeted sa_std.zig aliases:", n)

# drop the hub's own alias lines for fns now owned elsewhere
hl = open(hub_path).read().split("\n")
kept = []
dropped = 0
for l in hl:
    m = re.match(r"^pub const ([A-Za-z0-9_]+) = @import\(\"([^\"]+)\"\)\.([A-Za-z0-9_]+);$", l)
    if m and m.group(1) in owner and owner[m.group(1)] != hub_imp:
        dropped += 1
        continue
    kept.append(l)
open(hub_path, "w").write("\n".join(kept))
print("dropped hub alias lines:", dropped)
