const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const AbiStatus = @import("core.zig").AbiStatus;
const HttpClient = @import("core.zig").HttpClient;
const buildWebSocketFrame = @import("core.zig").buildWebSocketFrame;
const dialHost = @import("core.zig").dialHost;
const readExact = @import("core.zig").readExact;
const readWebSocketFrameAlloc = @import("core.zig").readWebSocketFrameAlloc;
const websocketAccept = @import("core.zig").websocketAccept;

const WebSocketOpcode = enum(u8) {
    continuation = 0,
    text = 1,
    binary = 2,
    connection_close = 8,
    ping = 9,
    pong = 10,
};
// Single-short-read helper shared by the v1 and v2 websocket
// rawRead paths (see the NOTE at each call site).
pub fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
    if (comptime builtin.cpu.arch.isWasm()) {
        var iov = [_]std.os.wasi.iovec_t{.{ .base = buf.ptr, .len = buf.len }};
        var n: usize = 0;
        const err = std.os.wasi.fd_read(fd, &iov, iov.len, &n);
        if (err != .SUCCESS) return error.Io;
        return n;
    } else {
        return std.posix.read(fd, buf);
    }
}
const WebSocketHandle = struct {
    allocator: std.mem.Allocator,
    stream: ?std.Io.net.Stream = null,
    // TLS state for wss://. The net reader/writer (and their buffers) must
    // outlive tls_client, which borrows them; all live in the handle.
    tls_client: ?*std.crypto.tls.Client = null,
    net_reader: std.Io.net.Stream.Reader = undefined,
    net_writer: std.Io.net.Stream.Writer = undefined,
    net_read_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    net_write_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    // Persistent buffered reader for plain (non-TLS) frame reads. A fresh
    // reader per read would over-read past frame boundaries and lose bytes.
    frame_reader: std.Io.net.Stream.Reader = undefined,
    frame_read_buf: [8192]u8 = undefined,
    tls_read_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    tls_write_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    ca_lock: std.Io.RwLock = .init,

    pub fn isClient(self: *WebSocketHandle) bool {
        _ = self;
        return true;
    }

    pub fn rawRead(self: *WebSocketHandle, buffer: []u8) !usize {
        if (self.tls_client) |t| {
            return try t.reader.readSliceShort(buffer);
        }
        // NOTE(Zig 0.17): Stream.Reader is unusable with the Threaded
        // backend (same reason as WebSocketV2.rawRead and sci sa_ws_client
        // tcpRead); read the blocking socket fd directly with a single
        // short-read shape. A Reader.readSliceShort loops until the buffer
        // is full or EOF, so the 101 head-read loop blocked until the peer
        // timed out (D5); a single posix read returns the bytes on hand.
        const stream = self.stream orelse return error.EndOfStream;
        return posixRead(stream.socket.handle, buffer);
    }

    pub fn rawWrite(self: *WebSocketHandle, bytes: []const u8) !void {
        if (self.tls_client) |t| {
            try t.writer.writeAll(bytes);
            try t.writer.flush();
            try self.net_writer.interface.flush();
            return;
        }
        const stream = self.stream orelse return error.EndOfStream;
        var wbuf: [8192]u8 = undefined;
        var w = stream.writer(sio.io(), &wbuf);
        try w.interface.writeAll(bytes);
        try w.interface.flush();
    }

    fn readExact(self: *WebSocketHandle, buffer: []u8) bool {
        var offset: usize = 0;
        while (offset < buffer.len) {
            const n = self.rawRead(buffer[offset..]) catch return false;
            if (n == 0) return false;
            offset += n;
        }
        return true;
    }

    pub fn writeExact(self: *WebSocketHandle, bytes: []const u8) bool {
        self.rawWrite(bytes) catch return false;
        return true;
    }

    pub fn deinit(self: *WebSocketHandle) void {
        if (self.tls_client) |t| {
            self.allocator.destroy(t);
            self.tls_client = null;
        }
        if (self.stream) |stream| {
            stream.close(sio.io());
            self.stream = null;
        }
        self.allocator.destroy(self);
    }
};
pub fn findRawHeader(head: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    _ = lines.next(); // status line
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " "), key)) {
            return std.mem.trim(u8, line[colon + 1 ..], " ");
        }
    }
    return null;
}
fn websocketHeaderContainsToken(value: []const u8, token: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, value, " \t,");
    while (it.next()) |part| {
        if (std.ascii.eqlIgnoreCase(part, token)) return true;
    }
    return false;
}
fn websocketWriteFrame(handle: *WebSocketHandle, opcode: u8, payload: []const u8) bool {
    const masked = handle.isClient();
    var mask_key: [4]u8 = undefined;
    const mask = if (masked) blk: {
        sio.io().random(&mask_key);
        break :blk &mask_key;
    } else null;
    const frame_cap = std.math.add(usize, payload.len, 14) catch return false;
    const frame = handle.allocator.alloc(u8, frame_cap) catch return false;
    defer handle.allocator.free(frame);
    const frame_len = buildWebSocketFrame(frame, opcode, payload, mask) catch return false;
    return handle.writeExact(frame[0..frame_len]);
}
fn websocketSendPingPong(handle: *WebSocketHandle, opcode: u8, payload: []const u8) bool {
    return websocketWriteFrame(handle, opcode, payload);
}
fn fail() u32 {
    return @intFromEnum(AbiStatus.failed);
}
fn websocketReadFrame(handle: *WebSocketHandle, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const opcode_slot = out_opcode orelse return fail();
    const ptr_slot = out_ptr orelse return fail();
    const len_slot = out_len orelse return fail();

    while (true) {
        if (handle.stream == null and handle.tls_client == null) return fail();
        const reader: *std.Io.Reader = if (handle.tls_client) |t|
            &t.reader
        else
            &handle.frame_reader.interface;
        const frame = readWebSocketFrameAlloc(handle.allocator, reader, max_len, !handle.isClient()) catch return fail();
        const opcode = frame.opcode;
        const payload = frame.payload;

        switch (opcode) {
            @intFromEnum(WebSocketOpcode.ping) => {
                if (!websocketSendPingPong(handle, @intFromEnum(WebSocketOpcode.pong), payload)) {
                    if (payload.len > 0) handle.allocator.free(payload);
                    return fail();
                }
                if (payload.len > 0) handle.allocator.free(payload);
                continue;
            },
            @intFromEnum(WebSocketOpcode.pong) => {
                if (payload.len > 0) handle.allocator.free(payload);
                continue;
            },
            @intFromEnum(WebSocketOpcode.connection_close), @intFromEnum(WebSocketOpcode.text), @intFromEnum(WebSocketOpcode.binary) => {
                opcode_slot.* = opcode;
                if (payload.len == 0) {
                    ptr_slot.* = null;
                    len_slot.* = 0;
                } else {
                    ptr_slot.* = payload.ptr;
                    len_slot.* = payload.len;
                }
                return 0;
            },
            else => {
                if (payload.len > 0) handle.allocator.free(payload);
                return fail();
            },
        }
    }
}
pub export fn sa_http_websocket_read(ws: ?*anyopaque, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const value = ws orelse return fail();
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(value)));
    return websocketReadFrame(handle, max_len, out_opcode, out_ptr, out_len);
}
pub export fn sa_http_websocket_write(ws: ?*anyopaque, opcode: u8, data_ptr: ?[*]const u8, data_len: u64) u32 {
    const value = ws orelse return fail();
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(value)));
    const payload = if (data_ptr) |ptr| ptr[0..@intCast(data_len)] else &[_]u8{};
    if (!websocketWriteFrame(handle, opcode, payload)) return fail();
    return 0;
}
pub export fn sa_http_websocket_free(ws: ?*anyopaque) u32 {
    const value = ws orelse return fail();
    const handle = @as(*WebSocketHandle, @ptrCast(@alignCast(value)));
    handle.deinit();
    return 0;
}
pub export fn sa_http_client_websocket_connect(client: ?*anyopaque, url_ptr: ?[*]const u8, url_len: u64, out_ws: ?*?*anyopaque) u32 {
    const client_ptr = client orelse return fail();
    const url = url_ptr orelse return fail();
    const slot = out_ws orelse return fail();
    const cli = @as(*HttpClient, @ptrCast(@alignCast(client_ptr)));
    const url_slice = url[0..@intCast(url_len)];
    const uri = std.Uri.parse(url_slice) catch return fail();

    const host_slice = switch (uri.host orelse return fail()) {
        .raw => |s| s,
        .percent_encoded => |s| s,
    };
    const use_tls = std.mem.eql(u8, uri.scheme, "wss") or std.mem.eql(u8, uri.scheme, "https");
    if (!use_tls and !std.mem.eql(u8, uri.scheme, "ws") and !std.mem.eql(u8, uri.scheme, "http")) return fail();
    // GAP-17: no shaped-TLS WebSocket variant; fail loudly.
    if (use_tls and cli.tls_profile != null) return fail();
    const port: u16 = uri.port orelse if (use_tls) 443 else 80;

    // Request target: path + optional query.
    var target_buf: [8192]u8 = undefined;
    var target_stream = std.Io.Writer.fixed(&target_buf);
    const raw_path: []const u8 = switch (uri.path) {
        .raw => |s| if (s.len != 0) s else "/",
        .percent_encoded => |s| if (s.len != 0) s else "/",
    };
    target_stream.print("{s}", .{raw_path}) catch return fail();
    if (uri.query) |q| {
        const qs = switch (q) {
            .raw => |s| s,
            .percent_encoded => |s| s,
        };
        target_stream.print("?{s}", .{qs}) catch return fail();
    }
    const target = target_stream.buffer[0..target_stream.end];

    var key_bytes: [16]u8 = undefined;
    sio.io().random(&key_bytes);
    var key_b64: [24]u8 = undefined;
    const key = std.base64.standard.Encoder.encode(&key_b64, &key_bytes);

    var stream = dialHost(host_slice, port) catch return fail();
    errdefer stream.close(sio.io());

    const handle = cli.allocator.create(WebSocketHandle) catch {
        stream.close(sio.io());
        return fail();
    };
    errdefer handle.deinit();
    handle.* = .{ .allocator = cli.allocator, .stream = stream };
    handle.frame_reader = stream.reader(sio.io(), &handle.frame_read_buf);

    if (use_tls) {
        // TLS handshake over the raw stream (wss://).
        handle.net_reader = stream.reader(sio.io(), &handle.net_read_buf);
        handle.net_writer = stream.writer(sio.io(), &handle.net_write_buf);
        var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
        sio.io().random(&entropy);
        const tls_client = cli.allocator.create(std.crypto.tls.Client) catch return fail();
        errdefer cli.allocator.destroy(tls_client);
        tls_client.* = std.crypto.tls.Client.init(
            &handle.net_reader.interface,
            &handle.net_writer.interface,
            .{
                .host = .{ .explicit = host_slice },
                .ca = .{ .bundle = .{
                    .gpa = cli.allocator,
                    .io = sio.io(),
                    .lock = &handle.ca_lock,
                    .bundle = &cli.client.ca_bundle,
                } },
                .write_buffer = &handle.tls_write_buf,
                .read_buffer = &handle.tls_read_buf,
                .entropy = &entropy,
                .realtime_now = std.Io.Clock.real.now(sio.io()),
            },
        ) catch return fail();
        handle.tls_client = tls_client;
    }

    // Send upgrade request.
    var req_buf = std.array_list.Managed(u8).init(cli.allocator);
    defer req_buf.deinit();
    req_buf.print("GET {s} HTTP/1.1\r\n", .{target}) catch return fail();
    if (port == 80 or port == 443) {
        req_buf.print("Host: {s}\r\n", .{host_slice}) catch return fail();
    } else {
        req_buf.print("Host: {s}:{d}\r\n", .{ host_slice, port }) catch return fail();
    }
    req_buf.appendSlice("Connection: Upgrade\r\nUpgrade: websocket\r\nsec-websocket-version: 13\r\n") catch return fail();
    req_buf.print("sec-websocket-key: {s}\r\n\r\n", .{key}) catch return fail();
    if (!handle.writeExact(req_buf.items)) return fail();

    // Read response head.
    var head_buf = std.array_list.Managed(u8).init(cli.allocator);
    defer head_buf.deinit();
    var tmp: [4096]u8 = undefined;
    var head_end: ?usize = null;
    while (head_end == null) {
        const n = handle.rawRead(&tmp) catch return fail();
        if (n == 0) return fail();
        head_buf.appendSlice(tmp[0..n]) catch return fail();
        if (head_buf.items.len > 64 * 1024) return fail();
        if (std.mem.indexOf(u8, head_buf.items, "\r\n\r\n")) |idx| head_end = idx;
    }
    const head = head_buf.items[0..head_end.?];
    {
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        const status_line = lines.next() orelse return fail();
        var parts = std.mem.splitScalar(u8, status_line, ' ');
        _ = parts.next();
        const code_str = parts.next() orelse return fail();
        const code = std.fmt.parseInt(u16, code_str, 10) catch return fail();
        if (code != 101) return fail();
    }
    const upgrade = findRawHeader(head, "upgrade") orelse return fail();
    if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) return fail();
    const connection_value = findRawHeader(head, "connection") orelse return fail();
    if (!websocketHeaderContainsToken(connection_value, "upgrade")) return fail();
    const accept_value = findRawHeader(head, "sec-websocket-accept") orelse return fail();
    var expected_accept_buf: [28]u8 = undefined;
    const expected_accept = websocketAccept(key, &expected_accept_buf) catch return fail();
    if (!std.mem.eql(u8, accept_value, expected_accept)) return fail();

    slot.* = @ptrCast(handle);
    return 0;
}
