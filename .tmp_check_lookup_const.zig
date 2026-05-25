const std = @import("std");
const plugin_api = @import("plugin_api.zig");

pub fn main() !void {
    var lib = try std.DynLib.open("/home/vscode/projects/sci/.tmp_plugin_check/libalpha_const.so");
    defer lib.close();
    const ptr = lib.lookup(plugin_api.DescriptorPtr, "saasm_plugin_descriptor_v1") orelse return error.Missing;
    std.debug.print("addr=0x{x} abi={} size={} name_ptr=0x{x} skills_ptr=0x{x} len={}\n", .{@intFromPtr(ptr), ptr.abi_version, ptr.descriptor_size, @intFromPtr(ptr.name), @intFromPtr(ptr.skills_ptr), ptr.skills_len});
    std.debug.print("name={s}\n", .{std.mem.span(ptr.name)});
}
