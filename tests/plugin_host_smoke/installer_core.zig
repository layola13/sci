const std = @import("std");
const builtin = @import("builtin");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const writeSource = helpers.writeSource;
const targetArtifactKey = helpers.targetArtifactKey;
const dynLibFileNameAlloc = helpers.dynLibFileNameAlloc;
const badDynamicLibraryName = helpers.badDynamicLibraryName;
const runCommand = helpers.runCommand;
const sha256HexFileAlloc = helpers.sha256HexFileAlloc;
const expectSuccess = helpers.expectSuccess;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

test "default plugin home is absolute on windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const path = try saasm.plugins.defaultPluginsHome(std.testing.allocator);
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.fs.path.isAbsolute(path));
}

test "plugin runtime loads descriptors, skills, commands, and skips bad libraries" {
    const test_start = startTimedTest("plugin runtime loads descriptors, skills, commands, and skips bad libraries");
    defer endTimedTest("plugin runtime loads descriptors, skills, commands, and skips bad libraries", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "host_smoke_plugin.zig",
        \\const std = @import("std");
        \\
        \\const SkillSection = struct {
        \\    name: []const u8,
        \\    summary: []const u8,
        \\    items: []const []const u8,
        \\};
        \\
        \\const Context = struct {
        \\    allocator: std.mem.Allocator,
        \\    host_version: ?[]const u8 = null,
        \\    log: ?*const fn (ctx: *const anyopaque, level: u8, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
        \\    log_ctx: ?*anyopaque = null,
        \\    json_mode: bool = false,
        \\};
        \\
        \\const HostStream = extern struct {
        \\    ctx: ?*anyopaque,
        \\    write_all: ?*const fn (ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32,
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
        \\const skills = [_]SkillSection{.{
        \\    .name = "host smoke",
        \\    .summary = "runtime plugin host smoke section",
        \\    .items = &.{"hello-plugin"},
        \\}};
        \\
        \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = ctx;
        \\    _ = stderr;
        \\    out_code.* = 0;
        \\    const write_all = stdout.write_all orelse return 2;
        \\    if (argv_len >= 2 and std.mem.eql(u8, std.mem.span(argv[1]), "pkg")) {
        \\        const message = "pkg command reached plugin\n";
        \\        if (write_all(stdout.ctx, message.ptr, message.len) != 0) return 2;
        \\        return 0;
        \\    }
        \\    if (argv_len < 2 or !std.mem.eql(u8, std.mem.span(argv[1]), "hello-plugin")) return 1;
        \\    const message = "hello from plugin\n";
        \\    if (write_all(stdout.ctx, message.ptr, message.len) != 0) return 2;
        \\    out_code.* = 7;
        \\    return 0;
        \\}
        \\
        \\const descriptor = PluginDescriptor{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "host-smoke",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = handle,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = descriptor;
    );
    try writeSource(tmp.dir, badDynamicLibraryName(), "not a dynamic library");

    const host_smoke_lib = try dynLibFileNameAlloc(std.testing.allocator, "host_smoke");
    defer std.testing.allocator.free(host_smoke_lib);
    const host_smoke_emit = try std.fmt.allocPrint(std.testing.allocator, "-femit-bin={s}", .{host_smoke_lib});
    defer std.testing.allocator.free(host_smoke_emit);

    const build_plugin = try runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        "host_smoke_plugin.zig",
        "-dynamic",
        "-O",
        "Debug",
        host_smoke_emit,
    });
    defer std.testing.allocator.free(build_plugin.stdout);
    defer std.testing.allocator.free(build_plugin.stderr);
    try expectSuccess(build_plugin);

    const smoke_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "host-smoke",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{}},
        \\  "skills": [],
        \\  "help": "usage: sa host-smoke <command> [options]\n\nCommands:\n  help-check    Show manifest-defined help\n",
        \\  "permissions": {{"fs": [], "net": [], "env": [], "process": {{"spawn": false, "exec": []}}}},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), host_smoke_lib });
    defer std.testing.allocator.free(smoke_manifest);
    try writeSource(tmp.dir, "sap.json", smoke_manifest);

    var runtime = try saasm.plugins.Runtime.initFromPathList(std.testing.allocator, ".");
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 1), runtime.plugins.items.len);
    try std.testing.expect(runtime.diagnostics.items.len >= 1);
    try std.testing.expectEqualStrings("host-smoke", std.mem.span(runtime.plugins.items[0].descriptor.name));

    var sections = std.array_list.Managed(struct {
        name: []const u8,
        summary: []const u8,
        items: []const []const u8,
    }).init(std.testing.allocator);
    defer sections.deinit();
    try runtime.appendSkills(&sections);
    try std.testing.expectEqual(@as(usize, 1), sections.items.len);
    try std.testing.expectEqualStrings("host smoke", sections.items[0].name);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const help_code = try runtime.dispatchCommand(
        &.{ "sa", "host-smoke", "--help" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 0), help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "usage: sa host-smoke <command> [options]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "help-check"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const code = try runtime.dispatchCommand(
        &.{ "sa", "hello-plugin" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 7), code);
    try std.testing.expectEqualStrings("hello from plugin\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const env_name: [:0]const u8 = "SA_PLUGINS_PATH";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, ".");

    var cli_stdout = std.array_list.Managed(u8).init(std.testing.allocator);
    defer cli_stdout.deinit();
    var cli_stderr = std.array_list.Managed(u8).init(std.testing.allocator);
    defer cli_stderr.deinit();

    const cli_help_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "host-smoke", "--help" },
        sio.managedWriter(&cli_stdout),
        sio.managedWriter(&cli_stderr),
    );
    try std.testing.expectEqual(@as(u8, 0), cli_help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, cli_stdout.items, 1, "usage: sa host-smoke <command> [options]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cli_stdout.items, 1, "help-check"));
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);

    cli_stdout.clearRetainingCapacity();
    cli_stderr.clearRetainingCapacity();
    const cli_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "hello-plugin" },
        sio.managedWriter(&cli_stdout),
        sio.managedWriter(&cli_stderr),
    );
    try std.testing.expectEqual(@as(u8, 7), cli_code);
    try std.testing.expectEqualStrings("hello from plugin\n", cli_stdout.items);
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);

    cli_stdout.clearRetainingCapacity();
    cli_stderr.clearRetainingCapacity();
    const pkg_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "pkg", "audit", "demo" },
        sio.managedWriter(&cli_stdout),
        sio.managedWriter(&cli_stderr),
    );
    try std.testing.expectEqual(@as(u8, 0), pkg_code);
    try std.testing.expectEqualStrings("pkg command reached plugin\n", cli_stdout.items);
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);

    cli_stdout.clearRetainingCapacity();
    cli_stderr.clearRetainingCapacity();
    const skills_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        sio.managedWriter(&cli_stdout),
        sio.managedWriter(&cli_stderr),
    );
    try std.testing.expectEqual(@as(u8, 0), skills_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, cli_stdout.items, 1, "host smoke"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cli_stdout.items, 1, "hello-plugin"));
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);
}

