const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");
const sio = @import("sio");
const ws_net = @import("sa_ws_stream");
const HIST_SEG_EXIT = @import("h01.zig").HIST_SEG_EXIT;
const HttpRequest = @import("h03.zig").HttpRequest;
const HttpResponse = @import("h03.zig").HttpResponse;
const HttpServer = @import("h02.zig").HttpServer;
const HttpStreamResponse = @import("h03.zig").HttpStreamResponse;
const NetworkStatus = @import("h01.zig").NetworkStatus;
const WebSocketHandle = @import("h03.zig").WebSocketHandle;
const WebSocketOpcode = @import("h01.zig").WebSocketOpcode;
const decodeV2Frame = @import("h03.zig").decodeV2Frame;
const ensureProcessSignalSafety = @import("h01.zig").ensureProcessSignalSafety;
const findHeader = @import("h03.zig").findHeader;
const flushPendingWrite = @import("h03.zig").flushPendingWrite;
const headerContainsToken = @import("h03.zig").headerContainsToken;
const hist_buckets = @import("h01.zig").hist_buckets;
const hist_segments = @import("h01.zig").hist_segments;
const max_v2_message_bytes = @import("h01.zig").max_v2_message_bytes;
const nowMicros = @import("h01.zig").nowMicros;
const pollStream = @import("h01.zig").pollStream;
const readFrame = @import("h03.zig").readFrame;
const replaceLastMessage = @import("h03.zig").replaceLastMessage;
const statusFromError = @import("h01.zig").statusFromError;
const streamReadSome = @import("h03.zig").streamReadSome;
const streamWriteAll = @import("h03.zig").streamWriteAll;
const websocketFrameSize = @import("h03.zig").websocketFrameSize;
const writeFrame = @import("h03.zig").writeFrame;
const writeFrameV2 = @import("h03.zig").writeFrameV2;

