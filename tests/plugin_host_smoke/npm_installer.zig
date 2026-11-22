const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const servoWriteAll = helpers.servoWriteAll;
const writeSource = helpers.writeSource;
const writeInstallablePluginProject = helpers.writeInstallablePluginProject;
const runCommand = helpers.runCommand;
const expectSuccess = helpers.expectSuccess;
const expectInstallCode = helpers.expectInstallCode;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

fn sha512SriAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const data = try sio.cwd().readFileAlloc(allocator, path, 64 << 20);
    defer allocator.free(data);
    var digest: [64]u8 = undefined;
    std.crypto.hash.sha2.Sha512.hash(data, &digest, .{});
    var encoded_buf: [128]u8 = undefined;
    const encoded = std.base64.standard.Encoder.encode(&encoded_buf, &digest);
    return try std.fmt.allocPrint(allocator, "sha512-{s}", .{encoded});
}

const RegistryFixture = struct {
    good_meta: []const u8,
    bad_meta: []const u8,
    evil_meta: []const u8,
    good_tgz_path: []const u8,
    evil_tgz_path: []const u8,
};

fn registryRespondJson(stream: std.Io.net.Stream, body: []const u8) void {
    var header_buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n",
        .{body.len},
    ) catch return;
    servoWriteAll(stream, header) catch return;
    servoWriteAll(stream, body) catch return;
}

fn registryRespondFile(stream: std.Io.net.Stream, path: []const u8) void {
    var file = sio.openFileAbsolute(path, .{}) catch return;
    defer file.close();
    const size = file.getEndPos() catch return;
    var header_buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n",
        .{size},
    ) catch return;
    servoWriteAll(stream, header) catch return;
    var file_buf: [8192]u8 = undefined;
    while (true) {
        const n = file.read(&file_buf) catch return;
        if (n == 0) break;
        servoWriteAll(stream, file_buf[0..n]) catch return;
    }
}

fn registryHandle(stream: std.Io.net.Stream, fx: *const RegistryFixture) void {
    var request_buf: [4096]u8 = undefined;
    const n = std.posix.read(stream.socket.handle, &request_buf) catch return;
    if (n == 0) return;
    const request = request_buf[0..n];
    if (std.mem.indexOf(u8, request, ".tgz") != null) {
        const path = if (std.mem.indexOf(u8, request, "evil") != null) fx.evil_tgz_path else fx.good_tgz_path;
        registryRespondFile(stream, path);
    } else if (std.mem.indexOf(u8, request, "badfix") != null) {
        registryRespondJson(stream, fx.bad_meta);
    } else if (std.mem.indexOf(u8, request, "evilfix") != null) {
        registryRespondJson(stream, fx.evil_meta);
    } else {
        registryRespondJson(stream, fx.good_meta);
    }
}

