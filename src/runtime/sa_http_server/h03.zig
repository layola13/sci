const std = @import("std");
const builtin = @import("builtin");
const sa_std_net = @import("sa_ws_stream");
const sio = @import("sio");
const ws_net = @import("sa_ws_stream");
const ConnState = @import("h01.zig").ConnState;
const Header = @import("h01.zig").Header;
const HttpServer = @import("h02.zig").HttpServer;
const NetworkStatus = @import("h01.zig").NetworkStatus;
const PollEvent = @import("h01.zig").PollEvent;
const ResponseHeaderBag = @import("h01.zig").ResponseHeaderBag;
const WebSocketOpcode = @import("h01.zig").WebSocketOpcode;
const max_v2_message_bytes = @import("h01.zig").max_v2_message_bytes;
const pollStream = @import("h01.zig").pollStream;
const setNonBlocking = @import("h01.zig").setNonBlocking;
const statusFromError = @import("h01.zig").statusFromError;
const stream_flush_threshold = @import("h01.zig").stream_flush_threshold;

pub const HttpRequest = struct {
    allocator: std.mem.Allocator,
    conn: *ConnState,
    server: *HttpServer,
    /// Negotiated at accept: HTTP/1.1 default (unless `Connection: close`),
    /// HTTP/1.0 only with `Connection: keep-alive`. Chunked request bodies
    /// force false (we don't consume them).
    keep_alive: bool,
    /// Set once a fully-framed response hit the wire (content-length body or
    /// terminated chunked stream). req_free recycles the connection only when
    /// this is true; otherwise the connection is closed.
    response_done: bool = false,
    method: []u8,
    target: []u8,
    headers: []Header,
    body: []u8,

    pub fn stream(self: *HttpRequest) std.Io.net.Stream {
        return self.conn.stream;
    }

    pub fn freeResources(self: *HttpRequest) void {
        for (self.headers) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.allocator.free(self.headers);
        self.allocator.free(self.method);
        self.allocator.free(self.target);
        if (self.body.len != 0) self.allocator.free(self.body);
    }

    /// Release parser state without closing the stream; ownership of the
    /// returned stream transfers to the caller (WebSocket upgrade).
    pub fn releaseStream(self: *HttpRequest) std.Io.net.Stream {
        const s = self.conn.stream;
        self.server.destroyConn(self.conn, false);
        return s;
    }

    pub fn deinit(self: *HttpRequest) void {
        self.server.destroyConn(self.conn, true);
        self.freeResources();
        self.allocator.destroy(self);
    }
};

pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    status: u16,
    headers: ResponseHeaderBag,
    sent: bool = false,

    pub fn init(request: *HttpRequest, status: u16) !*HttpResponse {
        const self = try request.allocator.create(HttpResponse);
        self.* = .{
            .allocator = request.allocator,
            .request = request,
            .status = status,
            .headers = ResponseHeaderBag.init(request.allocator, "text/plain"),
        };
        return self;
    }

    pub fn setContentType(self: *HttpResponse, content_type: []const u8) !void {
        if (self.sent) return error.ResponseAlreadySent;
        try self.headers.setContentType(content_type);
    }

    pub fn setHeader(self: *HttpResponse, name: []const u8, value: []const u8) !void {
        if (self.sent) return error.ResponseAlreadySent;
        try self.headers.add(name, value);
    }

    pub fn send(self: *HttpResponse, body: []const u8) !void {
        if (self.sent) return error.ResponseAlreadySent;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\n", .{ self.status, statusText(self.status), body.len });
        try self.headers.write(writer);
        // Framing is explicit (content-length), so the connection may be
        // reused when the client negotiated keep-alive.
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try writer.writeAll(body);
        try streamWriteAll(self.request.stream(), head.written());
        self.sent = true;
        self.request.response_done = true;
    }

    /// Header-only response (HEAD semantics): the caller declares
    /// the content-length the equivalent GET would have produced and
    /// no body bytes are written. `send` cannot express this: it
    /// always frames content-length from the body it is handed, and
    /// the header bag rejects a caller-set content-length. Framing
    /// stays explicit, so keep-alive reuse works exactly as send().
    pub fn sendHeadOnly(self: *HttpResponse, content_length: u64) !void {
        if (self.sent) return error.ResponseAlreadySent;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\n", .{ self.status, statusText(self.status), content_length });
        try self.headers.write(writer);
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try streamWriteAll(self.request.stream(), head.written());
        self.sent = true;
        self.request.response_done = true;
    }

    /// File-body response (static serving): the head is framed
    /// with content-length = count, then the file bytes move
    /// kernel-side via sendfile(2) -- no userspace copy, no
    /// whole-file buffer. Returns the number of file bytes
    /// actually sent: it equals count on success; a short count
    /// means the file ended early (it shrank after the caller
    /// measured it), which the caller must treat as a failed
    /// response, never as a completed one. response_done is set
    /// only when the full count is on the wire, so a short or
    /// failed send closes the connection instead of recycling a
    /// stream whose framing is broken. Linux only: other
    /// platforms return error.Unsupported BEFORE any byte is
    /// written, so the caller can still send an explicit error
    /// response. There is deliberately no buffered fallback here.
    pub fn sendFile(self: *HttpResponse, in_fd: std.posix.fd_t, offset: u64, count: u64) !u64 {
        if (self.sent) return error.ResponseAlreadySent;
        if (comptime builtin.cpu.arch.isWasm() or builtin.os.tag != .linux) return error.Unsupported;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\n", .{ self.status, statusText(self.status), count });
        try self.headers.write(writer);
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try streamWriteAll(self.request.stream(), head.written());
        self.sent = true;
        const out_fd = self.request.stream().socket.handle;
        var next_offset: u64 = offset;
        var sent_total: u64 = 0;
        while (sent_total < count) {
            const remaining = count - sent_total;
            const chunk: usize = @intCast(@min(remaining, @as(u64, 0x7ffff000)));
            var off: i64 = @intCast(next_offset);
            const rc = std.os.linux.sendfile(out_fd, in_fd, &off, chunk);
            const e = std.os.linux.errno(rc);
            if (e != .SUCCESS) {
                return switch (e) {
                    .AGAIN => error.WouldBlock,
                    .PIPE => error.BrokenPipe,
                    .INVAL, .BADF, .NOTSOCK => error.InvalidArgument,
                    else => error.SendFileFailed,
                };
            }
            if (rc == 0) break; // EOF: short send, reported via the return value.
            sent_total += rc;
            next_offset = @intCast(off);
        }
        if (sent_total == count) {
            self.request.response_done = true;
        }
        return sent_total;
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
        self.allocator.destroy(self);
    }
};

pub const HttpStreamResponse = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    status: u16,
    headers: ResponseHeaderBag,
    sent_head: bool = false,
    ended: bool = false,
    /// Explicit write buffer. writeChunk frames chunk bytes into it instead
    /// of hitting the socket directly. flush() — or the 8KB auto-flush, or
    /// endChunked() — pushes it to the socket. This is what makes flush() a
    /// real operation: without it, bytes may sit in this buffer.
    /// Semantics: writeChunk alone does NOT guarantee delivery; call flush()
    /// (or end the stream) to push.
    out_buffer: std.array_list.Managed(u8),

    pub fn init(request: *HttpRequest, status: u16) !*HttpStreamResponse {
        const self = try initDeferred(request, status);
        errdefer self.deinit();
        try self.sendHead(status);
        return self;
    }

    pub fn initDeferred(request: *HttpRequest, status: u16) !*HttpStreamResponse {
        const self = try request.allocator.create(HttpStreamResponse);
        errdefer request.allocator.destroy(self);
        self.* = .{
            .allocator = request.allocator,
            .request = request,
            .status = status,
            .headers = ResponseHeaderBag.init(request.allocator, "text/event-stream"),
            .sent_head = false,
            .ended = false,
            .out_buffer = std.array_list.Managed(u8).init(request.allocator),
        };
        return self;
    }

    pub fn setHeader(self: *HttpStreamResponse, name: []const u8, value: []const u8) !void {
        if (self.sent_head) return error.ResponseAlreadySent;
        try self.headers.add(name, value);
    }

    pub fn sendHead(self: *HttpStreamResponse, status: u16) !void {
        if (self.sent_head) return;
        var head: std.Io.Writer.Allocating = .init(self.allocator);
        defer head.deinit();
        const writer = &head.writer;
        try writer.print("HTTP/1.1 {d} {s}\r\n", .{ status, statusText(status) });
        try self.headers.write(writer);
        try writer.writeAll("transfer-encoding: chunked\r\n");
        // Chunked framing is self-delimiting, so the connection may be
        // reused once the terminal chunk is sent.
        if (self.request.keep_alive) {
            try writer.writeAll("connection: keep-alive\r\n\r\n");
        } else {
            try writer.writeAll("connection: close\r\n\r\n");
        }
        try streamWriteAll(self.request.stream(), head.written());
        self.sent_head = true;
    }

    pub fn writeChunk(self: *HttpStreamResponse, bytes: []const u8) !void {
        if (!self.sent_head) try self.sendHead(self.status);
        var size_buf: [32]u8 = undefined;
        const size = try std.fmt.bufPrint(&size_buf, "{x}\r\n", .{bytes.len});
        try self.out_buffer.appendSlice(size);
        try self.out_buffer.appendSlice(bytes);
        try self.out_buffer.appendSlice("\r\n");
        if (self.out_buffer.items.len >= stream_flush_threshold) try self.flush();
    }

    /// Push everything buffered (sending the head first if needed) to the
    /// socket. This is a real flush: after it returns, all previously
    /// written chunks have been handed to the OS.
    pub fn flush(self: *HttpStreamResponse) !void {
        if (!self.sent_head) try self.sendHead(self.status);
        if (self.out_buffer.items.len != 0) {
            try streamWriteAll(self.request.stream(), self.out_buffer.items);
            self.out_buffer.clearRetainingCapacity();
        }
    }

    pub fn endChunked(self: *HttpStreamResponse) !void {
        if (self.ended) return;
        if (!self.sent_head) try self.sendHead(self.status);
        try self.flush();
        try streamWriteAll(self.request.stream(), "0\r\n\r\n");
        self.ended = true;
        self.request.response_done = true;
    }

    pub fn deinit(self: *HttpStreamResponse) void {
        self.out_buffer.deinit();
        self.headers.deinit();
        self.allocator.destroy(self);
    }
};

