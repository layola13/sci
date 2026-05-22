const std = @import("std");
const plugin_api = @import("plugin_api.zig");
const plugin_helpers = @import("plugin_helpers.zig");
pub usingnamespace @import("http_saasm_api.zig");

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "http server plugin",
        .summary = "HubProxy and HTTP server scaffolding",
        .items = &.{
            "http-server scaffold <dir>",
            "http-server serve <host> <port>",
            "reads request headers and bodies",
            "streams chunked responses for SSE-style routes",
            "generates a concrete HubProxy starter project",
            "emits a working sa_http_server.sai stub",
        },
    },
};

fn ensureDir(path: []const u8) !void {
    if (path.len != 0) try std.fs.cwd().makePath(path);
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| try ensureDir(dir);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn requestPath(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |idx| return target[0..idx];
    return target;
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}

fn readRequestBodyAlloc(ctx: *const plugin_api.Context, request: *std.http.Server.Request) ![]u8 {
    var body = std.ArrayList(u8).init(ctx.allocator);
    errdefer body.deinit();
    const reader = try request.reader();
    try reader.readAllArrayList(&body, 2 * 1024 * 1024);
    return body.toOwnedSlice();
}

fn respondStreamed(request: *std.http.Server.Request, send_buffer: []u8, chunks: []const []const u8) !void {
    var response = request.respondStreaming(.{
        .send_buffer = send_buffer,
        .respond_options = .{
            .status = .ok,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/event-stream" },
            },
            .transfer_encoding = .chunked,
        },
    });
    for (chunks, 0..) |chunk, idx| {
        try response.writeAll(chunk);
        try response.flush();
        if (idx + 1 < chunks.len) std.time.sleep(10 * std.time.ns_per_ms);
    }
    try response.endChunked(.{});
}

fn handleRoute(
    ctx: *const plugin_api.Context,
    request: *std.http.Server.Request,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
) !void {
    const path = requestPath(request.head.target);
    const content_type = headerValue(request, "content-type") orelse "";

    if (std.mem.eql(u8, path, "/echo")) {
        const body = try readRequestBodyAlloc(ctx, request);
        defer ctx.allocator.free(body);
        try request.respond(body, .{
            .status = .ok,
            .extra_headers = if (content_type.len == 0) &.{} else &.{.{ .name = "content-type", .value = content_type }},
        });
        try stdout.print("route=echo path={s} body={d}\n", .{ path, body.len });
        return;
    }

    if (std.mem.eql(u8, path, "/stream")) {
        var send_buffer: [2048]u8 = undefined;
        try respondStreamed(request, &send_buffer, &.{
            "data: first\n\n",
            "data: second\n\n",
        });
        try stdout.print("route=stream path={s}\n", .{path});
        return;
    }

    const not_found = "not found\n";
    try request.respond(not_found, .{
        .status = .not_found,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
    try stderr.print("error: unknown route {s}\n", .{path});
}

fn runServeCommand(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "http-server")) return null;
    if (argv.len < 5) return error.MissingSourcePath;

    const sub = argv[2];
    if (!std.mem.eql(u8, sub, "serve")) return error.UnknownCommand;

    const host = argv[3];
    const port = std.fmt.parseInt(u16, argv[4], 10) catch return error.InvalidPath;
    var max_requests: ?usize = null;
    if (argv.len >= 6) {
        max_requests = std.fmt.parseInt(usize, argv[5], 10) catch return error.InvalidPath;
    }
    const address = try std.net.Address.parseIp(host, port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    var served: usize = 0;
    while (max_requests == null or served < max_requests.?) {
        var accepted = try server.accept();
        defer accepted.stream.close();

        var request_buffer: [4096]u8 = undefined;
        var http_server = std.http.Server.init(accepted, &request_buffer);
        var request = http_server.receiveHead() catch |err| {
            try stderr.print("error: receive head failed: {}\n", .{err});
            return 1;
        };

        handleRoute(ctx, &request, stdout, stderr) catch |err| {
            try stderr.print("error: request handling failed: {}\n", .{err});
            return 1;
        };
        served += 1;
    }
    return 0;
}

fn runHttpServerCommand(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "http-server")) return null;
    if (argv.len < 3) return error.MissingSourcePath;

    const sub = argv[2];
    if (std.mem.eql(u8, sub, "serve")) {
        if (argv.len < 5) return error.MissingSourcePath;
        return try runServeCommand(ctx, argv, stdout, stderr);
    }
    if (!std.mem.eql(u8, sub, "scaffold")) return error.UnknownCommand;
    if (argv.len < 4) return error.MissingSourcePath;

    const root = argv[3];
    const iface_path = try std.fs.path.join(ctx.allocator, &.{ root, "sa_http_server.sai" });
    defer ctx.allocator.free(iface_path);
    const main_path = try std.fs.path.join(ctx.allocator, &.{ root, "main.sa" });
    defer ctx.allocator.free(main_path);
    const readme_path = try std.fs.path.join(ctx.allocator, &.{ root, "README.md" });
    defer ctx.allocator.free(readme_path);

    try writeFile(iface_path,
        \\@extern sa_http_server_new(&out_server: ptr) -> i32!
        \\@extern sa_http_server_route(server: ptr, &path: ptr, path_len: u64, ^handler: ptr) -> i32!
        \\@extern sa_http_server_start(server: ptr, &host: ptr, host_len: u64, port: u16) -> i32!
        \\@extern sa_http_server_resp_new(req: ptr, status: u16, &out_resp: ptr) -> i32!
        \\@extern sa_http_server_resp_send(resp: ptr, &body_ptr: ptr, body_len: u64) -> i32!
    );

    try writeFile(main_path,
        \\@export hubproxy_main():
        \\L_ENTRY:
        \\  panic(102)
    );

    try writeFile(readme_path,
        \\# HubProxy scaffold
        \\
        \\Generated by `sa http-server scaffold`.
        \\Fill in the HTTP handlers and wire them to `sa_http_server`.
        \\
        \\The `http-server serve` command is a minimal runtime smoke test for the plugin.
    );

    try stdout.print("{s}\n", .{root});
    return 0;
}

