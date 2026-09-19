// WebSocket client runtime binding for the sci/sa_std platform layer.
//
// Pure-Zig RFC 6455 WebSocket client. The transport is either a plain TCP
// stream (ws://) or a sa_tls_client TLS session (wss://); the wss:// path
// reuses src/runtime/sa_tls_client.zig wholesale — CA bundle, SNI, hostname
// verification — so there is deliberately no second TLS implementation here.
// wss:// peer verification is therefore exactly the sa_tls_client policy and
// there is no verification-disabled mode on this surface either.
//
// Message model: send_text / send_binary transmit one message as a single
// frame (client frames are always masked, RFC 6455 5.3). recv() reassembles
// fragmented messages, answers pings with pongs automatically, ignores
// unsolicited pongs, and surfaces a peer close as opcode 8 with an empty
// payload — the caller then calls close() to release the handle.
//
// Blocking I/O throughout, same as sa_tls_client: connect() dials and runs
// the HTTP Upgrade handshake synchronously; recv() blocks for the next
// complete message.
//
// Status codes follow the sci convention: 0 = SA_STD_OK, negative = error.
// Certificate verification failures on wss:// propagate SA_STD_ERR_TLS_VERIFY
// (-100) from the TLS layer.
//
// Handles are heap-allocated WsClientHandle structs packed into a u64;
// 0 == invalid. close() consumes the handle (double-close is a caller bug,
// same as the other protocol sinks).

const std = @import("std");
const primitives = @import("sa_net_primitives.zig");
const tls_client = @import("sa_tls_client.zig");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_TLS_VERIFY: i32 = -100;

pub const WS_OPCODE_TEXT: u32 = 1;
pub const WS_OPCODE_BINARY: u32 = 2;
pub const WS_OPCODE_CLOSE: u32 = 8;

const Transport = union(enum) {
    tcp: std.net.Stream,
    tls: u64, // sa_tls_client handle
};

const WsClientHandle = struct {
    transport: Transport,
    recv_buf: std.ArrayListUnmanaged(u8),
    host: []u8, // owned copy, for status/debug
    peer_closed: bool,
    close_sent: bool,
};

const WsError = error{
    EndOfStream,
    HandshakeFailed,
    ProtocolViolation,
    Closed,
    OutOfMemory,
};

fn handleFromU64(handle: u64) *WsClientHandle {
    // Heap pointers from page_allocator are 16-byte aligned; alignCast keeps
    // this sound on targets (aarch64) where @ptrFromInt is stricter.
    const p: *WsClientHandle = @ptrFromInt(handle);
    return @alignCast(p);
}

// ---- transport ---------------------------------------------------------------

fn transportRead(t: Transport, buf: []u8) WsError!usize {
    std.debug.assert(buf.len != 0);
    switch (t) {
        .tcp => |stream| {
            return stream.read(buf) catch return WsError.EndOfStream;
        },
        .tls => |th| {
            var n: u64 = 0;
            const rc = tls_client.sa_std_tls_client_read(th, buf.ptr, @as(u64, @intCast(buf.len)), &n);
            if (rc != SA_STD_OK) return WsError.EndOfStream;
            return @as(usize, @intCast(n));
        },
    }
}

fn transportWriteAll(t: Transport, buf: []const u8) WsError!void {
    var off: usize = 0;
    while (off < buf.len) {
        const n: usize = switch (t) {
            .tcp => |stream| stream.write(buf[off..]) catch return WsError.EndOfStream,
            .tls => |th| blk: {
                var w: u64 = 0;
                const rc = tls_client.sa_std_tls_client_write(th, buf[off..].ptr, @as(u64, @intCast(buf.len - off)), &w);
                if (rc != SA_STD_OK) return WsError.EndOfStream;
                break :blk @as(usize, @intCast(w));
            },
        };
        if (n == 0) return WsError.EndOfStream;
        off += n;
    }
}

fn transportClose(t: Transport) void {
    switch (t) {
        .tcp => |stream| stream.close(),
        .tls => |th| _ = tls_client.sa_std_tls_client_close(th),
    }
}

fn freeHandle(h: *WsClientHandle) void {
    const alloc = std.heap.page_allocator;
    transportClose(h.transport);
    alloc.free(h.host);
    h.recv_buf.deinit(alloc);
    alloc.destroy(h);
}

// ---- HTTP Upgrade handshake ---------------------------------------------------

fn readMore(h: *WsClientHandle) WsError!void {
    var tmp: [32768]u8 = undefined;
    const n = try transportRead(h.transport, &tmp);
    if (n == 0) return WsError.EndOfStream;
    h.recv_buf.appendSlice(std.heap.page_allocator, tmp[0..n]) catch return WsError.OutOfMemory;
}

