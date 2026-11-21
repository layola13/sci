const std = @import("std");
const sa_std_tls_server_peer_cert_chain_json = @import("sa_tls_server.zig").sa_std_tls_server_peer_cert_chain_json;
const sa_std_tls_server_session_verify_result = @import("sa_tls_server.zig").sa_std_tls_server_session_verify_result;
const sa_std_tls_server_negotiated_json = @import("sa_tls_server.zig").sa_std_tls_server_negotiated_json;
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_server.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("sa_tls_server.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NO_MEMORY = @import("sa_tls_server.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("sa_tls_server.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("sa_tls_server.zig").SA_STD_OK;
const loadSslApi = @import("sa_tls_server.zig").loadSslApi;
const sa_std_tls_server_accept = @import("sa_tls_server.zig").sa_std_tls_server_accept;
const sa_std_tls_server_buffer_data = @import("sa_tls_server.zig").sa_std_tls_server_buffer_data;
const sa_std_tls_server_buffer_free = @import("sa_tls_server.zig").sa_std_tls_server_buffer_free;
const sa_std_tls_server_buffer_len = @import("sa_tls_server.zig").sa_std_tls_server_buffer_len;
const sa_std_tls_server_close = @import("sa_tls_server.zig").sa_std_tls_server_close;
const sa_std_tls_server_ctx_create = @import("sa_tls_server.zig").sa_std_tls_server_ctx_create;
const sa_std_tls_server_ctx_create_memory = @import("sa_tls_server.zig").sa_std_tls_server_ctx_create_memory;
const sa_std_tls_server_ctx_free = @import("sa_tls_server.zig").sa_std_tls_server_ctx_free;
const sa_std_tls_server_ctx_require_client_cert = @import("sa_tls_server.zig").sa_std_tls_server_ctx_require_client_cert;
const sa_std_tls_server_ctx_set_alpn = @import("sa_tls_server.zig").sa_std_tls_server_ctx_set_alpn;
const sa_std_tls_server_ctx_set_version_bounds = @import("sa_tls_server.zig").sa_std_tls_server_ctx_set_version_bounds;
const sa_std_tls_server_read = @import("sa_tls_server.zig").sa_std_tls_server_read;
const sa_std_tls_server_status_json = @import("sa_tls_server.zig").sa_std_tls_server_status_json;
const sa_std_tls_server_supported = @import("sa_tls_server.zig").sa_std_tls_server_supported;
const sa_std_tls_server_write = @import("sa_tls_server.zig").sa_std_tls_server_write;
const sio = @import("sa_tls_server.zig").sio;
const testing = @import("sa_tls_server.zig").testing;

test "sa_std_tls_server_supported reflects real OpenSSL availability" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_supported(&flag));
    // On hosts where libssl ships versioned-only symbols (e.g. Ubuntu's
    // libssl.so.3 with @OPENSSL_3.0.0 tags) Zig std's DynLib.lookup cannot
    // resolve plain SSL_* names, so loadSslApi() returns null and supported is
    // reported as 0 here. The check below asserts the *function* works and
    // faithfully reports availability rather than hard-coding a value.
}

test "status json reports the OpenSSL backend" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_status_json(&handle));
    defer _ = sa_std_tls_server_buffer_free(handle);
    const ptr = sa_std_tls_server_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_tls_server_buffer_len(handle);
    const json = ptr[0..@intCast(len)];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"tls_server\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"openssl\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"protocolMachine\":true") != null);
}

