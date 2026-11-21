const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");
const sio = @import("sio");
const ws_net = @import("sa_ws_stream");
const AbiStatus = @import("h04.zig").AbiStatus;
const HIST_SEG_EXIT = @import("h01.zig").HIST_SEG_EXIT;
const HttpRequest = @import("h03.zig").HttpRequest;
const HttpResponse = @import("h03.zig").HttpResponse;
const HttpServer = @import("h02.zig").HttpServer;
const HttpStreamResponse = @import("h03.zig").HttpStreamResponse;
const WebSocketHandle = @import("h03.zig").WebSocketHandle;
const closeWebSocketV2 = @import("h04.zig").closeWebSocketV2;
const findHeader = @import("h03.zig").findHeader;
const max_v2_message_bytes = @import("h01.zig").max_v2_message_bytes;
const networkStatus = @import("h04.zig").networkStatus;
const nowMicros = @import("h01.zig").nowMicros;
const pollStream = @import("h01.zig").pollStream;
const pollWebSocketV2 = @import("h03.zig").pollWebSocketV2;
const readFrameV2 = @import("h04.zig").readFrameV2;
const sa_http_server_accept_v2 = @import("h04.zig").sa_http_server_accept_v2;
const sa_http_server_new_v2 = @import("h04.zig").sa_http_server_new_v2;
const sa_http_server_req_free_v2 = @import("h04.zig").sa_http_server_req_free_v2;
const sa_http_server_req_get_path = @import("h04.zig").sa_http_server_req_get_path;
const sa_http_server_resp_new_v2 = @import("h04.zig").sa_http_server_resp_new_v2;
const sa_http_server_resp_send_v2 = @import("h04.zig").sa_http_server_resp_send_v2;
const sa_http_server_start_v2 = @import("h04.zig").sa_http_server_start_v2;
const sa_http_server_websocket_upgrade = @import("h04.zig").sa_http_server_websocket_upgrade;
const setReceiveTimeout = @import("h01.zig").setReceiveTimeout;
const statusFromError = @import("h01.zig").statusFromError;
const streamWriteAll = @import("h03.zig").streamWriteAll;
const validWebSocketKey = @import("h04.zig").validWebSocketKey;
const writeFrameV2 = @import("h03.zig").writeFrameV2;