pub const WebSocketHandle = struct {
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    last_message: ?[]u8 = null,
    incoming: std.array_list.Managed(u8),
    fragmented: std.array_list.Managed(u8),
    fragmented_opcode: ?u8 = null,
    pending_write: ?[]u8 = null,
    pending_offset: usize = 0,
    v2_mode: bool = false,
    close_sent: bool = false,
    close_received: bool = false,
    peer_closed: bool = false,

    pub fn initFromRequest(request: *HttpRequest) !*WebSocketHandle {
        const self = try request.allocator.create(WebSocketHandle);
        self.* = .{
            .allocator = request.allocator,
            // Takes over the TCP stream; the HTTP connection is consumed and
            // never recycled for keep-alive.
            .stream = request.releaseStream(),
            .incoming = std.array_list.Managed(u8).init(request.allocator),
            .fragmented = std.array_list.Managed(u8).init(request.allocator),
        };
        return self;
    }

    pub fn enableV2(self: *WebSocketHandle) !void {
        if (self.v2_mode) return;
        try setNonBlocking(self.stream);
        self.v2_mode = true;
    }

    pub fn deinit(self: *WebSocketHandle) void {
        if (self.last_message) |message| self.allocator.free(message);
        if (self.pending_write) |pending| self.allocator.free(pending);
        self.incoming.deinit();
        self.fragmented.deinit();
        self.stream.close(sio.io());
        self.allocator.destroy(self);
    }
};

pub fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => "OK",
    };
}

pub fn findHeader(request: *HttpRequest, name: []const u8) ?[]const u8 {
    for (request.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}

pub fn headerContainsToken(value: []const u8, token: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, value, " \t,");
    while (it.next()) |part| {
        if (std.ascii.eqlIgnoreCase(part, token)) return true;
    }
    return false;
}

pub fn streamWriteAll(stream: std.Io.net.Stream, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = std.c.write(stream.socket.handle, bytes.ptr + off, bytes.len - off);
        if (rc == 0) return error.BrokenPipe;
        if (rc < 0) {
            const e = std.c.errno(rc);
            if (e == .AGAIN) return error.WouldBlock;
            return error.ConnectionResetByPeer;
        }
        off += @intCast(rc);
    }
}

pub fn streamWriteSome(stream: std.Io.net.Stream, bytes: []const u8) !usize {
    const rc = std.c.write(stream.socket.handle, bytes.ptr, bytes.len);
    if (rc == 0) return error.BrokenPipe;
    if (rc < 0) {
        const e = std.c.errno(rc);
        if (e == .AGAIN) return error.WouldBlock;
        return error.ConnectionResetByPeer;
    }
    return @intCast(rc);
}

