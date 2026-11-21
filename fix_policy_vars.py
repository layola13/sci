#!/usr/bin/env python3
"""Fix the 4 policy var aliases in sa_std.zig:
- delete the const aliases (a const alias to a var is not comptime-resolvable)
- repoint the @export use to the policy module alias.
"""
sa = open("src/runtime/sa_std.zig").read().split("\n")
names = ["policy_context_storage", "policy_bootstrap_attempted",
         "sigpipe_ignore_installed", "policy_bootstrap_init_entry"]
for name in names:
    for i, l in enumerate(sa):
        if l == f'pub const {name} = @import("sa_std/policy.zig").{name};':
            del sa[i]
            print(f"deleted alias {name} at line {i+1}")
            break
# add module alias after the std import if not present
if not any(l.startswith('const policy = @import("sa_std/policy.zig");') for l in sa):
    for i, l in enumerate(sa):
        if l == 'const std = @import("std");':
            sa.insert(i + 1, 'const policy = @import("sa_std/policy.zig");')
            print("added policy module alias")
            break
# repoint the @export use
for i, l in enumerate(sa):
    if "@export(&policy_bootstrap_init_entry" in l:
        sa[i] = l.replace("&policy_bootstrap_init_entry", "&policy.policy_bootstrap_init_entry")
        print(f"repointed @export at line {i+1}")
open("src/runtime/sa_std.zig", "w").write("\n".join(sa))
