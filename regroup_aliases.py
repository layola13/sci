#!/usr/bin/env python3
"""Regroup all decl-alias lines in sa_std.zig into a single re-exports
section (grouped by module, 8 alias statements per line), placed right
after the module-import block at the top of the file.

Only touches lines matching: ^pub const NAME = @import("PATH").NAME;$
Module-import lines (no .NAME suffix) are left alone.
"""
import re, sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")
pat = re.compile(r'^pub const ([A-Za-z0-9_]+) = @import\("([^"]+)"\)\.\1;$')

groups = {}  # module -> [alias lines]
rest = []
for l in lines:
    m = pat.match(l)
    if m:
        groups.setdefault(m.group(2), []).append(l)
    else:
        rest.append(l)
total = sum(len(v) for v in groups.values())
print(f"alias lines: {total} in {len(groups)} modules")

# build the re-exports section
section = ["", "// Re-exports: decls moved to sa_std/* submodules (grouped by module)."]
for mod in sorted(groups):
    section.append(f"// --- {mod} ---")
    run = groups[mod]
    for j in range(0, len(run), N):
        section.append(" ".join(run[j:j + N]))
section.append("")

# insertion point: after the last module-import line near the top
# (a line matching ^(pub )?const \w+ = @import\("..."\) without .NAME)
imp_pat = re.compile(r'^(?:pub )?const [A-Za-z0-9_]+ = @import\("[^"]*"\);$')
ins = None
for i, l in enumerate(rest[:120]):
    if imp_pat.match(l):
        ins = i
if ins is None:
    raise SystemExit("no module-import line found near top")
rest[ins + 1:ins + 1] = section
open(sa_path, "w").write("\n".join(rest))
saved = total - (len(section) - 2 - len(groups))
print(f"section: {len(section)} lines; saved {saved} lines; sa_std.zig now {len(rest)} lines")
