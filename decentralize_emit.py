#!/usr/bin/env python3
"""Decentralize force-emit: move a module's `_ = &@import(...).fn;` lines
from sa_std.zig into the module itself as a comptime block that takes
the address of its own fns (bare names). This forces the compiler to
emit the pub export fns into libsa_std.a without the parent's keep-alive.

Usage: decentralize_emit.py <module.zig>   (path relative to src/runtime/sa_std/)
The module's own fns are found by scanning its pub export fn decls.
"""
import re, sys

mod_rel = sys.argv[1]  # e.g. json.zig
mod_path = f"src/runtime/sa_std/{mod_rel}"
sa_path = "src/runtime/sa_std.zig"

sa = open(sa_path).read().split("\n")
# find force-emit lines for this module
pat = re.compile(r'^\s*_ = &@import\("sa_std/' + re.escape(mod_rel) + r'"\)\.([A-Za-z0-9_]+);$')
fns = []
keep = []
for l in sa:
    m = pat.match(l)
    if m:
        fns.append(m.group(1))
    else:
        keep.append(l)
print(f"{mod_rel}: found {len(fns)} force-emit lines in sa_std.zig")
if not fns:
    sys.exit(0)
# verify the fns are defined in the module (pub export fn or pub fn)
mod = open(mod_path).read()
missing = [f for f in fns if not re.search(r"(?:pub export fn|pub fn) " + re.escape(f) + r"\b", mod)]
if missing:
    print(f"WARNING: {len(missing)} fns not defined in {mod_rel}: {missing[:5]}")
    sys.exit(1)
# append comptime block to the module
block = ["", "// Force-emit the pub export fns into libsa_std.a (Zig lazy analysis",
         "// does not emit a child module's pub export fn unless referenced).",
         "comptime {"] + [f"    _ = &{f};" for f in fns] + ["}"]
with open(mod_path, "a") as f:
    f.write("\n".join(block) + "\n")
open(sa_path, "w").write("\n".join(keep))
print(f"moved {len(fns)} force-emit lines into {mod_rel}; sa_std.zig now {len(keep)} lines")
