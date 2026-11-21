const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_client.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("sa_tls_client.zig").SA_STD_ERR_IO;
const SA_STD_ERR_TLS_VERIFY = @import("sa_tls_client.zig").SA_STD_ERR_TLS_VERIFY;
const SA_STD_OK = @import("sa_tls_client.zig").SA_STD_OK;
const builtin = @import("sa_tls_client.zig").builtin;
const sa_std_tls_client_add_ca_file = @import("sa_tls_client.zig").sa_std_tls_client_add_ca_file;
const sa_std_tls_client_close = @import("sa_tls_client.zig").sa_std_tls_client_close;
const sa_std_tls_client_config_add_ca_file = @import("sa_tls_client.zig").sa_std_tls_client_config_add_ca_file;
const sa_std_tls_client_config_add_ca_memory = @import("sa_tls_client.zig").sa_std_tls_client_config_add_ca_memory;
const sa_std_tls_client_config_free = @import("sa_tls_client.zig").sa_std_tls_client_config_free;
const sa_std_tls_client_config_new = @import("sa_tls_client.zig").sa_std_tls_client_config_new;
const sa_std_tls_client_config_set_insecure_no_verification = @import("sa_tls_client.zig").sa_std_tls_client_config_set_insecure_no_verification;
const sa_std_tls_client_config_set_server_name = @import("sa_tls_client.zig").sa_std_tls_client_config_set_server_name;
const sa_std_tls_client_config_set_verify_self_signed = @import("sa_tls_client.zig").sa_std_tls_client_config_set_verify_self_signed;
const sa_std_tls_client_connect = @import("sa_tls_client.zig").sa_std_tls_client_connect;
const sa_std_tls_client_connect_config = @import("sa_tls_client.zig").sa_std_tls_client_connect_config;
const sa_std_tls_client_read = @import("sa_tls_client.zig").sa_std_tls_client_read;
const sa_std_tls_client_start_tls = @import("sa_tls_client.zig").sa_std_tls_client_start_tls;
const sa_std_tls_client_write = @import("sa_tls_client.zig").sa_std_tls_client_write;
const sio = @import("sa_tls_client.zig").sio;
const testing = @import("sa_tls_client.zig").testing;

pub fn makeSelfSignedCert(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, "cert.pem" });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, "key.pem" });
    errdefer allocator.free(key_path);
    // openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 1
    //             -nodes -subj "/CN=localhost"
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path,
        "-out",    cert_path,
        "-days",   "1",   "-nodes", "-subj", "/CN=localhost",
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return error.OpensslSpawnFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslCertFailed,
        else => return error.OpensslCertAbnormal,
    }
    return .{ .cert = cert_path, .key = key_path };
}

pub fn spawnPlainServer(allocator: std.mem.Allocator, cert: []const u8, key: []const u8, port: u16) !sio.Child {
    const accept_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(accept_arg);
    const args = [_][]const u8{
        "openssl", "s_server",
        "-accept", accept_arg,
        "-cert",   cert,
        "-key",    key,
        "-naccept", "1",
        "-quiet",
    };
    var server = sio.Child.init(&args, allocator);
    server.stdin_behavior = .Pipe;
    server.stdout_behavior = .Pipe;
    server.stderr_behavior = .Ignore;
    try server.spawn();
    return server;
}

pub fn freePort() !u16 {
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    listener.deinit(sio.io());
    return port;
}

pub fn connectConfigRetry(host: []const u8, port: u16, cfg: u64) i32 {
    var handle: u64 = 0;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_client_connect_config(host.ptr, host.len, port, cfg, &handle);
        if (rc == SA_STD_OK) {
            _ = sa_std_tls_client_close(handle);
            return SA_STD_OK;
        }
        if (rc != SA_STD_ERR_IO) return rc;
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    return SA_STD_ERR_IO;
}

