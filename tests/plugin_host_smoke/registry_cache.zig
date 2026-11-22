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

test "language frontend registry resolves extensions and reports conflicts" {
    const allocator = std.testing.allocator;
    var runtime = saasm.plugins.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.registerLanguageFrontend("sla", &.{".sla"});
    try std.testing.expectEqualStrings("sla", runtime.languageFrontendForExtension(".sla").?);
    try std.testing.expect(runtime.languageFrontendForExtension(".xyz") == null);
    try runtime.registerLanguageFrontend("other", &.{ ".sla", ".other" });
    try std.testing.expectEqualStrings("sla", runtime.languageFrontendForExtension(".sla").?);
    try std.testing.expectEqualStrings("other", runtime.languageFrontendForExtension(".other").?);
    try std.testing.expect(runtime.diagnostics.items.len == 1);
}

test "runtime broker cache ops store, hit, and invalidate on closure change" {
    const test_start = startTimedTest("runtime broker cache ops store, hit, and invalidate on closure change");
    defer endTimedTest("runtime broker cache ops store, hit, and invalidate on closure change", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "cache_cli/src");
    try writeSource(tmp.dir, "cache_cli/build.zig",
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
        \\        .name = "cache_cli",
        \\        .root_module = root_module,
        \\        .linkage = .dynamic,
        \\    });
        \\    b.installArtifact(lib);
        \\}
        \\
    );
    try writeSource(tmp.dir, "cache_cli/src/plugin.zig",
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
        \\const BrokerCacheLookupRequest = extern struct {
        \\    ns_ptr: [*]const u8,
        \\    ns_len: usize,
        \\    key_ptr: [*]const u8,
        \\    key_len: usize,
        \\    closure_ptr: [*]const u8,
        \\    closure_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerCacheLookupResponse = extern struct {
        \\    hit: u32,
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerCacheStoreRequest = extern struct {
        \\    ns_ptr: [*]const u8,
        \\    ns_len: usize,
        \\    key_ptr: [*]const u8,
        \\    key_len: usize,
        \\    closure_ptr: [*]const u8,
        \\    closure_len: usize,
        \\    value_ptr: [*]const u8,
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerCacheStoreResponse = extern struct {
        \\    stored: u32,
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
        \\fn writeAll(stream: HostStream, bytes: []const u8) u32 {
        \\    const write_fn = stream.write_all orelse return 2;
        \\    return write_fn(stream.ctx, bytes.ptr, bytes.len);
        \\}
        \\
        \\fn buildClosure(path: []const u8, blob: []u8) usize {
        \\    blob[0] = 1;
        \\    blob[1] = 0;
        \\    blob[2] = 0;
        \\    blob[3] = 0;
        \\    const len: u32 = @intCast(path.len);
        \\    blob[4] = @intCast(len & 0xff);
        \\    blob[5] = @intCast((len >> 8) & 0xff);
        \\    blob[6] = @intCast((len >> 16) & 0xff);
        \\    blob[7] = @intCast((len >> 24) & 0xff);
        \\    @memcpy(blob[8 .. 8 + path.len], path);
        \\    return 8 + path.len;
        \\}
        \\
        \\fn printStatus(stream: HostStream, out_code: *u8, status: u32) u32 {
        \\    var buf: [32]u8 = undefined;
        \\    const text = std.fmt.bufPrint(&buf, "STATUS {d}\n", .{status}) catch return 2;
        \\    out_code.* = 0;
        \\    return writeAll(stream, text);
        \\}
        \\
        \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = stderr;
        \\    if (argv_len < 2) return 1;
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    const command = std.mem.span(argv[1]);
        \\    var blob: [1024]u8 = undefined;
        \\
        \\    if (std.mem.eql(u8, command, "cache-store")) {
        \\        if (argv_len < 6) return 1;
        \\        const ns = std.mem.span(argv[2]);
        \\        const key = std.mem.span(argv[3]);
        \\        const dep = std.mem.span(argv[4]);
        \\        const bytes = std.mem.span(argv[5]);
        \\        const closure_len = buildClosure(dep, &blob);
        \\        var response = BrokerCacheStoreResponse{ .stored = 0 };
        \\        const request = BrokerCacheStoreRequest{
        \\            .ns_ptr = ns.ptr,
        \\            .ns_len = ns.len,
        \\            .key_ptr = key.ptr,
        \\            .key_len = key.len,
        \\            .closure_ptr = &blob,
        \\            .closure_len = closure_len,
        \\            .value_ptr = bytes.ptr,
        \\            .value_len = bytes.len,
        \\        };
        \\        const status = broker_call(ctx.broker_ctx, 6, &request, &response);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            return writeAll(stdout, "OK\n");
        \\        }
        \\        return printStatus(stdout, out_code, status);
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "cache-lookup")) {
        \\        if (argv_len < 5) return 1;
        \\        const ns = std.mem.span(argv[2]);
        \\        const key = std.mem.span(argv[3]);
        \\        const dep = std.mem.span(argv[4]);
        \\        const closure_len = buildClosure(dep, &blob);
        \\        var buffer: [4096]u8 = undefined;
        \\        var response = BrokerCacheLookupResponse{ .hit = 0, .value_len = 0 };
        \\        var request = BrokerCacheLookupRequest{
        \\            .ns_ptr = ns.ptr,
        \\            .ns_len = ns.len,
        \\            .key_ptr = key.ptr,
        \\            .key_len = key.len,
        \\            .closure_ptr = &blob,
        \\            .closure_len = closure_len,
        \\            .value_ptr = null,
        \\            .value_cap = 0,
        \\        };
        \\        var status = broker_call(ctx.broker_ctx, 5, &request, &response);
        \\        if (status == 0 and response.hit == 0) {
        \\            out_code.* = 0;
        \\            return writeAll(stdout, "MISS\n");
        \\        }
        \\        if (status == 5 or (status == 0 and response.hit != 0)) {
        \\            request.value_ptr = &buffer;
        \\            request.value_cap = buffer.len;
        \\            status = broker_call(ctx.broker_ctx, 5, &request, &response);
        \\            if (status == 0 and response.hit != 0) {
        \\                out_code.* = 0;
        \\                if (writeAll(stdout, "HIT ") != 0) return 2;
        \\                if (writeAll(stdout, buffer[0..response.value_len]) != 0) return 2;
        \\                return writeAll(stdout, "\n");
        \\            }
        \\        }
        \\        return printStatus(stdout, out_code, status);
        \\    }
        \\    return 1;
        \\}
        \\
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "cache-cli",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = handle,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
    );

    const cache_cli_artifact = try dynLibInstallPath(std.testing.allocator, "cache_cli");
    defer std.testing.allocator.free(cache_cli_artifact);
    const plugin_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "cache-cli",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [],
        \\    "net": [],
        \\    "env": [],
        \\    "process": {{ "spawn": false, "exec": [] }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
    , .{ targetArtifactKey(), cache_cli_artifact });
    defer std.testing.allocator.free(plugin_manifest);
    try writeSource(tmp.dir, "cache_cli/sap.json", plugin_manifest);

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

    const cache_dir_name: [:0]const u8 = "SA_FRONTEND_CACHE_DIR";
    const saved_cache_dir = try saveEnvVarZ(std.testing.allocator, cache_dir_name);
    defer {
        if (saved_cache_dir) |value| {
            setEnvVarZ(cache_dir_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(cache_dir_name);
        }
    }
    try setEnvVarZ(cache_dir_name, "fecache");

    try writeSource(tmp.dir, "dep.txt", "v1");

    var install_output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer install_output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "cache_cli", sio.managedWriter(&install_output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, install_code, install_output.items);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const miss_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "cache-lookup", "testns", "key1", "dep.txt" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), miss_code);
    try std.testing.expectEqualStrings("MISS\n", stdout_buffer.items);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const store_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "cache-store", "testns", "key1", "dep.txt", "ARTIFACT-BYTES" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), store_code);
    try std.testing.expectEqualStrings("OK\n", stdout_buffer.items);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const hit_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "cache-lookup", "testns", "key1", "dep.txt" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), hit_code);
    try std.testing.expectEqualStrings("HIT ARTIFACT-BYTES\n", stdout_buffer.items);

    try writeSource(tmp.dir, "dep.txt", "v2");
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const stale_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "cache-lookup", "testns", "key1", "dep.txt" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), stale_code);
    try std.testing.expectEqualStrings("MISS\n", stdout_buffer.items);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const bad_ns_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "cache-store", "../evil", "key1", "dep.txt", "X" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), bad_ns_code);
    try std.testing.expectEqualStrings("STATUS 3\n", stdout_buffer.items);
}
