const std = @import("std");
const sa_std_tls_shaped_negotiated_json = @import("sa_tls_shaped.zig").sa_std_tls_shaped_negotiated_json;
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_shaped.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("sa_tls_shaped.zig").SA_STD_ERR_IO;
const SA_STD_ERR_TLS_VERIFY = @import("sa_tls_shaped.zig").SA_STD_ERR_TLS_VERIFY;
const SA_STD_ERR_UNSUPPORTED = @import("sa_tls_shaped.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("sa_tls_shaped.zig").SA_STD_OK;
const builtin = @import("sa_tls_shaped.zig").builtin;
const sa_std_tls_shaped_buffer_data = @import("sa_tls_shaped.zig").sa_std_tls_shaped_buffer_data;
const sa_std_tls_shaped_buffer_free = @import("sa_tls_shaped.zig").sa_std_tls_shaped_buffer_free;
const sa_std_tls_shaped_buffer_len = @import("sa_tls_shaped.zig").sa_std_tls_shaped_buffer_len;
const sa_std_tls_shaped_close = @import("sa_tls_shaped.zig").sa_std_tls_shaped_close;
const sa_std_tls_shaped_connect = @import("sa_tls_shaped.zig").sa_std_tls_shaped_connect;
const sa_std_tls_shaped_hello_ja3 = @import("sa_tls_shaped.zig").sa_std_tls_shaped_hello_ja3;
const sa_std_tls_shaped_hello_ja3_string = @import("sa_tls_shaped.zig").sa_std_tls_shaped_hello_ja3_string;
const sa_std_tls_shaped_hello_ja4 = @import("sa_tls_shaped.zig").sa_std_tls_shaped_hello_ja4;
const sa_std_tls_shaped_peer_cert_chain_json = @import("sa_tls_shaped.zig").sa_std_tls_shaped_peer_cert_chain_json;
const sa_std_tls_shaped_read = @import("sa_tls_shaped.zig").sa_std_tls_shaped_read;
const sa_std_tls_shaped_session_blob = @import("sa_tls_shaped.zig").sa_std_tls_shaped_session_blob;
const sa_std_tls_shaped_start_tls = @import("sa_tls_shaped.zig").sa_std_tls_shaped_start_tls;
const sa_std_tls_shaped_supported = @import("sa_tls_shaped.zig").sa_std_tls_shaped_supported;
const sa_std_tls_shaped_write = @import("sa_tls_shaped.zig").sa_std_tls_shaped_write;
const sio = @import("sa_tls_shaped.zig").sio;
const testing = @import("sa_tls_shaped.zig").testing;

test "supported reports the dlopen result and validates the slot" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_supported(&flag));
    try testing.expect(flag == 0 or flag == 1);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_supported(null));
}

test "profile validation rejects bad documents before any dial" {
    if (!sslAvailable()) return;
    const host = "127.0.0.1";
    var h: u64 = 0;
    // unknown key
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"bogus\":1}".ptr, 11, &h));
    // grease is honestly unsupported on the OpenSSL backend
    try testing.expectEqual(@as(i32, SA_STD_ERR_UNSUPPORTED), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"grease\":true}".ptr, 15, &h));
    // unknown preset
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"preset\":\"netscape\"}".ptr, 21, &h));
    // unknown version
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{\"min_version\":\"1.9\"}".ptr, 22, &h));
    // malformed JSON
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{oops".ptr, 5, &h));
    // valid empty profile, dead port -> dial error, handle stays 0
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_tls_shaped_connect(host.ptr, host.len, 1, "{}".ptr, 2, &h));
    try testing.expectEqual(@as(u64, 0), h);
    // bad host/port arguments
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(host.ptr, host.len, 0, null, 0, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect(null, 0, 443, null, 0, &h));
}