// Header-only send (HEAD): same response object and header bag as
// resp_send_v2, but the wire carries the caller-declared
// content-length and zero body bytes. resp_send_v2 is unchanged.
pub export fn sa_http_server_resp_send_head_v2(resp: ?*anyopaque, content_length: u64, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const exit_t0 = nowMicros();
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    const send_result = response.sendHeadOnly(content_length);
    response.request.server.histRecord(HIST_SEG_EXIT, @intCast(@max(0, nowMicros() - exit_t0)));
    send_result catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

// Raw request target of a v2 request, exactly as it arrived on
// the request line (path + "?" + query, absolute-form untouched).
// req_get_path strips the query; this getter exists so proxies
// and loggers can see the whole target. The returned slice is
// borrowed from the request and stays valid until req_free.
pub export fn sa_http_server_req_get_target_v2(req: ?*anyopaque, out_target_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const target_slot = out_target_ptr orelse return networkStatus(.invalid);
    const len_slot = out_len orelse return networkStatus(.invalid);
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    target_slot.* = request.target.ptr;
    len_slot.* = request.target.len;
    return networkStatus(.ok);
}

// Query component of a v2 request's target: the bytes after the
// first "?", without the "?" itself. A target with no "?" returns
// ok with a zero length (no query is a normal case, not an
// error); the out pointer then addresses the end of the target.
pub export fn sa_http_server_req_get_query_v2(req: ?*anyopaque, out_query_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const query_slot = out_query_ptr orelse return networkStatus(.invalid);
    const len_slot = out_len orelse return networkStatus(.invalid);
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const target = request.target;
    if (std.mem.indexOfScalar(u8, target, '?')) |idx| {
        const query = target[idx + 1 ..];
        query_slot.* = query.ptr;
        len_slot.* = query.len;
    } else {
        query_slot.* = target.ptr + target.len;
        len_slot.* = 0;
    }
    return networkStatus(.ok);
}

// File-body send (G3'): frames the response head with
// content-length = count and streams the file body with
// sendfile(2) -- the static-serving shape resp_send_v2 cannot
// express (it would need the whole file in memory). file_fd is a
// borrowed OS descriptor for an already-open readable file (see
// sa_std_fs_file_fd); it is NOT closed here. out_sent always
// receives the number of file bytes written, including on
// failure. Status values are the v2 network statuses, plus one
// extension: 8 = unsupported (the platform has no sendfile;
// NOTHING was sent, so the caller may still answer with an
// explicit error response). There is no buffered fallback: a
// short send (the file shrank after being measured) is reported
// as io_error with out_sent < count, never as success.
pub export fn sa_http_server_resp_send_file_v2(resp: ?*anyopaque, file_fd: i64, offset: u64, count: u64, timeout_ms: u32, out_sent: ?*u64) u32 {
    const sent_slot = out_sent orelse return networkStatus(.invalid);
    sent_slot.* = 0;
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (file_fd < 0 or file_fd > std.math.maxInt(std.posix.fd_t)) return networkStatus(.invalid);
    if (comptime builtin.cpu.arch.isWasm() or builtin.os.tag != .linux) return 8;
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const exit_t0 = nowMicros();
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    const send_result = response.sendFile(@intCast(file_fd), offset, count);
    response.request.server.histRecord(HIST_SEG_EXIT, @intCast(@max(0, nowMicros() - exit_t0)));
    const sent = send_result catch |err| return networkStatus(statusFromError(err));
    sent_slot.* = sent;
    if (sent != count) return networkStatus(.io_error);
    return networkStatus(.ok);
}

// Peer (remote) address of a v2 request, as text + port: the access
// log's remote field and per-request ACLs both need exactly this.
// The address text goes to out[0..out_len): dotted quad for IPv4;
// IPv6 in full (uncompressed) groups. If out_cap is too small the
// call returns too_large and out_len reports the needed size (the
// port is still written). Linux resolves via getpeername(2); other
// native platforms use the libc call; WASM has no sockets and
// returns invalid.
pub export fn sa_http_server_req_peer_addr_v2(req: ?*anyopaque, out: ?[*]u8, out_cap: u64, out_len: ?*u64, out_port: ?*u32) u32 {
    const len_slot = out_len orelse return networkStatus(.invalid);
    const port_slot = out_port orelse return networkStatus(.invalid);
    len_slot.* = 0;
    port_slot.* = 0;
    const req_ptr = req orelse return networkStatus(.invalid);
    if (out_cap > 0 and out == null) return networkStatus(.invalid);
    if (out_cap > std.math.maxInt(usize)) return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const fd = request.stream().socket.handle;
    var storage: [128]u8 align(4) = std.mem.zeroes([128]u8);
    var addr_len: u32 = storage.len;
    if (comptime builtin.cpu.arch.isWasm()) {
        return networkStatus(.invalid);
    } else if (comptime builtin.os.tag == .linux) {
        const rc = std.os.linux.getpeername(fd, @ptrCast(&storage), &addr_len);
        if (std.os.linux.errno(rc) != .SUCCESS) return networkStatus(.io_error);
    } else {
        const getpeername_c = struct {
            extern "c" fn getpeername(fd: std.posix.fd_t, addr: *anyopaque, len: *u32) c_int;
        }.getpeername;
        if (getpeername_c(fd, @ptrCast(&storage), &addr_len) != 0) return networkStatus(.io_error);
    }
    const family: u16 = std.mem.readInt(u16, storage[0..2], .little);
    const port_be: u16 = std.mem.readInt(u16, storage[2..4], .big);
    port_slot.* = port_be;
    var text_buf: [64]u8 = undefined;
    const text: []const u8 = switch (family) {
        2 => std.fmt.bufPrint(&text_buf, "{d}.{d}.{d}.{d}", .{ storage[4], storage[5], storage[6], storage[7] }) catch return networkStatus(.io_error),
        10 => blk: {
            var groups: [8]u16 = undefined;
            for (&groups, 0..) |*group, i| {
                group.* = std.mem.readInt(u16, storage[8 + i * 2 ..][0..2], .big);
            }
            break :blk std.fmt.bufPrint(&text_buf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{ groups[0], groups[1], groups[2], groups[3], groups[4], groups[5], groups[6], groups[7] }) catch return networkStatus(.io_error);
        },
        else => return networkStatus(.invalid),
    };
    len_slot.* = text.len;
    if (out_cap < text.len) return networkStatus(.too_large);
    if (out) |dst| @memcpy(dst[0..text.len], text);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_free_v2(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_new_v2(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const slot = out_resp orelse return networkStatus(.invalid);
    slot.* = null;
    const req_ptr = req orelse return networkStatus(.invalid);
    if (status < 100 or status > 599) return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpStreamResponse.initDeferred(request, status) catch return networkStatus(.io_error);
    slot.* = @ptrCast(response);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_add_header_v2(resp: ?*anyopaque, name_ptr: ?[*]const u8, name_len: u64, value_ptr: ?[*]const u8, value_len: u64) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (name_len == 0 or name_len > std.math.maxInt(usize) or value_len > std.math.maxInt(usize)) return networkStatus(.invalid);
    const name = name_ptr orelse return networkStatus(.invalid);
    const value = if (value_ptr) |ptr| ptr[0..@intCast(value_len)] else blk: {
        if (value_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    response.setHeader(name[0..@intCast(name_len)], value) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_write_v2(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (body_len > max_v2_message_bytes) return networkStatus(.too_large);
    const body = if (body_ptr) |ptr| ptr[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return networkStatus(.closed);
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    response.writeChunk(body) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_flush_v2(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return networkStatus(.closed);
    response.flush() catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_end_v2(resp: ?*anyopaque, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return networkStatus(.closed);
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    response.endChunked() catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_stream_free_v2(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return networkStatus(.ok);
}

pub export fn sa_http_server_free_v2(server: ?*anyopaque) u32 {
    const server_ptr = server orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.deinit();
    return networkStatus(.ok);
}

pub export fn sa_http_server_websocket_upgrade_v2(req: ?*anyopaque, out_ws: ?*?*anyopaque) u32 {
    const slot = out_ws orelse return networkStatus(.invalid);
    slot.* = null;
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const version = findHeader(request, "sec-websocket-version") orelse return networkStatus(.invalid);
    const key = findHeader(request, "sec-websocket-key") orelse return networkStatus(.invalid);
    if (!std.mem.eql(u8, version, "13") or !validWebSocketKey(key)) return networkStatus(.invalid);

    var raw_ws: ?*anyopaque = null;
    if (sa_http_server_websocket_upgrade(req, &raw_ws) != @intFromEnum(AbiStatus.ok)) return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(raw_ws orelse return networkStatus(.io_error))));
    handle.enableV2() catch {
        handle.deinit();
        return networkStatus(.io_error);
    };
    slot.* = raw_ws;
    return networkStatus(.ok);
}

pub export fn sa_http_server_websocket_poll_v2(ws: ?*anyopaque, interests: u32, timeout_ms: u32, out_events: ?*u32) u32 {
    const events_slot = out_events orelse return networkStatus(.invalid);
    events_slot.* = 0;
    const ws_ptr = ws orelse return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return networkStatus(pollWebSocketV2(handle, interests, timeout_ms, events_slot));
}

pub export fn sa_http_server_websocket_read_v2(ws: ?*anyopaque, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const opcode_slot = out_opcode orelse return networkStatus(.invalid);
    const ptr_slot = out_ptr orelse return networkStatus(.invalid);
    const len_slot = out_len orelse return networkStatus(.invalid);
    opcode_slot.* = 0;
    ptr_slot.* = null;
    len_slot.* = 0;
    const ws_ptr = ws orelse return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return networkStatus(readFrameV2(handle, max_len, opcode_slot, ptr_slot, len_slot));
}

pub export fn sa_http_server_websocket_write_v2(ws: ?*anyopaque, opcode: u8, data_ptr: ?[*]const u8, data_len: u64, out_written: ?*u64) u32 {
    const written_slot = out_written orelse return networkStatus(.invalid);
    written_slot.* = 0;
    const ws_ptr = ws orelse return networkStatus(.invalid);
    if (data_len > max_v2_message_bytes) return networkStatus(.too_large);
    const payload = if (data_ptr) |ptr| ptr[0..@intCast(data_len)] else blk: {
        if (data_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    const status = writeFrameV2(handle, opcode, payload);
    if (status == .ok) written_slot.* = data_len;
    return networkStatus(status);
}

pub export fn sa_http_server_websocket_close_v2(ws: ?*anyopaque, code: u16, reason_ptr: ?[*]const u8, reason_len: u64) u32 {
    const ws_ptr = ws orelse return networkStatus(.invalid);
    if (reason_len > 123) return networkStatus(.too_large);
    const reason = if (reason_ptr) |ptr| ptr[0..@intCast(reason_len)] else blk: {
        if (reason_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return networkStatus(closeWebSocketV2(handle, code, reason));
}

pub export fn sa_http_server_websocket_free_v2(ws: ?*anyopaque) u32 {
    const ws_ptr = ws orelse return networkStatus(.invalid);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    handle.deinit();
    return networkStatus(.ok);
}

test "v2 send_head carries declared content-length without body; peer addr is the loopback client" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18231));

    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18231);
    var client = try address.connect(sio.io(), .{ .mode = .stream });
    defer client.close(sio.io());
    try streamWriteAll(client, "HEAD /thing HTTP/1.1\r\nhost: x\r\n\r\n");

    var req_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req_slot));
    const request = req_slot orelse return error.TestUnexpectedResult;

    // G2: peer address is the loopback client, port = client's own
    // local port (cross-checked through getsockname on the client).
    var ip_buf: [64]u8 = undefined;
    var ip_len: u64 = 0;
    var peer_port: u32 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_peer_addr_v2(request, &ip_buf, ip_buf.len, &ip_len, &peer_port));
    try std.testing.expectEqualStrings("127.0.0.1", ip_buf[0..@intCast(ip_len)]);
    var client_storage: [128]u8 align(4) = std.mem.zeroes([128]u8);
    var client_len: u32 = client_storage.len;
    const grc = std.os.linux.getsockname(client.socket.handle, @ptrCast(&client_storage), &client_len);
    try std.testing.expect(std.os.linux.errno(grc) == .SUCCESS);
    const client_port: u32 = std.mem.readInt(u16, client_storage[2..4], .big);
    try std.testing.expectEqual(client_port, peer_port);
    // Too-small buffer: too_large + needed length reported.
    var tiny: [4]u8 = undefined;
    var tiny_len: u64 = 0;
    var tiny_port: u32 = 0;
    try std.testing.expectEqual(@as(u32, 4), sa_http_server_req_peer_addr_v2(request, &tiny, tiny.len, &tiny_len, &tiny_port));
    try std.testing.expectEqual(@as(u64, 9), tiny_len);

    // G1: header-only send with a declared content-length of 1234.
    var resp_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request, 200, &resp_slot));
    const resp = resp_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_resp_free_v2(resp);
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_head_v2(resp, 1234, 5000));

    // The client receives exactly the head: status line, the
    // declared content-length, and no body bytes after the blank
    // line (the connection stays open under keep-alive, so any
    // extra byte within 300 ms would be a body leak).
    var rbuf: [512]u8 = undefined;
    var total: usize = 0;
    while (std.mem.indexOf(u8, rbuf[0..total], "\r\n\r\n") == null) {
        const rc = std.c.read(client.socket.handle, @ptrCast(rbuf[total..].ptr), rbuf.len - total);
        if (rc <= 0) return error.TestUnexpectedResult;
        total += @intCast(rc);
    }
    const head_text = rbuf[0..total];
    try std.testing.expect(std.mem.indexOf(u8, head_text, "HTTP/1.1 200") != null);
    try std.testing.expect(std.mem.indexOf(u8, head_text, "content-length: 1234") != null);
    var poll_fds = [1]std.posix.pollfd{.{ .fd = client.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
    const ready = std.posix.poll(&poll_fds, 300) catch return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 0), ready);

    _ = sa_http_server_req_free_v2(request);
}

test "v2 req_get_target/req_get_query expose the raw target and query (G4)" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18234));
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18234);

    // Request WITH a query string: target is verbatim, query is
    // the bytes after the first '?', path stays query-free.
    var client = try address.connect(sio.io(), .{ .mode = .stream });
    try streamWriteAll(client, "GET /api/echo?x=1&y=%32 HTTP/1.1\r\nhost: x\r\n\r\n");
    var req_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req_slot));
    const request = req_slot orelse return error.TestUnexpectedResult;
    var t_ptr: ?[*]const u8 = null;
    var t_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_target_v2(request, &t_ptr, &t_len));
    try std.testing.expectEqualStrings("/api/echo?x=1&y=%32", t_ptr.?[0..t_len]);
    var q_ptr: ?[*]const u8 = null;
    var q_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_query_v2(request, &q_ptr, &q_len));
    try std.testing.expectEqualStrings("x=1&y=%32", q_ptr.?[0..q_len]);
    var p_ptr: ?[*]const u8 = null;
    var p_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_path(request, &p_ptr, &p_len));
    try std.testing.expectEqualStrings("/api/echo", p_ptr.?[0..p_len]);
    var resp_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request, 200, &resp_slot));
    const resp = resp_slot orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_head_v2(resp, 0, 5000));
    _ = sa_http_server_resp_free_v2(resp);
    _ = sa_http_server_req_free_v2(request);
    client.close(sio.io());

    // Request WITHOUT a query string: ok status, zero length.
    var client2 = try address.connect(sio.io(), .{ .mode = .stream });
    defer client2.close(sio.io());
    try streamWriteAll(client2, "GET /plain HTTP/1.1\r\nhost: x\r\n\r\n");
    var req2_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req2_slot));
    const request2 = req2_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_req_free_v2(request2);
    var q2_ptr: ?[*]const u8 = null;
    var q2_len: u64 = 99;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_query_v2(request2, &q2_ptr, &q2_len));
    try std.testing.expectEqual(@as(u64, 0), q2_len);
    var t2_ptr: ?[*]const u8 = null;
    var t2_len: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_req_get_target_v2(request2, &t2_ptr, &t2_len));
    try std.testing.expectEqualStrings("/plain", t2_ptr.?[0..t2_len]);
    var resp2_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request2, 200, &resp2_slot));
    const resp2 = resp2_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_resp_free_v2(resp2);
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_head_v2(resp2, 0, 5000));
}

