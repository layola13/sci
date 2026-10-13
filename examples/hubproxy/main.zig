const std = @import("std");
const sio = @import("sio");

const Config = struct {
    listen_host: []const u8 = "127.0.0.1",
    listen_port: u16 = 18081,
    upstream_base_url: []const u8 = "http://127.0.0.1:18080/v1",
    name: []const u8 = "openai",
    mode: []const u8 = "streaming",
};

const ConfigState = struct {
    arena: std.heap.ArenaAllocator,
    config: Config,

    fn deinit(self: *ConfigState) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const Route = enum {
    chat_completions,
    responses,
};

const ResolvedRoute = struct {
    route: Route,
    suffix: []const u8,
};

fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !ConfigState {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    const bytes = try sio.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSliceLeaky(Config, arena.allocator(), bytes, .{
        .ignore_unknown_fields = true,
    });

    return .{
        .arena = arena,
        .config = parsed,
    };
}

fn resolveRoute(target: []const u8) ?ResolvedRoute {
    const path = std.mem.sliceTo(target, '?');
    if (std.mem.eql(u8, path, "/v1/chat/completions")) {
        return .{
            .route = .chat_completions,
            .suffix = target["/v1".len..],
        };
    }
    if (std.mem.eql(u8, path, "/v1/responses")) {
        return .{
            .route = .responses,
            .suffix = target["/v1".len..],
        };
    }
    return null;
}

fn joinUpstreamUrl(allocator: std.mem.Allocator, base_url: []const u8, suffix: []const u8) ![]u8 {
    const trimmed_base = std.mem.trimEnd(u8, base_url, "/");
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ trimmed_base, suffix });
}

fn readRequestBody(allocator: std.mem.Allocator, request: *std.http.Server.Request) ![]u8 {
    var tmp: [8192]u8 = undefined;
    var body_reader = request.readerExpectNone(&tmp);
    return try body_reader.allocRemaining(allocator, .limited(16 * 1024 * 1024));
}

fn isStreamingResponse(response: std.http.Client.Response) bool {
    if (response.head.transfer_encoding == .chunked) return true;
    if (response.head.content_type) |content_type| {
        return std.mem.startsWith(u8, content_type, "text/event-stream");
    }
    return false;
}

fn proxyStreamingResponse(
    request: *std.http.Server.Request,
    upstream: *std.http.Client.Response,
    status: std.http.Status,
    content_type: []const u8,
) !void {
    var send_buffer: [16 * 1024]u8 = undefined;
    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = content_type },
    };
    var body_writer = try request.respondStreaming(&send_buffer, .{
        .respond_options = .{
            .status = status,
            .keep_alive = false,
            .extra_headers = &headers,
        },
    });

    var ubuf: [4096]u8 = undefined;
    var ureader = upstream.reader(&ubuf);
    var buffer: [4096]u8 = undefined;
    while (true) {
        var vec = [_][]u8{buffer[0..]};
        const n = ureader.readVec(&vec) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (n == 0) break;
        try body_writer.writer.writeAll(buffer[0..n]);
    }
    try body_writer.end();
}

fn proxyBufferedResponse(
    request: *std.http.Server.Request,
    upstream: *std.http.Client.Response,
    allocator: std.mem.Allocator,
    status: std.http.Status,
    content_type: []const u8,
) !void {
    var ubuf: [4096]u8 = undefined;
    var ureader = upstream.reader(&ubuf);
    const body = try ureader.allocRemaining(allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(body);

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = content_type },
    };
    try request.respond(body, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = &headers,
    });
}