pub fn streamReadSome(stream: std.Io.net.Stream, buf: []u8) !usize {
    const rc = std.c.read(stream.socket.handle, buf.ptr, buf.len);
    if (rc == 0) return 0;
    if (rc < 0) {
        const e = std.c.errno(rc);
        if (e == .AGAIN) return error.WouldBlock;
        return error.ConnectionResetByPeer;
    }
    return @intCast(rc);
}

pub fn writeExact(stream: std.Io.net.Stream, bytes: []const u8) bool {
    streamWriteAll(stream, bytes) catch return false;
    return true;
}

pub fn writeFrame(stream: std.Io.net.Stream, opcode: u8, payload: []const u8) bool {
    const frame_cap = std.math.add(usize, payload.len, 14) catch return false;
    const frame = std.heap.c_allocator.alloc(u8, frame_cap) catch return false;
    defer std.heap.c_allocator.free(frame);
    const frame_len = sa_std_net.buildWebSocketFrame(frame, opcode, payload, null) catch return false;
    return writeExact(stream, frame[0..frame_len]);
}

pub fn readFrame(handle: *WebSocketHandle, max_len: u64, out_opcode: ?*u8, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const opcode_slot = out_opcode orelse return 2;
    const ptr_slot = out_ptr orelse return 2;
    const len_slot = out_len orelse return 2;

    while (true) {
        const frame = sa_std_net.readWebSocketFrameAlloc(handle.allocator, handle.stream, max_len, true) catch return 2;
        const opcode = frame.opcode;
        const payload = frame.payload;
        if (payload.len > 0) {
            if (handle.last_message) |message| handle.allocator.free(message);
            handle.last_message = null;
        }

        switch (opcode) {
            @intFromEnum(WebSocketOpcode.ping) => {
                if (!writeFrame(handle.stream, @intFromEnum(WebSocketOpcode.pong), payload)) {
                    if (payload.len > 0) handle.allocator.free(payload);
                    return 2;
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
                    if (handle.last_message) |message| handle.allocator.free(message);
                    handle.last_message = null;
                    ptr_slot.* = null;
                    len_slot.* = 0;
                } else {
                    if (handle.last_message) |message| handle.allocator.free(message);
                    handle.last_message = payload;
                    ptr_slot.* = payload.ptr;
                    len_slot.* = payload.len;
                }
                return 0;
            },
            else => {
                if (payload.len > 0) handle.allocator.free(payload);
                return 2;
            },
        }
    }
}

pub const ParsedV2Frame = struct {
    fin: bool,
    opcode: u8,
    payload: []u8,
};

pub fn decodeV2Frame(handle: *WebSocketHandle, max_len: usize) !?ParsedV2Frame {
    const bytes = handle.incoming.items;
    if (bytes.len < 2) return null;
    if ((bytes[0] & 0x70) != 0) return error.InvalidWebSocketFrame;

    const fin = bytes[0] & 0x80 != 0;
    const opcode = bytes[0] & 0x0f;
    const masked = bytes[1] & 0x80 != 0;
    if (!masked) return error.InvalidWebSocketFrame;

    var payload_len: u64 = bytes[1] & 0x7f;
    var offset: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return null;
        payload_len = std.mem.readInt(u16, bytes[2..4], .big);
        if (payload_len < 126) return error.InvalidWebSocketFrame;
        offset = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return null;
        payload_len = std.mem.readInt(u64, bytes[2..10], .big);
        if (payload_len < 65536 or payload_len & (@as(u64, 1) << 63) != 0) return error.InvalidWebSocketFrame;
        offset = 10;
    }
    if (payload_len > max_len or payload_len > max_v2_message_bytes) return error.StreamTooLong;
    if (opcode >= 8 and (!fin or payload_len > 125)) return error.InvalidWebSocketFrame;
    if (opcode != 0 and opcode != 1 and opcode != 2 and opcode != 8 and opcode != 9 and opcode != 10) return error.InvalidWebSocketFrame;

    const payload_len_usize: usize = @intCast(payload_len);
    const frame_len = std.math.add(usize, offset + 4, payload_len_usize) catch return error.StreamTooLong;
    if (bytes.len < frame_len) return null;
    const mask = bytes[offset..][0..4].*;
    offset += 4;

    var payload: []u8 = &.{};
    if (payload_len_usize != 0) {
        payload = try handle.allocator.alloc(u8, payload_len_usize);
        @memcpy(payload, bytes[offset .. offset + payload_len_usize]);
        for (payload, 0..) |*byte, idx| byte.* ^= mask[idx & 3];
    }

    const remaining = bytes.len - frame_len;
    std.mem.copyForwards(u8, handle.incoming.items[0..remaining], handle.incoming.items[frame_len..]);
    handle.incoming.items.len = remaining;
    return .{ .fin = fin, .opcode = opcode, .payload = payload };
}