fn doHandshake(h: *WsClientHandle, parts: primitives.UrlParts) WsError!void {
    const alloc = std.heap.page_allocator;

    var key_raw: [16]u8 = undefined;
    std.crypto.random.bytes(&key_raw);
    var key_b64: [24]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&key_b64, &key_raw);

    // IPv6 literals carry ':' and must be bracketed in the Host header.
    const host_hdr = if (std.mem.indexOfScalar(u8, parts.host, ':') != null)
        std.fmt.allocPrint(alloc, "[{s}]:{d}", .{ parts.host, parts.port }) catch return WsError.OutOfMemory
    else
        std.fmt.allocPrint(alloc, "{s}:{d}", .{ parts.host, parts.port }) catch return WsError.OutOfMemory;
    defer alloc.free(host_hdr);

    const req = std.fmt.allocPrint(alloc,
        "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n\r\n",
        .{ parts.path, host_hdr, key_b64 }) catch return WsError.OutOfMemory;
    defer alloc.free(req);

    try transportWriteAll(h.transport, req);

    // Read until the end of the response headers; 32 KiB cap.
    h.recv_buf.clearRetainingCapacity();
    var hdr_end: ?usize = null;
    while (hdr_end == null) {
        if (h.recv_buf.items.len >= 32768) return WsError.HandshakeFailed;
        try readMore(h);
        if (std.mem.indexOf(u8, h.recv_buf.items, "\r\n\r\n")) |i| hdr_end = i + 4;
    }
    const hs = h.recv_buf.items[0..hdr_end.?];

    // Status line must be "HTTP/x.y 101 ...".
    const line_end = std.mem.indexOf(u8, hs, "\r\n") orelse return WsError.HandshakeFailed;
    const status_line = hs[0..line_end];
    if (!std.mem.startsWith(u8, status_line, "HTTP/")) return WsError.HandshakeFailed;
    const sp = std.mem.indexOfScalar(u8, status_line, ' ') orelse return WsError.HandshakeFailed;
    const after = status_line[sp + 1 ..];
    const code_tok = after[0..(std.mem.indexOfScalar(u8, after, ' ') orelse after.len)];
    const code = std.fmt.parseInt(u16, code_tok, 10) catch return WsError.HandshakeFailed;
    if (code != 101) return WsError.HandshakeFailed;

    // Sec-WebSocket-Accept, header name matched case-insensitively.
    var accept: ?[]const u8 = null;
    var lines = std.mem.splitSequence(u8, hs, "\r\n");
    _ = lines.next(); // status line
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "sec-websocket-accept")) {
            accept = std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    const expected = primitives.websocketAccept(&key_b64) catch return WsError.HandshakeFailed;
    const got = accept orelse return WsError.HandshakeFailed;
    if (!std.mem.eql(u8, got, expected[0..])) return WsError.HandshakeFailed;

    // Keep any bytes pipelined past the headers for the frame loop.
    const leftover_len = h.recv_buf.items.len - hdr_end.?;
    std.mem.copyForwards(u8, h.recv_buf.items[0..leftover_len], h.recv_buf.items[hdr_end.?..]);
    h.recv_buf.shrinkRetainingCapacity(leftover_len);
}

// ---- framing -------------------------------------------------------------------

fn sendFrame(h: *WsClientHandle, opcode: u8, payload: []const u8) WsError!void {
    if (h.peer_closed) return WsError.Closed;
    var mask: [4]u8 = undefined;
    std.crypto.random.bytes(&mask);
    const alloc = std.heap.page_allocator;
    // Max header is 14 bytes (1 + 8 length + 4 mask); provably enough.
    const out = alloc.alloc(u8, 14 + payload.len) catch return WsError.OutOfMemory;
    defer alloc.free(out);
    const n = primitives.buildWsFrame(opcode, true, payload, &mask, out) catch unreachable;
    try transportWriteAll(h.transport, out[0..n]);
}

fn sendCloseFrame(h: *WsClientHandle, code: u16, reason: []const u8) WsError!void {
    std.debug.assert(reason.len <= 123);
    var payload: [125]u8 = undefined;
    payload[0] = @as(u8, @intCast(code >> 8));
    payload[1] = @as(u8, @intCast(code & 0xff));
    @memcpy(payload[2 .. 2 + reason.len], reason);
    try sendFrame(h, 0x8, payload[0 .. 2 + reason.len]);
}

const InFrame = struct {
    fin: bool,
    opcode: u8,
    payload: []u8, // owned; caller frees
};

fn nextFrame(h: *WsClientHandle) WsError!InFrame {
    const alloc = std.heap.page_allocator;
    while (true) {
        if (h.recv_buf.items.len < 2) {
            try readMore(h);
            continue;
        }
        // RFC 6455 enforcement, before parsing:
        // - RSV1/2/3 must be 0: we never negotiate extensions (5.2).
        // - a server MUST NOT mask frames it sends (5.1).
        if (h.recv_buf.items[0] & 0x70 != 0) return WsError.ProtocolViolation;
        if (h.recv_buf.items[1] & 0x80 != 0) return WsError.ProtocolViolation;
        const fr = primitives.parseWsFrame(h.recv_buf.items) catch |err| switch (err) {
            error.Incomplete => {
                try readMore(h);
                continue;
            },
            error.Invalid => return WsError.ProtocolViolation,
        };
        // Control frames must be unfragmented with payload <= 125 (RFC 6455 5.5).
        if (fr.opcode >= 0x8 and (!fr.fin or fr.payload_len > 125)) return WsError.ProtocolViolation;
        // A close frame carries either no body or a 2-byte code + reason (7.1.5):
        // a 1-byte body can never be a valid close code.
        if (fr.opcode == 0x8 and fr.payload_len == 1) return WsError.ProtocolViolation;
        const payload = alloc.dupe(u8, h.recv_buf.items[fr.payload_start .. fr.payload_start + fr.payload_len]) catch return WsError.OutOfMemory;
        errdefer alloc.free(payload);
        const rest_len = h.recv_buf.items.len - fr.frame_len;
        std.mem.copyForwards(u8, h.recv_buf.items[0..rest_len], h.recv_buf.items[fr.frame_len..]);
        h.recv_buf.shrinkRetainingCapacity(rest_len);
        return .{ .fin = fr.fin, .opcode = fr.opcode, .payload = payload };
    }
}

