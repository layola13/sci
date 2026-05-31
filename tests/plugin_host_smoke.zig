const std = @import("std");
const saasm = @import("saasm");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn writeInstallablePluginProject(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    root: []const u8,
    library_name: []const u8,
    plugin_name: []const u8,
    export_symbol: []const u8,
    permissions_json: []const u8,
    source_prelude: []const u8,
    export_body: []const u8,
    link_libc: bool,
) !void {
    const src_dir = try std.fmt.allocPrint(allocator, "{s}/src", .{root});
    defer allocator.free(src_dir);
    try dir.makePath(src_dir);

    const build_path = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{root});
    defer allocator.free(build_path);
    const build_source = if (link_libc)
        try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\    const root_module = b.createModule(.{{
            \\        .root_source_file = b.path("src/plugin.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\        .link_libc = true,
            \\    }});
            \\    const lib = b.addLibrary(.{{
            \\        .name = "{s}",
            \\        .root_module = root_module,
            \\        .linkage = .dynamic,
            \\    }});
            \\    b.installArtifact(lib);
            \\}}
            \\
        , .{library_name})
    else
        try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\    const root_module = b.createModule(.{{
            \\        .root_source_file = b.path("src/plugin.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\    const lib = b.addLibrary(.{{
            \\        .name = "{s}",
            \\        .root_module = root_module,
            \\        .linkage = .dynamic,
            \\    }});
            \\    b.installArtifact(lib);
            \\}}
            \\
        , .{library_name});
    defer allocator.free(build_source);
    try writeSource(dir, build_path, build_source);

    const plugin_path = try std.fmt.allocPrint(allocator, "{s}/src/plugin.zig", .{root});
    defer allocator.free(plugin_path);
    const plugin_source = try std.fmt.allocPrint(allocator,
        \\const SkillSection = extern struct {{
        \\    name: [*:0]const u8,
        \\    summary: [*:0]const u8,
        \\    items: [*]const [*:0]const u8,
        \\    items_len: usize,
        \\}};
        \\const PluginDescriptor = extern struct {{
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\    init: ?*const fn (?*anyopaque) callconv(.c) u32,
        \\    prebuild: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) u32,
        \\    postbuild: ?*const fn (?*anyopaque) callconv(.c) u32,
        \\    handle_command: ?*const anyopaque,
        \\    skills_ptr: [*]const SkillSection,
        \\    skills_len: usize,
        \\}};
        \\const skills = [_]SkillSection{{}};
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "{s}",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\}};
        \\{s}
        \\pub export fn {s}() u32 {{
        \\    {s}
        \\}}
        \\
    , .{ plugin_name, source_prelude, export_symbol, export_body });
    defer allocator.free(plugin_source);
    try writeSource(dir, plugin_path, plugin_source);

    const interface_name = try std.fmt.allocPrint(allocator, "{s}.sai", .{plugin_name});
    defer allocator.free(interface_name);
    const interface_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, interface_name });
    defer allocator.free(interface_path);
    const interface_source = try std.fmt.allocPrint(allocator,
        \\@extern {s}() -> u32
        \\
    , .{export_symbol});
    defer allocator.free(interface_source);
    try writeSource(dir, interface_path, interface_source);

    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/sap.json", .{root});
    defer allocator.free(manifest_path);
    const manifest_source = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "linux-x86_64": {{ "path": "zig-out/lib/lib{s}.so" }}
        \\  }},
        \\  "interfaces": {{
        \\    "sai": {{ "path": "{s}" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {s},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ plugin_name, library_name, interface_name, permissions_json });
    defer allocator.free(manifest_source);
    try writeSource(dir, manifest_path, manifest_source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn sha256HexFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return try allocator.dupe(u8, hex[0..]);
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

test "plugin installer rejects raw libraries and installs source project in dev mode" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("plugin/src");
    try writeSource(tmp.dir, "plugin/build.zig",
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
        \\        .name = "smoke",
        \\        .root_module = root_module,
        \\        .linkage = .dynamic,
        \\    });
        \\    b.installArtifact(lib);
        \\}
        \\
    );
    try writeSource(tmp.dir, "plugin/src/plugin.zig",
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
        \\    .name = "smoke",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\pub export fn sa_smoke_probe() u32 {
        \\    return 0;
        \\}
        \\
    );
    try writeSource(tmp.dir, "plugin/smoke.sai",
        \\@extern sa_smoke_probe() -> u32
        \\
    );
    try writeSource(tmp.dir, "plugin/sap.json",
        \\{
        \\  "schema": "sa.plugin/1",
        \\  "name": "smoke",
        \\  "version": "0.1.0",
        \\  "artifacts": {
        \\    "linux-x86_64": { "path": "zig-out/lib/libsmoke.so" }
        \\  },
        \\  "interfaces": {
        \\    "sai": { "path": "smoke.sai" }
        \\  },
        \\  "skills": [],
        \\  "permissions": {
        \\    "fs": [],
        \\    "net": [
        \\      { "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }
        \\    ],
        \\    "env": [],
        \\    "process": { "spawn": false, "exec": [] }
        \\  },
        \\  "dependencies": {}
        \\}
        \\
    );
    try writeSource(tmp.dir, "plugin/bad_net.sap.json",
        \\{
        \\  "schema": "sa.plugin/1",
        \\  "name": "bad-net",
        \\  "version": "0.1.0",
        \\  "artifacts": {
        \\    "linux-x86_64": { "path": "zig-out/lib/libsmoke.so" }
        \\  },
        \\  "interfaces": {},
        \\  "skills": [],
        \\  "permissions": {
        \\    "fs": [],
        \\    "net": [{ "url": "http://localhost.evil.example", "methods": ["POST"] }],
        \\    "env": [],
        \\    "process": { "spawn": false, "exec": [] }
        \\  },
        \\  "dependencies": {}
        \\}
        \\
    );

    const env_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, "state");

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const raw_code = try saasm.plugins.installFromPath(std.testing.allocator, "plugin/zig-out/lib/libsmoke.so", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 1), raw_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "refusing to install a raw dynamic library"));

    output.clearRetainingCapacity();
    try std.testing.expectError(
        error.InvalidPluginPermission,
        saasm.plugins.installFromPath(std.testing.allocator, "plugin/bad_net.sap.json", output.writer(), .{ .dev = true }),
    );

    output.clearRetainingCapacity();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "plugin", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), install_code);
    try tmp.dir.access("state/installed/smoke/current/libsmoke.so", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/smoke/current/sap.json", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/smoke/current/sap.lock", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/smoke/current/permissions.lock", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/smoke/current/sa/smoke.sai", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/smoke/0.1.0/libsmoke.so", .{ .mode = .read_only });
}

