const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const shaped = @import("../sa_tls_shaped.zig");

const HttpRequest = @import("core.zig").HttpRequest;
const HttpResponse = @import("response.zig").HttpResponse;
const cloneResponseHeaders = @import("response.zig").cloneResponseHeaders;
const dialHost = @import("core.zig").dialHost;
const hostMatchesNoProxy = @import("response.zig").hostMatchesNoProxy;
const indexOfIgnoreCase = @import("core.zig").indexOfIgnoreCase;
const makeStatusResponse = @import("response.zig").makeStatusResponse;
const mapStatus = @import("response.zig").mapStatus;
const maybeBypassProxy = @import("response.zig").maybeBypassProxy;
const splitStdHeaders = @import("v2_core.zig").splitStdHeaders;

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
pub fn isRetryableStatus(status: u16) bool {
    return status == 429 or (status >= 500 and status < 600);
}
/// Exponential backoff in seconds: 1, 2, 4, 8, 16 for attempts 0..4.
pub fn backoffSecs(attempt: u32) u64 {
    return @as(u64, 1) << @intCast(@min(attempt, 4));
}
/// Single attempt without retry. See httpRequestExec for the retry wrapper.
// ---- GAP-17 shaped-TLS execution path ----
//
// When the client carries a tls_profile, https:// requests run
// here instead of through std.http.Client: the connection is
// established by the shaped TLS stack (sa_tls_shaped) so the
// ClientHello on the wire is the profile's, and HTTP/1.1 is
// spoken directly over it. Semantics mirror httpRequestExecOnce
// where the face promises them: request headers/body in,
// status/headers/body out, Accept-Encoding: identity unless the
// caller set one, Connection: close, no redirect following (the
// std path also leaves redirects unhandled), response size cap
// from req.max_response_bytes. The client's configured https
// proxy (explicit GAP-25 URL or environment-provided) is
// honoured with a CONNECT tunnel + shaped_start_tls, and the
// no_proxy bypass applies exactly as on the std path. Transport
// failures are plain errors, so the v1 retry wrapper treats
// them like std transport errors.

