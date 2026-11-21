#!/usr/bin/env python3
"""Batch-convert all per-fn force-emit lines in sa_std.zig into one
comptime loop block per module (std.meta.declarations), for every module
that has >= 3 force-emit lines. Modules with < 3 lines keep individual lines.

The loop blocks are inserted at the end of the keep-alive comptime block
(just before its closing brace, after the last force-emit line).
"""
import re

sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")

# group force-emit lines by module path
pat = re.compile(r'^(\s*)_ = &@import\("([^"]+)"\)\.([A-Za-z0-9_]+);$')
groups = {}  # module -> list of fn names
keep = []
for l in lines:
    m = pat.match(l)
    # keep the Linux-only sa_net_uring line in place (inside its if block)
    if m and "sa_net_uring.zig" in m.group(2):
        keep.append(l)
        continue
    if m:
        groups.setdefault(m.group(2), []).append(m.group(3))
    else:
        keep.append(l)
print(f"modules with force-emit lines: {len(groups)}")
total = sum(len(v) for v in groups.values())
print(f"total force-emit lines: {total}")

# build loop blocks for modules with >= 3 lines
loops = []
for mod, fns in sorted(groups.items()):
    if len(fns) < 3:
        continue
    loops.append((mod, [
        f"    // force-emit all fns of {mod} ({len(fns)} fns, loop over decls)",
        "    {",
        f'        const m = @import("{mod}");',
        "        for (std.meta.declarations(m)) |decl_name| {",
        "            _ = &@field(m, decl_name);",
        "        }",
        "    }",
    ]))
print(f"loop blocks: {len(loops)} (modules with >=3 lines)")
saved = sum(len(groups[m]) for m, _ in loops) - sum(len(b) for _, b in loops)
print(f"lines saved: {saved}")

# re-insert the <3-line modules' individual lines + loop blocks
# Find the keep-alive comptime block: it contains the remaining force-emit
# lines. Insert loops after the last remaining force-emit line in keep.
# First, re-add the small modules' lines to keep (they were removed above).
small = []
for mod, fns in sorted(groups.items()):
    if len(fns) < 3:
        for f in fns:
            small.append(f'    _ = &@import("{mod}").{f};')
print(f"small modules kept as individual lines: {len(small)}")

# find insertion point: just before the `if (builtin.os.tag == .linux) {`
# line inside the keep-alive comptime block (after the force-emit lines).
ins = None
for i, l in enumerate(keep):
    if l.strip() == "if (builtin.os.tag == .linux) {" and i > 200 and i < 2000:
        ins = i
        break
if ins is None:
    raise SystemExit("cannot find the linux-if insertion point")
# insert small lines + loop blocks just before the linux-if line
block = small[:]
for _, b in loops:
    block.extend(b)
keep[ins:ins] = block
open(sa_path, "w").write("\n".join(keep))
print(f"sa_std.zig now {len(keep)} lines")
