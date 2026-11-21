const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const HttpRequest = @import("core.zig").HttpRequest;
const cloneRequestForAsync = @import("core.zig").cloneRequestForAsync;
const httpRequestExec = @import("exec.zig").httpRequestExec;

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

    pub fn init(allocator: std.mem.Allocator, body: []u8) !*HttpBodyReader {
        const self = try allocator.create(HttpBodyReader);
        self.* = .{
            .allocator = allocator,
            .body = body,
            .cursor = 0,
        };
        return self;
    }

    pub fn deinit(self: *HttpBodyReader) void {
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

    pub fn init(request: *HttpRequest) !*HttpRequestAsyncOp {
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

    pub fn run(self: *HttpRequestAsyncOp) void {
        const response = httpRequestExec(self.request) catch null;
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        self.response = response;
        self.done = true;
        self.mutex.unlock();
    }

    pub fn poll(self: *HttpRequestAsyncOp) bool {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        return self.done;
    }

    pub fn takeResponse(self: *HttpRequestAsyncOp) ?*HttpResponse {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (!self.done) return null;
        const response = self.response orelse return null;
        self.response = null;
        return response;
    }

    pub fn deinit(self: *HttpRequestAsyncOp) void {
        if (self.thread) |thread| thread.join();
        if (self.response) |response| response.deinit();
        self.request.deinit();
        self.allocator.destroy(self);
    }
};
pub fn mapStatus(status: std.http.Status) u16 {
    return @intCast(@intFromEnum(status));
}
fn endsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - needle.len ..], needle);
}
/// curl-compatible no_proxy matching: "*" matches all; ".example.com" or
/// "example.com" match the domain and subdomains; "host:port" restricts by port.
pub fn hostMatchesNoProxy(host: []const u8, port: u16, no_proxy: []const u8) bool {
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
pub fn maybeBypassProxy(req: *HttpRequest, uri: std.Uri) void {
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
pub fn cloneResponseHeaders(allocator: std.mem.Allocator, response: std.http.Client.Response) ![]std.http.Header {
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
pub fn makeStatusResponse(allocator: std.mem.Allocator, status: u16, headers: []std.http.Header, body: []u8) !*HttpResponse {
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