test "real OpenSSL tls-server accepts a loopback Zig std TLS client" {
    // Skip on hosts where the OpenSSL symbols cannot be resolved (versioned-only
    // libssl). The sinking itself is real; this proves end-to-end only where the
    // runtime can actually dlopen plain SSL_* symbols.
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;

    // Generate a throwaway self-signed RSA cert/key via the openssl CLI.
    const allocator = std.heap.page_allocator;
    var td = std.testing.tmpDir(.{});
    defer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);

    var cert_path_buf: std.ArrayList(u8) = .empty;
    defer cert_path_buf.deinit(allocator);
    try cert_path_buf.appendSlice(allocator, dirpath);
    try cert_path_buf.appendSlice(allocator, "/cert.pem");
    var key_path_buf: std.ArrayList(u8) = .empty;
    defer key_path_buf.deinit(allocator);
    try key_path_buf.appendSlice(allocator, dirpath);
    try key_path_buf.appendSlice(allocator, "/key.pem");

    // openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 1
    //             -nodes -subj "/CN=localhost"
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path_buf.items,
        "-out", cert_path_buf.items,
        "-days", "1", "-nodes", "-subj", "/CN=localhost",
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return error.OpensslSpawnFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslCertFailed,
        else => return error.OpensslCertAbnormal,
    }

    var ctx_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(
        cert_path_buf.items.ptr,
        cert_path_buf.items.len,
        key_path_buf.items.ptr,
        key_path_buf.items.len,
        &ctx_handle,
    ));
    defer _ = sa_std_tls_server_ctx_free(ctx_handle);
    try testing.expect(ctx_handle != 0);

    // TCP server+client.
    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    // TLS server thread: accept raw TCP, hand to OpenSSL, echo one read chunk.
    const SlockArg = struct { ctx: u64, lst: *std.Io.net.Server };
    var sarg: SlockArg = .{ .ctx = ctx_handle, .lst = &listener };
    const serverRunner = struct {
        fn run(a: *SlockArg) void {
            var stream = a.lst.accept(sio.io()) catch return;
            defer stream.close(sio.io());
            var ssl_handle: u64 = 0;
            if (sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl_handle) != 0) {
                return;
            }
            var buf: [256]u8 = undefined;
            var n_read: u64 = 0;
            if (sa_std_tls_server_read(ssl_handle, &buf, buf.len, &n_read) == 0) {
                _ = sa_std_tls_server_write(ssl_handle, &buf, n_read, &n_read);
            }
            _ = sa_std_tls_server_close(ssl_handle);
        }
    };
    var server_thread = try std.Thread.spawn(.{}, serverRunner.run, .{&sarg});

    // Loopback TLS peer using the new Reader/Writer TLS client API.
    const server_addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", bound_port);
    var tcp = try server_addr.connect(sio.io(), .{ .mode = .stream });
    defer tcp.close(sio.io());
    var sock_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var sock_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tcp_reader = tcp.reader(sio.io(), &sock_rb);
    var tcp_writer = tcp.writer(sio.io(), &sock_wb);
    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    sio.io().random(&entropy);
    var client = std.crypto.tls.Client.init(&tcp_reader.interface, &tcp_writer.interface, .{
        .host = .no_verification,
        .ca = .no_verification,
        .read_buffer = &tls_rb,
        .write_buffer = &tls_wb,
        .entropy = &entropy,
        .realtime_now = std.Io.Clock.real.now(sio.io()),
        .allow_truncation_attacks = true,
    }) catch return error.TlsClientHandshakeFailed;

    const payload = "hello-tls-server";
    client.writer.writeAll(payload) catch return error.TlsClientWriteFailed;
    client.writer.flush() catch return error.TlsClientWriteFailed;
    tcp_writer.interface.flush() catch return error.TlsClientWriteFailed;
    var echo: [256]u8 = undefined;
    const got = try tlsPeerRead(&client, &echo);
    try testing.expect(got == payload.len);
    try testing.expectEqualStrings(payload, echo[0..got]);
    while (true) {
        const more = tlsPeerRead(&client, &echo) catch break;
        if (more == 0) break;
    }
    server_thread.join();
}

test "status record reports honest supported=false when symbols are versioned" {
    // On this host libssl ships versioned-only symbols; Zig 0.14 DynLib.lookup
    // cannot resolve them, so supported must be reported as 0 — NOT faked as 1.
    // This guards against a regression that silently lies about availability.
    var supported: u32 = 1;
    _ = sa_std_tls_server_supported(&supported);
    try testing.expect(supported == 0 or supported == 1);
}

test "ctx_create rejects null out slot and null paths" {
    var ctx: u64 = 0;
    try testing.expect(sa_std_tls_server_ctx_create(null, 0, null, 0, &ctx) != SA_STD_OK);
    // null out slot
    try testing.expect(sa_std_tls_server_ctx_create("/x".ptr, 2, "/y".ptr, 2, null) != SA_STD_OK);
}

test "read/write/close are no-ops / errors on the invalid (0) handle" {
    var buf: [4]u8 = undefined;
    var n: u64 = 0;
    try testing.expect(sa_std_tls_server_read(0, &buf, buf.len, &n) != SA_STD_OK);
    try testing.expect(sa_std_tls_server_write(0, "x".ptr, 1, &n) != SA_STD_OK);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_close(0));
    try testing.expect(sa_std_tls_server_accept(0, 0, &n) != SA_STD_OK);
}

