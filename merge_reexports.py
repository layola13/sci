#!/usr/bin/env python3
"""Merge all re-exports sections in sa_std.zig into ONE section.
Collects every alias statement (incl. those on multi-alias lines),
groups by module, and emits 8 per line with // --- headers.
"""
import re

sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")
alias_re = re.compile(r'pub const ([A-Za-z0-9_]+) = @import\("([^"]+)"\)\.\1;')

# collect all alias statements from the whole file, grouped by module
groups = {}
rest = []
for l in lines:
    if 'pub const ' in l and '@import(' in l:
        # split the line into individual alias statements
        stmts = alias_re.findall(l)
        # check if the line is ONLY alias statements (possibly several)
        stripped = alias_re.sub("", l).strip()
        if stripped == "" and stmts:
            for name, mod in stmts:
                groups.setdefault(mod, []).append(f'pub const {name} = @import("{mod}").{name};')
            continue
    rest.append(l)
total = sum(len(v) for v in groups.values())
print(f"alias statements: {total} in {len(groups)} modules")

# build the single section
section = ["", "// Re-exports: decls moved to sa_std/* submodules (grouped by module)."]
for mod in sorted(groups):
    section.append(f"// --- {mod} ---")
    run = groups[mod]
    for j in range(0, len(run), 8):
        section.append(" ".join(run[j:j + 8]))
section.append("")

# remove any leftover "// Re-exports:" / "// ---" header lines from rest
rest = [l for l in rest if not l.startswith("// Re-exports:") and not l.startswith("// --- ")]
# insertion point: after the last module-import line near the top
imp_pat = re.compile(r'^(?:pub )?const [A-Za-z0-9_]+ = @import\("[^"]*"\);$')
ins = None
for i, l in enumerate(rest[:120]):
    if imp_pat.match(l):
        ins = i
if ins is None:
    raise SystemExit("no module-import line found near top")
rest[ins + 1:ins + 1] = section
open(sa_path, "w").write("\n".join(rest))
print(f"sa_std.zig now {len(rest)} lines")