test "plugin runtime verifies declared artifact sha256 before loading" {
    const test_start = startTimedTest("plugin runtime verifies declared artifact sha256 before loading");
    defer endTimedTest("plugin runtime verifies declared artifact sha256 before loading", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "hashed_plugin.zig",
        \\const SkillSection = extern struct {
        \\    name: [*:0]const u8,
        \\    summary: [*:0]const u8,
        \\    items: [*]const [*:0]const u8,
        \\    items_len: usize,
        \\};
        \\const PluginDescriptor = extern struct {
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\    init: ?*const fn (?*anyopaque) callconv(.c) u32,
        \\    prebuild: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) u32,
        \\    postbuild: ?*const fn (?*anyopaque) callconv(.c) u32,
        \\    handle_command: ?*const anyopaque,
        \\    skills_ptr: [*]const SkillSection,
        \\    skills_len: usize,
        \\};
        \\const skills = [_]SkillSection{};
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "hashed-plugin",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
    );

    const hashed_lib = try dynLibFileNameAlloc(std.testing.allocator, "hashed_plugin");
    defer std.testing.allocator.free(hashed_lib);
    const hashed_emit = try std.fmt.allocPrint(std.testing.allocator, "-femit-bin={s}", .{hashed_lib});
    defer std.testing.allocator.free(hashed_emit);

    const build_plugin = try runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        "hashed_plugin.zig",
        "-dynamic",
        "-O",
        "Debug",
        hashed_emit,
    });
    defer std.testing.allocator.free(build_plugin.stdout);
    defer std.testing.allocator.free(build_plugin.stderr);
    try expectSuccess(build_plugin);

    const digest_hex = try sha256HexFileAlloc(std.testing.allocator, hashed_lib);
    defer std.testing.allocator.free(digest_hex);
    const manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "hashed-plugin",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}", "sha256": "{s}" }}
        \\  }},
        \\  "interfaces": {{}},
        \\  "skills": [],
        \\  "permissions": {{"fs": [], "net": [], "env": [], "process": {{"spawn": false, "exec": []}}}},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), hashed_lib, digest_hex });
    defer std.testing.allocator.free(manifest);
    try writeSource(tmp.dir, "sap.json", manifest);

    var runtime = try saasm.plugins.Runtime.initFromPathList(std.testing.allocator, ".");
    defer runtime.deinit();
    try std.testing.expectEqual(@as(usize, 1), runtime.plugins.items.len);
    try std.testing.expectEqualStrings("hashed-plugin", std.mem.span(runtime.plugins.items[0].descriptor.name));

    const bad_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "hashed-plugin",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}", "sha256": "0000000000000000000000000000000000000000000000000000000000000000" }}
        \\  }},
        \\  "interfaces": {{}},
        \\  "skills": [],
        \\  "permissions": {{"fs": [], "net": [], "env": [], "process": {{"spawn": false, "exec": []}}}},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), hashed_lib });
    defer std.testing.allocator.free(bad_manifest);
    try writeSource(tmp.dir, "sap.json", bad_manifest);

    var rejected_runtime = try saasm.plugins.Runtime.initFromPathList(std.testing.allocator, ".");
    defer rejected_runtime.deinit();
    try std.testing.expectEqual(@as(usize, 0), rejected_runtime.plugins.items.len);
    try std.testing.expectEqual(@as(usize, 1), rejected_runtime.diagnostics.items.len);
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        rejected_runtime.diagnostics.items[0].reason,
        1,
        "plugin artifact sha256 mismatch before load",
    ));
}