test "plugin installer rejects undeclared network imports in artifact scan" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "scan",
        "scan",
        "scan",
        "sa_scan_probe",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        "extern \"c\" fn connect(fd: i32, address: ?*const anyopaque, address_len: i32) i32;\n",
        "_ = connect(-1, null, 0);\n    return 0;",
        true,
    );

    const env_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, "state");

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "scan", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 1), install_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "without declared net permission"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "connect"));
}

test "plugin installer rejects duplicate extern symbols across installed plugins" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "alpha",
        "alpha",
        "alpha",
        "sa_duplicate_probe",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        "",
        "return 0;",
        false,
    );
    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "beta",
        "beta",
        "beta",
        "sa_duplicate_probe",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        "",
        "return 0;",
        false,
    );

    const env_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, "state");

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const first_code = try saasm.plugins.installFromPath(std.testing.allocator, "alpha", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), first_code);

    output.clearRetainingCapacity();
    const second_code = try saasm.plugins.installFromPath(std.testing.allocator, "beta", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 1), second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "plugin extern symbol conflict"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sa_duplicate_probe"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "alpha"));
}

test "sa skills hides plugin capabilities until optional dependency is installed" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "dep",
        "dep",
        "dep",
        "sa_optional_dep_probe",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        "",
        "return 0;",
        false,
    );

    try tmp.dir.makePath("opt/src");
    try writeSource(tmp.dir, "opt/build.zig",
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
        \\        .name = "opt",
        \\        .root_module = root_module,
        \\        .linkage = .dynamic,
        \\    });
        \\    b.installArtifact(lib);
        \\}
        \\
    );
    try writeSource(tmp.dir, "opt/src/plugin.zig",
        \\const SkillSection = struct {
        \\    name: []const u8,
        \\    summary: []const u8,
        \\    items: []const []const u8,
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
        \\const skills = [_]SkillSection{.{
        \\    .name = "optional section",
        \\    .summary = "requires dep",
        \\    .items = &.{"optional.cap"},
        \\}};
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "opt",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = null,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\pub export fn sa_opt_probe() u32 {
        \\    return 0;
        \\}
        \\
    );
    try writeSource(tmp.dir, "opt/opt.sai",
        \\@extern sa_opt_probe() -> u32
        \\
    );
    try writeSource(tmp.dir, "opt/sap.json",
        \\{
        \\  "schema": "sa.plugin/1",
        \\  "name": "opt",
        \\  "version": "0.1.0",
        \\  "artifacts": {
        \\    "linux-x86_64": { "path": "zig-out/lib/libopt.so" }
        \\  },
        \\  "interfaces": {
        \\    "sai": { "path": "opt.sai" }
        \\  },
        \\  "skills": ["optional.cap"],
        \\  "permissions": {
        \\    "fs": [],
        \\    "net": [
        \\      { "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }
        \\    ],
        \\    "env": [],
        \\    "process": { "spawn": false, "exec": [] }
        \\  },
        \\  "dependencies": {
        \\    "dep": {
        \\      "version": "*",
        \\      "abi": 1,
        \\      "optional": true,
        \\      "symbols": ["sa_optional_dep_probe"]
        \\    }
        \\  }
        \\}
        \\
    );

    const env_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, "state");

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

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const opt_code = try saasm.plugins.installFromPath(std.testing.allocator, "opt", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), opt_code);

    var skills_stdout = std.ArrayList(u8).init(std.testing.allocator);
    defer skills_stdout.deinit();
    var skills_stderr = std.ArrayList(u8).init(std.testing.allocator);
    defer skills_stderr.deinit();
    const hidden_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        skills_stdout.writer(),
        skills_stderr.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), hidden_code);
    try std.testing.expect(!std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional section"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional.cap"));

    output.clearRetainingCapacity();
    const dep_code = try saasm.plugins.installFromPath(std.testing.allocator, "dep", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), dep_code);

    skills_stdout.clearRetainingCapacity();
    skills_stderr.clearRetainingCapacity();
    const visible_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        skills_stdout.writer(),
        skills_stderr.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), visible_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional section"));
    try std.testing.expect(std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional.cap"));
}

