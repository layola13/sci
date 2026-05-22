const std = @import("std");
const plugin_api = @import("plugin_api.zig");
const plugin_helpers = @import("plugin_helpers.zig");
pub usingnamespace @import("http_saasm_api.zig");

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "http client",
        .summary = "Outgoing HTTP and HTTPS requests for plugins and HubProxy",
        .items = &.{
            "http-client get <url>",
            "http-client get --ca-bundle <path> <url>",
            "http-client stream <url>",
            "http-client stream --ca-bundle <path> <url>",
            "loopback GET and body retrieval",
            "chunked SSE body streaming",
            "custom CA bundle loading",
            "runtime descriptor and skills metadata",
        },
    },
};

const ClientArgs = struct {
    url: []const u8,
    ca_bundle_path: ?[]const u8 = null,
};

const RequestOptions = struct {
    method: std.http.Method = .GET,
    url: []const u8,
    ca_bundle_path: ?[]const u8 = null,
    body: ?[]const u8 = null,
    headers: []const std.http.Header = &.{},
};

const RequestArgs = struct {
    url: []const u8,
    ca_bundle_path: ?[]const u8 = null,
    body: ?[]const u8 = null,
    headers: []const std.http.Header = &.{},
};

fn parseRequestArgs(allocator: std.mem.Allocator, args: []const []const u8, allow_body: bool) !RequestArgs {
    var url: ?[]const u8 = null;
    var ca_bundle_path: ?[]const u8 = null;
    var body: ?[]const u8 = null;
    var header_list = std.ArrayList(std.http.Header).init(allocator);
    defer header_list.deinit();
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--ca-bundle")) {
            if (i + 1 >= args.len) return error.MissingSourcePath;
            ca_bundle_path = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--header")) {
            if (i + 1 >= args.len) return error.MissingSourcePath;
            const raw = args[i + 1];
            const colon = std.mem.indexOfScalar(u8, raw, ':') orelse return error.UnexpectedArgument;
            const name = std.mem.trim(u8, raw[0..colon], " \t");
            const value = std.mem.trim(u8, raw[colon + 1 ..], " \t");
            if (name.len == 0) return error.UnexpectedArgument;
            try header_list.append(.{ .name = name, .value = value });
            i += 1;
            continue;
        }
        if (url == null) {
            url = arg;
            continue;
        }
        if (allow_body and body == null) {
            body = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return .{
        .url = url orelse return error.MissingSourcePath,
        .ca_bundle_path = ca_bundle_path,
        .body = body,
        .headers = try header_list.toOwnedSlice(),
    };
}

fn configureHttpsTrust(client: *std.http.Client, ctx: *const plugin_api.Context, ca_bundle_path: ?[]const u8) !void {
    if (std.http.Client.disable_tls) return;
    if (ca_bundle_path) |bundle_path| {
        const abs_path = try std.fs.cwd().realpathAlloc(ctx.allocator, bundle_path);
        defer ctx.allocator.free(abs_path);
        try client.ca_bundle.addCertsFromFilePathAbsolute(ctx.allocator, abs_path);
        client.next_https_rescan_certs = false;
    }
}

fn runHttpRequest(
    ctx: *const plugin_api.Context,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    options: RequestOptions,
) anyerror!?u8 {
    var client: std.http.Client = .{ .allocator = ctx.allocator };
    defer client.deinit();

    var response_buf = std.ArrayList(u8).init(ctx.allocator);
    defer response_buf.deinit();

    try configureHttpsTrust(&client, ctx, options.ca_bundle_path);
    const result = client.fetch(.{
        .location = .{ .url = options.url },
        .method = options.method,
        .payload = options.body,
        .headers = .{},
        .extra_headers = options.headers,
        .response_storage = .{ .dynamic = &response_buf },
        .max_append_size = 2 * 1024 * 1024,
        .keep_alive = false,
    }) catch |err| {
        try stderr.print("error: http request failed: {}\n", .{err});
        return 1;
    };

    try stdout.print("status: {d}\n", .{@intFromEnum(result.status)});
    if (response_buf.items.len != 0) {
        try stdout.writeAll(response_buf.items);
        if (response_buf.items[response_buf.items.len - 1] != '\n') try stdout.writeByte('\n');
    }
    return 0;
}

