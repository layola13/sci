//! sa_std built-in HTTP/1.1 client (+ WebSocket client + SSE streaming).
//!
//! Migrated from the sa_plugin_http_client plugin (2026-10-24) under the
//! "all foundational cores live in sa_std" doctrine: the plugin keeps
//! only framework-level wrapping. The extern surface is unchanged
//! (sa_http_client_* / sa_http_websocket_*), so existing .sai callers
//! link against libsa_std.a with no plugin installed.
//!
//! Transports: std.http.Client for the request/response paths, a curl
//! subprocess for the SSE POST path (proxy/TLS edge cases), and raw
//! streams for the WebSocket client. Response compression is disabled
//! by asking upstreams for `Accept-Encoding: identity` (the plugin's
//! long-standing strategy: always-safe bodies over negotiated ones).

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

// AbiStatus mirrors the plugin ABI enum (ok=0, failed=2), localized so
// the std module carries no plugin dependency.
const AbiStatus = enum(u32) { ok = 0, failed = 2 };

// Client-owned allocations pool through malloc (the same decision the
// server face documents at serverAllocator): the page allocator costs
// one mmap/munmap pair per small allocation, and a client request
// churns dozens of small allocations (header pairs, body lists, URI
// clones), so per-request throughput collapses into syscall overhead.
// Every HttpClient allocation flows from the allocator stored at
// construction, so switching the two constructors switches the whole
// request/response lifecycle consistently.
fn clientAllocator() std.mem.Allocator {
    return std.heap.c_allocator;
}


// ---- shared WS frame helpers (ex plugin sa_std_net.zig) ----
const sa_net = @import("sa_net_primitives");

pub const WebSocketFrame = struct {
    opcode: u8,
    payload: []u8,
};

const ParsedFrame = struct {
    fin: bool,
    opcode: u8,
    masked: bool,
    payload_offset: usize,
    payload_len: usize,
    frame_len: usize,
    mask: [4]u8,
};

pub fn websocketAccept(key: []const u8, out: *[28]u8) ![]const u8 {
    const accept = try sa_net.websocketAccept(key);
    @memcpy(out[0..], accept[0..]);
    return out[0..];
}

pub fn buildWebSocketFrame(out: []u8, opcode: u8, payload: []const u8, mask: ?*const [4]u8) !usize {
    return sa_net.buildWsFrame(opcode, true, payload, mask, out) catch |err| switch (err) {
        error.NoSpaceLeft => error.NoSpaceLeft,
        else => error.InvalidWebSocketFrame,
    };
}

pub fn readWebSocketFrameAlloc(allocator: std.mem.Allocator, reader: *std.Io.Reader, max_len: u64, expect_masked: bool) !WebSocketFrame {
    var header: [14]u8 = undefined;
    try readExact(reader, header[0..2]);

    if ((header[0] & 0x70) != 0) return error.InvalidWebSocketFrame;
    const masked = (header[1] & 0x80) != 0;
    if (masked != expect_masked) return error.InvalidWebSocketFrame;

    var payload_len: u64 = header[1] & 0x7f;
    var header_len: usize = 2;
    if (payload_len == 126) {
        try readExact(reader, header[2..4]);
        payload_len = std.mem.readInt(u16, header[2..4], .big);
        header_len = 4;
    } else if (payload_len == 127) {
        try readExact(reader, header[2..10]);
        payload_len = std.mem.readInt(u64, header[2..10], .big);
        header_len = 10;
    }

    if (payload_len > max_len or payload_len > std.math.maxInt(usize)) return error.InvalidWebSocketFrame;
    if (masked) {
        try readExact(reader, header[header_len .. header_len + 4]);
        header_len += 4;
    }

    const payload_len_usize: usize = @intCast(payload_len);
    const frame_len = std.math.add(usize, header_len, payload_len_usize) catch return error.InvalidWebSocketFrame;
    const frame = try allocator.alloc(u8, frame_len);
    defer allocator.free(frame);
    @memcpy(frame[0..header_len], header[0..header_len]);
    if (payload_len_usize > 0) try readExact(reader, frame[header_len..frame_len]);

    const parsed = try parseWebSocketFrame(frame);
    if (!parsed.fin or parsed.masked != expect_masked or parsed.frame_len != frame_len) return error.InvalidWebSocketFrame;

    var payload: []u8 = &.{};
    if (parsed.payload_len > 0) {
        payload = try allocator.alloc(u8, parsed.payload_len);
        errdefer allocator.free(payload);
        @memcpy(payload, frame[parsed.payload_offset .. parsed.payload_offset + parsed.payload_len]);
        if (parsed.masked) try unmaskWebSocketPayload(payload, parsed.mask);
    }

    return .{ .opcode = parsed.opcode, .payload = payload };
}

fn parseWebSocketFrame(frame: []const u8) !ParsedFrame {
    const parsed = sa_net.parseWsFrame(frame) catch |err| switch (err) {
        error.Incomplete => return error.EndOfStream,
        error.Invalid => return error.InvalidWebSocketFrame,
    };
    return .{
        .fin = parsed.fin,
        .opcode = parsed.opcode,
        .masked = parsed.masked,
        .payload_offset = parsed.payload_start,
        .payload_len = parsed.payload_len,
        .frame_len = parsed.frame_len,
        .mask = parsed.mask,
    };
}

fn unmaskWebSocketPayload(payload: []u8, mask: [4]u8) !void {
    if (payload.len == 0) return;
    sa_net.unmaskFrame(payload, mask);
}

fn readExact(reader: *std.Io.Reader, buffer: []u8) !void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const read_n = reader.readSliceShort(buffer[offset..]) catch return error.EndOfStream;
        if (read_n == 0) return error.EndOfStream;
        offset += read_n;
    }
}

// ---- sync + legacy WS + SSE surface (ex http_saasm_api.zig) ----


// NOTE(Zig 0.17): `std.net.tcpConnectToHost` was removed (only literals via
// `IpAddress.parse`; DNS via `HostName.connect` with Happy Eyeballs).
pub fn dialHost(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                ok = false;
                break;
            }
        }
        if (ok) return i;
    }
    return null;
}
pub const SaHttpClientHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpRequestHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpResponseHandle = extern struct {
    impl: ?*anyopaque,
};

pub const SaHttpBodyReaderHandle = extern struct {
    impl: ?*anyopaque,
};

pub const HttpMethod = enum(u8) {
    get = 1,
    post = 2,
    put = 3,
    delete = 4,
    head = 5,
    patch = 6,
    options = 7,
    trace = 8,
    connect = 9,
};

pub const HttpClientConfig = struct {
    use_tls: u8,
    ca_bundle_path: ?[]const u8 = null,
};

pub const HttpRequestConfig = struct {
    method: HttpMethod,
    url: []const u8,
    body: ?[]const u8 = null,
    headers: []const std.http.Header = &.{},
};

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    proxy_arena: std.heap.ArenaAllocator,
    lifetime_mutex: std.atomic.Mutex = .unlocked,
    reference_count: usize = 1,
    // Serializes request execution so per-request proxy bypass (no_proxy)
    // can temporarily clear client.http_proxy/https_proxy safely.
    request_mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator, cfg: HttpClientConfig) !*HttpClient {
        const self = try allocator.create(HttpClient);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .client = .{ .allocator = allocator, .io = sio.io() },
            .proxy_arena = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer self.proxy_arena.deinit();
        // Route through https_proxy/http_proxy env vars when present (sandboxed
        // environments may block direct DNS/TCP; the proxy path is required).
        // NOTE(Zig 0.17): proxy env must be loaded explicitly via arena + map.
        if (sio.getEnvMap(allocator)) |env| {
            var owned_env = env;
            defer owned_env.deinit();
            self.client.initDefaultProxies(self.proxy_arena.allocator(), &owned_env) catch {};
        } else |_| {}
        try self.configureHttpsTrust(cfg);
        return self;
    }

    fn configureHttpsTrust(self: *HttpClient, cfg: HttpClientConfig) !void {
        if (std.http.Client.disable_tls or cfg.use_tls == 0) return;
        if (cfg.ca_bundle_path) |bundle_path| {
            const abs_path = try sio.cwd().realpathAlloc(self.allocator, bundle_path);
            defer self.allocator.free(abs_path);
            const now = std.Io.Clock.real.now(sio.io());
            try self.client.ca_bundle.addCertsFromFilePathAbsolute(
                self.allocator,
                sio.io(),
                now,
                abs_path,
            );
            // NOTE(Zig 0.17): std.http.Client.fetch() rescans the OS trust
            // store and SWAPS OUT our bundle when client.now == null. Pin now
            // so the custom CA survives.
            self.client.now = now;
        }
    }

    pub fn retain(self: *HttpClient) void {
        while (!self.lifetime_mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.lifetime_mutex.unlock();
        std.debug.assert(self.reference_count > 0);
        self.reference_count += 1;
    }

    pub fn release(self: *HttpClient) void {
        while (!self.lifetime_mutex.tryLock()) std.atomic.spinLoopHint();
        std.debug.assert(self.reference_count > 0);
        self.reference_count -= 1;
        const destroy = self.reference_count == 0;
        self.lifetime_mutex.unlock();
        if (!destroy) return;
        self.client.deinit();
        self.proxy_arena.deinit();
        self.allocator.destroy(self);
    }
};

pub const HttpRequest = struct {
    allocator: std.mem.Allocator,
    client: *HttpClient,
    method: std.http.Method,
    url: []const u8,
    body: ?[]const u8 = null,
    headers: std.array_list.Managed(std.http.Header),
    timeout_ms: u32 = 0,
    max_response_bytes: u64 = 16 * 1024 * 1024,
    retains_client: bool = false,

    pub fn init(client: *HttpClient, cfg: HttpRequestConfig) !*HttpRequest {
        const self = try client.allocator.create(HttpRequest);
        errdefer client.allocator.destroy(self);
        self.* = .{
            .allocator = client.allocator,
            .client = client,
            .method = switch (cfg.method) {
                .get => .GET,
                .post => .POST,
                .put => .PUT,
                .delete => .DELETE,
                .head => .HEAD,
                .patch => .PATCH,
                .options => .OPTIONS,
                .trace => .TRACE,
                .connect => .CONNECT,
            },
            .url = try client.allocator.dupe(u8, cfg.url),
            .headers = std.array_list.Managed(std.http.Header).init(client.allocator),
        };
        errdefer client.allocator.free(self.url);
        errdefer self.headers.deinit();
        for (cfg.headers) |header| {
            const name = try client.allocator.dupe(u8, header.name);
            errdefer client.allocator.free(name);
            const value = try client.allocator.dupe(u8, header.value);
            errdefer client.allocator.free(value);
            try self.headers.append(.{ .name = name, .value = value });
        }
        self.body = if (cfg.body) |body| try client.allocator.dupe(u8, body) else null;
        errdefer if (self.body) |body| client.allocator.free(body);
        return self;
    }

    pub fn deinit(self: *HttpRequest) void {
        const client = self.client;
        const retains_client = self.retains_client;
        for (self.headers.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        if (self.body) |body| self.allocator.free(body);
        self.allocator.free(self.url);
        self.headers.deinit();
        client.allocator.destroy(self);
        if (retains_client) client.release();
    }
};

fn requestUrlOriginLen(target: []const u8) usize {
    var authority_start: usize = 0;
    var scan: usize = 0;
    while (scan + 2 < target.len) : (scan += 1) {
        if (target[scan] == ':' and target[scan + 1] == '/' and target[scan + 2] == '/') {
            authority_start = scan + 3;
            break;
        }
    }
    var i = authority_start;
    while (i < target.len) : (i += 1) {
        switch (target[i]) {
            '/', '?', '#' => return i,
            else => {},
        }
    }
    return target.len;
}

fn targetBasePath(target: []const u8) []const u8 {
    const start = requestUrlOriginLen(target);
    if (start >= target.len or target[start] != '/') return "";
    var end = start;
    while (end < target.len and target[end] != '?' and target[end] != '#') : (end += 1) {}
    while (end > start and target[end - 1] == '/') end -= 1;
    if (end <= start) return "";
    return target[start..end];
}

fn requestPathWithoutLeadingSlashes(request_path: []const u8) []const u8 {
    var start: usize = 0;
    while (start < request_path.len and request_path[start] == '/') : (start += 1) {}
    return request_path[start..];
}

fn buildUpstreamUrl(allocator: std.mem.Allocator, target: []const u8, request_path: []const u8, preserve_base_path: bool) ![]u8 {
    const origin = target[0..requestUrlOriginLen(target)];
    if (!preserve_base_path) {
        if (request_path.len > 0 and request_path[0] == '/') {
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ origin, request_path });
        }
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ origin, request_path });
    }

    const base_path = targetBasePath(target);
    var relative_path = requestPathWithoutLeadingSlashes(request_path);
    if (std.mem.endsWith(u8, base_path, "/v1") and std.mem.startsWith(u8, relative_path, "v1/")) {
        relative_path = relative_path["v1/".len..];
    }
    if (relative_path.len == 0) {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ origin, base_path });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}/{s}", .{ origin, base_path, relative_path });
}

