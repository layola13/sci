const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const AbiStatus = @import("core.zig").AbiStatus;
const HttpBodyReader = @import("response.zig").HttpBodyReader;
const HttpClient = @import("core.zig").HttpClient;
const HttpRequest = @import("core.zig").HttpRequest;
const HttpRequestAsyncOp = @import("response.zig").HttpRequestAsyncOp;
const HttpResponse = @import("response.zig").HttpResponse;
const TestServer = @import("tests_server.zig").TestServer;
const addRequestHeader = @import("core.zig").addRequestHeader;
const buildUpstreamUrl = @import("core.zig").buildUpstreamUrl;
const clientAllocator = @import("core.zig").clientAllocator;
const httpEchoHandler = @import("tests_server.zig").httpEchoHandler;
const httpRequestExec = @import("exec.zig").httpRequestExec;
const testing = @import("tests_server.zig").testing;

pub export fn sa_http_client_new(use_tls: u8, out_client: ?*?*anyopaque) u32 {
    const slot = out_client orelse return @intFromEnum(AbiStatus.failed);
    const client = HttpClient.init(clientAllocator(), .{ .use_tls = use_tls }) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(client);
    return @intFromEnum(AbiStatus.ok);
}
// ---- GAP-17 / GAP-25 client variants ----
//
// Same lifecycle and status convention as sa_http_client_new;
// the returned handle is an ordinary client usable with the
// whole v1 surface (req_new / req_send / async / request_*),
// with two loud exceptions: the v2 send path and WebSocket
// connects reject https/wss on profile clients instead of
// silently using std TLS.

