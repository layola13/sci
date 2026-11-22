const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const startTimedTest = helpers.startTimedTest;
const endTimedTest = helpers.endTimedTest;
const servoWriteAll = helpers.servoWriteAll;
const dynLibInstallPath = helpers.dynLibInstallPath;
const writeInstallablePluginProject = helpers.writeInstallablePluginProject;
const runCommand = helpers.runCommand;
const sha256HexFileAlloc = helpers.sha256HexFileAlloc;
const expectSuccess = helpers.expectSuccess;
const expectInstallCode = helpers.expectInstallCode;
const setEnvVarZ = helpers.setEnvVarZ;
const unsetEnvVarZ = helpers.unsetEnvVarZ;
const saveEnvVarZ = helpers.saveEnvVarZ;

test "plugin installer installs remote archive source with sha256 pin" {
    const test_start = startTimedTest("plugin installer installs remote archive source with sha256 pin");
    defer endTimedTest("plugin installer installs remote archive source with sha256 pin", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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
    const archive_abs = try sio.cwd().realpathAlloc(std.testing.allocator, "plugin.tar.gz");
    defer std.testing.allocator.free(archive_abs);

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 18092);
    const server = try std.testing.allocator.create(std.Io.net.Server);
    server.* = try address.listen(sio.io(), .{ .reuse_address = true });
    defer std.testing.allocator.destroy(server);

    const ready = try std.testing.allocator.create(std.atomic.Value(bool));
    ready.* = std.atomic.Value(bool).init(false);
    defer std.testing.allocator.destroy(ready);

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.Io.net.Server, server_ready: *std.atomic.Value(bool), archive_path: []const u8) void {
            defer listen_server.deinit(sio.io());
            server_ready.store(true, .release);

            var stream = listen_server.accept(sio.io()) catch return;
            defer stream.close(sio.io());

            var request_buf: [1024]u8 = undefined;
            _ = std.posix.read(stream.socket.handle, &request_buf) catch return;

            var file = sio.openFileAbsolute(archive_path, .{}) catch return;
            defer file.close();
            const size = file.getEndPos() catch return;

            var header_buf: [256]u8 = undefined;
            const header = std.fmt.bufPrint(
                &header_buf,
                "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nContent-Type: application/gzip\r\nConnection: close\r\n\r\n",
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
    }.run, .{ server, ready, archive_abs });
    while (!ready.load(.acquire)) std.Io.sleep(sio.io(), .fromMilliseconds(1), .awake) catch {};

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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, install_spec, sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, install_code, output.items);
    server_thread.join();

    const archive_artifact = try dynLibInstallPath(std.testing.allocator, "archive");
    defer std.testing.allocator.free(archive_artifact);
    const archive_installed = try std.fs.path.join(std.testing.allocator, &.{ "state/installed/archive/current", std.fs.path.basename(archive_artifact) });
    defer std.testing.allocator.free(archive_installed);
    try tmp.dir.access(std.testing.io, archive_installed, .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/archive/current/sap.json", .{ .read = true });
    try tmp.dir.access(std.testing.io, "state/installed/archive/current/sa/archive.sai", .{ .read = true });
}

test "runtime blocks privileged installed plugins outside dev mode" {
    const test_start = startTimedTest("runtime blocks privileged installed plugins outside dev mode");
    defer endTimedTest("runtime blocks privileged installed plugins outside dev mode", test_start);
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();
    const install_code = try saasm.plugins.installFromPath(std.testing.allocator, "priv", sio.managedWriter(&output), .{ .dev = true, .optimize = "Debug" });
    try expectInstallCode(0, install_code, output.items);

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