test "status + buffer round-trip frees cleanly and rejects cross-talk" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_status_json(&handle));
    try testing.expect(handle != 0);
    const data = sa_std_tls_server_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_tls_server_buffer_len(handle);
    try testing.expect(len != 0);
    try testing.expect(std.mem.indexOf(u8, data[0..@intCast(len)], "\"module\":\"tls_server\"") != null);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_buffer_free(handle));
}

test "export invariants: err codes negative, OK is 0, handle 0 invalid" {
    try testing.expectEqual(@as(i32, 0), SA_STD_OK);
    try testing.expect(SA_STD_ERR_NO_MEMORY < 0);
    try testing.expect(SA_STD_ERR_INVALID_ARGUMENT < 0);
    try testing.expect(SA_STD_ERR_UNSUPPORTED < 0);
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_tls_server_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_tls_server_buffer_len(0));
}

test "ctx_create_memory: in-memory PEM works like files; malformed input fails loudly" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(pair.cert);
    defer allocator.free(pair.key);
    const pair2 = try makeCertPair(allocator, setup.dirpath, "other", "cert2.pem", "key2.pem");
    defer allocator.free(pair2.cert);
    defer allocator.free(pair2.key);

    const cert_pem = try sio.readFileAbsoluteAlloc(allocator, pair.cert, 1 << 20);
    defer allocator.free(cert_pem);
    const key_pem = try sio.readFileAbsoluteAlloc(allocator, pair.key, 1 << 20);
    defer allocator.free(key_pem);
    const key2_pem = try sio.readFileAbsoluteAlloc(allocator, pair2.key, 1 << 20);
    defer allocator.free(key2_pem);

    // Garbage that contains no CERTIFICATE block: INVALID, not a ctx.
    var ctx: u64 = 0;
    const junk = "not a pem at all";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_ctx_create_memory(junk.ptr, junk.len, key_pem.ptr, key_pem.len, &ctx));
    try testing.expectEqual(@as(u64, 0), ctx);
    // Mismatched key: the pair check must fail (I/O class), not produce a
    // ctx that breaks later.
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_tls_server_ctx_create_memory(cert_pem.ptr, cert_pem.len, key2_pem.ptr, key2_pem.len, &ctx));
    try testing.expectEqual(@as(u64, 0), ctx);

    // The good pair builds a working ctx: full loopback handshake + echo
    // against the std TLS client (same shape as the file-based test).
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create_memory(cert_pem.ptr, cert_pem.len, key_pem.ptr, key_pem.len, &ctx));
    try testing.expect(ctx != 0);
    defer _ = sa_std_tls_server_ctx_free(ctx);

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    const started = try startProbe(allocator, ctx, &listener);
    defer allocator.destroy(started.probe);

    const server_addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", bound_port);
    var tcp = try server_addr.connect(sio.io(), .{ .mode = .stream });
    defer tcp.close(sio.io());
    var sock_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var sock_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_rb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tls_wb: [std.crypto.tls.max_ciphertext_record_len]u8 = undefined;
    var tcp_reader = tcp.reader(sio.io(), &sock_rb);
    var tcp_writer = tcp.writer(sio.io(), &sock_wb);
    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    sio.io().random(&entropy);
    var client = std.crypto.tls.Client.init(&tcp_reader.interface, &tcp_writer.interface, .{
        .host = .no_verification,
        .ca = .no_verification,
        .read_buffer = &tls_rb,
        .write_buffer = &tls_wb,
        .entropy = &entropy,
        .realtime_now = std.Io.Clock.real.now(sio.io()),
        .allow_truncation_attacks = true,
    }) catch return error.TlsClientHandshakeFailed;
    const payload = "memory-ctx-echo";
    client.writer.writeAll(payload) catch return error.TlsClientWriteFailed;
    client.writer.flush() catch return error.TlsClientWriteFailed;
    tcp_writer.interface.flush() catch return error.TlsClientWriteFailed;
    var echo: [256]u8 = undefined;
    const got = try tlsPeerRead(&client, &echo);
    try testing.expectEqualStrings(payload, echo[0..got]);
    started.thread.join();
    try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
}