// Text messages must be valid UTF-8 (RFC 6455 5.6); validated on the
// reassembled message since UTF-8 sequences may span fragments.
fn checkTextUtf8(opcode: u8, payload: []const u8) WsError!void {
    if (opcode == 0x1 and !std.unicode.utf8ValidateSlice(payload)) return WsError.ProtocolViolation;
}

// ---- exported surface ------------------------------------------------------------

pub export fn sa_std_ws_client_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    // Pure-Zig backend (no dlopen, no external library): always available
    // wherever sa_std itself builds.
    slot.* = 1;
    return SA_STD_OK;
}

pub export fn sa_std_ws_client_connect(url_ptr: ?[*]const u8, url_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const url = if (url_ptr) |p| p[0..url_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (url.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;

    const parts = primitives.parseUrlParts(url) catch return SA_STD_ERR_INVALID_ARGUMENT;
    const is_tls = std.mem.eql(u8, parts.scheme, "wss");
    if (!is_tls and !std.mem.eql(u8, parts.scheme, "ws")) return SA_STD_ERR_INVALID_ARGUMENT;

    const alloc = std.heap.page_allocator;
    const h = alloc.create(WsClientHandle) catch return SA_STD_ERR_NO_MEMORY;
    h.* = .{
        .transport = undefined,
        .recv_buf = .{},
        .host = alloc.dupe(u8, parts.host) catch {
            alloc.destroy(h);
            return SA_STD_ERR_NO_MEMORY;
        },
        .peer_closed = false,
        .close_sent = false,
    };
    // NOTE: this function returns i32, so errdefer is dead code here -- every
    // failure path below frees/closes explicitly.
    if (is_tls) {
        var th: u64 = 0;
        // Propagate the TLS layer's codes as-is: -100 stays -100.
        const rc = tls_client.sa_std_tls_client_connect(parts.host.ptr, @as(u64, @intCast(parts.host.len)), parts.port, &th);
        if (rc != SA_STD_OK) {
            alloc.free(h.host);
            h.recv_buf.deinit(alloc);
            alloc.destroy(h);
            return rc;
        }
        h.transport = .{ .tls = th };
    } else {
        const stream = std.net.tcpConnectToHost(alloc, parts.host, parts.port) catch {
            alloc.free(h.host);
            h.recv_buf.deinit(alloc);
            alloc.destroy(h);
            return SA_STD_ERR_IO;
        };
        h.transport = .{ .tcp = stream };
    }

    doHandshake(h, parts) catch |err| {
        transportClose(h.transport);
        alloc.free(h.host);
        h.recv_buf.deinit(alloc);
        alloc.destroy(h);
        return switch (err) {
            WsError.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            WsError.HandshakeFailed, WsError.ProtocolViolation, WsError.EndOfStream, WsError.Closed => SA_STD_ERR_IO,
        };
    };

    slot.* = @intFromPtr(h);
    return SA_STD_OK;
}

pub export fn sa_std_ws_client_add_ca_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    // The wss:// transport IS sa_tls_client; its bundle is the one we extend.
    const p = path_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT;
    return tls_client.sa_std_tls_client_add_ca_file(p, path_len);
}

fn sendImpl(handle: u64, opcode: u8, buf: ?[*]const u8, len: u64) i32 {
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const h = handleFromU64(handle);
    const payload: []const u8 = if (len == 0) "" else (buf orelse return SA_STD_ERR_INVALID_ARGUMENT)[0..@as(usize, @intCast(len))];
    // Control payloads are capped at 125 bytes by the frame format.
    if (opcode >= 0x8 and payload.len > 125) return SA_STD_ERR_INVALID_ARGUMENT;
    sendFrame(h, opcode, payload) catch |err| {
        return switch (err) {
            WsError.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            WsError.Closed, WsError.EndOfStream, WsError.HandshakeFailed, WsError.ProtocolViolation => SA_STD_ERR_IO,
        };
    };
    return SA_STD_OK;
}

pub export fn sa_std_ws_client_send_text(handle: u64, buf: ?[*]const u8, len: u64) i32 {
    return sendImpl(handle, 0x1, buf, len);
}

pub export fn sa_std_ws_client_send_binary(handle: u64, buf: ?[*]const u8, len: u64) i32 {
    return sendImpl(handle, 0x2, buf, len);
}

pub export fn sa_std_ws_client_ping(handle: u64, buf: ?[*]const u8, len: u64) i32 {
    return sendImpl(handle, 0x9, buf, len);
}

fn recvImpl(h: *WsClientHandle, opcode_slot: *u32, buf_slot: *u64) WsError!void {
    const alloc = std.heap.page_allocator;
    var msg = std.ArrayListUnmanaged(u8){};
    defer msg.deinit(alloc);
    var msg_opcode: u8 = 0;
    var in_fragment = false;

    while (true) {
        const fr = try nextFrame(h);
        defer alloc.free(fr.payload);
        switch (fr.opcode) {
            0x8 => { // close: reply if we haven't, then surface opcode 8
                if (!h.close_sent) {
                    sendCloseFrame(h, 1000, "") catch {};
                    h.close_sent = true;
                }
                h.peer_closed = true;
                opcode_slot.* = WS_OPCODE_CLOSE;
                buf_slot.* = try registerBuffer(try alloc.dupe(u8, ""));
                return;
            },
            0x9 => { // ping: auto-pong with identical payload
                sendFrame(h, 0xA, fr.payload) catch {};
            },
            0xA => {}, // unsolicited pong: ignore
            0x1, 0x2 => {
                if (in_fragment) return WsError.ProtocolViolation;
                if (fr.fin) {
                    try checkTextUtf8(fr.opcode, fr.payload);
                    opcode_slot.* = fr.opcode;
                    buf_slot.* = try registerBuffer(try alloc.dupe(u8, fr.payload));
                    return;
                }
                msg_opcode = fr.opcode;
                try msg.appendSlice(alloc, fr.payload);
                in_fragment = true;
            },
            0x0 => { // continuation
                if (!in_fragment) return WsError.ProtocolViolation;
                try msg.appendSlice(alloc, fr.payload);
                if (fr.fin) {
                    try checkTextUtf8(msg_opcode, msg.items);
                    opcode_slot.* = msg_opcode;
                    buf_slot.* = try registerBuffer(try msg.toOwnedSlice(alloc));
                    return;
                }
            },
            else => return WsError.ProtocolViolation,
        }
    }
}

pub export fn sa_std_ws_client_recv(handle: u64, out_opcode: ?*u32, out_buf_handle: ?*u64) i32 {
    const opcode_slot = out_opcode orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const buf_slot = out_buf_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    opcode_slot.* = 0;
    buf_slot.* = 0;
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const h = handleFromU64(handle);
    recvImpl(h, opcode_slot, buf_slot) catch |err| {
        return switch (err) {
            WsError.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            WsError.EndOfStream, WsError.HandshakeFailed, WsError.ProtocolViolation, WsError.Closed => SA_STD_ERR_IO,
        };
    };
    return SA_STD_OK;
}

pub export fn sa_std_ws_client_close(handle: u64, code: u16, reason_ptr: ?[*]const u8, reason_len: u64) i32 {
    if (handle == 0) return SA_STD_OK;
    const h = handleFromU64(handle);
    // close() consumes the handle on every path below.
    if (reason_len > 123) {
        freeHandle(h);
        return SA_STD_ERR_INVALID_ARGUMENT;
    }
    const reason: []const u8 = if (reason_len == 0) "" else (reason_ptr orelse {
        freeHandle(h);
        return SA_STD_ERR_INVALID_ARGUMENT;
    })[0..@as(usize, @intCast(reason_len))];
    if (!h.close_sent and !h.peer_closed) {
        sendCloseFrame(h, code, reason) catch {};
        h.close_sent = true;
    }
    freeHandle(h);
    return SA_STD_OK;
}

pub export fn sa_std_ws_client_status_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var buffer: [192]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"module\":\"ws_client\",\"backend\":\"pure-zig-rfc6455\",\"supported\":true,\"wss\":true}}", .{}) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerBufferOwned(owned, slot);
}

