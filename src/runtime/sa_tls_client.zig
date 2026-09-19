// TLS-client runtime binding for the sci/sa_std platform layer.
//
// Real TLS client handshake backed by Zig 0.14's std.crypto.tls.Client (pure
// Zig, no OpenSSL). std.crypto ships a TLS *client* only, which makes this the
// natural complement of sa_tls_server.zig (OpenSSL-backed TLS server).
//
// Trust model: the process-wide CA bundle singleton is populated from the OS
// trust store on first use (std.crypto.Certificate.Bundle.rescan, which covers
// Linux/macOS/Windows) and can be extended via sa_std_tls_client_add_ca_file
// (e.g. a private CA for loopback tests). There is deliberately NO
// verification-disabled path on this surface: `ca` is always `.bundle` and
// `host` is always `.explicit` (SNI + hostname check against the peer cert).
// The std ssl_key_log_file hook exists but is not exposed.
//
// Threading: the bundle singleton is guarded by a mutex. connect() dials TCP
// outside the lock (DNS can block), then holds the lock for the bundle
// snapshot + the full TLS handshake, because a copied Bundle shares the
// singleton's byte storage and add_ca_file could otherwise reallocate it out
// from under a live handshake.
//
// Status codes follow the sci convention: 0 = SA_STD_OK, negative = error.
// Certificate verification failures get SA_STD_ERR_TLS_VERIFY (-100).
//
// Handles are heap-allocated TlsClientHandle structs packed into a u64;
// 0 == invalid. close() consumes the handle (double-close is a caller bug,
// same as the other protocol sinks).
//
// Note: allow_truncation_attacks is set on every connection. Without it, a
// peer that closes TCP without a close_notify alert turns the final read into
// an error instead of a clean 0-byte EOF; HTTP-style users rely on the
// application layer (Content-Length / connection-close framing) for
// truncation safety anyway.

const std = @import("std");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;
const SA_STD_ERR_UNSUPPORTED: i32 = -1;
const SA_STD_ERR_IO: i32 = -5;
const SA_STD_ERR_TLS_VERIFY: i32 = -100;

const TlsClientHandle = struct {
    stream: std.net.Stream,
    client: std.crypto.tls.Client,
    host: []u8,
    port: u32,
};

// ---- process-wide CA bundle singleton --------------------------------------
// Populated once from the OS trust store (rescan), extended on demand by
// add_ca_file, never freed. Mirrors the SslApi singleton in sa_tls_server.zig.

var bundle_mutex = std.Thread.Mutex{};
var ca_bundle: ?std.crypto.Certificate.Bundle = null;

/// Caller must hold bundle_mutex. Returns a pointer to the live singleton so
/// adders mutate the shared store; readers take a value copy while the lock is
/// held and must finish using it before the lock is released by the owner.
fn ensureBundleLocked() anyerror!*std.crypto.Certificate.Bundle {
    if (ca_bundle == null) {
        var b: std.crypto.Certificate.Bundle = .{};
        errdefer b.deinit(std.heap.page_allocator);
        try b.rescan(std.heap.page_allocator);
        ca_bundle = b;
    }
    return &ca_bundle.?;
}

fn mapBundleErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        else => SA_STD_ERR_IO,
    };
}

/// Certificate-shaped failures -> SA_STD_ERR_TLS_VERIFY (-100); everything
/// else that can surface from a TLS operation -> IO (or NO_MEMORY).
fn mapTlsErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.CertificateHostMismatch,
        error.CertificateExpired,
        error.CertificateNotYetValid,
        error.CertificateTimeInvalid,
        error.CertificateIssuerMismatch,
        error.CertificateSignatureInvalid,
        error.CertificateSignatureInvalidLength,
        error.CertificateSignatureAlgorithmMismatch,
        error.CertificateSignatureAlgorithmUnsupported,
        error.CertificatePublicKeyInvalid,
        error.CertificateFieldHasInvalidLength,
        error.CertificateFieldHasWrongDataType,
        error.CertificateHasUnrecognizedObjectId,
        error.CertificateHasInvalidBitString,
        error.CertificateIssuerNotFound,
        error.TlsCertificateNotVerified,
        error.SignatureVerificationFailed,
        error.InvalidSignature,
        error.WeakPublicKey,
        => SA_STD_ERR_TLS_VERIFY,
        else => SA_STD_ERR_IO,
    };
}

fn mapDialErr(err: anyerror) i32 {
    return switch (err) {
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        else => SA_STD_ERR_IO,
    };
}

// ---- exported surface ------------------------------------------------------
// Handles are u64-packed heap pointers; 0 == invalid, matching the TCP and
// tls_server sinks.