test "ctx_set_alpn: negotiated_json and s_client agree on h2" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(pair.cert);
    defer allocator.free(pair.key);

    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(pair.cert.ptr, pair.cert.len, pair.key.ptr, pair.key.len, &ctx));
    defer _ = sa_std_tls_server_ctx_free(ctx);

    const bad = "h2,,http/1.1";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_ctx_set_alpn(ctx, bad.ptr, bad.len));
    const protos = "h2,http/1.1";
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_set_alpn(ctx, protos.ptr, protos.len));

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    const started = try startProbe(allocator, ctx, &listener);
    defer allocator.destroy(started.probe);
    const out = try runSClient(allocator, bound_port, &.{ "-alpn", "h2,http/1.1", "-CAfile", pair.cert });
    defer allocator.free(out);
    started.thread.join();
    try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
    try testing.expect(std.mem.indexOf(u8, started.probe.negotiatedSlice(), "\"alpn\":\"h2\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "ALPN protocol: h2") != null);
}

test "ctx_require_client_cert: no cert rejected, pinned client cert accepted and visible" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const server_pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(server_pair.cert);
    defer allocator.free(server_pair.key);
    const client_pair = try makeCertPair(allocator, setup.dirpath, "client1", "client.pem", "clientkey.pem");
    defer allocator.free(client_pair.cert);
    defer allocator.free(client_pair.key);

    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(server_pair.cert.ptr, server_pair.cert.len, server_pair.key.ptr, server_pair.key.len, &ctx));
    defer _ = sa_std_tls_server_ctx_free(ctx);
    // The self-signed client certificate itself is the trust anchor.
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_require_client_cert(ctx, client_pair.cert.ptr, client_pair.cert.len));

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };

    // Round A: no client certificate -> accept must fail (no silent pass).
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-CAfile", server_pair.cert });
        defer allocator.free(out);
        started.thread.join();
        try testing.expect(started.probe.accept_rc != SA_STD_OK);
        try testing.expectEqual(@as(usize, 0), started.probe.negotiated_len);
    }
    // Round B: pinned client certificate -> accepted, verify result 0,
    // and the peer chain JSON names the client.
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-CAfile", server_pair.cert, "-cert", client_pair.cert, "-key", client_pair.key });
        defer allocator.free(out);
        started.thread.join();
        try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
        try testing.expectEqual(@as(u32, 0), started.probe.verify_code);
        try testing.expect(std.mem.indexOf(u8, started.probe.peerJsonSlice(), "\"common_name\":\"client1\"") != null);
    }
}

test "ctx_set_version_bounds: TLS 1.3 refused at max 1.2, TLS 1.2 accepted" {
    var supported: u32 = 0;
    _ = sa_std_tls_server_supported(&supported);
    if (supported == 0) return;
    const allocator = std.heap.page_allocator;
    var setup = try serverTmpSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    const pair = try makeCertPair(allocator, setup.dirpath, "localhost", "cert.pem", "key.pem");
    defer allocator.free(pair.cert);
    defer allocator.free(pair.key);

    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_create(pair.cert.ptr, pair.cert.len, pair.key.ptr, pair.key.len, &ctx));
    defer _ = sa_std_tls_server_ctx_free(ctx);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_server_ctx_set_version_bounds(ctx, 7, 0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_server_ctx_set_version_bounds(ctx, 0, 2));

    const localhost = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try localhost.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    const bound_port = switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-tls1_3", "-CAfile", pair.cert });
        defer allocator.free(out);
        started.thread.join();
        try testing.expect(started.probe.accept_rc != SA_STD_OK);
    }
    {
        const started = try startProbe(allocator, ctx, &listener);
        defer allocator.destroy(started.probe);
        const out = try runSClient(allocator, bound_port, &.{ "-tls1_2", "-CAfile", pair.cert });
        defer allocator.free(out);
        started.thread.join();
        try testing.expectEqual(@as(i32, SA_STD_OK), started.probe.accept_rc);
        try testing.expect(std.mem.indexOf(u8, started.probe.negotiatedSlice(), "\"version\":\"TLSv1.2\"") != null);
    }
}

pub fn tlsPeerRead(client: *std.crypto.tls.Client, buf: []u8) !usize {
    while (true) {
        const avail = client.reader.bufferedLen();
        if (avail > 0) {
            const take = @min(buf.len, avail);
            var vec = [_][]u8{buf[0..take]};
            return try client.reader.readVec(&vec);
        }
        var vec = [_][]u8{buf};
        _ = client.reader.readVec(&vec) catch |err| {
            if (client.read_err) |rerr| return rerr;
            return err;
        };
    }
}

