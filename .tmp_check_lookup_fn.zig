const std = @import("std");
const plugin_api = @import("src/plugin_api.zig");

pub fn main() !void {
    var lib = try std.DynLib.open("/home/vscode/projects/sci/.tmp_plugin_check/libalpha.so");
    defer lib.close();
    if (lib.lookup(plugin_api.DescriptorFn, "saasm_plugin_descriptor_v1_fn")) |fn_ptr| {
        std.debug.print("fn_ptr=0x{x}\n", .{@intFromPtr(fn_ptr)});
    } else {
        std.debug.print("missing\n", .{});
    }
}