// ---- buffer handle registry (same shape as sa_tls_client.zig) --------------------

var string_registry_mutex = std.Thread.Mutex{};
var string_registry = std.ArrayListUnmanaged(?[]u8){};

fn registerBuffer(bytes: []u8) WsError!u64 {
    string_registry_mutex.lock();
    defer string_registry_mutex.unlock();
    var i: usize = 0;
    while (i < string_registry.items.len) : (i += 1) {
        if (string_registry.items[i] == null) {
            string_registry.items[i] = bytes;
            return @as(u64, @intCast(i + 1));
        }
    }
    string_registry.append(std.heap.page_allocator, bytes) catch return WsError.OutOfMemory;
    return @as(u64, @intCast(string_registry.items.len));
}

fn registerBufferOwned(bytes: []u8, slot: *u64) i32 {
    const id = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return switch (err) {
            WsError.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            else => SA_STD_ERR_IO,
        };
    };
    slot.* = id;
    return SA_STD_OK;
}

fn takeBuffer(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    string_registry_mutex.lock();
    defer string_registry_mutex.unlock();
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return null;
    return string_registry.items[idx];
}

pub export fn sa_std_ws_client_buffer_data(handle: u64) ?[*]const u8 {
    const s = takeBuffer(handle) orelse return null;
    return s.ptr;
}