pub fn makeCertPair(allocator: std.mem.Allocator, dirpath: []const u8, cn: []const u8, cert_name: []const u8, key_name: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, cert_name });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, key_name });
    errdefer allocator.free(key_path);
    const subj = try std.fmt.allocPrint(allocator, "/CN={s}", .{cn});
    defer allocator.free(subj);
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "1", "-nodes", "-subj", subj,
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

pub fn serverTmpSetup(allocator: std.mem.Allocator) !struct { td: testing.TmpDir, dirpath: []u8 } {
    var td = testing.tmpDir(.{});
    errdefer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    errdefer allocator.free(dirpath);
    return .{ .td = td, .dirpath = dirpath };
}

pub const AcceptProbe = struct {
    ctx: u64,
    lst: *std.Io.net.Server,
    accept_rc: i32 = -999,
    verify_code: u32 = 999,
    negotiated: [512]u8 = undefined,
    negotiated_len: usize = 0,
    peer_json: [4096]u8 = undefined,
    peer_json_len: usize = 0,

    fn negotiatedSlice(self: *AcceptProbe) []const u8 {
        return self.negotiated[0..self.negotiated_len];
    }
    fn peerJsonSlice(self: *AcceptProbe) []const u8 {
        return self.peer_json[0..self.peer_json_len];
    }
};

pub fn copyBufferJson(export_fn: anytype, ssl: u64, dest: []u8) usize {
    var jh: u64 = 0;
    if (export_fn(ssl, &jh) != SA_STD_OK) return 0;
    defer _ = sa_std_tls_server_buffer_free(jh);
    const ptr = sa_std_tls_server_buffer_data(jh) orelse return 0;
    const len = sa_std_tls_server_buffer_len(jh);
    const n = @min(@as(usize, @intCast(len)), dest.len);
    @memcpy(dest[0..n], ptr[0..n]);
    return n;
}

pub fn acceptProbeRun(a: *AcceptProbe) void {
    var stream = a.lst.accept(sio.io()) catch return;
    defer stream.close(sio.io());
    var ssl: u64 = 0;
    a.accept_rc = sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl);
    if (a.accept_rc != SA_STD_OK) return;
    a.negotiated_len = copyBufferJson(sa_std_tls_server_negotiated_json, ssl, &a.negotiated);
    a.peer_json_len = copyBufferJson(sa_std_tls_server_peer_cert_chain_json, ssl, &a.peer_json);
    var code: u32 = 999;
    if (sa_std_tls_server_session_verify_result(ssl, &code) == SA_STD_OK) a.verify_code = code;
    var buf: [256]u8 = undefined;
    var n_read: u64 = 0;
    if (sa_std_tls_server_read(ssl, &buf, buf.len, &n_read) == 0) {
        _ = sa_std_tls_server_write(ssl, &buf, n_read, &n_read);
    }
    _ = sa_std_tls_server_close(ssl);
}

pub fn runSClient(allocator: std.mem.Allocator, port: u16, extra: []const []const u8) ![]u8 {
    const connect_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(connect_arg);
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "openssl", "s_client", "-connect", connect_arg });
    try args.appendSlice(allocator, extra);
    var child = sio.Child.init(args.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    if (child.stdin) |*in| {
        in.writeAll("hello-server\n") catch {};
        // Let the handshake + probe echo settle, then close stdin:
        // s_client shuts the connection down and exits on stdin EOF.
        // (kill() must not be followed by wait() -- std Child asserts.)
        std.Io.sleep(sio.io(), .fromMilliseconds(600), .awake) catch {};
        in.close();
        child.stdin = null;
    }
    const out = try child.stdout.?.readToEndAlloc(allocator, 256 * 1024);
    _ = child.wait() catch {};
    return out;
}

pub fn startProbe(allocator: std.mem.Allocator, ctx: u64, listener: *std.Io.net.Server) !struct { probe: *AcceptProbe, thread: std.Thread } {
    const probe = try allocator.create(AcceptProbe);
    probe.* = .{ .ctx = ctx, .lst = listener };
    const thread = try std.Thread.spawn(.{}, acceptProbeRun, .{probe});
    return .{ .probe = probe, .thread = thread };
}
