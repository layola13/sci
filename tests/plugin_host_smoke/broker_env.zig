const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const writeSource = helpers.writeSource;
const targetArtifactKey = helpers.targetArtifactKey;
const dynLibInstallPath = helpers.dynLibInstallPath;
const expectInstallCode = helpers.expectInstallCode;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

test "runtime broker env_get enforces declared env permissions" {
    const test_start = startTimedTest("runtime broker env_get enforces declared env permissions");
    defer endTimedTest("runtime broker env_get enforces declared env permissions", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "broker/src");
    try writeSource(tmp.dir, "broker/build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const root_module = b.createModule(.{
        \\        .root_source_file = b.path("src/plugin.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    const lib = b.addLibrary(.{
        \\        .name = "broker_env",
        \\        .root_module = root_module,
        \\        .linkage = .dynamic,
        \\    });
        \\    b.installArtifact(lib);
        \\}
        \\
    );
    try writeSource(tmp.dir, "broker/src/plugin.zig",
        \\const std = @import("std");
        \\
        \\const SkillSection = struct {
        \\    name: []const u8,
        \\    summary: []const u8,
        \\    items: []const []const u8,
        \\};
        \\
        \\const BrokerCallFn = *const fn (ctx: ?*anyopaque, op: u32, req: ?*const anyopaque, resp: ?*anyopaque) callconv(.c) u32;
        \\
        \\const Context = struct {
        \\    allocator: std.mem.Allocator,
        \\    host_version: ?[]const u8 = null,
        \\    log: ?*const fn (ctx: *const anyopaque, level: u8, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
        \\    log_ctx: ?*anyopaque = null,
        \\    json_mode: bool = false,
        \\    broker_abi_version: u32 = 0,
        \\    broker_call: ?BrokerCallFn = null,
        \\    broker_ctx: ?*anyopaque = null,
        \\};
        \\
        \\const HostStream = extern struct {
        \\    ctx: ?*anyopaque,
        \\    write_all: ?*const fn (ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32,
        \\};
        \\
        \\const BrokerEnvGetRequest = extern struct {
        \\    name_ptr: [*]const u8,
        \\    name_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerEnvGetResponse = extern struct {
        \\    value_len: usize,
        \\};
        \\
        \\const PluginDescriptor = extern struct {
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\    init: ?*const fn (ctx: *const Context) callconv(.c) u32,
        \\    prebuild: ?*const fn (ctx: *const Context, compile_options: ?*anyopaque) callconv(.c) u32,
        \\    postbuild: ?*const fn (ctx: *const Context) callconv(.c) u32,
        \\    handle_command: ?*const fn (ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32,
        \\    skills_ptr: [*]const SkillSection,
        \\    skills_len: usize,
        \\};
        \\
        \\const skills = [_]SkillSection{};
        \\
        \\const BrokerResult = struct {
        \\    status: u32,
        \\    value_len: usize,
        \\};
        \\
        \\fn writeAll(stream: HostStream, bytes: []const u8) u32 {
        \\    const write_fn = stream.write_all orelse return 2;
        \\    return write_fn(stream.ctx, bytes.ptr, bytes.len);
        \\}
        \\
        \\fn brokerEnvGet(ctx: *const Context, name: []const u8, buffer: []u8) BrokerResult {
        \\    const broker_call = ctx.broker_call orelse return .{ .status = 2, .value_len = 0 };
        \\    var response = BrokerEnvGetResponse{ .value_len = 0 };
        \\    const request = BrokerEnvGetRequest{
        \\        .name_ptr = name.ptr,
        \\        .name_len = name.len,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    return .{
        \\        .status = broker_call(ctx.broker_ctx, 1, &request, &response),
        \\        .value_len = response.value_len,
        \\    };
        \\}
        \\
        \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = stderr;
        \\    if (argv_len < 2 or !std.mem.eql(u8, std.mem.span(argv[1]), "broker-env")) return 1;
        \\    if (argv_len < 3) return 2;
        \\
        \\    var buffer: [256]u8 = undefined;
        \\    const result = brokerEnvGet(ctx, std.mem.span(argv[2]), buffer[0..]);
        \\    switch (result.status) {
        \\        0 => {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..result.value_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        },
        \\        1 => {
        \\            out_code.* = 41;
        \\            if (writeAll(stdout, "DENIED\n") != 0) return 2;
        \\            return 0;
        \\        },
        \\        4 => {
        \\            out_code.* = 42;
        \\            if (writeAll(stdout, "NOT_FOUND\n") != 0) return 2;
        \\            return 0;
        \\        },
        \\        5 => {
        \\            out_code.* = 43;
        \\            if (writeAll(stdout, "BUFFER\n") != 0) return 2;
        \\            return 0;
        \\        },
        \\        else => {
        \\            out_code.* = 44;
        \\            return 2;
        \\        },
        \\    }
        \\}
        \\
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "broker-env",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = handle,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
    );
    const broker_env_artifact = try dynLibInstallPath(std.testing.allocator, "broker_env");
    defer std.testing.allocator.free(broker_env_artifact);
    const broker_env_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "broker-env",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [],
        \\    "net": [
        \\      {{ "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }}
        \\    ],
        \\    "env": ["SA_BROKER_*"],
        \\    "process": {{ "spawn": false, "exec": [] }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), broker_env_artifact });
    defer std.testing.allocator.free(broker_env_manifest);
    try writeSource(tmp.dir, "broker/sap.json", broker_env_manifest);

    const home_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_home = try saveEnvVarZ(std.testing.allocator, home_name);
    defer {
        if (saved_home) |value| {
            setEnvVarZ(home_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(home_name);
        }
    }
    try setEnvVarZ(home_name, "state");

    const dev_name: [:0]const u8 = "SA_PLUGIN_DEV";
    const saved_dev = try saveEnvVarZ(std.testing.allocator, dev_name);
    defer {
        if (saved_dev) |value| {
            setEnvVarZ(dev_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(dev_name);
        }
    }
    try setEnvVarZ(dev_name, "1");

    const broker_env_name: [:0]const u8 = "SA_BROKER_ALLOWED";
    const saved_broker_env = try saveEnvVarZ(std.testing.allocator, broker_env_name);
    defer {
        if (saved_broker_env) |value| {
            setEnvVarZ(broker_env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(broker_env_name);
        }
    }
    try setEnvVarZ(broker_env_name, "broker-secret");
    unsetEnvVarZ("SA_BROKER_MISSING");

    var install_output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer install_output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "broker", sio.managedWriter(&install_output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, install_code, install_output.items);

    var runtime = try saasm.plugins.Runtime.initFromEnv(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectEqual(@as(usize, 1), runtime.plugins.items.len);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const allowed_code = try runtime.dispatchCommand(
        &.{ "sa", "broker-env", "SA_BROKER_ALLOWED" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 0), allowed_code);
    try std.testing.expectEqualStrings("broker-secret\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const denied_code = try runtime.dispatchCommand(
        &.{ "sa", "broker-env", "HOME" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 41), denied_code);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const missing_code = try runtime.dispatchCommand(
        &.{ "sa", "broker-env", "SA_BROKER_MISSING" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 42), missing_code);
    try std.testing.expectEqualStrings("NOT_FOUND\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
