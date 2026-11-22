const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const writeSource = helpers.writeSource;
const targetArtifactKey = helpers.targetArtifactKey;
const dynLibFileNameAlloc = helpers.dynLibFileNameAlloc;
const runCommand = helpers.runCommand;
const expectSuccess = helpers.expectSuccess;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

const lang_echo_fixture_source =
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
    \\
    \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
    \\    _ = ctx;
    \\    _ = stderr;
    \\    if (argv_len < 2) return 1;
    \\    const name = std.mem.span(argv[1]);
    \\    if (!std.mem.eql(u8, name, "langx")) return 1;
    \\    const verb: []const u8 = if (argv_len > 2) std.mem.span(argv[2]) else "";
    \\    const write_all = stdout.write_all orelse return 2;
    \\    const parts = [_][]const u8{ "LX:", name, ":", verb, "\n" };
    \\    for (parts) |part| {
    \\        if (write_all(stdout.ctx, part.ptr, part.len) != 0) return 2;
    \\    }
    \\    out_code.* = 0;
    \\    return 0;
    \\}
    \\
    \\const descriptor = PluginDescriptor{
    \\    .abi_version = 1,
    \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
    \\    .name = "langx",
    \\    .init = null,
    \\    .prebuild = null,
    \\    .postbuild = null,
    \\    .handle_command = handle,
    \\    .skills_ptr = skills[0..].ptr,
    \\    .skills_len = skills.len,
    \\};
    \\
    \\pub export const saasm_plugin_descriptor_v1: PluginDescriptor = descriptor;
    \\
;

fn writeEchoLangPlugin(allocator: std.mem.Allocator, dir: std.Io.Dir, root: []const u8) !void {
    try dir.createDirPath(std.testing.io, root);

    const source_path = try std.fmt.allocPrint(allocator, "{s}/langx_plugin.zig", .{root});
    defer allocator.free(source_path);
    try writeSource(dir, source_path, lang_echo_fixture_source);

    const lib_file = try dynLibFileNameAlloc(allocator, "langx");
    defer allocator.free(lib_file);
    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}/{s}", .{ root, lib_file });
    defer allocator.free(emit_arg);
    const build_result = try runCommand(allocator, &.{ "zig", "build-lib", source_path, "-dynamic", "-O", "Debug", emit_arg });
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);
    try expectSuccess(build_result);

    const manifest = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "langx",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{}},
        \\  "skills": [],
        \\  "help": "usage: sa langx\\n",
        \\  "permissions": {{"fs": [], "net": [], "env": [], "process": {{"spawn": false, "exec": []}}}},
        \\  "dependencies": {{}},
        \\  "kind": "language",
        \\  "language_extensions": [".lx"]
        \\}}
        \\
    , .{ targetArtifactKey(), lib_file });
    defer allocator.free(manifest);
    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/sap.json", .{root});
    defer allocator.free(manifest_path);
    try writeSource(dir, manifest_path, manifest);
}

test "project verbs route to the language frontend selected by the project" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    try writeEchoLangPlugin(std.testing.allocator, tmp.dir, "fixture");
    const fixture_root = try tmp.dir.realPathFileAlloc(std.testing.io, "fixture", std.testing.allocator);
    defer std.testing.allocator.free(fixture_root);

    try tmp.dir.createDirPath(std.testing.io, "proj/src");
    try writeSource(tmp.dir, "proj/sa.mod", "package \"demo\"\n");
    try writeSource(tmp.dir, "proj/src/main.lx", "fn main() {}\n");

    try tmp.dir.createDirPath(std.testing.io, "native/src");
    try writeSource(tmp.dir, "native/sa.mod", "package \"nat\"\n");
    try writeSource(tmp.dir, "native/src/main.sa", "@main() -> i32:\nreturn 0\n");

    try tmp.dir.createDirPath(std.testing.io, "bare/src");
    try writeSource(tmp.dir, "bare/src/main.lx", "fn main() {}\n");

    const path_env: [:0]const u8 = "SA_PLUGINS_PATH";
    const saved_path = try saveEnvVarZ(std.testing.allocator, path_env);
    defer {
        if (saved_path) |value| {
            setEnvVarZ(path_env, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(path_env);
        }
    }
    const fixture_root_z = try std.testing.allocator.dupeSentinel(u8, fixture_root, 0);
    defer std.testing.allocator.free(fixture_root_z);
    try setEnvVarZ(path_env, fixture_root_z);

    const dev_env: [:0]const u8 = "SA_PLUGIN_DEV";
    const saved_dev = try saveEnvVarZ(std.testing.allocator, dev_env);
    defer {
        if (saved_dev) |value| {
            setEnvVarZ(dev_env, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(dev_env);
        }
    }
    try setEnvVarZ(dev_env, "1");

    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    // Language project: bare lifecycle verbs dispatch to the frontend,
    // with the lifecycle mapping build -> build-exe.
    try std.process.setCurrentDir(std.testing.io, try tmp.dir.openDir(std.testing.io, "proj", .{}));
    const check_code = try saasm.cli.executeWithWriters(std.testing.allocator, &.{ "sa", "check" }, sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), check_code);
    try std.testing.expectEqualStrings("LX:langx:check\n", stdout_buf.items);

    stdout_buf.clearRetainingCapacity();
    const test_code = try saasm.cli.executeWithWriters(std.testing.allocator, &.{ "sa", "test" }, sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), test_code);
    try std.testing.expectEqualStrings("LX:langx:test\n", stdout_buf.items);

    stdout_buf.clearRetainingCapacity();
    const build_code = try saasm.cli.executeWithWriters(std.testing.allocator, &.{ "sa", "build" }, sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), build_code);
    try std.testing.expectEqualStrings("LX:langx:build-exe\n", stdout_buf.items);

    // A generated main.sa beside the frontend entry (the frontend's
    // own build/run output) must not veto routing.
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "proj/src/main.sa", .data = "; generated\n" });
    stdout_buf.clearRetainingCapacity();
    const mixed_code = try saasm.cli.executeWithWriters(std.testing.allocator, &.{ "sa", "check" }, sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf));
    try std.testing.expectEqual(@as(u8, 0), mixed_code);
    try std.testing.expectEqualStrings("LX:langx:check\n", stdout_buf.items);

    // Native SA project: the frontend must not be consulted.
    try std.process.setCurrentDir(std.testing.io, try tmp.dir.openDir(std.testing.io, "native", .{}));
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    if (saasm.cli.executeWithWriters(std.testing.allocator, &.{ "sa", "check" }, sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf))) |code| {
        try std.testing.expect(code != 0);
    } else |_| {}
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "LX:") == null);

    // No sa.mod at all: no project routing either (guardrail).
    try std.process.setCurrentDir(std.testing.io, try tmp.dir.openDir(std.testing.io, "bare", .{}));
    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    if (saasm.cli.executeWithWriters(std.testing.allocator, &.{ "sa", "check" }, sio.managedWriter(&stdout_buf), sio.managedWriter(&stderr_buf))) |code| {
        try std.testing.expect(code != 0);
    } else |_| {}
    try std.testing.expect(std.mem.indexOf(u8, stdout_buf.items, "LX:") == null);
}