test "loopback: chrome preset handshake, echo, negotiated + ja3/ja4 from captured hello" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);

    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
    const profile = try std.fmt.allocPrint(allocator, "{{\"preset\":\"chrome\",\"ca_file\":\"{s}\"}}", .{setup.cert});
    defer allocator.free(profile);

    const rc = connectRetry(port, profile);
    try testing.expect(rc > 0);
    const handle: u64 = @intCast(rc);
    // NOTE: no deferred close for this handle -- the success path below
    // closes it explicitly (the server only exits, closing its stdout,
    // once the connection closes), and shaped handles are raw pointers:
    // a second close is a use-after-free, not an error. The double
    // close stayed latent while the JA4 expectation failed first; with
    // that fixed it segfaulted intermittently in close/shutdown.

    // negotiated values
    var jbuf: [512]u8 = undefined;
    const json = try negotiatedJson(handle, &jbuf);
    try testing.expect(std.mem.indexOf(u8, json, "\"version\":\"TLSv1.3\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"alpn\":\"\"") != null);

    // JA3 computed from the captured ClientHello: TLS1.3 suites lead.
    var ja3s_buf: [2048]u8 = undefined;
    var ja3s_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3_string(handle, &ja3s_buf, ja3s_buf.len, &ja3s_len));
    const ja3s = ja3s_buf[0..@intCast(ja3s_len)];
    try testing.expect(std.mem.startsWith(u8, ja3s, "771,"));
    try testing.expect(std.mem.indexOf(u8, ja3s, "4865-4866-4867") != null);
    var ja3_buf: [64]u8 = undefined;
    var ja3_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3(handle, &ja3_buf, ja3_buf.len, &ja3_len));
    try testing.expectEqual(@as(u64, 32), ja3_len);
    var ja4_buf: [128]u8 = undefined;
    var ja4_len: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja4(handle, &ja4_buf, ja4_buf.len, &ja4_len));
    const ja4 = ja4_buf[0..@intCast(ja4_len)];
    try testing.expect(std.mem.startsWith(u8, ja4, "t13d"));
    try testing.expectEqual(@as(usize, 36), ja4.len);

    // echo: server stdin -> TLS -> us; our write -> server stdout
    const msg = "shaped-hello\n";
    try server.stdin.?.writeAll(msg);
    var got: [64]u8 = undefined;
    var total: usize = 0;
    while (total < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_read(handle, got[total..].ptr, got.len - total, &n));
        if (n == 0) break;
        total += @intCast(n);
    }
    try testing.expectEqualStrings(msg, got[0..total]);
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_write(handle, "ping-back".ptr, 9, &written));
    try testing.expectEqual(@as(u64, 9), written);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_close(handle));

    const echoed = try server.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(echoed);
    const term = try server.wait();
    switch (term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.ServerAbnormalExit,
    }
    try testing.expect(std.mem.indexOf(u8, echoed, "ping-back") != null);
}

test "loopback: ciphersuite restriction, alpn selection, version cap, ja3 order sensitivity" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);

    // --- restricted TLS1.3 suite + ciphersuite order changes the JA3 ---
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "2", "-alpn", "h2" });
        defer _ = server.kill() catch {};

        const p1 = try std.fmt.allocPrint(allocator, "{{\"ca_file\":\"{s}\",\"ciphersuites\":\"TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256\",\"alpn\":[\"h2\"]}}", .{setup.cert});
        defer allocator.free(p1);
        const rc1 = connectRetry(port, p1);
        try testing.expect(rc1 > 0);
        const h1: u64 = @intCast(rc1);
        var jbuf: [512]u8 = undefined;
        const json = try negotiatedJson(h1, &jbuf);
        try testing.expect(std.mem.indexOf(u8, json, "\"cipher\":\"TLS_AES_256_GCM_SHA384\"") != null);
        try testing.expect(std.mem.indexOf(u8, json, "\"alpn\":\"h2\"") != null);
        var s1: [2048]u8 = undefined;
        var l1: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3_string(h1, &s1, s1.len, &l1));
        try testing.expect(std.mem.indexOf(u8, s1[0..@intCast(l1)], "4866-4865") != null);
        _ = sa_std_tls_shaped_close(h1);

        const p2 = try std.fmt.allocPrint(allocator, "{{\"ca_file\":\"{s}\",\"ciphersuites\":\"TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384\",\"alpn\":[\"h2\"]}}", .{setup.cert});
        defer allocator.free(p2);
        const rc2 = connectRetry(port, p2);
        try testing.expect(rc2 > 0);
        const h2: u64 = @intCast(rc2);
        var s2: [2048]u8 = undefined;
        var l2: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_hello_ja3_string(h2, &s2, s2.len, &l2));
        try testing.expect(std.mem.indexOf(u8, s2[0..@intCast(l2)], "4865-4866") != null);
        try testing.expect(!std.mem.eql(u8, s1[0..@intCast(l1)], s2[0..@intCast(l2)]));
        _ = sa_std_tls_shaped_close(h2);
        _ = try server.wait();
    }

    // --- max_version 1.2 negotiates TLS 1.2 with an ECDHE suite ---
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const profile = try std.fmt.allocPrint(allocator, "{{\"preset\":\"chrome\",\"ca_file\":\"{s}\",\"max_version\":\"1.2\"}}", .{setup.cert});
        defer allocator.free(profile);
        const rc = connectRetry(port, profile);
        try testing.expect(rc > 0);
        const handle: u64 = @intCast(rc);
        var jbuf: [512]u8 = undefined;
        const json = try negotiatedJson(handle, &jbuf);
        try testing.expect(std.mem.indexOf(u8, json, "\"version\":\"TLSv1.2\"") != null);
        try testing.expect(std.mem.indexOf(u8, json, "ECDHE") != null);
        _ = sa_std_tls_shaped_close(handle);
        _ = try server.wait();
    }
}

