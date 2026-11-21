const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const AbiStatus = @import("core.zig").AbiStatus;
const TestServer = @import("tests_server.zig").TestServer;
const buildWebSocketFrame = @import("core.zig").buildWebSocketFrame;
const findRawHeader = @import("websocket.zig").findRawHeader;
const httpEchoHandler = @import("tests_server.zig").httpEchoHandler;
const linux = @import("tests_server.zig").linux;
const readRequest = @import("tests_server.zig").readRequest;
const sa_http_client_free = @import("exports_v1.zig").sa_http_client_free;
const sa_http_client_new = @import("exports_v1.zig").sa_http_client_new;
const sa_http_client_new_v2 = @import("v2_core.zig").sa_http_client_new_v2;
const sa_http_client_req_add_header = @import("exports_v1.zig").sa_http_client_req_add_header;
const sa_http_client_req_add_header_v2 = @import("v2_core.zig").sa_http_client_req_add_header_v2;
const sa_http_client_req_free = @import("exports_v1.zig").sa_http_client_req_free;
const sa_http_client_req_new = @import("exports_v1.zig").sa_http_client_req_new;
const sa_http_client_req_new_v2 = @import("v2_core.zig").sa_http_client_req_new_v2;
const sa_http_client_req_send = @import("exports_v1.zig").sa_http_client_req_send;
const sa_http_client_req_send_v2 = @import("v2_core.zig").sa_http_client_req_send_v2;
const sa_http_client_req_set_body = @import("exports_v1.zig").sa_http_client_req_set_body;
const sa_http_client_req_set_body_v2 = @import("v2_core.zig").sa_http_client_req_set_body_v2;
const sa_http_client_req_set_timeout_v2 = @import("v2_core.zig").sa_http_client_req_set_timeout_v2;
const sa_http_client_resp_body_len = @import("exports_v1.zig").sa_http_client_resp_body_len;
const sa_http_client_resp_body_slice = @import("exports_v1.zig").sa_http_client_resp_body_slice;
const sa_http_client_resp_free = @import("exports_v1.zig").sa_http_client_resp_free;
const sa_http_client_resp_get_header = @import("exports_v1.zig").sa_http_client_resp_get_header;
const sa_http_client_resp_status = @import("exports_v1.zig").sa_http_client_resp_status;
const sa_http_client_sse_free = @import("sse.zig").sa_http_client_sse_free;
const sa_http_client_sse_poll = @import("sse.zig").sa_http_client_sse_poll;
const sa_http_client_sse_post = @import("sse.zig").sa_http_client_sse_post;
const sa_http_client_sse_read = @import("sse.zig").sa_http_client_sse_read;
const sa_http_client_sse_status = @import("sse.zig").sa_http_client_sse_status;
const sa_http_client_websocket_connect_v2 = @import("v2_websocket.zig").sa_http_client_websocket_connect_v2;
const sa_http_websocket_free_v2 = @import("v2_frames.zig").sa_http_websocket_free_v2;
const sa_http_websocket_poll_v2 = @import("v2_frames.zig").sa_http_websocket_poll_v2;
const sa_http_websocket_read_v2 = @import("v2_frames.zig").sa_http_websocket_read_v2;
const sa_http_websocket_write_v2 = @import("v2_frames.zig").sa_http_websocket_write_v2;
const sockRead = @import("tests_server.zig").sockRead;
const sockWriteAll = @import("tests_server.zig").sockWriteAll;
const sysErr = @import("tests_server.zig").sysErr;
const testing = @import("tests_server.zig").testing;
const websocketAccept = @import("core.zig").websocketAccept;

