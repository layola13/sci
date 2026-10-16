const std = @import("std");
const sio = @import("./sa_io.zig");

fn daemonWrite(stream: std.Io.net.Stream, bytes: []const u8) void {
    var wbuf: [8192]u8 = undefined;
    var w = stream.writer(sio.io(), &wbuf);
    w.interface.writeAll(bytes) catch {};
    w.interface.flush() catch {};
}

pub fn main() !void {
    const a = std.heap.page_allocator;
    // base64 standard Encoder shapes
    var sub_path: [std.base64.standard.Encoder.calcSize(12)]u8 = undefined;
    var rb: [12]u8 = undefined;
    sio.io().random(&rb);
    const enc = std.base64.standard.Encoder.encode(&sub_path, &rb);
    std.debug.assert(enc.len == sub_path.len);
    // unix accept/read/write/close roundtrip
    const path = ".probe_tmp/p3.sock";
    sio.cwd().deleteFile(path) catch {};
    const ua = try std.Io.net.UnixAddress.init(path);
    var server = try ua.listen(sio.io(), .{});
    defer server.deinit(sio.io());
    const client_thread = try std.Thread.spawn(.{}, struct {
        fn run(p: []const u8) void {
            const c = std.Io.net.UnixAddress.init(p) catch return;
            var s = c.connect(sio.io()) catch return;
            defer s.close(sio.io());
            daemonWrite(s, "hello\n");
        }
    }.run, .{path});
    var stream = try server.accept(sio.io());
    defer stream.close(sio.io());
    var read_buf: [4096]u8 = undefined;
    var srbuf: [4096]u8 = undefined;
    var sr = stream.reader(sio.io(), &srbuf);
    const n = try sr.interface.readSliceShort(read_buf[0..]);
    std.debug.assert(n == 6);
    std.debug.assert(std.mem.eql(u8, read_buf[0..n], "hello\n"));
    client_thread.join();
    sio.cwd().deleteFile(path) catch {};
    // Dir writeFile / setAsCwd / realpathAlloc
    try sio.cwd().makePath(".probe_tmp/p3");
    try sio.cwd().writeFile(.{ .sub_path = ".probe_tmp/p3/f.txt", .data = "xyz" });
    const rp = try sio.cwd().realpathAlloc(a, ".probe_tmp/p3/f.txt");
    defer a.free(rp);
    // File seekTo/getEndPos
    var f = try sio.cwd().openFile(".probe_tmp/p3/f.txt", .{});
    defer f.close();
    const len = try f.getEndPos();
    std.debug.assert(len == 3);
    try f.seekTo(1);
    var one: [1]u8 = undefined;
    try f.readAll(&one);
    std.debug.assert(one[0] == 'y');
    // http full chain type-check (expected runtime failure, must compile)
    const m = std.meta.stringToEnum(std.http.Method, "GET") orelse return error.Bad;
    var client: std.http.Client = .{ .allocator = a, .io = sio.io() };
    defer client.deinit();
    const uri = try std.Uri.parse("http://127.0.0.1:1/nope");
    var req = client.request(m, uri, .{
        .redirect_behavior = .not_allowed,
        .keep_alive = false,
        .headers = .{ .accept_encoding = .omit },
    }) catch |e| {
        std.debug.print("http request failed as expected: {s}\n", .{@errorName(e)});
        std.debug.print("PROBE3 OK\n", .{});
        return;
    };
    defer req.deinit();
    if (m.requestHasBody()) {
        req.sendBodyComplete("") catch {};
    } else {
        req.sendBodiless() catch {};
    }
    var rbuf: [8192]u8 = undefined;
    var resp = req.receiveHead(&rbuf) catch |e| {
        std.debug.print("http receiveHead failed as expected: {s}\n", .{@errorName(e)});
        std.debug.print("PROBE3 OK\n", .{});
        return;
    };
    const sc: u16 = @intFromEnum(resp.head.status);
    _ = sc;
    if (m.responseHasBody()) {
        if (resp.head.content_length) |cl| {
            _ = cl;
            var tbuf: [8192]u8 = undefined;
            var out: [16]u8 = undefined;
            resp.reader(&tbuf).readSliceAll(out[0..0]) catch {};
        } else {
            var tbuf: [8192]u8 = undefined;
            var br = resp.reader(&tbuf);
            const p = br.allocRemaining(a, .limited(1024)) catch &.{};
            defer a.free(p);
        }
    }
    std.debug.print("PROBE3 OK\n", .{});
}