test "profile validation: session blob and key conflicts are rejected before dialing" {
    if (!sslAvailable()) return;
    // Nothing listens on port 1; a profile error must surface as
    // INVALID_ARGUMENT before any connection attempt (an IO error here
    // would mean validation ran after dialing).
    const bad_session = "{\"session\":\"!!!not-base64!!!\"}";
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect("127.0.0.1", 9, 1, bad_session.ptr, bad_session.len, &h));
    const both_ca = "{\"ca_file\":\"/tmp/x.pem\",\"ca_pem\":\"y\"}";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect("127.0.0.1", 9, 1, both_ca.ptr, both_ca.len, &h));
    const half_cert = "{\"cert_file\":\"/tmp/x.pem\"}";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_shaped_connect("127.0.0.1", 9, 1, half_cert.ptr, half_cert.len, &h));
}

test "loopback: ca_pem + sni override verifies by IP; wrong CA fails; insecure is explicit" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    // A second, unrelated cert serves as the "wrong CA".
    var td2 = testing.tmpDir(.{});
    defer td2.cleanup();
    const tdir2 = sio.Dir{ .inner = td2.dir };
    const dirpath2 = try tdir2.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath2);
    const other = try makeCert(allocator, dirpath2);
    defer allocator.free(other.cert);
    defer allocator.free(other.key);
    const other_pem = try sio.readFileAbsoluteAlloc(allocator, other.cert, 1 << 20);
    defer allocator.free(other_pem);

    // (1) ca_pem pins trust, sni names the peer: dial by IP, verify as
    // "localhost".
    {
        const profile = try profileJson(allocator, .{ .sni = "localhost", .ca_pem = pem });
        defer allocator.free(profile);
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const h = connectRetryProfile("127.0.0.1", port, profile);
        try testing.expect(h > 0);
        try shapedServerRoundTrip(allocator, &server, @intCast(h));
        _ = server.wait() catch {};
    }
    // (2) Wrong CA in ca_pem: explicit verification failure, no fallback.
    {
        const profile = try profileJson(allocator, .{ .sni = "localhost", .ca_pem = other_pem });
        defer allocator.free(profile);
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        try testing.expectEqual(@as(i64, SA_STD_ERR_TLS_VERIFY), connectRetryProfile("127.0.0.1", port, profile));
        _ = server.wait() catch {};
    }
    // (3) Default profile (full verification, system store): the
    // self-signed peer fails.
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        try testing.expectEqual(@as(i64, SA_STD_ERR_TLS_VERIFY), connectRetryProfile("127.0.0.1", port, "{}"));
        _ = server.wait() catch {};
    }
    // (4) The explicitly named insecure switch connects.
    {
        const port = try freePort();
        var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
        defer _ = server.kill() catch {};
        const h = connectRetryProfile("127.0.0.1", port, "{\"insecure_skip_verify\":true}");
        try testing.expect(h > 0);
        _ = sa_std_tls_shaped_close(@intCast(h));
        _ = server.wait() catch {};
    }
}

