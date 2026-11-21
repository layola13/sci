#!/usr/bin/env python3
"""Fix var-alias problem:
1) delete const aliases in sa_std.zig that point at a `var` in a submodule
   (a const alias to a var is not comptime-resolvable and breaks test builds)
2) in sa_std_tests.zig, repoint uses of those vars to import from the
   owning submodule directly.
"""
import re

sa = open("src/runtime/sa_std.zig").read().split("\n")
# find all const aliases in sa_std.zig
alias_re = re.compile(r'^pub const ([A-Za-z0-9_]+) = @import\("sa_std/([A-Za-z0-9_]+)\.zig"\)\.([A-Za-z0-9_]+);$')
bad = []  # (line_idx, name, module)
for i, l in enumerate(sa):
    m = alias_re.match(l)
    if m and m.group(1) == m.group(3):
        mod = f"src/runtime/sa_std/{m.group(2)}.zig"
        try:
            txt = open(mod).read()
        except FileNotFoundError:
            continue
        # is the target a var?
        if re.search(r"^(?:pub\s+)?(?:threadlocal\s+)?var " + re.escape(m.group(1)) + r"\b", txt, re.M):
            bad.append((i, m.group(1), m.group(2)))
print("var aliases to delete:", bad)
for i, name, mod in sorted(bad, reverse=True):
    del sa[i]
open("src/runtime/sa_std.zig", "w").write("\n".join(sa))

# repoint uses in sa_std_tests.zig
t = "src/runtime/sa_std/sa_std_tests.zig"
tl = open(t).read().split("\n")
# add pthread import after the std import if not present
if not any(l.startswith('const pthread = @import("pthread.zig");') for l in tl):
    for i, l in enumerate(tl):
        if l == 'const std = @import("std");':
            tl.insert(i + 1, 'const pthread = @import("pthread.zig");')
            break
for i, name, mod in bad:
    pass
# generic: for each deleted var, replace sa_std.<name> with <mod>.<name>
# (module alias is the file base name)
for _, name, mod in bad:
    tl = [l.replace(f"sa_std.{name}", f"{mod}.{name}") for l in tl]
open(t, "w").write("\n".join(tl))
print("repointed uses in sa_std_tests.zig")
