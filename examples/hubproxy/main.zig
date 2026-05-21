const std = @import("std");

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

    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
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
    const trimmed_base = std.mem.trimRight(u8, base_url, "/");
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ trimmed_base, suffix });
}

fn readRequestBody(allocator: std.mem.Allocator, request: *std.http.Server.Request) ![]u8 {
    var body = std.ArrayList(u8).init(allocator);
    errdefer body.deinit();

    var reader = try request.reader();
    try reader.readAllArrayList(&body, 16 * 1024 * 1024);
    return try body.toOwnedSlice();
}

fn isStreamingResponse(response: std.http.Client.Response) bool {
    if (response.transfer_encoding == .chunked) return true;
    if (response.content_type) |content_type| {
        return std.mem.startsWith(u8, content_type, "text/event-stream");
    }
    return false;
}

fn proxyStreamingResponse(
    request: *std.http.Server.Request,
    upstream: *std.http.Client.Request,
    status: std.http.Status,
    content_type: []const u8,
) !void {
    var send_buffer: [16 * 1024]u8 = undefined;
    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = content_type },
    };
    var response = request.respondStreaming(.{
        .send_buffer = &send_buffer,
        .respond_options = .{
            .status = status,
            .keep_alive = false,
            .extra_headers = &headers,
        },
    });

    var buffer: [4096]u8 = undefined;
    var reader = upstream.reader();
    while (true) {
        const n = try reader.read(&buffer);
        if (n == 0) break;
        try response.writeAll(buffer[0..n]);
    }
    try response.end();
}

fn proxyBufferedResponse(
    request: *std.http.Server.Request,
    upstream: *std.http.Client.Request,
    allocator: std.mem.Allocator,
    status: std.http.Status,
    content_type: []const u8,
) !void {
    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    var reader = upstream.reader();
    try reader.readAllArrayList(&body, 16 * 1024 * 1024);

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = content_type },
    };
    try request.respond(body.items, .{
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

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var server_header_buffer: [16 * 1024]u8 = undefined;
    const upstream_uri = try std.Uri.parse(upstream_url);
    const content_type = request.head.content_type orelse "application/json";
    var upstream_req = try client.open(request.head.method, upstream_uri, .{
        .server_header_buffer = &server_header_buffer,
        .keep_alive = false,
        .headers = .{
            .content_type = .{ .override = content_type },
            .accept_encoding = .omit,
        },
    });
    defer upstream_req.deinit();

    if (body.len > 0) {
        upstream_req.transfer_encoding = .{ .content_length = body.len };
    }

    try upstream_req.send();
    if (body.len > 0) try upstream_req.writeAll(body);
    try upstream_req.finish();
    try upstream_req.wait();

    const upstream_status = upstream_req.response.status;
    const upstream_content_type = upstream_req.response.content_type orelse if (isStreamingResponse(upstream_req.response)) "text/event-stream" else "application/json";
    if (isStreamingResponse(upstream_req.response)) {
        try proxyStreamingResponse(request, &upstream_req, upstream_status, upstream_content_type);
    } else {
        try proxyBufferedResponse(request, &upstream_req, allocator, upstream_status, upstream_content_type);
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

fn serveConnection(allocator: std.mem.Allocator, connection: std.net.Server.Connection, config: Config) !void {
    var request_buffer: [16 * 1024]u8 = undefined;
    var server = std.http.Server.init(connection, &request_buffer);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => break,
            else => return err,
        };
        _ = try handleRequest(allocator, &request, config);
    }
}

fn serve(config: Config) !void {
    const address = try std.net.Address.parseIp(config.listen_host, config.listen_port);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    std.debug.print("hubproxy listening on http://{s}:{d}\n", .{ config.listen_host, config.listen_port });
    while (true) {
        const connection = try listener.accept();
        defer connection.stream.close();
        try serveConnection(std.heap.page_allocator, connection, config);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
