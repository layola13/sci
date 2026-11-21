const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

// AbiStatus mirrors the plugin ABI enum (ok=0, failed=2), localized so
// the std module carries no plugin dependency.
pub const AbiStatus = enum(u32) { ok = 0, failed = 2 };
// Client-owned allocations pool through malloc (the same decision the
// server face documents at serverAllocator): the page allocator costs
// one mmap/munmap pair per small allocation, and a client request
// churns dozens of small allocations (header pairs, body lists, URI
// clones), so per-request throughput collapses into syscall overhead.
// Every HttpClient allocation flows from the allocator stored at
// construction, so switching the two constructors switches the whole
// request/response lifecycle consistently.
pub fn clientAllocator() std.mem.Allocator {
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
pub fn readExact(reader: *std.Io.Reader, buffer: []u8) !void {
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
pub fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
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
    // GAP-17: shaped-TLS profile JSON (the sa_tls_shaped profile
    // document). When set, https:// requests execute over the
    // shaped TLS stack instead of std.http.Client's TLS, so the
    // ClientHello carries the profile's fingerprint. Validated at
    // construction; plain http:// requests are unaffected.
    tls_profile: ?[]const u8 = null,
    // GAP-25: explicit proxy URL (http:// or https://, optional
    // user:password@ authority). Overrides the proxy environment
    // for BOTH schemes on this client. SOCKS URLs are rejected:
    // std.http.Client has no SOCKS support and a silent direct
    // fallback would be a lie.
    proxy_url: ?[]const u8 = null,
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
    // Owned copy of the GAP-17 shaped-TLS profile JSON, or null
    // for the default (std TLS) face.
    tls_profile: ?[]u8 = null,

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
        if (cfg.tls_profile) |profile| {
            // Fail at construction, not at first request: the
            // profile document is parsed and resolved exactly as
            // the shaped connect path would.
            if (shaped.shapedProfileCheck(profile) != 0) return error.InvalidTlsProfile;
            self.tls_profile = try allocator.dupe(u8, profile);
        }
        errdefer if (self.tls_profile) |profile| allocator.free(profile);
        if (cfg.proxy_url) |proxy_url| {
            try self.applyExplicitProxy(proxy_url);
        }
        return self;
    }

    /// GAP-25: parse an explicit proxy URL and install it for
    /// both schemes, replacing whatever the environment provided.
    /// Mirrors std's createProxyFromEnvVar construction (which is
    /// private): http:// and https:// proxies only -- a socks*
    /// scheme makes Protocol.fromUri return null and the caller
    /// fails loudly instead of silently going direct.
    fn applyExplicitProxy(self: *HttpClient, proxy_url: []const u8) !void {
        const a = self.proxy_arena.allocator();
        const uri = std.Uri.parse(proxy_url) catch
            (std.Uri.parseAfterScheme("http", proxy_url) catch return error.InvalidProxyUrl);
        const protocol = std.http.Client.Protocol.fromUri(uri) orelse return error.InvalidProxyUrl;
        var host_buf: [std.Io.net.HostName.max_len]u8 = undefined;
        const raw_host = std.Io.net.HostName.fromUri(uri, &host_buf) catch return error.InvalidProxyUrl;
        if (raw_host.bytes.len == 0) return error.InvalidProxyUrl;
        const authorization: ?[]const u8 = if (uri.user != null or uri.password != null) blk: {
            const s = try a.alloc(u8, std.http.Client.basic_authorization.valueLengthFromUri(uri));
            std.debug.assert(std.http.Client.basic_authorization.value(uri, s).len == s.len);
            break :blk s;
        } else null;
        const proxy = try a.create(std.http.Client.Proxy);
        proxy.* = .{
            .protocol = protocol,
            .host = .{ .bytes = try a.dupe(u8, raw_host.bytes) },
            .authorization = authorization,
            .port = uri.port orelse switch (protocol) {
                .plain => 80,
                .tls => 443,
            },
            .supports_connect = true,
        };
        self.client.http_proxy = proxy;
        self.client.https_proxy = proxy;
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
        if (self.tls_profile) |profile| self.allocator.free(profile);
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
pub fn buildUpstreamUrl(allocator: std.mem.Allocator, target: []const u8, request_path: []const u8, preserve_base_path: bool) ![]u8 {
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
pub fn addRequestHeader(request: *HttpRequest, key: []const u8, val: []const u8) !void {
    const name = try request.allocator.dupe(u8, key);
    errdefer request.allocator.free(name);
    const value = try request.allocator.dupe(u8, val);
    errdefer request.allocator.free(value);
    try request.headers.append(.{ .name = name, .value = value });
}
pub fn cloneRequestForAsync(src: *HttpRequest) !*HttpRequest {
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