fn addRequestHeader(request: *HttpRequest, key: []const u8, val: []const u8) !void {
    const name = try request.allocator.dupe(u8, key);
    errdefer request.allocator.free(name);
    const value = try request.allocator.dupe(u8, val);
    errdefer request.allocator.free(value);
    try request.headers.append(.{ .name = name, .value = value });
}

fn cloneRequestForAsync(src: *HttpRequest) !*HttpRequest {
    const allocator = src.allocator;
    const cloned = try allocator.create(HttpRequest);
    errdefer allocator.destroy(cloned);
    cloned.* = .{
        .allocator = allocator,
        .client = src.client,
        .method = src.method,
        .url = try allocator.dupe(u8, src.url),
        .headers = std.array_list.Managed(std.http.Header).init(allocator),
        .timeout_ms = src.timeout_ms,
        .max_response_bytes = src.max_response_bytes,
        .retains_client = true,
    };
    cloned.client.retain();
    errdefer cloned.client.release();
    errdefer allocator.free(cloned.url);
    errdefer cloned.headers.deinit();

    for (src.headers.items) |header| {
        const name = try allocator.dupe(u8, header.name);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, header.value);
        errdefer allocator.free(value);
        try cloned.headers.append(.{ .name = name, .value = value });
    }
    cloned.body = if (src.body) |body| try allocator.dupe(u8, body) else null;
    return cloned;
}

pub const HttpResponse = struct {
    allocator: std.mem.Allocator,
    status: u16,
    headers: []std.http.Header,
    body: []u8,

    pub fn deinit(self: *HttpResponse) void {
        for (self.headers) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.allocator.free(self.headers);
        if (self.body.len != 0) self.allocator.free(self.body);
        self.headers = &.{};
        self.body = &.{};
        self.status = 0;
        self.allocator.destroy(self);
    }
};

pub const HttpBodyReader = struct {
    allocator: std.mem.Allocator,
    body: []u8,
    cursor: usize = 0,

    fn init(allocator: std.mem.Allocator, body: []u8) !*HttpBodyReader {
        const self = try allocator.create(HttpBodyReader);
        self.* = .{
            .allocator = allocator,
            .body = body,
            .cursor = 0,
        };
        return self;
    }

    fn deinit(self: *HttpBodyReader) void {
        self.allocator.destroy(self);
    }
};

pub const HttpRequestAsyncOp = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    thread: ?std.Thread = null,
    mutex: std.atomic.Mutex = .unlocked,
    done: bool = false,
    response: ?*HttpResponse = null,

    fn init(request: *HttpRequest) !*HttpRequestAsyncOp {
        const cloned_request = try cloneRequestForAsync(request);
        errdefer cloned_request.deinit();
        const self = try cloned_request.allocator.create(HttpRequestAsyncOp);
        errdefer cloned_request.allocator.destroy(self);
        self.* = .{
            .allocator = cloned_request.allocator,
            .request = cloned_request,
        };
        if (comptime builtin.cpu.arch.isWasm()) {
            HttpRequestAsyncOp.run(self);
        } else {
            self.thread = try std.Thread.spawn(.{}, HttpRequestAsyncOp.run, .{self});
        }
        return self;
    }

    fn run(self: *HttpRequestAsyncOp) void {
        const response = httpRequestExec(self.request) catch null;
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        self.response = response;
        self.done = true;
        self.mutex.unlock();
    }

    fn poll(self: *HttpRequestAsyncOp) bool {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        return self.done;
    }

    fn takeResponse(self: *HttpRequestAsyncOp) ?*HttpResponse {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (!self.done) return null;
        const response = self.response orelse return null;
        self.response = null;
        return response;
    }

    fn deinit(self: *HttpRequestAsyncOp) void {
        if (self.thread) |thread| thread.join();
        if (self.response) |response| response.deinit();
        self.request.deinit();
        self.allocator.destroy(self);
    }
};

fn mapStatus(status: std.http.Status) u16 {
    return @intCast(@intFromEnum(status));
}

fn endsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - needle.len ..], needle);
}

/// curl-compatible no_proxy matching: "*" matches all; ".example.com" or
/// "example.com" match the domain and subdomains; "host:port" restricts by port.
fn hostMatchesNoProxy(host: []const u8, port: u16, no_proxy: []const u8) bool {
    var h = host;
    if (h.len >= 2 and h[0] == '[' and h[h.len - 1] == ']') h = h[1 .. h.len - 1];
    var it = std.mem.splitScalar(u8, no_proxy, ',');
    while (it.next()) |raw_entry| {
        const entry = std.mem.trim(u8, raw_entry, " \t");
        if (entry.len == 0) continue;
        if (std.mem.eql(u8, entry, "*")) return true;
        var e = entry;
        // Strip [brackets] from IPv6 entries, honor optional :port suffix.
        if (e.len >= 2 and e[0] == '[') {
            if (std.mem.indexOfScalar(u8, e, ']')) |end| {
                const rest = e[end + 1 ..];
                e = e[1..end];
                if (rest.len > 1 and rest[0] == ':') {
                    const p = std.fmt.parseInt(u16, rest[1..], 10) catch continue;
                    if (p != port) continue;
                } else if (rest.len != 0) {
                    continue;
                }
            } else continue;
        }
        var entry_host = e;
        if (std.mem.count(u8, e, ":") == 1) {
            const ci = std.mem.lastIndexOfScalar(u8, e, ':').?;
            entry_host = e[0..ci];
            const p = std.fmt.parseInt(u16, e[ci + 1 ..], 10) catch continue;
            if (p != port) continue;
        }
        if (entry_host.len > 0 and entry_host[0] == '.') {
            const suffix = entry_host[1..];
            if (std.ascii.eqlIgnoreCase(h, suffix)) return true;
            if (h.len > suffix.len and endsWithIgnoreCase(h, suffix) and h[h.len - suffix.len - 1] == '.') return true;
        } else {
            if (std.ascii.eqlIgnoreCase(h, entry_host)) return true;
            if (h.len > entry_host.len and endsWithIgnoreCase(h, entry_host) and h[h.len - entry_host.len - 1] == '.') return true;
        }
    }
    return false;
}

/// Zig 0.14.1's initDefaultProxies ignores no_proxy/NO_PROXY, so honor it here
/// by temporarily clearing the client proxies for matching hosts.
fn maybeBypassProxy(req: *HttpRequest, uri: std.Uri) void {
    const host_component = uri.host orelse return;
    const host: []const u8 = switch (host_component) {
        .raw => |r| r,
        .percent_encoded => |p| p,
    };
    const no_proxy = sio.getEnvVarOwned(req.allocator, "no_proxy") catch
        (sio.getEnvVarOwned(req.allocator, "NO_PROXY") catch return);
    defer req.allocator.free(no_proxy);
    const port: u16 = uri.port orelse
        if (std.mem.eql(u8, uri.scheme, "https")) 443
        else if (std.mem.eql(u8, uri.scheme, "http")) 80
        else 0;
    if (hostMatchesNoProxy(host, port, no_proxy)) {
        req.client.client.http_proxy = null;
        req.client.client.https_proxy = null;
    } else {
    }
}

fn cloneResponseHeaders(allocator: std.mem.Allocator, response: std.http.Client.Response) ![]std.http.Header {
    var headers = std.array_list.Managed(std.http.Header).init(allocator);
    errdefer {
        for (headers.items) |header| {
            allocator.free(header.name);
            allocator.free(header.value);
        }
        headers.deinit();
    }

    var it = response.head.iterateHeaders();
    while (it.next()) |header| {
        try headers.append(.{
            .name = try allocator.dupe(u8, header.name),
            .value = try allocator.dupe(u8, header.value),
        });
    }
    return headers.toOwnedSlice();
}

fn makeStatusResponse(allocator: std.mem.Allocator, status: u16, headers: []std.http.Header, body: []u8) !*HttpResponse {
    const resp = try allocator.create(HttpResponse);
    errdefer allocator.destroy(resp);
    resp.* = .{
        .allocator = allocator,
        .status = status,
        .headers = headers,
        .body = body,
    };
    return resp;
}


/// HTTP POST via curl subprocess (most stable for proxy+TLS).
/// Uses system curl which handles proxy auth, TLS, chunked correctly.
fn curlHttpPost(allocator: std.mem.Allocator, req: *HttpRequest) !*HttpResponse {
    // Build curl command.
    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    try args.append("curl");
    try args.append("-s");
    try args.append("-S");
    try args.append("--max-time");
    try args.append("30");
    try args.append("-X");
    try args.append("POST");
    // URL
    const url = try std.fmt.allocPrint(allocator, "{s}", .{req.url});
    defer allocator.free(url);
    try args.append(url);
    // Headers. Formatted strings must live until Child.run has
    // consumed argv, so arg_strings owns them at function scope (a
    // defer inside the loop freed each string per-iteration).
    var arg_strings = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (arg_strings.items) |str| allocator.free(str);
        arg_strings.deinit();
    }
    for (req.headers.items) |h| {
        const hs = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ h.name, h.value });
        try arg_strings.append(hs);
        try args.append("-H");
        try args.append(hs);
    }
    // Body
    if (req.body) |body| {
        try args.append("--data-binary");
        // Write body to temp file to avoid arg length limits.
        const tmp_path = "/tmp/curl_body_tmp.json";
        const f = try sio.cwd().createFile(tmp_path, .{});
        try f.writeAll(body);
        f.close();
        const data_arg = try std.fmt.allocPrint(allocator, "@{s}", .{tmp_path});
        try arg_strings.append(data_arg);
        try args.append(data_arg);
    }
    // Capture response body and status code.
    try args.append("-w");
    try args.append("\n%{http_code}");
    try args.append("-o");
    try args.append("-"); // stdout

    const result = try sio.Child.run(.{
        .allocator = allocator,
        .argv = args.items,
        .max_output_bytes = 16 * 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Clean up temp file.
    sio.cwd().deleteFile("/tmp/curl_body_tmp.json") catch {};

    switch (result.term) {
        .exited => |code| if (code != 0) return error.CurlFailed,
        else => return error.CurlFailed,
    }

    // Parse output: body + "\n" + status_code
    const out = result.stdout;
    const last_nl = std.mem.lastIndexOfScalar(u8, out, '\n') orelse return error.CurlBadOutput;
    const code_str = std.mem.trim(u8, out[last_nl + 1 ..], " \r\n");
    const status = std.fmt.parseInt(u16, code_str, 10) catch return error.CurlBadOutput;
    const body = out[0..last_nl];

    const headers = try allocator.alloc(std.http.Header, 0);
    const body_copy = try allocator.dupe(u8, body);
    return try makeStatusResponse(allocator, status, headers, body_copy);
}


/// Parse Retry-After header value in delta-seconds. Returns 0 if absent or invalid.
fn getRetryAfterSecs(headers: []std.http.Header) u64 {
    for (headers) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "retry-after")) {
            const v = std.mem.trim(u8, h.value, " \t");
            if (std.fmt.parseInt(u64, v, 10)) |secs| {
                return @min(secs, 300); // Cap at 5 minutes.
            } else |_| {}
            return 0;
        }
    }
    return 0;
}