fn runHttpServerCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    const args = plugin_helpers.cArgvToSlice(argv, argv_len, ctx.allocator) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer ctx.allocator.free(args);
    var stdout_ctx: plugin_helpers.StreamWriterCtx = undefined;
    var stderr_ctx: plugin_helpers.StreamWriterCtx = undefined;
    const stdout_writer = plugin_helpers.makeAnyWriter(stdout, &stdout_ctx) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const stderr_writer = plugin_helpers.makeAnyWriter(stderr, &stderr_ctx) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const result = runHttpServerCommand(ctx, args, stdout_writer, stderr_writer) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

pub const plugin = plugin_api.Plugin{
    .name = "http-server",
    .handleCommand = runHttpServerCommand,
    .skills = &skills,
};

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "http-server",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runHttpServerCommandAbi,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;

test "http server plugin exports runtime descriptor and scaffold entry" {
    const exported = saasm_plugin_descriptor_v1;
    try std.testing.expectEqual(plugin_api.abi_version, exported.abi_version);
    try std.testing.expectEqual(@as(u32, @sizeOf(plugin_api.PluginDescriptor)), exported.descriptor_size);
    try std.testing.expectEqualStrings("http-server", std.mem.span(exported.name));
    try std.testing.expectEqual(@as(usize, 1), exported.skills_len);
    try std.testing.expectEqualStrings("http server plugin", exported.skills_ptr[0].name);
    try std.testing.expect(exported.handle_command != null);

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const argv = [_][]const u8{ "sa", "http-server", "scaffold", "scaffold-out" };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const code = try runHttpServerCommand(
        &ctx,
        argv[0..],
        stdout_buf.writer().any(),
        stderr_buf.writer().any(),
    );

    try std.testing.expectEqual(@as(?u8, 0), code);
    try std.testing.expectEqualStrings("scaffold-out\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    const iface = try std.fs.cwd().readFileAlloc(std.testing.allocator, "scaffold-out/sa_http_server.sai", 1024 * 1024);
    defer std.testing.allocator.free(iface);
    try std.testing.expectEqualStrings(
        \\@extern sa_http_server_new(&out_server: ptr) -> i32!
        \\@extern sa_http_server_route(server: ptr, &path: ptr, path_len: u64, ^handler: ptr) -> i32!
        \\@extern sa_http_server_start(server: ptr, &host: ptr, host_len: u64, port: u16) -> i32!
        \\@extern sa_http_server_resp_new(req: ptr, status: u16, &out_resp: ptr) -> i32!
        \\@extern sa_http_server_resp_send(resp: ptr, &body_ptr: ptr, body_len: u64) -> i32!
    , iface);
}

test "http server plugin serve responds on a local loopback socket" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const port: u16 = 18080;
    const argv = [_][]const u8{ "sa", "http-server", "serve", "127.0.0.1", "18080", "1" };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const serve_thread = try std.Thread.spawn(.{}, struct {
        fn run(context: *plugin_api.Context, args: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) void {
            _ = runHttpServerCommand(context, args, stdout, stderr) catch {};
        }
    }.run, .{ &ctx, argv[0..], stdout_buf.writer().any(), stderr_buf.writer().any() });

    var client = blk: {
        var attempt: usize = 0;
        while (attempt < 50) : (attempt += 1) {
            const stream = std.net.tcpConnectToHost(std.testing.allocator, "127.0.0.1", port) catch |err| switch (err) {
                error.ConnectionRefused => {
                    std.time.sleep(20 * std.time.ns_per_ms);
                    continue;
                },
                else => return err,
            };
            break :blk stream;
        }
        return error.ConnectionRefused;
    };
    defer client.close();
    try client.writeAll("GET /echo HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello");

    var response_buf: [256]u8 = undefined;
    const n = try client.read(&response_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..n], "hello") != null);

    serve_thread.join();
    try std.testing.expectEqualStrings("route=echo path=/echo body=5\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}

test "http server plugin stream route returns chunked SSE body" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const port: u16 = 18081;
    const argv = [_][]const u8{ "sa", "http-server", "serve", "127.0.0.1", "18081", "1" };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const serve_thread = try std.Thread.spawn(.{}, struct {
        fn run(context: *plugin_api.Context, args: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) void {
            _ = runHttpServerCommand(context, args, stdout, stderr) catch {};
        }
    }.run, .{ &ctx, argv[0..], stdout_buf.writer().any(), stderr_buf.writer().any() });

    var client = blk: {
        var attempt: usize = 0;
        while (attempt < 50) : (attempt += 1) {
            const stream = std.net.tcpConnectToHost(std.testing.allocator, "127.0.0.1", port) catch |err| switch (err) {
                error.ConnectionRefused => {
                    std.time.sleep(20 * std.time.ns_per_ms);
                    continue;
                },
                else => return err,
            };
            break :blk stream;
        }
        return error.ConnectionRefused;
    };
    defer client.close();
    try client.writeAll("GET /stream HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");

    var response_buf: [512]u8 = undefined;
    const n = try client.read(&response_buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, response_buf[0..n], "data: first") != null);

    serve_thread.join();
    try std.testing.expectEqualStrings("route=stream path=/stream\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}
