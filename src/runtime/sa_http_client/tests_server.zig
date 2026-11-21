const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const AbiStatus = @import("core.zig").AbiStatus;
const HttpClient = @import("core.zig").HttpClient;
const sa_http_client_free = @import("exports_v1.zig").sa_http_client_free;
const sa_http_client_new = @import("exports_v1.zig").sa_http_client_new;
const sa_http_client_new_v2 = @import("v2_core.zig").sa_http_client_new_v2;
const sa_http_client_new_with_profile = @import("exports_v1.zig").sa_http_client_new_with_profile;
const sa_http_client_new_with_profile_proxy = @import("exports_v1.zig").sa_http_client_new_with_profile_proxy;
const sa_http_client_new_with_proxy = @import("exports_v1.zig").sa_http_client_new_with_proxy;
const sa_http_client_req_free = @import("exports_v1.zig").sa_http_client_req_free;
const sa_http_client_req_new = @import("exports_v1.zig").sa_http_client_req_new;
const sa_http_client_req_new_v2 = @import("v2_core.zig").sa_http_client_req_new_v2;
const sa_http_client_req_send = @import("exports_v1.zig").sa_http_client_req_send;
const sa_http_client_req_send_v2 = @import("v2_core.zig").sa_http_client_req_send_v2;
const sa_http_client_req_set_body = @import("exports_v1.zig").sa_http_client_req_set_body;
const sa_http_client_req_set_body_v2 = @import("v2_core.zig").sa_http_client_req_set_body_v2;
const sa_http_client_resp_body_slice = @import("exports_v1.zig").sa_http_client_resp_body_slice;
const sa_http_client_resp_free = @import("exports_v1.zig").sa_http_client_resp_free;
const sa_http_client_resp_status = @import("exports_v1.zig").sa_http_client_resp_status;

// ======================= loopback tests =======================
// Real 127.0.0.1 servers (raw linux sockets) exercising the exported
// ABI end to end: v1 sync client, v2 client, WS client, SSE (curl).

