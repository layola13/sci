const std = @import("std");
const bc2sa = @import("llvm2sa.zig");
const plugin_api = @import("plugin_api.zig");
const plugin_helpers = @import("llvm2sa/plugin_helpers.zig");

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "bc2sa",
        .summary = "Translate LLVM bitcode back into SA source",
        .items = &.{
            "bc2sa <file.bc>",
            "bitcode-only input",
            "stdout emits translated SA source",
        },
    },
};

const StreamCtx = struct {
    stream: plugin_api.HostStream,
};

const CaptureCtx = struct {
    buffer: *std.ArrayList(u8),
};

fn writeAll(ctx: *const anyopaque, bytes: []const u8) anyerror!usize {
    const self = @as(*const StreamCtx, @ptrCast(@alignCast(ctx)));
    const write_all = self.stream.write_all orelse return error.WriteFailed;
    if (write_all(self.stream.ctx, bytes.ptr, bytes.len) != @intFromEnum(plugin_api.AbiStatus.ok)) return error.WriteFailed;
    return bytes.len;
}

fn captureWriteAll(ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32 {
    const self = @as(*CaptureCtx, @ptrCast(@alignCast(ctx.?)));
    self.buffer.appendSlice(bytes[0..len]) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    return @intFromEnum(plugin_api.AbiStatus.ok);
}

fn makeCaptureStream(ctx: *CaptureCtx) plugin_api.HostStream {
    return .{ .ctx = ctx, .write_all = captureWriteAll };
}

fn cArgvToSlice(argv: []const [*:0]const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    var out = try allocator.alloc([]const u8, argv.len);
    errdefer allocator.free(out);
    for (argv, 0..) |arg, idx| {
        out[idx] = std.mem.span(arg);
    }
    return out;
}

fn runLlvm2SaCommand(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    _ = stdout;
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "bc2sa")) return null;
    if (argv.len < 3) return error.MissingSourcePath;
    _ = bc2sa.translateBitcodeFile(ctx.allocator, argv[2]) catch |err| {
        try stderr.print("error: {s}\n", .{@errorName(err)});
        return 1;
    };
    unreachable;
}

fn runLlvm2SaCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    var stdout_ctx = StreamCtx{ .stream = stdout };
    var stderr_ctx = StreamCtx{ .stream = stderr };
    const stdout_writer = std.io.AnyWriter{ .context = &stdout_ctx, .writeFn = writeAll };
    const stderr_writer = std.io.AnyWriter{ .context = &stderr_ctx, .writeFn = writeAll };
    const args = cArgvToSlice(argv[0..argv_len], ctx.allocator) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer ctx.allocator.free(args);

    const result = runLlvm2SaCommand(ctx, args, stdout_writer, stderr_writer) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "bc2sa",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runLlvm2SaCommandAbi,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;

test "bc2sa plugin exports runtime descriptor and skills" {
    const exported = saasm_plugin_descriptor_v1;
    try std.testing.expectEqual(plugin_api.abi_version, exported.abi_version);
    try std.testing.expectEqualStrings("bc2sa", std.mem.span(exported.name));
    try std.testing.expectEqual(@as(usize, 1), exported.skills_len);
    try std.testing.expectEqualStrings("bc2sa", exported.skills_ptr[0].name);
    try std.testing.expectEqualStrings("bc2sa <file.bc>", exported.skills_ptr[0].items[0]);
}