pub fn readFrameV2(handle: *WebSocketHandle, max_len_u64: u64, out_opcode: *u8, out_ptr: *?[*]const u8, out_len: *u64) NetworkStatus {
    out_opcode.* = 0;
    out_ptr.* = null;
    out_len.* = 0;
    if (handle.peer_closed or handle.close_received) return .closed;
    handle.enableV2() catch return .io_error;
    const max_len: usize = @intCast(@min(max_len_u64, @as(u64, max_v2_message_bytes)));

    while (true) {
        const decoded = decodeV2Frame(handle, max_len) catch |err| {
            const status = statusFromError(err);
            if (status == .too_large or status == .invalid) handle.peer_closed = true;
            return status;
        };
        if (decoded) |frame| {
            switch (frame.opcode) {
                @intFromEnum(WebSocketOpcode.ping) => {
                    const pong_status = writeFrameV2(handle, @intFromEnum(WebSocketOpcode.pong), frame.payload);
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                    if (pong_status != .ok) return pong_status;
                    continue;
                },
                @intFromEnum(WebSocketOpcode.pong) => {
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                    continue;
                },
                @intFromEnum(WebSocketOpcode.connection_close) => {
                    if (frame.payload.len == 1) {
                        handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .invalid;
                    }
                    if (frame.payload.len >= 2) {
                        const code = std.mem.readInt(u16, frame.payload[0..2], .big);
                        if (!validCloseCode(code) or !std.unicode.utf8ValidateSlice(frame.payload[2..])) {
                            handle.allocator.free(frame.payload);
                            handle.peer_closed = true;
                            return .invalid;
                        }
                    }
                    handle.close_received = true;
                    out_opcode.* = frame.opcode;
                    replaceLastMessage(handle, frame.payload, out_ptr, out_len);
                    return .ok;
                },
                @intFromEnum(WebSocketOpcode.text), @intFromEnum(WebSocketOpcode.binary) => {
                    if (handle.fragmented_opcode != null) {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .invalid;
                    }
                    if (frame.fin) {
                        if (frame.opcode == @intFromEnum(WebSocketOpcode.text) and !std.unicode.utf8ValidateSlice(frame.payload)) {
                            if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                            handle.peer_closed = true;
                            return .invalid;
                        }
                        out_opcode.* = frame.opcode;
                        replaceLastMessage(handle, frame.payload, out_ptr, out_len);
                        return .ok;
                    }
                    handle.fragmented_opcode = frame.opcode;
                    handle.fragmented.appendSlice(frame.payload) catch {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        return .io_error;
                    };
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                },
                @intFromEnum(WebSocketOpcode.continuation) => {
                    const opcode = handle.fragmented_opcode orelse {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .invalid;
                    };
                    if (handle.fragmented.items.len + frame.payload.len > max_len or
                        handle.fragmented.items.len + frame.payload.len > max_v2_message_bytes)
                    {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        handle.peer_closed = true;
                        return .too_large;
                    }
                    handle.fragmented.appendSlice(frame.payload) catch {
                        if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                        return .io_error;
                    };
                    if (frame.payload.len != 0) handle.allocator.free(frame.payload);
                    if (frame.fin) {
                        const message = handle.fragmented.toOwnedSlice() catch return .io_error;
                        handle.fragmented = std.array_list.Managed(u8).init(handle.allocator);
                        handle.fragmented_opcode = null;
                        if (opcode == @intFromEnum(WebSocketOpcode.text) and !std.unicode.utf8ValidateSlice(message)) {
                            if (message.len != 0) handle.allocator.free(message);
                            handle.peer_closed = true;
                            return .invalid;
                        }
                        out_opcode.* = opcode;
                        replaceLastMessage(handle, message, out_ptr, out_len);
                        return .ok;
                    }
                },
                else => unreachable,
            }
            continue;
        }

        if (handle.incoming.items.len >= max_v2_message_bytes + 14) {
            handle.peer_closed = true;
            return .too_large;
        }
        var buffer: [4096]u8 = undefined;
        const capacity = max_v2_message_bytes + 14 - handle.incoming.items.len;
        const read_len = @min(buffer.len, capacity);
        const count = streamReadSome(handle.stream, buffer[0..read_len]) catch |err| return statusFromError(err);
        if (count == 0) {
            handle.peer_closed = true;
            return .closed;
        }
        handle.incoming.appendSlice(buffer[0..count]) catch return .io_error;
    }
}

pub fn validCloseCode(code: u16) bool {
    if (code < 1000 or code >= 5000) return false;
    return switch (code) {
        1004, 1005, 1006, 1015 => false,
        else => true,
    };
}

pub fn closeWebSocketV2(handle: *WebSocketHandle, code: u16, reason: []const u8) NetworkStatus {
    if (handle.peer_closed or handle.close_sent) return .closed;
    if (!validCloseCode(code) or reason.len > 123 or !std.unicode.utf8ValidateSlice(reason)) return .invalid;
    var payload: [125]u8 = undefined;
    std.mem.writeInt(u16, payload[0..2], code, .big);
    @memcpy(payload[2 .. 2 + reason.len], reason);

    handle.enableV2() catch return .io_error;
    const pending_status = flushPendingWrite(handle);
    if (pending_status != .ok) return pending_status;
    const frame_cap = websocketFrameSize(2 + reason.len) catch return .too_large;
    const frame = handle.allocator.alloc(u8, frame_cap) catch return .io_error;
    const frame_len = sa_std_net.buildWebSocketFrame(frame, @intFromEnum(WebSocketOpcode.connection_close), payload[0 .. 2 + reason.len], null) catch {
        handle.allocator.free(frame);
        return .invalid;
    };
    handle.pending_write = frame[0..frame_len];
    handle.pending_offset = 0;
    handle.close_sent = true;
    const status = flushPendingWrite(handle);
    return switch (status) {
        .would_block => .ok,
        else => status,
    };
}

