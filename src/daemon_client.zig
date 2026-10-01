const std = @import("std");

// Thin client: if SA_DAEMON_SOCKET is set, forward argv to a running daemon and
// return its exit code. Returns null when no socket is configured, the request
// is the `daemon` command itself, or the connection fails — the caller then
// runs in-process. This is what makes the persistent daemon usable from the CLI.
//
// Protocol: one JSON request line, one JSON header line, then body bytes.
// Request always sends the full argv (including argv[0] = "sa") so the daemon
// can reuse executeWithWritersAndOptions unchanged.

pub const MAX_REQUEST_BYTES: usize = 1024 * 1024;
pub const MAX_RESPONSE_BYTES: usize = 64 * 1024 * 1024;

pub fn tryDaemonClient(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype) !?u8 {
    const sock_path = std.process.getEnvVarOwned(allocator, "SA_DAEMON_SOCKET") catch return null;
    defer allocator.free(sock_path);
    if (sock_path.len == 0) return null;
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "daemon")) return null;
    for (argv) |a| {
        if (std.mem.eql(u8, a, "--no-daemon")) return null;
    }

    const stream = std.net.connectUnixSocket(sock_path) catch return null;
    defer stream.close();

    const agent_id = std.process.getEnvVarOwned(allocator, "SA_AGENT_ID") catch null;
    defer if (agent_id) |v| allocator.free(v);
    const generation_text = std.process.getEnvVarOwned(allocator, "SA_AGENT_GENERATION") catch null;
    defer if (generation_text) |v| allocator.free(v);
    const generation: u64 = if (generation_text) |t| std.fmt.parseInt(u64, t, 10) catch 0 else 0;

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch null;

    var req = std.ArrayList(u8).init(allocator);
    defer req.deinit();
    try req.appendSlice("{\"argv\":[");
    // Send FULL argv including argv[0] ("sa").
    for (argv, 0..) |a, idx| {
        if (idx != 0) try req.append(',');
        try appendJsonString(&req, a);
    }
    try req.appendSlice("]");
    if (agent_id) |id| {
        try req.appendSlice(",\"agent_id\":");
        try appendJsonString(&req, id);
        try req.writer().print(",\"generation\":{d}", .{generation});
    }
    if (cwd) |c| {
        try req.appendSlice(",\"cwd\":");
        try appendJsonString(&req, c);
    }
    try req.appendSlice("}\n");
    if (req.items.len > MAX_REQUEST_BYTES) return null;
    stream.writeAll(req.items) catch return null;

    var resp = std.ArrayList(u8).init(allocator);
    defer resp.deinit();
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = stream.read(buf[0..]) catch break;
        if (n == 0) break;
        if (resp.items.len > MAX_RESPONSE_BYTES - n) return null;
        try resp.appendSlice(buf[0..n]);
    }

    if (resp.items.len == 0) return null;
    const nl = std.mem.indexOfScalar(u8, resp.items, '\n') orelse return null;
    const header = resp.items[0..nl];
    const body = if (nl + 1 <= resp.items.len) resp.items[nl + 1 ..] else "";

    if (std.mem.indexOf(u8, header, "\"status\":\"canceled\"") != null) {
        try stdout.writeAll(header);
        try stdout.writeAll("\n");
        return 130;
    }
    if (std.mem.indexOf(u8, header, "\"status\":\"busy\"") != null) {
        try stdout.writeAll(header);
        try stdout.writeAll("\n");
        return 75; // EX_TEMPFAIL
    }
    if (std.mem.indexOf(u8, header, "\"status\":\"error\"") != null and std.mem.indexOf(u8, header, "\"code\"") == null) {
        // Protocol-level error without an executable code — fall back local.
        return null;
    }

    try stdout.writeAll(body);
    const code = parseCodeField(header) orelse 0;
    return @as(u8, @intCast(code & 0xff));
}

fn appendJsonString(buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append('"');
    for (s) |c| {
        switch (c) {
            '"', '\\' => {
                try buf.append('\\');
                try buf.append(c);
            },
            '\n' => try buf.appendSlice("\\n"),
            '\r' => try buf.appendSlice("\\r"),
            '\t' => try buf.appendSlice("\\t"),
            else => try buf.append(c),
        }
    }
    try buf.append('"');
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

test "appendJsonString escapes" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try appendJsonString(&buf, "a\"b\\c");
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\"", buf.items);
}
