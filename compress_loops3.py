#!/usr/bin/env python3
"""Compress 7-line force-emit loop blocks in sa_std.zig to one line each.
Pattern (insert_loop_emit.py output):
    // force-emit all fns of <path> (loop over decls)
    {
        const m = @import("<path>");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
->  { const m = @import("<path>"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
Skips any block whose body contains 'if (' (special guard, e.g. setTsDir).
"""
import re

path = "src/runtime/sa_std.zig"
text = open(path).read()
pat = re.compile(
    r'    // force-emit all fns of ([^\s]+) \(loop over decls\)\n'
    r'    \{\n'
    r'        const m = @import\("\1"\);\n'
    r'        for \(std\.meta\.declarations\(m\)\) \|decl_name\| \{\n'
    r'            _ = &@field\(m, decl_name\);\n'
    r'        \}\n'
    r'    \}\n'
)
count = 0
def repl(m):
    global count
    p = m.group(1)
    count += 1
    return f'    {{ const m = @import("{p}"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }}\n'

new_text, n = pat.subn(repl, text)
print(f"compressed {n} blocks")
open(path, "w").write(new_text)
print(f"lines: {len(text.splitlines())} -> {len(new_text.splitlines())}")