pub fn methodStringAlloc(allocator: std.mem.Allocator, method: std.http.Method) ![]u8 {
    return allocator.dupe(u8, @tagName(method));
}

// ---------------------------------------------------------------------------
// SA-facing C ABI (sa_http_server_*). Moved from the plugin's
// http_saasm_api.zig; symbol names and status values are unchanged so
// existing .sai declarations and generated code link unmodified.
// AbiStatus mirrors the plugin ABI enum (ok=0, failed=2).
// ---------------------------------------------------------------------------
pub const AbiStatus = enum(u32) { ok = 0, failed = 2 };

pub const SaHttpServerHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpRequestHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpResponseHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpStreamResponseHandle = extern struct {
    impl: ?*anyopaque,
};

/// The HTTP server used to be initialized with `std.heap.page_allocator`, which
/// issues one `mmap` per small allocation and one `munmap` per free. Under the
/// SA host that used to be invisible because the host's `munmap` stub was a
/// no-op, so the process leaked ~55 KB per request. With the stub hidden (see
/// `sci/src/runtime/sa_std.zig`) those syscalls became real and per-request
/// throughput collapsed. Use libc malloc so small request objects are pooled.
pub fn serverAllocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

pub export fn sa_http_server_new(out_server: ?*?*anyopaque) u32 {
    ensureProcessSignalSafety();
    const slot = out_server orelse return @intFromEnum(AbiStatus.failed);
    const server = HttpServer.init(serverAllocator()) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(server);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_start(server: ?*anyopaque, host_ptr: ?[*]const u8, host_len: u64, port: u16) u32 {
    const server_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const host = host_ptr orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.start(host[0..@intCast(host_len)], port) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_accept(server: ?*anyopaque, out_req: ?*?*anyopaque) u32 {
    const server_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_req orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    const request = srv.accept() catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(request);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_req_get_method(req: ?*anyopaque, out_method_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const method_slot = out_method_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    method_slot.* = request.method.ptr;
    len_slot.* = request.method.len;
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_req_get_path(req: ?*anyopaque, out_path_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const path_slot = out_path_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const target = request.target;
    const path = if (std.mem.indexOfScalar(u8, target, '?')) |idx| target[0..idx] else target;
    path_slot.* = path.ptr;
    len_slot.* = path.len;
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_req_get_header(req: ?*anyopaque, key_ptr: ?[*]const u8, key_len: u64, out_val_ptr: ?*?[*]const u8, out_val_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const key = key_ptr orelse return @intFromEnum(AbiStatus.failed);
    const path_slot = out_val_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_val_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const wanted = key[0..@intCast(key_len)];
    for (request.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, wanted)) {
            path_slot.* = header.value.ptr;
            len_slot.* = header.value.len;
            return @intFromEnum(AbiStatus.ok);
        }
    }
    return @intFromEnum(AbiStatus.failed);
}

pub export fn sa_http_server_req_get_body(req: ?*anyopaque, out_body_ptr: ?*?[*]const u8, out_body_len: ?*u64) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const body_slot = out_body_ptr orelse return @intFromEnum(AbiStatus.failed);
    const len_slot = out_body_len orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    body_slot.* = request.body.ptr;
    len_slot.* = request.body.len;
    return @intFromEnum(AbiStatus.ok);
}

/// Frees a request. When the client negotiated keep-alive AND a fully-framed
/// response was sent, the TCP connection is recycled into the server's pool
/// for the next request instead of being closed.
pub fn recycleOrCloseRequest(request: *HttpRequest) void {
    if (request.response_done and request.keep_alive) {
        const srv = request.server;
        const conn = request.conn;
        // The client usually closes a connection-per-request socket right
        // after reading the response; recycling it would only fill the idle
        // pool with dead connections and slow every later accept to O(pool).
        if (HttpServer.isPeerClosed(conn.stream)) {
            request.deinit();
        } else {
            request.freeResources();
            request.allocator.destroy(request);
            srv.pushRecycled(conn);
        }
    } else {
        request.deinit();
    }
}

pub export fn sa_http_server_req_free(req: ?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    recycleOrCloseRequest(request);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_new(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_resp orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpResponse.init(request, status) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(response);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_send(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const body = if (body_ptr) |body| body[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return @intFromEnum(AbiStatus.failed);
        break :blk "";
    };
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.send(body) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_set_content_type(resp: ?*anyopaque, content_type_ptr: ?[*]const u8, content_type_len: u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const content_type = content_type_ptr orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.setContentType(content_type[0..@intCast(content_type_len)]) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_free(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_new(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_resp orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpStreamResponse.init(request, status) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(response);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_write(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const body = if (body_ptr) |body| body[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return @intFromEnum(AbiStatus.failed);
        break :blk "";
    };
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return @intFromEnum(AbiStatus.failed);
    response.writeChunk(body) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_flush(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return @intFromEnum(AbiStatus.failed);
    response.flush() catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_end(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    if (response.ended) return @intFromEnum(AbiStatus.failed);
    response.endChunked() catch return @intFromEnum(AbiStatus.failed);
    response.ended = true;
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_resp_stream_free(resp: ?*anyopaque) u32 {
    const resp_ptr = resp orelse return @intFromEnum(AbiStatus.failed);
    const response = @as(*HttpStreamResponse, @ptrCast(@alignCast(resp_ptr)));
    response.deinit();
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_free(server: ?*anyopaque) u32 {
    const server_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.deinit();
    return @intFromEnum(AbiStatus.ok);
}

/// Sets the v1 request body limit (default 2MB). Rejects 0 or >1GB.
/// v2's 16MB limit is unchanged.
pub export fn sa_http_server_set_max_body_bytes(server: ?*anyopaque, max_bytes: u64) u32 {
    const srv_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(srv_ptr)));
    srv.setMaxBodyLen(@intCast(max_bytes)) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

/// Runs a fixed-size plugin-internal accept loop: `num_threads` worker
/// threads invoke `handler(req, handler_ctx)` per accepted request (the
/// handler owns the request and must resp/upgrade + req_free it). Blocks
/// until sa_http_server_stop_serving is called or max_requests requests were
/// accepted (0 = unlimited). num_threads=0 uses the CPU count (1..256 clamp).
pub export fn sa_http_server_serve_threaded(
    server: ?*anyopaque,
    num_threads: u32,
    handler: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    handler_ctx: ?*anyopaque,
    max_requests: u64,
) u32 {
    const srv_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const h = handler orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(srv_ptr)));
    srv.serveThreaded(num_threads, h, handler_ctx, max_requests) catch return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

/// Signals a running sa_http_server_serve_threaded loop to stop. Wakes
/// workers blocked in poll() via listener shutdown; in-flight handlers run
/// to completion. The listening socket is shut down, so the server handle
/// cannot accept afterwards — free it once serve_threaded has returned.
pub export fn sa_http_server_stop_serving(server: ?*anyopaque) u32 {
    const srv_ptr = server orelse return @intFromEnum(AbiStatus.failed);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(srv_ptr)));
    srv.stopServing();
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_websocket_upgrade(req: ?*anyopaque, out_ws: ?*?*anyopaque) u32 {
    const req_ptr = req orelse return @intFromEnum(AbiStatus.failed);
    const slot = out_ws orelse return @intFromEnum(AbiStatus.failed);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));

    const upgrade = findHeader(request, "upgrade") orelse return @intFromEnum(AbiStatus.failed);
    if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) return @intFromEnum(AbiStatus.failed);
    const connection = findHeader(request, "connection") orelse return @intFromEnum(AbiStatus.failed);
    if (!headerContainsToken(connection, "upgrade")) return @intFromEnum(AbiStatus.failed);
    const key = findHeader(request, "sec-websocket-key") orelse return @intFromEnum(AbiStatus.failed);
    // DEF-WS-CLUSTER VERSION-TEXT: v1 upgrade accepted any
    // Sec-WebSocket-Version (e.g. 99); v2 upgrade already requires "13".
    // RFC 6455 4.1: the server MUST fail the handshake when the version
    // is not 13. Check here so v1 matches v2 on both backends.
    const version = findHeader(request, "sec-websocket-version") orelse return @intFromEnum(AbiStatus.failed);
    if (!std.mem.eql(u8, version, "13")) return @intFromEnum(AbiStatus.failed);

    var accept_buf: [28]u8 = undefined;
    const accept = ws_net.websocketAccept(key, &accept_buf) catch return @intFromEnum(AbiStatus.failed);

    var header_buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: {s}\r\n\r\n",
        .{accept},
    ) catch return @intFromEnum(AbiStatus.failed);
    streamWriteAll(request.stream(), response) catch return @intFromEnum(AbiStatus.failed);

    const handle = WebSocketHandle.initFromRequest(request) catch return @intFromEnum(AbiStatus.failed);
    slot.* = @ptrCast(handle);
    request.freeResources();
    request.allocator.destroy(request);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_websocket_read(ws: ?*anyopaque, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const ws_ptr = ws orelse return @intFromEnum(AbiStatus.failed);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    return readFrame(handle, max_len, out_opcode, out_ptr, out_len);
}

pub export fn sa_http_server_websocket_write(ws: ?*anyopaque, opcode: u8, data_ptr: ?[*]const u8, data_len: u64) u32 {
    const ws_ptr = ws orelse return @intFromEnum(AbiStatus.failed);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    const payload = if (data_ptr) |ptr| ptr[0..@intCast(data_len)] else &[_]u8{};
    if (!writeFrame(handle.stream, opcode, payload)) return @intFromEnum(AbiStatus.failed);
    return @intFromEnum(AbiStatus.ok);
}

pub export fn sa_http_server_websocket_free(ws: ?*anyopaque) u32 {
    const ws_ptr = ws orelse return @intFromEnum(AbiStatus.failed);
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(ws_ptr)));
    handle.deinit();
    return @intFromEnum(AbiStatus.ok);
}

pub fn networkStatus(status: NetworkStatus) u32 {
    return @intFromEnum(status);
}

pub fn validWebSocketKey(key: []const u8) bool {
    if (key.len != 24) return false;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(key) catch return false;
    if (decoded_len != 16) return false;
    var decoded: [16]u8 = undefined;
    std.base64.standard.Decoder.decode(&decoded, key) catch return false;
    return true;
}

pub export fn sa_http_server_new_v2(out_server: ?*?*anyopaque) u32 {
    ensureProcessSignalSafety();
    const slot = out_server orelse return networkStatus(.invalid);
    slot.* = null;
    const server = HttpServer.init(serverAllocator()) catch return networkStatus(.io_error);
    slot.* = @ptrCast(server);
    return networkStatus(.ok);
}

pub export fn sa_http_server_start_v2(server: ?*anyopaque, host_ptr: ?[*]const u8, host_len: u64, port: u16) u32 {
    const server_ptr = server orelse return networkStatus(.invalid);
    if (host_len == 0 or host_len > std.math.maxInt(usize)) return networkStatus(.invalid);
    const host = host_ptr orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    srv.start(host[0..@intCast(host_len)], port) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_accept_v2(server: ?*anyopaque, timeout_ms: u32, out_req: ?*?*anyopaque) u32 {
    const slot = out_req orelse return networkStatus(.invalid);
    slot.* = null;
    const server_ptr = server orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    // Tail-fix form 1: no discarded pre-poll. This export used to
    // poll the whole set once via pollAccept, throw the outcome
    // away, and let the bounded accept poll the same set again
    // (whose claim then polled a third time) -- three polls and
    // ~9 pool-lock holds per accepted request on the hot path.
    // The bounded accept now owns the single poll and threads
    // its outcome into the claim.
    const request = srv.acceptWithBodyLimitAndTimeout(max_v2_message_bytes, timeout_ms) catch |err| {
        if (err == error.WouldBlock or err == error.HttpHeadersUnreadable) return networkStatus(if (timeout_ms == 0) .would_block else .timeout);
        return networkStatus(statusFromError(err));
    };
    slot.* = @ptrCast(request);
    return networkStatus(.ok);
}

// Resident instrumentation readout (tail-fix D1): one bucket of
// one segment of the server's service-discipline histograms.
// Out-of-range segment/bucket reads return 0 (readout only; the
// counters themselves are the contract).
pub export fn sa_http_server_hist_v2(server: ?*anyopaque, segment: u32, bucket: u32) u64 {
    const server_ptr = server orelse return 0;
    if (segment >= hist_segments or bucket >= hist_buckets) return 0;
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    return srv.hist[segment][bucket].load(.monotonic);
}

pub export fn sa_http_server_hist_reset_v2(server: ?*anyopaque) u32 {
    const server_ptr = server orelse return networkStatus(.invalid);
    const srv = @as(*HttpServer, @ptrCast(@alignCast(server_ptr)));
    for (&srv.hist) |*seg| {
        for (seg) |*cell| cell.store(0, .monotonic);
    }
    srv.hist_served.store(0, .monotonic);
    return networkStatus(.ok);
}

pub export fn sa_http_server_req_free_v2(req: ?*anyopaque) u32 {
    const req_ptr = req orelse return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    recycleOrCloseRequest(request);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_new_v2(req: ?*anyopaque, status: u16, out_resp: ?*?*anyopaque) u32 {
    const slot = out_resp orelse return networkStatus(.invalid);
    slot.* = null;
    const req_ptr = req orelse return networkStatus(.invalid);
    if (status < 100 or status > 599) return networkStatus(.invalid);
    const request = @as(*HttpRequest, @ptrCast(@alignCast(req_ptr)));
    const response = HttpResponse.init(request, status) catch return networkStatus(.io_error);
    slot.* = @ptrCast(response);
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_add_header_v2(resp: ?*anyopaque, name_ptr: ?[*]const u8, name_len: u64, value_ptr: ?[*]const u8, value_len: u64) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (name_len == 0 or name_len > std.math.maxInt(usize) or value_len > std.math.maxInt(usize)) return networkStatus(.invalid);
    const name = name_ptr orelse return networkStatus(.invalid);
    const value = if (value_ptr) |ptr| ptr[0..@intCast(value_len)] else blk: {
        if (value_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    response.setHeader(name[0..@intCast(name_len)], value) catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}

pub export fn sa_http_server_resp_send_v2(resp: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64, timeout_ms: u32) u32 {
    const resp_ptr = resp orelse return networkStatus(.invalid);
    if (body_len > max_v2_message_bytes) return networkStatus(.too_large);
    const body = if (body_ptr) |ptr| ptr[0..@intCast(body_len)] else blk: {
        if (body_len != 0) return networkStatus(.invalid);
        break :blk "";
    };
    const response = @as(*HttpResponse, @ptrCast(@alignCast(resp_ptr)));
    const exit_t0 = nowMicros();
    const poll_status = pollStream(response.request.stream().socket.handle, std.posix.POLL.OUT, timeout_ms, null);
    if (poll_status != .ok) return networkStatus(poll_status);
    const send_result = response.send(body);
    response.request.server.histRecord(HIST_SEG_EXIT, @intCast(@max(0, nowMicros() - exit_t0)));
    send_result catch |err| return networkStatus(statusFromError(err));
    return networkStatus(.ok);
}