pub export fn sa_std_ws_client_buffer_len(handle: u64) u64 {
    const s = takeBuffer(handle) orelse return 0;
    return @as(u64, @intCast(s.len));
}

pub export fn sa_std_ws_client_buffer_free(handle: u64) i32 {
    string_registry_mutex.lock();
    defer string_registry_mutex.unlock();
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = string_registry.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    string_registry.items[idx] = null;
    std.heap.page_allocator.free(entry);
    return SA_STD_OK;
}

// ============================================================================
// Unit tests.
// ============================================================================

const testing = std.testing;

test "supported is always 1: pure-Zig backend, no dlopen" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_supported(&flag));
    try testing.expectEqual(@as(u32, 1), flag);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_supported(null));
}

test "connect rejects bad urls without touching the network" {
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_connect(null, 0, &h));
    const empty = "";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_connect(empty.ptr, 0, &h));
    const http = "http://example.com/";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_connect(http.ptr, http.len, &h));
    const noscheme = "example.com/socket";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_connect(noscheme.ptr, noscheme.len, &h));
    const badport = "ws://example.com:notaport/";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_connect(badport.ptr, badport.len, &h));
    try testing.expectEqual(@as(u64, 0), h);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_connect(http.ptr, http.len, null));
}

test "rfc6455 accept-key reference vector" {
    // RFC 6455, section 1.3: key "dGhlIHNhbXBsZSBub25jZQ==" -> accept below.
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const accept = try primitives.websocketAccept(key);
    try testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept[0..]);
}

test "send/recv/close contract on the invalid (0) handle" {
    var opcode: u32 = 0;
    var msg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_send_text(0, "x".ptr, 1));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_send_text(0, null, 0));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_recv(0, &opcode, &msg));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_recv(0, null, &msg));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_recv(0, &opcode, null));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(0, 1000, null, 0));
    // ping payload over 125 bytes is a protocol violation at the API boundary
    var big: [126]u8 = undefined;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_ping(0, &big, big.len));
}

test "status json + buffer trio round-trips" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_status_json(&handle));
    try testing.expect(handle != 0);
    const ptr = sa_std_ws_client_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_ws_client_buffer_len(handle);
    try testing.expect(len != 0);
    const json = ptr[0..@as(usize, @intCast(len))];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"ws_client\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"wss\":true") != null);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_ws_client_buffer_free(handle));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_ws_client_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_ws_client_buffer_len(0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_buffer_free(0));
}

// ---- loopback integration: scripted echo server --------------------------------
// The server speaks just enough RFC 6455 to verify the client: HTTP upgrade,
// masked-frame parsing, echo, and a mid-script server->client ping whose pong
// it verifies. Deterministic, no sleeps.

const SrvScript = struct {
    listener: std.net.Server,
    err: *?anyerror,
};

