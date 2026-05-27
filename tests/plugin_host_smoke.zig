const std = @import("std");
const saasm = @import("saasm");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn expectSuccess(result: std.process.Child.RunResult) !void {
    if (result.stderr.len != 0) std.debug.print("{s}", .{result.stderr});
    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

fn setEnvVarZ(name: [:0]const u8, value: [:0]const u8) !void {
    if (setenv(name.ptr, value.ptr, 1) != 0) return error.SetEnvFailed;
}

fn unsetEnvVarZ(name: [:0]const u8) void {
    _ = unsetenv(name.ptr);
}

fn saveEnvVarZ(allocator: std.mem.Allocator, name: []const u8) !?[:0]u8 {
    const value = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(value);
    return try allocator.dupeZ(u8, value);
}

test "plugin runtime loads descriptors, skills, commands, and skips bad libraries" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
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
    try writeSource(tmp.dir, "bad.so", "not an elf library");

    const build_plugin = try runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        "host_smoke_plugin.zig",
        "-dynamic",
        "-O",
        "Debug",
        "-femit-bin=libhost_smoke.so",
    });
    defer std.testing.allocator.free(build_plugin.stdout);
    defer std.testing.allocator.free(build_plugin.stderr);
    try expectSuccess(build_plugin);

    var runtime = try saasm.plugins.Runtime.initFromPathList(std.testing.allocator, ".");
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 1), runtime.plugins.items.len);
    try std.testing.expect(runtime.diagnostics.items.len >= 1);
    try std.testing.expectEqualStrings("host-smoke", std.mem.span(runtime.plugins.items[0].descriptor.name));

    var sections = std.ArrayList(struct {
        name: []const u8,
        summary: []const u8,
        items: []const []const u8,
    }).init(std.testing.allocator);
    defer sections.deinit();
    try runtime.appendSkills(&sections);
    try std.testing.expectEqual(@as(usize, 1), sections.items.len);
    try std.testing.expectEqualStrings("host smoke", sections.items[0].name);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const code = try runtime.dispatchCommand(
        &.{ "sa", "hello-plugin" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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

    var cli_stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer cli_stdout.deinit();
    var cli_stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer cli_stderr.deinit();
    const cli_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "hello-plugin" },
        cli_stdout.writer(),
        cli_stderr.writer(),
    );
    try std.testing.expectEqual(@as(u8, 7), cli_code);
    try std.testing.expectEqualStrings("hello from plugin\n", cli_stdout.items);
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);

    cli_stdout.clearRetainingCapacity();
    cli_stderr.clearRetainingCapacity();
    const pkg_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "pkg", "audit", "demo" },
        cli_stdout.writer(),
        cli_stderr.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), pkg_code);
    try std.testing.expectEqualStrings("pkg command reached plugin\n", cli_stdout.items);
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);

    cli_stdout.clearRetainingCapacity();
    cli_stderr.clearRetainingCapacity();
    const skills_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        cli_stdout.writer(),
        cli_stderr.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), skills_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, cli_stdout.items, 1, "host smoke"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cli_stdout.items, 1, "hello-plugin"));
    try std.testing.expectEqual(@as(usize, 0), cli_stderr.items.len);
}

test "native build and test link installed plugin exporting referenced extern" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
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

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const build_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "build-exe", "main.sa", "-o", "probe.out" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
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
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    if (test_code != 0) std.debug.print("plugin link test failed:\nstdout:\n{s}\nstderr:\n{s}\n", .{ stdout_buffer.items, stderr_buffer.items });
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "[PASS] plugin extern"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
