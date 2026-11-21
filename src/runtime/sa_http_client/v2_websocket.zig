const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const HttpClient = @import("core.zig").HttpClient;
const HttpRequest = @import("core.zig").HttpRequest;
const HttpResponse = @import("response.zig").HttpResponse;
const NetworkStatus = @import("v2_core.zig").NetworkStatus;
const PollEvent = @import("v2_core.zig").PollEvent;
const V2Error = @import("v2_core.zig").V2Error;
const dialHost = @import("core.zig").dialHost;
const executeRequestV2 = @import("v2_core.zig").executeRequestV2;
const posixRead = @import("websocket.zig").posixRead;
const requiredSlice = @import("v2_core.zig").requiredSlice;
const statusCode = @import("v2_core.zig").statusCode;
const statusFromV2Error = @import("v2_core.zig").statusFromV2Error;
const validHeaderName = @import("v2_core.zig").validHeaderName;
const validHeaderValue = @import("v2_core.zig").validHeaderValue;
const websocketAccept = @import("core.zig").websocketAccept;

fn cloneRequestV2(source: *HttpRequest) !*HttpRequest {
    const allocator = source.allocator;
    const request = try allocator.create(HttpRequest);
    errdefer allocator.destroy(request);
    source.client.retain();
    errdefer source.client.release();
    request.* = .{
        .allocator = allocator,
        .client = source.client,
        .method = source.method,
        .url = try allocator.dupe(u8, source.url),
        .headers = std.array_list.Managed(std.http.Header).init(allocator),
        .timeout_ms = source.timeout_ms,
        .max_response_bytes = source.max_response_bytes,
        .retains_client = true,
    };
    errdefer allocator.free(request.url);
    errdefer request.headers.deinit();
    for (source.headers.items) |header| {
        const name = try allocator.dupe(u8, header.name);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, header.value);
        errdefer allocator.free(value);
        try request.headers.append(.{ .name = name, .value = value });
    }
    request.body = if (source.body) |body| try allocator.dupe(u8, body) else null;
    return request;
}
pub const V2AsyncOp = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    thread: ?std.Thread = null,
    // NOTE(Zig 0.17): Thread.Mutex/Condition removed; spin + sleep-poll.
    mutex: std.atomic.Mutex = .unlocked,
    done: bool = false,
    cancel_requested: bool = false,
    result_status: NetworkStatus = .would_block,
    response: ?*HttpResponse = null,

    pub fn init(source: *HttpRequest) !*V2AsyncOp {
        const request = try cloneRequestV2(source);
        errdefer request.deinit();
        const self = try request.allocator.create(V2AsyncOp);
        errdefer request.allocator.destroy(self);
        self.* = .{ .allocator = request.allocator, .request = request };
        if (comptime builtin.cpu.arch.isWasm()) {
            run(self);
        } else {
            self.thread = try std.Thread.spawn(.{}, run, .{self});
        }
        return self;
    }

    pub fn run(self: *V2AsyncOp) void {
        const response = executeRequestV2(self.request, self) catch |err| {
            self.complete(statusFromV2Error(err), null);
            return;
        };
        self.complete(.ok, response);
    }

    fn complete(self: *V2AsyncOp, result_status: NetworkStatus, response: ?*HttpResponse) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (self.cancel_requested) {
            if (response) |value| value.deinit();
            self.response = null;
            self.result_status = .closed;
        } else {
            self.response = response;
            self.result_status = result_status;
        }
        self.done = true;
    }

    pub fn cancelled(self: *V2AsyncOp) bool {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        return self.cancel_requested;
    }

    pub fn cancel(self: *V2AsyncOp) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (self.done or self.cancel_requested) return;
        self.cancel_requested = true;
    }

    pub fn poll(self: *V2AsyncOp, timeout_ms: u32, out_ready: *u8) NetworkStatus {
        out_ready.* = 0;
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        if (self.done) {
            const st = self.result_status;
            self.mutex.unlock();
            out_ready.* = 1;
            return st;
        }
        self.mutex.unlock();
        if (timeout_ms == 0) return .would_block;

        const deadline_ns: i128 = sio.nanoTimestamp() + @as(i128, timeout_ms) * std.time.ns_per_ms;
        while (true) {
            sio.io().sleep(.fromMilliseconds(5), .awake) catch {};
            while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
            if (self.done) {
                const st = self.result_status;
                self.mutex.unlock();
                out_ready.* = 1;
                return st;
            }
            self.mutex.unlock();
            if (sio.nanoTimestamp() >= deadline_ns) return .timeout;
        }
    }

    pub fn takeResponse(self: *V2AsyncOp, out_resp: *?*anyopaque) NetworkStatus {
        out_resp.* = null;
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (!self.done) return .would_block;
        if (self.result_status != .ok) return self.result_status;
        const response = self.response orelse return .closed;
        self.response = null;
        out_resp.* = @ptrCast(response);
        return .ok;
    }

    pub fn deinit(self: *V2AsyncOp) void {
        self.cancel();
        if (self.thread) |thread| thread.join();
        if (self.response) |response| response.deinit();
        self.request.deinit();
        self.allocator.destroy(self);
    }
};
pub export fn sa_http_client_req_send_async_v2(req: ?*anyopaque, out_op: ?*?*anyopaque) u32 {
    const slot = out_op orelse return statusCode(.invalid);
    slot.* = null;
    const req_ptr = req orelse return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    const operation = V2AsyncOp.init(request) catch return statusCode(.io_error);
    slot.* = @ptrCast(operation);
    return statusCode(.ok);
}
pub export fn sa_http_client_async_poll_v2(op: ?*anyopaque, timeout_ms: u32, out_ready: ?*u8) u32 {
    const ready = out_ready orelse return statusCode(.invalid);
    ready.* = 0;
    const op_ptr = op orelse return statusCode(.invalid);
    const operation: *V2AsyncOp = @ptrCast(@alignCast(op_ptr));
    return statusCode(operation.poll(timeout_ms, ready));
}
pub export fn sa_http_client_async_take_response_v2(op: ?*anyopaque, out_resp: ?*?*anyopaque) u32 {
    const slot = out_resp orelse return statusCode(.invalid);
    slot.* = null;
    const op_ptr = op orelse return statusCode(.invalid);
    const operation: *V2AsyncOp = @ptrCast(@alignCast(op_ptr));
    return statusCode(operation.takeResponse(slot));
}
pub export fn sa_http_client_async_cancel_v2(op: ?*anyopaque) u32 {
    const op_ptr = op orelse return statusCode(.invalid);
    const operation: *V2AsyncOp = @ptrCast(@alignCast(op_ptr));
    operation.cancel();
    return statusCode(.ok);
}
pub export fn sa_http_client_async_free_v2(op: ?*anyopaque) u32 {
    const op_ptr = op orelse return statusCode(.invalid);
    const operation: *V2AsyncOp = @ptrCast(@alignCast(op_ptr));
    operation.deinit();
    return statusCode(.ok);
}
pub const WebSocketOpcodeV2 = enum(u8) {
    continuation = 0,
    text = 1,
    binary = 2,
    close = 8,
    ping = 9,
    pong = 10,
};
pub const WebSocketV2 = struct {
    allocator: std.mem.Allocator,
    client: *HttpClient,
    stream: std.Io.net.Stream,
    // TLS state for wss:// (mirrors the v1 handle layout).
    tls_client: ?*std.crypto.tls.Client = null,
    net_reader: std.Io.net.Stream.Reader = undefined,
    net_writer: std.Io.net.Stream.Writer = undefined,
    net_read_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    net_write_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    tls_read_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    tls_write_buf: [std.crypto.tls.Client.min_buffer_len]u8 = undefined,
    // Persistent buffered reader for plain frame input (a fresh reader per
    // read would over-read past frame boundaries and lose bytes).
    frame_reader: std.Io.net.Stream.Reader = undefined,
    frame_read_buf: [8192]u8 = undefined,
    ca_lock: std.Io.RwLock = .init,
    receive_buffer: std.array_list.Managed(u8),
    receive_start: usize = 0,
    fragment_buffer: std.array_list.Managed(u8),
    fragment_opcode: ?u8 = null,
    last_message: ?[]u8 = null,
    pending_pong: ?[]u8 = null,
    close_sent: bool = false,
    closed: bool = false,
    io_mutex: std.atomic.Mutex = .unlocked,

    pub fn rawRead(self: *WebSocketV2, buffer: []u8) V2Error!usize {
        if (self.tls_client) |t| {
            return t.reader.readSliceShort(buffer) catch return error.Io;
        }
        // NOTE(Zig 0.17): Stream.Reader is unusable with the Threaded
        // backend (same reason as sci sa_ws_client tcpRead); read the
        // blocking socket fd directly with single-short-read shape.
        // Callers loop on need_more; handshake preserves over-read bytes
        // into receive_buffer explicitly.
        return posixRead(self.stream.socket.handle, buffer) catch return error.Io;
    }

    pub fn rawWrite(self: *WebSocketV2, bytes: []const u8) V2Error!void {
        if (self.tls_client) |t| {
            t.writer.writeAll(bytes) catch return error.Io;
            t.writer.flush() catch return error.Io;
            self.net_writer.interface.flush() catch return error.Io;
            return;
        }
        var wbuf: [8192]u8 = undefined;
        var w = self.stream.writer(sio.io(), &wbuf);
        w.interface.writeAll(bytes) catch return error.Io;
        w.interface.flush() catch return error.Io;
    }

    pub fn markClosed(self: *WebSocketV2) void {
        if (self.closed) return;
        self.closed = true;
        self.stream.shutdown(sio.io(), .both) catch {};
    }

    pub fn clearLastMessage(self: *WebSocketV2) void {
        if (self.last_message) |message| self.allocator.free(message);
        self.last_message = null;
    }

    pub fn deinit(self: *WebSocketV2) void {
        while (!self.io_mutex.tryLock()) std.atomic.spinLoopHint();
        self.markClosed();
        self.clearLastMessage();
        if (self.pending_pong) |payload| self.allocator.free(payload);
        self.pending_pong = null;
        self.receive_buffer.deinit();
        self.fragment_buffer.deinit();
        if (self.tls_client) |t| self.allocator.destroy(t);
        self.stream.close(sio.io());
        self.io_mutex.unlock();
        const client = self.client;
        self.allocator.destroy(self);
        client.release();
    }
};
fn timeoutMillis(timeout_ms: u32) i32 {
    return @intCast(@min(timeout_ms, @as(u32, @intCast(std.math.maxInt(i32)))));
}
pub fn websocketPoll(handle: *WebSocketV2, interests: u32, timeout_ms: u32, out_events: *u32) NetworkStatus {
    out_events.* = 0;
    if (interests == 0 or interests & ~(PollEvent.readable | PollEvent.writable) != 0) return .invalid;
    if (handle.closed) {
        out_events.* = PollEvent.closed;
        return .closed;
    }

    if (interests & PollEvent.readable != 0 and
        handle.receive_start < handle.receive_buffer.items.len)
    {
        out_events.* |= PollEvent.readable;
    }
    if (out_events.* != 0 and interests & PollEvent.writable == 0) return .ok;

    var native_events: i16 = 0;
    if (interests & PollEvent.readable != 0 and out_events.* & PollEvent.readable == 0) native_events |= std.posix.POLL.IN;
    if (interests & PollEvent.writable != 0) native_events |= std.posix.POLL.OUT;
    if (native_events == 0) return .ok;

    var poll_fds = [1]std.posix.pollfd{.{
        .fd = handle.stream.socket.handle,
        .events = native_events,
        .revents = 0,
    }};
    const ready = std.posix.poll(&poll_fds, timeoutMillis(timeout_ms)) catch return .io_error;
    if (ready == 0) return if (timeout_ms == 0) .would_block else .timeout;
    const returned = poll_fds[0].revents;
    if (returned & (std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0) return .io_error;
    if (returned & std.posix.POLL.IN != 0) out_events.* |= PollEvent.readable;
    if (returned & std.posix.POLL.OUT != 0) out_events.* |= PollEvent.writable;
    if (returned & std.posix.POLL.HUP != 0) out_events.* |= PollEvent.closed;
    if (out_events.* & (PollEvent.readable | PollEvent.writable) != 0) return .ok;
    if (out_events.* & PollEvent.closed != 0) return .closed;
    return .would_block;
}
fn normalizedWebSocketUrl(allocator: std.mem.Allocator, url: []const u8) V2Error![]u8 {
    if (std.mem.startsWith(u8, url, "ws://")) {
        return std.fmt.allocPrint(allocator, "http{s}", .{url[2..]}) catch return error.Io;
    }
    if (std.mem.startsWith(u8, url, "wss://")) {
        return std.fmt.allocPrint(allocator, "https{s}", .{url[3..]}) catch return error.Io;
    }
    return error.Invalid;
}
fn findRawHeaderV2(head: []const u8, key: []const u8) ?[]const u8 {
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
fn websocketHeaderContainsTokenV2(value: []const u8, token: []const u8) bool {
    var iterator = std.mem.tokenizeAny(u8, value, " \t,");
    while (iterator.next()) |part| {
        if (std.ascii.eqlIgnoreCase(part, token)) return true;
    }
    return false;
}
fn reservedWebSocketHeader(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "connection") or
        std.ascii.eqlIgnoreCase(name, "host") or
        std.ascii.eqlIgnoreCase(name, "upgrade") or
        std.ascii.eqlIgnoreCase(name, "sec-websocket-key") or
        std.ascii.eqlIgnoreCase(name, "sec-websocket-version");
}
fn websocketConnect(
    client: *HttpClient,
    logical_url: []const u8,
    headers: []const std.http.Header,
    unix_socket_path: ?[]const u8,
    timeout_ms: u32,
) V2Error!*WebSocketV2 {
    if (logical_url.len == 0) return error.Invalid;
    if (unix_socket_path != null and !std.mem.startsWith(u8, logical_url, "ws://")) return error.Invalid;
    const use_tls = std.mem.startsWith(u8, logical_url, "wss://");
    if (!use_tls and !std.mem.startsWith(u8, logical_url, "ws://")) return error.Invalid;
    // GAP-17: WebSocket has no shaped-TLS variant; reject wss on
    // a profiled client instead of falling back to std TLS.
    if (use_tls and client.tls_profile != null) return error.Invalid;
    const normalized_url = try normalizedWebSocketUrl(client.allocator, logical_url);
    defer client.allocator.free(normalized_url);
    const uri = std.Uri.parse(normalized_url) catch return error.Invalid;
    if (uri.fragment != null) return error.Invalid;
    _ = timeout_ms; // handshake is blocking; callers bound total time via poll

    var key_bytes: [16]u8 = undefined;
    sio.io().random(&key_bytes);
    var key_buffer: [24]u8 = undefined;
    const key = std.base64.standard.Encoder.encode(&key_buffer, &key_bytes);

    for (headers) |header| {
        if (reservedWebSocketHeader(header.name)) continue;
        if (!validHeaderName(header.name) or !validHeaderValue(header.value)) return error.Invalid;
    }

    const host_slice = switch (uri.host orelse return error.Invalid) {
        .raw => |s| s,
        .percent_encoded => |s| s,
    };

    // Dial: unix socket or TCP (+TLS handshake for wss://).
    var stream: std.Io.net.Stream = undefined;
    if (unix_socket_path) |path| {
        if (path.len == 0) return error.Invalid;
        const addr = std.Io.net.UnixAddress.init(path) catch return error.Invalid;
        stream = addr.connect(sio.io()) catch return error.Closed;
    } else {
        const port: u16 = uri.port orelse if (use_tls) 443 else 80;
        stream = dialHost(host_slice, port) catch return error.Closed;
    }
    errdefer stream.close(sio.io());

    const handle = client.allocator.create(WebSocketV2) catch return error.Io;
    errdefer client.allocator.destroy(handle);
    client.retain();
    errdefer client.release();
    handle.* = .{
        .allocator = client.allocator,
        .client = client,
        .stream = stream,
        .receive_buffer = std.array_list.Managed(u8).init(client.allocator),
        .fragment_buffer = std.array_list.Managed(u8).init(client.allocator),
    };
    errdefer {
        handle.receive_buffer.deinit();
        handle.fragment_buffer.deinit();
    }
    handle.frame_reader = stream.reader(sio.io(), &handle.frame_read_buf);

    if (use_tls and unix_socket_path == null) {
        handle.net_reader = stream.reader(sio.io(), &handle.net_read_buf);
        handle.net_writer = stream.writer(sio.io(), &handle.net_write_buf);
        var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
        sio.io().random(&entropy);
        const tls_client = client.allocator.create(std.crypto.tls.Client) catch return error.Io;
        errdefer client.allocator.destroy(tls_client);
        tls_client.* = std.crypto.tls.Client.init(
            &handle.net_reader.interface,
            &handle.net_writer.interface,
            .{
                .host = .{ .explicit = host_slice },
                .ca = .{ .bundle = .{
                    .gpa = client.allocator,
                    .io = sio.io(),
                    .lock = &handle.ca_lock,
                    .bundle = &client.client.ca_bundle,
                } },
                .write_buffer = &handle.tls_write_buf,
                .read_buffer = &handle.tls_read_buf,
                .entropy = &entropy,
                .realtime_now = std.Io.Clock.real.now(sio.io()),
            },
        ) catch return error.Io;
        handle.tls_client = tls_client;
    }
    errdefer handle.deinit();

    // Request target: path + optional query.
    var target_buf: [8192]u8 = undefined;
    var target_stream = std.Io.Writer.fixed(&target_buf);
    const raw_path: []const u8 = switch (uri.path) {
        .raw => |s| if (s.len != 0) s else "/",
        .percent_encoded => |s| if (s.len != 0) s else "/",
    };
    target_stream.print("{s}", .{raw_path}) catch return error.Io;
    if (uri.query) |q| {
        const qs = switch (q) {
            .raw => |s| s,
            .percent_encoded => |s| s,
        };
        target_stream.print("?{s}", .{qs}) catch return error.Io;
    }
    const target = target_stream.buffer[0..target_stream.end];

    var req_buf = std.array_list.Managed(u8).init(client.allocator);
    defer req_buf.deinit();
    req_buf.print("GET {s} HTTP/1.1\r\n", .{target}) catch return error.Io;
    req_buf.print("Host: {s}\r\n", .{host_slice}) catch return error.Io;
    req_buf.appendSlice("Connection: Upgrade\r\nUpgrade: websocket\r\nsec-websocket-version: 13\r\n") catch return error.Io;
    for (headers) |header| {
        if (reservedWebSocketHeader(header.name)) continue;
        req_buf.print("{s}: {s}\r\n", .{ header.name, header.value }) catch return error.Io;
    }
    req_buf.print("sec-websocket-key: {s}\r\n\r\n", .{key}) catch return error.Io;
    handle.rawWrite(req_buf.items) catch return error.Io;

    // Read response head.
    var head_buf = std.array_list.Managed(u8).init(client.allocator);
    defer head_buf.deinit();
    var tmp: [4096]u8 = undefined;
    var head_end: ?usize = null;
    while (head_end == null) {
        const n = handle.rawRead(&tmp) catch return error.Io;
        if (n == 0) return error.Closed;
        head_buf.appendSlice(tmp[0..n]) catch return error.Io;
        if (head_buf.items.len > 64 * 1024) return error.TooLarge;
        if (std.mem.indexOf(u8, head_buf.items, "\r\n\r\n")) |idx| head_end = idx;
    }
    const head = head_buf.items[0..head_end.?];
    // Preserve any bytes pipelined after the handshake head (e.g. the
    // first frame) into the frame input buffer instead of dropping them.
    const pipelined = head_buf.items[head_end.? + 4 ..];
    if (pipelined.len != 0) {
        handle.receive_buffer.appendSlice(pipelined) catch return error.Io;
    }
    {
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        const status_line = lines.next() orelse return error.Invalid;
        var parts = std.mem.splitScalar(u8, status_line, ' ');
        _ = parts.next();
        const code_str = parts.next() orelse return error.Invalid;
        const code = std.fmt.parseInt(u16, code_str, 10) catch return error.Invalid;
        if (code != 101) return error.Invalid;
    }
    const upgrade = findRawHeaderV2(head, "upgrade") orelse return error.Invalid;
    if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) return error.Invalid;
    const connection_header = findRawHeaderV2(head, "connection") orelse return error.Invalid;
    if (!websocketHeaderContainsTokenV2(connection_header, "upgrade")) return error.Invalid;
    const accept = findRawHeaderV2(head, "sec-websocket-accept") orelse return error.Invalid;
    var expected_buffer: [28]u8 = undefined;
    const expected = websocketAccept(key, &expected_buffer) catch return error.Invalid;
    if (!std.mem.eql(u8, accept, expected)) return error.Invalid;
    return handle;
}
pub export fn sa_http_client_websocket_connect_v2(
    client: ?*anyopaque,
    url_ptr: ?[*]const u8,
    url_len: u64,
    timeout_ms: u32,
    out_ws: ?*?*anyopaque,
) u32 {
    const slot = out_ws orelse return statusCode(.invalid);
    slot.* = null;
    const client_ptr = client orelse return statusCode(.invalid);
    const url = requiredSlice(url_ptr, url_len) catch return statusCode(.invalid);
    const cli: *HttpClient = @ptrCast(@alignCast(client_ptr));
    const websocket = websocketConnect(cli, url, &.{}, null, timeout_ms) catch |err| return statusCode(statusFromV2Error(err));
    slot.* = @ptrCast(websocket);
    return statusCode(.ok);
}
pub export fn sa_http_client_websocket_connect_unix_v2(
    client: ?*anyopaque,
    socket_path_ptr: ?[*]const u8,
    socket_path_len: u64,
    url_ptr: ?[*]const u8,
    url_len: u64,
    timeout_ms: u32,
    out_ws: ?*?*anyopaque,
) u32 {
    const slot = out_ws orelse return statusCode(.invalid);
    slot.* = null;
    const client_ptr = client orelse return statusCode(.invalid);
    const socket_path = requiredSlice(socket_path_ptr, socket_path_len) catch return statusCode(.invalid);
    const url = requiredSlice(url_ptr, url_len) catch return statusCode(.invalid);
    const cli: *HttpClient = @ptrCast(@alignCast(client_ptr));
    const websocket = websocketConnect(cli, url, &.{}, socket_path, timeout_ms) catch |err| return statusCode(statusFromV2Error(err));
    slot.* = @ptrCast(websocket);
    return statusCode(.ok);
}
pub export fn sa_http_client_req_websocket_connect_v2(req: ?*anyopaque, timeout_ms: u32, out_ws: ?*?*anyopaque) u32 {
    const slot = out_ws orelse return statusCode(.invalid);
    slot.* = null;
    const req_ptr = req orelse return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    const effective_timeout = if (timeout_ms == 0) request.timeout_ms else timeout_ms;
    const websocket = websocketConnect(request.client, request.url, request.headers.items, null, effective_timeout) catch |err| return statusCode(statusFromV2Error(err));
    slot.* = @ptrCast(websocket);
    return statusCode(.ok);
}
pub export fn sa_http_client_req_websocket_connect_unix_v2(
    req: ?*anyopaque,
    socket_path_ptr: ?[*]const u8,
    socket_path_len: u64,
    timeout_ms: u32,
    out_ws: ?*?*anyopaque,
) u32 {
    const slot = out_ws orelse return statusCode(.invalid);
    slot.* = null;
    const req_ptr = req orelse return statusCode(.invalid);
    const socket_path = requiredSlice(socket_path_ptr, socket_path_len) catch return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    const effective_timeout = if (timeout_ms == 0) request.timeout_ms else timeout_ms;
    const websocket = websocketConnect(request.client, request.url, request.headers.items, socket_path, effective_timeout) catch |err| return statusCode(statusFromV2Error(err));
    slot.* = @ptrCast(websocket);
    return statusCode(.ok);
}