/// Retryable: 429 Too Many Requests, and 5xx server errors.
/// Other 4xx (400, 401, 403, 404, ...) are not retried.
fn isRetryableStatus(status: u16) bool {
    return status == 429 or (status >= 500 and status < 600);
}

/// Exponential backoff in seconds: 1, 2, 4, 8, 16 for attempts 0..4.
fn backoffSecs(attempt: u32) u64 {
    return @as(u64, 1) << @intCast(@min(attempt, 4));
}

/// Single attempt without retry. See httpRequestExec for the retry wrapper.
fn httpRequestExecOnce(req: *HttpRequest) !*HttpResponse {
    const uri = try std.Uri.parse(req.url);
    while (!req.client.request_mutex.tryLock()) std.atomic.spinLoopHint();
    defer req.client.request_mutex.unlock();
    // Save proxies; maybeBypassProxy may clear them for no_proxy hosts.
    const saved_http_proxy = req.client.client.http_proxy;
    const saved_https_proxy = req.client.client.https_proxy;
    defer {
        req.client.client.http_proxy = saved_http_proxy;
        req.client.client.https_proxy = saved_https_proxy;
    }
    maybeBypassProxy(req, uri);
    // Disable response compression: Zig 0.14.1's gzip/deflate decompression
    // fails on some servers (DecompressionFailure). Identity is always safe.
    {
        const ae_name = try req.allocator.dupe(u8, "Accept-Encoding");
        errdefer req.allocator.free(ae_name);
        const ae_val = try req.allocator.dupe(u8, "identity");
        errdefer req.allocator.free(ae_val);
        try req.headers.append(.{ .name = ae_name, .value = ae_val });
    }
    // NOTE(Zig 0.17): proxy CONNECT tunnels + TLS are handled natively by
    // std.http.Client (see HttpClient.init -> initDefaultProxies); the manual
    // tunnel path was removed.
    var redirect_buf: [16 * 1024]u8 = undefined;
    const parts = try splitStdHeaders(req.allocator, req.headers.items);
    defer req.allocator.free(parts.extra);
    var request = try req.client.client.request(req.method, uri, .{
        .keep_alive = false,
        .redirect_behavior = .unhandled,
        .headers = parts.headers,
        .extra_headers = parts.extra,
    });
    defer request.deinit();
    if (req.body) |body| {
        const owned_body = try req.allocator.dupe(u8, body);
        defer req.allocator.free(owned_body);
        try request.sendBodyComplete(owned_body);
    } else {
        try request.sendBodiless();
    }
    var response = try request.receiveHead(&redirect_buf);
    const headers = try cloneResponseHeaders(req.allocator, response);
    errdefer {
        for (headers) |header| {
            req.allocator.free(header.name);
            req.allocator.free(header.value);
        }
        req.allocator.free(headers);
    }
    var body = std.array_list.Managed(u8).init(req.allocator);
    errdefer body.deinit();
    // D6 (same defect as executeRequestV2): skip the read loop
    // when the response has no body by definition (HEAD/TRACE);
    // Response.reader() would hand out the shared read-only
    // Io.Reader.ending singleton and readSliceShort's seek
    // write through it segfaults in zig-cc/LLD-linked binaries.
    if (req.method.responseHasBody()) {
        var transfer_buf: [8192]u8 = undefined;
        var body_reader = response.reader(&transfer_buf);
        var read_buf: [8192]u8 = undefined;
        var total: usize = 0;
        while (true) {
            const n = try body_reader.readSliceShort(&read_buf);
            if (n == 0) break;
            total += n;
            if (total > 16 * 1024 * 1024) return error.StreamTooLong;
            try body.appendSlice(read_buf[0..n]);
        }
    }
    return try makeStatusResponse(req.allocator, mapStatus(response.head.status), headers, try body.toOwnedSlice());
}

/// Retry wrapper: up to 5 retries (6 attempts total) on 429 / 5xx /
/// transient network errors. Exponential backoff (1,2,4,8,16s),
/// respecting Retry-After when present. Covers first and follow-up requests.
fn httpRequestExec(req: *HttpRequest) !*HttpResponse {
    const max_retries: u32 = 5;
    var attempt: u32 = 0;
    while (true) {
        const resp = httpRequestExecOnce(req) catch |err| {
            if (attempt < max_retries) {
                sio.io().sleep(.fromNanoseconds(backoffSecs(attempt) * std.time.ns_per_s), .awake) catch {};
                attempt += 1;
                continue;
            }
            return err;
        };
        if (!isRetryableStatus(resp.status) or attempt >= max_retries) {
            return resp;
        }
        const wait_secs = @max(backoffSecs(attempt), getRetryAfterSecs(resp.headers));
        resp.deinit();
        sio.io().sleep(.fromNanoseconds(wait_secs * std.time.ns_per_s), .awake) catch {};
        attempt += 1;
    }
}

fn readAllIntoList(reader: anytype, allocator: std.mem.Allocator) !std.array_list.Managed(u8) {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    var buf: [1024]u8 = undefined;
    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;
        try out.appendSlice(buf[0..n]);
    }
    return out;
}

pub export fn sa_http_client_new(use_tls: u8, out_client: ?*?*anyopaque) u32 {
    const slot = out_client orelse return @intFromEnum(AbiStatus.failed);
    const client = HttpClient.init(clientAllocator(), .{ .use_tls = use_tls }) catch return @intFromEnum(AbiStatus.failed);
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

const WebSocketOpcode = enum(u8) {
    continuation = 0,
    text = 1,
    binary = 2,
    connection_close = 8,
    ping = 9,
    pong = 10,
};

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

    fn isClient(self: *WebSocketHandle) bool {
        _ = self;
        return true;
    }

    fn rawRead(self: *WebSocketHandle, buffer: []u8) !usize {
        if (self.tls_client) |t| {
            return try t.reader.readSliceShort(buffer);
        }
        return try self.frame_reader.interface.readSliceShort(buffer);
    }

    fn rawWrite(self: *WebSocketHandle, bytes: []const u8) !void {
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

    fn writeExact(self: *WebSocketHandle, bytes: []const u8) bool {
        self.rawWrite(bytes) catch return false;
        return true;
    }

    fn deinit(self: *WebSocketHandle) void {
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

fn findRawHeader(head: []const u8, key: []const u8) ?[]const u8 {
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

// ============ SSE streaming POST ============
// Spawns curl in the background writing the response body to a temp file
// as it arrives (-N/--no-buffer). The caller polls and reads incrementally.

var sse_stream_counter = std.atomic.Value(u32).init(0);

const SseStream = struct {
    allocator: std.mem.Allocator,
    child: sio.Child,
    body_path: []u8,
    header_path: []u8,
    req_body_path: []u8,
    read_offset: u64,
    http_status: u16,
    finished: bool,
    failed: bool,
};

fn sseTempPath(allocator: std.mem.Allocator, suffix: []const u8) ![]u8 {
    const n = sse_stream_counter.fetchAdd(1, .monotonic);
    const pid: i32 = if (comptime builtin.cpu.arch.isWasm()) 0 else std.os.linux.getpid();
    return std.fmt.allocPrint(allocator, "/tmp/scodex_sse_{d}_{d}.{s}", .{ pid, n, suffix });
}

fn sseParseStatus(header_path: []const u8) u16 {
    const f = sio.cwd().openFile(header_path, .{}) catch return 0;
    defer f.close();
    var buf: [256]u8 = undefined;
    const n = f.read(&buf) catch return 0;
    // First line: "HTTP/1.1 200 OK"
    const line_end = std.mem.indexOfScalar(u8, buf[0..n], '\n') orelse n;
    const line = buf[0..line_end];
    // Find first space, then parse the number after it.
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return 0;
    const rest = std.mem.trimStart(u8, line[sp + 1 ..], " ");
    const sp2 = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    return std.fmt.parseInt(u16, rest[0..sp2], 10) catch 0;
}

/// Parse Retry-After from SSE header file. Returns 0 if absent/invalid. Capped at 300s.
fn sseParseRetryAfter(header_path: []const u8) u64 {
    const f = sio.cwd().openFile(header_path, .{}) catch return 0;
    defer f.close();
    var buf: [4096]u8 = undefined;
    const n = f.read(&buf) catch return 0;
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len > 12 and std.ascii.eqlIgnoreCase(trimmed[0..12], "retry-after:")) {
            const v = std.mem.trim(u8, trimmed[12..], " \t");
            if (std.fmt.parseInt(u64, v, 10)) |secs| {
                return @min(secs, 300);
            } else |_| {}
        }
    }
    return 0;
}

// Blocking reap of an SSE curl child by its own pid. Do NOT use
// std.process.Child.wait() here: sseCheckFinished polls with a
// raw waitpid(pid, WNOHANG) and may already have reaped the
// child, after which Child.wait() blocks in the Io reaper's
// waitpid(-1) until some unrelated child of the process exits
// (deadlock when a long-lived child, e.g. an MCP server, is
// alive). One mechanism, one pid: this wait.
fn sseWaitSioChild(child: *sio.Child) void {
    if (builtin.os.tag != .linux) {
        _ = child.wait() catch {};
        return;
    }
    const inner = &(child.inner orelse return);
    const pid = inner.id orelse return;
    var status: i32 = 0;
    _ = std.os.linux.waitpid(pid, &status, 0);
}

fn sseCheckFinished(s: *SseStream) void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        sseCheckFinishedNative(s);
    }
}

fn sseCheckFinishedNative(s: *SseStream) void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return;
    } else {
        sseCheckFinishedNativeNative(s);
    }
}

fn sseCheckFinishedNativeNative(s: *SseStream) void {
    if (s.finished) return;
    // NOTE(Zig 0.17): `std.posix.waitpid` was removed; poll via raw Linux
    // wait4 with WNOHANG (curl SSE path is Linux-only in practice).
    if (builtin.os.tag != .linux) return;
    const inner = &(s.child.inner orelse return);
    const pid = inner.id orelse return;
    var status: i32 = 0;
    const rc = std.os.linux.waitpid(pid, &status, std.os.linux.W.NOHANG);
    if (rc == 0) return; // still running
    s.finished = true;
    if (@as(isize, @bitCast(rc)) < 0) {
        s.failed = true; // wait error (e.g. no child)
    } else {
        const st: u32 = @bitCast(status);
        if (std.os.linux.W.IFEXITED(st)) {
            s.failed = std.os.linux.W.EXITSTATUS(st) != 0;
        } else {
            s.failed = true; // signaled or stopped
        }
    }
    s.http_status = sseParseStatus(s.header_path);
}

