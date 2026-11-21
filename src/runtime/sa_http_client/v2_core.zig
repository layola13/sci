const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const HttpClient = @import("core.zig").HttpClient;
const HttpMethod = @import("core.zig").HttpMethod;
const HttpRequest = @import("core.zig").HttpRequest;
const HttpResponse = @import("response.zig").HttpResponse;
const V2AsyncOp = @import("v2_websocket.zig").V2AsyncOp;
const clientAllocator = @import("core.zig").clientAllocator;
const maybeBypassProxy = @import("response.zig").maybeBypassProxy;

// ---- v2 async surface (ex http_v2_api.zig) ----



pub const max_v2_message_bytes: u64 = 16 * 1024 * 1024;
pub const default_v2_response_bytes: u64 = 16 * 1024 * 1024;
pub const NetworkStatus = enum(u32) {
    ok = 0,
    would_block = 1,
    closed = 2,
    timeout = 3,
    too_large = 4,
    invalid = 5,
    io_error = 6,
};
pub const PollEvent = struct {
    pub const readable: u32 = 1;
    pub const writable: u32 = 2;
    pub const closed: u32 = 4;
};
pub const V2Error = error{
    WouldBlock,
    Closed,
    Timeout,
    TooLarge,
    Invalid,
    Io,
};
pub fn statusCode(status: NetworkStatus) u32 {
    return @intFromEnum(status);
}
pub fn statusFromV2Error(err: V2Error) NetworkStatus {
    return switch (err) {
        error.WouldBlock => .would_block,
        error.Closed => .closed,
        error.Timeout => .timeout,
        error.TooLarge => .too_large,
        error.Invalid => .invalid,
        error.Io => .io_error,
    };
}
fn statusFromOperationError(err: anyerror, has_timeout: bool) NetworkStatus {
    return switch (err) {
        error.WouldBlock => if (has_timeout) .timeout else .would_block,
        error.ConnectionTimedOut => .timeout,
        error.EndOfStream,
        error.BrokenPipe,
        error.ConnectionAborted,
        error.ConnectionResetByPeer,
        error.NotOpenForReading,
        error.NotOpenForWriting,
        => .closed,
        error.StreamTooLong, error.BodyTooLarge => .too_large,
        error.InvalidCharacter,
        error.InvalidContentLength,
        error.InvalidPort,
        error.InvalidUri,
        error.UriMissingHost,
        error.UnsupportedUriScheme,
        error.HttpHeadersInvalid,
        error.HttpHeadersOversize,
        error.InvalidWebSocketFrame,
        error.InvalidArgument,
        => .invalid,
        else => .io_error,
    };
}
pub fn requiredSlice(ptr: ?[*]const u8, len: u64) V2Error![]const u8 {
    if (len > std.math.maxInt(usize)) return error.Invalid;
    if (len == 0) return "";
    return (ptr orelse return error.Invalid)[0..@intCast(len)];
}
pub fn validHeaderName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        const valid = std.ascii.isAlphanumeric(ch) or switch (ch) {
            '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
            else => false,
        };
        if (!valid) return false;
    }
    return true;
}
pub fn validHeaderValue(value: []const u8) bool {
    return std.mem.indexOfAny(u8, value, "\r\n\x00") == null;
}
/// std.http.Client reserves dedicated request slots for a few
/// standard headers and emits its own default for each slot
/// BEFORE any extra_headers (see emitOverridableHeader in
/// std/http/Client.zig). A caller-supplied header with one of
/// those names passed as an extra header is therefore shadowed
/// on the wire -- registered gap G5: req_add_header("user-agent")
/// never beat std's "zig/<ver> (std.http)" default, and an echo
/// upstream reports the std value, not the caller's. Route
/// caller values for the slotted names into the slots (last one
/// wins, matching header-set semantics) and keep everything else
/// in extra_headers.
const StdHeaderParts = struct {
    headers: std.http.Client.Request.Headers = .{},
    extra: []std.http.Header,
};
pub fn splitStdHeaders(allocator: std.mem.Allocator, headers: []const std.http.Header) !StdHeaderParts {
    var extra = std.array_list.Managed(std.http.Header).init(allocator);
    errdefer extra.deinit();
    var parts = StdHeaderParts{ .extra = &.{} };
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "host")) {
            parts.headers.host = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
            parts.headers.authorization = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "user-agent")) {
            parts.headers.user_agent = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "connection")) {
            parts.headers.connection = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "accept-encoding")) {
            parts.headers.accept_encoding = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "content-type")) {
            parts.headers.content_type = .{ .override = header.value };
        } else {
            try extra.append(header);
        }
    }
    parts.extra = try extra.toOwnedSlice();
    return parts;
}
fn methodFromCode(method: u8) ?HttpMethod {
    return switch (method) {
        1 => .get,
        2 => .post,
        3 => .put,
        4 => .delete,
        5 => .head,
        6 => .patch,
        7 => .options,
        8 => .trace,
        9 => .connect,
        else => null,
    };
}
pub export fn sa_http_client_new_v2(
    use_tls: u8,
    ca_bundle_path_ptr: ?[*]const u8,
    ca_bundle_path_len: u64,
    out_client: ?*?*anyopaque,
) u32 {
    const slot = out_client orelse return statusCode(.invalid);
    slot.* = null;
    const ca_path = requiredSlice(ca_bundle_path_ptr, ca_bundle_path_len) catch return statusCode(.invalid);
    const client = HttpClient.init(clientAllocator(), .{
        .use_tls = use_tls,
        .ca_bundle_path = if (ca_path.len == 0) null else ca_path,
    }) catch |err| return statusCode(statusFromOperationError(err, false));
    slot.* = @ptrCast(client);
    return statusCode(.ok);
}
pub export fn sa_http_client_req_new_v2(
    client: ?*anyopaque,
    method: u8,
    url_ptr: ?[*]const u8,
    url_len: u64,
    out_req: ?*?*anyopaque,
) u32 {
    const slot = out_req orelse return statusCode(.invalid);
    slot.* = null;
    const client_ptr = client orelse return statusCode(.invalid);
    const url = requiredSlice(url_ptr, url_len) catch return statusCode(.invalid);
    if (url.len == 0) return statusCode(.invalid);
    const http_method = methodFromCode(method) orelse return statusCode(.invalid);
    const cli: *HttpClient = @ptrCast(@alignCast(client_ptr));
    cli.retain();
    const request = HttpRequest.init(cli, .{
        .method = http_method,
        .url = url,
    }) catch |err| {
        cli.release();
        return statusCode(statusFromOperationError(err, false));
    };
    request.retains_client = true;
    slot.* = @ptrCast(request);
    return statusCode(.ok);
}
pub export fn sa_http_client_req_add_header_v2(
    req: ?*anyopaque,
    key_ptr: ?[*]const u8,
    key_len: u64,
    value_ptr: ?[*]const u8,
    value_len: u64,
) u32 {
    const req_ptr = req orelse return statusCode(.invalid);
    const key = requiredSlice(key_ptr, key_len) catch return statusCode(.invalid);
    const value = requiredSlice(value_ptr, value_len) catch return statusCode(.invalid);
    if (!validHeaderName(key) or !validHeaderValue(value)) return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    const name_copy = request.allocator.dupe(u8, key) catch return statusCode(.io_error);
    const value_copy = request.allocator.dupe(u8, value) catch {
        request.allocator.free(name_copy);
        return statusCode(.io_error);
    };
    request.headers.append(.{ .name = name_copy, .value = value_copy }) catch {
        request.allocator.free(name_copy);
        request.allocator.free(value_copy);
        return statusCode(.io_error);
    };
    return statusCode(.ok);
}
pub export fn sa_http_client_req_set_body_v2(req: ?*anyopaque, body_ptr: ?[*]const u8, body_len: u64) u32 {
    const req_ptr = req orelse return statusCode(.invalid);
    const body = requiredSlice(body_ptr, body_len) catch return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    const body_copy = request.allocator.dupe(u8, body) catch return statusCode(.io_error);
    if (request.body) |old| request.allocator.free(old);
    request.body = body_copy;
    return statusCode(.ok);
}
pub export fn sa_http_client_req_set_timeout_v2(req: ?*anyopaque, timeout_ms: u32) u32 {
    const req_ptr = req orelse return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    request.timeout_ms = timeout_ms;
    return statusCode(.ok);
}
pub export fn sa_http_client_req_set_max_response_bytes_v2(req: ?*anyopaque, max_bytes: u64) u32 {
    const req_ptr = req orelse return statusCode(.invalid);
    if (max_bytes == 0 or max_bytes > std.math.maxInt(usize)) return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    request.max_response_bytes = max_bytes;
    return statusCode(.ok);
}
const Deadline = struct {
    // NOTE(Zig 0.17): `std.time.Instant` was removed; wall nanos via sio.
    started_ns: ?i128,
    duration_ns: u64 = 0,
    immediate: bool = false,

    pub fn request(timeout_ms: u32) Deadline {
        if (timeout_ms == 0) return .{ .started_ns = null };
        return .{
            .started_ns = sio.nanoTimestamp(),
            .duration_ns = @as(u64, timeout_ms) * std.time.ns_per_ms,
        };
    }

    fn operation(timeout_ms: u32) Deadline {
        if (timeout_ms == 0) return .{ .started_ns = null, .immediate = true };
        return .{
            .started_ns = sio.nanoTimestamp(),
            .duration_ns = @as(u64, timeout_ms) * std.time.ns_per_ms,
            .immediate = false,
        };
    }

    pub fn hasTimeout(self: Deadline) bool {
        return self.started_ns != null;
    }

    pub fn remainingNs(self: Deadline) V2Error!u64 {
        const started = self.started_ns orelse return 0;
        const elapsed: i128 = sio.nanoTimestamp() - started;
        if (elapsed < 0) return 0;
        const elapsed_u: u64 = @intCast(elapsed);
        if (elapsed_u >= self.duration_ns) return error.Timeout;
        return self.duration_ns - elapsed_u;
    }

    fn pollMillis(self: Deadline) V2Error!u32 {
        if (self.immediate) return 0;
        if (self.started == null) return 0;
        const remaining = try self.remainingNs();
        const rounded = @divFloor(remaining + std.time.ns_per_ms - 1, std.time.ns_per_ms);
        return @intCast(@min(rounded, std.math.maxInt(u32)));
    }

    pub fn socketMillis(self: Deadline) V2Error!u32 {
        if (self.immediate) return 1;
        if (self.started_ns == null) return 0;
        const remaining = try self.remainingNs();
        const rounded = @divFloor(remaining + std.time.ns_per_ms - 1, std.time.ns_per_ms);
        return @intCast(@max(@as(u64, 1), @min(rounded, std.math.maxInt(u32))));
    }
};
fn setConnectionTimeout(connection: *std.http.Client.Connection, timeout_ms: u32) V2Error!void {
    // NOTE(Zig 0.17): per-socket timeouts via setsockopt were removed with the
    // old Client API surface used here; timeouts are enforced by Deadline
    // checks around operations instead.
    _ = connection;
    _ = timeout_ms;
}
fn cloneResponseHeadersV2(allocator: std.mem.Allocator, response: std.http.Client.Response) ![]std.http.Header {
    var headers = std.array_list.Managed(std.http.Header).init(allocator);
    errdefer {
        for (headers.items) |header| {
            allocator.free(header.name);
            allocator.free(header.value);
        }
        headers.deinit();
    }
    var iterator = response.head.iterateHeaders();
    while (iterator.next()) |header| {
        const name = try allocator.dupe(u8, header.name);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, header.value);
        errdefer allocator.free(value);
        try headers.append(.{ .name = name, .value = value });
    }
    return headers.toOwnedSlice();
}
fn freeResponseHeaders(allocator: std.mem.Allocator, headers: []std.http.Header) void {
    for (headers) |header| {
        allocator.free(header.name);
        allocator.free(header.value);
    }
    allocator.free(headers);
}
fn requestCancelled(tracker: ?*V2AsyncOp) bool {
    return if (tracker) |op| op.cancelled() else false;
}
fn mapHttpError(err: anyerror, deadline: Deadline, tracker: ?*V2AsyncOp) V2Error {
    if (requestCancelled(tracker)) return error.Closed;
    if (deadline.hasTimeout() and (err == error.UnexpectedReadFailure or err == error.UnexpectedWriteFailure)) {
        const remaining = deadline.remainingNs() catch |deadline_err| return deadline_err;
        if (remaining <= std.time.ns_per_ms) return error.Timeout;
    }
    return switch (statusFromOperationError(err, deadline.hasTimeout())) {
        .would_block => error.WouldBlock,
        .closed => error.Closed,
        .timeout => error.Timeout,
        .too_large => error.TooLarge,
        .invalid => error.Invalid,
        .io_error => error.Io,
        .ok => unreachable,
    };
}
fn checkRequestState(deadline: Deadline, tracker: ?*V2AsyncOp) V2Error!void {
    if (requestCancelled(tracker)) return error.Closed;
    _ = deadline.socketMillis() catch |err| return err;
}
fn configureRequestConnection(connection: *std.http.Client.Connection, deadline: Deadline, tracker: ?*V2AsyncOp) V2Error!void {
    if (tracker) |op| try op.attach(connection.stream.handle);
    errdefer if (tracker) |op| op.detach(connection.stream.handle);
    try setConnectionTimeout(connection, try deadline.socketMillis());
}
pub fn executeRequestV2(request: *HttpRequest, tracker: ?*V2AsyncOp) V2Error!*HttpResponse {
    const deadline = Deadline.request(request.timeout_ms);
    if (requestCancelled(tracker)) return error.Closed;
    const uri = std.Uri.parse(request.url) catch |err| return mapHttpError(err, deadline, tracker);
    // GAP-17: the v2 send path has no shaped-TLS variant; a
    // profiled client must not silently fall back to std TLS.
    if (request.client.tls_profile != null and std.mem.eql(u8, uri.scheme, "https")) return error.Invalid;
    // Mirror the v1 path (httpRequestExecOnce): under the
    // client-wide request mutex, drop the configured proxies for
    // this request when the target host matches no_proxy, and
    // restore them before returning. v2 previously skipped this
    // entirely, so in proxied deployments requests to no_proxy
    // hosts were routed into the proxy (slanginx line finding).
    while (!request.client.request_mutex.tryLock()) std.atomic.spinLoopHint();
    defer request.client.request_mutex.unlock();
    const saved_http_proxy = request.client.client.http_proxy;
    const saved_https_proxy = request.client.client.https_proxy;
    defer {
        request.client.client.http_proxy = saved_http_proxy;
        request.client.client.https_proxy = saved_https_proxy;
    }
    maybeBypassProxy(request, uri);
    // NOTE(Zig 0.17): proxy CONNECT tunnels are handled natively by
    // std.http.Client now; the manual-tunnel path was removed.
    var redirect_buffer: [16 * 1024]u8 = undefined;
    const parts = splitStdHeaders(request.allocator, request.headers.items) catch return error.Io;
    defer request.allocator.free(parts.extra);
    var http_request = request.client.client.request(request.method, uri, .{
        .keep_alive = false,
        .redirect_behavior = .unhandled,
        .headers = parts.headers,
        .extra_headers = parts.extra,
    }) catch |err| return mapHttpError(err, deadline, tracker);
    defer http_request.deinit();

    if (request.body) |body| {
        const owned_body = request.allocator.dupe(u8, body) catch return error.Io;
        defer request.allocator.free(owned_body);
        checkRequestState(deadline, tracker) catch |err| return err;
        http_request.sendBodyComplete(owned_body) catch |err| return mapHttpError(err, deadline, tracker);
    } else {
        checkRequestState(deadline, tracker) catch |err| return err;
        http_request.sendBodiless() catch |err| return mapHttpError(err, deadline, tracker);
    }
    checkRequestState(deadline, tracker) catch |err| return err;
    var response = http_request.receiveHead(&redirect_buffer) catch |err| return mapHttpError(err, deadline, tracker);

    const headers = cloneResponseHeadersV2(request.allocator, response) catch return error.Io;
    errdefer freeResponseHeaders(request.allocator, headers);

    var body = std.array_list.Managed(u8).init(request.allocator);
    errdefer body.deinit();
    // D6: for a request method whose response has no body by
    // definition (HEAD), std's Response.reader() returns the
    // shared Io.Reader.ending singleton -- a @constCast pointer
    // to a const global that lands in .data.rel.ro and is mapped
    // read-only after relocation in zig-cc/LLD-linked binaries
    // (exactly how SA binaries are linked). readSliceShort
    // writes the reader's seek field through that pointer and
    // segfaults. The body is empty by definition, so the read
    // loop must be skipped entirely for such responses; never
    // touch the ending reader.
    if (request.method.responseHasBody()) {
        var transfer_buffer: [8192]u8 = undefined;
        var response_reader = response.reader(&transfer_buffer);
        var read_buffer: [8192]u8 = undefined;
        while (true) {
            checkRequestState(deadline, tracker) catch |err| return err;
            const read_len = response_reader.readSliceShort(&read_buffer) catch |err| return mapHttpError(err, deadline, tracker);
            if (read_len == 0) break;
            const next_len = std.math.add(u64, @intCast(body.items.len), @intCast(read_len)) catch return error.TooLarge;
            if (next_len > request.max_response_bytes) return error.TooLarge;
            body.appendSlice(read_buffer[0..read_len]) catch return error.Io;
        }
    }

    const out = request.allocator.create(HttpResponse) catch return error.Io;
    errdefer request.allocator.destroy(out);
    out.* = .{
        .allocator = request.allocator,
        .status = @intCast(@intFromEnum(response.head.status)),
        .headers = headers,
        .body = body.toOwnedSlice() catch return error.Io,
    };
    return out;
}
pub export fn sa_http_client_req_send_v2(req: ?*anyopaque, out_resp: ?*?*anyopaque) u32 {
    const slot = out_resp orelse return statusCode(.invalid);
    slot.* = null;
    const req_ptr = req orelse return statusCode(.invalid);
    const request: *HttpRequest = @ptrCast(@alignCast(req_ptr));
    const response = executeRequestV2(request, null) catch |err| return statusCode(statusFromV2Error(err));
    slot.* = @ptrCast(response);
    return statusCode(.ok);
}
