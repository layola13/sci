const std = @import("std");
const Binding = @import("binding_types.zig").Binding;

pub fn bindingForMemSignalDlopen(name: []const u8) ?Binding {
    const all_void: u64 = ~@as(u64, 0);
    return     if (std.mem.eql(u8, name, "memcpy"))
        // The libc copy primitive (sa_std core/mem.sa's
        // @sa_mem_copy_nonoverlapping binds here): a real copy
        // inside guest memory, bounds-checked on both ranges;
        // returns the destination like C memcpy.
        .{ .voids = all_void ^ 0b111, .tag = .memcpy }
    else if (std.mem.eql(u8, name, "sa_mem_free"))
        // The one sa_std allocator extern: bound to the emitter's own
        // free-list sa_free so C-route drops actually release memory
        // (without this binding every @sa_vec_free trapped).
        .{ .voids = all_void ^ 0b1, .tag = .mem_free }
    else if (std.mem.eql(u8, name, "signal"))
        .{ .voids = all_void ^ 0b1, .tag = .signal }
    else if (std.mem.eql(u8, name, "dlopen"))
        .{ .voids = all_void, .tag = .dlopen }
    else if (std.mem.eql(u8, name, "dlsym"))
        .{ .voids = all_void, .tag = .dlsym }
    else if (std.mem.eql(u8, name, "dlclose"))
        .{ .voids = all_void, .tag = .dlclose }
    else if (std.mem.eql(u8, name, "sa_parse_float"))
        .{ .voids = all_void ^ 0b11, .tag = .parse_float }
    else
        null;
}