pub export fn sa_std_tls_client_supported(out_supported: ?*u32) i32 {
    const slot = out_supported orelse return SA_STD_ERR_INVALID_ARGUMENT;
    // Pure-Zig backend (std.crypto.tls): no dlopen, no external library, so
    // the client is always available wherever sa_std itself builds.
    slot.* = 1;
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_connect(host_ptr: ?[*]const u8, host_len: u64, port: u32, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const host_slice = if (host_ptr) |p| p[0..host_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (host_slice.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (port == 0 or port > 65535) return SA_STD_ERR_INVALID_ARGUMENT;

    // 1. TCP dial first, outside the bundle mutex (DNS resolution can block).
    const stream = std.net.tcpConnectToHost(std.heap.page_allocator, host_slice, @intCast(port)) catch |err| {
        return mapDialErr(err);
    };
    errdefer stream.close();

    // 2. Owned copy of the hostname: Client.init only borrows it during the
    // call, but we keep it on the handle for status/debug.
    const host_owned = std.heap.page_allocator.dupe(u8, host_slice) catch return SA_STD_ERR_NO_MEMORY;
    errdefer std.heap.page_allocator.free(host_owned);

    // 3. Snapshot the bundle and run the blocking TLS handshake under the
    // mutex: the copied Bundle shares the singleton's byte storage, and this
    // keeps add_ca_file from reallocating it mid-handshake.
    bundle_mutex.lock();
    defer bundle_mutex.unlock();
    const bundle_copy = (ensureBundleLocked() catch |err| return mapBundleErr(err)).*;
    var client = std.crypto.tls.Client.init(stream, .{
        .host = .{ .explicit = host_owned },
        .ca = .{ .bundle = bundle_copy },
    }) catch |err| {
        return mapTlsErr(err);
    };
    client.allow_truncation_attacks = true;

    const h = std.heap.page_allocator.create(TlsClientHandle) catch {
        // Extremely unlikely, but don't leak the live TLS session: try a
        // clean close_notify before dropping the socket. (host_owned is freed
        // by the errdefer above.)
        _ = client.writeEnd(stream, "", true) catch 0;
        stream.close();
        return SA_STD_ERR_NO_MEMORY;
    };
    h.* = .{
        .stream = stream,
        .client = client,
        .host = host_owned,
        .port = port,
    };
    slot.* = @intFromPtr(h);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_add_ca_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = if (path_ptr) |p| p[0..path_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (path.len == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    // addCertsFromFilePathAbsolute asserts an absolute path; reject early with
    // a contract error instead of tripping the assert.
    if (!std.fs.path.isAbsolute(path)) return SA_STD_ERR_INVALID_ARGUMENT;
    bundle_mutex.lock();
    defer bundle_mutex.unlock();
    const b = ensureBundleLocked() catch |err| return mapBundleErr(err);
    b.addCertsFromFilePathAbsolute(std.heap.page_allocator, path) catch |err| {
        return switch (err) {
            error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
            else => SA_STD_ERR_IO,
        };
    };
    return SA_STD_OK;
}

fn handleFromU64(handle: u64) *TlsClientHandle {
    // Heap pointers from page_allocator are 16-byte aligned; alignCast keeps
    // this sound on targets (aarch64) where @ptrFromInt is stricter.
    const p: *TlsClientHandle = @ptrFromInt(handle);
    return @alignCast(p);
}

pub export fn sa_std_tls_client_read(handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const slot = out_read orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const h = handleFromU64(handle);
    const n = h.client.read(h.stream, buf[0..@min(cap, @as(u64, @intCast(std.math.maxInt(c_int))))]) catch |err| {
        return mapTlsErr(err);
    };
    slot.* = @intCast(n);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_write(handle: u64, buf: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const slot = out_written orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const src = buf orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const h = handleFromU64(handle);
    const n = h.client.write(h.stream, src[0..@min(len, @as(u64, @intCast(std.math.maxInt(c_int))))]) catch |err| {
        return mapTlsErr(err);
    };
    slot.* = @intCast(n);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_close(handle: u64) i32 {
    if (handle == 0) return SA_STD_OK;
    const h = handleFromU64(handle);
    // Best-effort close_notify so the peer sees a clean shutdown; the peer
    // may already be gone, hence catch {}.
    _ = h.client.writeEnd(h.stream, "", true) catch 0;
    h.stream.close();
    std.heap.page_allocator.free(h.host);
    std.heap.page_allocator.destroy(h);
    return SA_STD_OK;
}

pub export fn sa_std_tls_client_status_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var buffer: [192]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"module\":\"tls_client\",\"backend\":\"std.crypto.tls\",\"supported\":true,\"protocolMachine\":true}}", .{}) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

// ---- buffer handle registry (same shape as sa_tls_server.zig) --------------

var string_registry_mutex = std.Thread.Mutex{};
var string_registry = std.ArrayListUnmanaged(?[]u8){};

fn registerString(bytes: []u8, slot: *u64) i32 {
    string_registry_mutex.lock();
    defer string_registry_mutex.unlock();
    var i: usize = 0;
    while (i < string_registry.items.len) : (i += 1) {
        if (string_registry.items[i] == null) {
            string_registry.items[i] = bytes;
            slot.* = @intCast(i + 1);
            return SA_STD_OK;
        }
    }
    string_registry.append(std.heap.page_allocator, bytes) catch return SA_STD_ERR_NO_MEMORY;
    slot.* = @intCast(string_registry.items.len);
    return SA_STD_OK;
}

fn takeString(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    string_registry_mutex.lock();
    defer string_registry_mutex.unlock();
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return null;
    return string_registry.items[idx];
}

pub export fn sa_std_tls_client_buffer_data(handle: u64) ?[*]const u8 {
    const s = takeString(handle) orelse return null;
    return s.ptr;
}

pub export fn sa_std_tls_client_buffer_len(handle: u64) u64 {
    const s = takeString(handle) orelse return 0;
    return @intCast(s.len);
}

pub export fn sa_std_tls_client_buffer_free(handle: u64) i32 {
    string_registry_mutex.lock();
    defer string_registry_mutex.unlock();
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= string_registry.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = string_registry.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    string_registry.items[idx] = null;
    std.heap.page_allocator.free(entry);
    return SA_STD_OK;
}

// ============================================================================
// Unit tests.
// ============================================================================

const testing = std.testing;

test "supported is always 1: pure-Zig backend, no dlopen" {
    var flag: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_supported(&flag));
    try testing.expectEqual(@as(u32, 1), flag);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_supported(null));
}

test "connect rejects bad arguments without touching the network" {
    var h: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect(null, 0, 443, &h));
    try testing.expectEqual(@as(u64, 0), h);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 0, 443, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 11, 0, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 11, 65536, &h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_connect("example.com".ptr, 11, 443, null));
    try testing.expectEqual(@as(u64, 0), h);
}

test "read/write/close contract on the invalid (0) handle" {
    var buf: [4]u8 = undefined;
    var n: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_read(0, &buf, buf.len, &n));
    try testing.expectEqual(@as(u64, 0), n);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_write(0, "x".ptr, 1, &n));
    try testing.expectEqual(@as(u64, 0), n);
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_read(0, null, 4, &n));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_read(0, &buf, 4, null));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_close(0));
}

