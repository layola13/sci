#!/usr/bin/env python3
"""Fix registry_slots var alias in sa_std.zig (spawn cluster move):
- delete the const alias for the var
- add spawn module alias
- rewrite bare uses in getResourceLocked/registerResourceLocked
"""
import re
sa = open("src/runtime/sa_std.zig").read().split("\n")
for i, l in enumerate(sa):
    if l == 'pub const registry_slots = @import("sa_std/spawn.zig").registry_slots;':
        del sa[i]
        print(f"deleted registry_slots alias at line {i+1}")
        break
if not any(l.startswith('const spawn = @import("sa_std/spawn.zig");') for l in sa):
    for i, l in enumerate(sa):
        if l == 'const std = @import("std");':
            sa.insert(i + 1, 'const spawn = @import("sa_std/spawn.zig");')
            print("added spawn module alias")
            break
# rewrite bare registry_slots uses (not already spawn.registry_slots, not alias lines)
n = 0
for i, l in enumerate(sa):
    if re.search(r"(?<!spawn\.)\bregistry_slots\b", l) and "@import" not in l:
        sa[i] = re.sub(r"(?<!spawn\.)\bregistry_slots\b", "spawn.registry_slots", l)
        n += 1
print(f"rewrote {n} uses")
open("src/runtime/sa_std.zig", "w").write("\n".join(sa))