test "plugin installer installs remote archive source with sha256 pin" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "bundle/archive",
        "archive",
        "archive",
        "sa_archive_probe",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        "",
        "return 0;",
        false,
    );

    const tar_result = try runCommand(std.testing.allocator, &.{
        "tar",
        "-C",
        "bundle",
        "-czf",
        "plugin.tar.gz",
        "archive",
    });
    defer std.testing.allocator.free(tar_result.stdout);
    defer std.testing.allocator.free(tar_result.stderr);
    try expectSuccess(tar_result);

    const archive_sha = try sha256HexFileAlloc(std.testing.allocator, "plugin.tar.gz");
    defer std.testing.allocator.free(archive_sha);
    const archive_abs = try std.fs.cwd().realpathAlloc(std.testing.allocator, "plugin.tar.gz");
    defer std.testing.allocator.free(archive_abs);

    const address = try std.net.Address.parseIp4("127.0.0.1", 18092);
    const server = try std.testing.allocator.create(std.net.Server);
    server.* = try address.listen(.{ .reuse_address = true });
    defer std.testing.allocator.destroy(server);

    const ready = try std.testing.allocator.create(std.atomic.Value(bool));
    ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(ready);

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.net.Server, server_ready: *std.atomic.Value(bool), archive_path: []const u8) void {
            defer listen_server.deinit();
            server_ready.store(true, .release);

            var conn = listen_server.accept() catch return;
            defer conn.stream.close();

            var request_buf: [1024]u8 = undefined;
            _ = conn.stream.read(&request_buf) catch return;

            var file = std.fs.openFileAbsolute(archive_path, .{}) catch return;
            defer file.close();
            const size = file.getEndPos() catch return;

            var header_buf: [256]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nContent-Type: application/gzip\r\nConnection: close\r\n\r\n",
                .{size},
            ) catch return;
            conn.stream.writeAll(header) catch return;

            var file_buf: [8192]u8 = undefined;
            while (true) {
                const n = file.read(&file_buf) catch return;
                if (n == 0) break;
                conn.stream.writeAll(file_buf[0..n]) catch return;
            }
        }
    }.run, .{ server, ready, archive_abs });
    while (!ready.load(.acquire)) std.time.sleep(1 * std.time.ns_per_ms);

    const env_name: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_env = try saveEnvVarZ(std.testing.allocator, env_name);
    defer {
        if (saved_env) |value| {
            setEnvVarZ(env_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(env_name);
        }
    }
    try setEnvVarZ(env_name, "state");

    const install_spec = try std.fmt.allocPrint(
        std.testing.allocator,
        "http://127.0.0.1:18092/plugin.tar.gz#sha256:{s}",
        .{archive_sha},
    );
    defer std.testing.allocator.free(install_spec);

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, install_spec, output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), install_code);
    server_thread.join();

    try tmp.dir.access("state/installed/archive/current/libarchive.so", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/archive/current/sap.json", .{ .mode = .read_only });
    try tmp.dir.access("state/installed/archive/current/sa/archive.sai", .{ .mode = .read_only });
}

