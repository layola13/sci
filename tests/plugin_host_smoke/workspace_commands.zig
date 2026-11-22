const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const writeSource = helpers.writeSource;
const targetArtifactKey = helpers.targetArtifactKey;
const dynLibFileNameAlloc = helpers.dynLibFileNameAlloc;
const dynLibInstallPath = helpers.dynLibInstallPath;
const runCommand = helpers.runCommand;
const expectSuccess = helpers.expectSuccess;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

test "workspace declared plugin stages and dispatches without global install or dev mode" {
    const test_start = startTimedTest("workspace declared plugin stages and dispatches without global install or dev mode");
    defer endTimedTest("workspace declared plugin stages and dispatches without global install or dev mode", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "broker_cli/src");
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
        \\fn handle(ctx: *const Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: HostStream, stderr: HostStream, out_code: *u8) callconv(.c) u32 {
        \\    _ = stderr;
        \\    if (argv_len < 2) return 1;
        \\    const command = std.mem.span(argv[1]);
        \\    if (std.mem.eql(u8, command, "broker-env-cli")) {
        \\        if (argv_len < 3) return 1;
        \\        const subject = std.mem.span(argv[2]);
        \\        var buffer: [512]u8 = undefined;
        \\        var out_len: usize = 0;
        \\        const status = brokerEnvGet(ctx, subject, buffer[0..], &out_len);
        \\        if (status == 0) {
        \\            out_code.* = 0;
        \\            if (writeAll(stdout, buffer[0..out_len]) != 0) return 2;
        \\            if (writeAll(stdout, "\n") != 0) return 2;
        \\            return 0;
        \\        }
        \\        if (status == 1) {
        \\            out_code.* = 41;
        \\            return writeAll(stdout, "DENIED\n");
        \\        }
        \\        out_code.* = 42;
        \\        return writeAll(stdout, "OTHER\n");
        \\    }
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
    );
    const broker_cli_artifact = try dynLibInstallPath(std.testing.allocator, "broker_cli");
    defer std.testing.allocator.free(broker_cli_artifact);
    const plugin_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "broker-cli",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [],
        \\    "net": [],
        \\    "env": ["SA_BROKER_*"],
        \\    "process": {{ "spawn": false, "exec": [] }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
    , .{ targetArtifactKey(), broker_cli_artifact });
    defer std.testing.allocator.free(plugin_manifest);
    try writeSource(tmp.dir, "broker_cli/sap.json", plugin_manifest);

    try writeSource(tmp.dir, "sa.mod", "require_plugin broker_cli @0.1.0 abi 1\n");

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

    const secret_name: [:0]const u8 = "SA_BROKER_ALLOWED";
    const saved_secret = try saveEnvVarZ(std.testing.allocator, secret_name);
    defer {
        if (saved_secret) |value| {
            setEnvVarZ(secret_name, value) catch {};
            std.testing.allocator.free(value);
        } else {
            unsetEnvVarZ(secret_name);
        }
    }
    try setEnvVarZ(secret_name, "workspace-secret");

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    // The plugin is privileged (declares an env permission), is NOT in
    // the global plugins home, and SA_PLUGIN_DEV is unset: only the
    // project's workspace declaration can stage and load it. The
    // broker call itself is denied (no CLI authorization granted),
    // which proves dispatch reached the staged plugin.
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "broker-env-cli", "SA_BROKER_ALLOWED" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 41), code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_buffer.items, "DENIED") != null);

    const lock_text = try sio.cwd().readFileAlloc(std.testing.allocator, ".sa-cache/workspace-plugins/installed/broker-cli/current/permissions.lock", 1 << 20);
    defer std.testing.allocator.free(lock_text);
    try std.testing.expect(std.mem.indexOf(u8, lock_text, "workspace_declared=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, lock_text, "dev_install=false") != null);

    var global_exists = true;
    sio.cwd().access("state/installed/broker-cli/current", .{}) catch {
        global_exists = false;
    };
    try std.testing.expect(!global_exists);
}

test "command claims registry resolves commands and reports conflicts" {
    const allocator = std.testing.allocator;
    var runtime = saasm.plugins.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.registerCommandClaims("alpha", &.{ "build", "serve" });
    try std.testing.expectEqualStrings("alpha", runtime.commandClaimant("build").?);
    try std.testing.expectEqualStrings("alpha", runtime.commandClaimant("serve").?);
    try std.testing.expect(runtime.commandClaimant("missing") == null);
    try runtime.registerCommandClaims("beta", &.{ "serve", "clean" });
    try std.testing.expectEqualStrings("alpha", runtime.commandClaimant("serve").?);
    try std.testing.expectEqualStrings("beta", runtime.commandClaimant("clean").?);
    try std.testing.expectEqual(@as(usize, 1), runtime.diagnostics.items.len);
    try std.testing.expect(std.mem.indexOf(u8, runtime.diagnostics.items[0].reason, "command serve is claimed by both alpha and beta") != null);
}

const command_fixture_source =
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
    \\    const command = std.mem.span(argv[1]);
    \\    if (!(@@CONDITIONS@@)) return 1;
    \\    const write_all = stdout.write_all orelse return 2;
    \\    const tag: []const u8 = "@@TAG@@:";
    \\    if (write_all(stdout.ctx, tag.ptr, tag.len) != 0) return 2;
    \\    if (write_all(stdout.ctx, command.ptr, command.len) != 0) return 2;
    \\    const newline: []const u8 = "\n";
    \\    if (write_all(stdout.ctx, newline.ptr, newline.len) != 0) return 2;
    \\    out_code.* = @@CODE@@;
    \\    return 0;
    \\}
    \\
    \\const descriptor = PluginDescriptor{
    \\    .abi_version = 1,
    \\    .descriptor_size = @as(u32, @intCast(@sizeOf(PluginDescriptor))),
    \\    .name = "@@NAME@@",
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

fn writeCommandFixturePlugin(
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    root: []const u8,
    lib_stem: []const u8,
    plugin_name: []const u8,
    tag: []const u8,
    exit_code: u8,
    served: []const []const u8,
    manifest_extra: []const u8,
) !void {
    try dir.createDirPath(std.testing.io, root);

    var conditions = std.array_list.Managed(u8).init(allocator);
    defer conditions.deinit();
    for (served, 0..) |command, i| {
        if (i != 0) try conditions.appendSlice(" or ");
        const piece = try std.fmt.allocPrint(allocator, "std.mem.eql(u8, command, \"{s}\")", .{command});
        defer allocator.free(piece);
        try conditions.appendSlice(piece);
    }

    const with_conditions = try std.mem.replaceOwned(u8, allocator, command_fixture_source, "@@CONDITIONS@@", conditions.items);
    defer allocator.free(with_conditions);
    const with_tag = try std.mem.replaceOwned(u8, allocator, with_conditions, "@@TAG@@", tag);
    defer allocator.free(with_tag);
    const with_name = try std.mem.replaceOwned(u8, allocator, with_tag, "@@NAME@@", plugin_name);
    defer allocator.free(with_name);
    const code_text = try std.fmt.allocPrint(allocator, "{d}", .{exit_code});
    defer allocator.free(code_text);
    const final_source = try std.mem.replaceOwned(u8, allocator, with_name, "@@CODE@@", code_text);
    defer allocator.free(final_source);

    const source_path = try std.fmt.allocPrint(allocator, "{s}/{s}_plugin.zig", .{ root, lib_stem });
    defer allocator.free(source_path);
    try writeSource(dir, source_path, final_source);

    const lib_file = try dynLibFileNameAlloc(allocator, lib_stem);
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
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{}},
        \\  "skills": [],
        \\  "help": "usage: sa {s}\n",
        \\  "permissions": {{"fs": [], "net": [], "env": [], "process": {{"spawn": false, "exec": []}}}},
        \\  "dependencies": {{}}{s}
        \\}}
        \\
    , .{ plugin_name, targetArtifactKey(), lib_file, plugin_name, manifest_extra });
    defer allocator.free(manifest);
    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/sap.json", .{root});
    defer allocator.free(manifest_path);
    try writeSource(dir, manifest_path, manifest);
}

