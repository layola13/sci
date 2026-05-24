const std = @import("std");
const fetch = @import("fetch.zig");
const plugin_api = @import("plugin_api.zig");
const plugin_helpers = @import("plugin_helpers.zig");

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "package install",
        .summary = "Project dependency installation and offline mirroring",
        .items = &.{
            "install",
            "install <identity>",
            "install --ref <ref>",
            "install --offline",
            "install -g <identity>",
            "fetch <identity>",
            "fetch --ref <ref>",
            "fetch --offline",
            "fetch -g <identity>",
        },
    },
};

fn parseFetchArgs(args: []const []const u8) !struct { options: fetch.FetchOptions, identity: []const u8, ref: []const u8 } {
    var options: fetch.FetchOptions = .{};
    var identity: ?[]const u8 = null;
    var ref: []const u8 = "HEAD";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-g")) {
            options.global = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--offline")) {
            options.offline = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--ref")) {
            if (i + 1 >= args.len) return error.MissingRef;
            ref = args[i + 1];
            i += 1;
            continue;
        }
        if (identity == null) {
            identity = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }

    const id = identity orelse return error.MissingSourcePath;
    return .{ .options = options, .identity = id, .ref = ref };
}

fn runFetchCommand(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "fetch")) return null;

    const parsed = try parseFetchArgs(argv[2..]);
    var result = try fetch.fetchPackage(ctx.allocator, parsed.identity, parsed.ref, parsed.options);
    defer result.deinit(ctx.allocator);
    try stdout.print("{s}\n", .{result.root});
    _ = stderr;
    return 0;
}

fn pkgPrebuildHook(ctx: *const plugin_api.Context, compile_options: *anyopaque) !void {
    _ = compile_options;
    const pkg_dir = try std.fs.path.join(ctx.allocator, &.{ ".sa", "pkg" });
    defer ctx.allocator.free(pkg_dir);
    try std.fs.cwd().makePath(pkg_dir);
}

fn runPkgPrebuildHookAbi(ctx: *const plugin_api.Context, compile_options: ?*anyopaque) callconv(.c) u32 {
    var dummy: u8 = 0;
    const opts: *anyopaque = if (compile_options) |p| p else @ptrCast(&dummy);
    pkgPrebuildHook(ctx, opts) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    return @intFromEnum(plugin_api.AbiStatus.ok);
}

fn runFetchCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    const args = argv[0..argv_len];
    var args_owned = std.ArrayList([]const u8).init(ctx.allocator);
    defer args_owned.deinit();
    for (args) |arg| args_owned.append(std.mem.span(arg)) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    var stdout_storage: plugin_helpers.StreamWriterCtx = undefined;
    var stderr_storage: plugin_helpers.StreamWriterCtx = undefined;
    const stdout_writer = plugin_helpers.makeAnyWriter(stdout, &stdout_storage) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const stderr_writer = plugin_helpers.makeAnyWriter(stderr, &stderr_storage) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const result = runFetchCommand(ctx, args_owned.items, stdout_writer, stderr_writer) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

pub const plugin = plugin_api.Plugin{
    .name = "fetch",
    .handleCommand = runFetchCommand,
    .skills = &skills,
};

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "fetch",
    .init = null,
    .prebuild = runPkgPrebuildHookAbi,
    .postbuild = null,
    .handle_command = runFetchCommandAbi,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;

test "pkg plugin exports runtime descriptor" {
    const exported = saasm_plugin_descriptor_v1;
    try std.testing.expectEqual(plugin_api.abi_version, exported.abi_version);
    try std.testing.expectEqualStrings("fetch", std.mem.span(exported.name));
    try std.testing.expectEqual(@as(usize, 1), exported.skills_len);
    try std.testing.expectEqualStrings("package install", exported.skills_ptr[0].name);
    try std.testing.expectEqualStrings("install", exported.skills_ptr[0].items[0]);
    try std.testing.expect(exported.prebuild != null);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const rc = runPkgPrebuildHookAbi(&ctx, null);
    try std.testing.expectEqual(@intFromEnum(plugin_api.AbiStatus.ok), rc);
    var pkg_dir = try std.fs.cwd().openDir(".sa/pkg", .{});
    defer pkg_dir.close();
}