test "v2 resp_send_file streams the file body kernel-side (G3')" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const content = "sendfile-body-0123456789";
    const fd = std.c.open("/tmp/sa_sendfile_test_body.txt", .{ .ACCMODE = .RDWR, .CREAT = true, .TRUNC = true }, @as(std.c.mode_t, 0o644));
    if (fd < 0) return error.TestUnexpectedResult;
    defer _ = std.c.close(fd);
    if (std.c.write(fd, content.ptr, content.len) != @as(isize, @intCast(content.len))) return error.TestUnexpectedResult;

    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18235));
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18235);
    var client = try address.connect(sio.io(), .{ .mode = .stream });
    defer client.close(sio.io());
    try streamWriteAll(client, "GET /body.txt HTTP/1.1\r\nhost: x\r\n\r\n");

    var req_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_accept_v2(server, 5000, &req_slot));
    const request = req_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_req_free_v2(request);
    var resp_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_new_v2(request, 200, &resp_slot));
    const resp = resp_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_resp_free_v2(resp);
    var sent: u64 = 0;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_resp_send_file_v2(resp, @intCast(fd), 0, content.len, 5000, &sent));
    try std.testing.expectEqual(@as(u64, content.len), sent);

    // The client receives the framed head (content-length =
    // count) followed by exactly the file bytes.
    var rbuf: [1024]u8 = undefined;
    var total: usize = 0;
    while (total < rbuf.len) {
        const rc = std.c.read(client.socket.handle, @ptrCast(rbuf[total..].ptr), rbuf.len - total);
        if (rc <= 0) break;
        total += @intCast(rc);
        if (std.mem.indexOf(u8, rbuf[0..total], "\r\n\r\n")) |hend| {
            if (total >= hend + 4 + content.len) break;
        }
    }
    const got = rbuf[0..total];
    const hend = std.mem.indexOf(u8, got, "\r\n\r\n") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, got[0..hend], "content-length: 24") != null);
    try std.testing.expectEqualStrings(content, got[hend + 4 ..][0..content.len]);
}

