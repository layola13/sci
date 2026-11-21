#!/usr/bin/env python3
"""Repair the truncated splitMcpNamespace move:
take the 8-line body fragment left in sa_std.zig (after the alias line)
and append it to the fn signature in chat_norm.zig.
"""
sa = open("src/runtime/sa_std.zig").read().split("\n")
# find the alias line for splitMcpNamespace
ai = next(i for i, l in enumerate(sa) if "splitMcpNamespace" in l and "@import" in l)
# the fragment follows (skip blank lines), ends at a line that is exactly "}"
j = ai + 1
while sa[j].strip() == "":
    j += 1
start = j
while sa[j].strip() != "}":
    j += 1
end = j  # inclusive, the closing brace
frag = sa[start:end + 1]
print("fragment lines", start + 1, "..", end + 1, ":", len(frag), "lines")
assert frag[0].strip().startswith("if (!std.mem.startsWith"), frag[0]
del sa[start:end + 1]
open("src/runtime/sa_std.zig", "w").write("\n".join(sa))

cn = open("src/runtime/sa_std/chat_norm.zig").read().split("\n")
si = next(i for i, l in enumerate(cn) if l.startswith("fn splitMcpNamespace("))
cn[si + 1:si + 1] = frag
open("src/runtime/sa_std/chat_norm.zig", "w").write("\n".join(cn))
print("inserted fragment after chat_norm.zig line", si + 1)