fn srvReadFrame(stream: std.net.Stream, fbuf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !struct { opcode: u8, payload: []u8 } {
    var tmp: [8192]u8 = undefined;
    while (true) {
        const fr = primitives.parseWsFrame(fbuf.items) catch |e| {
            if (e == error.Incomplete) {
                const n = try stream.read(&tmp);
                if (n == 0) return error.Eof;
                try fbuf.appendSlice(alloc, tmp[0..n]);
                continue;
            }
            return e;
        };
        const payload = try alloc.dupe(u8, fbuf.items[fr.payload_start .. fr.payload_start + fr.payload_len]);
        errdefer alloc.free(payload);
        if (fr.masked) primitives.unmaskFrame(payload, fr.mask);
        const rest_len = fbuf.items.len - fr.frame_len;
        std.mem.copyForwards(u8, fbuf.items[0..rest_len], fbuf.items[fr.frame_len..]);
        fbuf.shrinkRetainingCapacity(rest_len);
        return .{ .opcode = fr.opcode, .payload = payload };
    }
}

fn srvSendFrame(stream: std.net.Stream, opcode: u8, payload: []const u8, alloc: std.mem.Allocator) !void {
    // Servers MUST NOT mask.
    const out = try alloc.alloc(u8, 14 + payload.len);
    defer alloc.free(out);
    const n = try primitives.buildWsFrame(opcode, true, payload, null, out);
    try stream.writeAll(out[0..n]);
}

fn wsScriptedServer(listener: *std.net.Server) !void {
    defer listener.deinit();
    const alloc = testing.allocator;
    var conn = try listener.accept();
    defer conn.stream.close();
    const stream = conn.stream;

    // --- HTTP Upgrade ---
    var req = std.ArrayListUnmanaged(u8){};
    defer req.deinit(alloc);
    var tmp: [4096]u8 = undefined;
    while (std.mem.indexOf(u8, req.items, "\r\n\r\n") == null) {
        if (req.items.len > 32768) return error.ReqTooLarge;
        const n = try stream.read(&tmp);
        if (n == 0) return error.Eof;
        try req.appendSlice(alloc, tmp[0..n]);
    }
    var key: ?[]const u8 = null;
    var lines = std.mem.splitSequence(u8, req.items, "\r\n");
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "sec-websocket-key")) {
            key = std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    const accept = try primitives.websocketAccept(key orelse return error.NoKey);
    var resp: [256]u8 = undefined;
    const resp_s = try std.fmt.bufPrint(&resp, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
    try stream.writeAll(resp_s);

    // --- scripted frame exchange ---
    var fbuf = std.ArrayListUnmanaged(u8){};
    defer fbuf.deinit(alloc);

    // 1. echo a text message
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x1), fr.opcode);
        try testing.expectEqualStrings("hello-ws", fr.payload);
        try srvSendFrame(stream, 0x1, fr.payload, alloc);
    }
    // 2. echo a binary message
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x2), fr.opcode);
        try testing.expectEqualStrings("bin-payload", fr.payload);
        try srvSendFrame(stream, 0x2, fr.payload, alloc);
    }
    // 3. server -> client ping; client must auto-pong with identical payload.
    // The client does NOT send anything before its next recv(), so the pong
    // is guaranteed to be the next client frame — no race.
    try srvSendFrame(stream, 0x9, "srv-ping", alloc);
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0xA), fr.opcode);
        try testing.expectEqualStrings("srv-ping", fr.payload);
    }
    // 4. liveness probe after the pong: the client's recv() must have
    // answered the ping internally and kept going.
    try srvSendFrame(stream, 0x1, "ping-done", alloc);
    // 5. echo another text message
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x1), fr.opcode);
        try testing.expectEqualStrings("after-ping", fr.payload);
        try srvSendFrame(stream, 0x1, fr.payload, alloc);
    }
    // 6. expect the client's close, reply close
    {
        const fr = try srvReadFrame(stream, &fbuf, alloc);
        defer alloc.free(fr.payload);
        try testing.expectEqual(@as(u8, 0x8), fr.opcode);
        try testing.expect(fr.payload.len >= 2);
        try testing.expectEqual(@as(u16, 1000), std.mem.readInt(u16, fr.payload[0..2], .big));
        try testing.expectEqualStrings("done", fr.payload[2..]);
        try srvSendFrame(stream, 0x8, fr.payload, alloc);
    }
}

fn wsServerMain(ctx: SrvScript) void {
    var listener = ctx.listener;
    wsScriptedServer(&listener) catch |e| {
        ctx.err.* = e;
    };
}

fn recvText(h: u64, want_opcode: u32, want: []const u8) !void {
    var opcode: u32 = 0;
    var msg_h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_recv(h, &opcode, &msg_h));
    try testing.expectEqual(want_opcode, opcode);
    try testing.expect(msg_h != 0);
    const ptr = sa_std_ws_client_buffer_data(msg_h) orelse return error.MissingData;
    const got = ptr[0..@as(usize, @intCast(sa_std_ws_client_buffer_len(msg_h)))];
    try testing.expectEqualStrings(want, got);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_buffer_free(msg_h));
}

/// Runs the client side of the scripted exchange; used by both the IPv4 and
/// the IPv6 loopback tests.
fn runClientScript(url: []const u8) !void {
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_connect(url.ptr, url.len, &h));
    try testing.expect(h != 0);
    errdefer _ = sa_std_ws_client_close(h, 1000, "", 0);

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_text(h, "hello-ws".ptr, 8));
    try recvText(h, WS_OPCODE_TEXT, "hello-ws");

    const bin = "bin-payload";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_binary(h, bin.ptr, bin.len));
    try recvText(h, WS_OPCODE_BINARY, "bin-payload");

    // The server pings us after the binary echo; this recv() must answer
    // the ping internally and return the following "ping-done" message.
    try recvText(h, WS_OPCODE_TEXT, "ping-done");

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_text(h, "after-ping".ptr, 10));
    try recvText(h, WS_OPCODE_TEXT, "after-ping");

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(h, 1000, "done".ptr, 4));
}

test "loopback ws:// echo + server ping/pong + close handshake" {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    const port = listener.listen_address.getPort();

    var server_err: ?anyerror = null;
    const thread = try std.Thread.spawn(.{}, wsServerMain, .{SrvScript{ .listener = listener, .err = &server_err }});

    const url = try std.fmt.allocPrint(testing.allocator, "ws://127.0.0.1:{d}/chat", .{port});
    defer testing.allocator.free(url);
    try runClientScript(url);

    thread.join();
    try testing.expectEqual(@as(?anyerror, null), server_err);
}