test "v2 accept: concurrent acceptors receive each request exactly once (def-accept claim)" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var server_slot: ?*anyopaque = null;
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_new_v2(&server_slot));
    const server = server_slot orelse return error.TestUnexpectedResult;
    defer _ = sa_http_server_free_v2(server);
    const host = "127.0.0.1";
    try std.testing.expectEqual(@as(u32, 0), sa_http_server_start_v2(server, host.ptr, host.len, 18251));

    const Ctx = struct {
        server: *anyopaque,
        stop_at: usize,
        got: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        failed: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        fn worker(ctx: *@This()) void {
            while (ctx.got.load(.acquire) < ctx.stop_at) {
                var slot: ?*anyopaque = null;
                const st = sa_http_server_accept_v2(ctx.server, 3000, &slot);
                if (st != 0) {
                    // Quota filled while this acceptor was parked:
                    // a timeout then is a clean exit, not a failure.
                    if (ctx.got.load(.acquire) >= ctx.stop_at) return;
                    _ = ctx.failed.fetchAdd(1, .monotonic);
                    return;
                }
                const req = slot orelse {
                    _ = ctx.failed.fetchAdd(1, .monotonic);
                    return;
                };
                _ = ctx.got.fetchAdd(1, .monotonic);
                var resp_slot: ?*anyopaque = null;
                if (sa_http_server_resp_new_v2(req, 200, &resp_slot) == 0) {
                    const resp = resp_slot.?;
                    const body = "ok";
                    _ = sa_http_server_resp_send_v2(resp, body.ptr, body.len, 5000);
                    _ = sa_http_server_resp_free_v2(resp);
                }
                _ = sa_http_server_req_free_v2(req);
            }
        }
        fn readResponse(client: std.Io.net.Stream) !void {
            var buf: [512]u8 = undefined;
            var total: usize = 0;
            while (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") == null) {
                const rc = std.c.read(client.socket.handle, @ptrCast(buf[total..].ptr), buf.len - total);
                if (rc <= 0) return error.TestUnexpectedResult;
                total += @intCast(rc);
            }
            const head_end = std.mem.indexOf(u8, buf[0..total], "\r\n\r\n").? + 4;
            var body_got: usize = total - head_end;
            while (body_got < 2) {
                const rc = std.c.read(client.socket.handle, @ptrCast(buf[total..].ptr), buf.len - total);
                if (rc <= 0) return error.TestUnexpectedResult;
                total += @intCast(rc);
                body_got += @intCast(rc);
            }
        }
    };

    // 36 requests total: phase 1 = 12 keep-alive connections x 2
    // requests (second accept comes out of the recycled pool, i.e.
    // the claim path), phase 2 = 12 fresh connections x 1 request.
    var ctx = Ctx{ .server = server, .stop_at = 36 };
    var threads: [8]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Ctx.worker, .{&ctx});
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 18251);
    var c1: usize = 0;
    while (c1 < 12) : (c1 += 1) {
        var client = try address.connect(sio.io(), .{ .mode = .stream });
        defer client.close(sio.io());
        try setReceiveTimeout(client, 10000);
        try streamWriteAll(client, "GET /a HTTP/1.1\r\nhost: x\r\n\r\n");
        try Ctx.readResponse(client);
        try streamWriteAll(client, "GET /b HTTP/1.1\r\nhost: x\r\nconnection: close\r\n\r\n");
        try Ctx.readResponse(client);
    }
    var c2: usize = 0;
    while (c2 < 12) : (c2 += 1) {
        var client = try address.connect(sio.io(), .{ .mode = .stream });
        defer client.close(sio.io());
        try setReceiveTimeout(client, 10000);
        try streamWriteAll(client, "GET /c HTTP/1.1\r\nhost: x\r\nconnection: close\r\n\r\n");
        try Ctx.readResponse(client);
    }
    for (&threads) |*t| t.join();
    try std.testing.expectEqual(@as(usize, 0), ctx.failed.load(.acquire));
    try std.testing.expectEqual(@as(usize, 36), ctx.got.load(.acquire));
}
