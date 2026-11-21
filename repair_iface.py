#!/usr/bin/env python3
"""Repair the truncated buildInterfaceAddressesJson move:
append its missing tail (3 lines) before `const struct_sockaddr` in iface_json.zig.
"""
lines = open("src/runtime/sa_std/iface_json.zig").read().split("\n")
idx = next(i for i, l in enumerate(lines) if l.startswith("const struct_sockaddr"))
tail = ["", "    try list.append(']');", "    return list.toOwnedSlice();", "}", ""]
lines[idx:idx] = tail
open("src/runtime/sa_std/iface_json.zig", "w").write("\n".join(lines))
print("inserted fn tail before struct_sockaddr at line", idx + 1)