pub export fn sa_http_client_sse_post(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    out_handle: ?*?*anyopaque,
) u32 {
    const allocator = std.heap.page_allocator;
    const slot = out_handle orelse return 1;
    const url = if (url_ptr) |p| p[0..@intCast(url_len)] else return 1;

    const body_path = sseTempPath(allocator, "body") catch return 1;
    errdefer allocator.free(body_path);
    const header_path = sseTempPath(allocator, "headers") catch return 1;
    errdefer allocator.free(header_path);
    const req_body_path = sseTempPath(allocator, "req") catch return 1;
    errdefer allocator.free(req_body_path);

    // Write request body to temp file.
    {
        const f = sio.cwd().createFile(req_body_path, .{}) catch return 1;
        defer f.close();
        if (body_ptr) |p| {
            f.writeAll(p[0..@intCast(body_len)]) catch return 1;
        }
    }

    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    args.append("curl") catch return 1;
    args.append("-s") catch return 1;
    args.append("-S") catch return 1;
    args.append("-N") catch return 1; // no buffering: stream as it arrives
    args.append("--max-time") catch return 1;
    args.append("300") catch return 1;
    args.append("-X") catch return 1;
    args.append("POST") catch return 1;
    args.append(url) catch return 1;
    // Auth header. The string must outlive this block: a block-scoped
    // defer here freed it before Child.spawn consumed argv
    // (use-after-free, caught by the std loopback tests).
    var auth_buf: ?[]u8 = null;
    defer if (auth_buf) |a| allocator.free(a);
    if (key_ptr) |kp| {
        auth_buf = std.fmt.allocPrint(allocator, "Authorization: Bearer {s}", .{kp[0..@intCast(key_len)]}) catch return 1;
        args.append("-H") catch return 1;
        args.append(auth_buf.?) catch return 1;
    }
    args.append("-H") catch return 1;
    args.append("Content-Type: application/json") catch return 1;
    args.append("-H") catch return 1;
    args.append("Accept: text/event-stream") catch return 1;
    const data_arg = std.fmt.allocPrint(allocator, "@{s}", .{req_body_path}) catch return 1;
    defer allocator.free(data_arg);
    args.append("--data-binary") catch return 1;
    args.append(data_arg) catch return 1;
    args.append("-D") catch return 1;
    args.append(header_path) catch return 1;
    args.append("-o") catch return 1;
    args.append(body_path) catch return 1;

    var child = sio.Child.init(args.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return 1;

    const s = allocator.create(SseStream) catch {
        child.kill() catch {};
        sseWaitSioChild(&child);
        return 1;
    };
    s.* = .{
        .allocator = allocator,
        .child = child,
        .body_path = body_path,
        .header_path = header_path,
        .req_body_path = req_body_path,
        .read_offset = 0,
        .http_status = 0,
        .finished = false,
        .failed = false,
    };
    slot.* = @ptrCast(s);
    return 0;
}

pub export fn sa_http_client_sse_read(
    handle: ?*anyopaque,
    buf_ptr: ?[*]u8, buf_cap: u64,
    out_len: ?*u64,
) u32 {
    const s = @as(*SseStream, @ptrCast(@alignCast(handle orelse return 1)));
    const out = out_len orelse return 1;
    const buf = buf_ptr orelse return 1;
    out.* = 0;
    if (buf_cap == 0) return 0;

    const f = sio.cwd().openFile(s.body_path, .{}) catch return 0;
    defer f.close();
    const st = f.stat() catch return 0;
    if (st.size <= s.read_offset) return 0;
    f.seekTo(s.read_offset) catch return 0;
    const want: usize = @intCast(@min(buf_cap, st.size - s.read_offset));
    const n = f.read(buf[0..want]) catch return 0;
    s.read_offset += n;
    out.* = n;
    return 0;
}

// out_done: 0 = running, 1 = finished ok, 2 = finished with error
pub export fn sa_http_client_sse_poll(handle: ?*anyopaque, out_done: ?*u8) u32 {
    const s = @as(*SseStream, @ptrCast(@alignCast(handle orelse return 1)));
    const out = out_done orelse return 1;
    sseCheckFinished(s);
    // Also try to parse status from headers if not yet known.
    if (s.http_status == 0) {
        s.http_status = sseParseStatus(s.header_path);
    }
    out.* = if (!s.finished) 0 else if (s.failed) 2 else 1;
    return 0;
}

pub export fn sa_http_client_sse_status(handle: ?*anyopaque) u16 {
    const s = @as(*SseStream, @ptrCast(@alignCast(handle orelse return 0)));
    if (s.http_status == 0) {
        s.http_status = sseParseStatus(s.header_path);
    }
    return s.http_status;
}

pub export fn sa_http_client_sse_free(handle: ?*anyopaque) u32 {
    const s = @as(*SseStream, @ptrCast(@alignCast(handle orelse return 1)));
    if (!s.finished) {
        _ = s.child.kill() catch {};
        sseWaitSioChild(&s.child);
    }
    sio.cwd().deleteFile(s.body_path) catch {};
    sio.cwd().deleteFile(s.header_path) catch {};
    sio.cwd().deleteFile(s.req_body_path) catch {};
    s.allocator.free(s.body_path);
    s.allocator.free(s.header_path);
    s.allocator.free(s.req_body_path);
    s.allocator.destroy(s);
    return 0;
}

// High-level SSE turn: POST, stream, parse events, print deltas live,
// accumulate text and tool calls. Bypasses SLA compiler limitations.
// Returns: 0=ok (text), 1=ok (tool calls), 2=error.
// Out params: text (ptr/len), calls_json (ptr/len, JSON array of {call_id,name,args}).
// Caller must free returned buffers via sa_http_client_sse_turn_free.
pub export fn sa_http_client_sse_turn(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    api_mode: u64,
    out_text_ptr: ?*?[*]u8, out_text_len: ?*u64,
    out_calls_ptr: ?*?[*]u8, out_calls_len: ?*u64,
) u32 {
    return sseTurnImpl(url_ptr, url_len, body_ptr, body_len, key_ptr, key_len, api_mode, out_text_ptr, out_text_len, out_calls_ptr, out_calls_len, null, null, null, null);
}

// sse_turn plus the channel-reported usage object: out_usage
// receives the raw JSON span of the last top-level "usage" value
// in the stream (for example
// {"prompt_tokens":N,"completion_tokens":N,"total_tokens":N}).
// It stays empty when the channel reports no usage; callers must
// treat absence as "not reported", never as zero. Free with
// sa_http_client_sse_turn_free like the other outs.
pub export fn sa_http_client_sse_turn_ex(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    api_mode: u64,
    out_text_ptr: ?*?[*]u8, out_text_len: ?*u64,
    out_calls_ptr: ?*?[*]u8, out_calls_len: ?*u64,
    out_usage_ptr: ?*?[*]u8, out_usage_len: ?*u64,
    out_reasoning_ptr: ?*?[*]u8, out_reasoning_len: ?*u64,
) u32 {
    return sseTurnImpl(url_ptr, url_len, body_ptr, body_len, key_ptr, key_len, api_mode, out_text_ptr, out_text_len, out_calls_ptr, out_calls_len, out_usage_ptr, out_usage_len, out_reasoning_ptr, out_reasoning_len);
}

fn sseTurnImpl(
    url_ptr: ?[*]const u8, url_len: u64,
    body_ptr: ?[*]const u8, body_len: u64,
    key_ptr: ?[*]const u8, key_len: u64,
    api_mode: u64,
    out_text_ptr: ?*?[*]u8, out_text_len: ?*u64,
    out_calls_ptr: ?*?[*]u8, out_calls_len: ?*u64,
    out_usage_ptr: ?*?[*]u8, out_usage_len: ?*u64,
    out_reasoning_ptr: ?*?[*]u8, out_reasoning_len: ?*u64,
) u32 {
    const otp = out_text_ptr orelse return 2;
    const otl = out_text_len orelse return 2;
    const ocp = out_calls_ptr orelse return 2;
    const ocl = out_calls_len orelse return 2;
    otp.* = null;
    otl.* = 0;
    ocp.* = null;
    ocl.* = 0;
    if (out_usage_ptr) |oup| {
        if (out_usage_len) |oul| {
            oup.* = null;
            oul.* = 0;
        }
    }
    if (out_reasoning_ptr) |orp| {
        if (out_reasoning_len) |orl| {
            orp.* = null;
            orl.* = 0;
        }
    }

    // Retry wrapper: up to 5 retries (6 attempts) on 429/5xx/transient network errors.
    // Exponential backoff 1/2/4/8/16s, respecting Retry-After (capped at 5min).
    // Once streaming starts (200 OK), no retry - mid-stream failures return error.
    var attempt: u32 = 0;
    while (true) {
        var handle: ?*anyopaque = null;
        if (sa_http_client_sse_post(url_ptr, url_len, body_ptr, body_len, key_ptr, key_len, &handle) != 0 or handle == null) {
            if (handle) |h| _ = sa_http_client_sse_free(h);
            if (attempt < 5) {
                sio.io().sleep(.fromNanoseconds(backoffSecs(attempt) * std.time.ns_per_s), .awake) catch {};
                attempt += 1;
                continue;
            }
            return 2;
        }
        // Wait for HTTP status. The poll cap must tolerate slow
        // time-to-first-byte upstreams: a grok tool-call request was
        // measured at 20s to first byte, over the old 200*50ms = 10s
        // cap, which surfaced as a spurious upstream error. 3600*50ms
        // = 180s; a dead transfer still ends the wait via poll done.
        var status: u16 = 0;
        var waits: u32 = 0;
        while (waits < 3600) : (waits += 1) {
            const st = sa_http_client_sse_status(handle);
            if (st != 0) {
                status = st;
                break;
            }
            var done: u8 = 0;
            _ = sa_http_client_sse_poll(handle, &done);
            if (done != 0) break;
            sio.io().sleep(.fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
        }
        if (status == 200) {
            // Success: stream to completion. sseTurnStream does not free handle;
            // we free it here via defer.
            defer _ = sa_http_client_sse_free(handle);
            return sseTurnStream(handle, api_mode, otp, otl, ocp, ocl, out_usage_ptr, out_usage_len, out_reasoning_ptr, out_reasoning_len);
        }
        // Non-200: check if retryable.
        const s = @as(*SseStream, @ptrCast(@alignCast(handle.?)));
        const retry_after = sseParseRetryAfter(s.header_path);
        _ = sa_http_client_sse_free(handle);
        if (status != 0 and isRetryableStatus(status) and attempt < 5) {
            const wait_secs = @max(backoffSecs(attempt), retry_after);
            sio.io().sleep(.fromNanoseconds(wait_secs * std.time.ns_per_s), .awake) catch {};
            attempt += 1;
            continue;
        }
        return 2;
    }
}

/// Streaming part: assumes handle has 200 OK status. Reads SSE stream to completion.
fn sseTurnStream(
    handle: ?*anyopaque,
    api_mode: u64,
    otp: *?[*]u8, otl: *u64,
    ocp: *?[*]u8, ocl: *u64,
    oup_opt: ?*?[*]u8, oul_opt: ?*u64,
    orp_opt: ?*?[*]u8, orl_opt: ?*u64,
) u32 {
    const allocator = std.heap.page_allocator;
    const s = @as(*SseStream, @ptrCast(@alignCast(handle.?)));

    var text = std.array_list.Managed(u8).init(allocator);
    defer text.deinit();
    var calls = std.array_list.Managed(SseCall).init(allocator);
    defer {
        for (calls.items) |*c| {
            if (c.call_id.len > 0) allocator.free(c.call_id);
            if (c.name.len > 0) allocator.free(c.name);
            if (c.args.len > 0) allocator.free(c.args);
            if (c.key.len > 0) allocator.free(c.key);
        }
        calls.deinit();
    }
    var active = std.array_list.Managed(SseCall).init(allocator);
    defer {
        // Free any remaining active calls.
        for (active.items) |*ac| {
            if (ac.call_id.len > 0) allocator.free(ac.call_id);
            if (ac.name.len > 0) allocator.free(ac.name);
            if (ac.args.len > 0) allocator.free(ac.args);
            if (ac.key.len > 0) allocator.free(ac.key);
        }
        active.deinit();
    }
    var stream_done = false;
    var usage = std.array_list.Managed(u8).init(allocator);
    defer usage.deinit();
    var reasoning = std.array_list.Managed(u8).init(allocator);
    defer reasoning.deinit();

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();
    var processed_offset: usize = 0;

    var stdout_buf: [8192]u8 = undefined;
    var stdout_stream = std.Io.File.stdout().writerStreaming(sio.io(), &stdout_buf);
    const stdout = &stdout_stream.interface;
    defer stdout_stream.interface.flush() catch {};

    // Main read loop.
    while (!stream_done) {
        // Read new bytes from body file.
        const new_data = sseReadNew(s, &processed_offset) catch {
            return 2;
        };
        if (new_data.len > 0) {
            buf.appendSlice(new_data) catch return 2;
            allocator.free(new_data);
            // Extract complete events.
            while (true) {
                const delim = sseFindEventEnd(buf.items) orelse break;
                const ev = buf.items[0..delim.pos];
                // Parse event data.
                if (sseParseEventData(allocator, ev)) |data| {
                    defer if (data.owned) allocator.free(data.payload);
                    if (data.is_done) {
                        stream_done = true;
                    } else if (data.payload.len > 0) {
                        sseCaptureUsage(data.payload, &usage);
                        sseHandleEvent(allocator, data.payload, api_mode, &text, &reasoning, &calls, &active, &stream_done, stdout) catch {};
                    }
                }
                // Remove processed event (+ delimiter length).
                const remove_len = delim.pos + delim.len;
                if (remove_len < buf.items.len) {
                    std.mem.copyForwards(u8, buf.items[0..], buf.items[remove_len..]);
                }
                buf.shrinkRetainingCapacity(buf.items.len - remove_len);
                if (stream_done) break;
            }
        }
        if (stream_done) break;
        var done: u8 = 0;
        _ = sa_http_client_sse_poll(handle, &done);
        if (done == 1) {
            // Process trailing.
            if (buf.items.len > 0) {
                if (sseParseEventData(allocator, buf.items)) |data| {
                    defer if (data.owned) allocator.free(data.payload);
                    if (!data.is_done and data.payload.len > 0) {
                        sseCaptureUsage(data.payload, &usage);
                        sseHandleEvent(allocator, data.payload, api_mode, &text, &reasoning, &calls, &active, &stream_done, stdout) catch {};
                    }
                }
            }
            break;
        } else if (done == 2) {
            return 2;
        }
        if (new_data.len == 0) {
            sio.io().sleep(.fromNanoseconds(20 * std.time.ns_per_ms), .awake) catch {};
        }
    }

    // Finalize all active calls.
    sseFinalizeActive(allocator, &active, &calls) catch return 2;

    // Print newline after stream.
    stdout.writeAll("\n") catch {};

    // Build calls JSON first (so text isn't leaked on failure).
    var calls_json = std.array_list.Managed(u8).init(allocator);
    defer calls_json.deinit();
    calls_json.appendSlice("[") catch return 2;
    for (calls.items, 0..) |c, i| {
        if (i > 0) calls_json.appendSlice(",") catch return 2;
        calls_json.appendSlice("{\"call_id\":\"") catch return 2;
        sseJsonEscape(&calls_json, c.call_id) catch return 2;
        calls_json.appendSlice("\",\"name\":\"") catch return 2;
        sseJsonEscape(&calls_json, c.name) catch return 2;
        calls_json.appendSlice("\",\"args\":\"") catch return 2;
        sseJsonEscape(&calls_json, c.args) catch return 2;
        calls_json.appendSlice("\"}") catch return 2;
    }
    calls_json.appendSlice("]") catch return 2;
    const cj_slice = calls_json.toOwnedSlice() catch return 2;
    errdefer allocator.free(cj_slice);

    // Return text.
    const text_slice = text.toOwnedSlice() catch {
        allocator.free(cj_slice);
        return 2;
    };

    const usage_slice = usage.toOwnedSlice() catch {
        allocator.free(cj_slice);
        allocator.free(text_slice);
        return 2;
    };
    errdefer allocator.free(usage_slice);

    // All succeeded; assign outputs.
    otp.* = text_slice.ptr;
    otl.* = text_slice.len;
    ocp.* = cj_slice.ptr;
    ocl.* = cj_slice.len;
    if (oup_opt) |oup| {
        if (oul_opt) |oul| {
            oup.* = usage_slice.ptr;
            oul.* = usage_slice.len;
        } else {
            allocator.free(usage_slice);
        }
    } else {
        allocator.free(usage_slice);
    }
    const reasoning_slice = reasoning.toOwnedSlice() catch {
        allocator.free(cj_slice);
        allocator.free(text_slice);
        return 2;
    };
    if (orp_opt) |orp| {
        if (orl_opt) |orl| {
            orp.* = reasoning_slice.ptr;
            orl.* = reasoning_slice.len;
        } else {
            allocator.free(reasoning_slice);
        }
    } else {
        allocator.free(reasoning_slice);
    }

    return if (calls.items.len > 0) 1 else 0;
}

const SseCall = struct {
    call_id: []u8,
    name: []u8,
    args: []u8,
    // For lookup during streaming: responses uses call_id, chat uses index.
    // We store the raw key string for matching.
    key: []u8,
};

const SseEventData = struct {
    payload: []const u8,
    is_done: bool,
    owned: bool, // if true, caller must free payload
};

fn sseReadNew(s: *SseStream, offset: *usize) ![]u8 {
    const f = sio.cwd().openFile(s.body_path, .{}) catch |err| {
        // File not yet created by curl; treat as no new data.
        if (err == error.FileNotFound) {
            return try s.allocator.alloc(u8, 0);
        }
        return err;
    };
    defer f.close();
    const stat = try f.stat();
    const size = stat.size;
    if (size <= offset.*) return try s.allocator.alloc(u8, 0);
    const len = size - offset.*;
    var data = try s.allocator.alloc(u8, @intCast(len));
    errdefer s.allocator.free(data);
    try f.seekTo(offset.*);
    var n: usize = 0;
    while (n < data.len) {
        const m = try f.read(data[n..]);
        if (m == 0) break;
        n += m;
    }
    offset.* += n;
    // Shrink to actual bytes read so free() gets the right size.
    if (n < len) {
        data = try s.allocator.realloc(data, n);
    }
    return data;
}

const SseDelim = struct { pos: usize, len: usize };
fn sseFindEventEnd(data: []const u8) ?SseDelim {
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 1) {
        if (data[i] == '\n' and data[i + 1] == '\n') return .{ .pos = i, .len = 2 };
        // CRLF: \r\n\r\n is 4 bytes.
        if (i + 3 < data.len and data[i] == '\r' and data[i + 1] == '\n' and data[i + 2] == '\r' and data[i + 3] == '\n') return .{ .pos = i, .len = 4 };
    }
    return null;
}

fn sseParseEventData(allocator: std.mem.Allocator, ev: []const u8) ?SseEventData {
    // SSE spec: multiple "data:" lines are joined with "\n".
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();
    var is_done = false;
    var lines = std.mem.splitScalar(u8, ev, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (std.mem.startsWith(u8, trimmed, "data:")) {
            const d = std.mem.trim(u8, trimmed[5..], " ");
            if (std.mem.eql(u8, d, "[DONE]")) {
                is_done = true;
            } else {
                parts.append(d) catch return null;
            }
        }
    }
    if (is_done) return .{ .payload = "", .is_done = true, .owned = false };
    if (parts.items.len == 0) return null;
    if (parts.items.len == 1) {
        return .{ .payload = parts.items[0], .is_done = false, .owned = false };
    }
    // Join with \n.
    const joined = std.mem.join(allocator, "\n", parts.items) catch return null;
    return .{ .payload = joined, .is_done = false, .owned = true };
}

/// Captures the raw JSON span of the last top-level "usage"
/// object in one SSE event payload. Escaped quotes inside string
/// values cannot form a false match because the search requires
/// a literal opening quote directly before the key.
fn sseCaptureUsage(payload: []const u8, usage: *std.array_list.Managed(u8)) void {
    const key = "\"usage\"";
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, payload, i, key)) |pos| {
        var j = pos + key.len;
        while (j < payload.len and (payload[j] == ' ' or payload[j] == '\t')) : (j += 1) {}
        if (j < payload.len and payload[j] == ':') {
            j += 1;
            while (j < payload.len and (payload[j] == ' ' or payload[j] == '\t')) : (j += 1) {}
            if (j < payload.len and payload[j] == '{') {
                var depth: usize = 0;
                var in_str = false;
                var esc = false;
                var k = j;
                while (k < payload.len) : (k += 1) {
                    const c = payload[k];
                    if (in_str) {
                        if (esc) {
                            esc = false;
                        } else if (c == '\\') {
                            esc = true;
                        } else if (c == '"') {
                            in_str = false;
                        }
                    } else if (c == '"') {
                        in_str = true;
                    } else if (c == '{') {
                        depth += 1;
                    } else if (c == '}') {
                        depth -= 1;
                        if (depth == 0) {
                            usage.clearRetainingCapacity();
                            usage.appendSlice(payload[j .. k + 1]) catch return;
                            return;
                        }
                    }
                }
                return;
            }
        }
        i = pos + key.len;
    }
}

