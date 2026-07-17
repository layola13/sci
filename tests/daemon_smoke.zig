const std = @import("std");
const builtin = @import("builtin");
const daemon_smoke_options = @import("daemon_smoke_options");

fn runCommandAnyExitWithEnvMap(allocator: std.mem.Allocator, argv: []const []const u8, env_map: *const std.process.EnvMap) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .env_map = env_map,
    });
}

fn daemonControlRequest(allocator: std.mem.Allocator, socket_path: []const u8, request: []const u8) ![]u8 {
    const stream = try std.net.connectUnixSocket(socket_path);
    defer stream.close();
    try stream.writeAll(request);

    var response = std.ArrayList(u8).init(allocator);
    errdefer response.deinit();
    var buf: [4096]u8 = undefined;
    const n = try stream.read(buf[0..]);
    try response.appendSlice(buf[0..n]);
    return try response.toOwnedSlice();
}

fn daemonSendControlNoRead(socket_path: []const u8, request: []const u8) void {
    const stream = std.net.connectUnixSocket(socket_path) catch return;
    defer stream.close();
    stream.writeAll(request) catch {};
}

fn daemonControlRequestWithRetry(allocator: std.mem.Allocator, socket_path: []const u8, request: []const u8) ![]u8 {
    var attempt: usize = 0;
    while (attempt < 200) : (attempt += 1) {
        return daemonControlRequest(allocator, socket_path, request) catch |err| switch (err) {
            error.FileNotFound, error.ConnectionRefused => {
                std.Thread.sleep(10 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
    }
    return error.DaemonSocketNotReady;
}

fn waitForDaemonSocketRemoved(socket_path: []const u8) !void {
    var attempt: usize = 0;
    while (attempt < 200) : (attempt += 1) {
        _ = std.fs.cwd().statFile(socket_path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    return error.DaemonSocketStillPresent;
}

test "daemon unix socket smoke forwards cli command and shuts down" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const socket_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "daemon.sock" });
    defer std.testing.allocator.free(socket_path);

    var daemon = std.process.Child.init(&.{
        daemon_smoke_options.sa_cli_path,
        "daemon",
        "--socket",
        socket_path,
        "--max-workers",
        "2",
        "--per-agent-limit",
        "2",
    }, std.testing.allocator);
    daemon.stdin_behavior = .Ignore;
    daemon.stdout_behavior = .Ignore;
    daemon.stderr_behavior = .Ignore;
    try daemon.spawn();
    var daemon_waited = false;
    defer {
        if (!daemon_waited) {
            daemonSendControlNoRead(socket_path, "{\"op\":\"shutdown\"}\n");
            daemonSendControlNoRead(socket_path, "{\"op\":\"ping\"}\n");
            _ = daemon.kill() catch {};
        }
        std.fs.cwd().deleteFile(socket_path) catch {};
    }

    const ping_response = try daemonControlRequestWithRetry(std.testing.allocator, socket_path, "{\"op\":\"ping\"}\n");
    defer std.testing.allocator.free(ping_response);
    try std.testing.expect(std.mem.containsAtLeast(u8, ping_response, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, ping_response, 1, "\"in_flight\""));

    var env_map = try std.process.getEnvMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("SA_DAEMON_SOCKET", socket_path);
    try env_map.put("SA_AGENT_ID", "daemon-smoke");
    try env_map.put("SA_AGENT_GENERATION", "1");

    const version_result = try runCommandAnyExitWithEnvMap(std.testing.allocator, &.{ daemon_smoke_options.sa_cli_path, "version" }, &env_map);
    defer std.testing.allocator.free(version_result.stdout);
    defer std.testing.allocator.free(version_result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, version_result.term);
    const expected_version = try std.fmt.allocPrint(std.testing.allocator, "sa {s}\n", .{daemon_smoke_options.version});
    defer std.testing.allocator.free(expected_version);
    try std.testing.expectEqualStrings(expected_version, version_result.stdout);
    try std.testing.expectEqualStrings("", version_result.stderr);

    const shutdown_response = try daemonControlRequestWithRetry(std.testing.allocator, socket_path, "{\"op\":\"shutdown\"}\n");
    defer std.testing.allocator.free(shutdown_response);
    try std.testing.expect(std.mem.containsAtLeast(u8, shutdown_response, 1, "\"status\":\"ok\""));
    if (daemonControlRequest(std.testing.allocator, socket_path, "{\"op\":\"ping\"}\n")) |unblock_response| {
        std.testing.allocator.free(unblock_response);
    } else |_| {}
    try waitForDaemonSocketRemoved(socket_path);
    const daemon_term = try daemon.wait();
    daemon_waited = true;
    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, daemon_term);
}