test "runtime blocks privileged installed plugins outside dev mode" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "priv",
        "priv",
        "priv",
        "sa_priv_probe",
        "{\"fs\": [], \"net\": [], \"env\": [\"HOME\"], \"process\": {\"spawn\": false, \"exec\": []}}",
        "",
        "return 0;",
        false,
    );

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
    unsetEnvVarZ(dev_name);

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "priv", output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), install_code);

    var runtime = try saasm.plugins.Runtime.initFromEnv(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectEqual(@as(usize, 0), runtime.plugins.items.len);
    try std.testing.expect(runtime.diagnostics.items.len >= 1);
    try std.testing.expect(std.mem.containsAtLeast(u8, runtime.diagnostics.items[0].reason, 1, "blocked in formal runtime mode"));

    try setEnvVarZ(dev_name, "1");
    var dev_runtime = try saasm.plugins.Runtime.initFromEnv(std.testing.allocator);
    defer dev_runtime.deinit();
    try std.testing.expectEqual(@as(usize, 1), dev_runtime.plugins.items.len);
}

test "runtime broker env_get enforces declared env permissions" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("broker/src");
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
    try writeSource(tmp.dir, "broker/sap.json",
        \\{
        \\  "schema": "sa.plugin/1",
        \\  "name": "broker-env",
        \\  "version": "0.1.0",
        \\  "artifacts": {
        \\    "linux-x86_64": { "path": "zig-out/lib/libbroker_env.so" }
        \\  },
        \\  "skills": [],
        \\  "permissions": {
        \\    "fs": [],
        \\    "net": [
        \\      { "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }
        \\    ],
        \\    "env": ["SA_BROKER_*"],
        \\    "process": { "spawn": false, "exec": [] }
        \\  },
        \\  "dependencies": {}
        \\}
        \\
    );

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

    var install_output = std.ArrayList(u8).init(std.testing.allocator);
    defer install_output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "broker", install_output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), install_code);

    var runtime = try saasm.plugins.Runtime.initFromEnv(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectEqual(@as(usize, 1), runtime.plugins.items.len);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const allowed_code = try runtime.dispatchCommand(
        &.{ "sa", "broker-env", "SA_BROKER_ALLOWED" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 0), allowed_code);
    try std.testing.expectEqualStrings("broker-secret\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const denied_code = try runtime.dispatchCommand(
        &.{ "sa", "broker-env", "HOME" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 41), denied_code);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const missing_code = try runtime.dispatchCommand(
        &.{ "sa", "broker-env", "SA_BROKER_MISSING" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
        false,
    );
    try std.testing.expectEqual(@as(?u8, 42), missing_code);
    try std.testing.expectEqualStrings("NOT_FOUND\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "cli allow flags constrain broker env and fs access" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("broker_cli/src");
    try tmp.dir.makePath("data");
    try tmp.dir.makePath("secret");
    try tmp.dir.makePath("tools");
    try writeSource(tmp.dir, "data/allowed.txt", "payload");
    try writeSource(tmp.dir, "secret/blocked.txt", "blocked");
    var runner_file = try tmp.dir.createFile("tools/runner.sh", .{ .truncate = true });
    try runner_file.writeAll(
        \\#!/bin/sh
        \\printf "%s" "$1"
        \\
    );
    try runner_file.chmod(0o755);
    runner_file.close();
    const runner_abs = try std.fs.cwd().realpathAlloc(std.testing.allocator, "tools/runner.sh");
    defer std.testing.allocator.free(runner_abs);

    try writeSource(tmp.dir, "broker_cli/build.zig",
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
        \\        .name = "broker_cli",
        \\        .root_module = root_module,
        \\        .linkage = .dynamic,
        \\    });
        \\    b.installArtifact(lib);
        \\}
        \\
    );
    try writeSource(tmp.dir, "broker_cli/src/plugin.zig",
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
        \\const BrokerFsReadRequest = extern struct {
        \\    path_ptr: [*]const u8,
        \\    path_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerFsReadResponse = extern struct {
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerHttpRequest = extern struct {
        \\    method_ptr: [*]const u8,
        \\    method_len: usize,
        \\    url_ptr: [*]const u8,
        \\    url_len: usize,
        \\    body_ptr: ?[*]const u8,
        \\    body_len: usize,
        \\    value_ptr: ?[*]u8,
        \\    value_cap: usize,
        \\};
        \\
        \\const BrokerHttpResponse = extern struct {
        \\    status_code: u16,
        \\    value_len: usize,
        \\};
        \\
        \\const BrokerString = extern struct {
        \\    ptr: [*]const u8,
        \\    len: usize,
        \\};
        \\
        \\const BrokerProcessSpawnRequest = extern struct {
        \\    path_ptr: [*]const u8,
        \\    path_len: usize,
        \\    argv_ptr: ?[*]const BrokerString,
        \\    argv_len: usize,
        \\    stdout_ptr: ?[*]u8,
        \\    stdout_cap: usize,
        \\    stderr_ptr: ?[*]u8,
        \\    stderr_cap: usize,
        \\};
        \\
        \\const BrokerProcessSpawnResponse = extern struct {
        \\    exit_code: u32,
        \\    stdout_len: usize,
        \\    stderr_len: usize,
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
        \\fn writeStatus(stream: HostStream, out_code: *u8, status: u32) u32 {
        \\    return switch (status) {
        \\        1 => blk: {
        \\            out_code.* = 41;
        \\            break :blk writeAll(stream, "DENIED\n");
        \\        },
        \\        4 => blk: {
        \\            out_code.* = 42;
        \\            break :blk writeAll(stream, "NOT_FOUND\n");
        \\        },
        \\        5 => blk: {
        \\            out_code.* = 43;
        \\            break :blk writeAll(stream, "BUFFER\n");
        \\        },
        \\        else => 2,
        \\    };
        \\}
        \\
        \\fn brokerEnvGet(ctx: *const Context, name: []const u8, buffer: []u8, out_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerEnvGetResponse{ .value_len = 0 };
        \\    const request = BrokerEnvGetRequest{
        \\        .name_ptr = name.ptr,
        \\        .name_len = name.len,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 1, &request, &response);
        \\    out_len.* = response.value_len;
        \\    return status;
        \\}
        \\
        \\fn brokerFsRead(ctx: *const Context, path: []const u8, buffer: []u8, out_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerFsReadResponse{ .value_len = 0 };
        \\    const request = BrokerFsReadRequest{
        \\        .path_ptr = path.ptr,
        \\        .path_len = path.len,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 2, &request, &response);
        \\    out_len.* = response.value_len;
        \\    return status;
        \\}
        \\
        \\fn brokerHttpRequest(ctx: *const Context, method: []const u8, url: []const u8, buffer: []u8, out_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerHttpResponse{
        \\        .status_code = 0,
        \\        .value_len = 0,
        \\    };
        \\    const request = BrokerHttpRequest{
        \\        .method_ptr = method.ptr,
        \\        .method_len = method.len,
        \\        .url_ptr = url.ptr,
        \\        .url_len = url.len,
        \\        .body_ptr = null,
        \\        .body_len = 0,
        \\        .value_ptr = if (buffer.len == 0) null else buffer.ptr,
        \\        .value_cap = buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 3, &request, &response);
        \\    out_len.* = response.value_len;
        \\    _ = response.status_code;
        \\    return status;
        \\}
        \\
        \\fn brokerProcessSpawn(ctx: *const Context, path: []const u8, args: []const BrokerString, stdout_buffer: []u8, stderr_buffer: []u8, exit_code: *u32, stdout_len: *usize, stderr_len: *usize) u32 {
        \\    const broker_call = ctx.broker_call orelse return 2;
        \\    var response = BrokerProcessSpawnResponse{
        \\        .exit_code = 0,
        \\        .stdout_len = 0,
        \\        .stderr_len = 0,
        \\    };
        \\    const request = BrokerProcessSpawnRequest{
        \\        .path_ptr = path.ptr,
        \\        .path_len = path.len,
        \\        .argv_ptr = if (args.len == 0) null else args.ptr,
        \\        .argv_len = args.len,
        \\        .stdout_ptr = if (stdout_buffer.len == 0) null else stdout_buffer.ptr,
        \\        .stdout_cap = stdout_buffer.len,
        \\        .stderr_ptr = if (stderr_buffer.len == 0) null else stderr_buffer.ptr,
        \\        .stderr_cap = stderr_buffer.len,
        \\    };
        \\    const status = broker_call(ctx.broker_ctx, 4, &request, &response);
        \\    exit_code.* = response.exit_code;
        \\    stdout_len.* = response.stdout_len;
        \\    stderr_len.* = response.stderr_len;
        \\    return status;
        \\}
        \\
        \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = stderr;
        \\    if (argv_len < 2) return 1;
        \\
        \\    const command = std.mem.span(argv[1]);
        \\    var buffer: [512]u8 = undefined;
        \\    var out_len: usize = 0;
        \\
        \\    if (std.mem.eql(u8, command, "broker-env-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const subject = std.mem.span(argv[2]);
        \\        const status = brokerEnvGet(ctx, subject, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "broker-fs-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const subject = std.mem.span(argv[2]);
        \\        const status = brokerFsRead(ctx, subject, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "broker-net-cli")) {
        \\        if (argv_len < 4) return 1;
        \\        const method = std.mem.span(argv[2]);
        \\        const url = std.mem.span(argv[3]);
        \\        const status = brokerHttpRequest(ctx, method, url, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    if (std.mem.eql(u8, command, "broker-run-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const path = std.mem.span(argv[2]);
        \\        var arg_records: [8]BrokerString = undefined;
        \\        var child_arg_count: usize = 0;
        \\        var idx: usize = 3;
        \\        while (idx < argv_len) : (idx += 1) {
        \\            const arg = std.mem.span(argv[idx]);
        \\            if (std.mem.startsWith(u8, arg, "--allow-run") or
        \\                std.mem.startsWith(u8, arg, "--permission-set") or
        \\                std.mem.startsWith(u8, arg, "-P"))
        \\            {
        \\                continue;
        \\            }
        \\            if (child_arg_count >= arg_records.len) return 1;
        \\            arg_records[child_arg_count] = .{
        \\                .ptr = arg.ptr,
        \\                .len = arg.len,
        \\            };
        \\            child_arg_count += 1;
        \\        }
        \\
        \\        var stdout_capture: [512]u8 = undefined;
        \\        var stderr_capture: [512]u8 = undefined;
        \\        var exit_code: u32 = 0;
        \\        var stdout_len: usize = 0;
        \\        var stderr_len: usize = 0;
        \\        const status = brokerProcessSpawn(
        \\            ctx,
        \\            path,
        \\            arg_records[0..child_arg_count],
        \\            stdout_capture[0..],
        \\            stderr_capture[0..],
        \\            &exit_code,
        \\            &stdout_len,
        \\            &stderr_len,
        \\        );
        \\        if (status == 0) {
        \\            out_code.* = @as(u8, @truncate(exit_code));
        \\            if (stdout_len != 0 and writeAll(stdout, stdout_capture[0..stdout_len]) != 0) return 2;
        \\            if (stderr_len != 0 and writeAll(stdout, stderr_capture[0..stderr_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (writeStatus(stdout, out_code, status) != 0) return 2;
        \\        return 0;
        \\    }
        \\
        \\    return 1;
        \\}
        \\
        \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
        \\    .name = "broker-cli",
        \\    .init = null,
        \\    .prebuild = null,
        \\    .postbuild = null,
        \\    .handle_command = handle,
        \\    .skills_ptr = skills[0..].ptr,
        \\    .skills_len = skills.len,
        \\};
        \\
    );
    const plugin_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "broker-cli",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "linux-x86_64": {{ "path": "zig-out/lib/libbroker_cli.so" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [
        \\      {{ "op": "read", "path": "$PROJECT/data/**" }},
        \\      {{ "op": "read", "path": "$PROJECT/secret/**" }}
        \\    ],
        \\    "net": [
        \\      {{ "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }}
        \\    ],
        \\    "env": ["SA_BROKER_*", "HOME"],
        \\    "process": {{
        \\      "spawn": true,
        \\      "exec": [
        \\        {{ "path": "{s}", "args": ["run-ok"] }}
        \\      ]
        \\    }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{runner_abs});
    defer std.testing.allocator.free(plugin_manifest);
    try writeSource(tmp.dir, "broker_cli/sap.json", plugin_manifest);

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
    try setEnvVarZ(broker_env_name, "cli-secret");

    var install_output = std.ArrayList(u8).init(std.testing.allocator);
    defer install_output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "broker_cli", install_output.writer(), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 0), install_code);

    const sa_mod_source = try std.fmt.allocPrint(std.testing.allocator,
        \\permission_set dev {{
        \\  env [SA_BROKER_*]
        \\  read [$PROJECT/data/**]
        \\  write []
        \\  net [http://127.0.0.1:18094/allowed]
        \\  run [{s}]
        \\}}
        \\
    , .{runner_abs});
    defer std.testing.allocator.free(sa_mod_source);
    try writeSource(tmp.dir, "sa.mod", sa_mod_source);

    const net_address = try std.net.Address.parseIp4("127.0.0.1", 18094);
    const net_server = try std.testing.allocator.create(std.net.Server);
    net_server.* = try net_address.listen(.{ .reuse_address = true });
    defer std.testing.allocator.destroy(net_server);

    const net_ready = try std.testing.allocator.create(std.atomic.Value(bool));
    net_ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(net_ready);

    const net_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.net.Server, ready: *std.atomic.Value(bool)) void {
            defer listen_server.deinit();
            ready.store(true, .release);

            var served: usize = 0;
            while (served < 2) : (served += 1) {
                var conn = listen_server.accept() catch return;
                defer conn.stream.close();

                var request_buf: [1024]u8 = undefined;
                const n = conn.stream.read(&request_buf) catch return;
                const request = request_buf[0..n];
                const ok = std.mem.containsAtLeast(u8, request, 1, "GET /allowed HTTP/1.1\r\n");
                const status = if (ok) "200 OK" else "404 Not Found";
                const body = if (ok) "net-ok" else "missing";

                var header_buf: [256]u8 = undefined;
                const header = std.fmt.bufPrint(
                    &header_buf,
                    "HTTP/1.1 {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
                    .{ status, body.len },
                ) catch return;
                conn.stream.writeAll(header) catch return;
                conn.stream.writeAll(body) catch return;
            }
        }
    }.run, .{ net_server, net_ready });
    defer {
        var wake_attempts: usize = 0;
        while (wake_attempts < 2) : (wake_attempts += 1) {
            const conn = std.net.tcpConnectToAddress(net_address) catch continue;
            defer conn.close();
            conn.writeAll("GET /shutdown HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n") catch {};
        }
        net_thread.join();
    }
    while (!net_ready.load(.acquire)) std.time.sleep(1 * std.time.ns_per_ms);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const env_ok = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-env-cli", "SA_BROKER_ALLOWED", "--allow-env=SA_BROKER_*" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), env_ok);
    try std.testing.expectEqualStrings("cli-secret\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const env_denied = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-env-cli", "HOME", "--allow-env=SA_BROKER_*" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 41), env_denied);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const env_ok_permission_set = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-env-cli", "SA_BROKER_ALLOWED", "-P=dev" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), env_ok_permission_set);
    try std.testing.expectEqualStrings("cli-secret\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const fs_ok = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-fs-cli", "data/allowed.txt", "--allow-read=$PROJECT/data/**" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), fs_ok);
    try std.testing.expectEqualStrings("payload\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const fs_denied = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-fs-cli", "secret/blocked.txt", "--allow-read=$PROJECT/data/**" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 41), fs_denied);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const fs_ok_permission_set = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-fs-cli", "data/allowed.txt", "-P=dev" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), fs_ok_permission_set);
    try std.testing.expectEqualStrings("payload\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const net_ok = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-net-cli", "GET", "http://127.0.0.1:18094/allowed", "--allow-net=http://127.0.0.1:18094/allowed" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), net_ok);
    try std.testing.expectEqualStrings("net-ok\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const net_denied_host = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-net-cli", "GET", "http://127.0.0.1:18094/blocked", "--allow-net=http://127.0.0.1:18094/allowed" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 41), net_denied_host);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const net_denied_method = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-net-cli", "POST", "http://127.0.0.1:18094/allowed", "--allow-net=http://127.0.0.1:18094/allowed" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 41), net_denied_method);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const net_ok_permission_set = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-net-cli", "GET", "http://127.0.0.1:18094/allowed", "-P=dev" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), net_ok_permission_set);
    try std.testing.expectEqualStrings("net-ok\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const allow_run_flag = try std.fmt.allocPrint(std.testing.allocator, "--allow-run={s}", .{runner_abs});
    defer std.testing.allocator.free(allow_run_flag);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_ok = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-run-cli", runner_abs, "run-ok", allow_run_flag },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), run_ok);
    try std.testing.expectEqualStrings("run-ok\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_denied_arg = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-run-cli", runner_abs, "wrong", allow_run_flag },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 41), run_denied_arg);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_denied_host = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-run-cli", runner_abs, "run-ok", "--allow-run=/bin/sh" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 41), run_denied_host);
    try std.testing.expectEqualStrings("DENIED\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const run_ok_permission_set = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-run-cli", runner_abs, "run-ok", "-P=dev" },
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), run_ok_permission_set);
    try std.testing.expectEqualStrings("run-ok\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