pub export fn sa_http_client_new_with_profile(use_tls: u8, profile_ptr: ?[*]const u8, profile_len: u64, out_client: ?*?*anyopaque) u32 {
    const slot = out_client orelse return @intFromEnum(AbiStatus.failed);
    const profile = profile_ptr orelse return @intFromEnum(AbiStatus.failed);
    if (profile_len == 0) return @intFromEnum(AbiStatus.failed);
    const client = HttpClient.init(clientAllocator(), .{
        .use_tls = use_tls,
        .tls_profile = profile[0..@intCast(profile_len)],
    }) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(client);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_new_with_proxy(use_tls: u8, proxy_ptr: ?[*]const u8, proxy_len: u64, out_client: ?*?*anyopaque) u32 {
    const slot = out_client orelse return @intFromEnum(AbiStatus.failed);
    const proxy = proxy_ptr orelse return @intFromEnum(AbiStatus.failed);
    if (proxy_len == 0) return @intFromEnum(AbiStatus.failed);
    const client = HttpClient.init(clientAllocator(), .{
        .use_tls = use_tls,
        .proxy_url = proxy[0..@intCast(proxy_len)],
    }) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(client);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_new_with_profile_proxy(use_tls: u8, profile_ptr: ?[*]const u8, profile_len: u64, proxy_ptr: ?[*]const u8, proxy_len: u64, out_client: ?*?*anyopaque) u32 {
    const slot = out_client orelse return @intFromEnum(AbiStatus.failed);
    const profile = profile_ptr orelse return @intFromEnum(AbiStatus.failed);
    const proxy = proxy_ptr orelse return @intFromEnum(AbiStatus.failed);
    if (profile_len == 0 or proxy_len == 0) return @intFromEnum(AbiStatus.failed);
    const client = HttpClient.init(clientAllocator(), .{
        .use_tls = use_tls,
        .tls_profile = profile[0..@intCast(profile_len)],
        .proxy_url = proxy[0..@intCast(proxy_len)],
    }) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(client);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_new(client: ?*anyopaque, method: u8, url_ptr: ?[*]const u8, url_len: u64, out_req: ?*?*anyopaque) u32 {
    const client_ptr = client orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_req orelse return @intFromEnum(AbiStatus.failed);
    const url = url_ptr orelse return @intFromEnum(AbiStatus.failed);
    const cli = @as(*HttpClient, @ptrCast(@alignCast(client_ptr)));
    const request = HttpRequest.init(cli, .{
        .method = @enumFromInt(method),
        .url = url[0..@intCast(url_len)],
    }) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(request);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_new_joined(
    client: ?*anyopaque,
    method: u8,
    target_ptr: ?[*]const u8,
    target_len: u64,
    path_ptr: ?[*]const u8,
    path_len: u64,
    preserve_base_path: u8,
    out_req: ?*?*anyopaque,
) u32 {
    const client_ptr = client orelse return @intFromEnum(AbiStatus.failed);
    const target = target_ptr orelse return @intFromEnum(AbiStatus.failed);
    const path = path_ptr orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_req orelse return @intFromEnum(AbiStatus.failed);
    const cli = @as(*HttpClient, @ptrCast(@alignCast(client_ptr)));
    const url = buildUpstreamUrl(
        cli.allocator,
        target[0..@intCast(target_len)],
        path[0..@intCast(path_len)],
        preserve_base_path != 0,
    ) catch return @intFromEnum(AbiStatus.failed);
    defer cli.allocator.free(url);
    const request = HttpRequest.init(cli, .{
        .method = @enumFromInt(method),
        .url = url,
    }) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(request);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_add_header(req: ?*anyopaque, key_ptr: ?[*]const u8, key_len: u64, val_ptr: ?[*]const u8, val_len: u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const key = key_ptr orelse return @intFromEnum(AbiStatus.failed);
    const val = val_ptr orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    addRequestHeader(request, key[0..@intCast(key_len)], val[0..@intCast(val_len)]) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_add_openai_auth(req: ?*anyopaque, key_ptr: ?[*]const u8, key_len: u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const key = key_ptr orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const api_key = key[0..@intCast(key_len)];
    if (api_key.len == 0) return @intFromEnum(AbiStatus.ok);
    const bearer = std.fmt.allocPrint(request.allocator, "Bearer {s}", .{api_key}) catch return @intFromEnum(AbiStatus.failed);
    defer request.allocator.free(bearer);
    addRequestHeader(request, "authorization", bearer) catch return @intFromEnum(AbiStatus.failed);
    addRequestHeader(request, "x-api-key", api_key) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_set_body(req: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const body = body_ptr orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    if (request.body) |old| request.allocator.free(old);
    request.body = request.allocator.dupe(u8, body[0..@intCast(body_len)]) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_send(req: ?*anyopaque, out_resp: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_resp orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = httpRequestExec(request) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(response);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_send_async(req: ?*anyopaque, out_op: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_op orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const op = HttpRequestAsyncOp.init(request) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(op);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_async_poll(op: ?*anyopaque, out_ready: ?*u8) u32 {
    const op_ptr = op orelse return @intFromEnum(AbiStatus.failed);
    const ready_slot = out_ready orelse return @intFromEnum(AbiStatus.failed);
    const async_op = @as(*HttpRequestAsyncOp, @ptrCast(@alignCast(op_ptr)));
    ready_slot.* = if (async_op.poll()) 1 else 0;
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_async_take_response(op: ?*anyopaque, out_resp: ?*?*anyopaque) u32 {
    const op_ptr = op orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_resp orelse return @intFromEnum(AbiStatus.failed);
    const async_op = @as(*HttpRequestAsyncOp, @ptrCast(@alignCast(op_ptr)));
    const response = async_op.takeResponse() orelse return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(response);
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_async_free(op: ?*anyopaque) u32 {
    const value = op orelse return @intFromEnum(AbiStatus.failed);
    const async_op = @as(*HttpRequestAsyncOp, @ptrCast(@alignCast(value)));
    async_op.deinit();
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_resp_status(resp: ?*anyopaque) u16 {
    const response = resp orelse return 0;
    return @as(*HttpResponse, @ptrCast(@alignCast(response))).status;
}
pub export fn sa_http_client_resp_get_header(resp: ?*anyopaque, key_ptr: ?[*]const u8, key_len: u64, out_val_ptr: ?*?[*]const u8, out_val_len: ?*u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const key = key_ptr orelse return @intFromEnum(AbiStatus.failed);
    const value_slot = out_val_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_val_len orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const wanted = key[0..@intCast(key_len)];
    for (response.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, wanted)) {
            value_slot.* = header.value.ptr;
            len_slot.* = header.value.len;
            return @intFromEnum(AbiStatus.ok);
        }
    }
    return @intFromEnum(AbiStatus.failed);
}
pub export fn sa_http_client_resp_body_slice(resp: ?*anyopaque, out_body_ptr: ?*?[*]const u8, out_body_len: ?*u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const ptr_slot = out_body_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_body_len orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    ptr_slot.* = response.body.ptr;
    len_slot.* = response.body.len;
    return @intFromEnum(AbiStatus.ok);
}
// One-shot synchronous GET (2026-10-26): composes the stateful v1
// client (new -> req_new -> send -> body_slice) into a single call
// for callers that only need a response body in a buffer. Status
// codes mirror SA_STD_ERR_* (this file otherwise speaks AbiStatus):
// 0 ok, 1 invalid argument (bad url/scheme or null out), 6 io
// (transport or client failure), 9 truncated (body larger than cap:
// out_len reports the full body length and nothing is copied — the
// copyOut convention). Any completed HTTP exchange is a success
// regardless of its status code; callers that need the status code
// or headers use the stateful client.
pub export fn sa_http_fetch_bytes(url_ptr: ?[*]const u8, url_len: u64, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const len_out = out_len orelse return 1;
    len_out.* = 0;
    const up = url_ptr orelse return 1;
    if (url_len == 0 or url_len > 8192) return 1;
    const url = up[0..@intCast(url_len)];
    const use_tls: u8 = if (std.mem.startsWith(u8, url, "https://")) 1 else if (std.mem.startsWith(u8, url, "http://")) 0 else return 1;
    var client: ?*anyopaque = null;
    if (sa_http_client_new(use_tls, &client) != @intFromEnum(AbiStatus.ok)) return 6;
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    if (sa_http_client_req_new(client, 1, url.ptr, url.len, &req) != @intFromEnum(AbiStatus.ok)) return 6;
    defer _ = sa_http_client_req_free(req);
    var resp: ?*anyopaque = null;
    if (sa_http_client_req_send(req, &resp) != @intFromEnum(AbiStatus.ok)) return 6;
    defer _ = sa_http_client_resp_free(resp);
    var body_ptr: ?[*]const u8 = null;
    var body_len: u64 = 0;
    if (sa_http_client_resp_body_slice(resp, &body_ptr, &body_len) != @intFromEnum(AbiStatus.ok)) return 6;
    len_out.* = body_len;
    if (body_len > cap) return 9;
    if (body_len > 0) {
        const bp = body_ptr orelse return 6;
        const out = buf_ptr orelse return 1;
        @memcpy(out[0..@intCast(body_len)], bp[0..@intCast(body_len)]);
    }
    return 0;
}
test "http fetch bytes: one-shot GET over loopback" {
    const srv = try TestServer.start(httpEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/echo", .{srv.port});
    var buf: [256]u8 = undefined;
    var out_len: u64 = 0;
    try testing.expectEqual(@as(i32, 0), sa_http_fetch_bytes(url.ptr, url.len, &buf, buf.len, &out_len));
    try testing.expectEqualStrings("GET /echo ", buf[0..@intCast(out_len)]);
}
test "http fetch bytes: truncated body reports required length; bad scheme rejected" {
    const srv = try TestServer.start(httpEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/echo", .{srv.port});
    var small: [4]u8 = undefined;
    var need: u64 = 0;
    try testing.expectEqual(@as(i32, 9), sa_http_fetch_bytes(url.ptr, url.len, &small, small.len, &need));
    try testing.expectEqual(@as(u64, 10), need);
    var buf: [256]u8 = undefined;
    var out_len: u64 = 0;
    try testing.expectEqual(@as(i32, 1), sa_http_fetch_bytes("ftp://127.0.0.1/x".ptr, 17, &buf, buf.len, &out_len));
}
pub export fn sa_http_client_resp_body_ptr(resp: ?*anyopaque) ?[*]const u8 {
    const response = resp orelse return null;
    const value = @as(*HttpResponse, @ptrCast(@alignCast(response)));
    if (value.body.len == 0) return null;
    return value.body.ptr;
}
pub export fn sa_http_client_resp_body_len(resp: ?*anyopaque) u64 {
    const response = resp orelse return 0;
    return @as(*HttpResponse, @ptrCast(@alignCast(response))).body.len;
}
pub export fn sa_http_client_resp_body_reader(resp: ?*anyopaque, out_reader: ?*?*anyopaque) u32 {
    const response = resp orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_reader orelse return @intFromEnum(AbiStatus.failed);
    const resp_ptr = @as(*HttpResponse, @ptrCast(@alignCast(response)));
    const reader = HttpBodyReader.init(resp_ptr.allocator, resp_ptr.body) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(reader);
    return @intFromEnum(AbiStatus.ok);
}
fn bodyReaderReadChunk(reader: *HttpBodyReader, buf: []u8) usize {
    if (reader.cursor >= reader.body.len) return 0;
    const n = @min(buf.len, reader.body.len - reader.cursor);
    @memcpy(buf[0..n], reader.body[reader.cursor .. reader.cursor + n]);
    reader.cursor += n;
    return n;
}
pub export fn sa_http_client_resp_read_chunk(reader: ?*anyopaque, buf_ptr: ?[*]u8, cap: u64, out_len: ?*u64) u32 {
    const reader_ptr = reader orelse return @intFromEnum(AbiStatus.failed);
    const buf = buf_ptr orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_len orelse return @intFromEnum(AbiStatus.failed);
    const body_reader = @as(*HttpBodyReader, @ptrCast(@alignCast(reader_ptr)));
    const n = bodyReaderReadChunk(body_reader, buf[0..@intCast(cap)]);
    slot.* = n;
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_resp_free(resp: ?*anyopaque) u32 {
    const response = resp orelse return @intFromEnum(AbiStatus.failed);
    const resp_ptr = @as(*HttpResponse, @ptrCast(@alignCast(response)));
    resp_ptr.deinit();
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_body_reader_free(reader: ?*anyopaque) u32 {
    const value = reader orelse return @intFromEnum(AbiStatus.failed);
    const body_reader = @as(*HttpBodyReader, @ptrCast(@alignCast(value)));
    body_reader.deinit();
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_free(client: ?*anyopaque) u32 {
    const value = client orelse return @intFromEnum(AbiStatus.failed);
    const cli = @as(*HttpClient, @ptrCast(@alignCast(value)));
    cli.release();
    return @intFromEnum(AbiStatus.ok);
}
pub export fn sa_http_client_req_free(req: ?*anyopaque) u32 {
    const value = req orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(value)));
    request.deinit();
    return @intFromEnum(AbiStatus.ok);
}
