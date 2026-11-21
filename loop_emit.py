#!/usr/bin/env python3
"""Test the comptime-loop force-emit approach for one module:
- remove the comptime force-emit block from the module (if present)
- in sa_std.zig, replace that module's individual force-emit lines with
  a single comptime block that iterates the module's decls and takes
  the address of every fn (forcing emission of all pub export fns).

Usage: loop_emit.py <module.zig>
"""
import re, sys

mod_rel = sys.argv[1]
mod_path = f"src/runtime/sa_std/{mod_rel}"
sa_path = "src/runtime/sa_std.zig"

# 1) remove the comptime force-emit block from the module
mod = open(mod_path).read()
m = re.search(r"\n// Force-emit the pub export fns into libsa_std\.a.*?\ncomptime \{\n(?:    _ = &[A-Za-z0-9_]+;\n)+\}\n?$", mod, re.S)
if m:
    mod = mod[:m.start()] + "\n"
    open(mod_path, "w").write(mod)
    print(f"removed comptime force-emit block from {mod_rel}")
else:
    print(f"no comptime force-emit block found in {mod_rel}")

# 2) in sa_std.zig, replace the module's individual lines with a loop block
sa = open(sa_path).read().split("\n")
pat = re.compile(r'^\s*_ = &@import\("sa_std/' + re.escape(mod_rel) + r'"\)\.([A-Za-z0-9_]+);$')
fns = []
keep = []
for l in sa:
    m2 = pat.match(l)
    if m2:
        fns.append(m2.group(1))
    else:
        keep.append(l)
print(f"{mod_rel}: found {len(fns)} force-emit lines in sa_std.zig")
if not fns:
    sys.exit(0)
# find the comptime keep-alive block start to insert the loop near it
# insert the loop block right where the first removed line was (approx: after
# the last remaining force-emit line of the previous module). Simplest: append
# the loop block at the end of the first comptime block that contains force-emit lines.
loop = [
    f"    // force-emit all fns of sa_std/{mod_rel} (loop over decls)",
    f"    {{",
    f"        const m = @import(\"sa_std/{mod_rel}\");",
    f"        inline for (@typeInfo(m).@\"struct\".decls) |d| {{",
    f"            const decl = @field(m, d.name);",
    f"            if (@typeInfo(@TypeOf(decl)) == .@\"fn\") {{",
    f"                _ = &decl;",
    f"            }}",
    f"        }}",
    f"    }}",
]
# find insertion point: the line index of the last remaining "_ = &@import" line
ins = None
for i, l in enumerate(keep):
    if "_ = &@import" in l:
        ins = i
if ins is None:
    ins = len(keep) - 1
keep[ins + 1:ins + 1] = loop
open(sa_path, "w").write("\n".join(keep))
print(f"inserted loop block after line {ins+1}; sa_std.zig now {len(keep)} lines")