// ---- no_proxy bypass coverage (v1 anchor + v2 regression) ----
//
// Each case runs in a forked child that sets the proxy env for
// itself. Mutating the env in the suite process instead would
// corrupt the environ block snapshot captured at process start:
// std's Io.Threaded.scanEnviron unwraps every slot of that
// block on the first subprocess spawn, and unsetenv in-process
// shifts the live array underneath it (observed: the SSE test
// later in this suite panicking with "attempt to use null
// value" inside scanEnviron when these tests used setenv /
// unsetenv directly in an environment that had proxy variables
// set). The child inherits a private copy of the environment,
// so it can set and unset freely; it reports the outcome via
// its exit code. The proxy configuration is loaded at client
// init (HttpClient.init -> initDefaultProxies, which consults
// http_proxy/HTTP_PROXY/all_proxy/ALL_PROXY for http) and the
// bypass reads no_proxy at request time, so the child sets all
// of them before creating its client. The "dead proxy" is an
// ephemeral loopback port bound and immediately closed, so any
// request routed to it is refused at connect.

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn _exit(status: c_int) noreturn;
fn proxyEnvSet(key: [:0]const u8, value: ?[:0]const u8) void {
    if (value) |v| {
        _ = setenv(key, v, 1);
    } else {
        _ = unsetenv(key);
    }
}
fn unlistenedLoopbackPort() u16 {
    const rc = linux.socket(std.posix.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, std.posix.IPPROTO.TCP);
    const fd: i32 = @intCast(rc);
    var addr = std.posix.sockaddr.in{ .family = std.posix.AF.INET, .port = 0, .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
    _ = linux.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in));
    var alen: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    _ = linux.getsockname(fd, @ptrCast(&addr), &alen);
    const port = std.mem.bigToNative(u16, addr.port);
    _ = linux.close(fd);
    return port;
}
// TestServer accepts exactly one connection; when a request
// never reaches it (proxy misroute), release the pending accept
// with a dummy connection carrying a minimal well-formed
// request (the echo handler panics on an empty request line) so
// join() cannot hang.
fn releaseTestServerAccept(port: u16) void {
    const rc = linux.socket(std.posix.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, std.posix.IPPROTO.TCP);
    if (sysErr(rc)) return;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var addr = std.posix.sockaddr.in{ .family = std.posix.AF.INET, .port = std.mem.nativeToBig(u16, port), .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
    if (sysErr(linux.connect(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in)))) return;
    sockWriteAll(fd, "GET / HTTP/1.0\r\n\r\n");
}
fn deadProxyUrl(buf: []u8) ![:0]u8 {
    const slice = try std.fmt.bufPrint(buf, "http://127.0.0.1:{d}", .{unlistenedLoopbackPort()});
    return testing.allocator.dupeSentinel(u8, slice, 0);
}
const ProxyCase = struct {
    proxy_url: [:0]const u8,
    no_proxy: ?[:0]const u8,
    url: []const u8,
    body: []const u8,
    expected_echo: []const u8,
    use_v2: bool,
    expect_success: bool,
};
// Child side of a proxy case. Returns 0 when the observed
// outcome matches the expectation, else a stage code: 21 client
// creation, 22 request creation, 23 body set, 24 send outcome
// mismatch, 25 status, 26 body slice, 27 body content.
fn proxyCaseChild(case: ProxyCase) i32 {
    proxyEnvSet("http_proxy", case.proxy_url);
    proxyEnvSet("HTTP_PROXY", case.proxy_url);
    proxyEnvSet("https_proxy", case.proxy_url);
    proxyEnvSet("HTTPS_PROXY", case.proxy_url);
    proxyEnvSet("all_proxy", case.proxy_url);
    proxyEnvSet("ALL_PROXY", case.proxy_url);
    proxyEnvSet("no_proxy", case.no_proxy);
    proxyEnvSet("NO_PROXY", null);

    var client: ?*anyopaque = null;
    const new_ok = if (case.use_v2)
        sa_http_client_new_v2(0, null, 0, &client) == 0
    else
        sa_http_client_new(0, &client) == @intFromEnum(AbiStatus.ok);
    if (!new_ok) return 21;
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    const req_ok = if (case.use_v2)
        sa_http_client_req_new_v2(client, 2, case.url.ptr, case.url.len, &req) == 0
    else
        sa_http_client_req_new(client, 2, case.url.ptr, case.url.len, &req) == @intFromEnum(AbiStatus.ok);
    if (!req_ok) return 22;
    defer _ = sa_http_client_req_free(req);
    const body_ok = if (case.use_v2)
        sa_http_client_req_set_body_v2(req, case.body.ptr, case.body.len) == 0
    else
        sa_http_client_req_set_body(req, case.body.ptr, case.body.len) == @intFromEnum(AbiStatus.ok);
    if (!body_ok) return 23;
    var resp: ?*anyopaque = null;
    const send_rc = if (case.use_v2)
        sa_http_client_req_send_v2(req, &resp)
    else
        sa_http_client_req_send(req, &resp);
    const send_ok = if (case.use_v2) send_rc == 0 else send_rc == @intFromEnum(AbiStatus.ok);
    if (send_ok != case.expect_success) return 24;
    if (!case.expect_success) return 0;
    defer _ = sa_http_client_resp_free(resp);
    if (sa_http_client_resp_status(resp) != 200) return 25;
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    if (sa_http_client_resp_body_slice(resp, &out_body, &out_len) != @intFromEnum(AbiStatus.ok)) return 26;
    if (!std.mem.eql(u8, out_body.?[0..out_len], case.expected_echo)) return 27;
    return 0;
}
// Parent side: fork the case and wait with a watchdog. Returns
// the child's exit code, 100 if it died by signal, or 101 on
// watchdog timeout.
fn runProxyCase(case: ProxyCase) !i32 {
    const fork_rc = linux.fork();
    if (sysErr(fork_rc)) return error.ForkFailed;
    const pid: i32 = @intCast(fork_rc);
    if (pid == 0) {
        _exit(proxyCaseChild(case));
    }
    var status: i32 = 0;
    var waited_ms: u32 = 0;
    while (waited_ms < 30000) {
        const w = linux.waitpid(pid, &status, 1); // 1 = WNOHANG (stable Linux ABI value; this std exposes no named constant)
        if (!sysErr(w) and w != 0) {
            if ((status & 0x7f) == 0) return @intCast((status >> 8) & 0xff);
            return 100;
        }
        sio.io().sleep(.fromMilliseconds(50), .awake) catch {};
        waited_ms += 50;
    }
    _ = linux.kill(pid, linux.SIG.KILL);
    _ = linux.waitpid(pid, &status, 0);
    return 101;
}
test "http client v2: no_proxy host bypasses configured proxy (loopback)" {
    var proxy_buf: [64]u8 = undefined;
    const proxy_url = try deadProxyUrl(&proxy_buf);
    defer testing.allocator.free(proxy_url);
    const srv = try TestServer.start(httpEchoHandler);
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/v2", .{srv.port});
    const rc = try runProxyCase(.{
        .proxy_url = proxy_url,
        .no_proxy = "127.0.0.1",
        .url = url,
        .body = "v2-body",
        .expected_echo = "POST /v2 v2-body",
        .use_v2 = true,
        .expect_success = true,
    });
    if (rc != 0) releaseTestServerAccept(srv.port);
    srv.join();
    // Pre-fix the v2 path ignored no_proxy and routed into the
    // dead proxy, so the child send failed at connect (rc 24).
    try testing.expectEqual(@as(i32, 0), rc);
}
test "http client v1: no_proxy host bypasses configured proxy (loopback)" {
    // Semantics anchor: the v1 bypass the v2 fix mirrors. This
    // test passes before and after the v2 fix.
    var proxy_buf: [64]u8 = undefined;
    const proxy_url = try deadProxyUrl(&proxy_buf);
    defer testing.allocator.free(proxy_url);
    const srv = try TestServer.start(httpEchoHandler);
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/echo", .{srv.port});
    const rc = try runProxyCase(.{
        .proxy_url = proxy_url,
        .no_proxy = "127.0.0.1",
        .url = url,
        .body = "hello-std",
        .expected_echo = "POST /echo hello-std",
        .use_v2 = false,
        .expect_success = true,
    });
    if (rc != 0) releaseTestServerAccept(srv.port);
    srv.join();
    try testing.expectEqual(@as(i32, 0), rc);
}
test "http client v2: host outside no_proxy still uses configured proxy" {
    var proxy_buf: [64]u8 = undefined;
    const proxy_url = try deadProxyUrl(&proxy_buf);
    defer testing.allocator.free(proxy_url);
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/v2", .{unlistenedLoopbackPort()});
    const rc = try runProxyCase(.{
        .proxy_url = proxy_url,
        .no_proxy = "example.invalid",
        .url = url,
        .body = "v2-body",
        .expected_echo = "",
        .use_v2 = true,
        .expect_success = false,
    });
    // 127.0.0.1 does not match the no_proxy entry, so the
    // request must still go to the (dead) proxy and fail at
    // connect: the bypass must not become "never use a proxy".
    try testing.expectEqual(@as(i32, 0), rc);
}
fn httpHeadHandler(fd: i32) void {
    var buf: [8192]u8 = undefined;
    _ = readRequest(fd, &buf);
    // HEAD semantics (RFC 9110): the response carries the headers the
    // equivalent GET would have produced -- including its
    // Content-Length -- and NO body bytes, and the connection stays
    // open (no Connection: close). A client that waits for the
    // declared 22 body bytes blocks until the server gives up and
    // closes, which the sleep makes observable.
    const h = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 22\r\n\r\n";
    sockWriteAll(fd, h);
    sio.io().sleep(.fromMilliseconds(3000), .awake) catch {};
}
test "http client v2: HEAD against keep-alive upstream returns empty body promptly (D6)" {
    const srv = try TestServer.start(httpHeadHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/hello", .{srv.port});
    var client: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_new_v2(0, null, 0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_new_v2(client, 5, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_set_timeout_v2(req, 4000));
    const t0 = sio.nanoTimestamp();
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_send_v2(req, &resp));
    const elapsed_ms = @divTrunc(sio.nanoTimestamp() - t0, std.time.ns_per_ms);
    // The handler holds the keep-alive connection open for 3 s
    // after sending the head; a correct HEAD client returns at
    // once with an empty body instead of waiting for the
    // declared Content-Length bytes (which never arrive). (In
    // SA-linked binaries the pre-fix code segfaulted outright:
    // see the D6 note in executeRequestV2.)
    try testing.expect(elapsed_ms < 2500);
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    try testing.expectEqual(@as(u64, 0), sa_http_client_resp_body_len(resp));
    var hv: ?[*]const u8 = null;
    var hv_len: u64 = 0;
    try testing.expectEqual(@as(u32, 0), sa_http_client_resp_get_header(resp, "content-length".ptr, "content-length".len, &hv, &hv_len));
    try testing.expectEqualStrings("22", hv.?[0..hv_len]);
}
test "http client v1: HEAD against keep-alive upstream returns empty body promptly (D6)" {
    const srv = try TestServer.start(httpHeadHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/hello", .{srv.port});
    var client: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new(0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_new(client, 5, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const t0 = sio.nanoTimestamp();
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_send(req, &resp));
    const elapsed_ms = @divTrunc(sio.nanoTimestamp() - t0, std.time.ns_per_ms);
    try testing.expect(elapsed_ms < 2500);
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    try testing.expectEqual(@as(u64, 0), sa_http_client_resp_body_len(resp));
}
fn httpUserAgentEchoHandler(fd: i32) void {
    var buf: [8192]u8 = undefined;
    const req = readRequest(fd, &buf);
    const ua = findRawHeader(req, "user-agent") orelse "<none>";
    var hdr: [512]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n", .{ua.len}) catch return;
    sockWriteAll(fd, h);
    sockWriteAll(fd, ua);
}
test "http client v2: add_header user-agent reaches the wire (G5)" {
    const srv = try TestServer.start(httpUserAgentEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/ua", .{srv.port});
    var client: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_new_v2(0, null, 0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_new_v2(client, 1, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const ua = "probe-ua/1.0";
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_add_header_v2(req, "user-agent".ptr, "user-agent".len, ua.ptr, ua.len));
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_send_v2(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@as(u32, 0), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    // Wire-level: the upstream echoes the user-agent it actually
    // received; pre-fix this was std's own default ("zig/..."),
    // never the value set via add_header.
    try testing.expectEqualStrings("probe-ua/1.0", out_body.?[0..out_len]);
}
test "http client v1: add_header user-agent reaches the wire (G5)" {
    const srv = try TestServer.start(httpUserAgentEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/ua", .{srv.port});
    var client: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new(0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_new(client, 1, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const ua = "probe-ua/1.0";
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_add_header(req, "user-agent".ptr, "user-agent".len, ua.ptr, ua.len));
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_send(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    try testing.expectEqualStrings("probe-ua/1.0", out_body.?[0..out_len]);
}
test "http client v2: unset user-agent keeps the std default (G5)" {
    const srv = try TestServer.start(httpUserAgentEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/ua", .{srv.port});
    var client: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_new_v2(0, null, 0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_new_v2(client, 1, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_send_v2(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@as(u32, 0), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    // Documents the default that used to shadow add_header:
    // without an explicit user-agent the wire still carries
    // std.http's own ("zig/<version> (std.http)").
    try testing.expect(std.mem.startsWith(u8, out_body.?[0..out_len], "zig/"));
}
fn wsEchoHandler(fd: i32) void {
    var buf: [8192]u8 = undefined;
    const req = readRequest(fd, &buf);
    const key = findRawHeader(req, "sec-websocket-key") orelse return;
    var accept_buf: [28]u8 = undefined;
    const accept = websocketAccept(key, &accept_buf) catch return;
    var hdr: [512]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept}) catch return;
    sockWriteAll(fd, h);
    // parse one masked client frame by hand
    var fbuf: [4096]u8 = undefined;
    var n: usize = 0;
    while (n < 2) {
        const r = sockRead(fd, fbuf[n..]);
        if (r == 0) return;
        n += r;
    }
    const opcode: u8 = fbuf[0] & 0x0f;
    const masked = (fbuf[1] & 0x80) != 0;
    var payload_len: usize = fbuf[1] & 0x7f;
    var off: usize = 2;
    if (payload_len == 126) {
        while (n < off + 2) {
            const r = sockRead(fd, fbuf[n..]);
            if (r == 0) return;
            n += r;
        }
        payload_len = std.mem.readInt(u16, fbuf[off..][0..2], .big);
        off += 2;
    }
    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) {
        while (n < off + 4) {
            const r = sockRead(fd, fbuf[n..]);
            if (r == 0) return;
            n += r;
        }
        mask = fbuf[off..][0..4].*;
        off += 4;
    }
    while (n < off + payload_len) {
        const r = sockRead(fd, fbuf[n..]);
        if (r == 0) return;
        n += r;
    }
    const payload = fbuf[off..][0..payload_len];
    if (masked) {
        for (payload, 0..) |*b, i| b.* ^= mask[i % 4];
    }
    var out_frame: [4096]u8 = undefined;
    const written = buildWebSocketFrame(&out_frame, opcode, payload, null) catch return;
    sockWriteAll(fd, out_frame[0..written]);
}
test "websocket client v2: echo over loopback" {
    const srv = try TestServer.start(wsEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "ws://127.0.0.1:{d}/ws", .{srv.port});
    var client: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_new_v2(0, null, 0, &client));
    defer _ = sa_http_client_free(client);
    var ws: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_websocket_connect_v2(client, url.ptr, url.len, 5000, &ws));
    defer _ = sa_http_websocket_free_v2(ws);
    const msg = "ping-123";
    var written: u64 = 0;
    try testing.expectEqual(@as(u32, 0), sa_http_websocket_write_v2(ws, 1, msg.ptr, msg.len, &written));
    var events: u32 = 0;
    var polls: usize = 0;
    while (polls < 100) : (polls += 1) {
        try testing.expectEqual(@as(u32, 0), sa_http_websocket_poll_v2(ws, 1, 100, &events));
        if (events & 1 != 0) break;
    }
    try testing.expect(events & 1 != 0);
    var opcode: u8 = 0;
    var out_ptr: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@as(u32, 0), sa_http_websocket_read_v2(ws, 4096, &opcode, &out_ptr, &out_len));
    try testing.expectEqualStrings(msg, out_ptr.?[0..out_len]);
}
fn sseHandler(fd: i32) void {
    var buf: [8192]u8 = undefined;
    _ = readRequest(fd, &buf);
    const body = "data: one\n\ndata: two\n\n";
    var hdr: [256]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{body.len}) catch return;
    sockWriteAll(fd, h);
    sockWriteAll(fd, body);
}
test "sse post: streamed events over loopback" {
    const srv = try TestServer.start(sseHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/sse", .{srv.port});
    const body = "{}";
    const key = "test-key";
    var handle: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_sse_post(url.ptr, url.len, body.ptr, body.len, key.ptr, key.len, &handle));
    defer _ = sa_http_client_sse_free(handle);
    var done: u8 = 0;
    var spins: usize = 0;
    while (spins < 200) : (spins += 1) {
        try testing.expectEqual(@as(u32, 0), sa_http_client_sse_poll(handle, &done));
        if (done != 0) break;
        _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = 25 * std.time.ns_per_ms }, null);
    }
    try testing.expectEqual(@as(u8, 1), done);
    try testing.expectEqual(@as(u16, 200), sa_http_client_sse_status(handle));
    var acc: [256]u8 = undefined;
    var total: usize = 0;
    while (true) {
        var n: u64 = 0;
        try testing.expectEqual(@as(u32, 0), sa_http_client_sse_read(handle, @ptrCast(acc[total..].ptr), acc.len - total, &n));
        if (n == 0) break;
        total += @intCast(n);
    }
    try testing.expect(std.mem.indexOf(u8, acc[0..total], "data: one") != null);
    try testing.expect(std.mem.indexOf(u8, acc[0..total], "data: two") != null);
}