test "declared commands dispatch to their claimant and legacy frontend invocation is deprecated" {
    const test_start = startTimedTest("declared commands dispatch to their claimant and legacy frontend invocation is deprecated");
    defer endTimedTest("declared commands dispatch to their claimant and legacy frontend invocation is deprecated", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeCommandFixturePlugin(std.testing.allocator, tmp.dir, "plug_a", "cmda", "cmd-a", "A", 5, &.{ "cmd-a", "shared-cmd", "only-a" }, ",\n  \"commands\": [\"shared-cmd\", \"only-a\"]");
    try writeCommandFixturePlugin(std.testing.allocator, tmp.dir, "plug_b", "langb", "lang-b", "B", 6, &.{ "lang-b", "shared-cmd" }, ",\n  \"kind\": \"language\",\n  \"language_extensions\": [\".lb\"],\n  \"commands\": [\"shared-cmd\"]");

    var runtime = try saasm.plugins.Runtime.initFromPathList(std.testing.allocator, "plug_a:plug_b");
    defer runtime.deinit();
    try std.testing.expectEqual(@as(usize, 2), runtime.plugins.items.len);

    // The shared command belongs to the first claimant; the second
    // claim is a load diagnostic naming both plugins.
    try std.testing.expectEqualStrings("cmd-a", runtime.commandClaimant("shared-cmd").?);
    try std.testing.expectEqualStrings("cmd-a", runtime.commandClaimant("only-a").?);
    try std.testing.expect(runtime.commandClaimant("other") == null);
    var saw_conflict = false;
    for (runtime.diagnostics.items) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.reason, "command shared-cmd is claimed by both cmd-a and lang-b") != null) saw_conflict = true;
    }
    try std.testing.expect(saw_conflict);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    // A declared command goes straight to its claimant: plugin B is
    // loaded and would answer "shared-cmd" too, but is never asked.
    const shared_code = try runtime.dispatchCommand(&.{ "sa", "shared-cmd" }, sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer), false);
    try std.testing.expectEqual(@as(?u8, 5), shared_code);
    try std.testing.expectEqualStrings("A:shared-cmd\n", stdout_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    // The legacy two-layer language invocation still dispatches but
    // prints the deprecation notice.
    stdout_buffer.clearRetainingCapacity();
    const legacy_code = try runtime.dispatchCommand(&.{ "sa", "lang-b", "check" }, sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer), false);
    try std.testing.expectEqual(@as(?u8, 6), legacy_code);
    try std.testing.expectEqualStrings("B:lang-b\n", stdout_buffer.items);
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "deprecated") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "'sa lang-b check'") != null);

    // Host-constructed dispatches (extension routing) suppress it.
    stderr_buffer.clearRetainingCapacity();
    runtime.suppress_legacy_frontend_notice = true;
    const routed_code = try runtime.dispatchCommand(&.{ "sa", "lang-b", "check" }, sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer), false);
    try std.testing.expectEqual(@as(?u8, 6), routed_code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "deprecated") == null);
}
