lines = open("src/emit_js.zig").read().split("\n")

# Ident helpers block: from 'fn isJsReserved' to just before 'const FuncTask'.
s = None
for i, l in enumerate(lines):
    if l.startswith("fn isJsReserved("):
        s = i
        break
assert s is not None
# include the doc comment above isJsReserved if present
while s > 0 and lines[s-1].startswith("///"):
    s -= 1
e = None
for j in range(s, len(lines)):
    if lines[j].startswith("const FuncTask"):
        e = j
        break
assert e is not None
print(f"ident block: lines {s+1}..{e} ({e - s} lines)")

# Collect function names in the block
import re
names = []
for l in lines[s:e]:
    m = re.match(r'^fn ([A-Za-z0-9_]+)\(', l)
    if m:
        names.append(m.group(1))
print("functions:", names)

# Build ident.zig
out = []
out.append("const std = @import(\"std\");")
out.append("const inst = @import(\"../common/instruction.zig\");")
out.append("const sig = @import(\"../common/signature.zig\");")
out.append("const const_decl = @import(\"../common/const_decl.zig\");")
out.append("")
block = lines[s:e]
# make each top-level fn pub
for idx, l in enumerate(block):
    if l.startswith("fn "):
        block[idx] = "pub " + l
out.extend(block)
text = "\n".join(out)
# strip trailing blank lines, ensure single trailing newline
text = text.rstrip("\n") + "\n"
nlines = text.count("\n")
print(f"ident.zig: {nlines} lines")
assert nlines <= 700
open("src/emit_js/ident.zig", "w").write(text)

# Replace block in emit_js.zig with direct imports (so call sites unchanged).
imports = []
for n in names:
    imports.append(f'const {n} = @import("emit_js/ident.zig").{n};')
lines[s:e] = imports
open("src/emit_js.zig", "w").write("\n".join(lines))
print(f"replaced ident block with {len(imports)} imports")
print("done")