test "native build and test link installed plugin exporting referenced extern" {
    // Requires the LLVM-C native backend (unavailable with -Dllvm=false).
    if (!saasm.build_options.llvm_enabled) return error.SkipZigTest;
    const test_start = startTimedTest("native build and test link installed plugin exporting referenced extern");
    defer endTimedTest("native build and test link installed plugin exporting referenced extern", test_start);
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "http_link_plugin.zig",
        \\const std = @import("std");
        \\
        \\const SkillSection = struct {
        \\    name: []const u8,
        \\    summary: []const u8,
        \\    items: []const []const u8,
        \\};
        \\
        \\const Context = struct {
        \\    allocator: std.mem.Allocator,
        \\    host_version: ?[]const u8 = null,
        \\    log: ?*const fn (ctx: *const anyopaque, level: u8, message_ptr: [*]const u8, message_len: usize) callconv(.c) void = null,
        \\    log_ctx: ?*anyopaque = null,
        \\    json_mode: bool = false,
        \\};
        \\
        \\const HostStream = extern struct {
        \\    ctx: ?*anyopaque,
        \\    write_all: ?*const fn (ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32,
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
        \\const descriptor = PluginDescriptor{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "http-link-smoke",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = descriptor;
        \\pub export fn sa_http_probe() u32 {
        \\    return 0;
        \\}
    );

    try writeSource(tmp.dir, "main.sa",
        \\@extern sa_http_probe() -> u32
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    status = call @sa_http_probe()
        \\    ok = eq status, 0
        \\    !status
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    return 0
        \\
        \\L_ERR:
        \\    !ok
        \\    return 1
        \\
    );
    try writeSource(tmp.dir, "main_test.sa",
        \\@extern sa_http_probe() -> u32
        \\
        \\@test "plugin extern"():
        \\L_ENTRY:
        \\    status = call @sa_http_probe()
        \\    ok = eq status, 0
        \\    !status
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    return
        \\
        \\L_ERR:
        \\    !ok
        \\    panic(901)
        \\
    );

    const build_plugin = try runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        "http_link_plugin.zig",
        "-dynamic",
        "-O",
        "Debug",
        "-femit-bin=libhttp_link_plugin.so",
    });
    defer std.testing.allocator.free(build_plugin.stdout);
    defer std.testing.allocator.free(build_plugin.stderr);
    try expectSuccess(build_plugin);

    const env_name: [:0]const u8 = "SA_PLUGINS_PATH";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, ".");

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const build_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "build-exe", "main.sa", "-o", "probe.out" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (build_code != 0) std.debug.print("plugin link build failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    try std.testing.expectEqual(@as(u8, 0), build_code);

    const exe_result = try runCommand(std.testing.allocator, &.{"./probe.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    try expectSuccess(exe_result);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stdout.len);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const test_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "test", "main_test.sa", "--jobs", "1" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (test_code != 0) std.debug.print("plugin link test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] plugin extern"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