fn runHttpStreamRequest(
    ctx: *const plugin_api.Context,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    options: RequestOptions,
) anyerror!?u8 {
    var client: std.http.Client = .{ .allocator = ctx.allocator };
    defer client.deinit();

    try configureHttpsTrust(&client, ctx, options.ca_bundle_path);
    const uri = try std.Uri.parse(options.url);
    var header_buf: [16 * 1024]u8 = undefined;
    var req = client.open(options.method, uri, .{
        .server_header_buffer = &header_buf,
        .keep_alive = false,
        .headers = .{},
        .extra_headers = options.headers,
    }) catch |err| {
        try stderr.print("error: http stream open failed: {}\n", .{err});
        return 1;
    };
    defer req.deinit();

    req.transfer_encoding = if (options.body) |body| .{ .content_length = body.len } else .none;

    try req.send();
    if (options.body) |body| try req.writeAll(body);
    try req.finish();
    try req.wait();

    var buf: [1024]u8 = undefined;
    while (true) {
        const n = req.read(&buf) catch |err| {
            try stderr.print("error: http stream read failed: {}\n", .{err});
            return 1;
        };
        if (n == 0) break;
        try stdout.writeAll(buf[0..n]);
    }
    return 0;
}

fn runHttpClientCommand(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "http-client")) return null;
    if (argv.len < 4) return error.MissingSourcePath;
    const sub = argv[2];
    if (std.mem.eql(u8, sub, "get")) {
        const parsed = try parseRequestArgs(ctx.allocator, argv[3..], false);
        defer ctx.allocator.free(parsed.headers);
        return try runHttpRequest(ctx, stdout, stderr, .{
            .method = .GET,
            .url = parsed.url,
            .ca_bundle_path = parsed.ca_bundle_path,
            .headers = parsed.headers,
        });
    }
    if (std.mem.eql(u8, sub, "post")) {
        const parsed = try parseRequestArgs(ctx.allocator, argv[3..], true);
        defer ctx.allocator.free(parsed.headers);
        return try runHttpRequest(ctx, stdout, stderr, .{
            .method = .POST,
            .url = parsed.url,
            .ca_bundle_path = parsed.ca_bundle_path,
            .body = parsed.body,
            .headers = parsed.headers,
        });
    }
    if (std.mem.eql(u8, sub, "stream")) {
        const parsed = try parseRequestArgs(ctx.allocator, argv[3..], true);
        defer ctx.allocator.free(parsed.headers);
        return try runHttpStreamRequest(ctx, stdout, stderr, .{
            .method = if (parsed.body != null) .POST else .GET,
            .url = parsed.url,
            .ca_bundle_path = parsed.ca_bundle_path,
            .body = parsed.body,
            .headers = parsed.headers,
        });
    }
    return error.UnknownCommand;
}

fn runHttpClientCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    const args = plugin_helpers.cArgvToSlice(argv, argv_len, ctx.allocator) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer ctx.allocator.free(args);

    var stdout_storage: plugin_helpers.StreamWriterCtx = undefined;
    var stderr_storage: plugin_helpers.StreamWriterCtx = undefined;
    const stdout_writer = plugin_helpers.makeAnyWriter(stdout, &stdout_storage) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const stderr_writer = plugin_helpers.makeAnyWriter(stderr, &stderr_storage) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const result = runHttpClientCommand(ctx, args, stdout_writer, stderr_writer) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

pub const plugin = plugin_api.Plugin{
    .name = "http-client",
    .handleCommand = runHttpClientCommand,
    .skills = &skills,
};

pub const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "http-client",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runHttpClientCommandAbi,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: *const plugin_api.PluginDescriptor = &descriptor;

fn spawnLoopbackServer(allocator: std.mem.Allocator, body: []const u8) !struct {
    thread: std.Thread,
    server: *std.net.Server,
    done: *bool,
} {
    const address = try std.net.Address.parseIp4("127.0.0.1", 0);
    const server = try allocator.create(std.net.Server);
    server.* = try address.listen(.{ .reuse_address = true });

    const done_flag = try allocator.create(bool);
    done_flag.* = false;

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.net.Server, finished: *bool, response_body: []const u8) void {
            defer listen_server.deinit();

            var conn = listen_server.accept() catch return;
            defer conn.stream.close();

            var response_buf: [256]u8 = undefined;
            const response = std.fmt.bufPrint(&response_buf,
                "HTTP/1.1 200 OK\r\ncontent-length: {d}\r\nconnection: close\r\n\r\n{s}",
                .{ response_body.len, response_body },
            ) catch return;
            conn.stream.writeAll(response) catch return;
            finished.* = true;
        }
    }.run, .{ server, done_flag, body });

    return .{ .thread = thread, .server = server, .done = done_flag };
}