test "sse usage capture extracts the last usage object" {
    const alloc = std.testing.allocator;
    var usage = std.array_list.Managed(u8).init(alloc);
    defer usage.deinit();
    sseCaptureUsage("{\"choices\":[],\"usage\":{\"prompt_tokens\":47,\"completion_tokens\":31,\"total_tokens\":78,\"prompt_tokens_details\":{\"cached_tokens\":0}}}", &usage);
    try std.testing.expectEqualStrings("{\"prompt_tokens\":47,\"completion_tokens\":31,\"total_tokens\":78,\"prompt_tokens_details\":{\"cached_tokens\":0}}", usage.items);
    // A later, smaller usage replaces the earlier one.
    sseCaptureUsage("{\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}", &usage);
    try std.testing.expectEqualStrings("{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}", usage.items);
    // null usage and content text do not capture.
    var usage2 = std.array_list.Managed(u8).init(alloc);
    defer usage2.deinit();
    sseCaptureUsage("{\"usage\":null}", &usage2);
    try std.testing.expectEqual(@as(usize, 0), usage2.items.len);
    sseCaptureUsage("{\"choices\":[{\"delta\":{\"content\":\"say \\\"usage\\\" please\"}}]}", &usage2);
    try std.testing.expectEqual(@as(usize, 0), usage2.items.len);
}

