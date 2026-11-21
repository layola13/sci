#!/usr/bin/env python3
"""Fix fs split leftovers:
1) registry_mutex var import in fs.zig -> module alias + rewrite uses
2) saFsOpenFile pub in fs.zig + reverse import into sa_std.zig
"""
import re

j = "src/runtime/sa_std/fs.zig"
jl = open(j).read().split("\n")
for i, l in enumerate(jl):
    if l == 'const registry_mutex = @import("../sa_std.zig").registry_mutex;':
        jl[i] = 'const sa_std = @import("../sa_std.zig");'
        print("registry_mutex -> sa_std alias")
        break
jl = [l.replace("registry_mutex.", "sa_std.registry_mutex.") for l in jl]
for i, l in enumerate(jl):
    if l.startswith("fn saFsOpenFile("):
        jl[i] = "pub " + l
        print("saFsOpenFile pub")
        break
open(j, "w").write("\n".join(jl))

p = "src/runtime/sa_std.zig"
pl = open(p).read().split("\n")
if not any("saFsOpenFile" in l and "@import" in l for l in pl):
    # insert near the fs aliases: find first sa_fs_ alias line
    idx = next(i for i, l in enumerate(pl) if "sa_fs_" in l and "@import" in l)
    pl.insert(idx, 'const saFsOpenFile = @import("sa_std/fs.zig").saFsOpenFile;')
    print("added saFsOpenFile reverse import at line", idx + 1)
open(p, "w").write("\n".join(pl))