test "http client plugin exports runtime descriptor and loopback GET works" {
    const exported = saasm_plugin_descriptor_v1;
    try std.testing.expectEqual(plugin_api.abi_version, exported.abi_version);
    try std.testing.expectEqualStrings("http-client", std.mem.span(exported.name));
    try std.testing.expectEqual(@as(usize, 1), exported.skills_len);
    try std.testing.expectEqualStrings("http client", exported.skills_ptr[0].name);
    try std.testing.expectEqualStrings("http-client get <url>", exported.skills_ptr[0].items[0]);

    const loopback = try spawnLoopbackServer(std.testing.allocator, "hello from loopback");

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const url = try std.fmt.allocPrint(std.testing.allocator, "http://127.0.0.1:{d}/hello", .{loopback.server.listen_address.getPort()});
    defer std.testing.allocator.free(url);

    const args = [_][]const u8{ "sa", "http-client", "get", url };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const code = try runHttpClientCommand(&ctx, args[0..], stdout_buf.writer().any(), stderr_buf.writer().any());

    try std.testing.expectEqual(@as(?u8, 0), code);
    try std.testing.expectEqualStrings("status: 200\nhello from loopback\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);

    loopback.thread.join();
    try std.testing.expect(loopback.done.*);
    std.testing.allocator.destroy(loopback.server);
    std.testing.allocator.destroy(loopback.done);
}

test "http client plugin stream command forwards chunked SSE body incrementally" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const address = try std.net.Address.parseIp4("127.0.0.1", 0);
    const server = try std.testing.allocator.create(std.net.Server);
    server.* = try address.listen(.{ .reuse_address = true });

    const done_flag = try std.testing.allocator.create(bool);
    done_flag.* = false;

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.net.Server, finished: *bool) void {
            defer listen_server.deinit();

            var conn = listen_server.accept() catch return;
            defer conn.stream.close();

            var request_buffer: [4096]u8 = undefined;
            var http_server = std.http.Server.init(conn, &request_buffer);
            const request = http_server.receiveHead() catch return;

            const chunks = [_][]const u8{
                "data: first\n\n",
                "data: second\n\n",
            };
            var response_buf: [256]u8 = undefined;
            var head = std.ArrayListUnmanaged(u8).initBuffer(&response_buf);
            head.fixedWriter().print("HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n", .{}) catch return;
            conn.stream.writeAll(head.items) catch return;
            for (chunks, 0..) |chunk, idx| {
                var chunk_header: [32]u8 = undefined;
                const header = std.fmt.bufPrint(&chunk_header, "{x}\r\n", .{chunk.len}) catch return;
                conn.stream.writeAll(header) catch return;
                conn.stream.writeAll(chunk) catch return;
                conn.stream.writeAll("\r\n") catch return;
                if (idx == 0) std.time.sleep(20 * std.time.ns_per_ms);
            }
            conn.stream.writeAll("0\r\n\r\n") catch return;
            _ = request;
            finished.* = true;
        }
    }.run, .{ server, done_flag });

    const url = try std.fmt.allocPrint(std.testing.allocator, "http://127.0.0.1:{d}/events", .{server.listen_address.getPort()});
    defer std.testing.allocator.free(url);

    const args = [_][]const u8{ "sa", "http-client", "stream", url };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const code = try runHttpClientCommand(&ctx, args[0..], stdout_buf.writer().any(), stderr_buf.writer().any());
    try std.testing.expectEqual(@as(?u8, 0), code);
    try std.testing.expectEqualStrings("data: first\n\ndata: second\n\n", stdout_buf.items);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);

    thread.join();
    try std.testing.expect(done_flag.*);
    std.testing.allocator.destroy(server);
    std.testing.allocator.destroy(done_flag);
}

test "http client plugin custom CA bundle path is accepted by parser" {
    const parsed = try parseRequestArgs(std.testing.allocator, &.{ "https://example.com", "--ca-bundle", "server.crt" }, false);
    try std.testing.expectEqualStrings("https://example.com", parsed.url);
    try std.testing.expectEqualStrings("server.crt", parsed.ca_bundle_path.?);
}