test "add_ca_file rejects bad paths" {
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_add_ca_file(null, 0));
    const empty = "";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_add_ca_file(empty.ptr, 0));
    const rel = "relative/ca.pem";
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_add_ca_file(rel.ptr, rel.len));
    const missing = "/nonexistent-dir-xyz/ca.pem";
    try testing.expectEqual(@as(i32, SA_STD_ERR_IO), sa_std_tls_client_add_ca_file(missing.ptr, missing.len));
}

test "status json + buffer trio round-trips" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_status_json(&handle));
    try testing.expect(handle != 0);
    const ptr = sa_std_tls_client_buffer_data(handle) orelse return error.MissingData;
    const len = sa_std_tls_client_buffer_len(handle);
    try testing.expect(len != 0);
    const json = ptr[0..@as(usize, @intCast(len))];
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"tls_client\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"std.crypto.tls\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"supported\":true") != null);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_buffer_free(handle));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_tls_client_buffer_free(handle));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_tls_client_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_tls_client_buffer_len(0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_buffer_free(0));
}

test "export invariants: err codes negative, OK is 0" {
    try testing.expectEqual(@as(i32, 0), SA_STD_OK);
    try testing.expect(SA_STD_ERR_NO_MEMORY < 0);
    try testing.expect(SA_STD_ERR_INVALID_ARGUMENT < 0);
    try testing.expect(SA_STD_ERR_UNSUPPORTED < 0);
    try testing.expect(SA_STD_ERR_IO < 0);
    try testing.expectEqual(@as(i32, -100), SA_STD_ERR_TLS_VERIFY);
}

fn makeSelfSignedCert(allocator: std.mem.Allocator, dirpath: []const u8) !struct { cert: []u8, key: []u8 } {
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
    var child = std.process.Child.init(&args, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return error.OpensslSpawnFailed;
    switch (term) {
        .Exited => |code| if (code != 0) return error.OpensslCertFailed,
        else => return error.OpensslCertAbnormal,
    }
    return .{ .cert = cert_path, .key = key_path };
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
    const dirpath = try td.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dirpath);
    const paths = try makeSelfSignedCert(allocator, dirpath);
    defer allocator.free(paths.cert);
    defer allocator.free(paths.key);

    // Pin the self-signed CA into the singleton bundle (real verification).
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_tls_client_add_ca_file(paths.cert.ptr, paths.cert.len));

    // Grab a free loopback port, then hand it to s_server.
    const probe = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try probe.listen(.{ .reuse_address = true });
    const port = listener.listen_address.getPort();
    listener.deinit();

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
    var server = std.process.Child.init(&server_args, allocator);
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
        std.time.sleep(50 * std.time.ns_per_ms);
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
        .Exited => |code| try testing.expectEqual(@as(u8, 0), code),
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