pub const testing = std.testing;
pub const linux = std.os.linux;
pub fn sysErr(rc: usize) bool {
    return @as(isize, @bitCast(rc)) < 0;
}
pub const TestServer = struct {
    thread: std.Thread,
    port: u16,
    listen_fd: i32,

    const Handler = *const fn (fd: i32) void;

    pub fn start(handler: Handler) !*TestServer {
        const rc = linux.socket(std.posix.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, std.posix.IPPROTO.TCP);
        if (sysErr(rc)) return error.SocketFailed;
        const fd: i32 = @intCast(rc);
        var addr = std.posix.sockaddr.in{ .family = std.posix.AF.INET, .port = 0, .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
        if (sysErr(linux.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in)))) return error.BindFailed;
        if (sysErr(linux.listen(fd, 4))) return error.ListenFailed;
        var alen: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
        if (sysErr(linux.getsockname(fd, @ptrCast(&addr), &alen))) return error.GetsocknameFailed;
        const self = try testing.allocator.create(TestServer);
        self.* = .{ .thread = undefined, .port = std.mem.bigToNative(u16, addr.port), .listen_fd = fd };
        if (comptime builtin.cpu.arch.isWasm()) {
            return error.UnsupportedPlatform;
        } else {
            self.thread = try std.Thread.spawn(.{}, runServer, .{ fd, handler });
        }
        return self;
    }

    fn runServer(fd: i32, handler: Handler) void {
        const rc = linux.accept(fd, null, null);
        if (sysErr(rc)) {
            _ = linux.close(fd);
            return;
        }
        const cfd: i32 = @intCast(rc);
        handler(cfd);
        _ = linux.close(cfd);
        _ = linux.close(fd);
    }

    pub fn join(self: *TestServer) void {
        self.thread.join();
        testing.allocator.destroy(self);
    }
};
pub fn sockRead(fd: i32, buf: []u8) usize {
    const rc = linux.read(fd, buf.ptr, buf.len);
    if (sysErr(rc)) return 0;
    return rc;
}
pub fn sockWriteAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (sysErr(rc) or rc == 0) return;
        off += rc;
    }
}
pub fn readRequest(fd: i32, buf: []u8) []u8 {
    var n: usize = 0;
    while (n < buf.len) {
        const r = sockRead(fd, buf[n..]);
        if (r == 0) break;
        n += r;
        if (std.mem.indexOf(u8, buf[0..n], "\r\n\r\n")) |he| {
            var need: usize = 0;
            if (std.mem.indexOf(u8, buf[0..he], "Content-Length: ")) |ci| {
                const vs = ci + "Content-Length: ".len;
                const ve = std.mem.indexOfScalarPos(u8, buf[0..he], vs, '\r') orelse he;
                need = std.fmt.parseInt(usize, buf[vs..ve], 10) catch 0;
            }
            const total = he + 4 + need;
            while (n < total and n < buf.len) {
                const r2 = sockRead(fd, buf[n..]);
                if (r2 == 0) break;
                n += r2;
            }
            break;
        }
    }
    return buf[0..n];
}
pub fn httpEchoHandler(fd: i32) void {
    var buf: [8192]u8 = undefined;
    const req = readRequest(fd, &buf);
    var out: [8192]u8 = undefined;
    var olen: usize = 0;
    const sp1 = std.mem.indexOfScalar(u8, req, ' ') orelse 0;
    const sp2 = if (sp1 > 0) std.mem.indexOfScalarPos(u8, req, sp1 + 1, ' ') orelse sp1 else 0;
    const body = if (std.mem.indexOf(u8, req, "\r\n\r\n")) |he| req[he + 4 ..] else "";
    const parts = [_][]const u8{ req[0..sp1], " ", req[sp1 + 1 .. sp2], " ", body };
    for (parts) |p| {
        @memcpy(out[olen..][0..p.len], p);
        olen += p.len;
    }
    var hdr: [256]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{olen}) catch return;
    sockWriteAll(fd, h);
    sockWriteAll(fd, out[0..olen]);
}
test "http client v1: POST echo over loopback" {
    const srv = try TestServer.start(httpEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/echo", .{srv.port});

    var client: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new(0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_new(client, 2, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const body = "hello-std";
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_set_body(req, body.ptr, body.len));
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_send(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    try testing.expectEqualStrings("POST /echo hello-std", out_body.?[0..out_len]);
}
// ---- GAP-17 / GAP-25 variant constructors ----

test "http client variants: profile and proxy validation" {
    // Profile documents are resolved at construction time.
    var client: ?*anyopaque = null;
    const good_profile = "{\"preset\":\"chrome\"}";
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new_with_profile(1, good_profile.ptr, good_profile.len, &client));
    const http_client: *HttpClient = @ptrCast(@alignCast(client.?));
    try testing.expect(http_client.tls_profile != null);
    try testing.expectEqualStrings(good_profile, http_client.tls_profile.?);
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_free(client));

    client = null;
    const bad_preset = "{\"preset\":\"netscape\"}";
    try testing.expectEqual(@intFromEnum(AbiStatus.failed), sa_http_client_new_with_profile(1, bad_preset.ptr, bad_preset.len, &client));
    const grease = "{\"grease\":true}";
    try testing.expectEqual(@intFromEnum(AbiStatus.failed), sa_http_client_new_with_profile(1, grease.ptr, grease.len, &client));
    try testing.expectEqual(@intFromEnum(AbiStatus.failed), sa_http_client_new_with_profile(1, good_profile.ptr, 0, &client));

    // Explicit proxy: installed for both schemes, overriding env.
    const proxy_url = "http://127.0.0.1:18080";
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new_with_proxy(1, proxy_url.ptr, proxy_url.len, &client));
    const proxy_client: *HttpClient = @ptrCast(@alignCast(client.?));
    try testing.expect(proxy_client.client.http_proxy != null);
    try testing.expect(proxy_client.client.https_proxy != null);
    try testing.expect(proxy_client.client.http_proxy == proxy_client.client.https_proxy);
    try testing.expectEqual(@as(u16, 18080), proxy_client.client.http_proxy.?.port);
    try testing.expectEqualStrings("127.0.0.1", proxy_client.client.http_proxy.?.host.bytes);
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_free(client));

    client = null;
    const socks = "socks5://127.0.0.1:1080";
    try testing.expectEqual(@intFromEnum(AbiStatus.failed), sa_http_client_new_with_proxy(1, socks.ptr, socks.len, &client));
    const no_host = "http://";
    try testing.expectEqual(@intFromEnum(AbiStatus.failed), sa_http_client_new_with_proxy(1, no_host.ptr, no_host.len, &client));

    // Composed constructor.
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new_with_profile_proxy(1, good_profile.ptr, good_profile.len, proxy_url.ptr, proxy_url.len, &client));
    const both: *HttpClient = @ptrCast(@alignCast(client.?));
    try testing.expect(both.tls_profile != null and both.client.https_proxy != null);
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_free(client));
}
var proxy_first_line_buf: [512]u8 = undefined;
var proxy_first_line_len: usize = 0;
fn sockReadHead(fd: i32, buf: []u8) []u8 {
    var total: usize = 0;
    while (total < buf.len) {
        const n = sockRead(fd, buf[total..]);
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
    }
    return buf[0..total];
}
fn recordingProxyHandler(fd: i32) void {
    var head_buf: [4096]u8 = undefined;
    const head = sockReadHead(fd, &head_buf);
    const line_end = std.mem.indexOf(u8, head, "\r\n") orelse head.len;
    const line = head[0..line_end];
    @memcpy(proxy_first_line_buf[0..line.len], line);
    proxy_first_line_len = line.len;
    if (std.mem.startsWith(u8, line, "CONNECT ")) {
        sockWriteAll(fd, "HTTP/1.1 200 Connection Established\r\n\r\n");
        // Play the origin inside the tunnel.
        var inner_buf: [4096]u8 = undefined;
        _ = sockReadHead(fd, &inner_buf);
    }
    sockWriteAll(fd, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nPROXY");
}
test "http client explicit proxy: request transits the proxy" {
    const srv = try TestServer.start(recordingProxyHandler);
    defer srv.join();
    var proxy_buf: [64]u8 = undefined;
    const proxy_url = try std.fmt.bufPrint(&proxy_buf, "http://127.0.0.1:{d}", .{srv.port});

    var client: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new_with_proxy(0, proxy_url.ptr, proxy_url.len, &client));
    defer _ = sa_http_client_free(client);
    // Port 9 on the target is closed: the request can only
    // succeed by transiting the configured proxy.
    const url = "http://duck.test:9/acc";
    var req: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_new(client, 1, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_send(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    try testing.expectEqualStrings("PROXY", out_body.?[0..out_len]);
    // The proxy saw the target authority (CONNECT) or the
    // absolute-form request line -- either proves transit.
    try testing.expect(std.mem.indexOf(u8, proxy_first_line_buf[0..proxy_first_line_len], "duck.test:9") != null);
}
test "http client v2: POST echo over loopback" {
    const srv = try TestServer.start(httpEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/v2", .{srv.port});

    var client: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_new_v2(0, null, 0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_new_v2(client, 2, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const body = "v2-body";
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_set_body_v2(req, body.ptr, body.len));
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_send_v2(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    try testing.expectEqualStrings("POST /v2 v2-body", out_body.?[0..out_len]);
}