test "loopback: peer_cert_chain_json fields match openssl x509 output" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    const profile = try profileJson(allocator, .{ .ca_pem = pem });
    defer allocator.free(profile);
    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1" });
    defer _ = server.kill() catch {};
    const h = connectRetryProfile("localhost", port, profile);
    try testing.expect(h > 0);
    const handle: u64 = @intCast(h);

    var jh: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_peer_cert_chain_json(handle, &jh));
    defer _ = sa_std_tls_shaped_buffer_free(jh);
    const jptr = sa_std_tls_shaped_buffer_data(jh) orelse return error.MissingData;
    const jlen = sa_std_tls_shaped_buffer_len(jh);
    const json = jptr[0..@intCast(jlen)];

    try testing.expect(std.mem.indexOf(u8, json, "\"common_name\":\"localhost\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"subject\":\"CN = localhost\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"not_before\":") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"not_after\":") != null);

    // Cross-check serial + SHA-256 fingerprint against the openssl CLI.
    const fp = try opensslX509Field(allocator, setup.cert, "-fingerprint");
    defer allocator.free(fp);
    try testing.expect(std.mem.indexOf(u8, json, fp) != null);
    const serial = try opensslX509Field(allocator, setup.cert, "-serial");
    defer allocator.free(serial);
    // serial_hex is the bare hex; openssl prints it after '='.
    try testing.expect(std.mem.indexOf(u8, json, serial) != null);
    _ = sa_std_tls_shaped_close(handle);
    _ = server.wait() catch {};
}

test "loopback: TLS 1.2 session blob resumes (session_reused=true)" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);

    const profile1 = try profileJson(allocator, .{ .max_version = "1.2", .ca_file = setup.cert });
    defer allocator.free(profile1);
    // A single s_server process must serve both connections: TLS 1.2
    // session resumption needs the server-side session cache, which
    // lives inside the server process. Two independent s_server
    // processes can never resume each other's sessions (pure-openssl
    // control, OpenSSL 3.0.13: cross-process -sess_out/-sess_in gives
    // "New", same process with -naccept 2 gives "Reused"), so the
    // previous two-server topology made this test unpassable for any
    // client and the blob path was never actually exercised.
    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "2" });
    defer _ = server.kill() catch {};
    var blob: []u8 = undefined;
    {
        const h = connectRetryProfile("localhost", port, profile1);
        try testing.expect(h > 0);
        const handle: u64 = @intCast(h);
        var bh: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_session_blob(handle, &bh));
        defer _ = sa_std_tls_shaped_buffer_free(bh);
        const bptr = sa_std_tls_shaped_buffer_data(bh) orelse return error.MissingData;
        const blen = sa_std_tls_shaped_buffer_len(bh);
        try testing.expect(blen > 0);
        blob = try allocator.dupe(u8, bptr[0..@intCast(blen)]);
        _ = sa_std_tls_shaped_close(handle);
    }
    defer allocator.free(blob);

    const profile2 = try profileJson(allocator, .{ .max_version = "1.2", .ca_file = setup.cert, .session = blob });
    defer allocator.free(profile2);
    const h = connectRetryProfile("localhost", port, profile2);
    try testing.expect(h > 0);
    const handle: u64 = @intCast(h);
    var nbuf: [256]u8 = undefined;
    const negotiated = try negotiatedJson(handle, &nbuf);
    try testing.expect(std.mem.indexOf(u8, negotiated, "\"session_reused\":true") != null);
    _ = sa_std_tls_shaped_close(handle);
    _ = server.wait() catch {};
}

test "start_tls: shaped upgrade after plaintext preamble" {
    if (!sslAvailable()) return;
    if (comptime builtin.os.tag == .windows) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    const srv = @import("sa_tls_server.zig");
    var sup: u32 = 0;
    _ = srv.sa_std_tls_server_supported(&sup);
    if (sup == 0) return;
    var ctx: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), srv.sa_std_tls_server_ctx_create(setup.cert.ptr, setup.cert.len, setup.key.ptr, setup.key.len, &ctx));
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
            const s = @import("sa_tls_server.zig");
            var stream = a.lst.accept(sio.io()) catch return;
            defer stream.close(sio.io());
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
            a.accept_rc = s.sa_std_tls_server_accept(a.ctx, stream.socket.handle, &ssl);
            if (a.accept_rc != 0) return;
            var buf: [64]u8 = undefined;
            var n: u64 = 0;
            if (s.sa_std_tls_server_read(ssl, &buf, buf.len, &n) == 0) {
                _ = s.sa_std_tls_server_write(ssl, &buf, n, &n);
            }
            _ = s.sa_std_tls_server_close(ssl);
        }
    };
    var thread = try std.Thread.spawn(.{}, Runner.run, .{&arg});

    const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
    var plain = try addr.connect(sio.io(), .{ .mode = .stream });
    var wb: [64]u8 = undefined;
    var wr = plain.writer(sio.io(), &wb);
    try wr.interface.writeAll("STARTTLS\n");
    try wr.interface.flush();

    const profile = try profileJson(allocator, .{ .ca_pem = pem });
    defer allocator.free(profile);
    const host = "localhost";
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_start_tls(plain.socket.handle, host.ptr, host.len, profile.ptr, profile.len, &handle));
    try testing.expect(handle != 0);
    try shapedEcho(handle, "shaped-starttls-echo");
    _ = sa_std_tls_shaped_close(handle);
    thread.join();
    try testing.expectEqual(@as(i32, 0), arg.accept_rc);
}