test "sse chat events accumulate reasoning separately from text" {
    const alloc = std.testing.allocator;
    var text = std.array_list.Managed(u8).init(alloc);
    defer text.deinit();
    var reasoning = std.array_list.Managed(u8).init(alloc);
    defer reasoning.deinit();
    var calls = std.array_list.Managed(SseCall).init(alloc);
    defer calls.deinit();
    var active = std.array_list.Managed(SseCall).init(alloc);
    defer active.deinit();
    var done = false;
    const DiscardWriter = struct {
        pub fn writeAll(_: *@This(), _: []const u8) !void {}
    };
    var dw = DiscardWriter{};
    const w = &dw;
    try sseHandleEvent(alloc, "{\"choices\":[{\"delta\":{\"reasoning\":\"The user\"}}]}", 1, &text, &reasoning, &calls, &active, &done, w);
    try sseHandleEvent(alloc, "{\"choices\":[{\"delta\":{\"reasoning\":\" asks.\",\"content\":\"ok\"}}]}", 1, &text, &reasoning, &calls, &active, &done, w);
    try std.testing.expectEqualStrings("The user asks.", reasoning.items);
    try std.testing.expectEqualStrings("ok", text.items);
}

fn sseHandleEvent(
    allocator: std.mem.Allocator,
    data: []const u8,
    api_mode: u64,
    text: *std.array_list.Managed(u8),
    reasoning: *std.array_list.Managed(u8),
    calls: *std.array_list.Managed(SseCall),
    active: *std.array_list.Managed(SseCall),
    stream_done: *bool,
    stdout: anytype,
) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value;
    if (api_mode == 0) {
        try sseHandleResponsesEvent(allocator, root, text, reasoning, calls, active, stream_done, stdout);
    } else {
        try sseHandleChatEvent(allocator, root, text, reasoning, calls, active, stream_done, stdout);
    }
}

// Find an active call by key (call_id for responses, index string for chat).
fn sseFindActive(active: *std.array_list.Managed(SseCall), key: []const u8) ?*SseCall {
    for (active.items) |*ac| {
        if (std.mem.eql(u8, ac.key, key)) return ac;
    }
    return null;
}

// Move all active calls to the completed list (finalize).
fn sseFinalizeActive(allocator: std.mem.Allocator, active: *std.array_list.Managed(SseCall), calls: *std.array_list.Managed(SseCall)) !void {
    for (active.items) |*ac| {
        if (ac.name.len > 0) {
            try calls.append(ac.*);
        } else {
            if (ac.call_id.len > 0) allocator.free(ac.call_id);
            if (ac.name.len > 0) allocator.free(ac.name);
            if (ac.args.len > 0) allocator.free(ac.args);
            if (ac.key.len > 0) allocator.free(ac.key);
        }
    }
    active.clearRetainingCapacity();
}

