const std = @import("std");
const plugin_api = @import("plugin_api.zig");
const skills = [_]plugin_api.SkillSection{ .{ .name = "alpha", .summary = "s", .items = &.{"a"} } };
fn runCommand(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    _ = ctx; _ = argv; _ = argv_len; _ = stdout; _ = stderr; out_code.* = 0; return @intFromEnum(plugin_api.AbiStatus.ok);
}
const descriptor = plugin_api.PluginDescriptor{ .abi_version = plugin_api.abi_version, .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))), .name = "alpha", .init = null, .prebuild = null, .postbuild = null, .handle_command = runCommand, .skills_ptr = skills[0..].ptr, .skills_len = skills.len };
pub export const saasm_plugin_descriptor_v1: plugin_api.PluginDescriptor = descriptor;
pub export fn saasm_plugin_descriptor_v1_fn(out: *plugin_api.PluginDescriptor) callconv(.c) void { out.* = saasm_plugin_descriptor_v1; }