test "loopback: client certificate (cert_file/key_file) satisfies a verifying server" {
    if (!sslAvailable()) return;
    const allocator = std.heap.page_allocator;
    var setup = try testDirSetup(allocator);
    defer setup.td.cleanup();
    defer allocator.free(setup.dirpath);
    defer allocator.free(setup.cert);
    defer allocator.free(setup.key);
    const pem = try sio.readFileAbsoluteAlloc(allocator, setup.cert, 1 << 20);
    defer allocator.free(pem);

    // Server demands a client cert chaining to the same self-signed cert
    // used as its CA file; the client presents that very cert.
    const port = try freePort();
    var server = try spawnServer(allocator, setup.cert, setup.key, port, &.{ "-naccept", "1", "-Verify", "1", "-verify_return_error", "-CAfile", setup.cert });
    defer _ = server.kill() catch {};
    const profile = try profileJson(allocator, .{ .max_version = "1.2", .ca_pem = pem, .cert_file = setup.cert, .key_file = setup.key });
    defer allocator.free(profile);
    const h = connectRetryProfile("localhost", port, profile);
    try testing.expect(h > 0);
    _ = sa_std_tls_shaped_close(@intCast(h));
    _ = server.wait() catch {};

    // Without the client certificate the same server refuses us.
    // Both halves pin TLS 1.2 on purpose: under TLS 1.3 the server can
    // only reject a missing client certificate after the client has
    // sent its Finished, so the refusal surfaces at the first read,
    // not during connect, and a connect-level refusal assertion can
    // never hold. Under TLS 1.2 the rejection happens inside the
    // handshake, which is the refusal this test asserts.
    const port2 = try freePort();
    var server2 = try spawnServer(allocator, setup.cert, setup.key, port2, &.{ "-naccept", "1", "-Verify", "1", "-verify_return_error", "-CAfile", setup.cert });
    defer _ = server2.kill() catch {};
    const profile2 = try profileJson(allocator, .{ .max_version = "1.2", .ca_pem = pem });
    defer allocator.free(profile2);
    const rc = connectRetryProfile("localhost", port2, profile2);
    try testing.expect(rc < 0);
    _ = server2.wait() catch {};
}

pub fn sslAvailable() bool {
    var flag: u32 = 0;
    if (sa_std_tls_shaped_supported(&flag) != SA_STD_OK) return false;
    return flag == 1;
}

pub fn makeCert(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
    const cert_path = try std.fs.path.join(allocator, &.{ dirpath, "cert.pem" });
    errdefer allocator.free(cert_path);
    const key_path = try std.fs.path.join(allocator, &.{ dirpath, "key.pem" });
    errdefer allocator.free(key_path);
    const args = [_][]const u8{
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "1", "-nodes", "-subj", "/CN=localhost",
    };
    var child = sio.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = try child.spawnAndWait();
    switch (term) {
        .exited => |code| if (code != 0) return error.CertFailed,
        else => return error.CertAbnormal,
    }
    return .{ .cert = cert_path, .key = key_path };
}

pub fn freePort() !u16 {
    const probe = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(sio.io(), .{ .reuse_address = true });
    defer listener.deinit(sio.io());
    return switch (listener.socket.address) {
        .ip4 => |a| a.port,
        .ip6 => |a| a.port,
    };
}

