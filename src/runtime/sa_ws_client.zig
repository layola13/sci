// WebSocket client runtime binding for the sci/sa_std platform layer.
test "sa_ws_client_tests" { std.testing.refAllDecls(@import("sa_ws_client_test.zig")); }
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
const builtin = @import("builtin");
pub const primitives = @import("sa_net_primitives");
pub const tls_client = @import("sa_tls_client.zig");
pub const sio = @import("sio");

pub const SA_STD_OK: i32 = 0;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
pub const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
pub const SA_STD_ERR_TLS_VERIFY: i32 = -100;

// wasm32-wasi: usize is 32-bit, C ABI passes u64 lengths. Checked conversion.
fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

pub const WS_OPCODE_TEXT: u32 = 1;
pub const WS_OPCODE_BINARY: u32 = 2;
pub const WS_OPCODE_CLOSE: u32 = 8;

const Transport = union(enum) {
    tcp: std.Io.net.Stream,
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
    // wasm32-wasi: usize is 32-bit, handle is u64 ABI (zero-extended pointer).
    const p: *WsClientHandle = @ptrFromInt(@as(usize, @intCast(handle)));
    return @alignCast(p);
}

// ---- transport ---------------------------------------------------------------

// NOTE(Zig 0.17): `std.Io.net.Stream` takes explicit `Io` and vectored
// buffers; these helpers preserve the old single-buffer call shapes.
pub fn tcpRead(stream: std.Io.net.Stream, buf: []u8) WsError!usize {
    if (comptime builtin.cpu.arch.isWasm()) return WsError.EndOfStream;
    std.debug.assert(buf.len != 0);
    var bufs: [1][]u8 = .{buf};
    const result = stream.readWithControl(sio.io(), &bufs, &.{}) catch return WsError.EndOfStream;
    return result.data_len;
}

pub fn tcpWriteAll(stream: std.Io.net.Stream, bytes: []const u8) WsError!void {
    var wbuf: [8192]u8 = undefined;
    var w = stream.writer(sio.io(), &wbuf);
    w.interface.writeAll(bytes) catch return WsError.EndOfStream;
    w.interface.flush() catch return WsError.EndOfStream;
}

pub fn boundPort(listener: *const std.Io.net.Server) u16 {
    return switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
}

// Same dial policy as sa_tls_client (literals direct, hostnames via
// Happy-Eyeballs HostName.connect); see dialHost there.
fn dialTcp(host: []const u8, port: u16) WsError!std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream }) catch return WsError.EndOfStream;
    } else |_| {}
    const hn = std.Io.net.HostName.init(host) catch return WsError.EndOfStream;
    return hn.connect(sio.io(), port, .{ .mode = .stream }) catch return WsError.EndOfStream;
}

fn transportRead(t: Transport, buf: []u8) WsError!usize {
    std.debug.assert(buf.len != 0);
    switch (t) {
        .tcp => |stream| {
            return try tcpRead(stream, buf);
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
    switch (t) {
        .tcp => |stream| try tcpWriteAll(stream, buf),
        .tls => |th| {
            var off: usize = 0;
            while (off < buf.len) {
                var w: u64 = 0;
                const rc = tls_client.sa_std_tls_client_write(th, buf[off..].ptr, @as(u64, @intCast(buf.len - off)), &w);
                if (rc != SA_STD_OK) return WsError.EndOfStream;
                const n: usize = @as(usize, @intCast(w));
                if (n == 0) return WsError.EndOfStream;
                off += n;
            }
        },
    }
}

fn transportClose(t: Transport) void {
    switch (t) {
        .tcp => |stream| stream.close(sio.io()),
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
    sio.io().random(&key_raw);
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
    sio.io().random(&mask);
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
    const url_n = u64ToUsize(url_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const url = if (url_ptr) |p| p[0..url_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (url.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;

    const parts = primitives.parseUrlParts(url) catch return SA_STD_ERR_INVALID_ARGUMENT;
    const is_tls = std.mem.eql(u8, parts.scheme, "wss");
    if (!is_tls and !std.mem.eql(u8, parts.scheme, "ws")) return SA_STD_ERR_INVALID_ARGUMENT;

    const alloc = std.heap.page_allocator;
    const h = alloc.create(WsClientHandle) catch return SA_STD_ERR_NO_MEMORY;
    h.* = .{
        .transport = undefined,
        .recv_buf = .empty,
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
        const stream = dialTcp(parts.host, parts.port) catch {
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
    var msg = std.ArrayListUnmanaged(u8).empty;
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

var string_registry_mutex = std.Io.Mutex.init;
var string_registry = std.ArrayListUnmanaged(?[]u8).empty;

fn registerBuffer(bytes: []u8) WsError!u64 {
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
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
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
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
    string_registry_mutex.lockUncancelable(sio.io());
    defer string_registry_mutex.unlock(sio.io());
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

pub const testing = std.testing;

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

pub const SrvScript = @import("sa_ws_client_test.zig").SrvScript;

pub const srvReadFrame = @import("sa_ws_client_test.zig").srvReadFrame;

pub const srvSendFrame = @import("sa_ws_client_test.zig").srvSendFrame;

pub const wsScriptedServer = @import("sa_ws_client_test.zig").wsScriptedServer;

pub const wsServerMain = @import("sa_ws_client_test.zig").wsServerMain;

pub const recvText = @import("sa_ws_client_test.zig").recvText;

/// Runs the client side of the scripted exchange; used by both the IPv4 and
/// the IPv6 loopback tests.
pub const runClientScript = @import("sa_ws_client_test.zig").runClientScript;




// ---- protocol-violation tests: raw TCP server speaking bad frames --------------

pub const ViolationServer = @import("sa_ws_client_test.zig").ViolationServer;

pub const expectViolation = @import("sa_ws_client_test.zig").expectViolation;


// ---- wss:// integration: python stdlib TLS server --------------------------------
// openssl generates a self-signed CN=localhost cert; the python server
// terminates TLS and speaks just enough WebSocket to echo one message.
// Iteration 1 is the unpinned (-100) probe, iteration 2 the pinned round-trip.

pub const wss_server_py = @import("sa_ws_client_test.zig").wss_server_py;