test "loopback: real handshake vs openssl s_server with CA-pinned verification" {
    // The repo's OpenSSL-backed tls_server FFI cannot dlopen versioned-only
    // libssl symbols on this host, so the loopback peer is the openssl CLI
    // server instead. The client side still goes through the real exported
    // FFI with REAL certificate verification: the self-signed cert is pinned
    // via add_ca_file and the hostname is verified against CN=localhost.
    // No .no_verification anywhere on this path.
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);

    // Pin the self-signed CA into the singleton bundle (real verification).
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_add_ca_file(paths.cert.ptr, paths.cert.len));

    // Grab a free loopback port, then hand it to s_server.
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    listener.deinit(sio.io());

    const accept_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(accept_arg);
    const server_args = [_][]const u8{
        "openssl", "s_server",
        "-accept", accept_arg,
        "-cert",   paths.cert,
        "-key",    paths.key,
        "-naccept", "1",
        "-quiet",
    };
    var server = sio.Child.init(&server_args, allocator);
    server.stdin_behavior = .Pipe;
    server.stdout_behavior = .Pipe;
    server.stderr_behavior = .Ignore;
    try server.spawn();
    errdefer _ = server.kill() catch {};

    // Connect with retries: s_server needs a moment to bind.
    const host = "localhost";
    var handle: u64 = 0;
    var connected = false;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_client_connect(host.ptr, host.len, port, &handle);
        if (rc == SA_STD_OK) {
            connected = true;
            break;
        }
        // Only retry dial-level failures; a -100 here would be a real
        // verification bug and must fail the test, not loop.
        try testing.expectEqual(@as(i32, SA_STD_ERR_IO), rc);
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    try testing.expect(connected);
    try testing.expect(handle != 0);
    errdefer _ = sa_std_tls_client_close(handle);

    // Server -> client: feed s_server's stdin, read it back over TLS.
    const server_msg = "server-hello\n";
    try server.stdin.?.writeAll(server_msg);
    var got_buf: [64]u8 = undefined;
    var got_total: usize = 0;
    while (got_total < server_msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_read(handle, got_buf[got_total..].ptr, got_buf.len - got_total, &n));
        if (n == 0) break; // clean EOF
        got_total += @as(usize, @intCast(n));
    }
    try testing.expectEqualStrings(server_msg, got_buf[0..got_total]);

    // Client -> server: write over TLS, expect it on s_server's stdout.
    const client_msg = "client-ping";
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_write(handle, client_msg.ptr, client_msg.len, &written));
    try testing.expectEqual(@as(u64, client_msg.len), written);

    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_close(handle));

    // -naccept 1: s_server exits once our connection closes; its stdout must
    // carry the plaintext we sent. Read before wait(): wait() closes the
    // stdio pipes (cleanupStreams).
    const echoed = try server.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(echoed);
    const term = try server.wait();
    switch (term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.ServerAbnormalExit,
    }
    try testing.expect(std.mem.indexOf(u8, echoed, client_msg) != null);
}

test "public internet: handshake with example.com:443 against the OS trust store" {
    // Graceful skip when there is no usable network path; a verification
    // failure (-100) is a real bug and fails the test. The HTTP GET after the
    // handshake is best-effort: the handshake itself is the assertion.
    const host = "example.com";
    var handle: u64 = 0;
    const rc = sa_std_tls_client_connect(host.ptr, host.len, 443, &handle);
    if (rc == SA_STD_ERR_IO) return; // no network: skip, don't fail
    try testing.expectEqual(@as(i32, SA_STD_OK), rc);
    defer _ = sa_std_tls_client_close(handle);
    try testing.expect(handle != 0);

    const req = "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    var written: u64 = 0;
    if (sa_std_tls_client_write(handle, req.ptr, req.len, &written) != SA_STD_OK) return;
    if (written != req.len) return;

    var head: [512]u8 = undefined;
    var head_len: usize = 0;
    var total: u64 = 0;
    var buf: [4096]u8 = undefined;
    while (true) {
        var n: u64 = 0;
        if (sa_std_tls_client_read(handle, &buf, buf.len, &n) != SA_STD_OK) return;
        if (n == 0) break; // clean EOF
        const room = head.len - head_len;
        const take: usize = @min(@as(usize, @intCast(n)), room);
        @memcpy(head[head_len..][0..take], buf[0..take]);
        head_len += take;
        total += n;
        if (total > 256 * 1024) break;
    }
    try testing.expect(total > 0);
    try testing.expect(std.mem.indexOf(u8, head[0..head_len], "HTTP/") != null);
}

test "config object: memory CA + server_name override connects by IP; unpinned fails" {
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, paths.cert, 1 << 20);
    defer allocator.free(pem);

    // (1) Per-config memory CA is accepted eagerly.
    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    defer _ = sa_std_tls_client_config_free(cfg);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_add_ca_memory(cfg, pem.ptr, pem.len));
    const sni = "localhost";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_server_name(cfg, sni.ptr, sni.len));

    var port = try freePort();
    var server = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server.kill() catch {};
    // Dial by IP; the certificate names "localhost" only, so this succeeds
    // solely because the config's server_name drives SNI + verification.
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("127.0.0.1", port, cfg));
    _ = server.wait() catch {};

    // (2) The CA-file variant of the same config also connects.
    var cfg2: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg2));
    defer _ = sa_std_tls_client_config_free(cfg2);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_add_ca_file(cfg2, paths.cert.ptr, paths.cert.len));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_server_name(cfg2, sni.ptr, sni.len));
    port = try freePort();
    var server2 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server2.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("127.0.0.1", port, cfg2));
    _ = server2.wait() catch {};

    // (3) No pin at all: the self-signed peer must fail verification (-100),
    // never silently connect.
    port = try freePort();
    var server3 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server3.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_ERR_TLS_VERIFY), connectConfigRetry("localhost", port, 0));
    _ = server3.wait() catch {};
}

