#!/usr/bin/env python3
"""Fix the json split follow-ups:
1) make Json handle structs + their methods pub in sa_std.zig
2) move the 64 json force-emit lines out of the if(.linux) block
3) registry_mutex in json.zig: module alias + rewrite uses
"""
import re

p = "src/runtime/sa_std.zig"
lines = open(p).read().split("\n")
for name in ("JsonNodeHandle", "JsonBufferHandle", "JsonDocumentHandle"):
    for i, l in enumerate(lines):
        if re.match(r"^const " + re.escape(name) + r" = struct", l):
            lines[i] = "pub " + l
            print("pub struct", name)
            break
in_handle = False
for i, l in enumerate(lines):
    if re.match(r"^pub const Json(Node|Buffer|Document)Handle = struct", l):
        in_handle = True
    elif in_handle and l.startswith("};"):
        in_handle = False
    elif in_handle and re.match(r"^    fn (deinit|retain|release)\(", l):
        lines[i] = "    pub " + l.strip()
        print("pub method line", i + 1, l.strip()[:40])
open(p, "w").write("\n".join(lines))

lines = open(p).read().split("\n")
json_lines = [l for l in lines if l.strip().startswith('_ = &@import("sa_std/json.zig")')]
assert len(json_lines) == 64, len(json_lines)
lines = [l for l in lines if not l.strip().startswith('_ = &@import("sa_std/json.zig")')]
if_idx = next(i for i, l in enumerate(lines) if "if (builtin.os.tag == .linux) {" in l)
lines[if_idx:if_idx] = json_lines
open(p, "w").write("\n".join(lines))
print("moved 64 force-emit lines before if(.linux) at line", if_idx + 1)

j = "src/runtime/sa_std/json.zig"
jl = open(j).read().split("\n")
for i, l in enumerate(jl):
    if l == 'const registry_mutex = @import("../sa_std.zig").registry_mutex;':
        jl[i] = 'const sa_std = @import("../sa_std.zig");'
        print("replaced registry_mutex import with sa_std module alias")
        break
jl = [l.replace("registry_mutex.", "sa_std.registry_mutex.") for l in jl]
open(j, "w").write("\n".join(jl))
print("rewrote registry_mutex uses")
