#!/usr/bin/env python3
"""Move vars back from a submodule to sa_std.zig (a const alias cannot
re-export a var). Deletes the alias in sa_std.zig and the var in the
submodule, re-inserting the var definition into sa_std.zig near the
other vars. Usage: move_vars_back.py <submodule.zig> <var1> [var2 ...]
"""
import re, sys

sub_path = sys.argv[1]
names = sys.argv[2:]
sa_path = "src/runtime/sa_std.zig"
sub = open(sub_path).read().split("\n")
sa = open(sa_path).read().split("\n")

# find the var definitions in the submodule and remove them
moved = {}
for name in names:
    for i, l in enumerate(sub):
        if re.match(rf"^(?:pub\s+)?(?:threadlocal\s+)?var {re.escape(name)}\b", l):
            # find end (single line var decl)
            moved[name] = l
            del sub[i]
            print(f"removed {name} from {sub_path} line {i+1}")
            break
    else:
        print(f"WARNING: {name} not found in {sub_path}")
open(sub_path, "w").write("\n".join(sub))

# delete the const aliases in sa_std.zig and re-insert the var defs
for name in names:
    if name not in moved:
        continue
    for i, l in enumerate(sa):
        if l == f'pub const {name} = @import("sa_std/{sub_path.split("/")[-1]}").{name};':
            # replace the alias line with the var definition (as pub)
            vardef = moved[name]
            if not vardef.startswith("pub "):
                vardef = "pub " + vardef
            sa[i] = vardef
            print(f"restored {name} in sa_std.zig line {i+1}")
            break
    else:
        print(f"WARNING: alias for {name} not found in sa_std.zig")
open(sa_path, "w").write("\n".join(sa))