test "http client plugin post command forwards headers and body" {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const address = try std.net.Address.parseIp4("127.0.0.1", 0);
    const server = try std.testing.allocator.create(std.net.Server);
    server.* = try address.listen(.{ .reuse_address = true });
    defer std.testing.allocator.destroy(server);

    const seen_body = try std.testing.allocator.create(bool);
    seen_body.* = false;
    defer std.testing.allocator.destroy(seen_body);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(listen_server: *std.net.Server, finished: *bool) void {
            defer listen_server.deinit();

            var conn = listen_server.accept() catch return;
            defer conn.stream.close();

            var request_buffer: [4096]u8 = undefined;
            var http_server = std.http.Server.init(conn, &request_buffer);
            var request = http_server.receiveHead() catch return;

            var header_seen = false;
            var header_it = request.iterateHeaders();
            while (header_it.next()) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, "content-type") and std.mem.eql(u8, header.value, "text/plain")) {
                    header_seen = true;
                    break;
                }
            }
            if (!header_seen) return;

            var body_buf: [128]u8 = undefined;
            const reader = request.reader() catch return;
            const n = reader.readAll(&body_buf) catch return;
            if (n != "payload body".len) return;
            if (!std.mem.eql(u8, body_buf[0..n], "payload body")) return;

            const response = "ok";
            request.respond(response, .{ .status = .ok }) catch return;
            finished.* = true;
        }
    }.run, .{ server, seen_body });

    const url = try std.fmt.allocPrint(std.testing.allocator, "http://127.0.0.1:{d}/submit", .{server.listen_address.getPort()});
    defer std.testing.allocator.free(url);

    const args = [_][]const u8{
        "sa",
        "http-client",
        "post",
        "--header",
        "content-type: text/plain",
        url,
        "payload body",
    };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };
    const code = try runHttpClientCommand(&ctx, args[0..], stdout_buf.writer().any(), stderr_buf.writer().any());

    try std.testing.expectEqual(@as(?u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "status: 200"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);

    thread.join();
    try std.testing.expect(seen_body.*);
}

test "http client plugin https ca bundle works against a local self-signed server" {
    if (std.http.Client.disable_tls) return error.SkipZigTest;

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const cert_conf =
        \\[req]
        \\distinguished_name = req_distinguished_name
        \\x509_extensions = v3_req
        \\prompt = no
        \\
        \\[req_distinguished_name]
        \\CN = localhost
        \\
        \\[v3_req]
        \\subjectAltName = @alt_names
        \\
        \\[alt_names]
        \\DNS.1 = localhost
        \\IP.1 = 127.0.0.1
    ;
    try std.fs.cwd().writeFile(.{ .sub_path = "cert.cnf", .data = cert_conf });

    const gen = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-sha256",
            "-days",
            "1",
            "-nodes",
            "-keyout",
            "server.key",
            "-out",
            "server.crt",
            "-config",
            "cert.cnf",
            "-extensions",
            "v3_req",
        },
        .cwd = ".",
    });
    defer std.testing.allocator.free(gen.stdout);
    defer std.testing.allocator.free(gen.stderr);
    switch (gen.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }

    var server_child = std.process.Child.init(&.{
        "openssl",
        "s_server",
        "-accept",
        "18443",
        "-cert",
        "server.crt",
        "-key",
        "server.key",
        "-www",
        "-naccept",
        "1",
    }, std.testing.allocator);
    server_child.cwd = ".";
    server_child.stdin_behavior = .Ignore;
    server_child.stdout_behavior = .Ignore;
    server_child.stderr_behavior = .Ignore;
    try server_child.spawn();

    const url = "https://localhost:18443/";
    const ca_bundle = "server.crt";
    const args = [_][]const u8{ "sa", "http-client", "get", "--ca-bundle", ca_bundle, url };
    var ctx = plugin_api.Context{ .allocator = std.testing.allocator };

    var attempt: usize = 0;
    var result_code: ?u8 = null;
    while (attempt < 50) : (attempt += 1) {
        stdout_buf.clearRetainingCapacity();
        stderr_buf.clearRetainingCapacity();
        const code = runHttpClientCommand(&ctx, args[0..], stdout_buf.writer().any(), stderr_buf.writer().any()) catch null;
        if (code) |exit_code| {
            if (exit_code == 0) {
                result_code = exit_code;
                break;
            }
        }
        std.time.sleep(20 * std.time.ns_per_ms);
    }

    const wait_result = try server_child.wait();
    if (result_code == null) {
        std.debug.print("tls stdout:\n{s}\ntls stderr:\n{s}\n", .{ stdout_buf.items, stderr_buf.items });
    }
    try std.testing.expectEqual(@as(?u8, 0), result_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "status: 200\n"));
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
    _ = wait_result;
}
