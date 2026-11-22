const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const writeSource = helpers.writeSource;
const targetArtifactKey = helpers.targetArtifactKey;
const dynLibInstallPath = helpers.dynLibInstallPath;
const netProbePrelude = helpers.netProbePrelude;
const netProbeBody = helpers.netProbeBody;
const netProbeSymbol = helpers.netProbeSymbol;
const writeInstallablePluginProject = helpers.writeInstallablePluginProject;
const expectInstallCode = helpers.expectInstallCode;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

test "plugin installer rejects raw libraries and installs source project in dev mode" {
    const test_start = startTimedTest("plugin installer rejects raw libraries and installs source project in dev mode");
    defer endTimedTest("plugin installer rejects raw libraries and installs source project in dev mode", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "plugin/src");
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
    const smoke_artifact = try dynLibInstallPath(std.testing.allocator, "smoke");
    defer std.testing.allocator.free(smoke_artifact);
    const smoke_filename = std.fs.path.basename(smoke_artifact);
    const smoke_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "smoke",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{
        \\    "sai": {{ "path": "smoke.sai" }}
        \\  }},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [],
        \\    "net": [
        \\      {{ "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }}
        \\    ],
        \\    "env": [],
        \\    "process": {{ "spawn": false, "exec": [] }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), smoke_artifact });
    defer std.testing.allocator.free(smoke_manifest);
    try writeSource(tmp.dir, "plugin/sap.json", smoke_manifest);

    const bad_net_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "bad-net",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{}},
        \\  "skills": [],
        \\  "permissions": {{
        \\    "fs": [],
        \\    "net": [{{ "url": "http://localhost.evil.example", "methods": ["POST"] }}],
        \\    "env": [],
        \\    "process": {{ "spawn": false, "exec": [] }}
        \\  }},
        \\  "dependencies": {{}}
        \\}}
        \\
    , .{ targetArtifactKey(), smoke_artifact });
    defer std.testing.allocator.free(bad_net_manifest);
    try writeSource(tmp.dir, "plugin/bad_net.sap.json", bad_net_manifest);

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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();

    const raw_artifact_path = try std.fs.path.join(std.testing.allocator, &.{ "plugin", smoke_artifact });
    defer std.testing.allocator.free(raw_artifact_path);
    const raw_code = try saasm.plugins.installFromPath(std.testing.allocator, raw_artifact_path, sio.managedWriter(&output), .{ .dev = true });
    try std.testing.expectEqual(@as(u8, 1), raw_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "refusing to install a raw dynamic library"));

    output.clearRetainingCapacity();
    try std.testing.expectError(
        error.InvalidPluginPermission,
        saasm.plugins.installFromPath(std.testing.allocator, "plugin/bad_net.sap.json", sio.managedWriter(&output), .{ .dev = true }),
    );

    output.clearRetainingCapacity();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "plugin", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, install_code, output.items);
    const installed_smoke = try std.fs.path.join(std.testing.allocator, &.{ "state/installed/smoke/current", smoke_filename });
    defer std.testing.allocator.free(installed_smoke);
    const version_smoke = try std.fs.path.join(std.testing.allocator, &.{ "state/installed/smoke/0.1.0", smoke_filename });
    defer std.testing.allocator.free(version_smoke);
    try tmp.dir.access(std.testing.io, installed_smoke, .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/smoke/current/sap.json", .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/smoke/current/sap.lock", .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/smoke/current/permissions.lock", .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/smoke/current/sa/smoke.sai", .{ .read = true });
    try tmp.dir.access(std.testing.io, version_smoke, .{ .read = true });
}

test "plugin installer rejects undeclared network imports in artifact scan" {
    const test_start = startTimedTest("plugin installer rejects undeclared network imports in artifact scan");
    defer endTimedTest("plugin installer rejects undeclared network imports in artifact scan", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "scan",
        "scan",
        "scan",
        "sa_scan_probe",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        netProbePrelude(),
        netProbeBody(),
        true,
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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "scan", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try std.testing.expectEqual(@as(u8, 1), install_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "without declared net permission"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, netProbeSymbol()));
}