test "loopback ws:// over IPv6 [::1]" {
    const addr = try std.net.Address.parseIp6("::1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    const port = listener.listen_address.getPort();

    var server_err: ?anyerror = null;
    const thread = try std.Thread.spawn(.{}, wsServerMain, .{SrvScript{ .listener = listener, .err = &server_err }});

    // Bracketed literal exercises parseUrlParts' IPv6 path and the Host
    // header bracketing; tcpConnectToHost resolves the bare "::1".
    const url = try std.fmt.allocPrint(testing.allocator, "ws://[::1]:{d}/v6", .{port});
    defer testing.allocator.free(url);
    try runClientScript(url);

    thread.join();
    try testing.expectEqual(@as(?anyerror, null), server_err);
}

test "connect to a closed port fails cleanly" {
    // Grab a port, close it, then connect: expect IO error, handle stays 0.
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{});
    const port = listener.listen_address.getPort();
    listener.deinit();

    const url = try std.fmt.allocPrint(testing.allocator, "ws://127.0.0.1:{d}/", .{port});
    defer testing.allocator.free(url);
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_ws_client_connect(url.ptr, url.len, &h));
    try testing.expectEqual(@as(u64, 0), h);
}

// ---- protocol-violation tests: raw TCP server speaking bad frames --------------

const ViolationServer = struct {
    listener: *std.net.Server,
    frame: []const u8,
    fn run(self: *ViolationServer) void {
        self.runImpl() catch {};
    }
    fn runImpl(self: *ViolationServer) !void {
        var conn = try self.listener.accept();
        defer conn.stream.close();
        var buf: [8192]u8 = undefined;
        var total: usize = 0;
        while (total < buf.len) {
            const n = conn.stream.read(buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
        }
        var key: []const u8 = "";
        var lines = std.mem.splitSequence(u8, buf[0..total], "\r\n");
        while (lines.next()) |line| {
            if (line.len > 18 and std.ascii.eqlIgnoreCase(line[0..18], "sec-websocket-key:")) {
                key = std.mem.trim(u8, line[18..], " \t");
            }
        }
        const accept = primitives.websocketAccept(key) catch return;
        var resp: [256]u8 = undefined;
        const resp_str = std.fmt.bufPrint(&resp,
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
            .{accept}) catch return;
        conn.stream.writeAll(resp_str) catch return;
        conn.stream.writeAll(self.frame) catch {};
        // Hold the connection briefly so the client reads the bad frame.
        std.time.sleep(500 * std.time.ns_per_ms);
    }
};

fn expectViolation(frame: []const u8) !void {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{});
    defer listener.deinit();
    const port = listener.listen_address.getPort();
    var srv = ViolationServer{ .listener = &listener, .frame = frame };
    const t = try std.Thread.spawn(.{}, ViolationServer.run, .{&srv});
    defer t.join();

    const url = try std.fmt.allocPrint(testing.allocator, "ws://127.0.0.1:{d}/", .{port});
    defer testing.allocator.free(url);
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_connect(url.ptr, url.len, &h));
    errdefer _ = sa_std_ws_client_close(h, 1000, "", 0);
    var opcode: u32 = 0;
    var bh: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_ws_client_recv(h, &opcode, &bh));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(h, 1000, "", 0));
}

test "server protocol violations fail recv with -5" {
    // Masked frame from server (RFC 6455 5.1: server MUST NOT mask).
    try expectViolation(&.{ 0x81, 0x82, 0x01, 0x02, 0x03, 0x04, 'h' ^ 0x01, 'i' ^ 0x02 });
    // RSV1 set with no extensions negotiated (5.2).
    try expectViolation(&.{ 0xC1, 0x02, 'h', 'i' });
    // Text frame with invalid UTF-8 payload (5.6).
    try expectViolation(&.{ 0x81, 0x02, 0xFF, 0xFE });
    // Close frame with a 1-byte body: never a valid close code (7.1.5).
    try expectViolation(&.{ 0x88, 0x01, 0x03 });
}

// ---- wss:// integration: python stdlib TLS server --------------------------------
// openssl generates a self-signed CN=localhost cert; the python server
// terminates TLS and speaks just enough WebSocket to echo one message.
// Iteration 1 is the unpinned (-100) probe, iteration 2 the pinned round-trip.