test "plugin installer installs npm packages and enforces registry integrity and inertness" {
    const test_start = startTimedTest("plugin installer installs npm packages and enforces registry integrity and inertness");
    defer endTimedTest("plugin installer installs npm packages and enforces registry integrity and inertness", test_start);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const saved_cwd = try sio.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(saved_cwd);
    var original_cwd = try sio.openDirAbsolute(saved_cwd, .{});
    defer original_cwd.close();
    defer original_cwd.setAsCwd() catch {};
    try std.process.setCurrentDir(std.testing.io, tmp.dir);

    // Stage one plugin project as two npm tarballs: a well-formed
    // package and an "evil" twin whose package.json carries a
    // lifecycle script. npm tarballs wrap the payload in package/.
    try writeInstallablePluginProject(std.testing.allocator, tmp.dir, "stage/package", "npmfix", "npmfix", "sa_plugin_npmfix_probe", "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}", "", "return 0;", false, false);
    try writeSource(tmp.dir, "stage/package/package.json",
        \\{
        \\  "name": "sa-plugin-npmfix",
        \\  "version": "1.0.0",
        \\  "files": ["sap.json", "build.zig", "src", "npmfix.sai"]
        \\}
        \\
    );
    const tar_good = try runCommand(std.testing.allocator, &.{ "tar", "-C", "stage", "-czf", "npmfix.tgz", "package" });
    defer std.testing.allocator.free(tar_good.stdout);
    defer std.testing.allocator.free(tar_good.stderr);
    try expectSuccess(tar_good);

    try writeInstallablePluginProject(std.testing.allocator, tmp.dir, "stage_evil/package", "npmfix", "npmfix", "sa_plugin_npmfix_probe", "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}", "", "return 0;", false, false);
    try writeSource(tmp.dir, "stage_evil/package/package.json",
        \\{
        \\  "name": "sa-plugin-evilfix",
        \\  "version": "1.0.0",
        \\  "scripts": { "postinstall": "echo owned" }
        \\}
        \\
    );
    const tar_evil = try runCommand(std.testing.allocator, &.{ "tar", "-C", "stage_evil", "-czf", "evil.tgz", "package" });
    defer std.testing.allocator.free(tar_evil.stdout);
    defer std.testing.allocator.free(tar_evil.stderr);
    try expectSuccess(tar_evil);

    const good_integrity = try sha512SriAlloc(std.testing.allocator, "npmfix.tgz");
    defer std.testing.allocator.free(good_integrity);
    const evil_integrity = try sha512SriAlloc(std.testing.allocator, "evil.tgz");
    defer std.testing.allocator.free(evil_integrity);
    const good_tgz_abs = try sio.cwd().realpathAlloc(std.testing.allocator, "npmfix.tgz");
    defer std.testing.allocator.free(good_tgz_abs);
    const evil_tgz_abs = try sio.cwd().realpathAlloc(std.testing.allocator, "evil.tgz");
    defer std.testing.allocator.free(evil_tgz_abs);

    const good_meta = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"name":"sa-plugin-npmfix","dist-tags":{{"latest":"1.0.0"}},"versions":{{"1.0.0":{{"version":"1.0.0","dist":{{"tarball":"http://127.0.0.1:18093/sa-plugin-npmfix/-/sa-plugin-npmfix-1.0.0.tgz","integrity":"{s}"}}}}}}}}
    , .{good_integrity});
    defer std.testing.allocator.free(good_meta);
    const bad_meta = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"name":"sa-plugin-badfix","dist-tags":{{"latest":"1.0.0"}},"versions":{{"1.0.0":{{"version":"1.0.0","dist":{{"tarball":"http://127.0.0.1:18093/sa-plugin-npmfix/-/sa-plugin-npmfix-1.0.0.tgz","integrity":"sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}}}}}}}}
    , .{});
    defer std.testing.allocator.free(bad_meta);
    const evil_meta = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"name":"sa-plugin-evilfix","dist-tags":{{"latest":"1.0.0"}},"versions":{{"1.0.0":{{"version":"1.0.0","dist":{{"tarball":"http://127.0.0.1:18093/evil.tgz","integrity":"{s}"}}}}}}}}
    , .{evil_integrity});
    defer std.testing.allocator.free(evil_meta);

    const fixture = try std.testing.allocator.create(RegistryFixture);
    fixture.* = .{
        .good_meta = good_meta,
        .bad_meta = bad_meta,
        .evil_meta = evil_meta,
        .good_tgz_path = good_tgz_abs,
        .evil_tgz_path = evil_tgz_abs,
    };
    defer std.testing.allocator.destroy(fixture);

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 18093);
    const server = try std.testing.allocator.create(std.Io.net.Server);
    server.* = try address.listen(sio.io(), .{ .reuse_address = true });
    defer std.testing.allocator.destroy(server);
    const ready = try std.testing.allocator.create(std.atomic.Value(bool));
    ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(ready);
    const stop = try std.testing.allocator.create(std.atomic.Value(bool));
    stop.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(stop);

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.Io.net.Server, server_ready: *std.atomic.Value(bool), server_stop: *std.atomic.Value(bool), fx: *const RegistryFixture) void {
            defer listen_server.deinit(sio.io());
            server_ready.store(true, .release);
            while (true) {
                var stream = listen_server.accept(sio.io()) catch return;
                defer stream.close(sio.io());
                if (server_stop.load(.acquire)) return;
                registryHandle(stream, fx);
            }
        }
    }.run, .{ server, ready, stop, fixture });
    while (!ready.load(.acquire)) std.Io.sleep(sio.io(), .fromMilliseconds(1), .awake) catch {};
    defer {
        stop.store(true, .release);
        const wake = runCommand(std.testing.allocator, &.{ "curl", "-s", "http://127.0.0.1:18093/" }) catch null;
        if (wake) |result| {
            std.testing.allocator.free(result.stdout);
            std.testing.allocator.free(result.stderr);
        }
        server_thread.join();
    }

    const home_env: [:0]const u8 = "SA_PLUGINS_HOME";
    const saved_home = try saveEnvVarZ(std.testing.allocator, home_env);
    defer {
        if (saved_home) |value| {
            setEnvVarZ(home_env, value) catch {};
            std.testing.allocator.free(value);
        } else unsetEnvVarZ(home_env);
    }
    const registry_env: [:0]const u8 = "SA_NPM_REGISTRY";
    const saved_registry = try saveEnvVarZ(std.testing.allocator, registry_env);
    defer {
        if (saved_registry) |value| {
            setEnvVarZ(registry_env, value) catch {};
            std.testing.allocator.free(value);
        } else unsetEnvVarZ(registry_env);
    }
    try setEnvVarZ(home_env, "state");
    try setEnvVarZ(registry_env, "http://127.0.0.1:18093");

    // Happy path: exact version, integrity verified, payload lands
    // in the regular installed layout under the sap.json name.
    var out_ok = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out_ok.deinit();
    const code_ok = try saasm.plugins.installFromPath(std.testing.allocator, "npm:sa-plugin-npmfix@1.0.0", sio.managedWriter(&out_ok), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, code_ok, out_ok.items);
    try std.testing.expect(std.mem.indexOf(u8, out_ok.items, "npm plugin sa-plugin-npmfix@1.0.0 resolved from http://127.0.0.1:18093") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_ok.items, "npm tarball integrity verified (sha512)") != null);
    try tmp.dir.access(std.testing.io, "state/installed/npmfix/current/sap.json", .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/npmfix/current/sa/npmfix.sai", .{ .read = true });

    // A registry entry whose integrity does not match the bytes is
    // refused before anything is extracted or installed.
    var out_bad = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out_bad.deinit();
    try std.testing.expectError(error.NpmIntegrityMismatch, saasm.plugins.installFromPath(std.testing.allocator, "npm:sa-plugin-badfix@1.0.0", sio.managedWriter(&out_bad), .{ .dev = true, .optimize = "Debug" }));
    try std.testing.expect(std.mem.indexOf(u8, out_bad.items, "integrity mismatch") != null);

    // A package with a lifecycle script is refused even though sa
    // itself would never run it: the channel is inert, period.
    var out_evil = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out_evil.deinit();
    try std.testing.expectError(error.NpmLifecycleScriptsForbidden, saasm.plugins.installFromPath(std.testing.allocator, "npm:sa-plugin-evilfix@1.0.0", sio.managedWriter(&out_evil), .{ .dev = true, .optimize = "Debug" }));
    try std.testing.expect(std.mem.indexOf(u8, out_evil.items, "lifecycle script") != null);

    // Unknown versions are an explicit error, never a silent latest.
    var out_missing = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out_missing.deinit();
    try std.testing.expectError(error.NpmVersionNotFound, saasm.plugins.installFromPath(std.testing.allocator, "npm:sa-plugin-npmfix@9.9.9", sio.managedWriter(&out_missing), .{ .dev = true, .optimize = "Debug" }));

    // Floating installs resolve dist-tags.latest (dev mode only;
    // formal mode requires an exact version, like other remotes).
    try setEnvVarZ(home_env, "state2");
    var out_float = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out_float.deinit();
    const code_float = try saasm.plugins.installFromPath(std.testing.allocator, "npm:sa-plugin-npmfix", sio.managedWriter(&out_float), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, code_float, out_float.items);
    try tmp.dir.access(std.testing.io, "state2/installed/npmfix/current/sap.json", .{ .read = true });
}