test "plugin installer rejects duplicate extern symbols across installed plugins" {
    const test_start = startTimedTest("plugin installer rejects duplicate extern symbols across installed plugins");
    defer endTimedTest("plugin installer rejects duplicate extern symbols across installed plugins", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();

    const first_code = try saasm.plugins.installFromPath(std.testing.allocator, "alpha", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, first_code, output.items);

    output.clearRetainingCapacity();
    const second_code = try saasm.plugins.installFromPath(std.testing.allocator, "beta", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try std.testing.expectEqual(@as(u8, 1), second_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "plugin extern symbol conflict"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sa_duplicate_probe"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "alpha"));
}

test "plugin installer reports duplicate extern symbols inside installed plugin" {
    const test_start = startTimedTest("plugin installer reports duplicate extern symbols inside installed plugin");
    defer endTimedTest("plugin installer reports duplicate extern symbols inside installed plugin", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "state/installed/bad/current/sa");
    try writeSource(tmp.dir, "state/installed/bad/current/sa/base.sai",
        \\@extern sa_bad_dup() -> u32
        \\
    );
    try writeSource(tmp.dir, "state/installed/bad/current/sa/extra.sai",
        \\@extern sa_bad_dup() -> u64
        \\
    );

    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "probe",
        "probe",
        "probe",
        "sa_probe_unique",
        "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}",
        "",
        "return 0;",
        false,
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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();

    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "probe", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try std.testing.expectEqual(@as(u8, 1), install_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "installed plugin duplicate extern symbol"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sa_bad_dup"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "bad"));
}

test "sa skills hides plugin capabilities until optional dependency is installed" {
    const test_start = startTimedTest("sa skills hides plugin capabilities until optional dependency is installed");
    defer endTimedTest("sa skills hides plugin capabilities until optional dependency is installed", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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
        false,
    );

    try tmp.dir.createDirPath(std.testing.io, "opt/src");
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
    const opt_artifact = try dynLibInstallPath(std.testing.allocator, "opt");
    defer std.testing.allocator.free(opt_artifact);
    const opt_manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "schema": "sa.plugin/1",
        \\  "name": "opt",
        \\  "version": "0.1.0",
        \\  "artifacts": {{
        \\    "{s}": {{ "path": "{s}" }}
        \\  }},
        \\  "interfaces": {{
        \\    "sai": {{ "path": "opt.sai" }}
        \\  }},
        \\  "skills": ["optional.cap"],
        \\  "permissions": {{
        \\    "fs": [],
        \\    "net": [
        \\      {{ "url": "http://127.0.0.1:18094/allowed", "methods": ["GET"] }}
        \\    ],
        \\    "env": [],
        \\    "process": {{ "spawn": false, "exec": [] }}
        \\  }},
        \\  "dependencies": {{
        \\    "dep": {{
        \\      "version": "*",
        \\      "abi": 1,
        \\      "optional": true,
        \\      "symbols": ["sa_optional_dep_probe"]
        \\    }}
        \\  }}
        \\}}
        \\
    , .{ targetArtifactKey(), opt_artifact });
    defer std.testing.allocator.free(opt_manifest);
    try writeSource(tmp.dir, "opt/sap.json", opt_manifest);

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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();

    const opt_code = try saasm.plugins.installFromPath(std.testing.allocator, "opt", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, opt_code, output.items);

    var skills_stdout = std.array_list.Managed(u8).init(std.testing.allocator);
    defer skills_stdout.deinit();
    var skills_stderr = std.array_list.Managed(u8).init(std.testing.allocator);
    defer skills_stderr.deinit();
    const hidden_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        sio.managedWriter(&skills_stdout),
        sio.managedWriter(&skills_stderr),
    );
    try std.testing.expectEqual(@as(u8, 0), hidden_code);
    try std.testing.expect(!std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional section"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional.cap"));

    output.clearRetainingCapacity();
    const dep_code = try saasm.plugins.installFromPath(std.testing.allocator, "dep", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, dep_code, output.items);

    skills_stdout.clearRetainingCapacity();
    skills_stderr.clearRetainingCapacity();
    const visible_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        sio.managedWriter(&skills_stdout),
        sio.managedWriter(&skills_stderr),
    );
    try std.testing.expectEqual(@as(u8, 0), visible_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional section"));
    try std.testing.expect(std.mem.containsAtLeast(u8, skills_stdout.items, 1, "optional.cap"));
}