const wss_server_py =
    \\import socket, ssl, hashlib, base64, sys
    \\
    \\cert_path, key_path, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
    \\
    \\ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    \\ctx.load_cert_chain(cert_path, key_path)
    \\
    \\srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    \\srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    \\srv.bind(("127.0.0.1", port))
    \\srv.listen(4)
    \\print("READY", flush=True)
    \\
    \\GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    \\
    \\def read_frame(tls):
    \\    buf = b""
    \\    while True:
    \\        if len(buf) >= 2:
    \\            b0, b1 = buf[0], buf[1]
    \\            op = b0 & 0x0F
    \\            masked = (b1 & 0x80) != 0
    \\            ln = b1 & 0x7F
    \\            i = 2
    \\            ok = True
    \\            if ln == 126:
    \\                if len(buf) < 4:
    \\                    ok = False
    \\                else:
    \\                    ln = int.from_bytes(buf[2:4], "big")
    \\                    i = 4
    \\            elif ln == 127:
    \\                if len(buf) < 10:
    \\                    ok = False
    \\                else:
    \\                    ln = int.from_bytes(buf[2:10], "big")
    \\                    i = 10
    \\            if ok:
    \\                hlen = i + (4 if masked else 0)
    \\                if len(buf) >= hlen + ln:
    \\                    if masked:
    \\                        m = buf[i:i+4]
    \\                        pl = bytes(c ^ m[j % 4] for j, c in enumerate(buf[i+4:i+4+ln]))
    \\                    else:
    \\                        pl = buf[hlen:hlen+ln]
    \\                    return op, pl
    \\        chunk = tls.recv(65536)
    \\        if not chunk:
    \\            return None, None
    \\        buf += chunk
    \\
    \\def send_frame(tls, op, payload):
    \\    hdr = bytes([0x80 | op])
    \\    ln = len(payload)
    \\    if ln < 126:
    \\        hdr += bytes([ln])
    \\    elif ln < 65536:
    \\        hdr += bytes([126]) + ln.to_bytes(2, "big")
    \\    else:
    \\        hdr += bytes([127]) + ln.to_bytes(8, "big")
    \\    tls.sendall(hdr + payload)
    \\
    \\for _ in range(2):
    \\    try:
    \\        conn, _ = srv.accept()
    \\    except Exception:
    \\        break
    \\    try:
    \\        tls = ctx.wrap_socket(conn, server_side=True)
    \\    except Exception:
    \\        continue
    \\    try:
    \\        data = b""
    \\        while b"\r\n\r\n" not in data:
    \\            chunk = tls.recv(4096)
    \\            if not chunk:
    \\                raise Exception("eof")
    \\            data += chunk
    \\        key = None
    \\        for line in data.decode("latin1").split("\r\n"):
    \\            if line.lower().startswith("sec-websocket-key:"):
    \\                key = line.split(":", 1)[1].strip()
    \\        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    \\        tls.sendall(("HTTP/1.1 101 Switching Protocols\r\n"
    \\                     "Upgrade: websocket\r\n"
    \\                     "Connection: Upgrade\r\n"
    \\                     "Sec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
    \\        op, pl = read_frame(tls)
    \\        if op == 1:
    \\            send_frame(tls, 1, pl)
    \\        try:
    \\            tls.settimeout(5)
    \\            read_frame(tls)
    \\        except Exception:
    \\            pass
    \\    except Exception:
    \\        pass
    \\    try:
    \\        tls.close()
    \\    except Exception:
    \\        pass
    \\
;

fn makeSelfSigned(alloc: std.mem.Allocator, cert_path: []const u8, key_path: []const u8) !void {
    // NOTE: the OU keeps this test's subject distinct from the tls_client
    // tests' "/CN=localhost": std's Bundle keeps only the FIRST cert per
    // subject name and silently drops later ones, so two pinned self-signed
    // certs with identical subjects would collide in the shared bundle.
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days",  "1",   "-nodes", "-subj", "/CN=localhost/OU=sa-ws-client-test",
    };
    var child = std.process.Child.init(&args, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.OpensslFailed,
    }
}

test "loopback wss:// via python ssl server, pinned CA and -100 without pin" {
    const alloc = testing.allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const dirpath = try td.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dirpath);

    const cert_path = try std.fs.path.join(alloc, &.{ dirpath, "cert.pem" });
    defer alloc.free(cert_path);
    const key_path = try std.fs.path.join(alloc, &.{ dirpath, "key.pem" });
    defer alloc.free(key_path);
    try makeSelfSigned(alloc, cert_path, key_path);

    const probe = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(.{ .reuse_address = true });
    const port = listener.listen_address.getPort();
    listener.deinit();
    const port_str = try std.fmt.allocPrint(alloc, "{d}", .{port});
    defer alloc.free(port_str);

    const py_path = try std.fs.path.join(alloc, &.{ dirpath, "wss_srv.py" });
    defer alloc.free(py_path);
    try td.dir.writeFile(.{ .sub_path = "wss_srv.py", .data = wss_server_py });

    var child = std.process.Child.init(&.{ "python3", py_path, cert_path, key_path, port_str }, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    errdefer _ = child.kill() catch {};

    // Wait for READY on the server's stdout.
    var ready: [16]u8 = undefined;
    var ready_len: usize = 0;
    while (ready_len < ready.len) {
        const n = try child.stdout.?.read(ready[ready_len..]);
        if (n == 0) return error.ServerDied;
        ready_len += n;
        if (std.mem.indexOf(u8, ready[0..ready_len], "\n") != null) break;
    }
    try testing.expect(std.mem.startsWith(u8, ready[0..ready_len], "READY"));

    const url = try std.fmt.allocPrint(alloc, "wss://localhost:{d}/secure", .{port});
    defer alloc.free(url);

    // Without the pinned CA the self-signed chain must fail verification.
    {
        var h: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_ERR_TLS_VERIFY), sa_std_ws_client_connect(url.ptr, url.len, &h));
        try testing.expectEqual(@as(u64, 0), h);
    }

    // Pin the CA, then the full wss round-trip works.
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_add_ca_file(cert_path.ptr, cert_path.len));
    {
        var h: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_connect(url.ptr, url.len, &h));
        errdefer _ = sa_std_ws_client_close(h, 1000, "", 0);
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_send_text(h, "hello-wss".ptr, 9));
        try recvText(h, WS_OPCODE_TEXT, "hello-wss");
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_ws_client_close(h, 1000, "", 0));
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.ServerAbnormalExit,
    }
}