fn shapedNoProxyBypass(req: *HttpRequest, host: []const u8, port: u16) bool {
    const no_proxy = sio.getEnvVarOwned(req.allocator, "no_proxy") catch
        (sio.getEnvVarOwned(req.allocator, "NO_PROXY") catch return false);
    defer req.allocator.free(no_proxy);
    return hostMatchesNoProxy(host, port, no_proxy);
}
fn shapedWriteAll(handle: u64, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        var written: u64 = 0;
        if (shaped.sa_std_tls_shaped_write(handle, bytes[off..].ptr, bytes.len - off, &written) != 0) return error.Io;
        if (written == 0) return error.Io;
        off += @intCast(written);
    }
}
/// Speak CONNECT to the proxy over `stream` and require a 200.
/// Reads one byte at a time from the raw fd so no byte past the
/// response head is consumed (everything after it is TLS). The
/// head is capped at 16 KiB.
fn proxyConnect(stream: std.Io.net.Stream, proxy: *std.http.Client.Proxy, host: []const u8, port: u16, allocator: std.mem.Allocator) !void {
    var head = std.array_list.Managed(u8).init(allocator);
    defer head.deinit();
    var port_buf: [8]u8 = undefined;
    const port_s = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch unreachable;
    try head.appendSlice("CONNECT ");
    try head.appendSlice(host);
    try head.append(':');
    try head.appendSlice(port_s);
    try head.appendSlice(" HTTP/1.1\r\nHost: ");
    try head.appendSlice(host);
    try head.append(':');
    try head.appendSlice(port_s);
    try head.appendSlice("\r\n");
    if (proxy.authorization) |auth| {
        try head.appendSlice("Proxy-Authorization: ");
        try head.appendSlice(auth);
        try head.appendSlice("\r\n");
    }
    try head.appendSlice("\r\n");
    var wbuf: [4096]u8 = undefined;
    var w = stream.writer(sio.io(), &wbuf);
    try w.interface.writeAll(head.items);
    try w.interface.flush();

    var resp = std.array_list.Managed(u8).init(allocator);
    defer resp.deinit();
    var byte: [1]u8 = undefined;
    while (!std.mem.endsWith(u8, resp.items, "\r\n\r\n")) {
        if (resp.items.len > 16 * 1024) return error.ProxyConnect;
        const n = if (comptime builtin.os.tag == .wasi) return error.ProxyConnect else std.posix.read(stream.socket.handle, &byte) catch return error.ProxyConnect;
        if (n == 0) return error.ProxyConnect;
        try resp.append(byte[0]);
    }
    if (resp.items.len < 12 or !std.mem.startsWith(u8, resp.items, "HTTP/1.") or
        !std.mem.eql(u8, resp.items[9..12], "200")) return error.ProxyConnect;
}
/// Find a header value in a raw response head (case-insensitive
/// name match); the head excludes the terminating CRLFCRLF.
fn rawHeadHeader(head: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, head, "\r\n");
    _ = lines.next(); // status line
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), name)) {
            return std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    return null;
}
/// Scan a chunked body: returns the decoded length once the
/// terminal chunk and its closing CRLF are fully present, or
/// null while more bytes are needed / the framing is malformed.
fn chunkedComplete(body: []const u8) ?usize {
    var pos: usize = 0;
    var total: usize = 0;
    while (true) {
        const line_end = std.mem.indexOfPos(u8, body, pos, "\r\n") orelse return null;
        var size_field = body[pos..line_end];
        if (std.mem.indexOfScalar(u8, size_field, ';')) |semi| size_field = size_field[0..semi];
        const size = std.fmt.parseInt(usize, std.mem.trim(u8, size_field, " \t"), 16) catch return null;
        pos = line_end + 2;
        if (size == 0) {
            // Trailer part runs to an empty line; the minimal
            // form is a single CRLF right here.
            if (body.len - pos >= 2 and std.mem.eql(u8, body[pos..][0..2], "\r\n")) return total;
            if (std.mem.indexOfPos(u8, body, pos, "\r\n\r\n") != null) return total;
            return null;
        }
        if (body.len - pos < size + 2) return null;
        if (!std.mem.eql(u8, body[pos + size ..][0..2], "\r\n")) return null;
        total += size;
        pos += size + 2;
    }
}
fn dechunkBody(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    var pos: usize = 0;
    while (true) {
        const line_end = std.mem.indexOfPos(u8, body, pos, "\r\n") orelse return error.InvalidResponse;
        var size_field = body[pos..line_end];
        if (std.mem.indexOfScalar(u8, size_field, ';')) |semi| size_field = size_field[0..semi];
        const size = std.fmt.parseInt(usize, std.mem.trim(u8, size_field, " \t"), 16) catch return error.InvalidResponse;
        pos = line_end + 2;
        if (size == 0) break;
        if (body.len - pos < size + 2) return error.InvalidResponse;
        try out.appendSlice(body[pos .. pos + size]);
        pos += size + 2;
    }
    return out.toOwnedSlice();
}
/// True when `raw` already holds a complete response under its
/// own framing (status line + head + body), so the reader can
/// stop before EOF. Close-delimited bodies are never "complete"
/// early -- EOF ends them.
fn shapedFramingComplete(raw: []const u8, method: std.http.Method) bool {
    const head_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return false;
    const head = raw[0..head_end];
    const first_sp = std.mem.indexOfScalar(u8, head, ' ') orelse return false;
    if (head.len < first_sp + 4) return false;
    const status = std.fmt.parseInt(u16, head[first_sp + 1 ..][0..3], 10) catch return false;
    if ((status >= 100 and status < 200) or status == 204 or status == 304 or !method.responseHasBody()) return true;
    const body = raw[head_end + 4 ..];
    if (rawHeadHeader(head, "transfer-encoding")) |te| {
        if (indexOfIgnoreCase(te, "chunked") != null) return chunkedComplete(body) != null;
    }
    if (rawHeadHeader(head, "content-length")) |cl| {
        const want = std.fmt.parseInt(usize, std.mem.trim(u8, cl, " \t"), 10) catch return false;
        return body.len >= want;
    }
    return false;
}
fn parseShapedResponse(req: *HttpRequest, raw: []const u8) !*HttpResponse {
    const a = req.allocator;
    var rest = raw;
    // Skip interim 1xx heads (except 101, which this client
    // never negotiates and is treated as final garbage below).
    while (true) {
        const head_end = std.mem.indexOf(u8, rest, "\r\n\r\n") orelse return error.InvalidResponse;
        const head = rest[0..head_end];
        const first_sp = std.mem.indexOfScalar(u8, head, ' ') orelse return error.InvalidResponse;
        if (head.len < first_sp + 4) return error.InvalidResponse;
        const status = std.fmt.parseInt(u16, head[first_sp + 1 ..][0..3], 10) catch return error.InvalidResponse;
        if (status >= 100 and status < 200 and status != 101) {
            rest = rest[head_end + 4 ..];
            continue;
        }
        var headers = std.array_list.Managed(std.http.Header).init(a);
        errdefer {
            for (headers.items) |header| {
                a.free(header.name);
                a.free(header.value);
            }
            headers.deinit();
        }
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        _ = lines.next(); // status line
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidResponse;
            try headers.append(.{
                .name = try a.dupe(u8, std.mem.trim(u8, line[0..colon], " \t")),
                .value = try a.dupe(u8, std.mem.trim(u8, line[colon + 1 ..], " \t")),
            });
        }
        var body_slice = rest[head_end + 4 ..];
        var body: []u8 = undefined;
        if ((status >= 100 and status < 200) or status == 204 or status == 304 or !req.method.responseHasBody()) {
            body = try a.alloc(u8, 0);
        } else if (rawHeadHeader(head, "transfer-encoding") != null and indexOfIgnoreCase(rawHeadHeader(head, "transfer-encoding").?, "chunked") != null) {
            body = try dechunkBody(a, body_slice);
        } else if (rawHeadHeader(head, "content-length")) |cl| {
            const want = std.fmt.parseInt(usize, std.mem.trim(u8, cl, " \t"), 10) catch return error.InvalidResponse;
            if (body_slice.len < want) return error.InvalidResponse;
            body = try a.dupe(u8, body_slice[0..want]);
        } else {
            body = try a.dupe(u8, body_slice);
        }
        errdefer a.free(body);
        if (body.len > req.max_response_bytes) return error.StreamTooLong;
        return try makeStatusResponse(a, status, try headers.toOwnedSlice(), body);
    }
}
fn httpRequestExecShaped(req: *HttpRequest, uri: std.Uri) !*HttpResponse {
    const a = req.allocator;
    const host_comp = uri.host orelse return error.InvalidUrl;
    const host: []const u8 = switch (host_comp) {
        .raw => |r| r,
        .percent_encoded => |p| p,
    };
    const port: u16 = uri.port orelse 443;
    const profile = req.client.tls_profile orelse return error.InvalidUrl;

    // Serialize on the client request mutex: the CONNECT path
    // reads the shared std-client proxy fields, mirroring the
    // std path's discipline around them.
    while (!req.client.request_mutex.tryLock()) std.atomic.spinLoopHint();
    defer req.client.request_mutex.unlock();

    var handle: u64 = 0;
    const proxy = req.client.client.https_proxy;
    if (proxy != null and !shapedNoProxyBypass(req, host, port)) {
        const p = proxy.?;
        var stream = try dialHost(p.host.bytes, p.port);
        var handed_off = false;
        defer if (!handed_off) stream.close(sio.io());
        try proxyConnect(stream, p, host, port, a);
        // start_tls takes the fd on success and on failure.
        const rc = shaped.sa_std_tls_shaped_start_tls(stream.socket.handle, host.ptr, host.len, profile.ptr, profile.len, &handle);
        handed_off = true;
        if (rc != 0) return error.TlsHandshake;
    } else {
        if (shaped.sa_std_tls_shaped_connect(host.ptr, host.len, port, profile.ptr, profile.len, &handle) != 0)
            return error.TlsHandshake;
    }
    defer _ = shaped.sa_std_tls_shaped_close(handle);

    // ---- serialize the request ----
    var out = std.array_list.Managed(u8).init(a);
    defer out.deinit();
    try out.appendSlice(@tagName(req.method));
    try out.append(' ');
    const path: []const u8 = switch (uri.path) {
        .raw => |r| r,
        .percent_encoded => |p| p,
    };
    if (path.len == 0) {
        try out.appendSlice("/");
    } else {
        try out.appendSlice(path);
    }
    if (uri.query) |q| {
        try out.append('?');
        try out.appendSlice(switch (q) {
            .raw => |r| r,
            .percent_encoded => |p| p,
        });
    }
    try out.appendSlice(" HTTP/1.1\r\nHost: ");
    try out.appendSlice(host);
    if (port != 443) {
        var port_buf: [8]u8 = undefined;
        const port_s = std.fmt.bufPrint(&port_buf, ":{d}", .{port}) catch unreachable;
        try out.appendSlice(port_s);
    }
    try out.appendSlice("\r\n");
    var has_ae = false;
    var has_cl = false;
    var has_conn = false;
    for (req.headers.items) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "accept-encoding")) has_ae = true;
        if (std.ascii.eqlIgnoreCase(h.name, "content-length")) has_cl = true;
        if (std.ascii.eqlIgnoreCase(h.name, "connection")) has_conn = true;
        try out.appendSlice(h.name);
        try out.appendSlice(": ");
        try out.appendSlice(h.value);
        try out.appendSlice("\r\n");
    }
    if (req.body != null and !has_cl) {
        var cl_buf: [48]u8 = undefined;
        const cl_s = std.fmt.bufPrint(&cl_buf, "Content-Length: {d}\r\n", .{req.body.?.len}) catch unreachable;
        try out.appendSlice(cl_s);
    }
    if (!has_ae) try out.appendSlice("Accept-Encoding: identity\r\n");
    if (!has_conn) try out.appendSlice("Connection: close\r\n");
    try out.appendSlice("\r\n");
    if (req.body) |body| try out.appendSlice(body);
    try shapedWriteAll(handle, out.items);

    // ---- read the response ----
    var raw = std.array_list.Managed(u8).init(a);
    defer raw.deinit();
    var chunk: [8192]u8 = undefined;
    while (!shapedFramingComplete(raw.items, req.method)) {
        var n: u64 = 0;
        if (shaped.sa_std_tls_shaped_read(handle, &chunk, chunk.len, &n) != 0) return error.Io;
        if (n == 0) break; // clean EOF
        try raw.appendSlice(chunk[0..@intCast(n)]);
        if (raw.items.len > req.max_response_bytes + 64 * 1024) return error.StreamTooLong;
    }
    return parseShapedResponse(req, raw.items);
}
fn httpRequestExecOnce(req: *HttpRequest) !*HttpResponse {
    const uri = try std.Uri.parse(req.url);
    // GAP-17 routing: a profiled client's https:// requests run
    // over the shaped TLS stack. http:// is unaffected.
    if (req.client.tls_profile != null and std.mem.eql(u8, uri.scheme, "https")) {
        return httpRequestExecShaped(req, uri);
    }
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
pub fn httpRequestExec(req: *HttpRequest) !*HttpResponse {
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
