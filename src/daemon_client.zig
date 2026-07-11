const std = @import("std");

// Thin client: if SA_DAEMON_SOCKET is set, forward argv to a running daemon and
// return its exit code. Returns null when no socket is configured, the request
// is the `daemon` command itself, or the connection fails — the caller then
// runs in-process. This is what makes the persistent daemon usable from the CLI.
pub fn tryDaemonClient(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype) !?u8 {
    const sock_path = std.process.getEnvVarOwned(allocator, "SA_DAEMON_SOCKET") catch return null;
    defer allocator.free(sock_path);
    if (sock_path.len == 0) return null;
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "daemon")) return null;

    const stream = std.net.connectUnixSocket(sock_path) catch return null;
    defer stream.close();

    var req = std.ArrayList(u8).init(allocator);
    defer req.deinit();
    try req.appendSlice("{\"argv\":[");
    for (argv[1..], 0..) |a, idx| {
        if (idx != 0) try req.append(',');
        try req.append('"');
        for (a) |c| {
            if (c == '"' or c == '\\') try req.append('\\');
            try req.append(c);
        }
        try req.append('"');
    }
    try req.appendSlice("]}\n");
    stream.writeAll(req.items) catch return null;

    var resp = std.ArrayList(u8).init(allocator);
    defer resp.deinit();
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = stream.read(buf[0..]) catch break;
        if (n == 0) break;
        try resp.appendSlice(buf[0..n]);
    }

    const nl = std.mem.indexOfScalar(u8, resp.items, '\n') orelse return null;
    const header = resp.items[0..nl];
    const body = if (nl + 1 <= resp.items.len) resp.items[nl + 1 ..] else "";
    try stdout.writeAll(body);

    const code = parseCodeField(header) orelse 0;
    return @as(u8, @intCast(code & 0xff));
}

fn parseCodeField(header: []const u8) ?u64 {
    const key = "\"code\"";
    const kp = std.mem.indexOf(u8, header, key) orelse return null;
    var i = kp + key.len;
    while (i < header.len and (header[i] == ' ' or header[i] == ':')) i += 1;
    var val: u64 = 0;
    var found = false;
    while (i < header.len and header[i] >= '0' and header[i] <= '9') {
        val = val * 10 + (header[i] - '0');
        i += 1;
        found = true;
    }
    return if (found) val else null;
}

test "parseCodeField extracts code" {
    try std.testing.expectEqual(@as(?u64, 0), parseCodeField("{\"status\":\"ok\",\"code\":0,\"len\":5}"));
    try std.testing.expectEqual(@as(?u64, 7), parseCodeField("{\"code\":7}"));
    try std.testing.expectEqual(@as(?u64, null), parseCodeField("{\"status\":\"ok\"}"));
}