test "plugin installer prints a namespace hint for unprefixed extern symbols" {
    const test_start = startTimedTest("plugin installer prints a namespace hint for unprefixed extern symbols");
    defer endTimedTest("plugin installer prints a namespace hint for unprefixed extern symbols", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const permissions = "{\"fs\": [], \"net\": [], \"env\": [], \"process\": {\"spawn\": false, \"exec\": []}}";
    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "gamma",
        "gamma",
        "gamma",
        "loose_probe",
        permissions,
        "",
        "return 0;",
        false,
        false,
    );
    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "delta",
        "delta",
        "delta",
        "sa_plugin_delta_probe",
        permissions,
        "",
        "return 0;",
        false,
        false,
    );
    try writeInstallablePluginProject(
        std.testing.allocator,
        tmp.dir,
        "epsilon",
        "epsilon",
        "epsilon",
        "sa_epsilon_probe",
        permissions,
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

    // An extern outside the plugin's namespace installs fine but is
    // called out with the canonical prefix for new symbols.
    const gamma_code = try saasm.plugins.installFromPath(std.testing.allocator, "gamma", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, gamma_code, output.items);
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "plugin extern namespace hint"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "loose_probe"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output.items, 1, "sa_plugin_gamma_"));

    // The canonical sa_plugin_<name>_ prefix is conforming: no hint.
    output.clearRetainingCapacity();
    const delta_code = try saasm.plugins.installFromPath(std.testing.allocator, "delta", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, delta_code, output.items);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "namespace hint") == null);

    // The established sa_<name>_ family counts as namespaced too.
    output.clearRetainingCapacity();
    const epsilon_code = try saasm.plugins.installFromPath(std.testing.allocator, "epsilon", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, epsilon_code, output.items);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "namespace hint") == null);
}