test "config object: insecure switch and self-signed mode are separate, conflicts are loud" {
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);

    // Insecure switch alone: connects to the unpinned self-signed server.
    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    defer _ = sa_std_tls_client_config_free(cfg);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_insecure_no_verification(cfg, 1));
    var port = try freePort();
    var server = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("127.0.0.1", port, cfg));
    _ = server.wait() catch {};

    // Self-signed mode (NOT a bypass): also connects, by name.
    var cfg2: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg2));
    defer _ = sa_std_tls_client_config_free(cfg2);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_set_verify_self_signed(cfg2, 1));
    port = try freePort();
    var server2 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server2.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_OK), connectConfigRetry("localhost", port, cfg2));
    _ = server2.wait() catch {};

    // Insecure + server_name is a contradiction (no_verification sends no
    // SNI): loud INVALID_ARGUMENT, not a silent ignore.
    var cfg3: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg3));
    defer _ = sa_std_tls_client_config_free(cfg3);
    _ = sa_std_tls_client_config_set_insecure_no_verification(cfg3, 1);
    const nm = "localhost";
    _ = sa_std_tls_client_config_set_server_name(cfg3, nm.ptr, nm.len);
    port = try freePort();
    var server3 = try spawnPlainServer(allocator, paths.cert, paths.key, port);
    defer _ = server3.kill() catch {};
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), connectConfigRetry("127.0.0.1", port, cfg3));
    _ = server3.wait() catch {};
}

test "start_tls upgrades a plaintext connection after a STARTTLS preamble" {
    if (comptime builtin.os.tag == .windows) return;
    const allocator = std.heap.page_allocator;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, paths.cert, 1 << 20);
    defer allocator.free(pem);

    // Server side: our own OpenSSL tls_server ctx on a listener thread.
    const srv = @import("sa_tls_server.zig");
    var sup: u32 = 0;
    _ = srv.sa_std_tls_server_supported(&sup);
    if (sup == 0) return; // host cannot resolve OpenSSL symbols; nothing to prove against
    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), srv.sa_std_tls_server_ctx_create(paths.cert.ptr, paths.cert.len, paths.key.ptr, paths.key.len, &ctx));
    defer _ = srv.sa_std_tls_server_ctx_free(ctx);

    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    const Arg = struct { ctx: u64, lst: *std.Io.net.Server, accept_rc: i32 = -999 };
    var arg: Arg = .{ .ctx = ctx, .lst = &listener };
    const Runner = struct {
        fn run(a: *Arg) void {
            const tsrv = @import("sa_tls_server.zig");
            var stream = a.lst.accept(sio.io()) catch return;
            defer stream.close(sio.io());
            // Plaintext preamble: read one line BYTE BY BYTE off the raw
            // fd. A buffered reader could swallow ClientHello bytes that
            // already arrived, starving the TLS handshake that follows.
            var line_buf: [16]u8 = undefined;
            var line_len: usize = 0;
            while (line_len < line_buf.len) {
                var b: [1]u8 = undefined;
                const n = std.posix.read(stream.socket.handle, &b) catch return;
                if (n == 0) return;
                line_buf[line_len] = b[0];
                line_len += 1;
                if (b[0] == '\n') break;
            }
            if (!std.mem.eql(u8, line_buf[0..line_len], "STARTTLS\n")) return;
            var ssl: u64 = 0;
            a.accept_rc = tsrv.sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl);
            if (a.accept_rc != 0) return;
            var buf: [64]u8 = undefined;
            var n: u64 = 0;
            if (tsrv.sa_std_tls_server_read(ssl, &buf, buf.len, &n) == 0) {
                _ = tsrv.sa_std_tls_server_write(ssl, &buf, n, &n);
            }
            _ = tsrv.sa_std_tls_server_close(ssl);
        }
    };
    var thread = try std.Thread.spawn(.{}, Runner.run, .{&arg});

    // Client side: plain TCP, preamble, then upgrade in place.
    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
    var plain = try addr.connect(sio.io(), .{ .mode = .stream });
    var wb: [64]u8 = undefined;
    var wr = plain.writer(sio.io(), &wb);
    try wr.interface.writeAll("STARTTLS\n");
    try wr.interface.flush();

    var cfg: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_new(&cfg));
    defer _ = sa_std_tls_client_config_free(cfg);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_config_add_ca_memory(cfg, pem.ptr, pem.len));

    const host = "localhost";
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_start_tls(plain.socket.handle, host.ptr, host.len, cfg, &handle));
    try testing.expect(handle != 0);

    const msg = "post-upgrade-ping";
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_write(handle, msg.ptr, msg.len, &written));
    try testing.expectEqual(@as(u64, msg.len), written);
    var echo: [64]u8 = undefined;
    var got: usize = 0;
    while (got < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_read(handle, echo[got..].ptr, echo.len - got, &n));
        if (n == 0) break;
        got += @intCast(n);
    }
    try testing.expectEqualStrings(msg, echo[0..got]);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_close(handle));
    thread.join();
    try testing.expectEqual(@as(i32, 0), arg.accept_rc);
}

test "start_tls returns an error on a non-socket fd instead of aborting" {
    if (comptime builtin.os.tag == .windows) return;
    // DEF-SCI-TLS-STARTTLS-NONSOCKET-ABORT: a non-socket fd (here stdin,
    // the exact shape the wrap smoke test hits) used to make the
    // handshake abort (SIGABRT, NOTSOCK). It must return an error code.
    const host = "localhost";
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_start_tls(0, host.ptr, host.len, 0, &handle));
    try testing.expectEqual(@as(u64, 0), handle);
}
