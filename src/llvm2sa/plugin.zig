const std = @import("std");
const plugin_api = @import("plugin");

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "llvm2sa",
        .summary = "Translate text LLVM IR back into SA source",
        .items = &.{
            "llvm2sa <file.ll>",
            "line-oriented translation",
            "stdout emits translated SA source",
        },
    },
};

const llvm2sa = @import("translate.zig");

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

fn runLlvm2SaCommand(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    _ = stderr;
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "llvm2sa")) return null;
    if (argv.len < 3) return error.MissingSourcePath;
    const translated = try llvm2sa.translateFile(ctx.allocator, argv[2]);
    defer ctx.allocator.free(translated);
    try stdout.writeAll(translated);
    if (translated.len == 0 or translated[translated.len - 1] != '\n') try stdout.writeByte('\n');
    return 0;
}

fn cArgvToSlice(argv: []const [*:0]const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    const slice = argv;
    var out = try allocator.alloc([]const u8, slice.len);
    errdefer allocator.free(out);
    for (slice, 0..) |arg, idx| {
        out[idx] = std.mem.span(arg);
    }
    return out;
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

pub const plugin = plugin_api.Plugin{
    .name = "llvm2sa",
    .handleCommand = runLlvm2SaCommand,
    .skills = &skills,
};

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "llvm2sa",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runLlvm2SaCommandAbi,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;

test "llvm2sa command and abi wrapper match on the hello fixture" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, ".probe_wasm2/hello.wasm.saasm.ll");
    defer std.testing.allocator.free(source_path);
    const expected_path = try original_cwd.realpathAlloc(std.testing.allocator, "tests/llvm2sa_expected_hello.saasm");
    defer std.testing.allocator.free(expected_path);

    const expected_file = try std.fs.cwd().openFile(expected_path, .{});
    defer expected_file.close();
    const expected = try expected_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(expected);

    const args = [_][]const u8{ "saasm", "llvm2sa", source_path };
    var native_stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer native_stdout.deinit();
    var native_stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer native_stderr.deinit();

    const native_result = try runLlvm2SaCommand(
        &plugin_api.Context{ .allocator = std.testing.allocator },
        args[0..],
        native_stdout.writer().any(),
        native_stderr.writer().any(),
    );
    try std.testing.expectEqual(@as(?u8, 0), native_result);
    try std.testing.expectEqualStrings(expected, native_stdout.items);
    try std.testing.expectEqual(@as(usize, 0), native_stderr.items.len);

    var abi_stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer abi_stdout.deinit();
    var abi_stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer abi_stderr.deinit();
    var out_code: u8 = 255;
    var stdout_ctx = CaptureCtx{ .buffer = &abi_stdout };
    var stderr_ctx = CaptureCtx{ .buffer = &abi_stderr };
    const source_c = try std.testing.allocator.dupeZ(u8, source_path);
    defer std.testing.allocator.free(source_c);
    const c_argv = [_][*:0]const u8{ "saasm", "llvm2sa", source_c };
    const abi_status = runLlvm2SaCommandAbi(
        &plugin_api.Context{ .allocator = std.testing.allocator },
        c_argv[0..].ptr,
        c_argv.len,
        makeCaptureStream(&stdout_ctx),
        makeCaptureStream(&stderr_ctx),
        &out_code,
    );
    try std.testing.expectEqual(@as(u32, @intFromEnum(plugin_api.AbiStatus.ok)), abi_status);
    try std.testing.expectEqual(@as(u8, 0), out_code);
    try std.testing.expectEqualStrings(expected, abi_stdout.items);
    try std.testing.expectEqualStrings("", abi_stderr.items);
}

test "llvm2sa unknown command stays unknown through native and abi paths" {
    const args = [_][]const u8{ "saasm", "not-llvm2sa", "ignored.ll" };
    const native_result = try runLlvm2SaCommand(
        &plugin_api.Context{ .allocator = std.testing.allocator },
        args[0..],
        std.io.null_writer.any(),
        std.io.null_writer.any(),
    );
    try std.testing.expectEqual(@as(?u8, null), native_result);

    var out_code: u8 = 99;
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    var stdout_ctx = CaptureCtx{ .buffer = &stdout_buf };
    var stderr_ctx = CaptureCtx{ .buffer = &stderr_buf };
    const ignored_c = try std.testing.allocator.dupeZ(u8, "ignored.ll");
    defer std.testing.allocator.free(ignored_c);
    const c_argv = [_][*:0]const u8{ "saasm", "not-llvm2sa", ignored_c };

    const abi_status = runLlvm2SaCommandAbi(
        &plugin_api.Context{ .allocator = std.testing.allocator },
        c_argv[0..].ptr,
        c_argv.len,
        makeCaptureStream(&stdout_ctx),
        makeCaptureStream(&stderr_ctx),
        &out_code,
    );
    try std.testing.expectEqual(@as(u32, @intFromEnum(plugin_api.AbiStatus.unknown_command)), abi_status);
    try std.testing.expectEqual(@as(u8, 99), out_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}