fn sseJsonStr(val: std.json.Value) ?[]const u8 {
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn sseHandleResponsesEvent(
    allocator: std.mem.Allocator,
    root: std.json.Value,
    text: *std.array_list.Managed(u8),
    reasoning: *std.array_list.Managed(u8),
    calls: *std.array_list.Managed(SseCall),
    active: *std.array_list.Managed(SseCall),
    stream_done: *bool,
    stdout: anytype,
) !void {
    const obj = switch (root) { .object => |o| o, else => return };
    const tval = obj.get("type") orelse return;
    const tstr = sseJsonStr(tval) orelse return;

    if (std.mem.eql(u8, tstr, "response.output_text.delta")) {
        if (obj.get("delta")) |dval| {
            if (sseJsonStr(dval)) |ds| {
                try stdout.writeAll(ds);
                try text.appendSlice(ds);
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.reasoning_summary_text.delta") or std.mem.eql(u8, tstr, "response.reasoning_text.delta")) {
        if (obj.get("delta")) |dval| {
            if (sseJsonStr(dval)) |ds| {
                try reasoning.appendSlice(ds);
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.output_item.added")) {
        if (obj.get("item")) |ival| {
            const item = switch (ival) { .object => |o| o, else => return };
            if (item.get("type")) |tyval| {
                if (sseJsonStr(tyval)) |tys| {
                    if (std.mem.eql(u8, tys, "function_call")) {
                        var cid: []u8 = &.{};
                        var nm: []u8 = &.{};
                        if (item.get("call_id")) |cv| {
                            if (sseJsonStr(cv)) |cs| cid = try allocator.dupe(u8, cs);
                        }
                        if (item.get("name")) |nv| {
                            if (sseJsonStr(nv)) |ns| nm = try allocator.dupe(u8, ns);
                        }
                        // Key by call_id for delta routing.
                        const key = try allocator.dupe(u8, cid);
                        errdefer allocator.free(key);
                        // If a call with same key exists, finalize it first.
                        if (sseFindActive(active, key)) |existing| {
                            if (existing.name.len > 0) {
                                try calls.append(existing.*);
                            } else {
                                if (existing.call_id.len > 0) allocator.free(existing.call_id);
                                if (existing.name.len > 0) allocator.free(existing.name);
                                if (existing.args.len > 0) allocator.free(existing.args);
                                if (existing.key.len > 0) allocator.free(existing.key);
                            }
                            // Remove from active.
                            for (active.items, 0..) |*ac, idx| {
                                if (ac == existing) {
                                    _ = active.orderedRemove(idx);
                                    break;
                                }
                            }
                        }
                        try active.append(.{
                            .call_id = cid,
                            .name = nm,
                            .args = &.{},
                            .key = key,
                        });
                    }
                }
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.function_call_arguments.delta")) {
        // Route by item_id if present, else use most recent active.
        var target: ?*SseCall = null;
        if (obj.get("item_id")) |idval| {
            if (sseJsonStr(idval)) |ids| {
                target = sseFindActive(active, ids);
            }
        }
        if (target == null and active.items.len > 0) {
            target = &active.items[active.items.len - 1];
        }
        if (target) |cc| {
            if (obj.get("delta")) |dval| {
                if (sseJsonStr(dval)) |ds| {
                    const old_args = cc.args;
                    const new_args = try std.mem.concat(allocator, u8, &.{ old_args, ds });
                    if (old_args.len > 0) allocator.free(old_args);
                    cc.args = new_args;
                }
            }
        }
    } else if (std.mem.eql(u8, tstr, "response.completed")) {
        stream_done.* = true;
    }
}

fn sseHandleChatEvent(
    allocator: std.mem.Allocator,
    root: std.json.Value,
    text: *std.array_list.Managed(u8),
    reasoning: *std.array_list.Managed(u8),
    calls: *std.array_list.Managed(SseCall),
    active: *std.array_list.Managed(SseCall),
    stream_done: *bool,
    stdout: anytype,
) !void {
    _ = stream_done;
    const obj = switch (root) { .object => |o| o, else => return };
    const cval = obj.get("choices") orelse return;
    const carr = switch (cval) { .array => |a| a, else => return };
    if (carr.items.len == 0) return;
    const choice = switch (carr.items[0]) { .object => |o| o, else => return };
    const dval = choice.get("delta") orelse return;
    const delta = switch (dval) { .object => |o| o, else => return };

    if (delta.get("content")) |cv| {
        if (sseJsonStr(cv)) |cs| {
            try stdout.writeAll(cs);
            try text.appendSlice(cs);
        }
    }

    // Reasoning text (chat shapes: delta.reasoning on some
    // gateways, delta.reasoning_content on DeepSeek-style APIs).
    // Accumulated separately; never printed, never mixed into
    // the answer text.
    if (delta.get("reasoning")) |rv| {
        if (sseJsonStr(rv)) |rs| {
            try reasoning.appendSlice(rs);
        }
    }
    if (delta.get("reasoning_content")) |rv| {
        if (sseJsonStr(rv)) |rs| {
            try reasoning.appendSlice(rs);
        }
    }

    if (delta.get("tool_calls")) |tcval| {
        const tcarr = switch (tcval) { .array => |a| a, else => return };
        for (tcarr.items) |tcitem| {
            const tc = switch (tcitem) { .object => |o| o, else => continue };
            // Get index for routing (default "0").
            var idx_buf: [16]u8 = undefined;
            var idx_str: []const u8 = "0";
            if (tc.get("index")) |ixval| {
                switch (ixval) {
                    .integer => |ix| {
                        idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{ix}) catch "0";
                    },
                    else => {},
                }
            }
            if (tc.get("id")) |idval| {
                if (sseJsonStr(idval)) |ids| {
                    // New call with this index: finalize previous with same index.
                    if (sseFindActive(active, idx_str)) |existing| {
                        if (existing.name.len > 0) {
                            try calls.append(existing.*);
                        } else {
                            if (existing.call_id.len > 0) allocator.free(existing.call_id);
                            if (existing.name.len > 0) allocator.free(existing.name);
                            if (existing.args.len > 0) allocator.free(existing.args);
                            if (existing.key.len > 0) allocator.free(existing.key);
                        }
                        for (active.items, 0..) |*ac, i| {
                            if (ac == existing) {
                                _ = active.orderedRemove(i);
                                break;
                            }
                        }
                    }
                    var nm: []u8 = &.{};
                    var ag: []u8 = &.{};
                    if (tc.get("function")) |fval| {
                        const func = switch (fval) { .object => |o| o, else => null };
                        if (func) |fo| {
                            if (fo.get("name")) |nv| {
                                if (sseJsonStr(nv)) |ns| nm = try allocator.dupe(u8, ns);
                            }
                            if (fo.get("arguments")) |av| {
                                if (sseJsonStr(av)) |as| ag = try allocator.dupe(u8, as);
                            }
                        }
                    }
                    const key = try allocator.dupe(u8, idx_str);
                    errdefer allocator.free(key);
                    try active.append(.{
                        .call_id = try allocator.dupe(u8, ids),
                        .name = nm,
                        .args = ag,
                        .key = key,
                    });
                }
            } else if (tc.get("function")) |fval| {
                // Arguments delta: route by index.
                if (sseFindActive(active, idx_str)) |cc| {
                    const func = switch (fval) { .object => |o| o, else => continue };
                    if (func.get("arguments")) |av| {
                        if (sseJsonStr(av)) |as| {
                            const old_args = cc.args;
                            const new_args = try std.mem.concat(allocator, u8, &.{ old_args, as });
                            if (old_args.len > 0) allocator.free(old_args);
                            cc.args = new_args;
                        }
                    }
                }
            }
        }
    }
}

fn sseJsonEscape(out: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => try out.append(ch),
        }
    }
}

/// Frees all four out buffers of an sse turn at once
/// (sa_http_client_sse_turn / _ex). Exists alongside the
/// per-buffer sa_http_client_sse_turn_free: that one returns
/// void, and SLA codegen cannot pass plain ptrs to
/// void-returning ptr externs (CapabilityMismatch), while
/// value-returning externs accept them. Zero-length outs are
/// skipped (their slices may be sentinels, not allocations).
pub export fn sa_http_client_sse_turn_free_all(
    text_ptr: ?[*]u8, text_len: u64,
    calls_ptr: ?[*]u8, calls_len: u64,
    usage_ptr: ?[*]u8, usage_len: u64,
    reasoning_ptr: ?[*]u8, reasoning_len: u64,
) u32 {
    if (text_len > 0) sa_http_client_sse_turn_free(text_ptr, text_len);
    if (calls_len > 0) sa_http_client_sse_turn_free(calls_ptr, calls_len);
    if (usage_len > 0) sa_http_client_sse_turn_free(usage_ptr, usage_len);
    if (reasoning_len > 0) sa_http_client_sse_turn_free(reasoning_ptr, reasoning_len);
    return 0;
}

pub export fn sa_http_client_sse_turn_free(ptr: ?[*]u8, len: u64) void {
    if (ptr) |p| {
        const slice = p[0..@intCast(len)];
        std.heap.page_allocator.free(slice);
    }
}

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

const V2Error = error{
    WouldBlock,
    Closed,
    Timeout,
    TooLarge,
    Invalid,
    Io,
};

fn statusCode(status: NetworkStatus) u32 {
    return @intFromEnum(status);
}

fn statusFromV2Error(err: V2Error) NetworkStatus {
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

fn requiredSlice(ptr: ?[*]const u8, len: u64) V2Error![]const u8 {
    if (len > std.math.maxInt(usize)) return error.Invalid;
    if (len == 0) return "";
    return (ptr orelse return error.Invalid)[0..@intCast(len)];
}

fn validHeaderName(name: []const u8) bool {
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

fn validHeaderValue(value: []const u8) bool {
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

fn splitStdHeaders(allocator: std.mem.Allocator, headers: []const std.http.Header) !StdHeaderParts {
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

    fn request(timeout_ms: u32) Deadline {
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

    fn hasTimeout(self: Deadline) bool {
        return self.started_ns != null;
    }

    fn remainingNs(self: Deadline) V2Error!u64 {
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

    fn socketMillis(self: Deadline) V2Error!u32 {
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

fn executeRequestV2(request: *HttpRequest, tracker: ?*V2AsyncOp) V2Error!*HttpResponse {
    const deadline = Deadline.request(request.timeout_ms);
    if (requestCancelled(tracker)) return error.Closed;
    const uri = std.Uri.parse(request.url) catch |err| return mapHttpError(err, deadline, tracker);
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

const V2AsyncOp = struct {
    allocator: std.mem.Allocator,
    request: *HttpRequest,
    thread: ?std.Thread = null,
    // NOTE(Zig 0.17): Thread.Mutex/Condition removed; spin + sleep-poll.
    mutex: std.atomic.Mutex = .unlocked,
    done: bool = false,
    cancel_requested: bool = false,
    result_status: NetworkStatus = .would_block,
    response: ?*HttpResponse = null,

    fn init(source: *HttpRequest) !*V2AsyncOp {
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

    fn run(self: *V2AsyncOp) void {
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

    fn cancelled(self: *V2AsyncOp) bool {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        return self.cancel_requested;
    }

    fn cancel(self: *V2AsyncOp) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (self.done or self.cancel_requested) return;
        self.cancel_requested = true;
    }

    fn poll(self: *V2AsyncOp, timeout_ms: u32, out_ready: *u8) NetworkStatus {
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

    fn takeResponse(self: *V2AsyncOp, out_resp: *?*anyopaque) NetworkStatus {
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

    fn deinit(self: *V2AsyncOp) void {
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

const WebSocketOpcodeV2 = enum(u8) {
    continuation = 0,
    text = 1,
    binary = 2,
    close = 8,
    ping = 9,
    pong = 10,
};

const WebSocketV2 = struct {
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

fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
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


    fn rawRead(self: *WebSocketV2, buffer: []u8) V2Error!usize {
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

    fn rawWrite(self: *WebSocketV2, bytes: []const u8) V2Error!void {
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

    fn markClosed(self: *WebSocketV2) void {
        if (self.closed) return;
        self.closed = true;
        self.stream.shutdown(sio.io(), .both) catch {};
    }

    fn clearLastMessage(self: *WebSocketV2) void {
        if (self.last_message) |message| self.allocator.free(message);
        self.last_message = null;
    }

    fn deinit(self: *WebSocketV2) void {
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

fn websocketPoll(handle: *WebSocketV2, interests: u32, timeout_ms: u32, out_events: *u32) NetworkStatus {
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

const FrameMeta = struct {
    fin: bool,
    opcode: u8,
    payload_offset: usize,
    payload_len: usize,
    frame_len: usize,
};

const FrameParse = union(enum) {
    need_more,
    too_large,
    invalid,
    frame: FrameMeta,
};

fn parseServerFrame(bytes: []const u8, max_payload: u64) FrameParse {
    if (bytes.len < 2) return .need_more;
    const first = bytes[0];
    const second = bytes[1];
    if (first & 0x70 != 0) return .invalid;
    if (second & 0x80 != 0) return .invalid;

    var payload_len: u64 = second & 0x7f;
    var payload_offset: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return .need_more;
        payload_len = std.mem.readInt(u16, bytes[2..4], .big);
        if (payload_len < 126) return .invalid;
        payload_offset = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return .need_more;
        payload_len = std.mem.readInt(u64, bytes[2..10], .big);
        if (payload_len < 65536 or payload_len & (@as(u64, 1) << 63) != 0) return .invalid;
        payload_offset = 10;
    }
    if (payload_len > max_payload or payload_len > std.math.maxInt(usize)) return .too_large;
    const payload_len_usize: usize = @intCast(payload_len);
    const frame_len = std.math.add(usize, payload_offset, payload_len_usize) catch return .too_large;
    if (bytes.len < frame_len) return .need_more;
    const opcode = first & 0x0f;
    const fin = first & 0x80 != 0;
    if (opcode >= 8 and (!fin or payload_len > 125)) return .invalid;
    return .{ .frame = .{
        .fin = fin,
        .opcode = opcode,
        .payload_offset = payload_offset,
        .payload_len = payload_len_usize,
        .frame_len = frame_len,
    } };
}

fn compactReceiveBuffer(handle: *WebSocketV2) void {
    if (handle.receive_start == 0) return;
    if (handle.receive_start == handle.receive_buffer.items.len) {
        handle.receive_buffer.clearRetainingCapacity();
        handle.receive_start = 0;
        return;
    }
    if (handle.receive_start < 4096 and handle.receive_start * 2 < handle.receive_buffer.items.len) return;
    const remaining = handle.receive_buffer.items.len - handle.receive_start;
    std.mem.copyForwards(u8, handle.receive_buffer.items[0..remaining], handle.receive_buffer.items[handle.receive_start..]);
    handle.receive_buffer.items.len = remaining;
    handle.receive_start = 0;
}

fn consumeFrame(handle: *WebSocketV2, frame_len: usize) void {
    handle.receive_start += frame_len;
    compactReceiveBuffer(handle);
}

fn errorFromNetworkStatus(status: NetworkStatus) V2Error {
    return switch (status) {
        .would_block => error.WouldBlock,
        .closed => error.Closed,
        .timeout => error.Timeout,
        .too_large => error.TooLarge,
        .invalid => error.Invalid,
        .io_error => error.Io,
        .ok => unreachable,
    };
}

fn fillWebSocketInput(handle: *WebSocketV2) V2Error!void {
    var events: u32 = 0;
    const poll_status = websocketPoll(handle, PollEvent.readable, 0, &events);
    if (poll_status != .ok) return errorFromNetworkStatus(poll_status);
    if (events & PollEvent.readable == 0) return if (events & PollEvent.closed != 0) error.Closed else error.WouldBlock;
    var buffer: [16 * 1024]u8 = undefined;
    const read_len = handle.rawRead(&buffer) catch |err| return err;
    if (read_len == 0) return error.Closed;
    handle.receive_buffer.appendSlice(buffer[0..read_len]) catch return error.Io;
}

fn websocketFrameBytes(handle: *WebSocketV2, opcode: u8, payload: []const u8) V2Error![]u8 {
    if (payload.len > max_v2_message_bytes) return error.TooLarge;
    const header_len: usize = if (payload.len < 126) 2 else if (payload.len <= std.math.maxInt(u16)) 4 else 10;
    const frame_capacity = std.math.add(usize, payload.len, header_len + 4) catch return error.TooLarge;
    const frame = handle.allocator.alloc(u8, frame_capacity) catch return error.Io;
    errdefer handle.allocator.free(frame);
    var mask_key: [4]u8 = undefined;
    sio.io().random(&mask_key);
    const frame_len = buildWebSocketFrame(frame, opcode, payload, &mask_key) catch return error.Invalid;
    std.debug.assert(frame_len == frame_capacity);
    return frame;
}

fn writeWebSocketFrame(handle: *WebSocketV2, opcode: u8, payload: []const u8) V2Error!void {
    if (handle.closed or handle.close_sent) return error.Closed;
    var events: u32 = 0;
    const poll_status = websocketPoll(handle, PollEvent.writable, 0, &events);
    if (poll_status != .ok) return errorFromNetworkStatus(poll_status);
    const frame = try websocketFrameBytes(handle, opcode, payload);
    defer handle.allocator.free(frame);
    handle.rawWrite(frame) catch |err| {
        handle.markClosed();
        return err;
    };
}

fn flushPendingPong(handle: *WebSocketV2) V2Error!void {
    const payload = handle.pending_pong orelse return;
    try writeWebSocketFrame(handle, @intFromEnum(WebSocketOpcodeV2.pong), payload);
    handle.allocator.free(payload);
    handle.pending_pong = null;
}

fn validCloseCode(code: u16) bool {
    if (code >= 3000 and code <= 4999) return true;
    return switch (code) {
        1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014 => true,
        else => false,
    };
}

fn validateClosePayload(payload: []const u8) bool {
    if (payload.len == 0) return true;
    if (payload.len == 1) return false;
    const code = std.mem.readInt(u16, payload[0..2], .big);
    return validCloseCode(code) and std.unicode.utf8ValidateSlice(payload[2..]);
}

fn deliverMessage(handle: *WebSocketV2, opcode: u8, payload: []const u8, out_opcode: *u8, out_ptr: *?[*]const u8, out_len: *u64) V2Error!void {
    if (opcode == @intFromEnum(WebSocketOpcodeV2.text) and !std.unicode.utf8ValidateSlice(payload)) return error.Invalid;
    const copy = if (payload.len == 0) null else handle.allocator.dupe(u8, payload) catch return error.Io;
    handle.clearLastMessage();
    handle.last_message = copy;
    out_opcode.* = opcode;
    out_ptr.* = if (copy) |message| message.ptr else null;
    out_len.* = payload.len;
}

fn readWebSocketMessage(
    handle: *WebSocketV2,
    max_len: u64,
    out_opcode: *u8,
    out_ptr: *?[*]const u8,
    out_len: *u64,
) V2Error!void {
    const message_limit = if (max_len == 0) max_v2_message_bytes else @min(max_len, max_v2_message_bytes);
    try flushPendingPong(handle);
    while (true) {
        const available = handle.receive_buffer.items[handle.receive_start..];
        switch (parseServerFrame(available, message_limit)) {
            .need_more => {
                fillWebSocketInput(handle) catch |err| {
                    if (err == error.Closed) handle.markClosed();
                    return err;
                };
                continue;
            },
            .too_large => {
                handle.markClosed();
                return error.TooLarge;
            },
            .invalid => {
                handle.markClosed();
                return error.Invalid;
            },
            .frame => |frame| {
                const payload = available[frame.payload_offset .. frame.payload_offset + frame.payload_len];
                switch (frame.opcode) {
                    @intFromEnum(WebSocketOpcodeV2.ping) => {
                        if (handle.pending_pong) |old| handle.allocator.free(old);
                        handle.pending_pong = handle.allocator.dupe(u8, payload) catch return error.Io;
                        consumeFrame(handle, frame.frame_len);
                        try flushPendingPong(handle);
                    },
                    @intFromEnum(WebSocketOpcodeV2.pong) => consumeFrame(handle, frame.frame_len),
                    @intFromEnum(WebSocketOpcodeV2.close) => {
                        if (!validateClosePayload(payload)) {
                            handle.markClosed();
                            return error.Invalid;
                        }
                        if (!handle.close_sent) {
                            writeWebSocketFrame(handle, @intFromEnum(WebSocketOpcodeV2.close), payload) catch {};
                            handle.close_sent = true;
                        }
                        consumeFrame(handle, frame.frame_len);
                        handle.markClosed();
                        return error.Closed;
                    },
                    @intFromEnum(WebSocketOpcodeV2.text), @intFromEnum(WebSocketOpcodeV2.binary) => {
                        if (handle.fragment_opcode != null) {
                            handle.markClosed();
                            return error.Invalid;
                        }
                        if (frame.fin) {
                            try deliverMessage(handle, frame.opcode, payload, out_opcode, out_ptr, out_len);
                            consumeFrame(handle, frame.frame_len);
                            return;
                        }
                        handle.fragment_opcode = frame.opcode;
                        handle.fragment_buffer.clearRetainingCapacity();
                        handle.fragment_buffer.appendSlice(payload) catch return error.Io;
                        consumeFrame(handle, frame.frame_len);
                    },
                    @intFromEnum(WebSocketOpcodeV2.continuation) => {
                        const initial_opcode = handle.fragment_opcode orelse {
                            handle.markClosed();
                            return error.Invalid;
                        };
                        const next_len = std.math.add(usize, handle.fragment_buffer.items.len, payload.len) catch {
                            handle.markClosed();
                            return error.TooLarge;
                        };
                        if (next_len > message_limit) {
                            handle.markClosed();
                            return error.TooLarge;
                        }
                        handle.fragment_buffer.appendSlice(payload) catch return error.Io;
                        consumeFrame(handle, frame.frame_len);
                        if (frame.fin) {
                            try deliverMessage(handle, initial_opcode, handle.fragment_buffer.items, out_opcode, out_ptr, out_len);
                            handle.fragment_buffer.clearRetainingCapacity();
                            handle.fragment_opcode = null;
                            return;
                        }
                    },
                    else => {
                        handle.markClosed();
                        return error.Invalid;
                    },
                }
            },
        }
    }
}

pub export fn sa_http_websocket_poll_v2(ws: ?*anyopaque, interests: u32, timeout_ms: u32, out_events: ?*u32) u32 {
    const events = out_events orelse return statusCode(.invalid);
    events.* = 0;
    const ws_ptr = ws orelse return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    return statusCode(websocketPoll(handle, interests, timeout_ms, events));
}

pub export fn sa_http_websocket_read_v2(
    ws: ?*anyopaque,
    max_len: u64,
    out_opcode: ?*u8,
    out_ptr: ?*?[*]const u8,
    out_len: ?*u64,
) u32 {
    const opcode_slot = out_opcode orelse return statusCode(.invalid);
    const ptr_slot = out_ptr orelse return statusCode(.invalid);
    const len_slot = out_len orelse return statusCode(.invalid);
    opcode_slot.* = 0;
    ptr_slot.* = null;
    len_slot.* = 0;
    const ws_ptr = ws orelse return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    readWebSocketMessage(handle, max_len, opcode_slot, ptr_slot, len_slot) catch |err| return statusCode(statusFromV2Error(err));
    return statusCode(.ok);
}

pub export fn sa_http_websocket_write_v2(
    ws: ?*anyopaque,
    opcode: u8,
    data_ptr: ?[*]const u8,
    data_len: u64,
    out_written: ?*u64,
) u32 {
    const written = out_written orelse return statusCode(.invalid);
    written.* = 0;
    const ws_ptr = ws orelse return statusCode(.invalid);
    const payload = requiredSlice(data_ptr, data_len) catch return statusCode(.invalid);
    if (opcode != @intFromEnum(WebSocketOpcodeV2.text) and opcode != @intFromEnum(WebSocketOpcodeV2.binary) and
        opcode != @intFromEnum(WebSocketOpcodeV2.ping) and opcode != @intFromEnum(WebSocketOpcodeV2.pong))
    {
        return statusCode(.invalid);
    }
    if ((opcode == @intFromEnum(WebSocketOpcodeV2.ping) or opcode == @intFromEnum(WebSocketOpcodeV2.pong)) and payload.len > 125) return statusCode(.too_large);
    if (opcode == @intFromEnum(WebSocketOpcodeV2.text) and !std.unicode.utf8ValidateSlice(payload)) return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    writeWebSocketFrame(handle, opcode, payload) catch |err| return statusCode(statusFromV2Error(err));
    written.* = payload.len;
    return statusCode(.ok);
}

pub export fn sa_http_websocket_close_v2(ws: ?*anyopaque, code: u16, reason_ptr: ?[*]const u8, reason_len: u64) u32 {
    const ws_ptr = ws orelse return statusCode(.invalid);
    const reason = requiredSlice(reason_ptr, reason_len) catch return statusCode(.invalid);
    if (!validCloseCode(code) or reason.len > 123) return statusCode(if (reason.len > 123) .too_large else .invalid);
    if (!std.unicode.utf8ValidateSlice(reason)) return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    while (!handle.io_mutex.tryLock()) std.atomic.spinLoopHint();
    defer handle.io_mutex.unlock();
    if (handle.closed or handle.close_sent) return statusCode(.closed);
    var payload: [125]u8 = undefined;
    std.mem.writeInt(u16, payload[0..2], code, .big);
    @memcpy(payload[2 .. 2 + reason.len], reason);
    writeWebSocketFrame(handle, @intFromEnum(WebSocketOpcodeV2.close), payload[0 .. 2 + reason.len]) catch |err| return statusCode(statusFromV2Error(err));
    handle.close_sent = true;
    return statusCode(.ok);
}

pub export fn sa_http_websocket_free_v2(ws: ?*anyopaque) u32 {
    const ws_ptr = ws orelse return statusCode(.invalid);
    const handle: *WebSocketV2 = @ptrCast(@alignCast(ws_ptr));
    handle.deinit();
    return statusCode(.ok);
}

// ======================= loopback tests =======================
// Real 127.0.0.1 servers (raw linux sockets) exercising the exported
// ABI end to end: v1 sync client, v2 client, WS client, SSE (curl).

const testing = std.testing;
const linux = std.os.linux;

fn sysErr(rc: usize) bool {
    return @as(isize, @bitCast(rc)) < 0;
}

const TestServer = struct {
    thread: std.Thread,
    port: u16,
    listen_fd: i32,

    const Handler = *const fn (fd: i32) void;

    fn start(handler: Handler) !*TestServer {
        const rc = linux.socket(std.posix.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, std.posix.IPPROTO.TCP);
        if (sysErr(rc)) return error.SocketFailed;
        const fd: i32 = @intCast(rc);
        var addr = std.posix.sockaddr.in{ .family = std.posix.AF.INET, .port = 0, .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
        if (sysErr(linux.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in)))) return error.BindFailed;
        if (sysErr(linux.listen(fd, 4))) return error.ListenFailed;
        var alen: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
        if (sysErr(linux.getsockname(fd, @ptrCast(&addr), &alen))) return error.GetsocknameFailed;
        const self = try testing.allocator.create(TestServer);
        self.* = .{ .thread = undefined, .port = std.mem.bigToNative(u16, addr.port), .listen_fd = fd };
        if (comptime builtin.cpu.arch.isWasm()) {
            return error.UnsupportedPlatform;
        } else {
            self.thread = try std.Thread.spawn(.{}, runServer, .{ fd, handler });
        }
        return self;
    }

    fn runServer(fd: i32, handler: Handler) void {
        const rc = linux.accept(fd, null, null);
        if (sysErr(rc)) {
            _ = linux.close(fd);
            return;
        }
        const cfd: i32 = @intCast(rc);
        handler(cfd);
        _ = linux.close(cfd);
        _ = linux.close(fd);
    }

    fn join(self: *TestServer) void {
        self.thread.join();
        testing.allocator.destroy(self);
    }
};

fn sockRead(fd: i32, buf: []u8) usize {
    const rc = linux.read(fd, buf.ptr, buf.len);
    if (sysErr(rc)) return 0;
    return rc;
}

fn sockWriteAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (sysErr(rc) or rc == 0) return;
        off += rc;
    }
}

fn readRequest(fd: i32, buf: []u8) []u8 {
    var n: usize = 0;
    while (n < buf.len) {
        const r = sockRead(fd, buf[n..]);
        if (r == 0) break;
        n += r;
        if (std.mem.indexOf(u8, buf[0..n], "\r\n\r\n")) |he| {
            var need: usize = 0;
            if (std.mem.indexOf(u8, buf[0..he], "Content-Length: ")) |ci| {
                const vs = ci + "Content-Length: ".len;
                const ve = std.mem.indexOfScalarPos(u8, buf[0..he], vs, '\r') orelse he;
                need = std.fmt.parseInt(usize, buf[vs..ve], 10) catch 0;
            }
            const total = he + 4 + need;
            while (n < total and n < buf.len) {
                const r2 = sockRead(fd, buf[n..]);
                if (r2 == 0) break;
                n += r2;
            }
            break;
        }
    }
    return buf[0..n];
}

fn httpEchoHandler(fd: i32) void {
    var buf: [8192]u8 = undefined;
    const req = readRequest(fd, &buf);
    var out: [8192]u8 = undefined;
    var olen: usize = 0;
    const sp1 = std.mem.indexOfScalar(u8, req, ' ') orelse 0;
    const sp2 = if (sp1 > 0) std.mem.indexOfScalarPos(u8, req, sp1 + 1, ' ') orelse sp1 else 0;
    const body = if (std.mem.indexOf(u8, req, "\r\n\r\n")) |he| req[he + 4 ..] else "";
    const parts = [_][]const u8{ req[0..sp1], " ", req[sp1 + 1 .. sp2], " ", body };
    for (parts) |p| {
        @memcpy(out[olen..][0..p.len], p);
        olen += p.len;
    }
    var hdr: [256]u8 = undefined;
    const h = std.fmt.bufPrint(&hdr, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{olen}) catch return;
    sockWriteAll(fd, h);
    sockWriteAll(fd, out[0..olen]);
}

test "http client v1: POST echo over loopback" {
    const srv = try TestServer.start(httpEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/echo", .{srv.port});

    var client: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_new(0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_new(client, 2, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const body = "hello-std";
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_set_body(req, body.ptr, body.len));
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_req_send(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    try testing.expectEqualStrings("POST /echo hello-std", out_body.?[0..out_len]);
}

test "http client v2: POST echo over loopback" {
    const srv = try TestServer.start(httpEchoHandler);
    defer srv.join();
    var url_buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/v2", .{srv.port});

    var client: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_new_v2(0, null, 0, &client));
    defer _ = sa_http_client_free(client);
    var req: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_new_v2(client, 2, url.ptr, url.len, &req));
    defer _ = sa_http_client_req_free(req);
    const body = "v2-body";
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_set_body_v2(req, body.ptr, body.len));
    var resp: ?*anyopaque = null;
    try testing.expectEqual(@as(u32, 0), sa_http_client_req_send_v2(req, &resp));
    defer _ = sa_http_client_resp_free(resp);
    try testing.expectEqual(@as(u16, 200), sa_http_client_resp_status(resp));
    var out_body: ?[*]const u8 = null;
    var out_len: u64 = 0;
    try testing.expectEqual(@intFromEnum(AbiStatus.ok), sa_http_client_resp_body_slice(resp, &out_body, &out_len));
    try testing.expectEqualStrings("POST /v2 v2-body", out_body.?[0..out_len]);
}

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