pub fn spawnServer(allocator: std.mem.Allocator, cert: []const u8, key: []const u8, port: u16, extra: []const []const u8) !sio.Child {
    const accept_arg = try std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
    defer allocator.free(accept_arg);
    var args = std.ArrayListUnmanaged([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "openssl", "s_server", "-accept", accept_arg, "-cert", cert, "-key", key, "-quiet" });
    try args.appendSlice(allocator, extra);
    var child = sio.Child.init(args.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    return child;
}

pub fn connectRetry(port: u16, profile: []const u8) i64 {
    const host = "localhost";
    var handle: u64 = 0;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_shaped_connect(host.ptr, host.len, port, profile.ptr, profile.len, &handle);
        if (rc == SA_STD_OK) return @intCast(handle);
        if (rc != SA_STD_ERR_IO) return rc;
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    return SA_STD_ERR_IO;
}

pub fn negotiatedJson(handle: u64, buf: []u8) ![]const u8 {
    var jh: u64 = 0;
    if (sa_std_tls_shaped_negotiated_json(handle, &jh) != SA_STD_OK) return error.NegotiatedFailed;
    defer _ = sa_std_tls_shaped_buffer_free(jh);
    const ptr = sa_std_tls_shaped_buffer_data(jh) orelse return error.MissingData;
    const len = sa_std_tls_shaped_buffer_len(jh);
    const n = @min(@as(usize, @intCast(len)), buf.len);
    @memcpy(buf[0..n], ptr[0..n]);
    return buf[0..n];
}

pub fn testDirSetup(allocator: std.mem.Allocator) !struct { td: testing.TmpDir, dirpath: []u8, cert: []u8, key: []u8 } {
    var td = testing.tmpDir(.{});
    errdefer td.cleanup();
    const tdir = sio.Dir{ .inner = td.dir };
    const dirpath = try tdir.realpathAlloc(allocator, ".");
    errdefer allocator.free(dirpath);
    const paths = try makeCert(allocator, dirpath);
    return .{ .td = td, .dirpath = dirpath, .cert = paths.cert, .key = paths.key };
}

pub fn profileJson(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

pub fn connectRetryProfile(host: []const u8, port: u16, profile: []const u8) i64 {
    var handle: u64 = 0;
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        const rc = sa_std_tls_shaped_connect(host.ptr, host.len, port, profile.ptr, profile.len, &handle);
        if (rc == SA_STD_OK) return @intCast(handle);
        if (rc != SA_STD_ERR_IO) return rc;
        std.Io.sleep(sio.io(), .fromMilliseconds(50), .awake) catch {};
    }
    return SA_STD_ERR_IO;
}

pub fn shapedEcho(handle: u64, msg: []const u8) !void {
    // Only for peers that echo at the TLS level (our own tls_server test
    // runner). s_server does NOT echo; see shapedServerRoundTrip.
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_write(handle, msg.ptr, msg.len, &written));
    try testing.expectEqual(@as(u64, msg.len), written);
    var buf: [128]u8 = undefined;
    var got: usize = 0;
    while (got < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_read(handle, buf[got..].ptr, buf.len - got, &n));
        if (n == 0) break;
        got += @intCast(n);
    }
    try testing.expectEqualStrings(msg, buf[0..got]);
}

pub fn shapedServerRoundTrip(allocator: std.mem.Allocator, server: *sio.Child, handle: u64) !void {
    const msg = "server-to-shaped\n";
    try server.stdin.?.writeAll(msg);
    var got: [64]u8 = undefined;
    var total: usize = 0;
    while (total < msg.len) {
        var n: u64 = 0;
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_read(handle, got[total..].ptr, got.len - total, &n));
        if (n == 0) break;
        total += @intCast(n);
    }
    try testing.expectEqualStrings(msg, got[0..total]);
    var written: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_write(handle, "shaped-to-server".ptr, 16, &written));
    try testing.expectEqual(@as(u64, 16), written);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_shaped_close(handle));
    const echoed = try server.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(echoed);
    try testing.expect(std.mem.indexOf(u8, echoed, "shaped-to-server") != null);
}

pub fn opensslX509Field(allocator: std.mem.Allocator, cert: []const u8, flag: []const u8) ![]u8 {
    const args: []const []const u8 = if (std.mem.eql(u8, flag, "-fingerprint"))
        &.{ "openssl", "x509", "-in", cert, "-noout", flag, "-sha256" }
    else
        &.{ "openssl", "x509", "-in", cert, "-noout", flag };
    var child = sio.Child.init(args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    const out = try child.stdout.?.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(out);
    const term = try child.wait();
    switch (term) {
        .exited => |code| if (code != 0) return error.OpensslX509Failed,
        else => return error.OpensslX509Failed,
    }
    const eq = std.mem.indexOfScalar(u8, out, '=') orelse return error.OpensslX509Failed;
    return allocator.dupe(u8, std.mem.trim(u8, out[eq + 1 ..], " \t\r\n"));
}