fn forwardToUpstream(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    config: Config,
    resolved: ResolvedRoute,
) !void {
    const body = try readRequestBody(allocator, request);
    defer allocator.free(body);

    const upstream_url = try joinUpstreamUrl(allocator, config.upstream_base_url, resolved.suffix);
    defer allocator.free(upstream_url);

    var client: std.http.Client = .{ .allocator = allocator, .io = sio.io() };
    defer client.deinit();

    const upstream_uri = try std.Uri.parse(upstream_url);
    const content_type = request.head.content_type orelse "application/json";
    var upstream_req = try client.request(request.head.method, upstream_uri, .{
        .keep_alive = false,
        .redirect_behavior = .not_allowed,
        .headers = .{
            .content_type = .{ .override = content_type },
            .accept_encoding = .omit,
        },
    });
    defer upstream_req.deinit();

    if (body.len > 0) {
        const body_mut = try allocator.dupe(u8, body);
        defer allocator.free(body_mut);
        try upstream_req.sendBodyComplete(body_mut);
    } else {
        try upstream_req.sendBodiless();
    }
    var redirect_buf: [8 * 1024]u8 = undefined;
    var upstream_resp = try upstream_req.receiveHead(&redirect_buf);
    const upstream_status = upstream_resp.head.status;
    const upstream_content_type = upstream_resp.head.content_type orelse if (isStreamingResponse(upstream_resp)) "text/event-stream" else "application/json";
    if (isStreamingResponse(upstream_resp)) {
        try proxyStreamingResponse(request, &upstream_resp, upstream_status, upstream_content_type);
    } else {
        try proxyBufferedResponse(request, &upstream_resp, allocator, upstream_status, upstream_content_type);
    }
}

fn handleRequest(
    allocator: std.mem.Allocator,
    request: *std.http.Server.Request,
    config: Config,
) !bool {
    const resolved = resolveRoute(request.head.target) orelse {
        try request.respond("not found\n", .{
            .status = .not_found,
            .keep_alive = false,
        });
        return false;
    };
    try forwardToUpstream(allocator, request, config, resolved);
    return true;
}

fn serveConnection(allocator: std.mem.Allocator, stream: std.Io.net.Stream, config: Config) !void {
    var rbuf: [16 * 1024]u8 = undefined;
    var wbuf: [16 * 1024]u8 = undefined;
    var sreader = stream.reader(sio.io(), &rbuf);
    var swriter = stream.writer(sio.io(), &wbuf);
    var server = std.http.Server.init(&sreader.interface, &swriter.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => break,
            else => return err,
        };
        _ = try handleRequest(allocator, &request, config);
    }
}

fn listenAddress(host: []const u8, port: u16) !std.Io.net.IpAddress {
    if (std.Io.net.IpAddress.parse(host, port)) |a| return a else |_| {}
    if (std.ascii.eqlIgnoreCase(host, "localhost")) {
        return try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
    }
    return error.InvalidListenHost;
}

fn serve(config: Config) !void {
    const address = try listenAddress(config.listen_host, config.listen_port);
    var listener = try address.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());

    std.debug.print("hubproxy listening on http://{s}:{d}\n", .{ config.listen_host, config.listen_port });
    while (true) {
        var stream = try listener.accept(sio.io());
        defer stream.close(sio.io());
        try serveConnection(std.heap.page_allocator, stream, config);
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try sio.argsAlloc(allocator);
    defer sio.argsFree(allocator, args);

    const config_path = if (args.len >= 2) args[1] else "examples/hubproxy/upstream.json";
    var state = try loadConfig(allocator, config_path);
    defer state.deinit();

    try serve(state.config);
}

test "hubproxy config parsing keeps defaults and ignores extra fields" {
    const json =
        \\{
        \\  "listen_host": "127.0.0.1",
        \\  "listen_port": 18081,
        \\  "upstream_base_url": "http://127.0.0.1:18080/v1",
        \\  "unexpected": "ignored"
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSliceLeaky(Config, arena.allocator(), json, .{
        .ignore_unknown_fields = true,
    });
    try std.testing.expectEqualStrings("127.0.0.1", parsed.listen_host);
    try std.testing.expectEqual(@as(u16, 18081), parsed.listen_port);
    try std.testing.expectEqualStrings("http://127.0.0.1:18080/v1", parsed.upstream_base_url);
}

test "hubproxy resolves supported routes" {
    try std.testing.expect(resolveRoute("/v1/chat/completions") != null);
    try std.testing.expect(resolveRoute("/v1/responses?stream=true") != null);
    try std.testing.expect(resolveRoute("/v1/models") == null);
}