pub fn replaceLastMessage(handle: *WebSocketHandle, payload: []u8, out_ptr: *?[*]const u8, out_len: *u64) void {
    if (handle.last_message) |message| handle.allocator.free(message);
    if (payload.len == 0) {
        handle.last_message = null;
        out_ptr.* = null;
        out_len.* = 0;
    } else {
        handle.last_message = payload;
        out_ptr.* = payload.ptr;
        out_len.* = payload.len;
    }
}

pub fn flushPendingWrite(handle: *WebSocketHandle) NetworkStatus {
    const pending = handle.pending_write orelse return .ok;
    while (handle.pending_offset < pending.len) {
        const written = streamWriteSome(handle.stream, pending[handle.pending_offset..]) catch |err| return statusFromError(err);
        if (written == 0) {
            handle.peer_closed = true;
            return .closed;
        }
        handle.pending_offset += written;
    }
    handle.allocator.free(pending);
    handle.pending_write = null;
    handle.pending_offset = 0;
    return .ok;
}

pub fn websocketFrameSize(payload_len: usize) !usize {
    const header_len: usize = if (payload_len < 126) 2 else if (payload_len <= std.math.maxInt(u16)) 4 else 10;
    return std.math.add(usize, payload_len, header_len) catch error.StreamTooLong;
}

pub fn writeFrameV2(handle: *WebSocketHandle, opcode: u8, payload: []const u8) NetworkStatus {
    if (handle.peer_closed or handle.close_sent or handle.close_received) return .closed;
    if (payload.len > max_v2_message_bytes) return .too_large;
    if (opcode != 1 and opcode != 2 and opcode != 9 and opcode != 10) return .invalid;
    if ((opcode == @intFromEnum(WebSocketOpcode.ping) or opcode == @intFromEnum(WebSocketOpcode.pong)) and payload.len > 125) return .too_large;
    if (opcode == @intFromEnum(WebSocketOpcode.text) and !std.unicode.utf8ValidateSlice(payload)) return .invalid;
    handle.enableV2() catch return .io_error;

    const pending_status = flushPendingWrite(handle);
    if (pending_status != .ok) return pending_status;

    const frame_cap = websocketFrameSize(payload.len) catch return .too_large;
    const frame = handle.allocator.alloc(u8, frame_cap) catch return .io_error;
    const frame_len = sa_std_net.buildWebSocketFrame(frame, opcode, payload, null) catch {
        handle.allocator.free(frame);
        return .invalid;
    };
    handle.pending_write = frame[0..frame_len];
    handle.pending_offset = 0;
    const status = flushPendingWrite(handle);
    return switch (status) {
        .would_block => .ok,
        else => status,
    };
}

pub fn pollWebSocketV2(handle: *WebSocketHandle, interests: u32, timeout_ms: u32, out_events: *u32) NetworkStatus {
    out_events.* = 0;
    if (handle.peer_closed or handle.close_received) {
        out_events.* = PollEvent.closed;
        return .closed;
    }
    if (interests == 0 or interests & ~(PollEvent.readable | PollEvent.writable) != 0) return .invalid;
    handle.enableV2() catch return .io_error;

    if (interests & PollEvent.writable != 0 and handle.pending_write != null) {
        const flush_status = flushPendingWrite(handle);
        if (flush_status == .closed or flush_status == .io_error) return flush_status;
    }

    var posix_events: i16 = 0;
    if (interests & PollEvent.readable != 0) posix_events |= std.posix.POLL.IN;
    if (interests & PollEvent.writable != 0) posix_events |= std.posix.POLL.OUT;
    const poll_status = pollStream(handle.stream.socket.handle, posix_events, timeout_ms, out_events);
    if (poll_status != .ok) return poll_status;
    if (out_events.* & PollEvent.writable != 0 and handle.pending_write != null) {
        const flush_status = flushPendingWrite(handle);
        if (flush_status != .ok) {
            out_events.* &= ~PollEvent.writable;
            if (out_events.* & PollEvent.readable != 0) return .ok;
            return flush_status;
        }
    }
    return .ok;
}
